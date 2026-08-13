--!strict
-- REVIEW: src/server/Services/MonsterService.luau:52-59, 523-527, 692-724, 773-819 (excerpts)
--
-- The reference for everything TaskService has to be shaped like: a service that subscribes to the
-- phase, converts to a pure module's plain tables at the call site, and puts its rate limit inline.

local AntiCheatService = require(script.Parent.AntiCheatService)                 -- :52
local KillValidation = require(Shared.pure.KillValidation)                       -- :59
-- NOTE: the require idiom, copied in Step 2.2. A service under Services/ reaches src/server/pure/ as
-- `script.Parent.Parent.pure.X` (confirmed at RoleService.luau:39), and src/shared/pure/ through the
-- `Shared` WaitForChild local.

-- Vector3 -> the plain table pure/KillValidation takes. The pure module cannot mention Vector3: Lune
-- has no Roblox datatypes and the whole module would stop being runnable from a terminal.
local function vec(position: Vector3): KillValidation.Vec3                       -- :525
	return { X = position.X, Y = position.Y, Z = position.Z }
end
-- IMPORTANT: this is the exact pattern the brief asks TaskService to reuse for TaskSelection.Vec3.
-- Step 2.3's `toVec` is this function with one word changed. NOTE the conversion happens at the CALL
-- SITE (:655-656), not at the boundary of the module — the pure module never sees a Roblox type.

local function onPhaseChanged(phase: Types.RoundPhase)                           -- :692
	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearCorpses()
	end
	if phase == Enums.RoundPhase.Active then
		return
	end
-- IMPORTANT and directly copied by Step 2.3's teardown. The comment above it (:694-703) records a real
-- shipped bug: clearing on "any phase that is not ACTIVE" destroyed the winning kill's corpse within a
-- frame, because MarkKilled -> EndRound -> ENDING -> PhaseChanged landed here while commitKill was
-- still on the stack. ENDING KEEPS THE ROUND'S ARTEFACTS; INTERMISSION and IDLE clear them.
-- TaskService inherits the same rule for the same reason — §4.8 calls the end screen "the screenshot
-- people share", and a round that finished 4/5 should still say 4/5 on it.

	--[[
		THE RATE LIMIT LIVES HERE, INLINE, and not inside validateAndTransform — deliberately.
		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
		1200 characters of an `.OnServerEvent:Connect(`. It is a proximity tripwire, by its own
		admission, so a handler that IS rate-limited but does it 250 lines away reads as unguarded and
		fails the build.
		Consume FIRST, before any state is read.
	]]                                                                            -- :775-787
	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end
		validateAndTransform(player)
	end)
-- IMPORTANT: the shape Step 4.1 copies exactly, and the reason it copies it rather than factoring the
-- guard into a helper. The 1200-character envelope is a hard constraint on where the Consume call may
-- sit, and "every later handler in this game will copy whatever shape this one sets" is stated in the
-- comment itself.
-- NOTE the second half — Consume BEFORE any state is read. It matters more for RequestTaskProgress
-- than for either of these: an honest client sends four a second, so a handler that validated first
-- would do a distance sweep per refused request.

	Remotes.Get("RequestKill").OnServerEvent:Connect(function(player: Player, targetUserId: unknown)
		if typeof(targetUserId) ~= "number" then
			return
		end
-- NOTE: `unknown` rather than `number`, so the check cannot be skipped — a remote argument is whatever
-- the client sent, and a table reaching GetPlayerByUserId throws inside a connection that Roblox
-- swallows into one warn.
-- IMPORTANT: RequestTaskProgress has NO arguments at all (Step 4.1), following RequestTransform above
-- rather than this. That is strictly stronger — there is no value to validate because the handler's
-- signature discards anything sent. It is only reachable because Config pins
-- PresenceRangeStuds * 2 < MinSpacingStuds, which makes the task point derivable from position alone.

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)                      -- :819
-- NOTE: the subscription idiom. `RoundService.PhaseChanged` is a BindableEvent (RoundService.luau:60),
-- so the connect goes through `.Event`. Step 2.3 uses this line verbatim.
