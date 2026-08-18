--!strict
--[[
	SkyController — the round timer, rendered as a sunrise. (C28, Appendix C.3)

	THE ONE FEATURE APPENDIX C SAYS TO STEAL. The competitor this project was scoped against built a
	"dynamic sunset-to-night" cycle, shipped it as atmosphere, and got nothing from it. §C.3's
	instruction is to point it at the round: **the sky visibly progressing toward sunrise IS the
	countdown.** No UI, no remote, no new network surface — and a player who is being chased is
	looking at the world rather than at the corner of their screen, which is exactly when a HUD timer
	stops being read.

	WHAT THIS CONTROLLER OWNS: `Lighting`, on this client, and nothing else. It cannot end a round,
	cannot advance a phase and cannot tell the server anything. Delete it and every outcome the server
	produces is identical — the test this codebase applies to any controller.

	═══ WHY IT RUNS ON THE CLIENT ══════════════════════════════════════════════

	`Lighting` replicates, so the server could drive it and every client would follow. Three reasons
	it does not:

	  · it is presentation, and this project's whole client contract is "controllers own presentation,
	    never truth". A server writing five Lighting properties twice a second is server work spent on
	    a picture.
	  · it costs replication for something every client can already derive: `RoundSnapshot` carries
	    `Phase` and `SecondsRemaining` and is already being sent.
	  · a client can restore its own night without asking. See the capture below.

	THE SKY IS IDENTICAL ON EVERY SCREEN AND THAT IS LOAD-BEARING, not incidental. It is driven from a
	snapshot every client receives, through a pure function with no role input and no local state — so
	there is no arrangement of this code in which one player's dawn arrives differently from another's.
	`.claude/lessons/absence-is-observable.md` is the long version: in this game a DIFFERENCE between
	players is the leak, and the sky is the largest surface in the game to leak one across.

	═══ THE NIGHT IS CAPTURED, NOT WRITTEN ═════════════════════════════════════

	`tools/greybox/barrio.luau` authors the barrio's night — ambient, fog, the Atmosphere — and C30
	will retune it. So this controller reads those four values ONCE at startup and treats them as the
	baseline it lerps away from and back to. `Config.Sky` holds only the destination.

	That is C04's bug avoided by construction rather than by care: `MonsterService`'s revert once
	restored HARDCODED DEFAULTS instead of captured state, and permanently branded an ex-Aswang with
	the monster's colour. A sky that returned to a hardcoded night would do the same thing to the
	whole map, one shade per round, and nothing on screen would name it.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local SkyCycle = require(Shared.pure.SkyCycle)
local Types = require(Shared.Types)

local SkyController = {}

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3]) -- config-ok: R/G/B indices, not tunables
end

--[[
	The Atmosphere is OPTIONAL and its absence is not an error.

	`barrio.luau` creates one, but a place built before C17 — or a fresh file someone is testing a
	single system in — has none, and a controller that errored on a missing decoration would take the
	sky down with it. Every write to it is guarded; the rest of the frame still lands.
]]
local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildWhichIsA("Atmosphere")
end

--[[
	THE CAPTURE. Read once, at Start, before anything has been driven.

	`ClockTime` is deliberately NOT captured. It is the one term the round owns outright: the place
	authors midnight so the map looks right in Studio, and `Config.Sky.StartClockTime` is where a
	ROUND begins — see that field's comment for why 3am rather than midnight is the readable end of
	the cycle. Everything else here belongs to the art direction and is borrowed, not replaced.
]]
local captured: SkyCycle.Params? = nil

