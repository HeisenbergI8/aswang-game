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
	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
	"TaskProgressChanged",
	-- C09. FireClient to the ONE player standing at a TIMING point. Carries a task point's bar, never
	-- a player: the server owns the phase and re-derives it on every stop, so this is a rendering
	-- hint and not an input to any decision.
	"TimingBarChanged",
	-- C12. FireClient to EVERY player, at STARTING, one loop, one payload shape. Survivors get this
	-- round's real five; the Aswang gets a decoy five. The uniformity is the design — see
	-- Types.TaskListPayload. Deliberately NOT on check-secrecy's REVEAL_ALLOWLIST: it carries no role,
	-- so it must keep being scanned like any other remote.
	"TaskListAssigned",
	"PlayerKilled",
	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
	"SaltEffect",
	"RoundEnded", -- includes the reveal
	"QuickChatBroadcast",
	"ProfileUpdated",
}

-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	"RequestTaskProgress",
	-- C09. NO ARGUMENTS, and that is the whole security design: the server resolves which task from
	-- the player's own position and reads the bar's phase off its own clock at the moment this lands.
	-- There is no argument in which a client could name a moment, a position or an outcome.
	"RequestTimingStop",
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
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
