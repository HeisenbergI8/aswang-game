--!strict
--[[
	REVIEW — src/client/Controllers/AudioController.luau (78 lines, whole file read)

	The file C29 rewrites. It already owns exactly one cue and, more importantly, already owns the
	ARGUMENT for how a ranged cue should work in this game. The plan extends that argument rather than
	replacing it, with one sentence of its rationale challenged (see the geometry QUESTION below).
]]

-- src/client/Controllers/AudioController.luau:8-11
--[[
	NO ASSET ID YET, AND THAT IS DELIBERATE. Sourcing audio is C29 with the `asset-pipeline` skill, and
	inventing an ID here would either 404 at runtime or ship somebody else's sound with no licence
	trail. So the Sound instance is created, positioned and RANGED correctly, and its SoundId is left
	empty: the spatial behaviour that C04 cares about is testable now, and C29 fills in one field.
]]
-- The blank-ID contract, written down a milestone before it was needed.
-- IMPORTANT: this is the precedent the whole plan generalises. All ten cues must create, parent,
-- range, LOG and destroy identically whether or not an id exists — which is what lets Phases 1-3 be
-- verified with `Config.Audio.Assets` entirely empty, and what lets a cue the user never approves
-- ship as a blank string rather than as a code change.

-- src/client/Controllers/AudioController.luau:13-18
--[[
	WHY THE SOUND IS PARENTED TO THE TRANSFORMING CHARACTER'S HEAD
	--------------------------------------------------------------
	`Config.Monster.TransformAudioRange` (40 studs) is a fact about WHERE the transform can be heard,
	and Roblox's own rolloff is what enforces it. A sound played at the listener with a manual distance
	check would be a second, wrong answer to a question the engine already answers — and it would be
	wrong in the direction that matters, since it would ignore the geometry between the two players.
]]
-- The precedent the heartbeat follows: the ENGINE owns the falloff, not a manual distance check.
-- IMPORTANT: the load-bearing half of this reasoning is unstated here and is the half that matters
-- for C29 — a manual distance check would need the MONSTER'S POSITION ON THE CLIENT, which is the
-- leak the whole design avoids. The plan's preamble P1 promotes that to the primary reason.
-- QUESTION: "it would ignore the geometry between the two players" implies Roblox's rolloff does NOT
-- ignore geometry. I believe that is false for a classic `Sound`, which attenuates by distance with
-- no occlusion model, but nothing in this codebase establishes it either way and CLAUDE.md forbids
-- guessing a Roblox API. Step 2.1 rewrites the paragraph so the decision no longer rests on it.
-- Raised as Follow Up 2 rather than silently corrected.

-- src/client/Controllers/AudioController.luau:39-51
local existing = head:FindFirstChild(STINGER_NAME)

if existing ~= nil then
	existing:Destroy()
end

local sound = Instance.new("Sound")
sound.Name = STINGER_NAME
-- TODO(C29): a Creator Store transform stinger. Empty until then — see the header.
sound.SoundId = ""
sound.RollOffMaxDistance = Config.Monster.TransformAudioRange
sound.RollOffMode = Enum.RollOffMode.Linear
sound.Parent = head
-- The one line C29 was always going to change is line 48.
-- IMPORTANT: `STINGER_NAME` is the duplicate sentinel three lines up. The plan's `newSound` helper
-- sets `Name = cueId`, so Step 3.1 MUST re-assign `sound.Name = STINGER_NAME` afterwards or the
-- duplicate cleanup silently stops matching and a re-transform stacks two stingers on one Head.

-- src/client/Controllers/AudioController.luau:55-61
-- Local-only instance on a replicated character, so it is cleaned up here rather than left for the
-- server's FX folder teardown to find.
task.delay(Config.Monster.TransformTime + Config.Monster.RevertTime, function()
	if sound.Parent ~= nil then
		sound:Destroy()
	end
end)
-- The cleanup pattern every cue in the plan inherits, and the reason it cannot use `Sound.Ended`.
-- IMPORTANT: "local-only instance on a replicated character" is the exact property that makes the
-- heartbeat safe. A Sound the SERVER parented here would replicate and name the Aswang in the
-- instance tree with the volume at zero. The plan's Step 3.5 promotes this sentence into the
-- secrecy statement, because it is currently a cleanup comment doing security work.
-- NOTE: the nil check is also the StreamingEnabled guard — a character can stream out mid-cue and
-- take its parent with it.

-- src/client/Controllers/AudioController.luau:64-70
local function onTransformed(payload: Types.MonsterTransformedPayload)
	-- Only the transform, not the revert. A revert stinger would tell every client the exact moment a
	-- monster became a person again, which is information a witness should get by looking.
	if payload.Transformed then
		playStinger(payload.Character)
	end
end
-- IMPORTANT: this comment constrains Step 3.2. The heartbeat handles the `false` branch, and it must
-- STOP a loop rather than PLAY a revert cue — the cessation of a sound is the absence of a cue, which
-- is what this comment permits; a revert stinger is what it forbids.

-- src/client/Controllers/AudioController.luau:74-76
function AudioController.Start()
	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
end
-- NOTE: one connection today. The plan adds `RoundSnapshot` beside it, `Players.PlayerAdded`, and one
-- `task.spawn` scheduler — and adds no remote to `Remotes.luau`, which is what `check:remotes`
-- verifies at Steps 2.2 and 3.3.
-- NOTE: `Init()` is empty and stays empty. `init.client.luau` runs every Init before any Start, which
-- is what guarantees no remote handler is connected before `SkyController` captures the night; this
-- controller must not connect anything in Init either, for the same reason.
