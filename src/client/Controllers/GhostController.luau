--!strict
--[[
	GhostController — the ghost's body, and it lives ENTIRELY on this client (§4.7, C15).

	WHY THE BODY IS HERE AND NOT ON THE SERVER. C15 first gave ghosts real server characters, because
	§4.7 needs a ghost to have a position. An exploit audit killed that: a server character replicates,
	so `Transparency = 1` hid pixels but not existence — a player-named Model per dead player let any
	client enumerate the dead, and since the Aswang can never be a ghost, every one of them eliminated a
	candidate. That is the death oracle Amendment A3 removed `AlivePlayerCount` to close.

	INSTANCES CREATED ON A CLIENT DO NOT REPLICATE. Everything this file builds exists only in this
	player's own DataModel — the server never sees it and no other client ever sees it. A living
	player's machine has no ghost object on it at all, so there is nothing to find by iterating
	`workspace`, nothing to fingerprint by transparency, and no raycast question to answer.

	WHAT CROSSES THE WIRE, in full:
	  · IN  — `GhostRoster`, fired only to ghosts, carrying dead UserIds.
	  · OUT — `ReportGhostPosition`, this body's position, so the server can price task contribution
	          (§4.7's 25%) and place the spook. The server refuses it unless it already believes this
	          player is a ghost, and refuses a jump larger than `FlySpeed` allows.

	THE HONEST LIMIT: this client owns its own position and can lie about it. What that buys is
	standing at a task point you are not at, for a quarter of one player's contribution rate. What it
	replaces is every living client knowing exactly who is dead. That trade is the whole design.

	⚠️ WHAT IS NOT BUILT YET, so nobody reads this file as finished:
	  · The peer bodies are grey blocks. Rendering a ghost as anything more is C34's job.
	  · There is no ghost HUD, no "you are dead" state, and no spook button — C18.
	  · Flight is `BodyVelocity`-free: the body is CFramed directly from input each frame, which is the
	    simplest thing that works on a client-owned object. It has not been tested with a real player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local GhostController = {}

local LOCAL_PLAYER = Players.LocalPlayer

-- Everything this controller creates goes under one parent, so leaving the ghost state is one Destroy
-- and there is no chance of orphaning a peer body. Same shape as the server's Corpses/Husks folders.
local root: Folder? = nil
local body: BasePart? = nil
local peers: { [number]: BasePart } = {}

local isGhost = false
local lastReportAt = 0

local function ensureRoot(): Folder
	local existing = root

	if existing ~= nil then
		return existing
	end

	local folder = Instance.new("Folder")

	folder.Name = "GhostLocal"
	folder.Parent = workspace
	root = folder

	return folder
end

--[[
	The ghost's own body. A part, not a character: a character would need a Humanoid, an appearance
	load and a control script, all to produce a position this file already has.

	`LocalTransparencyModifier` rather than `Transparency`, so the ghost can see their own body faintly
	while it stays out of the way of looking at the world.
]]
local function ensureBody(): BasePart
	local existing = body

	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end

	local part = Instance.new("Part")

	part.Name = "GhostBody"
	part.Size = Vector3.new(2, 4, 1) -- config-ok: the local body's own size, not a balance knob
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(180, 210, 255) -- config-ok: local ghost tint, replaced at C34
	part.Transparency = 0.6 -- config-ok: how solid your own ghost looks to you
	part.Parent = ensureRoot()

	body = part

	return part
end

--[[
	Where the ghost starts. Their body was destroyed by the server the instant they died, so there is
	nothing left to read a position from — the camera's current focus is the closest thing to "where I
	was looking when I died", and it is a client-side value that costs nothing to be wrong about.
]]
local function startingCFrame(): CFrame
	local camera = workspace.CurrentCamera

	return if camera ~= nil then camera.CFrame else CFrame.new()
end

local function teardown()
	local folder = root

	if folder ~= nil then
		folder:Destroy()
	end

	root = nil
	body = nil
	table.clear(peers)

	local camera = workspace.CurrentCamera

	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
	end
end

--[[
	FLIGHT. The body is moved directly rather than through physics, because it is anchored and
	client-owned — there is no server simulation to fight and no other client to keep in sync.

	Input is read from `UserInputService` rather than bound through `ContextActionService`, so it does
	not compete with the living player's movement binds. A ghost has no character, so the default
	controls have nothing to drive and the usual WASD does nothing.
]]
local function fly(deltaTime: number)
	local part = body
	local camera = workspace.CurrentCamera

	if part == nil or camera == nil then
		return
	end

	local direction = Vector3.zero

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		direction += camera.CFrame.LookVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		direction -= camera.CFrame.LookVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		direction += camera.CFrame.RightVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		direction -= camera.CFrame.RightVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		direction += Vector3.yAxis
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		direction -= Vector3.yAxis
	end

	if direction.Magnitude > 0 then
		part.CFrame = part.CFrame + direction.Unit * Config.Ghost.FlySpeed * deltaTime
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(
		part.Position - camera.CFrame.LookVector * Config.Ghost.CameraDistance,
		part.Position
	)
end

--[[
	REPORTED ON A TICK, NOT EVERY FRAME. `Config.Ghost.RosterInterval` governs the cadence for the same
	reason it governs the roster: §5's mobile budget counts sends per player per tick, and a position
	that moves at most `FlySpeed` does not need 60 updates a second to price a task contribution.

	The server bounds how far a report may jump, so a slower cadence means a LARGER allowed jump — the
	two numbers are related and the server derives its limit from elapsed time rather than assuming
	this interval.
]]
local function report()
	local part = body

	if part == nil then
		return
	end

	local now = os.clock()

	if now - lastReportAt < Config.Ghost.RosterInterval then
		return
	end

	lastReportAt = now

	Remotes.Get("ReportGhostPosition"):FireServer(part.Position)
end

--[[
	Peer ghosts, as grey blocks at no position this client knows.

	THE ROSTER CARRIES UserIds AND NOT POSITIONS, deliberately — see `Types.GhostRosterPayload`. So this
	cannot draw a peer WHERE they are; it can only draw that they exist. Until a ghost-to-ghost position
	channel exists (which would be a new remote with its own secrecy argument), a peer body is a marker
	rather than a location, and §4.7's "sees other ghosts" is only half delivered.

	Recorded here rather than quietly rendered wrong, because a grey block at the origin looks like a
	bug and is actually a missing feature.
]]
local function applyRoster(payload: Types.GhostRosterPayload)
	if not isGhost then
		return
	end

	local seen: { [number]: boolean } = {}

	for _, userId in payload.UserIds do
		seen[userId] = true
	end

	for userId, part in peers do
		if not seen[userId] then
			part:Destroy()
			peers[userId] = nil
		end
	end
end

local function onSnapshot(snapshot: Types.ClientRoundSnapshot)
	local nowGhost = snapshot.YourState == Enums.PlayerState.Ghost

	if nowGhost == isGhost then
		return
	end

	isGhost = nowGhost

	if not nowGhost then
		teardown()
		return
	end

	local part = ensureBody()

	part.CFrame = startingCFrame()
end

function GhostController.Init() end

function GhostController.Start()
	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
	Remotes.Get("GhostRoster").OnClientEvent:Connect(applyRoster)

	RunService.RenderStepped:Connect(function(deltaTime: number)
		if not isGhost then
			return
		end

		fly(deltaTime)
		report()
	end)

	-- A ghost whose player leaves takes their local body with them; nothing else holds a reference.
	LOCAL_PLAYER.AncestryChanged:Connect(function()
		if LOCAL_PLAYER.Parent == nil then
			teardown()
		end
	end)
end

return GhostController
