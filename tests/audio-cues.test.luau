--!strict
--[[
	The cue rules (C29, §5), proven where a listen cannot reach.

	C29's real verification is a person with headphones, and that is correct for "does this sound
	scary". It is useless for the two properties that break silently:

	  · A CUE FIRING IN THE WRONG PHASE. A transform stinger during the reveal, or a dog barking over
	    the sunrise, is a bug you hear once, cannot reproduce on demand, and cannot screenshot.
	  · A MONSTER CUE REACHING SOMEBODY OUTSIDE THE ROUND. A player sitting in LOBBY who hears the
	    heartbeat has learned that a transform is happening right now, from outside the barrio. That
	    is information leaving the round, and no screenshot of the round would ever show it.

	Both are one assertion each here.
]]

local AudioCues = require("../src/shared/pure/AudioCues")

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local PHASES = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
local STATES = { "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }

print("AudioCues")

-- EVERY phase has a bed. A phase with no bed is a silent screen, and §9.3's point about the lobby
-- ("a player waiting must never see a static screen — that reads as broken") is true of silence too.
for _, phase in PHASES do
	check(`bed exists for {phase}`, AudioCues.ambienceFor(phase) ~= nil)
end

check(
	"night and lobby beds differ",
	AudioCues.ambienceFor("ACTIVE") ~= AudioCues.ambienceFor("IDLE")
)
check("ENDING has its own bed", AudioCues.ambienceFor("ENDING") ~= AudioCues.ambienceFor("ACTIVE"))

-- The returned list is a COPY. A caller that sorted or cleared it in place would silently rewrite the
-- rule for every later call in that client's session.
local first = AudioCues.oneShotsFor("ACTIVE")
table.clear(first)
check("oneShotsFor returns a copy", #AudioCues.oneShotsFor("ACTIVE") > 0)

check("ENDING schedules no one-shots", #AudioCues.oneShotsFor("ENDING") == 0)
check("unknown phase yields no one-shots", #AudioCues.oneShotsFor("NOT_A_PHASE" :: any) == 0)

-- THE HEARTBEAT'S PHASE WINDOW. It exists only while a monster can be transformed, which is ACTIVE
-- and nothing else — see the plan's preamble P1 for why this cue is transformed-only at all.
for _, phase in PHASES do
	local permitted = AudioCues.isCuePermitted("CUE_HEARTBEAT", phase, "ALIVE")
	check(`heartbeat in {phase}`, permitted == (phase == "ACTIVE"), `got {permitted}`)
end

-- THE STATE GATE. A player outside the round hears no monster cue, in any phase.
for _, state in STATES do
	local outside = state == "LOBBY" or state == "SPECTATOR"

	check(
		`heartbeat for {state}`,
		AudioCues.isCuePermitted("CUE_HEARTBEAT", "ACTIVE", state) == not outside
	)
	check(
		`stinger for {state}`,
		AudioCues.isCuePermitted("CUE_TRANSFORM", "ACTIVE", state) == not outside
	)
end

-- A dead player is in the world and can SEE the monster. Refusing them the audio would make the dead
-- audibly different from the living, which is the leak `absence-is-observable` describes.
check("dead players hear the monster", AudioCues.isCuePermitted("CUE_HEARTBEAT", "ACTIVE", "DEAD"))

-- FAILS CLOSED. An id nobody assigned phases to plays nowhere, rather than everywhere.
check("unknown cue is refused", not AudioCues.isCuePermitted("CUE_NOPE", "ACTIVE", "ALIVE"))

-- Footsteps are the one cue with no phase restriction, because they are the one cue that is a
-- CONSTANT across every player and every state. See the plan's preamble P2.
for _, phase in PHASES do
	check(`footsteps in {phase}`, AudioCues.isCuePermitted("CUE_FOOTSTEP", phase, "ALIVE"))
end

--[[
	V04, §4.4. THE NOISE CUES. Two properties, and the second is the one no playtest would show you:
	a cue heard by somebody in the LOBBY is information leaving the round, and the person who has it
	is not even in the barrio.
]]
for _, cueId in { "CUE_NOISE", "CUE_NOISE_SELF" } do
	check(`{cueId} plays during ACTIVE`, AudioCues.isCuePermitted(cueId, "ACTIVE", "ALIVE"))
	check(`{cueId} reaches the dead`, AudioCues.isCuePermitted(cueId, "ACTIVE", "DEAD"))
	check(
		`{cueId} does not reach the lobby`,
		not AudioCues.isCuePermitted(cueId, "ACTIVE", "LOBBY")
	)
	check(
		`{cueId} does not reach a spectator`,
		not AudioCues.isCuePermitted(cueId, "ACTIVE", "SPECTATOR")
	)

	for _, phase in PHASES do
		if phase ~= "ACTIVE" then
			check(
				`{cueId} is silent in {phase}`,
				not AudioCues.isCuePermitted(cueId, phase, "ALIVE")
			)
		end
	end
end

print(`  {checked - failures}/{checked} checks passed`)

if failures > 0 then
	error(`{failures} AudioCues check(s) failed`, 0)
end
