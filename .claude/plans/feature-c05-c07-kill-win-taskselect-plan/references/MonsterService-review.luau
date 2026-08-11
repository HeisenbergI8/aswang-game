--!strict
-- Review of src/server/Services/MonsterService.luau — the file Phase 4 extends.
-- Excerpts only; open the real file for anything not annotated here.

-- src/server/Services/MonsterService.luau:51-70 — the per-Aswang state table.
type MonsterState = {
	Transformed: boolean,
	-- IMPORTANT: `Transformed` is set BEFORE the 1.2s windup (line 333), to close the spam race.
	-- So it is TRUE during the windup, when no client has seen anything yet. Using it as the kill's
	-- "is transformed" input would let the Aswang chain RequestTransform -> RequestKill and kill before
	-- the tell. Plan Step 4.3 uses `Announced` instead, which is set at line 373, after the broadcast.
	Applied: boolean,
	Announced: boolean,
	AppliedTo: Model?,
	OriginalParts: { PartLook },
	OriginalScales: { [string]: number },
	Effects: { Instance },
	-- IMPORTANT: this is the cooldown anchor §4.3 step 5 asks for, and it already exists. C05 needs no
	-- new timestamp — `revert()` stamps it, `TransformRules` reads it, `KillValidation` reads the same.
	LastRevertedAt: number?,
	BaseWalkSpeed: number?,
	Generation: number,
}

-- src/server/Services/MonsterService.luau:75
local transformedRemote = Remotes.Get("MonsterTransformed")
-- NOTE: the remote is held in a module local rather than called inline at the fire site. House style,
-- copied by Phase 4's `killedRemote`. Consequence: `check-secrecy.mjs` resolves a remote's name only
-- from an inline `Remotes.Get("X"):FireAllClients(` (:146-160), so the name is unknown at the fire
-- site. Changes nothing for PlayerKilled — not on REVEAL_ALLOWLIST, so the field check never runs.

-- src/server/Services/MonsterService.luau:254-268 — the revert, and the cooldown it starts.
local function revert(player: Player)
	-- IMPORTANT: READ, do not construct. Phase 4's `Humanoid.Died` handler calls this for players who
	-- may never have transformed, so the same discipline applies there.
	local monster = monsters[player.UserId]

	if monster == nil or not monster.Transformed then
		return
	end

	monster.Transformed = false
	-- IMPORTANT: THIS LINE IS §4.3 STEP 5. `commitKill` calling `revert(killer)` is the entire
	-- implementation of "kill cooldown: 30s from revert" — there is no second timer to add.
	monster.LastRevertedAt = os.clock()
	monster.Generation += 1

-- src/server/Services/MonsterService.luau:301-312
	-- ANNOUNCE ONLY WHAT WAS ANNOUNCED.
	if monster.Announced and character ~= nil then
		local payload: Types.MonsterTransformedPayload =
			{ Character = character, Transformed = false }

		transformedRemote:FireAllClients(payload)
	end
	-- NOTE: this is the shape Phase 4's PlayerKilled broadcast copies — a TYPED LOCAL passed by name,
	-- not an inline table. `FireAllClients` takes `...any`, so an inline literal is checked against
	-- nothing at all. The annotation catches a wrong type and a missing field, and NOT an extra one.

-- src/server/Services/MonsterService.luau:384-408 — validation, and what is never echoed.
local function validateAndTransform(player: Player)
	local monster = stateFor(player.UserId)

	local verdict = TransformRules.evaluate({
		IsAswang = RoleService.IsAswang(player),
		Phase = RoundService.GetPhase(),
		PlayerState = RoundService.GetPlayerState(player),
		Transformed = monster.Transformed,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})
	-- NOTE: the exact shape Phase 3's KillValidation call copies — a table literal built at the call
	-- site out of service state, with Config read here rather than inside the pure module.
	-- IMPORTANT: `Cooldown = Config.Monster.KillCooldown`. The TRANSFORM is gated on the KILL cooldown.
	-- That is deliberate (one cooldown, §4.3 step 5) and it means an on-cooldown Aswang cannot be
	-- transformed at all — which is why the kill's own cooldown check is defence in depth today.

	if verdict ~= "OK" then
		-- IMPORTANT: logged, never echoed. Phase 4's handler must do the same, and the stakes are
		-- higher: `TARGET_IS_ASWANG` is a role oracle you can walk the whole server with.
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused transform for {player.Name}: {verdict}`)
		end

		return
	end

	transform(player)
end

-- src/server/Services/MonsterService.luau:414-430 — the phase subscription.
local function onPhaseChanged(phase: Types.RoundPhase)
	if phase == Enums.RoundPhase.Active then
		return
	end
	-- NOTE: fires on entering ANY non-ACTIVE phase, so Phase 4 hangs `clearCorpses()` here and gets
	-- "no bodies from last round standing in the plaza during INTERMISSION" for free.

	for userId in monsters do
		local player = Players:GetPlayerByUserId(userId)

		if player ~= nil then
			revert(player)
		end
	end

	table.clear(monsters)
end

-- src/server/Services/MonsterService.luau:440-462 — the rate-limit shape every later handler copies.
function MonsterService.Start()
	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
		-- IMPORTANT: `check-ratelimit.mjs` matches AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)
		-- within 1200 CHARACTERS of the connect site. A handler that is limited 250 lines away reads as
		-- unguarded and fails the build. Phase 4's RequestKill handler must be inline for the same reason.
		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end

		validateAndTransform(player)
	end)
	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- NOTE: no PlayerAdded connection today. Phase 4 adds one for the `Humanoid.Died` watch, with a
	-- backfill loop, matching RoundService.Start's connect-then-sweep ordering.
end
