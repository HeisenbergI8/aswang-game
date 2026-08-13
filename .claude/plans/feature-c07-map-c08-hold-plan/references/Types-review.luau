--!strict
-- REVIEW: src/shared/Types.luau:51-58, 60-80, 128-160, 162-172 (excerpts)
--
-- Read for ActiveTask, and for the three long payload comments. Those comments are the direct input to
-- the TaskProgressChanged design and they are the reason it is a typed local rather than an inline table.

export type ActiveTask = {
	Id: string,
	Type: TaskType,
	SpawnPointName: string,
	Progress: number, -- 0..1
	Completed: boolean,
}
-- NOTE: already exactly what Phase 3 needs. UNCHANGED by this plan.
-- IMPORTANT: it deliberately does NOT carry a Position, and the plan keeps it that way. The anchor part
-- is what the server measures against (TaskService.activeParts), and a cached copy of a position is a
-- copy that goes stale the moment C17 moves the greybox.
-- NOTE `Progress` is 0..1 and `Completed` is separate rather than derived. TaskProgress.tick returns
-- both for the same reason: "reached 1.0 this tick" and "was already done" are different events, and
-- only the first should fire a completion.

	--[[
	  · a field of the WRONG TYPE      → caught  ("Property 'Result' is not compatible")
	  · a MISSING field                → caught  ("...missing field 'RoundNumber'")
	  · an EXTRA field                 → NOT CAUGHT. Silently accepted.
	]]
-- IMPORTANT, and the single most useful thing I read for designing a new payload. Measured against this
-- repo's own analyzer, not assumed. It means TaskProgressPayload is documentation plus two thirds of a
-- guard, and it means the plan cannot rely on the type to keep a field like `PresentPlayerCount` out.
-- That is why §1.4 decision 2 and risk R1 are written as prose with an exploit-auditor brief attached.

	--[[
		`check-secrecy.mjs` checks payload FIELDS against an allowlist only for remotes on its
		REVEAL_ALLOWLIST, and PlayerKilled is deliberately not on that list.
		Its broadcast rule DOES now run here, and it did not used to. ... It now resolves the payload to
		its declaration and matches `killer\w*`
	]]
-- IMPORTANT for what TaskProgressChanged actually gets checked on. It is NOT on REVEAL_ALLOWLIST, so
-- unlike RoundEnded the scanner does inspect the call: it resolves the typed local to its declaration
-- and reads top-level fields for role/userid/killer tokens. Concretely:
--   caught here   — Role, AswangUserId, KillerUserId added to the payload
--   NOT caught    — PresentPlayerCount, HolderCount, Contributors
-- The second row is the whole of risk R1, and it is why the payload is built as a typed local within
-- 1200 characters of the FireClient (the scanner's stated envelope) rather than inline.

	-- Built as a TYPED LOCAL, not an inline table: `FireAllClients` takes `...any`, so an inline
	-- literal is checked against nothing at all.
-- NOTE: copied exactly for publishProgress in Step 4.2. `Remotes.Get` returns a plain RemoteEvent, so
-- there is no type on the wire at all unless the caller puts one on the local.

export type KillVerdict = "OK" | "WRONG_PHASE" | ... | "TARGET_IS_ASWANG" | "OUT_OF_RANGE"
	-- TARGET_IS_ASWANG is a direct role oracle — fire RequestKill at every player in turn and the one
	-- that answers differently is the monster ... There is no "safe subset" to return, which is why the
	-- handler returns nothing at all on every refusal rather than filtering the verdict.
-- IMPORTANT: TaskProgressVerdict is modelled on this, and the argument transfers exactly. C12 adds a
-- value meaning "you are the Aswang, your progress does not count", and echoing ANY verdict once that
-- exists is the same oracle. Hence Step 4.1's rule: every refusal returns nothing, not a filtered
-- verdict, not a boolean, not an error.

export type ClientRoundSnapshot = {
	TasksCompleted: number,
	TasksRequired: number,
	GateOpen: boolean,
}
-- NOTE: UNCHANGED by this plan, and worth stating out loud — the architect brief says widening this is
-- a Follow Ups decision, not a detail. It is not widened. The three new types are additions beside it,
-- and only TaskProgressPayload crosses the wire.
