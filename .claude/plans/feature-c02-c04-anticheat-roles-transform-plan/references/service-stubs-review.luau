--!strict
--[[
	REVIEW — the three service stubs this plan replaces, read in full (they are ~20 lines each):
	  src/server/Services/AntiCheatService.luau
	  src/server/Services/RoleService.luau
	  src/server/Services/MonsterService.luau

	All three are scaffold placeholders with an Init/Start pair and a TODO block. There is no logic in
	any of them to preserve — the plan replaces each wholesale. What IS worth carrying forward is the
	intent recorded in their TODOs, which the scaffold author wrote against the spec.
]]

-- AntiCheatService.luau, in full apart from the module boilerplate:
--   TODO(M11): per-player token bucket on EVERY remote in Shared/Remotes.
--   TODO(M11): sanity-check movement speed and teleports.
--   -- Exploiters will specifically target this game because knowing the imposter
--   -- is so valuable. Server authority is the whole defence.
--
-- NOTE the milestone label says M11 while BUILD-PLAN puts the bucket at C02 and the speed/teleport
-- checks at C41. C02 is the correct order — the bucket must exist before the first handler does. The
-- speed/teleport half is NOT in this plan.

-- RoleService.luau:
--   TODO(M2): assign 1 Aswang from the player list.
--   TODO(M2): track last 2 rounds; heavily reduce weight for recent Aswangs.
--   -- SECURITY: the role is server-only state. Fire "RoleAssigned" to the ONE
--   -- player it concerns via FireClient — never FireAllClients.
--
-- IMPORTANT: the scaffold's security note is exactly what Phase 5 implements, and the plan preserves
-- its wording in the new header. "never FireAllClients" is the rule check:secrecy enforces mechanically.

-- MonsterService.luau:
--   TODO(M2): transform (Config.Monster.TransformTime) — visible to everyone by design.
--   TODO(M2): validate kills SERVER-SIDE: distance <= KillRange, raycast line of
--             sight, cooldown elapsed, both alive, phase == ACTIVE.
--   -- The client only requests. The server decides.
--
-- NOTE the kill half is C05 and is deliberately NOT built by this plan. `RequestKill` stays declared
-- and unwired. `MonsterState.LastRevertedAt` is written by this plan specifically so C05 has the
-- cooldown anchor §4.3 asks for ("30s from revert") already in place.

-- All three currently satisfy every check vacuously: no remote handler, no number, no broadcast.
function Service.Init() end
function Service.Start() end
