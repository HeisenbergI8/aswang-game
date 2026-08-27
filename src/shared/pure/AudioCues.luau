--!strict
--[[
	AudioCues — which sound belongs to which moment. (C29, §5)

		ambienceFor(phase) -> string?                       -- the looping bed for a round phase
		oneShotsFor(phase) -> { string }                    -- wind/dogs eligible in that phase
		isCuePermitted(cueId, phase, state) -> boolean      -- may this cue fire at all

	§5: "Audio matters more than visuals in horror… the cheapest fear-per-hour you can buy." This
	module is the part of that sentence a terminal can check. It owns no Sound, no Instance and no
	clock — `AudioController` plays cues, `RoundService` owns the phase (§6.4), and this answers
	"which one, and is it allowed" over plain strings.

	NOTHING SECRET PASSES THROUGH HERE, and that is structural rather than careful: the inputs are a
	phase and the RECEIVER'S OWN state, both of which are already on every client's `RoundSnapshot`.
	There is no role parameter and no player parameter, so there is no arrangement of this module in
	which two clients in the same phase get different answers. `.claude/lessons/absence-is-observable`
	is the long version — in this game the leak is a DIFFERENCE between players, and a rule that
	cannot see a player cannot produce one.

	This module is REQUIRABLE AND CALLABLE BY ANY CLIENT (`src/shared` maps wholesale into
	ReplicatedStorage) and that costs nothing: a table saying "crickets play at night" publishes
	nothing that is not audible.

	NO `script.Parent` REQUIRES (tests/README.md), so no Types, no Enums, no Config. `RoundPhase` and
	`PlayerState` are re-declared — Luau unions are structural, so these and the `Types.` ones are the
	same type. Every ASSET ID and every DURATION lives in `Config.Audio`; this file holds only the
	mapping, so C29's sourcing pass and M12's tuning never touch it.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"

local AudioCues = {}

--[[
	THE BEDS. One per phase, and the lobby shares INTERMISSION's deliberately: a player waiting must
	never experience a silent screen for the same reason C24 says they must never see a static one —
	silence reads as broken, not as waiting.

	Keyed by plain `string` rather than by `RoundPhase`, because a literal union in a table-VALUE or
	table-KEY annotation resolves to plain `string` anyway (the C21 lesson's sixth failed fix). The
	union is enforced at the PARAMETER, which is where it works.
]]
local BEDS: { [string]: string } = {
	IDLE = "CUE_BED_LOBBY",
	INTERMISSION = "CUE_BED_LOBBY",
	STARTING = "CUE_BED_NIGHT",
	ACTIVE = "CUE_BED_NIGHT",
	ENDING = "CUE_BED_DAWN",
}

-- Wind is always plausible; distant dogs belong to the barrio at night and would undercut the reveal
-- if they kept barking over it, so ENDING gets neither and lets the sunrise cue own the moment.
local ONE_SHOTS: { [string]: { string } } = {
	IDLE = { "CUE_WIND" },
	INTERMISSION = { "CUE_WIND" },
	STARTING = { "CUE_WIND", "CUE_DOGS" },
	ACTIVE = { "CUE_WIND", "CUE_DOGS" },
	ENDING = {},
}

--[[
	WHICH PHASES EACH EVENT CUE MAY FIRE IN. A cue absent from this table is refused everywhere, so
	adding a cue id without deciding its phases fails closed rather than playing during the reveal.

	`CUE_FOOTSTEP` IS THE ONE ROW WITH NO CALLER, AND THAT IS DELIBERATE. Every other id here is
	checked by `AudioController` before its cue plays. Footsteps are not, because gating them by
	phase or state is precisely the thing that would break them: they are safe only as a CONSTANT
	across every player, and a rule that can refuse them for some players and not others is a
	difference (`.claude/lessons/absence-is-observable`). The row exists to say "no restriction, in
	any phase" in the same place every other cue's restriction is written, and the test pins it.

	The C29 exploit audit read this row as dead and it was right to ask — until that audit the
	STINGER's row was dead too, in a file whose header claimed the opposite. That one is now called.
]]
local PERMITTED_PHASES: { [string]: { [string]: boolean } } = {
	CUE_TRANSFORM = { STARTING = true, ACTIVE = true },
	CUE_HEARTBEAT = { ACTIVE = true },
	CUE_SUNRISE = { ACTIVE = true, ENDING = true },
	--[[
		V04, §4.4. ACTIVE ONLY, because nothing can make noise outside it — `NoiseService.Emit`
		refuses every other phase, and this row is the second half of that statement rather than a
		restriction on top of it.

		BOTH IDS ARE PERMITTED ON IDENTICAL TERMS FOR EVERY PLAYER IN THE ROUND. There is no role
		branch, no form branch and no per-player exception, for `CUE_FOOTSTEP`'s reason two rows
		down: a rule that can refuse a cue for some players and not others is a difference, and in
		this game a difference IS the leak (`.claude/lessons/absence-is-observable.md`).
	]]
	CUE_NOISE = { ACTIVE = true },
	CUE_NOISE_SELF = { ACTIVE = true },
	CUE_FOOTSTEP = {
		IDLE = true,
		INTERMISSION = true,
		STARTING = true,
		ACTIVE = true,
		ENDING = true,
	},
}

--[[
	THE STATE GATE, AND THE ONE RULE IN IT THAT IS A SECRECY RULE.

	A player in LOBBY or SPECTATOR is not in the round. They must not hear the monster — not the
	stinger, not the heartbeat — because a cue is information, and information reaching somebody
	outside the round is information reaching a Discord call. §4.3's tell is for players who are in
	the barrio and can be killed by it.

	DEAD is allowed. A dead player is still in the world spectating and can already SEE a transformed
	monster; refusing them the audio would remove nothing and would make dead players audibly
	different from living ones, which is the failure mode `absence-is-observable` names.

	V04 RENAMED THIS FROM `MONSTER_CUES`, and the rename is the honest version of what it always
	was: the rule is "must not reach somebody outside the round", and the monster's cues were simply
	the only members. §4.4's noise cues need the same rule for the same reason — a lobby player
	hearing a search knows somebody is out there arming themselves, from outside the barrio. The
	server already refuses them (NoiseService.dispatchCue), so this is the second lock rather than
	the first.
]]
local ROUND_ONLY_CUES: { [string]: boolean } = {
	CUE_TRANSFORM = true,
	CUE_HEARTBEAT = true,
	CUE_NOISE = true,
	CUE_NOISE_SELF = true,
}

local OUTSIDE_THE_ROUND: { [string]: boolean } = {
	LOBBY = true,
	SPECTATOR = true,
}

-- The looping bed for a phase, or nil if the phase has none. Nil is a legitimate answer and the
-- caller stops its bed rather than treating it as an error.
function AudioCues.ambienceFor(phase: RoundPhase): string?
	return BEDS[phase]
end

--[[
	`{ string }`, NOT `{ AudioCueId }`, and never `{ Types.AudioCueId }`. A literal union survives
	`require` as a scalar and does NOT survive it inside a list: the element arrives as a union of
	plain strings, `::` widens every option rather than narrowing, and the analyzer reports it in the
	CALLING file. See `.claude/lessons/pure-module-unions-widen-in-lists.md`. The caller narrows by
	LOOKUP — `Config.Audio.Assets[id]` returns nil for an unknown id — which is a function, not a
	cast, and drops the bad id with a warn instead of waving it onward.
]]
function AudioCues.oneShotsFor(phase: RoundPhase): { string }
	local ids = ONE_SHOTS[phase]

	if ids == nil then
		return {}
	end

	return table.clone(ids)
end

function AudioCues.isCuePermitted(cueId: string, phase: RoundPhase, state: PlayerState): boolean
	local phases = PERMITTED_PHASES[cueId]

	if phases == nil or not phases[phase] then
		return false
	end

	if ROUND_ONLY_CUES[cueId] and OUTSIDE_THE_ROUND[state] then
		return false
	end

	return true
end

return AudioCues
