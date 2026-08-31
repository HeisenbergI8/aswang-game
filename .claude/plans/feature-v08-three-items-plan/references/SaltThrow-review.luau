--!strict
--[[
	REVIEW — src/shared/pure/SaltThrow.luau (210 lines), migrating to pure/ItemThrow at V08 Phase 1.

	~40 of the chunk's ~70 carried-over assertions are about this module
	(tests/salt-throw.test.luau, 379 lines). The geometry moves across unchanged; only the carry input
	and three verdict spellings change.

	Cited against the file as read on 2026-08-29.
]]

-- src/shared/pure/SaltThrow.luau:8-27 — the header's central argument
--[[
	WHAT COUNTS AS A HIT, AND THE FOUR THINGS THAT DO NOT
	A hit requires a TRANSFORMED Aswang, inside `Range`, inside the cone. Everything else is MISS, and
	MISS IS ONE VALUE ON PURPOSE:

	  · nothing in the cone
	  · a survivor in the cone
	  · the Aswang in the cone, NOT transformed
	  · the Aswang in the cone, transformed, past Range

	Splitting them is the obvious refactor and it hands over the game. `MISS_NOT_ASWANG` beside
	`MISS_OUT_OF_RANGE` lets a compromised client stand in front of each player in turn and read the
	monster off the refusal shape — for the price of one pouch.
]]
-- IMPORTANT: V08 ADDS A FIFTH WORLD ("holding a bawang or the buntot pagi") AND IT JOINS THE SAME
-- COLLAPSE. The fifth is the one most likely to be argued out, because it looks harmless: the
-- thrower already knows what they are holding, so a `MISS_WRONG_ITEM` seems to tell them nothing new.
-- The leak is in the NEGATIVE. Throw while holding salt, and a refusal that is NOT MISS_WRONG_ITEM is
-- a refusal about the TARGET. Splitting it restores the oracle through the back door.
-- NOTE: the empty hand is answered ABOVE the geometry (NO_POUCH → ITEM_NO_ITEM) precisely because it
-- depends only on the thrower, so every candidate gets the same answer and there is nothing to
-- difference. The wrong-item case is only reachable after a target was evaluated. That distinction is
-- the whole reason one goes above the MISS line and the other below it.

-- src/shared/pure/SaltThrow.luau:36-42
--[[
	WHY `src/shared/pure/` IS SAFE FOR THIS ... What a client cannot obtain is the INPUT
	`TargetIsTransformedAswang`, which exists only in server memory. Logic is not secret; inputs are.
	There is no seed here at all.
]]
-- NOTE: the test CLAUDE.md prescribes, applied and written down. `ItemThrow` inherits it unchanged —
-- V08 adds `Held`, which is the requesting client's OWN slot and therefore already known to it.
-- No new input becomes client-suppliable, and there is still no seed.

-- src/shared/pure/SaltThrow.luau:55-73 — the Request type
export type Request = {
	Phase: RoundPhase,
	ThrowerState: PlayerState,
	Carried: number,
	ThrowerPos: Vec3,
	Direction: Vec3,
	TargetPos: Vec3,
	TargetIsTransformedAswang: boolean,
	Range: number,
	ConeDegrees: number,
}
-- NOTE: `Carried: number` → `Held: ItemType?` is the only field change in the migration.
-- NOTE: `Direction` is documented as "unit-length in the caller's intent, NOT trusted to be" — a
-- client sends it and a client can send Vector3.zero. `normalise` refuses zero and non-finite.

-- src/shared/pure/SaltThrow.luau:76-176 — sub/magnitude/dot/normalise/inCone
-- IMPORTANT: COPY THIS BLOCK BYTE-FOR-BYTE. It is the half TrialService shares (C22: "the throw a
-- player learned in the tutorial would stop being the throw that works in a round"), and every
-- geometric assertion in the suite is about it. Renaming the file around it is a migration; editing
-- it while renaming is a rewrite with a migration's test coverage.

-- src/shared/pure/SaltThrow.luau:161-171 — the cosine comparison
if not (coneDegrees > 0 and coneDegrees < 90) then
	return false
end

return dot(aim, bearing) >= math.cos(math.rad(coneDegrees))
-- NOTE: no `math.acos`, deliberately — that call would need its own domain guard for a dot product
-- floating-point error pushed to 1.0000001. `math.cos` is monotonically decreasing over [0, pi], so
-- "inside the cone" is a plain `>=`.
-- IMPORTANT: the (0, 90) clamp is a DOMAIN GUARD, not a tunable, and stays hardcoded. `check:config`
-- must not be appeased by moving it to Config — Config's value is pinned separately at
-- tests/config.test.luau:203, and this line re-checks because the module is called with numbers.

-- src/shared/pure/SaltThrow.luau:188-199 — the carry gate
--[[
	`< 1` refuses a NaN carry too, because `NaN < 1` is false — which would WRONGLY admit it. Guard
	the finite range explicitly rather than relying on this comparison.
]]
if not (request.Carried >= 1 and request.Carried < math.huge) then
	return "NO_POUCH"
end
-- NOTE: the NaN and infinity guards DIE with the number they guarded. `Held` is an optional string
-- assigned from `SearchService.ItemFound`; there is no arithmetic left to poison. `if request.Held ==
-- nil then return "ITEM_NO_ITEM" end` is the whole replacement.
-- QUESTION for the implementer: keep the `NO_POUCH` spelling or move to `ITEM_NO_ITEM`? The plan
-- says rename, on Types.luau:520-524's argument that a third union sharing a bare spelling makes a
-- handler wired to the wrong path a working program with the wrong meaning.

-- tests/salt-throw.test.luau:216-240 — the four-worlds table
local worlds: { { label: string, verdict: SaltThrow.Verdict } } = {
	-- four entries, each an evaluate() call
}
-- IMPORTANT: THE ANNOTATION IS LOAD-BEARING AND IS THE LESSON IN
-- .claude/lessons/pure-module-unions-widen-in-lists.md. Without `: { { label: string, verdict:
-- SaltThrow.Verdict } }` the field infers as plain `string`, the comparisons still compile, and the
-- test passes while asserting nothing about the union. Carry the annotation across with the table.
-- NOTE: the suite's own header says this table is "the assertion this file exists for". The V08
-- migration adds two rows (bawang, buntot pagi) and must keep the property, which is not "bawang
-- cannot hit" but "all six rows produce the SAME value".
