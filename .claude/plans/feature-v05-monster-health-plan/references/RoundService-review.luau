--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau
	Excerpts only. Ranges as of 2026-08-27, branch v2-rewrite.
	V05 EDITS NOTHING IN THIS FILE. It is read for the service shape and for two seams.
]]

-- src/server/Services/RoundService.luau:8-12
--	subscribe via RoundService.PhaseChanged. Round logic is the single most
-- NOTE: the reference service shape — `Init()` clears state, `Start()` creates instances, connects
-- remotes and subscribes to phase changes, and every public function is a `function Service.Name`
-- at the bottom. `MonsterService` follows it and V05's four new seams go in that block.

-- src/server/Services/RoundService.luau:77-79
RoundService.PhaseChanged = Instance.new("BindableEvent")
local phaseChangedRemote = Remotes.Get("PhaseChanged")
-- NOTE: a BindableEvent for servers, a RemoteEvent for clients — two distinct fan-outs from one
-- `setPhase`. V05 subscribes to neither directly; `MonsterService.Start` already holds the one
-- connection and V05 adds work inside the existing `onPhaseChanged`.

-- src/server/Services/RoundService.luau:647-656
local function setPhase(newPhase: RoundPhase, duration: number?)
	RoundService.PhaseChanged:Fire(newPhase, duration)
end
-- IMPORTANT: `local`, deliberately. Spec §6.4: "Never let gameplay code mutate phase directly. Every
-- service subscribes to phase changes." Nothing in V05 calls this, and nothing can — it is not on
-- the returned table.

-- src/server/Services/RoundService.luau:744-747
--		GAMEPLAY SERVICES SUBSCRIBE TO PhaseChanged; this file must not call them. A service that needs
-- NOTE: the dependency direction. `MonsterService` requires `RoundService`, never the reverse — so
-- V05's health state cannot be reached from the round, which is correct: MonsterService owns it.

-- src/server/Services/RoundService.luau:99-101
function RoundService.GetAswangUserId(): number?
-- IMPORTANT: THE SECRET, and the third boolean in V08's strike gate. The pattern V05 sets up for it
-- is the one `ItemService.luau:606` already uses: AND the role with a form/state query ON THE SERVER
-- and hand a single boolean to the pure module, so the role never enters the pure layer.
--   RoundService.GetAswangUserId() == userId
--     and MonsterService.IsExposed(userId)
--     and MonsterService.IsWeakened(userId)

-- src/server/Services/RoundService.luau:814-841
function RoundService.EndRound(result: Types.RoundResult)
function RoundService.MarkKilled(player: Player, causedByKill: boolean?)
-- IMPORTANT: V05 calls NEITHER. §4.6: salt is counterplay, not a win condition — "salt alone can
-- never kill", which is why `MonsterHealth.apply` floors it. The chunk that calls `MarkKilled` for
-- the monster is V08, on a buntot pagi strike against an Exposed AND Weakened Aswang.

-- src/server/Services/RoundService.luau:1176-1200
--	The husk folder, for `MonsterService.hasLineOfSight`'s raycast filter.
function RoundService.GetHusksFolder(): Folder?
function RoundService.MarkHuskKilled(userId: number)
-- NOTE: §6.4's edge cases. Two matter for V05's Exposed window:
--   · the Aswang LEAVES mid-round -> the round ends immediately. `MonsterService.onPlayerRemoving`
--     nils the state, and the phase change out of ACTIVE runs `clearExposed` over what remains — but
--     the departing player's own entry is already gone, so their Highlight is destroyed by Roblox
--     along with their character. Confirm this in the playtest rather than assuming.
--   · a SURVIVOR leaves -> they become a husk and the round continues. Irrelevant to health; a husk
--     has no monster state and `IsWeakened` answers false for it.
-- QUESTION: a husk is a body with no Player. If a future chunk lets the Aswang be salted while its
-- owner is disconnecting, `applyExposed` parents a Highlight to a character that is about to become
-- a husk — a glowing husk, which is the corpse-glow bug in a different body. Not reachable today
-- (salt requires a transformed, connected player) but worth a line in V08's plan.
