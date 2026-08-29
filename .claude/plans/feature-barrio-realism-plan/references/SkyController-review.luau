--!strict
--[[
	REVIEW — src/client/Controllers/SkyController.luau

	Read to resolve the brief's stated trap: "any lighting change must be reconciled with SkyController
	or it will be overwritten at runtime". NOT changed by this plan.

	THE TRAP IS REAL BUT IT IS NOT WHAT IT LOOKS LIKE. The controller does not blindly overwrite the
	builder — it CAPTURES the builder's night as its baseline. Getting this backwards in either
	direction breaks Phase 8.
]]

--------------------------------------------------------------------------------
-- src/client/Controllers/SkyController.luau:34-42  — THE CAPTURE, stated by the author
--------------------------------------------------------------------------------

--	═══ THE NIGHT IS CAPTURED, NOT WRITTEN ═════════════════════════════════════
--
--	`tools/greybox/barrio.luau` authors the barrio's night — ambient, fog, the Atmosphere — and C30
--	will retune it. So this controller reads those four values ONCE at startup and treats them as the
--	baseline it lerps away from and back to. `Config.Sky` holds only the destination.

-- IMPORTANT: this is the single most decision-relevant comment for Phase 8. Retuning the night in
-- `barrio.luau` is CORRECT AND SUPPORTED — the controller picks the new values up. The brief's warning
-- that changes "will be overwritten at runtime" is true only for `ClockTime` and only in the sense
-- that the round drives it deliberately.
-- NOTE: it says "four values" and the code below captures FIVE (Brightness, FogEnd, Ambient,
-- OutdoorAmbient, Atmosphere.Density). Minor doc drift in the source; the code is authoritative.

--------------------------------------------------------------------------------
-- src/client/Controllers/SkyController.luau:88-113  — WHAT IS CAPTURED, exactly
--------------------------------------------------------------------------------

		NightBrightness = Lighting.Brightness,
		NightFogEnd = Lighting.FogEnd,
		NightAtmosphereDensity = if air ~= nil then air.Density else 0,
		NightAmbientRgb = { Lighting.Ambient.R * 255, ... },
		NightOutdoorAmbientRgb = { Lighting.OutdoorAmbient.R * 255, ... },

-- THE FIVE CAPTURED PROPERTIES. Everything else in Lighting is unowned at runtime.
-- IMPORTANT: this yields the exact rule Phase 8 works to.
--   CAPTURED (builder authors, controller lerps from):  Brightness, FogEnd, Ambient, OutdoorAmbient,
--                                                       Atmosphere.Density
--   ROUND-OWNED (do not treat as an art value):         ClockTime  (Config.Sky.StartClockTime = 3.0)
--   UNOWNED (builder owns outright, no runtime fight):  EnvironmentDiffuseScale, EnvironmentSpecular-
--                                                       Scale, GlobalShadows, FogColor, and the
--                                                       Atmosphere's Color, Decay, Glare, Haze
-- NOTE: Step 8.2 deliberately spends most of its budget in the third row, because those have no
-- runtime owner and cannot be surprised by a round starting.

--	The Atmosphere is OPTIONAL and its absence is not an error.

-- NOTE: `atmosphere()` uses FindFirstChildWhichIsA and tolerates nil, and the capture defaults Density
-- to 0. So a place with no Atmosphere still produces a valid cycle. The builder creates one, so this
-- is defensive rather than load-bearing — but it means Phase 8 must not ASSUME the Atmosphere exists
-- when reasoning about what a fresh place looks like.

--------------------------------------------------------------------------------
-- src/client/Controllers/SkyController.luau:129-142  — CAPTURED AT START, NOT POLLED
--------------------------------------------------------------------------------

		Lighting.ClockTime = frame.ClockTime
		Lighting.Brightness = frame.Brightness
		Lighting.FogEnd = frame.FogEnd
		Lighting.Ambient = rgb(frame.AmbientRgb)
		Lighting.OutdoorAmbient = rgb(frame.OutdoorAmbientRgb)

-- IMPORTANT and operationally sharp: the capture happens ONCE, at Start. A lighting change made in
-- `barrio.luau` while a play session is already running is INVISIBLE until the session restarts —
-- the controller is still lerping from the baseline it captured at join.
-- IMPORTANT: so the Phase 8 loop is: edit barrio.luau -> re-run it in EDIT mode -> restart the play
-- session -> judge. Judging without the restart produces "my change did nothing", which looks exactly
-- like a typo and will cost an hour. Listed in Phase 8's Potential Issues for that reason.

--------------------------------------------------------------------------------
-- SECRECY — src/client/Controllers/SkyController.luau:26-31 and :12-15
--------------------------------------------------------------------------------

--	THE SKY IS IDENTICAL ON EVERY SCREEN AND THAT IS LOAD-BEARING, not incidental. It is driven from a
--	snapshot every client receives, through a pure function with no role input and no local state — so
--	there is no arrangement of this code in which one player's dawn arrives differently from another's.
--	`.claude/lessons/absence-is-observable.md` is the long version: in this game a DIFFERENCE between
--	players is the leak, and the sky is the largest surface in the game to leak one across.

-- IMPORTANT: the constraint Phase 8 inherits. Nothing in this plan may make lighting depend on who is
-- looking. "The Aswang sees better at night" is a leak, not a feature — it would be readable by
-- comparing two screens, and no remote would carry it for `check:secrecy` to see.
-- NOTE: the builder is safe here by construction. It runs once, in Edit mode, before any player
-- exists, and writes a single global Lighting state. There is no per-player path to misuse.

--	WHAT THIS CONTROLLER OWNS: `Lighting`, on this client, and nothing else. It cannot end a round,
--	cannot advance a phase and cannot tell the server anything.

-- NOTE: the test this repo applies to every controller — delete it and every server outcome is
-- identical. Worth remembering if Phase 8 is ever tempted to move lighting work server-side to "fix"
-- the restart-to-see-it problem above. That would spend replication on a picture and buy nothing.
