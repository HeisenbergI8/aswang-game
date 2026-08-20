--!strict
--[[
	DailyService — the login streak's one button. (C33, §7)

	WHAT IT OWNS. Exactly one remote handler: `RequestClaimDaily`. It decides nothing itself —
	`shared/pure/DailyStreak` decides, `ProgressionService` writes, and this file is the twelve lines
	of Roblox in between.

	WHY IT IS NOT A FUNCTION INSIDE `ProgressionService`. That file's header carries a property worth
	keeping: "nothing here takes a client value — §6.6's fourth rule ... there is no `OnServerEvent`
	handler in this file, which is why `check:ratelimit` has nothing to say about it." An
	`OnServerEvent` connection in there would end that property for the sake of saving a file, and the
	property is what makes the profile's write paths auditable in one read.

	So the split is: the request lands HERE and is rate-limited HERE; the profile is written THERE,
	through the same guarded setters every other caller uses.

	§7 CALLS THIS "THE SINGLE HIGHEST-ROI RETENTION FEATURE YOU CAN BUILD", and C33's brief adds why
	it deserves a pure module and a suite: "timezone bugs here are silent and permanent, and a streak
	that resets wrongly is worse than no streak at all." None of that reasoning is repeated here; it is
	in `shared/pure/DailyStreak`'s header, next to the code it governs.

	SECRECY: NOTHING IN THIS FILE KNOWS WHAT A ROLE IS. A streak is one player's own history, the
	claim is fired by and answered to exactly one player, and no other player appears in any signature.
	The nearest thing to a leak would be a claim ANNOUNCED to the server at large, and there is no
	broadcast here — the only send is `ProgressionService.PushProfile`, which is FireClient to the
	claimant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyStreak = require(Shared.pure.DailyStreak)
local Remotes = require(Shared.Remotes)
local AntiCheatService = require(script.Parent.AntiCheatService)
local ProgressionService = require(script.Parent.ProgressionService)

local DailyService = {}

local function params(): DailyStreak.Params
	return { Rewards = Config.Daily.Rewards }
end

--[[
	THE CLAIM. No arguments — see `Remotes.luau`'s entry for why the absent timestamp is the design.

	THE ORDER OF THE FOUR STEPS IS THE WHOLE CORRECTNESS ARGUMENT, and it is the order that survives a
	failure at any point:

	  1. rate limit          — before anything is read, so a firehose costs one table lookup
	  2. evaluate            — a pure decision over the stored profile and the SERVER's clock
	  3. stamp the day       — `SetDaily`, and it must succeed before anything is paid
	  4. pay                 — `Award`, only then

	Stamping BEFORE paying is what makes a double claim impossible: if the process dies between 3 and
	4 the player loses one day's reward, and if it were the other way round they would be paid again
	on every button press until the write landed. Losing a reward is a support message; paying it
	repeatedly is an economy.

	`os.time()` IS THE SERVER'S CLOCK AND IS NEVER A CLIENT'S. It is also the only input here the
	client could have wanted to name, which is why the remote carries no arguments at all.
]]
local function onClaim(player: Player)
	local data = ProgressionService.GetProfile(player)

	--[[
		NO PROFILE, NO CLAIM, AND NO SILENT SUCCESS. A DataStore outage or a mid-load join both land
		here, and the honest answer is to do nothing — paying a streak that cannot be saved advances a
		counter the player will lose. `ProgressionService.IsReadOnly` is checked by the setters
		themselves, so a latched profile fails at step 3 and never reaches step 4.
	]]
	if data == nil then
		return
	end

	local result = DailyStreak.evaluate({
		LastClaimUTC = data.Daily.LastClaimUTC,
		Streak = data.Daily.Streak,
		NowUTC = os.time(),
	}, params())

	if result.Outcome ~= "CLAIMED" then
		--[[
			A REFUSAL STILL PUSHES. The button is drawn from the last snapshot, so a client whose view
			has drifted — a session left open across a UTC midnight, a claim already taken on another
			server — would otherwise keep offering a claim the server keeps refusing, with nothing on
			screen changing. One push re-synchronises it.
		]]
		ProgressionService.PushProfile(player, nil)

		if Config.Debug.VerboseLogging then
			print(`[Daily] {player.Name}: {result.Outcome}`)
		end

		return
	end

	if not ProgressionService.SetDaily(player, result.ClaimedAtUTC, result.Streak) then
		-- The stamp did not land, so nothing is paid. See the ordering note above.
		warn(`[Daily] could not stamp {player.Name}'s claim — nothing paid`)

		return
	end

	ProgressionService.Award(player, result.RewardXP, result.RewardCoins, "daily")
	ProgressionService.PushProfile(player, nil)

	if Config.Debug.VerboseLogging then
		print(
			`[Daily] {player.Name} claimed day {result.CycleDay} of a {result.Streak}-day streak `
				.. `(+{result.RewardXP} xp, +{result.RewardCoins} coins)`
		)
	end
end

function DailyService.Init() end

function DailyService.Start()
	--[[
		THE LIMITER IS AT THE CONNECT SITE, not inside `onClaim`, and that placement is deliberate on
		two counts. `check:ratelimit` reads a character window AFTER `.OnServerEvent:Connect(` and a
		handler limited somewhere else reads to it as unguarded — the same note QuickChatService and
		GhostService carry over their handlers. And it puts the budget's NAME beside the remote's name,
		where a mismatch between `Remotes.EVENTS_UP` and `Config.AntiCheat.Budgets` is one line to see
		rather than two files to compare.
	]]
	Remotes.Get("RequestClaimDaily").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestClaimDaily") then
			return
		end

		onClaim(player)
	end)

	--[[
		ONE CONNECTION, AND THE TWO THAT ARE MISSING ARE DELIBERATE.

		No `PlayerAdded`: the join push belongs to `ProgressionService.startSession`, which is the only
		place that knows when the profile has finished loading. A second connection here would race it
		and push a snapshot built from a nil profile.

		No `PlayerRemoving`: there is no per-player state in this file to clean up. Every decision is
		recomputed from the profile and the server clock on each call, which is what makes a claim
		correct on a player's second server as well as their first.
	]]
end

return DailyService
