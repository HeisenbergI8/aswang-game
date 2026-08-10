--!strict
--[[
	RoleService — the secret (C03).

	This is the one piece of state the whole game rests on. Everything else in this repo can be wrong
	and the game is worse; this being wrong and the game is OVER, because knowing the imposter is the
	entire win condition (§4.2, §6.2, Appendix C).

	WHAT LEAVES THIS SERVICE, EXHAUSTIVELY
	--------------------------------------
	  · `RoleAssigned`, via :FireClient, to ONE player, carrying ONE field: that player's own role.
	  · `AssignRoles` returns the Aswang's UserId to RoundService, in server memory, so that the
	    existing Aswang-leaves case and the end-of-round reveal keep reading it where they already do.

	That is the whole list. Not an attribute, not a tag, not a Highlight, not a name colour, not a
	walkspeed, not a tool in a backpack, not a sound played to one player. §6.2 calls the last few
	"derived hints": none of them contains the word "role" and every one is readable by any client.
	`check:secrecy` catches the obvious three shapes and cannot see a derived hint at all — which is why
	`exploit-auditor` GATES this chunk.

	WHY THE ROSTER IS PASSED IN RATHER THAN READ
	--------------------------------------------
	`AssignRoles(candidates)` takes the roster instead of asking RoundService for it. Two reasons, and
	the second is the load-bearing one:

	  1. RoundService requires RoleService. If RoleService required RoundService back, the cycle would
	     error at require time and take the bootstrap with it.
	  2. `RoleDraw` is only reproducible-from-a-seed if `candidates` arrives in a DETERMINISTIC order,
	     and `Players:GetPlayers()` does not promise one. RoundService sorts. Putting the sort at the
	     call site keeps the ordering requirement next to the thing that satisfies it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- script.Parent is Services; script.Parent.Parent is the `Server` script that src/server/init.server.luau
-- becomes, and `pure` is a sibling folder of Services beneath it.
local RoleDraw = require(script.Parent.Parent.pure.RoleDraw)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

type Role = Types.Role

local RoleService = {}

-- SERVER-ONLY state. None of these three tables is ever replicated, serialised, attributed or logged.
local roles: { [number]: Role } = {}

-- Most recent round FIRST, trimmed to Config.Roles.RepeatCooldownRounds. In memory only — C31 owns
-- disk. It is a DRAW INPUT, so it is as secret as the draw itself even though every past Aswang was
-- already revealed by RoundEnded: every input a client holds shrinks the search space for the seed.
local history: RoleDraw.History = {}

--[[
	THE SEED, and the single most dangerous line in this repository.

	`Random.new()` with NO ARGUMENT. Roblox seeds it from a source the client cannot observe.

	`Random.new(state.RoundNumber)` and `Random.new(os.time())` are both fatal: RoundNumber is in the
	snapshot every client receives, and a wall clock is a search space of a few thousand values. Either
	one, combined with the published roster and the published algorithm, lets an exploiter replay the
	draw locally and know the Aswang before ACTIVE — with no remote to intercept and nothing for
	`check:secrecy` to see. Putting RoleDraw under src/server/pure/ removes the algorithm from their
	reach as well; this line is the half that still has to be right.

	Created ONCE and reused, so the stream never restarts and consecutive rounds are not correlated.
]]
local rng: Random = nil :: any

--------------------------------------------------------------------------------
-- Queries. Server-side callers only.
--------------------------------------------------------------------------------

function RoleService.GetRole(player: Player): Role?
	return roles[player.UserId]
end

function RoleService.IsAswang(player: Player): boolean
	return roles[player.UserId] == Enums.Role.Aswang
end

--------------------------------------------------------------------------------
-- The draw
--------------------------------------------------------------------------------

--[[
	Is this value the Aswang? Returns a BOOLEAN rather than a role, and that is deliberate.

	ROOT CAUSE, measured over six failed attempts rather than guessed: **generalized iteration widens a
	singleton union**. `for k, v in t` where `t` is `{ [K]: "A" | "B" }` hands back a plain `string`,
	and a plain `string` does not satisfy a parameter typed as the literal union. It applies both to
	`RoleDraw`'s returned assignments and to this file's own `roles` table.

	That is why the obvious fixes all fail: a `::` cast, a typed local, and a helper returning
	`Types.Role` each receive an ALREADY-widened value, so the widening propagates through all three.
	What works is never carrying the iterated value as a role at all — reduce it to a boolean at the
	loop boundary, then write the role as a bare literal, which Luau accepts against the union
	directly. The boundary is one line wide and exactness is restored on the far side of it.

	Related to, but not the same as, the `Enums.RoundPhase.Idle` widening CLAUDE.md already documents:
	that one a cast fixes, this one it does not.
]]
local function drewAswang(value: unknown): boolean
	return value == Enums.Role.Aswang
end

--[[
	Called by RoundService.enterStarting with a SORTED list of the UserIds dealt into this round.
	Returns the Aswang's UserId so RoundService can keep it in the one place the reveal already reads.
]]
function RoleService.AssignRoles(candidates: { number }): number?
	table.clear(roles)

	local weights: RoleDraw.Weights = {
		Base = Config.Roles.BaseWeight,
		Recent = Config.Roles.RecentAswangWeight,
		Older = Config.Roles.OlderAswangWeight,
		HistoryRounds = Config.Roles.RepeatCooldownRounds,
	}

	local assignments = RoleDraw.draw(
		candidates,
		history,
		Config.Roles.AswangCount,
		weights,
		function(): number
			return rng:NextNumber()
		end
	)

	local aswangUserId: number? = nil

	for userId, drawn in assignments do
		if drewAswang(drawn) then
			roles[userId] = "ASWANG"
			aswangUserId = userId
		else
			roles[userId] = "SURVIVOR"
		end
	end

	if aswangUserId ~= nil then
		table.insert(history, 1, { aswangUserId })

		while #history > Config.Roles.RepeatCooldownRounds do
			table.remove(history)
		end
	end

	-- Told LAST, after the table is complete, so nothing can observe a half-assigned round.
	for userId, role in roles do
		local player = Players:GetPlayerByUserId(userId)

		if player == nil then
			-- Drawn, then disconnected inside STARTING. RoundService.onPlayerRemoving aborts the round
			-- when the departed player was the Aswang, and it covers STARTING as well as ACTIVE —
			-- which it did NOT until an audit found that an Aswang could delete a round for everyone
			-- by quitting inside the four-second role-card window. There is nothing to do here but
			-- not error.
			continue
		end

		-- A TYPED LOCAL, not an inline table. FireClient takes `...any`, so an inline literal is
		-- checked against nothing at all. This catches a wrong type and a missing field — it does NOT
		-- catch an EXTRA one, which is exactly the leak shape (see the Types.RoundEndedPayload comment
		-- that C01 left). Whatever is added here must be re-read as though every client received it.
		local payload: Types.RoleAssignedPayload =
			{ Role = if drewAswang(role) then "ASWANG" else "SURVIVOR" }

		Remotes.Get("RoleAssigned"):FireClient(player, payload)
	end

	if Config.Debug.VerboseLogging then
		-- Deliberately COUNTS, never names. This line is one careless edit away from being the leak,
		-- and a Studio output window is a screenshot away from being public.
		print(`[RoleService] Drew {#candidates} roles.`)
	end

	return aswangUserId
end

-- Called by RoundService when a round ends and the lobby reopens. The HISTORY deliberately survives —
-- that is the whole anti-repeat mechanism — while the live assignments do not.
function RoleService.ClearRoles()
	table.clear(roles)
end

function RoleService.Init()
	rng = Random.new()
	table.clear(roles)
	table.clear(history)
end

function RoleService.Start() end

return RoleService
