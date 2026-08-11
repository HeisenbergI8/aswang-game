--!strict
-- Review of src/server/pure/RoleDraw.luau — the injected-RNG pattern Phase 6 copies.
-- Excerpts only.

-- src/server/pure/RoleDraw.luau:7-19
--[[
	WHY THIS FILE IS UNDER src/server/pure/ AND NOT src/shared/pure/
	`default.project.json` maps `src/shared` wholesale into ReplicatedStorage, so every module there is
	require-able AND CALLABLE by any client ...

	For this module it is the security of the entire game. The algorithm being public is fine; a
	REPRODUCIBLE draw is not. Algorithm + inputs + seed = this round's assignment, and an exploiter who
	reproduces all three knows the Aswang BEFORE the round starts — with no remote to intercept and
	nothing for `check:secrecy` to see. It is the only leak in this game that leaves no trace on the wire.
]]
-- IMPORTANT: this is the whole argument for Phase 6's deviation from C07's written `(pool, count, seed)`
-- signature. TaskSelection lives in src/shared/ (its output is public within seconds and the module has
-- no secret inputs) — but a `seed` PARAMETER would put a reproducible generator on the client's side of
-- the wire. Injecting `nextFloat` keeps the generator in TaskService, on the server.

-- src/server/pure/RoleDraw.luau:22-25
--[[
	  · The RNG is INJECTED, never created here, and RoleService seeds it with `Random.new()` — no
	    argument. `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable and
	    both fatal.
]]
-- IMPORTANT: `roundNumber` is in EVERY RoundSnapshot (Types.ClientRoundSnapshot.RoundNumber), so it is
-- not merely guessable, it is delivered. `os.time()` is client-observable to the second. Phase 6 copies
-- this paragraph into TaskService's header, at the exact place the next author will be standing.

-- src/server/pure/RoleDraw.luau:30-31
--[[
	Lune resolves test requires by FILE PATH and knows nothing about Rojo, so this location costs no
	testability — `tests/role-draw.test.luau` requires "../src/server/pure/RoleDraw" and runs identically.
]]
-- NOTE: this is the escape hatch if TaskSelection ever turns out to need a secret input. Moving it to
-- src/server/pure/ and repointing the test's require is a two-line change; the plan does not need it,
-- because the seed is the only secret and the seed never enters the module.

-- src/server/pure/RoleDraw.luau:36-38
--[[
	NOTE `check-config.mjs` governs `src/server/`, so this file — unlike `src/shared/pure/` — may not
	contain a tunable number. That is why `weights` is a parameter.
]]
-- IMPORTANT and easy to trip over: `check:config` governs src/server/ and src/client/ ONLY
-- (.claude/scripts/check-config.mjs:36, `GOVERNED = /(^|\/)src\/(server|client)\//`). So a literal 8
-- inside src/shared/pure/KillValidation.luau would NOT be flagged. Phase 3 passes Range and Cooldown as
-- parameters anyway — for the same reason this file passes weights, and because the boundary tests can
-- then use round numbers without importing balance.

-- src/server/pure/RoleDraw.luau:79-92
--[[
	`nextFloat` must return a value in [0, 1). It is called exactly once per Aswang drawn, so a caller
	can reproduce a draw exactly by replaying the same stream — which is what makes 10,000 seeded rounds
	testable ...

	Degenerate inputs return a sensible assignment rather than erroring. A live server that reached one
	of these has a bigger problem than the draw, and the draw erroring inside `enterStarting` would
	leave the round stuck in STARTING with no Aswang and no log.
]]
-- IMPORTANT: both properties are copied by TaskSelection. `[0, 1)` is what makes
-- `math.floor(nextFloat() * i) + 1` a valid Fisher-Yates index, and the degenerate-input rule is why
-- an empty pool returns an empty table instead of erroring — the call site is enterStarting in both
-- cases, and a throw there is a round stuck in STARTING with no log.

-- src/server/pure/RoleDraw.luau:107-112
	-- Never draw every candidate as the Aswang: a round with no survivors is over before it starts.
	local picks = math.clamp(aswangCount, 0, math.max(#candidates - 1, 0))
-- IMPORTANT: this clamp is why a 1-player round draws ZERO Aswangs, which is the finding that made
-- C04's transform unverifiable (see the C02–C04 verification.md). Commit 3c70cfc added
-- Config.Debug.ForceAswangWhenSolo to work around it in Studio, and that override is the ONLY reason
-- this plan's solo refusal probes are reachable at all. It also means a solo round has zero SURVIVORS,
-- which is exactly the input Phase 5's WinConditions guard is built around.
