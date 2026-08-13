--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (832 lines)

	Excerpted ranges:
	  · src/server/Services/MonsterService.luau:73-102    the state table and the corpse folder
	  · src/server/Services/MonsterService.luau:297-357   makeCorpse and clearCorpses
	  · src/server/Services/MonsterService.luau:363-426   revert — the function C14 must reuse
	  · src/server/Services/MonsterService.luau:595-611   commitKill and the PlayerKilled broadcast
	  · src/server/Services/MonsterService.luau:692-724   onPhaseChanged — the clearing split
	  · src/server/Services/MonsterService.luau:793-817   the handler shape every new handler copies

	C14 touches this file twice: it reuses the revert path (Step 3.3) and it narrows PlayerKilled
	(Step 1.5). Everything below is why those are the two edits and not four.
]]

-- src/server/Services/MonsterService.luau:73-92
type MonsterState = {
	Transformed: boolean,
	Applied: boolean,
	Announced: boolean,
	AppliedTo: Model?,
	OriginalParts: { PartLook },
	OriginalScales: { [string]: number },
	Effects: { Instance },
	LastRevertedAt: number?,
	BaseWalkSpeed: number?,
	Generation: number,
}
-- Four fields exist FOR C14 and this plan's Step 3.3 is what makes them pay off.
-- NOTE `Announced` gates the revert broadcast. Its own comment (line ~81) says a revert broadcast for a
--      transform nobody saw "at C14 is a free identity leak" — throw salt at a suspect mid-windup and be
--      told whether you were right.
-- NOTE `AppliedTo` is the character the look was applied to, NOT player.Character. Resolving at revert
--      time lands on a freshly respawned body and whitens it.
-- IMPORTANT `Generation` exists solely to invalidate an in-flight forced-revert timer. Its comment names
--      C14 explicitly: a salt-forced revert followed by a fresh transform would otherwise be cut short by
--      the FIRST transform's expiry timer. A duplicate revert path in ItemService loses this silently.

-- src/server/Services/MonsterService.luau:100-102
local corpses: Folder? = nil
-- "One parent for every corpse, so the raycast can exclude them wholesale."
-- NOTE ItemService's pouch folder (Step 2.5) and GhostService's teardown copy this shape deliberately.

-- src/server/Services/MonsterService.luau:297-299
local function makeCorpse(victim: Player, character: Model)
	victim.Character = nil
-- IMPORTANT THE CALLER HAS ALREADY TAKEN THE BODY by the time RoundService.MarkKilled runs. This is why
--      BodyTransitions' GHOST/KILLED cell must stay REVOKE after Phase 6 opens the other four: REVOKE
--      finds nothing to destroy, and the corpse survives. Reversing the order deletes the corpse in the
--      frame it is created, and the symptom is "the corpse code does not work".

-- src/server/Services/MonsterService.luau:363-377
local function revert(player: Player)
	local monster = monsters[player.UserId]

	if monster == nil or not monster.Transformed then
		return
	end

	monster.Transformed = false
	monster.LastRevertedAt = os.clock()
	monster.Generation += 1
-- IMPORTANT This early return is why `MonsterService.ForceRevert` needs no caller guard: a mistaken call
--      is a no-op, not a state change.
-- NOTE `LastRevertedAt` stamped here means a salt-forced revert charges the full KillCooldown. That is
--      the right answer rather than a side effect — see line ~735, which makes the same argument for a
--      death mid-transform. Salt is a real setback, not an inconvenience.
-- QUESTION Does the plan want salt to charge the full 30s cooldown? It does today, by inheritance, and
--      nothing in §4.6 says otherwise. Worth confirming at M12 rather than assuming.

-- src/server/Services/MonsterService.luau:416-421
	if monster.Announced and character ~= nil then
		local payload: Types.MonsterTransformedPayload =
			{ Character = character, Transformed = false }

		transformedRemote:FireAllClients(payload)
	end
-- IMPORTANT "ANNOUNCE ONLY WHAT WAS ANNOUNCED." This is the mid-windup leak guard. Step 3.3 reuses it by
--      calling `revert` rather than reimplementing; a second path that broadcast unconditionally would
--      turn salt into "throw at a suspect mid-windup and be told whether you were right".

-- src/server/Services/MonsterService.luau:605-611
	local payload: Types.PlayerKilledPayload = { VictimUserId = victim.UserId, Position = position }

	killedRemote:FireAllClients(payload)
end
-- IMPORTANT THIS IS DECISION 1's LOAD-BEARING FINDING. `FireAllClients`, carrying who died and exactly
--      where, to every client, the instant it happens. That is a STRONGER death oracle than the
--      `AlivePlayerCount` field the brief asked about: it does not merely timestamp the kill, it hands
--      over the position, so an attacker skips the position-logging step of the correlation attack
--      BUILD-PLAN's C15 block describes. Dropping the snapshot field while this stands is theatre.
-- IMPORTANT Types.PlayerKilledPayload:196-199 defends `Position` on the grounds that "the corpse model
--      stands at that position and replicates to every client on its own". §5 requires StreamingEnabled
--      from C17 on, under which a corpse 200 studs away does NOT replicate and this remote does. The two
--      were never equivalent; they only looked it on an unstreamed baseplate.
-- NOTE Step 1.5 changes this to `FireClient(victim, payload)`. The only consumer is
--      CameraFXController:61-75, a first-person death reaction that was firing on seven other screens.

-- src/server/Services/MonsterService.luau:705-711
	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearCorpses()
	end

	if phase == Enums.RoundPhase.Active then
		return
	end
-- IMPORTANT THE SPLIT IS DELIBERATE AND THIS PLAN COPIES IT IN TWO PLACES. Clearing on "any phase that is
--      not ACTIVE" destroyed the winning kill's corpse within a frame of creating it. ENDING keeps them.
-- NOTE Step 2.5's `clearPouches` follows the corpse rule (INTERMISSION/IDLE only — pouches during ENDING
--      are scenery). Step 4.2's `clearAllEffects` follows the TRANSFORM rule (every non-ACTIVE phase — a
--      glow during ENDING is a mark on a player). Two different answers, both correct, and getting them
--      backwards is the mistake this comment prevents.

-- src/server/Services/MonsterService.luau:793-799
	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end

		validateAndTransform(player)
	end)
-- IMPORTANT THE SHAPE EVERY NEW HANDLER IN THIS PLAN COPIES. `check-ratelimit.mjs` matches the Consume
--      call within 1200 characters of the connect site — a proximity tripwire by its own admission — so
--      a handler that IS limited but does it 250 lines away fails the build. Consume FIRST, before any
--      state is read.
-- NOTE Steps 3.4 (RequestThrowSalt) and 8.4 (RequestGhostSpook) are written to this template, including
--      the `unknown`-typed argument at line ~804 and its typeof guard.
