--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau
	Excerpts only. Cited ranges are as of 2026-08-27 on branch v2-rewrite; open the real file to see
	whether anything has moved.
]]

-- src/server/Services/MonsterService.luau:103-104
-- The table V05's health field goes into. This one comment is the reason the whole chunk is cheap.
-- SERVER-ONLY. Keyed by UserId. Never replicated — the only thing that crosses is the broadcast.
local monsters: { [number]: MonsterState } = {}
-- IMPORTANT: there is no health here yet, and no `Exposed` either. V05 adds both to this table and
-- nowhere else. Anything that puts the number on a Humanoid, an attribute or a tag replicates.

-- src/server/Services/MonsterService.luau:106-113
local function stateFor(userId: number): MonsterState
	local existing = monsters[userId]
	if existing ~= nil then
		return existing
	end
	-- NOTE: lazy creation, on first TRANSFORM. So there is no code path that touches only the
	-- Aswang at round start, which is why V05 must NOT add a "seed the monster's health" loop —
	-- that would be a role-shaped branch on the secrecy surface for no gain.
end

-- src/server/Services/MonsterService.luau:382-389
local function revert(player: Player)
	-- READ, do not construct. `stateFor` here would re-insert a departed player's UserId every time a
	-- stale forced-revert timer fired, growing `monsters` unbounded inside a single ACTIVE phase.
	local monster = monsters[player.UserId]
	-- IMPORTANT: V05's `applyHealthEvent`, `clearExposed` and `IsWeakened` must all copy this. Every
	-- one of them can be reached from a `task.delay` that outlived the player.
end

-- src/server/Services/MonsterService.luau:390-393
	monster.Transformed = false
	monster.LastRevertedAt = os.clock()
	monster.Generation += 1
-- NOTE: the generation idiom V05 reuses for the Exposed expiry. `os.clock()` compared for equality
-- against a stored value — a nonce, not a seed, so CLAUDE.md's `Random.new(os.time())` prohibition
-- does not apply.
-- IMPORTANT: `revert()` does NOT end the Exposed window and must not start doing so. §4.6 gives the
-- glow ten seconds; the revert is instant. A revert that cleared the glow would delete nine of the
-- seconds the buntot pagi needs.

-- src/server/Services/MonsterService.luau:256-277
local function applyFullLook(state: MonsterState, character: Model, humanoid: Humanoid)
	applyScale(humanoid, Config.Monster.TransformedScale)
	-- NOTE: this is the file's existing precedent for a server-created, replicated visual keyed to
	-- monster state — a PointLight on the Head, tracked in `state.Effects` so the revert removes
	-- exactly what this service created and nothing else. V05's Highlight follows the same shape but
	-- is tracked separately, because its lifetime is the Exposed window rather than the transform.
end

-- src/server/Services/MonsterService.luau:919-938  (onPhaseChanged, the tail)
	if phase == Enums.RoundPhase.Active then
		return
	end
	for userId in monsters do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			revert(player)
		end
	end
	table.clear(monsters)
-- IMPORTANT: this runs on EVERY phase that is not ACTIVE, including ENDING — which is exactly the
-- condition `ItemService.onPhaseChanged:678` used for clearing the reveal. V05 puts `clearExposed`
-- inside this loop so the two can never drift apart again.
-- IMPORTANT: `table.clear` here without a preceding clear ORPHANS the Highlight — the state holding
-- the instance is dropped, the instance stays parented to a living character, and nothing ever
-- destroys it. A player hit at second 419 glows in the lobby forever.
-- NOTE: the loop is keyed off the state table, not off `GetPlayerByUserId`, so it also covers a
-- player who has already left.

-- src/server/Services/MonsterService.luau:941-963
local function watchCharacter(player: Player, character: Model)
	humanoid.Died:Connect(function()
		revert(player)
	end)
end
-- IMPORTANT: "the kill path does not go through Humanoid.Died — the victim's character is detached
-- and anchored, never killed, because §4.9 wants a fade rather than a death animation." So V05's
-- corpse-glow guard must hang off `CharacterRemoving`, which fires on the detach. `Died` does not.

-- src/server/Services/MonsterService.luau:1000-1004
function MonsterService.IsTransformed(userId: number): boolean
	local monster: MonsterState? = monsters[userId]
	return monster ~= nil and monster.Transformed
end
-- NOTE: the contract V05's `IsExposed` and `IsWeakened` copy exactly — "the caller must already hold
-- a UserId it got from somewhere else; this function never enumerates, never returns the Aswang, and
-- returns false for every player who is not transformed including the Aswang."
-- NOTE: the `: MonsterState?` annotation is load-bearing under --!strict. Indexing a
-- `{ [number]: MonsterState }` yields a NON-optional value, so comparing it to nil is a type error.

-- src/server/Services/MonsterService.luau:1006-1023
function MonsterService.ForceRevert(player: Player)
	revert(player)
end
-- IMPORTANT: exactly one caller in the repo — `ItemService.luau:511`. After V05 it has none, which
-- is why the plan deletes it rather than leaving a public seam that reverts WITHOUT applying §4.6's
-- damage. Its header's own argument ("a second implementation would have to get all four right and
-- would silently get at least one wrong") is the reason.

-- src/server/Services/MonsterService.luau:1064-1096  (Start, the handler shape)
	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end
	end)
-- NOTE: V05 adds no handler here, so `check:ratelimit` has nothing new to see. Recorded because a
-- reader may expect a new remote for the health readout — there is none; a Highlight's property
-- replicates without one.
-- src/server/Services/MonsterService.luau:1098
	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
-- NOTE: the ONE subscription. V05 adds work to `onPhaseChanged`, never a second connect, and never
-- calls `setPhase` (spec §6.4 — RoundService owns the phase).
