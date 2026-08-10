--!strict
--[[
	Remotes — single place where every RemoteEvent/RemoteFunction is declared.

	The server creates them; the client waits for them. Declaring them in one
	file means you can audit your entire network surface at a glance, which
	matters a lot in a game where one secret (who is the Aswang) decides
	everything.

	RULE: every remote listed here must be rate-limited and fully validated in
	AntiCheatService / the owning service. The client only ever *requests*.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

-- Server -> Client (the server tells you things)
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
	"PhaseChanged",
	"RoleAssigned", -- fired ONLY to the player it concerns
	"TaskProgressChanged",
	"PlayerKilled",
	"MonsterTransformed", -- public by design: this is the tell
	"SaltEffect",
	"RoundEnded", -- includes the reveal
	"QuickChatBroadcast",
	"ProfileUpdated",
}

-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	"RequestTaskProgress",
	"RequestTransform",
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
	"RequestGhostSpook",
	"RequestEquipCosmetic",
	"RequestClaimDaily",
}

local Remotes = {}

local function getFolder(): Folder
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local folder = getFolder()

local function getEvent(name: string): RemoteEvent
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Eagerly create on the server so the client's WaitForChild always resolves.
if IS_SERVER then
	for _, name in EVENTS_DOWN do
		getEvent(name)
	end
	for _, name in EVENTS_UP do
		getEvent(name)
	end
end

-- Usage: Remotes.Get("RequestKill"):FireServer(targetUserId)
function Remotes.Get(name: string): RemoteEvent
	return getEvent(name)
end

Remotes.Down = EVENTS_DOWN
Remotes.Up = EVENTS_UP

return Remotes
