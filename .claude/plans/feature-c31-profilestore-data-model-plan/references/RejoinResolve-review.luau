--!strict
--[[
	REVIEW — src/shared/pure/RejoinResolve.luau:1-53, 109-112
	Read for: does C31's rejoin overlap this module's rejoin? And what a pure module looks like here.
	ANSWER TO THE FIRST: no. They are two unrelated meanings of the same word, and the plan must not
	let them blur.
]]

--------------------------------------------------------------------------------
-- :3-11 — the concern this module owns
--------------------------------------------------------------------------------

--	RejoinResolve — what does a player become when they arrive mid-round? (§6.4, C15)
--		(request) -> PlayerState
-- IMPORTANT: THIS IS ROUND STATE, NOT SAVED DATA. It answers "ALIVE, GHOST, SPECTATOR or LOBBY for
-- the round currently running on THIS server". C31 answers "what XP and cosmetics does this account
-- own, across every server, forever". Nothing is shared: no field, no storage, no lifetime. A player
-- can rejoin as a SPECTATOR (this module) while their profile loads with 4,000 XP intact (C31).
-- The plan therefore neither calls this module nor is called by it, and ProgressionService does not
-- appear in RoundService's onPlayerAdded path at all.

--------------------------------------------------------------------------------
-- :28-31 — a limit worth carrying into C31's thinking
--------------------------------------------------------------------------------

--	WHAT THIS MODULE DOES NOT AND CANNOT FIX: server-hopping. Roblox does not guarantee a returning
--	player the server they left [...]
-- NOTE: the same platform fact is why C31 needs SESSION LOCKING rather than a plain DataStore write.
-- A player who leaves and lands on a different server is the ordinary case, not the edge case, and it
-- is exactly the case where an unlocked read-modify-write duplicates or rolls back data. §6.1's "do
-- not hand-roll DataStore access" and this paragraph are the same observation from two directions.

--------------------------------------------------------------------------------
-- :39-43 — the pure-module contract the plan copies exactly
--------------------------------------------------------------------------------

--	NO `script.Parent` REQUIRES. Both unions are re-declared; Luau unions are structural.
export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
-- IMPORTANT: this is the template for ProfileMigration. Types re-declared locally, exported so the
-- test can `type X = Module.X`, and no require of Types or Enums. A pure module that reaches for
-- either stops being runnable under Lune and the whole point is lost.

--------------------------------------------------------------------------------
-- :109-111 — the cast, and why ProfileMigration avoids needing one
--------------------------------------------------------------------------------

	-- The cast is CLAUDE.md's documented Luau bite: narrowing a literal union by excluding members
	-- widens the remainder to plain `string`, which then fails to satisfy the declared return type.
	return stored :: PlayerState
-- NOTE: this works because the union is a SCALAR. Per
-- .claude/lessons/pure-module-unions-widen-in-lists.md, the same cast inside a LIST fails with "none
-- of the union options are compatible" and reports at the call site, in the wrong file. The plan's
-- ProfileMigration sidesteps the question entirely: its Outcome union is a scalar FIELD that callers
-- compare with `==` against a literal, so there is no cast on either side of the require, and
-- `Applied` is plain `{ string }` by design.