local function capture(): SkyCycle.Params
	local air = atmosphere()

	return {
		NightClockTime = Config.Sky.StartClockTime,
		DawnClockTime = Config.Sky.EndClockTime,

		NightBrightness = Lighting.Brightness,
		DawnBrightnessMult = Config.Sky.DawnBrightnessMult,

		NightFogEnd = Lighting.FogEnd,
		DawnFogEndMult = Config.Sky.DawnFogEndMult,

		-- The default is what `barrio.luau` writes, so a place with no Atmosphere still produces a
		-- frame whose numbers are sane and simply has nothing to apply them to.
		NightAtmosphereDensity = if air ~= nil then air.Density else 0,
		DawnAtmosphereDensityMult = Config.Sky.DawnAtmosphereDensityMult,

		NightAmbientRgb = {
			Lighting.Ambient.R * 255, -- config-ok: Color3 channels are 0-1, RGB triples are 0-255
			Lighting.Ambient.G * 255, -- config-ok: Color3 channel conversion
			Lighting.Ambient.B * 255, -- config-ok: Color3 channel conversion
		},
		DawnAmbientRgb = Config.Sky.DawnAmbientRgb,

		NightOutdoorAmbientRgb = {
			Lighting.OutdoorAmbient.R * 255, -- config-ok: Color3 channel conversion
			Lighting.OutdoorAmbient.G * 255, -- config-ok: Color3 channel conversion
			Lighting.OutdoorAmbient.B * 255, -- config-ok: Color3 channel conversion
		},
		DawnOutdoorAmbientRgb = Config.Sky.DawnOutdoorAmbientRgb,
	}
end

--[[
	WHEN THE SKY MOVES IN A STEP AND WHEN IT MOVES IN A TWEEN.

	A round advances the sky by `SnapshotInterval / Duration` per push — about a thousandth — which is
	invisible as a step and costs nothing to assign. Tweening it would allocate two Tween objects
	twice a second for seven minutes to smooth something no eye can resolve.

	The jumps are the interesting case, and there are exactly two: a round ENDING (progress pinned to
	1, which from an aborted round is a leap) and the lobby afterwards (back to 0). Those are the only
	times the sky is tweened, over `Config.Sky.RestoreSeconds`, because a hard cut to midnight under
	the reveal is a flicker at the moment §4.8 calls "the screenshot people share".
]]
local lastProgress: number? = nil

local function applyFrame(frame: SkyCycle.Frame, seconds: number)
	local air = atmosphere()

	if seconds <= 0 then
		Lighting.ClockTime = frame.ClockTime
		Lighting.Brightness = frame.Brightness
		Lighting.FogEnd = frame.FogEnd
		Lighting.Ambient = rgb(frame.AmbientRgb)
		Lighting.OutdoorAmbient = rgb(frame.OutdoorAmbientRgb)

		if air ~= nil then
			air.Density = frame.AtmosphereDensity
		end

		return
	end

	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	TweenService:Create(Lighting, info, {
		ClockTime = frame.ClockTime,
		Brightness = frame.Brightness,
		FogEnd = frame.FogEnd,
		Ambient = rgb(frame.AmbientRgb),
		OutdoorAmbient = rgb(frame.OutdoorAmbientRgb),
	}):Play()

	if air ~= nil then
		TweenService:Create(air, info, { Density = frame.AtmosphereDensity }):Play()
	end
end

local function onSnapshot(snapshot: Types.ClientRoundSnapshot)
	local params = captured

	if params == nil then
		return
	end

	local progress = SkyCycle.progressFor({
		Phase = snapshot.Phase,
		SecondsRemaining = snapshot.SecondsRemaining,
		Duration = Config.Round.Duration,
	})

	if progress == lastProgress then
		return
	end

	local previous = lastProgress
	lastProgress = progress

	local jumped = previous ~= nil
		and math.abs(progress - previous) > Config.Sky.TweenAboveProgressDelta

	applyFrame(SkyCycle.frameFor(progress, params), if jumped then Config.Sky.RestoreSeconds else 0)
end

function SkyController.Init() end

function SkyController.Start()
	--[[
		Captured before the first snapshot can arrive, which is what `init.client.luau`'s two-phase
		lifecycle buys: every Init has run and no remote handler is connected yet. If the map streams
		in later and re-authors the night, this baseline is the one it had at join — a real
		limitation, and the honest fix if C30 ever needs it is to re-capture on a signal rather than
		to poll.
	]]
	captured = capture()

	--[[
		THE SAME REMOTE THE HUD RENDERS FROM, and no new one. C28 adds nothing to the network surface:
		`check:remotes` has no new name to learn and `check:secrecy` has no new payload to argue with,
		because the sky is derived from two fields every client already had.
	]]
	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
end

return SkyController
