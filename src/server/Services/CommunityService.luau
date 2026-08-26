--!strict
--[[
	CommunityService — the group join reward. (C39, §9.2)

	Milestone: M10
	Spec: docs/MVP-SPEC.md §9.2

	WHY A GROUP IS WORTH 250 COINS. The competitor had 1.43M unique players, no group and no social
	links, so every update they shipped went out into silence — see Appendix C. A group member is
	someone you can notify on every update for the rest of the game's life, free, forever. The reward
	is the cheapest acquisition cost in the project and it is paid once per player.

	WHAT IT OWNS. Exactly one remote handler, `RequestClaimGroupReward`, built to the same shape as
	`DailyService`: the request lands here and is rate-limited here; the profile is written in
	`ProgressionService` through a guarded setter. That split is what keeps `ProgressionService` free
	of `OnServerEvent` handlers, which is the property its header protects.

	IT DOES NOTHING UNTIL A HUMAN CREATES THE GROUP. `Config.Community.GroupId` ships as 0 and C36 is
	the 🧍 chunk that fills it — a Roblox group, the social links, and private servers, in one sitting.
	A zero id refuses every claim rather than erroring, and `Start` warns once so the refusal has a
	visible cause instead of reading as a broken button.

	SECRECY: NOTHING IN THIS FILE KNOWS WHAT A ROLE IS. Group membership is public information Roblox
	already publishes on every player's profile page, the claim is answered to exactly one player, and
	there is no broadcast anywhere in it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local AntiCheatService = require(script.Parent.AntiCheatService)
local ProgressionService = require(script.Parent.ProgressionService)

local CommunityService = {}

--[[
	`userId -> os.clock()` OF THE LAST "NOT A MEMBER" ANSWER FROM ROBLOX.

	NEGATIVE ANSWERS ONLY. A positive answer is spent on the claim in the same call and never needs
	remembering; a negative one is what a non-member's repeated press produces, and each of those is a
	web call against a quota shared by everyone on this server. Caching it turns a held button into one
	call per `GroupCheckNegativeCacheSeconds` instead of one per allowed press.

	`os.clock()` RATHER THAN `os.time()`, deliberately: this is a "how long since" measurement and
	nothing else, so it wants a monotonic clock. `os.time()` can step backwards on an NTP correction,
	which would extend a cached refusal by however far the clock moved.

	IT CANNOT WRONGLY GRANT. The cache only ever causes a REFUSAL to be repeated without asking; every
	payment still goes through a fresh `IsInGroupAsync` and `ClaimGroupReward`.
]]
local lastRefusedAt: { [number]: number } = {}

--[[
	THE CLAIM, AND THE ORDER OF ITS FIVE STEPS IS THE CORRECTNESS ARGUMENT:

	  1. rate limit    — at the connect site, before anything is read
	  2. profile       — no profile, no claim; a reward that cannot be saved must not be paid
	  3. group id set  — C36 has not been done yet, so refuse rather than ask Roblox about group 0
	  4. IS IN GROUP   — a Roblox web call, on the SERVER, about the id in Config
	  5. CLAIM then PAY — `ClaimGroupReward` test-and-sets, and coins move only on its `true`

	STEP 5 IS THE ONE THAT MATTERS. Claiming before paying means a crash between them costs the player
	250 coins — a support message. Paying before claiming means every press pays until the write
	lands, which is an economy. `DailyService` makes the same trade in the same direction and for the
	same reason.

	STEP 4 YIELDS, and two presses put two threads across that yield. Neither can double-pay, because
	the test and the set happen together inside `ClaimGroupReward` without yielding — see its header.
]]
local function onClaim(player: Player)
	local data = ProgressionService.GetProfile(player)

	--[[
		A DataStore outage or a mid-load join lands here. Refusing is the honest answer: this reward is
		claimable once ever, so paying it against a profile that cannot record the claim would either
		vanish at the next login or pay again — and the client is told nothing, because there is
		nothing true to tell it yet.
	]]
	if data == nil then
		return
	end

	-- Already taken. Checked here as well as inside the setter so the ordinary case costs no web call
	-- at all — a player who re-opens the lobby panel should not spend group-API quota to be told no.
	if data.GroupRewardClaimed then
		return
	end

	local groupId = Config.Community.GroupId

	if groupId <= 0 then
		return
	end

	-- A recent refusal stands without re-asking Roblox. See `lastRefusedAt`.
	local refusedAt = lastRefusedAt[player.UserId]

	if
		refusedAt ~= nil
		and os.clock() - refusedAt < Config.Community.GroupCheckNegativeCacheSeconds
	then
		return
	end

	--[[
		`IsInGroupAsync`, NOT `IsInGroup`. §9.2 names the latter and the analyzer rejects it as
		deprecated — measured here, not assumed. The old call blocked on a cached membership list; the
		Async form is the supported one and is explicit about being a web request, which is what the
		budget and the `pcall` below are both sized for.

		IT IS A WEB CALL AND IT FAILS IN NORMAL OPERATION. A Roblox outage, a throttle, a group made
		private — all of them throw, and an unprotected throw here would unwind the remote handler and
		leave the player with a button that does nothing and no warning anywhere.

		A FAILED CHECK IS NOT A MEMBERSHIP. `inGroup` stays false on an error, so the reward is
		withheld and the player can press again later — the opposite direction would pay everyone
		during an outage, permanently, with the claim flag set so it could never be corrected.
	]]
	local ok, inGroup = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)

	if not ok then
		warn(`[Community] could not check group membership for {player.Name}: {inGroup}`)

		return
	end

	if not inGroup then
		lastRefusedAt[player.UserId] = os.clock()

		return
	end

	if not ProgressionService.ClaimGroupReward(player) then
		-- Either the flag was already set by a racing press, or the profile is read-only. Both mean
		-- nothing is paid, and both are already explained above.
		return
	end

	ProgressionService.Award(player, 0, Config.Community.GroupJoinRewardCoins, "group-join")
	ProgressionService.PushProfile(player, nil)

	if Config.Debug.VerboseLogging then
		print(
			`[Community] {player.Name} claimed the group reward `
				.. `(+{Config.Community.GroupJoinRewardCoins} coins)`
		)
	end
end

function CommunityService.Init()
	table.clear(lastRefusedAt)
end

function CommunityService.Start()
	--[[
		ONE WARN AT STARTUP rather than one per refused press. Without it a lobby panel that pays
		nothing looks like a bug in the panel, and the actual cause — C36's group has not been created
		— is a zero in a config file nobody is looking at.
	]]
	if Config.Community.GroupId <= 0 then
		warn(
			"[Community] Config.Community.GroupId is 0 — the group join reward will refuse every "
				.. "claim. Create the Roblox group and set the id (C36)."
		)
	end

	--[[
		THE LIMITER IS AT THE CONNECT SITE, for the two reasons `DailyService` gives: `check:ratelimit`
		reads a character window after `.OnServerEvent:Connect(`, and it puts the budget's name beside
		the remote's name where a mismatch is one line to see.

		This handler is the only one in the game that makes a Roblox web call, which is why its budget
		is the tightest in `Config.AntiCheat.Budgets`.
	]]
	Remotes.Get("RequestClaimGroupReward").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestClaimGroupReward") then
			return
		end

		onClaim(player)
	end)

	--[[
		THE ONE PIECE OF PER-PLAYER STATE IS THE NEGATIVE CACHE, and it is cleared here so a userId
		cannot accumulate across a long-lived server. It holds no decision — every payment still costs
		a fresh membership check — so dropping it early only ever means asking Roblox once more.
	]]
	Players.PlayerRemoving:Connect(function(player)
		lastRefusedAt[player.UserId] = nil
	end)
end

return CommunityService
