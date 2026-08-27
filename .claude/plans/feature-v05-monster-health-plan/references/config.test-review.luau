--!strict
--[[
	REVIEW — tests/config.test.luau
	Excerpts only. Ranges as of 2026-08-27, branch v2-rewrite (modified in the working tree by V04).
]]

-- tests/config.test.luau:1-9
--[[
	Balance invariants.
	These are not tests of Config's VALUES — every number in there is explicitly "a starting value to
	tune" (spec §0). They test the RELATIONSHIPS between values, which are load-bearing and silent.
]]
-- NOTE: the contract V05's new checks must satisfy. `SaltDamage x (SaltSpawnCount - 1) >= MaxHealth
-- - WeakenedThreshold` is a relationship, not a value, so it belongs here rather than in
-- `tests/monster-health.test.luau`.

-- tests/config.test.luau:11-26
local Config = require("../src/shared/Config")
local AudioCues = require("../src/shared/pure/AudioCues")
local function check(label: string, ok: boolean, detail: string?)
-- NOTE: the `check` helper and the require-by-relative-path idiom that `tests/monster-health.test
-- .luau` copies verbatim. Lune resolves by file path and cares nothing for Rojo.

-- tests/config.test.luau:67-78  (the two §6.5 salt invariants that ARE pinned)
	Config.Salt.ThrowRange > Config.Monster.KillRange,
	Config.Salt.RevealDuration > Config.Salt.StunDuration,
-- NOTE: §6.5 invariants 3 and 6. Read through the `Salt` ALIASES rather than through `Items`, which
-- is fine today and breaks on the chunk that deletes the block — worth knowing before adding more.
-- V05's new checks read `Config.Items.*` directly, which is the canonical source.

-- tests/config.test.luau:96-116
	"Config.Salt.SpawnCount is still an alias of Items.SaltSpawnCount",
	"Config.Salt.RevealDuration is still an alias of Items.SaltRevealDuration",
-- IMPORTANT: this is why V05 does not delete the `Salt.RevealDuration` alias when it removes its
-- last reader. Deleting the alias reds this suite; removing both is a two-file edit V08 should make
-- as part of the `Salt*` -> `Item*` generalisation.

-- tests/config.test.luau:149-164
--[[
	C14/C15, and this relationship became load-bearing for a SECRECY invariant rather than for balance.
	An exploit audit traced the one path that would reproduce the permanent-WalkSpeed brand: transform
	while stunned, so the transform captures `BaseWalkSpeed = 0`.
]]
	Config.Monster.KillCooldown > Config.Salt.StunDuration,
-- IMPORTANT: V05 inserts its health invariants immediately AFTER this check, because this is where
-- the salt-versus-monster relationships live. Do not disturb it — it guards a secrecy property, not
-- a balance one, and `KillCooldown` is scheduled for deletion at V06.

-- tests/config.test.luau:733
local totalItems = Config.Items.SaltSpawnCount
-- NOTE: the only other reader of SaltSpawnCount in this file (a V03 container-layout invariant).
-- V05's invariant 1 check is independent of it.

-- tests/config.test.luau:878-889
if failures > 0 then
	error(`{failures} balance invariant(s) violated`, 0)
end
--[[
	COUNTED, NOT TYPED. This line read `34 balance invariants` as a literal for long enough that it
	...
]]
print(`  PASS  config: {checked} balance invariants`)
-- NOTE: the count is derived, so V05's five new checks need no edit here. Do not reintroduce a
-- literal.
-- QUESTION for whoever implements Phase 2: nothing in this file currently mentions `MaxHealth` at
-- all — `grep -n "MaxHealth" tests/config.test.luau` returns nothing. Confirm that is still true
-- before inserting, in case V04's working-tree changes added one.
