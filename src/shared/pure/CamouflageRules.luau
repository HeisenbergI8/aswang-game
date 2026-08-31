--!strict
--[[
	CamouflageRules — may this Aswang hide, right now? (V07, §4.3)

		evaluate(request)      -> Verdict        may camouflage BEGIN
		evaluateSmoke(request) -> SmokeVerdict   may a smoke burst be spent
		revealedAfter(flag, event)  -> boolean   the reveal flag's ONLY transition table
		chargeAfter(charge, event)  -> boolean   the charge's ONLY transition table
		smokeBlocks(from, to, centre, radius) -> boolean   the pure half of "breaks line of sight"

	THE FIRST TEST IS THE REVEAL AND IT IS UNCONDITIONAL. §4.3: "Camouflage is locked until the Aswang
	has been publicly revealed — that is, until it has taken a salt hit. Before that, it cannot
	camouflage at all." This module is the only place that sentence is written as code, and the
	ordering is load-bearing rather than stylistic: with the reveal test first, there is no
	combination of the other three inputs that can produce OK for an unrevealed monster, and
	`tests/camouflage-rules.test.luau` asserts the entire `HasBeenRevealed = false` half of the grid
	rather than a sample of it.

	WHY THAT SENTENCE IS WORTH A MODULE. Camouflage removes a player avatar from the world. Fired
	before a reveal, four players are visible and one is missing in a five-player lobby, and anyone
	who counts knows who the Aswang is — permanently, with no transform witnessed, no risk taken and
	nothing to argue about. The disguise would PERFORM the reveal rather than hide anything. No test
	elsewhere in this repo would report it: the leak is a difference between players, not a piece of
	data, and `check:secrecy` is a text tripwire that cannot see it (`.claude/lessons/absence-is-
	observable.md`).

	WHY `src/shared/pure/` IS SAFE FOR THIS, stated rather than assumed. `default.project.json` maps
	`src/shared` wholesale into `ReplicatedStorage`, so any client can require AND RUN this module.
	What it learns is the rule — which §4.3 states in public and one round of play demonstrates. What
	it cannot obtain is an INPUT: `HasBeenRevealed` and `HasCharge` are fields on `MonsterService`'s
	server-only `monsters` table, `MonsterState` is derived from that table by `monsterStateOf`, and
	`Phase` is already public. There is no seed here and no draw, so there is no arrangement of this
	module in which one player's answer is distinguishable from another's.

	NO `script.Parent` REQUIRES — Lune has no `script`. The unions below are re-declared; Luau unions
	are structural, so these and the matching ones in `Types` are the same types. The verdict is
	returned as a SCALAR and never inside a list: `.claude/lessons/pure-module-unions-widen-in-
	lists.md` is what that rule costs when it is broken.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
export type CamouflageForm = "CAT" | "DOG" | "PIG" | "GOAT" | "CHICKEN" | "VILLAGER"

--[[
	`NOT_REVEALED` IS FIRST IN THE UNION AND FIRST IN THE FUNCTION, and it is the only verdict in this
	game that is a DESIGN INVARIANT rather than a state report. Every other value here describes
	something the monster could fix in the next ten seconds; this one describes a round in which it
	has not yet been salted, and the answer does not change until a survivor lands a throw.
]]
export type Verdict =
	"OK"
	| "NOT_REVEALED" -- §4.3's gate. Nothing overrides it and nothing is checked before it
	| "WRONG_PHASE" -- hiding is an ACTIVE-phase activity and nothing else
	| "NO_CHARGE" -- spent on the last hide, and only a completed feed brings it back
	| "ALREADY_CAMOUFLAGED" -- one form at a time
	| "NOT_TRANSFORMED" -- the disguise is the monster's, and it steps out of monster form to wear it
	| "NO_SLOT" -- no ambient entity of that form to swap with (V07, Phase 3)

export type Request = {
	--[[
		THE GATE. False until this monster has taken a salt hit THIS ROUND, and false is the value a
		freshly-created record carries — see `MonsterService.stateFor`. A caller that cannot answer
		this question must pass false; there is no nil case and no default-true anywhere in the path.
	]]
	HasBeenRevealed: boolean,
	-- Spent on entry, restored ONLY by a completed feed. See `chargeAfter` for the whole transition.
	HasCharge: boolean,
	MonsterState: MonsterState,
	Phase: RoundPhase,
	--[[
		OPTIONAL, and nil is a real answer rather than a caller's mistake: `AmbientRoster.claim`
		returns nil when every entity of that form is already claimed or the population failed to
		spawn. Answered as NO_SLOT so that swap-not-spawn is enforced HERE rather than trusted at the
		call site — §4.3 is explicit that the monster "must never SPAWN a new one: two pigs where
		there was one is a head count with extra steps".
	]]
	SlotAvailable: boolean,
}

--[[
	EVERY EVENT IN THE ROUND THAT COULD PLAUSIBLY TOUCH EITHER BOOLEAN, enumerated so that the answer
	for each is written down rather than implied by which call sites someone remembered to edit.

	`pure/MonsterHealth` set this shape at V05 and the reason holds harder here: health is a number a
	playtester notices when it is wrong, and these two are booleans nobody can see from inside the
	game at all. The failure mode is not "camouflage misbehaves"; it is "camouflage was available one
	round earlier than the design allows and the round looked normal".
]]
export type MonsterEvent =
	"SALT_HIT" -- the ONLY event that reveals. §4.3, and V08 changes nothing about that
	| "FEED_COMPLETED" -- the ONLY event that restores the charge. §4.3
	| "FEED_INTERRUPTED" -- restores NOTHING. "Interrupting a feed is a real victory"
	| "CAMOUFLAGE_ENTERED" -- spends the charge
	| "CAMOUFLAGE_EXITED" -- does NOT return it. Once revealed, the monster must kill to hide
	| "TRANSFORMED"
	| "REVERTED"
	| "KILLED" -- the kill, not the feed that follows it. A kill alone restores nothing

export type SmokeVerdict =
	"OK"
	| "SMOKE_NOT_REVEALED" -- the same gate, and a DISTINCT value from camouflage's on purpose
	| "SMOKE_WRONG_PHASE"
	| "SMOKE_COOLING" -- Config.Monster.SmokeCooldown has not elapsed since the last burst

export type SmokeRequest = {
	HasBeenRevealed: boolean,
	Phase: RoundPhase,
	--[[
		os.clock() at the call site and at the last burst, or nil if there has not been one this
		round. Taken as fields rather than read here so the test can hand this module a synthetic
		clock and `check:config` has no literal to flag.
	]]
	Now: number,
	LastBurstAt: number?,
	Cooldown: number,
}

export type Vec3 = { X: number, Y: number, Z: number }

local CamouflageRules = {}

--[[
	MAY CAMOUFLAGE BEGIN? Called by `MonsterService`'s `RequestCamouflage` handler, on a request a
	client sent about ITSELF.

	THE ORDER IS THE CONTRACT, and it is not `FeedRules`'s order. `FeedRules` puts world facts first
	so that a log full of OUT_OF_RANGE is a UX finding; this module puts THE GATE first, above even
	the phase, because the gate is the one refusal whose precedence is a security property. Were
	`WRONG_PHASE` checked first, an unrevealed Aswang firing this remote in INTERMISSION and again in
	ACTIVE would receive two different refusals — and a client that can distinguish "wrong phase" from
	"not revealed" has been handed a probe for whether it has been salted yet. It already knows that,
	so the leak is small; the ORDERING RULE is what stops it growing when someone later adds an input
	whose refusal is not already public.
]]
function CamouflageRules.evaluate(request: Request): Verdict
	if not request.HasBeenRevealed then
		return "NOT_REVEALED"
	end

	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	if request.MonsterState == "CAMOUFLAGED" then
		return "ALREADY_CAMOUFLAGED"
	end

	--[[
		AN ALLOWLIST OVER FIVE STATES, NEVER `~= "NORMAL"` — `FeedRules`'s rule, and it matters more
		here. FEEDING is refused because §4.3 pins the monster to the body for the duration and a hide
		mid-meal would be an escape from the one predictable window the buntot pagi needs. EXPOSED is
		never produced by `monsterStateOf` (it is a LATCH that coexists with the form), and it is
		answered anyway: a state with no stated answer is how these tables acquire bugs.
	]]
	if request.MonsterState ~= "TRANSFORMED" then
		return "NOT_TRANSFORMED"
	end

	if not request.HasCharge then
		return "NO_CHARGE"
	end

	-- LAST, because it is the only refusal that depends on what OTHER entities in the world are doing,
	-- and a log full of NO_SLOT is a population finding rather than a rules one.
	if not request.SlotAvailable then
		return "NO_SLOT"
	end

	return "OK"
end

--[[
	THE REVEAL FLAG'S ONLY TRANSITION, AND IT IS ONE-WAY.

	§4.3 and the build plan agree on the source: "`hasBeenRevealed` is the gate and it is set by the
	first salt hit, never by anything else. 'Someone saw it transform' is not knowable server-side; a
	salt hit is a fact the server already owns."

	IT NEVER GOES BACK TO FALSE, and that is a decision rather than an omission. The Exposed window
	expires after `Items.SaltRevealDuration`; this does not. Once the barrio has seen a glowing
	monster, the information is out there and no timer takes it back — §4.3's "everyone already knows
	who it is, so a head count tells them nothing new" is a statement about the ROUND, not about the
	ten seconds. The reset is `onPhaseChanged`'s existing `table.clear(monsters)` on the way out of
	ACTIVE, exactly as it is for `Health`, and it is the only one.

	A `false` RETURN FOR AN UNKNOWN EVENT IS NOT AVAILABLE HERE — the function returns the CURRENT
	value for everything that is not a salt hit, so an event nobody has thought of cannot un-reveal a
	monster mid-round either. Fail closed in both directions.
]]
function CamouflageRules.revealedAfter(hasBeenRevealed: boolean, event: MonsterEvent): boolean
	if event == "SALT_HIT" then
		return true
	end

	return hasBeenRevealed
end

--[[
	THE CHARGE'S ONLY TRANSITION. §4.3: "Camouflage is spent on use and only a feed restores it. Once
	revealed, the Aswang must kill to hide."

	THE PRESSURE LOOP IS THESE FOUR LINES. Spend on entry, restore on a COMPLETED feed, and nothing
	else moves it — so a revealed monster that wants to hide again has to kill somebody and stand on
	the body for five seconds in the open, which is §4.3's "being salted does not make the monster
	cautious — it makes it desperate".

	`FEED_INTERRUPTED` IS IN THE ENUM AND ANSWERS WITH THE CURRENT VALUE, deliberately. It is the
	event a reader most expects to find handled, and leaving it to the fallthrough would make
	"interrupting a feed costs the camouflage refresh" a property of an ABSENCE. `MonsterService`
	already guarantees it structurally — `endFeed` fires neither `HealFromFeed` nor `FeedCompleted` —
	and this line states the same thing where the grid can assert it.

	`CAMOUFLAGE_EXITED` DOES NOT RESTORE IT. Stepping out of a cat is not a feed.
]]
function CamouflageRules.chargeAfter(hasCharge: boolean, event: MonsterEvent): boolean
	if event == "FEED_COMPLETED" then
		return true
	end

	if event == "CAMOUFLAGE_ENTERED" then
		return false
	end

	return hasCharge
end

--[[
	MAY A SMOKE BURST BE SPENT? Same gate, same ordering rule, separate verdict union.

	THE VERDICT VALUES ARE PREFIXED AND NOT SHARED WITH `Verdict`. Two unions that happen to contain
	the same strings are one refactor away from being passed to each other's handler, and under
	`--!strict` a shared union would typecheck that mistake.

	NO CHARGE FIELD, AND NO FEED DEPENDENCY. §4.3 ties the FEED to camouflage and says nothing of the
	kind about smoke — "it has one smoke ability" names the ability, not a per-round use — so smoke is
	a cooldown and camouflage is a charge. Wiring smoke to the feed as well would mean a salted Aswang
	that has not killed recently cannot escape, which is the death sentence §4.3 built smoke to
	prevent.
]]
function CamouflageRules.evaluateSmoke(request: SmokeRequest): SmokeVerdict
	if not request.HasBeenRevealed then
		return "SMOKE_NOT_REVEALED"
	end

	if request.Phase ~= "ACTIVE" then
		return "SMOKE_WRONG_PHASE"
	end

	local lastBurstAt = request.LastBurstAt

	if lastBurstAt == nil then
		return "OK"
	end

	--[[
		FAIL CLOSED ON EVERY DEGENERATE NUMBER, and test the values rather than trusting them —
		`KillValidation.withinRange`'s idiom, and `FeedRules` copied it for the same reason. Written
		`not (elapsed >= cooldown)` rather than `elapsed < cooldown` so a NaN elapsed (a clock that
		went backwards, a nil-coalesced field) REFUSES instead of granting: NaN compares false to
		everything, so the naive form lets it straight through.
	]]
	local elapsed = request.Now - lastBurstAt

	if not (elapsed >= request.Cooldown) then
		return "SMOKE_COOLING"
	end

	return "OK"
end

--[[
	DOES A SMOKE CLOUD SIT ON THE LINE BETWEEN THESE TWO POINTS? (V07, §4.3)

	THIS IS THE WHOLE OF "BREAKS LINE OF SIGHT" THAT IS ALLOWED TO BE A MECHANIC. The particles are
	presentation: a client can delete an emitter, lower its graphics quality, or never receive the
	burst at all, and none of that may change what the server permits. So the server asks this
	function — a closest-approach test from a segment to a sphere centre — and refuses the kill or the
	throw on its answer, exactly as `hasLineOfSight`'s raycast already refuses a kill through a wall.

	PURE GEOMETRY OVER THREE NUMBERS PER POINT, not Vector3, because Lune has no Roblox datatypes and
	the point of putting it here is that `tests/camouflage-rules.test.luau` can enumerate it.
	`KillValidation.Vec3` is the same trick and `MonsterService.vec` is the adapter that already
	exists for it.

	THE DEGENERATE SEGMENT IS A REAL CASE: `from == to` happens when a monster is standing on its
	victim. `length2 <= 0` falls through to the endpoint distance test, which is correct — a
	zero-length segment is a point, and a point is inside the sphere or it is not.
]]
function CamouflageRules.smokeBlocks(from: Vec3, to: Vec3, centre: Vec3, radius: number): boolean
	if not (radius > 0 and radius < math.huge) then
		return false
	end

	local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
	local fx, fy, fz = centre.X - from.X, centre.Y - from.Y, centre.Z - from.Z
	local length2 = dx * dx + dy * dy + dz * dz

	-- How far along the segment the closest point to the centre lies, clamped to the segment itself.
	-- Unclamped, a cloud BEHIND the shooter would block a shot away from it.
	local t = if length2 > 0 then math.clamp((fx * dx + fy * dy + fz * dz) / length2, 0, 1) else 0
	local cx, cy, cz = fx - dx * t, fy - dy * t, fz - dz * t
	local closest2 = cx * cx + cy * cy + cz * cz

	if closest2 ~= closest2 then
		-- NaN anywhere upstream. Refusing to block is the safe direction: it fails towards the
		-- survivors' counterplay, never towards the monster's escape.
		return false
	end

	return closest2 <= radius * radius
end

return CamouflageRules
