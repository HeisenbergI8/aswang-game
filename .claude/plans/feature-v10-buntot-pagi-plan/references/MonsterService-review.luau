--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (3343 lines)
	Read for V10 planning. This service already contains two seams built FOR this chunk and names
	them by number. It also contains the function whose behaviour invalidates the build plan's V10
	signature.
]]

-- src/server/Services/MonsterService.luau:48-64 — the header's list of seams
--[[
	THE FIVE SEAMS THE NEXT THREE CHUNKS CALL, so nobody has to guess which one to reach for:
	  · `IsExposed(userId) -> boolean` — V08's strike gate, half one.
	  · `IsWeakened(userId) -> boolean` — V08's strike gate, half two. §4.6: the buntot pagi kills an
	    Aswang that is BOTH. AND them with `RoundService.GetAswangUserId()` on the server and hand a
	    single boolean to the pure module, exactly as `ItemService` does for `IsTransformed`.

	NONE OF THE FOUR ENUMERATES, and none returns the health value. Every one takes a UserId the
	caller already holds and answers false for a player with no monster state — which is every
	survivor, every round, so none of them is usable as a probe.
]]
-- IMPORTANT THIS IS THE CONTRACT V10 IMPLEMENTS, AND IT IS ALREADY WRITTEN. The plan follows it
--           exactly: the role is resolved once in `ResolveStrikeTarget`, the two booleans come out
--           of these functions, and `pure/StrikeValidation` never sees a role or a health value.
-- IMPORTANT "none returns the health value" is the reason the plan REFUSES to add a `GetHealth`
--           seam to satisfy the build plan's literal `monsterHealth` parameter. See Follow Up 1.

-- src/server/Services/MonsterService.luau:429-437 — the finding that changes the signature
--[[
	`Enums.MonsterState` has five members and this function produces three. ...
	  · `EXPOSED` IS A LATCH, NOT AN ACTIVITY. §4.6's reveal coexists with whatever form the monster
	    is in — a salted Aswang is Exposed AND still an Aswang. Returning EXPOSED here would shadow
	    TRANSFORMED ...
]]
local function monsterStateOf(monster: MonsterState): Types.MonsterState
	if monster.Camouflaged and monster.Transformed then
		return Enums.MonsterState.Camouflaged
	end
	if monster.Feeding and monster.Transformed then
		return Enums.MonsterState.Feeding
	end
	if monster.Transformed then
		return Enums.MonsterState.Transformed
	end
	return Enums.MonsterState.Normal
end
-- IMPORTANT FOUR PRODUCERS, NONE OF THEM `EXPOSED`. A `StrikeValidation` gating on
--           `monsterState == "EXPOSED"` would therefore refuse EVERY cell of the grid, forever, and
--           the symptom would be that the second win condition silently does not exist — §6.5
--           invariant 1's exact failure mode. This is the single most important thing in this
--           review and it is why the plan's module takes `TargetExposed: boolean`.
-- NOTE      It is also why `TargetState` is carried but is NOT a gate: a Weakened, Exposed Aswang
--           dies whether this function said TRANSFORMED, CAMOUFLAGED or FEEDING.

-- src/server/Services/MonsterService.luau:816-836 — the invariant `StrikeDown` must not break
--[[
	THE BOOLEAN AND THE INSTANCE ALWAYS DIE TOGETHER. A `clearExposed` that destroyed the glow and
	left `Exposed = true` would leave V08 able to kill a monster nobody can see glowing ...
]]
local function clearExposed(userId: number) end
-- IMPORTANT `StrikeDown` MUST CALL THIS BEFORE THE DEATH. A Highlight orphaned onto the struck
--           Aswang's body is a permanent, map-wide, remote-free answer to "which body was the
--           monster", readable after the round by anyone who did not watch it die. That is C04's
--           bug shape exactly — a revert that shipped a brand with `verify` and `check:secrecy`
--           green over it — and only `exploit-auditor` found it that time.

-- src/server/Services/MonsterService.luau:1931-1990 — the raycast V10 must reuse, not reimplement
local function hasLineOfSight(killerRoot: BasePart, targetRoot: BasePart): boolean
	if smokeBlocksSegment(killerRoot.Position, targetRoot.Position) then
		return false
	end
	-- ... RaycastParams excluding: both characters, the corpses folder, the husks folder
end
-- IMPORTANT FOUR EXCLUSIONS, EACH ONE A RULE SOMEBODY WAS BITTEN BY: a body is not cover; two alts
--           in a doorway do not make a safe room; smoke breaks LOS symmetrically in both
--           directions. A second copy in `ItemService` starts correct and drifts, on the surface
--           where drift is an exploit. This is why the plan puts `ResolveStrikeTarget` in THIS file
--           rather than resolving the target where the remote lives.
-- NOTE      It is a file-local, so V10's resolver must be declared below line 1931. The plan places
--           it near `IsExposed` (~3126), which is well clear.

-- src/server/Services/MonsterService.luau:2664-2678 — the kill handler's cheap-checks-first ordering
	-- LAST, because it is the only check that touches the physics engine. Everything cheap has already
	-- said yes, so the expensive one runs at most once per legitimate attempt — which is what makes an
	-- unauthorised spam of this remote cost the server nothing beyond a table lookup.
	if not hasLineOfSight(killerRoot, targetRoot) then
		return
	end
-- NOTE `ResolveStrikeTarget` makes the same trade: the distance test gates the raycast, so spamming
--      `RequestStrike` costs a subtraction. This is why the range is tested twice — once in the
--      service to gate the ray, once in the pure module because that is what the Lune grid proves.

-- src/server/Services/MonsterService.luau:2085-2095 — the six feed-exit paths
--[[
	THE ONLY WAY A FEED ENDS. Six paths reach here and every one of them must: ...
	`verdict` IS nil WHEN THE CALLER SENDS ITS OWN MESSAGE. `completeFeed` sends FEED_OK and must not
	be followed by a FEED_INTERRUPTED; every other caller passes FEED_INTERRUPTED.
]]
-- IMPORTANT `StrikeDown` IS A SEVENTH PATH and must pass the interrupted verdict, never nil. The
--           struck feeder did not complete a feed, and nil is reserved for `completeFeed`.
-- QUESTION  Confirm the exact enum spelling against the six existing callers rather than against the
--           plan's diff — this review did not read all six.
