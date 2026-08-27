--!strict
--[[
	REVIEW — src/server/pure/RoleDraw.luau:1-99
	Read for V03 as THE PRECEDENT: a server-only pure draw module. ContainerLayout matches its shape,
	its header discipline and its three rules, and deviates in exactly one place (documented below).
]]

--[[
	IMPORTANT — THE PLACEMENT ARGUMENT, VERBATIM FROM THE HEADER (RoleDraw.luau:8-19). This is the
	paragraph V03's module must restate rather than cross-reference, because a phase is read alone:

	  "`default.project.json` maps `src/shared` wholesale into ReplicatedStorage, so every module
	   there is require-able AND CALLABLE by any client. [...] The algorithm being public is fine; a
	   REPRODUCIBLE draw is not. Algorithm + inputs + seed = this round's assignment, and an exploiter
	   who reproduces all three knows the Aswang BEFORE the round starts — with no remote to intercept
	   and nothing for `check:secrecy` to see. It is the only leak in this game that leaves no trace
	   on the wire."

	Substitute "layout" for "assignment" and it is V03's threat model unchanged. Spec §6.2 lists the
	two side by side for this reason.
]]

--[[
	IMPORTANT — THE TWO CALL-SITE RULES (RoleDraw.luau:26-32), both of which V03 inherits:

	  · "The RNG is INJECTED, never created here, and RoleService seeds it with `Random.new()` — no
	     argument. `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable
	     and both fatal."
	  · history is a DRAW INPUT and therefore secret "even though every past Aswang was already
	     revealed [...] every input a client holds shrinks the search space for the one it does not."

	The second rule is the subtler one for V03. The container ORDERING is a draw input and it IS
	client-derivable (Workspace replicates part names). That is acceptable here and it is worth being
	precise about why: an ordering is a permutation of labels, not a distribution over contents. The
	contents come from `Random.new()` and the mapping between them is never published. If a future
	chunk ever adds a second draw input a client controls — say, seeding from the player roster — this
	sentence stops being true.
]]

-- NOTE Lune resolves by FILE PATH, so `tests/role-draw.test.luau` requires
-- "../src/server/pure/RoleDraw" and runs identically. Proof that server/pure/ costs no testability.
-- tests/container-layout.test.luau does the same.

export type Role = "SURVIVOR" | "ASWANG"
-- NOTE Re-declared locally rather than required from Types, because a pure module that reaches for
-- `Types` stops being runnable from a terminal. Luau unions are structural so this and Types.Role are
-- the same type. ContainerLayout re-declares `Item` the same way.

--[[
	IMPORTANT (RoleDraw.luau:36-38) — "check-config.mjs governs src/server/, so this file — unlike
	src/shared/pure/ — may not contain a tunable number. That is why `weights` is a parameter."

	V03 inherits this exactly: ContainerLayout takes `Counts` as a parameter rather than reading 4/2/1,
	and the note adds that this is the right shape anyway — the counts are §4.4 balance knobs and V16
	is expected to move them.
]]

--[[
	THE INJECTION SIGNATURE, and V03's ONE DELIBERATE DEVIATION.
]]
function RoleDraw.draw(
	candidates: { number },
	history: History,
	aswangCount: number,
	weights: Weights,
	nextFloat: () -> number
): { [number]: Role }

--[[
	NOTE RoleDraw injects `nextFloat: () -> number` because weighted sampling needs a float over a
	cumulative range. ContainerLayout injects `nextInt: (number, number) -> number` instead, because a
	partial Fisher-Yates needs an integer in [slot, n].

	The deviation is deliberate and cheap: `nextInt`'s signature matches `Random:NextInteger`, so
	SearchService's adapter is one line and nothing has to be remembered. Deriving an index from a
	float would mean a floor and an off-by-one at the top of the range — precisely the bug a
	distribution band would catch late instead of early.
]]

--[[
	NOTE — TWO DISCIPLINES V03 COPIES WITHOUT CHANGE.

	1. DETERMINISTIC INPUT ORDER (RoleDraw.luau:88-91): "`Players:GetPlayers()` is not [ordered], so
	   RoleService sorts by UserId before calling; without that, 'same seed, same result' is false and
	   the test that proves this function correct proves nothing about the game."
	   V03's equivalent is `table.sort(names)` before evaluate — same rule, different unordered source
	   (`CollectionService:GetTagged`).

	2. DEGENERATE INPUTS RETURN, NEVER THROW (RoleDraw.luau:92-95): "A live server that reached one of
	   these has a bigger problem than the draw, and the draw erroring inside `enterStarting` would
	   leave the round stuck in STARTING with no Aswang and no log."
	   V03: containerCount = 0 returns an empty layout; a queue longer than the pool places what fits.
	   Both are asserted in tests/container-layout.test.luau.
]]
