--!strict
--[[
	REVIEW — src/server/Services/GateService.luau (213 lines; read 1-80 plus a signal scan of the
	whole file)

	READ ONLY. C29 changes nothing here. Reviewed to answer one question: where does the gate-opening
	cue come from? Answer: not from this service. A grep of the whole file for `Fire`, `Remotes.Get`,
	`SetAttribute` and `Sound` returns NOTHING — it emits no signal of any kind.
]]

-- src/server/Services/GateService.luau:20-23
--[[
	NO REMOTE. The gate is reached by walking, and the server measures the walk. There is no
	`RequestEscape` and there must not be: a client-callable escape is a free win behind whatever
	validation somebody remembers to write, and proximity needs none.
]]
-- IMPORTANT: this settles the gate cue's design before it is designed. The cue is an edge detector on
-- `ClientRoundSnapshot.GateOpen` (Types.luau:543), which RoundService already derives and already
-- sends — there is nothing here to hook and nothing that should be added.

-- src/server/Services/GateService.luau:5-9
--[[
	🔒 THE ONE SERVICE IN THIS MILESTONE THAT READS THE SECRET, and it reads it to REFUSE a win rather
	than to grant one. §4.8: "Survivors win: 5/5 tasks done AND at least 1 survivor reaches the escape
	gate." The Aswang reaching an open gate must do nothing at all, and "nothing at all" is literal —
	no refusal, no verdict, no remote, no sound, no prompt.
]]
-- IMPORTANT: "no sound" is written into this service's contract, and it is the constraint that decides
-- WHEN the gate cue fires. A cue on ARRIVAL would violate it directly — and would leak by omission
-- the first time an Aswang walked through an open gate and nothing played, which is the
-- `absence-is-observable` shape exactly. The plan's cue fires on the gate OPENING, a global fact on
-- every snapshot, identical for all eight players.

-- src/server/Services/GateService.luau:10-13
--[[
	IT DOES NOT OWN GateOpen. RoundService derives it from the task count (§6.4: RoundService owns the
	phase and everything that hangs off it), and this service reads `IsGateOpen()`. There is exactly
	one writer, and it is not here.
]]
-- NOTE: confirms the cue's input is authoritative and single-sourced. The client's `GateOpen` field
-- and this service's `IsGateOpen()` read the same derived value, so the sound cannot disagree with
-- the win condition.

-- src/server/Services/GateService.luau:41-47
-- SERVER-ONLY. Rebuilt at every STARTING rather than cached forever ...
local gates: { BasePart } = {}
-- What the gate looked like before it opened, so closing it puts back what was there rather than a
-- guessed default. MonsterService shipped a Critical bug doing exactly the opposite ...
local closedLook: { [BasePart]: { Transparency: number, CanCollide: boolean } } = {}
-- NOTE: the gates are discovered by CollectionService tag `EscapeGate` (:50). A client COULD find the
-- same tagged part and play the cue positionally at the gate, which would be better navigation.
-- The plan does not, because the tag is a MAP contract and the map is not in Git — C30 dresses the
-- barrio and is explicitly outside this run. Recorded as Follow Up 4 rather than dropped.
-- IMPORTANT: `closedLook` is the capture-then-restore pattern again (see SkyController-review). The
-- audio analogue is the heartbeat's stop conditions: state applied on an event must be removed on
-- every path, not just the happy one.
