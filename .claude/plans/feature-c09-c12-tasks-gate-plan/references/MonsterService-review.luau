--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau
	Read 2026-08-12 for the C09-C12 plan. Unmodified by this plan.

	Read for two reasons: it is the second example of the service shape Phase 6's GateService copies,
	and its kill path decides how Phase 4's "drop on death" has to be written.
]]

-- src/server/Services/MonsterService.luau:586-601
	--  1. The corpse first, because it steals the character from the player. RoundService.MarkKilled
local function commitKill(killer: Player, victim: Player, victimCharacter: Model, position: Vector3)
	RoundService.MarkKilled(victim, true)
end
-- IMPORTANT FOR PHASE 4 — THE ORDERING TRAP. The corpse is built FIRST, which sets
-- `player.Character = nil` (see :289), and only THEN is `MarkKilled` called. RoundService's own
-- comment at :680-683 confirms it: "THE CALLER HAS ALREADY TAKEN THE BODY [...] Reversing those two
-- steps deletes the corpse in the same frame it is created."
-- CONSEQUENCE: any fetch "drop the item where they died" handler that asks for the carrier's position
-- AT THE MOMENT OF DEATH gets nil. `positionOf` returns nil when `player.Character == nil`.
-- This is why the plan's drop is defined as CEASING TO MOVE the item rather than placing it: the 4 Hz
-- tick has already put it within 250 ms of where they fell, so the correct drop handler reads no
-- position at all. That is not a simplification — it is the only version that works.

-- src/server/Services/MonsterService.luau:289-292
--  `player.Character = nil` is what makes it a prop: the player no longer owns it, so nothing the
--  [player does moves it]
-- NOTE: confirms the above from the other side. A detached character is a workspace model with no
-- owner, which is also a decent mental model for the fetch item — an anchored part the server moves.

-- src/server/Services/MonsterService.luau:694-700
--  creating it: MarkKilled calls EndRound, which sets ENDING, which fires PhaseChanged, which
--  landed here — while `commitKill` was still on the stack that made the corpse.
-- IMPORTANT FOR PHASE 6, AND IT IS THE MOST VALUABLE LINE IN THIS FILE FOR THIS PLAN: a win condition
-- firing inside a call stack REENTERS the phase handlers synchronously. `MarkKilled` -> `EndRound` ->
-- `enterEnding` -> `setPhase` -> `PhaseChanged:Fire` -> every subscriber, all before `MarkKilled`
-- returns.
-- GateService's `step()` calls `EndRound` the same way, so its own `onPhaseChanged` will run BEFORE
-- `step()` returns — `setGateLook(false)` on the ENDING transition while `step` is still iterating
-- `gates`. That is safe as written (it mutates part properties, not the `gates` array) but it is
-- exactly the shape that stops being safe the moment someone adds a `table.clear(gates)` to that
-- handler. The plan's `onPhaseChanged` deliberately only calls `discoverGates` on STARTING.
-- NOTE: `step()` also `return`s immediately after calling EndRound, which bounds the reentrancy to
-- one pass. Keep that return.

-- src/server/Services/MonsterService.luau (the service shape, for GateService)
-- NOTE: the pattern Phase 6 copies, confirmed across MonsterService and TaskService both —
--   · `local RoundService = require(script.Parent.RoundService)`, ONE DIRECTION ONLY
--   · `Init()` empty, `Start()` does the connecting
--   · subscribe to `RoundService.PhaseChanged.Event`, never be called by RoundService
--   · ask RoundService for state (`GetPhase`, `GetPlayerState`) rather than keeping a copy
--   · request outcomes (`MarkKilled`, `EndRound`) rather than writing the phase
-- IMPORTANT: the require direction is the one that bites. A cycle "errors at load, init.server.luau
-- swallows it into a single warn, and the server sits in IDLE forever looking exactly like 'nobody
-- has joined yet'." GateService must never be required BY RoundService.

-- src/server/Services/MonsterService.luau (the C04 revert bug, from CLAUDE.md)
-- IMPORTANT: CLAUDE.md records that this file shipped a Critical bug where "the transform's revert
-- restored hardcoded defaults instead of captured state, permanently branding the ex-Aswang in a way
-- readable map-wide" — and that `analyze`, all five checks and six Lune suites were GREEN over it.
-- Only `exploit-auditor` found it.
-- That is why Phase 6's `setGateLook` captures `closedLook` per part before opening and restores from
-- the capture rather than assigning defaults. Same failure shape, same surface, one file over.
return nil
