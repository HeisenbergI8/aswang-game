--!strict
--[[
	REVIEW — src/client/Controllers/PerformanceController.luau

	Read to establish the light cap this plan must respect, and to find the FPS readout Steps 4.4 and
	8.3 depend on. NOT changed by this plan.
]]

--------------------------------------------------------------------------------
-- src/client/Controllers/PerformanceController.luau:64 and :282-295
--------------------------------------------------------------------------------

local TAG_MAP_LIGHT = "MapLight"

for _, instance in CollectionService:GetTagged(TAG_MAP_LIGHT) do
	track(instance)
end

CollectionService:GetInstanceAddedSignal(TAG_MAP_LIGHT):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG_MAP_LIGHT):Connect(untrack)

-- The culler only ever sees lights the greybox tagged. It keeps the nearest
-- `Config.Performance.MaxVisibleLights` lit and darkens the rest, per client, by camera distance.
-- IMPORTANT: BOTH signals are connected because `StreamingEnabled` is on and the barrio's far half is
-- genuinely absent from a client's DataModel most of the time. A one-shot scan at Start would cull an
-- empty list forever on a map larger than the streaming radius.
-- NOTE for this plan: any light the builder adds is picked up automatically IF tagged. The builder's
-- own `assert(mapLights == totalLights)` is what guarantees the tagging. The two mechanisms together
-- mean this plan does not need to touch the controller at all — which is why it does not.

--------------------------------------------------------------------------------
-- src/client/Controllers/PerformanceController.luau:25-31  — THE TAG IS A SECRECY BOUNDARY
--------------------------------------------------------------------------------

--	It only ever sees lights the greybox tagged `MapLight`. The Aswang's eye glow

-- IMPORTANT: `MapLight` marks a light as SCENERY, which is the client's permission to SWITCH IT OFF.
-- The Aswang's eye glow and a salt pouch's glow are TELLS — §4.3's warning and §4.6's counterplay —
-- and they are protected by NEVER BEING TAGGED, rather than by a rule somebody could relax.
-- IMPORTANT: so the tag is load-bearing in BOTH directions and this plan must be careful in both.
--   Tag a gameplay light  -> the culler darkens the only warning a survivor gets.
--   Forget to tag scenery -> the builder's third assert fails the build (which is the safe direction).
-- NOTE: this plan adds NO new lights at all. Every new emissive thing — banderitas bulbs, grave
-- candles, any chapel interior glow — is `Neon` GEOMETRY, which costs no light slot and cannot be
-- culled. That is a deliberate design choice repeated at four separate sites in the plan.

--------------------------------------------------------------------------------
-- Config.luau:1093 and :1101-1108  — THE NUMBERS
--------------------------------------------------------------------------------

		MaxVisibleLights = 8,

--			the culler is never shown them: it only ever sees lights the greybox tagged `MapLight`,

-- The cap. Fourteen `MapLight`s exist in the barrio; eight are lit at once, by distance.
-- IMPORTANT: §5 names many point lights as the #1 mobile FPS killer, and the lanterns meet the cap
-- BY SPACING rather than by count — twelve spread over 360 studs at range 26 means two or three are
-- in view at a time. That is what lets the cap and §5's sightline rule ("you should almost always be
-- able to see *something*") hold simultaneously.
-- IMPORTANT for research-04's suggestion to raise lantern posts toward the sourced 5-8 m: post height
-- changes what each light REACHES, which changes how many are in view, which is the mechanism holding
-- the cap. Do not change post height without re-reading the cull behaviour. Flagged, not recommended.
-- NOTE: research-04's OTHER suggestion — mixing sodium ~2000 K and LED ~4000 K across the twelve — is
-- free by comparison. It changes `Color3` only. No count, no spacing, no range, no cull behaviour.

--------------------------------------------------------------------------------
-- src/client/Controllers/PerformanceController.luau:260-278 and :303-306  — THE FPS READOUT
--------------------------------------------------------------------------------

	local fps = math.round(frames / elapsed)

	label.Text = `{fps} fps · {lit} lit`
	label.TextColor3 = if fps >= Config.Performance.TargetFPSMobile then COLOUR.Ok else COLOUR.Under

	if Config.Debug.VerboseLogging then
		trackFps(buildReadout())
	end

-- The on-screen readout Steps 4.4 and 8.3 depend on. It reports BOTH fps and the number of lights
-- currently lit, which is exactly the pair this plan needs.
-- IMPORTANT: it only exists when `Config.Debug.VerboseLogging` is true — a debug value `check:debug`
-- refuses to let anyone commit. So the loop is: set it, run, read, REVERT, and confirm with
-- `git diff src/shared/Config.luau`. `guard-commit.mjs` runs `check:debug`, so a forgotten flag costs
-- a blocked commit rather than reaching history — but it is still a wasted cycle.
-- IMPORTANT: this readout is measured on whatever device is running it. On a desktop Studio session it
-- is NOT evidence about a phone. §5 says "tested on a real phone at 30fps", and Step 8.3 says plainly
-- that a human with an Android device closes that check. Reporting the desktop number as if it
-- answered the mobile question is the specific dishonesty to avoid here.
-- NOTE: `TargetFPSMobile` is what the colour threshold compares against, so the readout is already
-- calibrated to the right target even when it is running on the wrong device.
