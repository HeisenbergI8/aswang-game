--!strict
--[[
	TeachingService — one line, once ever, at the moment it is needed (C23, §10).

	═══ WHY THIS IS SERVER-SIDE AND NOT A CLIENT FLAG ════════════════════════════

	"Once ever" has to survive a rejoin, and a client-side flag does not: leave and come back and the
	game teaches you salt again, which is exactly the repetition C23's done condition forbids. It is
	also where the equivalent already lived — the old task service's `everCompleted` was this same idea with
	one trigger, and its comment says the same thing: in memory now, in the profile at C40.

	═══ WHY IT IS ONE SERVICE AND NOT FOUR SETS ══════════════════════════════════

	The four triggers live in four different services — a salt pickup, a ghost death, a transform, a
	two-person task. Each could hold its own "have they seen it" table, and then C40 would have four
	migrations into the profile instead of one, and "none repeat" would be four separate promises.
	One table, one remote, one place to migrate.

	CALLERS PASS A TRIGGER, NEVER A SENTENCE. `Cue(player, "CUE_FIRST_SALT")` — the copy is in
	`shared/pure/TeachingLines` and the caller does not know it. A service that passed text would be a
	service that could show a fifth line without anyone editing the table that is supposed to be
	closed.

	═══ WHAT THIS REMOTE REVEALS ═════════════════════════════════════════════════

	That the RECEIVER is new, and nothing about anyone else — the same argument
	`FirstObjectiveAssigned` makes one entry above it in `Remotes.luau`. Three of the four triggers
	are things the receiving player did themselves (a pickup, their own death, standing at a point).
	The fourth is the transform, and its caller is the one place in C23 where the 🔒 surface is live:
	the cue must go to exactly the audience that already received the public `MonsterTransformed`
	broadcast, in the same frame, or it becomes new information about where the Aswang is.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local TeachingLines = require(Shared.pure.TeachingLines)

local TeachingService = {}

--[[
	WHO HAS SEEN WHAT. Keyed by UserId, then by cue id — per-cue rather than a single "has been
	taught" flag, because a shared flag would teach a player exactly one thing in their entire first
	round and pass every obvious test. `tests/teaching-lines.test.luau` pins that distinction.

	IN MEMORY AND DELIBERATELY SO, matching that same shape rather than introducing a
	second policy. It resets with the server, so "once ever" is really "once per server" until C40
	moves both tables into the profile together. A veteran seeing one repeated line costs a moment; a
	beginner never seeing one costs the player.
]]
local seenByUser: { [number]: { [string]: boolean } } = {}

local cueRemote = Remotes.Get("TeachingCue")

--[[
	Fire a cue at one player, if they have not had it. Returns whether anything was sent, so a caller
	can log or branch — no caller currently does, and none should need to.

	THE ORDER MATTERS: resolve FIRST, mark second. `TeachingLines.resolve` returns nil when the cue is
	already seen or is not a real cue, so marking before resolving would burn the one-shot on an
	unknown id and silently delete a real line the day a typo was fixed.
]]
function TeachingService.Cue(player: Player, cueId: string): boolean
	local seen = seenByUser[player.UserId]

	if seen == nil then
		seen = {}
		seenByUser[player.UserId] = seen
	end

	local line = TeachingLines.resolve(cueId, seen)

	if line == nil then
		return false
	end

	seen[cueId] = true

	-- FireClient to the one player this concerns. Never FireAllClients: the payload is an id, but the
	-- fact of RECEIVING one says the receiver is new, and that is a per-player fact.
	cueRemote:FireClient(player, cueId)

	if Config.Debug.VerboseLogging then
		-- A UserId and a cue id. No role, and no statement about anyone else.
		print(`[TeachingService] cued {player.UserId}: {cueId}`)
	end

	return true
end

function TeachingService.Init() end

function TeachingService.Start()
	--[[
		The set is dropped when its player leaves, which is what makes "once ever" honestly "once per
		session" until C40. Kept rather than leaked: an unbounded table keyed by UserId on a server
		that has seen a thousand players is a slow leak with no symptom.
	]]
	Players.PlayerRemoving:Connect(function(player: Player)
		seenByUser[player.UserId] = nil
	end)
end

return TeachingService
