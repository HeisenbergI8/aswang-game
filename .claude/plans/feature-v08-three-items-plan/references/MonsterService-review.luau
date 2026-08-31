--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (3245 lines). Phase 4 Step 4.4 only.

	THE HEADLINE FINDING OF THIS WHOLE PLAN: `ApplySaltHit` already does all five of §4.6's jobs.
	V05, V06 and V07 each landed their share as they built the systems behind them. V08 adds a comment
	and changes no logic.

	Cited against the file as read on 2026-08-29.
]]

-- src/server/Services/MonsterService.luau:46-66 — the seams, abridged
--[[
	THE FIVE SEAMS THE NEXT THREE CHUNKS CALL, so nobody has to guess which one to reach for:

	  · `ApplySaltHit(player)` — V08. Revert, -SaltDamage floored at WeakenedThreshold, Exposed for
	    SaltRevealDuration. The ONLY entry point for a salt hit; there is no bare `ForceRevert` any
	    more, precisely so a caller cannot revert without damaging.
	  · `HealFromFeed(userId) -> boolean` — WIRED AT V06 ...
	  · `FeedCompleted` (BindableEvent) — V07'S SEAM ...
	  · `IsExposed(userId) -> boolean` — V08's strike gate, half one.
	  · `IsWeakened(userId) -> boolean` — V08's strike gate, half two. §4.6: the buntot pagi kills an
	    Aswang that is BOTH.

	NONE OF THE FOUR ENUMERATES, and none returns the health value. Every one takes a UserId the
	caller already holds and answers false for a player with no monster state — which is every
	survivor, every round, so none of them is usable as a probe.
]]
-- IMPORTANT: `IsExposed` and `IsWeakened` are labelled "V08's strike gate", but THE STRIKE IS V10.
-- V08 builds carry, drop and the slot for the buntot pagi and gives it NO verb — `pure/ItemUse`
-- returns USE_NOT_IMPLEMENTED and tests/item-use.test.luau asserts it. Do not wire these two seams
-- in this chunk; the label predates the chunk numbering settling.
-- NOTE: "answers false for a player with no monster state" is what makes them safe to expose. V10
-- will AND them with GetAswangUserId() on the server and hand one boolean to a pure module, exactly
-- as ItemService.resolveThrow does for IsTransformed.

-- src/server/Services/MonsterService.luau:2926-2954 — ApplySaltHit's ordered body
function MonsterService.ApplySaltHit(player: Player)
	-- THE DISGUISE DIES FIRST (V07). BEFORE `endFeed`, BEFORE `revert`. A revert out of the MONSTER
	-- form while the CAT form stayed on would leave a player-shaped nothing wearing a cat: `revert`
	-- restores from `OriginalParts`, which `applyCamouflageLook` overwrote on top of.
	exitCamouflage(player)

	-- THE FEED DIES NEXT (V06). `endFeed` is what withholds both rewards — it is the path that fires
	-- neither `HealFromFeed` nor `FeedCompleted`. Left to feedTick's backstop, a hit in the last
	-- quarter-second races the deadline and §4.3's most important counterplay depends on tick
	-- alignment. SAFE FOR A PLAYER WHO IS NOT FEEDING, which is most salt hits.
	endFeed(player.UserId, "FEED_INTERRUPTED")
	revert(player)
	applyHealthEvent(player.UserId, "SALT")
	applyExposed(player)
end
-- IMPORTANT: FIVE OF §4.6's JOBS IN FIVE LINES, PLUS V07's CAMOUFLAGE EXIT. V08 rebuilds NOTHING
-- here. A phase that starts editing this function has misread the chunk.
-- IMPORTANT: THE ORDER IS THE CORRECTNESS. `endFeed` calls `revert` itself, so line 3 runs twice and
-- early-returns — the file calls that redundancy deliberate and cheap, because removing this
-- function's own revert on the grounds that a callee happens to do it would make the ordering depend
-- on endFeed's internals.

-- src/server/Services/MonsterService.luau:2963-3010 — the gate, abridged
--[[
	AND THE GATE OPENS HERE — THE ONLY PLACE IN THE REPO IT EVER DOES. (V07, §4.3)

	V06 made this function "the ONLY entry point for a salt hit; there is no bare `ForceRevert` any
	more, precisely so a caller cannot revert without damaging". V07 inherits that property and
	extends it: THERE IS NO WAY TO SALT A MONSTER WITHOUT REVEALING IT, AND NO WAY TO REVEAL ONE
	WITHOUT SALTING IT.

	THROUGH THE TRANSITION TABLE, NOT `= true`. Assigning the boolean directly here would work
	identically today and would put the rule in two places, which is how the second one stops being
	true.

	IT IS NEVER UNSET ... The reset is `onPhaseChanged`'s `table.clear(monsters)` on the way out of
	ACTIVE.

	READ, DO NOT CONSTRUCT. `stateFor` here would re-insert a departed player's UserId.
]]
local monster: MonsterState? = monsters[player.UserId]

if monster ~= nil then
	monster.HasBeenRevealed = CamouflageRules.revealedAfter(monster.HasBeenRevealed, "SALT_HIT")
end
-- IMPORTANT: THE FIFTH JOB, ALREADY DONE. The "only entry point" property is what V08's Step 4.4
-- comment names and protects — it is worth more than any of the six jobs individually, because each
-- was added by a different chunk and shared entry is the only thing that stopped them drifting.
-- NOTE: `revealedAfter` lives in pure/CamouflageRules with 16 grid cells asserting that only
-- SALT_HIT reveals. That is where the rule is written; this is where it is applied.

-- src/server/Services/MonsterService.luau:2033-2044 — endFeed's opening
local function endFeed(userId: number, verdict: Types.FeedVerdict?)
	local monster: MonsterState? = monsters[userId]

	if monster == nil or not monster.Feeding then
		return
	end

	-- STATE FIRST, THEN THE WORLD. `revert` below can reach code that asks whether this player is
	-- feeding; it must already read false by then, or a re-entrant path finds a half-ended feed.
	monster.Feeding = false
end
-- NOTE: this is why "interrupt any in-progress feed" is genuinely one of the five and not a hope.
-- endFeed is the ONLY way a feed ends, six paths reach it, and ApplySaltHit is path 2 by name.

-- src/server/Services/MonsterService.luau:2074-2086 — endFeed's WalkSpeed restore
--[[
	BaseWalkSpeed, NOT THE TRANSFORMED SPEED. C14 restored the captured transformed value onto an
	un-transformed player and left one character in the barrio reading 20 while everyone else read 16
	— a permanent role brand with the full gate green over it.
]]
-- IMPORTANT: THE STORY STEP 5.4 EXISTS BECAUSE OF, in this exact pair of services. `analyze`, all
-- five checks and six Lune suites were green over it. Only exploit-auditor found it. Quote this when
-- briefing the auditor on the carried item's tell surface.

-- src/server/Services/MonsterService.luau:866-870 — the Exposed glow's colours
glow.FillColor = rgb(Config.Salt.RevealGlowFillRgb)
glow.OutlineColor = rgb(Config.Salt.RevealGlowOutlineRgb)
-- IMPORTANT: THE FIFTH READER OF `Config.Salt`, and the one V02's survey at Config.luau:16-18 does
-- not list. Phase 2 must re-point these or the table's deletion fails analyze here.
-- NOTE: they move to `Config.Monster`, not to `Items` — the glow they colour is the Exposed
-- Highlight, whose brightness ramp is already ExposedGlowTransparency* under Monster.
