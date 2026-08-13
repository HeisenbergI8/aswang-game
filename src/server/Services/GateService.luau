--!strict
--[[
	GateService — the escape gate, and the survivors' win. (§4.8, C11)

	🔒 THE ONE SERVICE IN THIS MILESTONE THAT READS THE SECRET, and it reads it to REFUSE a win rather
	than to grant one. §4.8: "Survivors win: 5/5 tasks done AND at least 1 survivor reaches the escape
	gate." The Aswang reaching an open gate must do nothing at all, and "nothing at all" is literal —
	no refusal, no verdict, no remote, no sound, no prompt. Read `server/pure/GateEscape.luau`'s header
	for what that does and does not conceal.

	IT DOES NOT OWN GateOpen. RoundService derives it from the task count (§6.4: RoundService owns the
	phase and everything that hangs off it), and this service reads `IsGateOpen()`. There is exactly
	one writer, and it is not here.

	ONE DIRECTION ONLY, and this is the direction. RoundService must NEVER require GateService back: a
	require cycle errors at load, init.server.luau swallows it into a single warn, and the server sits
	in IDLE forever looking exactly like "nobody has joined yet". TaskService and MonsterService both
	sit on this side of the same rule.

	NO REMOTE. The gate is reached by walking, and the server measures the walk. There is no
	`RequestEscape` and there must not be: a client-callable escape is a free win behind whatever
	validation somebody remembers to write, and proximity needs none.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local GateEscape = require(script.Parent.Parent.pure.GateEscape)
local RoundService = require(script.Parent.RoundService)
local Types = require(Shared.Types)

local GateService = {}

local TAG_GATE = "EscapeGate"

-- SERVER-ONLY. Rebuilt at every STARTING rather than cached forever, for the reason TaskService's
-- `discoverPool` gives: C17 will add, move and delete these parts while a server is running.
local gates: { BasePart } = {}

-- What the gate looked like before it opened, so closing it puts back what was there rather than a
-- guessed default. MonsterService shipped a Critical bug doing exactly the opposite — its revert
-- restored hardcoded values instead of captured state, permanently branding the ex-Aswang.
local closedLook: { [BasePart]: { Transparency: number, CanCollide: boolean } } = {}

local function discoverGates()
	table.clear(gates)

	for _, instance in CollectionService:GetTagged(TAG_GATE) do
		if not instance:IsA("BasePart") then
			warn(
				`[GateService] {instance:GetFullName()} is tagged {TAG_GATE} but is a `
					.. `{instance.ClassName}, not a BasePart — skipped.`
			)
			continue
		end

		table.insert(gates, instance)

		local captured = closedLook[instance]

		if captured == nil then
			closedLook[instance] =
				{ Transparency = instance.Transparency, CanCollide = instance.CanCollide }
		end
	end

	--[[
		UNGATED BY VerboseLogging, like every other fault in this codebase. A round can reach 5/5 and
		then be unwinnable because nothing in the map is tagged, and the only symptom a player reports
		is "we finished everything and nothing happened".
	]]
	if #gates == 0 then
		warn(
			`[GateService] NO "{TAG_GATE}" PART IN THE MAP. Tag one anchored part with "{TAG_GATE}" `
				.. `via CollectionService, or survivors can never win (spec §4.8).`
		)
	end
end

--[[
	The gate's LOOK, and it is the minimum. C11's brief asks that the opening be "an event worth
	seeing and hearing, not a boolean" — the SEEING starts here and the HEARING is not code this repo
	can write: sound and VFX live in the place file and in AudioController's C18 work. A plan step
	that said "make the gate dramatic" would not be verifiable and does not belong in a plan.

	Restores captured state rather than defaults. See `closedLook`.
]]
local function setGateLook(open: boolean)
	for _, gate in gates do
		local look = closedLook[gate]

		if open then
			gate.Transparency = 0.6 -- config-ok: placeholder gate visual, replaced at C17/C18
			gate.CanCollide = false
		elseif look ~= nil then
			gate.Transparency = look.Transparency
			gate.CanCollide = look.CanCollide
		end
	end
end

local function positionOf(player: Player): Vector3?
	local character = player.Character

	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
end

--[[
	🔒 THE WIN CHECK. Everything it reads, it reads from RoundService or from the workspace.

	The role is derived here and used immediately; it is never stored, never attributed, never tagged
	and never sent. Compare TaskService's `weightFor`, which deliberately does NOT fetch the secret
	because the pure module is proven to ignore it — here the pure module genuinely needs it, which is
	the whole reason `GateEscape` exists as a separate file with its own exhaustive grid.

	EndRound is guarded on ACTIVE inside RoundService and `enterEnding` refuses a second reveal, so
	several survivors arriving in the same tick end the round once.
]]
local function step()
	if not RoundService.IsActive() or #gates == 0 then
		return
	end

	local gateOpen = RoundService.IsGateOpen()
	local aswangUserId = RoundService.GetAswangUserId()

	for _, player in Players:GetPlayers() do
		local position = positionOf(player)

		if position == nil then
			continue
		end

		local role: Types.Role = if player.UserId == aswangUserId
			then Enums.Role.Aswang
			else Enums.Role.Survivor

		for _, gate in gates do
			if
				GateEscape.escapes({
					GateOpen = gateOpen,
					PlayerState = RoundService.GetPlayerState(player),
					Role = role,
					Distance = (position - gate.Position).Magnitude,
					Range = Config.Tasks.GateRangeStuds,
				})
			then
				if Config.Debug.VerboseLogging then
					-- A UserId, never a role, and never "who did not escape". This line is read while
					-- a round is still running.
					print(`[GateService] {player.UserId} reached the gate.`)
				end

				RoundService.EndRound(Enums.RoundResult.SurvivorsEscaped)

				return
			end
		end
	end
end

local function onPhaseChanged(phase: Types.RoundPhase)
	if phase == Enums.RoundPhase.Starting then
		discoverGates()
		setGateLook(false)
	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		setGateLook(false)
	end
end

function GateService.Init() end

function GateService.Start()
	-- At boot, not only at STARTING, so an operator learns the map has no gate while they are still
	-- looking at the output window. TaskService's `Start` makes the same argument for the same reason.
	discoverGates()

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)

	--[[
		§5's mobile budget, counted: one server-side loop at 4 Hz doing at most `#players × #gates`
		distance comparisons — eight subtractions a tick with one gate. No lights, no particles, no
		client-side per-frame work. It is also the whole reason the gate's look is polled rather than
		event-driven: one boolean read per tick is cheaper than a second BindableEvent.
	]]
	task.spawn(function()
		local wasOpen = false

		while true do
			local open = RoundService.IsGateOpen()

			if open ~= wasOpen then
				wasOpen = open
				setGateLook(open)
			end

			step()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
end

return GateService
