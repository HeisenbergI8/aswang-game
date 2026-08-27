--!strict
--[[
	REVIEW — src/server/pure/SearchPool.luau:30-86
	Read for V03. THE ANSWER TO QUESTION 1: where does the container pool come from, and does this
	gate the seed.

	VERDICT: V03 CONSUMES THIS, it does not re-derive it. The module is already generic over three
	numbers and names no mechanic at all, so a second caller costs nothing and a second copy would
	cost a divergence.
]]

-- The five verdicts, already exported and already mirrored in Types.SearchPoolVerdict.
export type Verdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"

-- NOTE `Unique` preserves DISCOVERY ORDER, which is `GetTagged`'s order — engine-defined. V03 maps
-- container index -> Name off this list, so the caller MUST sort before evaluating or the index
-- meaning changes between servers. ItemService:90 already does; V03 copies it.
export type Report = {
	Verdict: Verdict,
	Unique: { string },
	Duplicates: { string },
}

-- IMPORTANT The signature is (names, required, expected) and nothing in it is salt-specific. V03
-- passes required = SaltSpawnCount + GarlicSpawnCount + BuntotPagiSpawnCount (7, summed from Config,
-- never a literal) and expected = Config.Search.ContainerCount (15).
function SearchPool.evaluate(names: { string }, required: number, expected: number): Report

-- NOTE Precedence is blocking-first and SHORT OUTRANKS DUPLICATE_ID deliberately. For V03 that means
-- a map with 6 containers, two of them same-named, reports SHORT — the urgent fault — rather than
-- sending the map author to rename a part first.
	if count == 0 then
		verdict = "EMPTY"
	elseif count < required then
		verdict = "SHORT"
	elseif #duplicates > 0 then
		verdict = "DUPLICATE_ID"
	elseif count > expected then
		verdict = "OVERSIZED"
	end

--[[
	IMPORTANT — HOW V03 TREATS EACH VERDICT, and it is NOT "gate the seed on OK".

	  EMPTY        the only blocking one. layout = nil, every RequestSearch answers
	               SEARCH_NO_CONTAINER, and the round STILL STARTS. RoundService owns the phase
	               (§6.4) and SearchService must never delay a transition.
	  SHORT        SEED ANYWAY into what exists, and warn. The greybox barrio has no tagged
	               containers today, so a plan that refuses to seed below 15 ships a chunk nobody can
	               play until the map catches up. ContainerLayout.draw places
	               math.min(#queue, containerCount) in priority order — buntot pagi, salt, bawang.
	  DUPLICATE_ID `evaluate` has already dropped the dupes from `Unique`. Warn naming them, seed.
	  OVERSIZED    seed over all of them; the map and Config merely disagree.
	  OK           seed, and log the COUNT only.

	QUESTION for V04+: `expected` is Config.Search.ContainerCount, so tagging a 16th container in the
	map produces an OVERSIZED warn on every round start until Config is bumped. That is the intended
	nag, but it is noisy during map work. Not V03's problem; noting it because the map author will
	hit it first.
]]

--[[
	NOTE ON THE HEADER, WHICH IS THE BEST ARGUMENT IN THE REPO FOR V03'S FILE PLACEMENT
	(src/server/pure/SearchPool.luau:16-24)

	"WHY src/server/pure/ AND NOT src/shared/pure/ — and the argument is about the INPUTS, not the
	algorithm. [...] It is not fine when a client can supply the inputs."

	ContainerLayout is the same argument one step stronger: SearchPool's inputs are the pool contents
	(a map index), ContainerLayout's inputs plus a seed are THE LAYOUT ITSELF. Both belong under
	src/server/pure/. `tests/search-pool.test.luau` requires "../src/server/pure/SearchPool" and runs
	fine, which is the proof that this placement costs no testability.
]]

--[[
	NOTE ON THE STALE COMMENTS. This file still says "TaskPoint" (line 43) and "see Step 2.2" (line
	55) — v1.3 vocabulary that V01 did not sweep. The CODE is generic and correct; only the prose is
	stale. V03 must not "fix" it: this is a shared module and rewording its comments to talk about
	containers would make it read as search-specific, which is exactly what it is not.
]]
