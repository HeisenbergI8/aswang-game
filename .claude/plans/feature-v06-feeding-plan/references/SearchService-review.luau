--!strict
--[[
	REVIEW — src/server/Services/SearchService.luau (675 lines)

	NOT a file V06 changes. It is read because it is the ONLY existing implementation in this repo of
	"a timed hold you must stand still for, that can be interrupted six ways" — which is exactly what
	a feed is with a body in place of a container. The feed lifecycle is this shape, deliberately.
]]

-- src/server/Services/SearchService.luau:263-282
--   -- The hold. ONE AUTHORITY AND ONE REVERSE INDEX.
--   -- `holds` is the truth… `occupied` exists only so that "is anybody on this container" is a
--   -- lookup rather than a scan… If the two ever disagree, `holds` wins — but the point of
--   -- confining the writes to two functions is that they cannot.
type Hold = {
	ContainerIndex: number,
	Name: string,
	EndsAt: number,
}
-- NOTE  V06 DELIBERATELY DOES NOT COPY THE TWO-TABLE PART. A feed needs no reverse index — nothing
--       asks "is anybody feeding on this body" — so all three facts go on the existing
--       `monsters[userId]` entry and there is nothing that can disagree.
-- IMPORTANT  What V06 DOES copy is `EndsAt` as an `os.clock()` deadline read by a tick, rather than a
--       `task.delay`. A delayed callback knows only that the duration passed; it cannot notice that
--       the player walked away at second two, and §4.3's whole point is "interruptible".

-- src/server/Services/SearchService.luau:355-390
--   THE ONLY WAY A HOLD ENDS. Every one of the six paths goes through here, and that is the entire
--   design of this section: a release path that clears `holds` without clearing `occupied` locks a
--   container for the rest of the round, with no symptom except that nobody can search it.
--
--   `verdict` is nil when the caller has already sent its own message — `completeHold` sends
--   SEARCH_OK with the item and must not be followed by an INTERRUPTED.
local function releaseHold(userId: number, verdict: Types.SearchVerdict?)
	local hold = holds[userId]

	if hold == nil then
		return
	end
-- IMPORTANT  `endFeed` IS THIS FUNCTION'S CONTRACT VERBATIM, including the nil-verdict rule and the
--       safe-to-call-when-not-holding early return. Copied rather than reinvented because the failure
--       it prevents — two contradictory messages for one ending — is the same failure.
-- IMPORTANT  The stakes are HIGHER for a feed. A search hold left dangling locks a container; a feed
--       left dangling strands `WalkSpeed = 0` on a living character, which is a map-wide role brand.
--       "Every path goes through one function" is the same discipline protecting a bigger thing.

-- src/server/Services/SearchService.luau:448-465
--   Resolve the part a hold is on, and how far the searcher has strayed from it. Returns nil when the
--   container has stopped existing — a map author deleting a tagged part mid-round is a real thing and
--   it must release the hold rather than error inside the tick.
local function holdDistance(player: Player, hold: Hold): number?
	local container: BasePart? = containersByName[hold.Name]
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if container == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end

	return (container.Position - root.Position).Magnitude
end
-- NOTE  `feedDistance` is this with a corpse Model instead of a container BasePart, resolved through
--       `MonsterService.rootOf` (which already does the FindFirstChild + IsA dance).
-- IMPORTANT  THE nil CASE IS THE ONE THAT MATTERS. V06 maps nil onto `math.huge` at the call site, so
--       "we could not measure" and "too far" resolve to the same OUT_OF_RANGE inside `FeedRules` —
--       one refusal instead of two, and no way for a missing body to read as distance zero.

-- src/server/Services/SearchService.luau:467-500
--   THE TICK. Paths 2 (moved out of range) and 3 (no longer ALIVE), plus path 1's trigger.
--
--   Assigning nil to an existing key during a generalised-for traversal is defined behaviour in Luau,
--   so releasing a hold from inside this loop is safe.
local function searchTick()
	for userId, hold in holds do
		local player = Players:GetPlayerByUserId(userId)

		if player == nil then
			releaseHold(userId, nil)
			continue
		end

		if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
			releaseHold(userId, "SEARCH_INTERRUPTED")
			continue
		end

		local distance = holdDistance(player, hold)

		if distance == nil or distance > Config.Search.RangeStuds then
			releaseHold(userId, "SEARCH_INTERRUPTED")
			continue
		end

		if now >= hold.EndsAt then
			completeHold(player, hold)
		end
	end
end
-- IMPORTANT  THIS LOOP IS THE SERVER'S AUTHORITY OVER A HOLD, AND SEARCHING HAS NO MOVEMENT LOCK AT
--       ALL — the leash IS the mechanic. V06 adds a lock on top for feel (§4.3 says "locked in
--       place") but the authority is still this: a client owns its own character's physics, so
--       `WalkSpeed = 0` is an affordance and the distance test is the guarantee.
-- NOTE  `feedTick` iterates `monsters` and never removes a KEY — `endFeed` clears three fields on an
--       entry that stays. Strictly safer than the precedent, and worth saying so rather than
--       inheriting the caveat unread.
-- NOTE  The ordering here is the one V06 copies: gone-player backstop, liveness, leash, then the
--       deadline. Completion is checked LAST, so an interruption in the same tick as the deadline
--       wins. That is the direction §4.3 wants.

-- src/server/Services/SearchService.luau:667-672
	task.spawn(function()
		while true do
			searchTick()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
-- IMPORTANT  THE EXACT WAIVER V06 REUSES, WORDING INCLUDED. `check:config` flags `0.25` in
--       `src/server/`; the waiver has a mandatory reason so a deliberate exception shows up in a diff.
-- NOTE  Runs unconditionally in every phase. The tick skips entries with nothing to do, and gating
--       the loop on the phase would be a second copy of the phase rule with nothing to gain.

-- src/server/Services/SearchService.luau:76
SearchService.ItemFound = Instance.new("BindableEvent")
-- IMPORTANT  THE SHAPE OF `MonsterService.FeedCompleted`, AND THE PRECEDENT FOR SHIPPING A SEAM WITH
--       NO SUBSCRIBER. V03 declared this and connected nothing; V08 connects it. The comment at line
--       438 — "V08 connects here. V03 connects nothing" — is the convention V06 copies for V07.
-- NOTE  A BindableEvent, so it never leaves the server. `FeedCompleted` carries a Player and nothing
--       else, for the same reason `ItemFound` carries a Player and an item: seams answer questions,
--       they do not volunteer state.

-- src/server/Services/SearchService.luau:306-317
local function sendUpdate(player: Player, verdict: Types.SearchVerdict, found: Types.ItemType?)
	local payload: Types.SearchUpdatePayload = {
		Verdict = verdict,
		-- Only a live hold has a duration. Every refusal and every ending sends 0, so a client cannot
		-- read a timing difference off a refusal.
		HoldSeconds = if verdict == "SEARCH_STARTED" then Config.Search.SearchTime else 0,
		Found = found,
	}

	updateRemote:FireClient(player, payload)
end
-- IMPORTANT  `sendFeedUpdate` IS THIS FUNCTION. The typed local is not style: `FireClient` takes
--       `...any`, so an inline literal is checked against nothing and a typo'd field ships. It is
--       also what `check-secrecy.mjs` resolves the payload back to when it scans the fire site — the
--       check was repaired after an audit found that a typed local reduced its scan to seven
--       characters.
-- NOTE  The HoldSeconds-is-zero-on-every-ending rule is copied verbatim into `FeedUpdatePayload`.
