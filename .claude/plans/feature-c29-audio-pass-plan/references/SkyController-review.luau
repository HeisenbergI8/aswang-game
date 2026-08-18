--!strict
--[[
	REVIEW — src/client/Controllers/SkyController.luau (209 lines, whole file read)

	READ ONLY. C29 changes nothing here. This is the PRECEDENT the audio plan copies wholesale: C28
	rendered the round clock as a sunrise with no remote, no server work, and a pure module deciding
	the mapping. Every structural decision in the C29 plan has an ancestor in this file.
]]

-- src/client/Controllers/SkyController.luau:16-19
--[[
	WHAT THIS CONTROLLER OWNS: `Lighting`, on this client, and nothing else. It cannot end a round,
	cannot advance a phase and cannot tell the server anything. Delete it and every outcome the server
	produces is identical — the test this codebase applies to any controller.
]]
-- IMPORTANT: the same test must pass for AudioController after C29. Delete it and every server
-- outcome is identical. If any phase of the plan makes that untrue, the phase is wrong.

-- src/client/Controllers/SkyController.luau:30-36
--[[
	THE SKY IS IDENTICAL ON EVERY SCREEN AND THAT IS LOAD-BEARING, not incidental. It is driven from a
	snapshot every client receives, through a pure function with no role input and no local state — so
	there is no arrangement of this code in which one player's dawn arrives differently from another's.
	`.claude/lessons/absence-is-observable.md` is the long version: in this game a DIFFERENCE between
	players is the leak, and the sky is the largest surface in the game to leak one across.
]]
-- IMPORTANT: the ambient bed inherits this argument verbatim, and the plan quotes it. Audio is the
-- SECOND largest surface to leak a difference across — it reaches players who are not looking at
-- anything. The bed therefore takes no role input and no per-player input, and the only asymmetry in
-- the whole plan (LOBBY/SPECTATOR hear no monster cue) withholds from outside the round rather than
-- granting inside it.

-- src/client/Controllers/SkyController.luau:160-170
local progress = SkyCycle.progressFor({
	Phase = snapshot.Phase,
	SecondsRemaining = snapshot.SecondsRemaining,
	Duration = Config.Round.Duration,
})

if progress == lastProgress then
	return
end
-- The exact call the sunrise CUE reuses (plan Step 3.4).
-- IMPORTANT: reuse this call rather than re-deriving progress. The sound and the sky must agree about
-- when dawn is; two independent derivations drift and nothing would report it.
-- NOTE: the early-return-on-unchanged idiom is worth copying for the bed — `setBed` returns early
-- when the cue id is unchanged, which matters because IDLE and INTERMISSION share a bed and a naive
-- implementation would restart the loop on every intermission tick.

-- src/client/Controllers/SkyController.luau:186-193
--[[
	THE SAME REMOTE THE HUD RENDERS FROM, and no new one. C28 adds nothing to the network surface:
	`check:remotes` has no new name to learn and `check:secrecy` has no new payload to argue with,
	because the sky is derived from two fields every client already had.
]]
Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
-- IMPORTANT: this is the sentence the C29 plan's overview mirrors. "What the client is told: nothing
-- new." C29 derives from four snapshot fields (Phase, SecondsRemaining, GateOpen, YourState) plus a
-- broadcast that already exists.

-- src/client/Controllers/SkyController.luau:38-49
--[[
	THE NIGHT IS CAPTURED, NOT WRITTEN
	`tools/greybox/barrio.luau` authors the barrio's night ... So this controller reads those four
	values ONCE at startup and treats them as the baseline it lerps away from and back to.
	... That is C04's bug avoided by construction rather than by care: `MonsterService`'s revert once
	restored HARDCODED DEFAULTS instead of captured state, and permanently branded an ex-Aswang ...
]]
-- NOTE: C29 has no equivalent capture — it creates its own Sounds and destroys them, rather than
-- borrowing and restoring a property of the place. The C04 analogue in audio is a LOOP THAT OUTLIVES
-- ITS STATE, which is the heartbeat's three stop conditions (plan Step 3.2). Same bug, different
-- mechanism.
-- NOTE: `barrio.luau` lives in `tools/greybox/`, so the map's authored state IS partly in Git after
-- all — worth knowing before repeating "the map is not code" too broadly. Geometry and the place file
-- are not; this generator is.
