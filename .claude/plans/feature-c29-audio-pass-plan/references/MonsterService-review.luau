--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (1088 lines; read the broadcast, the revert and
	the state shape — lines 70-106, 380-476, 990-1000)

	READ ONLY. C29 changes nothing here. This service is reviewed because it is the SOURCE of both
	monster cues, and because two of its guarantees decide the heartbeat's stop conditions.
]]

-- src/server/Services/MonsterService.luau:82-84
-- MonsterTransformed(true) was broadcast. A revert broadcasts false ONLY if this is set; otherwise
-- clients receive a revert for a transform they never saw, which at C14 is a free identity leak.
Announced: boolean,
-- IMPORTANT: THE REVERT BROADCAST IS NOT GUARANTEED. This is the single most load-bearing fact for
-- the heartbeat. A client cannot treat `Transformed = false` as an event that always arrives, so the
-- heartbeat needs stop conditions that do not depend on it (plan Step 3.2 uses three).

-- src/server/Services/MonsterService.luau:429-437
--[[
	ANNOUNCE ONLY WHAT WAS ANNOUNCED. `Transformed` is set before the windup so the spam race is
	closed, which means a revert during the windup reaches here for a player NO CLIENT EVER SAW
	TRANSFORM. Broadcasting a revert for them is an unconditional identity broadcast — inert today,
	and at C14 it is "throw salt at a suspect mid-windup and be told whether you were right".
]]
if monster.Announced and character ~= nil then
	local payload: Types.MonsterTransformedPayload =
		{ Character = character, Transformed = false }
-- The exact guard. `character ~= nil` is the second condition and the one C29 must survive.
-- IMPORTANT: if the character is gone, no stop arrives — but the heartbeat is parented to that
-- character's Head, so it dies with it. That is why the plan parents the loop to the character rather
-- than to the listener: the dangerous case cleans itself up.
-- NOTE: the symmetry is worth copying. This service refuses to announce a revert for a transform
-- nobody saw; the client correspondingly starts no heartbeat for a transform it never received (a
-- player who joins mid-transform). A missing cue is safe; a stale one is not.

-- src/server/Services/MonsterService.luau:447-476
--[[
	THE BROADCAST AND ITS TEACHING CUE, IN ONE PLACE, SO THEIR AUDIENCES CANNOT DIVERGE.

	`MonsterTransformed` is public by design — the tell is the point (§4.3) — and it is
	`FireAllClients`. ...

	NARROWING THE CUE BY PROXIMITY IS THE MISTAKE AVAILABLE HERE, and it would look like an
	improvement: only tell players who can actually see it. That subset is computed from the ASWANG'S
	POSITION and delivered per-player — and because the cue is FIRE-ONCE, it would leave a permanent
	per-client mark of "I was near the first transform", outliving the broadcast that justified it.
]]
local function announceTransform(payload: Types.MonsterTransformedPayload)
	local audience = Players:GetPlayers()

	transformedRemote:FireAllClients(payload)
-- IMPORTANT: this paragraph is the precedent that decides the heartbeat's design B rejection. A
-- server-side "who is near the monster" computation delivered per-player was ALREADY considered here,
-- for a gentler cue than a heartbeat, and refused. C29's server-gated heartbeat is the same shape
-- with a worse payoff, so it is refused for the same reason (plan preamble P1).
-- IMPORTANT: `FireAllClients` is what makes the client-side heartbeat safe. Every client already
-- knows this character transformed; the cue adds no recipient and no fact.

-- src/server/Services/MonsterService.luau:990-995 (paraphrased context)
-- ... already public — `MonsterTransformed` broadcasts it to every client by design. What makes it
-- safe ...
-- NOTE: the transformed LOOK is applied server-side and replicates — scale, tint, a head PointLight
-- from `Config.Monster.EyeGlowRgb`, a particle emitter. So a transformed character is visibly a
-- monster on every screen, which is the second half of why an audio cue scoped to that state
-- publishes nothing new.

-- Config dependencies the plan reads (src/shared/Config.luau:78-84)
-- MaxTransformTime = 8    -- forced revert if no kill
-- RevertTime = 1.0
-- TransformAudioRange = 40
-- NOTE: the heartbeat's hard timeout is `MaxTransformTime + RevertTime`, composed from existing
-- fields rather than a new Config number — the longest a transform can physically last.
-- IMPORTANT: `TransformAudioRange = 40` is §4.3's stated tell range, and
-- `Config.Audio.HeartbeatRange` is pinned at or below it in `tests/config.test.luau`. Without that
-- pin, tuning the heartbeat would quietly extend the tell without touching the field that documents
-- it.
