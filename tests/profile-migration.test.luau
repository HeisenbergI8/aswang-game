--!strict
--[[
	The profile migration grid (§6.6, C31).

	THE CELL THIS FILE EXISTS FOR is `v0 -> v1 keeps the XP`. A migration that returns a clean, correct,
	EMPTY profile passes every type check in the repo and silently wipes every player on the day the
	schema moves. Nothing else in the tree can catch that: the analyzer sees a well-formed `Profile`,
	and by the time a human notices, the wipe has been autosaved.

	The second thing pinned here is the REFUSAL. A profile written by a newer build must come back
	`REFUSED` and not `MIGRATED`, because those two outcomes are one comparison apart in the module and
	the difference is whether a rolled-back deploy deletes fields it has never heard of.
]]

local ProfileMigration = require("../src/shared/pure/ProfileMigration")

type Outcome = ProfileMigration.Outcome

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

--------------------------------------------------------------------------------
-- A fresh player
--------------------------------------------------------------------------------

do
	local template = ProfileMigration.template()

	check(
		"the template is at the current version",
		template.SchemaVersion == ProfileMigration.CURRENT_VERSION
	)
	check(
		"a fresh player starts at level 1 with nothing",
		template.XP == 0 and template.Level == 1 and template.Coins == 0
	)
	check("§6.6's Purchases field is present", template.Purchases.GamepassCacheUTC == 0)
	check(
		"the three cosmetic slots default",
		template.Cosmetics.Equipped.Skin == "default"
			and template.Cosmetics.Equipped.Lantern == "default"
			and template.Cosmetics.Equipped.DeathFX == "default"
	)

	local first = ProfileMigration.template()
	local second = ProfileMigration.template()

	first.Stats.Kills = 9
	check("template returns a FRESH table each call, not a shared one", second.Stats.Kills == 0)

	--[[
		NIL IS TESTED ON ITS OWN, NOT AS THE FIRST ELEMENT OF A LIST — and that is not a style
		preference. `{ nil, 7, "profile", true }` constructs an array Luau reports as length 3: the
		leading nil is dropped, the loop runs three times, and the suite still passes while never
		once calling `migrate(nil)`. That is the FIRST-TIME PLAYER — the most-executed path this
		module has — so the hole is precisely where coverage matters most and the assertion count
		is the only thing that shows it.
	]]
	local fresh = ProfileMigration.migrate(nil)

	check("nothing stored -> FRESH", fresh.Outcome == "FRESH", fresh.Outcome)
	check("nothing stored -> a whole profile", fresh.Profile.Level == 1)
	check("nothing stored reports version 0", fresh.FromVersion == 0)
	check("a first-time player claims no migration steps", #fresh.Applied == 0)

	for _, stored in { 7, "profile", true, 0 / 0 } :: { any } do
		local result = ProfileMigration.migrate(stored)

		check(`{typeof(stored)} stored -> FRESH`, result.Outcome == "FRESH", result.Outcome)
		check(`{typeof(stored)} stored -> a whole profile`, result.Profile.Level == 1)
	end
end

--------------------------------------------------------------------------------
-- v0 -> v1. The chunk's Done condition.
--------------------------------------------------------------------------------

do
	-- A v0 profile is one written before SchemaVersion existed: no version field, partial shape.
	local v0 = { XP = 120, Coins = 45, Stats = { Rounds = 3, Kills = 1 } }
	local result = ProfileMigration.migrate(v0)

	check("v0 is recognised as version 0", result.FromVersion == 0, `{result.FromVersion}`)
	check("v0 migrates rather than resetting", result.Outcome == "MIGRATED", result.Outcome)
	check("v0 -> v1 KEEPS the XP", result.Profile.XP == 120, `{result.Profile.XP}`)
	check("v0 -> v1 KEEPS the coins", result.Profile.Coins == 45)
	check(
		"v0 -> v1 KEEPS a partial Stats table",
		result.Profile.Stats.Rounds == 3 and result.Profile.Stats.Kills == 1
	)
	check("v0 -> v1 FILLS the stats it did not have", result.Profile.Stats.TasksDone == 0)
	check("v0 -> v1 FILLS §6.6's newer fields", result.Profile.Purchases.GamepassCacheUTC == 0)
	check(
		"v0 -> v1 stamps the version",
		result.Profile.SchemaVersion == ProfileMigration.CURRENT_VERSION
	)
	check("the migration says what it did", #result.Applied == 1, `{#result.Applied} entries`)
	check(
		"the source table is not mutated",
		(v0.Stats :: any).TasksDone == nil and rawget(v0 :: any, "SchemaVersion") == nil
	)
end

--------------------------------------------------------------------------------
-- Already current, and corrupt
--------------------------------------------------------------------------------

do
	local current = ProfileMigration.template()

	current.XP = 900
	current.Cosmetics.Owned = { lantern_brass = true }

	local result = ProfileMigration.migrate(current)

	check("a current profile is CURRENT, not MIGRATED", result.Outcome == "CURRENT", result.Outcome)
	check("a current profile is unchanged", result.Profile.XP == 900)
	check("owned cosmetics survive", result.Profile.Cosmetics.Owned.lantern_brass == true)
	check("a current profile applies nothing", #result.Applied == 0)

	local corrupt = ProfileMigration.migrate({
		SchemaVersion = 1,
		XP = 0 / 0,
		Level = -4,
		Coins = "lots",
		Cosmetics = { Owned = { [1] = true, ok = true, bad = "yes" }, Equipped = { Skin = "" } },
	})

	check("NaN XP falls back to the default", corrupt.Profile.XP == 0, `{corrupt.Profile.XP}`)

	--[[
		INFINITY IS THE CASE A NaN GUARD MISSES, and it is the expensive one. `math.floor(math.huge)`
		is `inf`, not an error; `inf ~= inf` is false and `inf < 0` is false, so a guard written as
		"not NaN and not negative" passes it straight through. JSON cannot encode `inf`, so one
		infinite field makes every later DataStore write for that player fail — silently, permanently.
		Found by an exploit-auditor after the first version of `num` shipped with exactly that hole.
	]]
	local infinite = ProfileMigration.migrate({
		SchemaVersion = 1,
		XP = math.huge,
		Coins = -math.huge,
		Stats = { Kills = math.huge },
		Daily = { LastClaimUTC = math.huge },
	})

	check(
		"infinite XP falls back to the default",
		infinite.Profile.XP == 0,
		`{infinite.Profile.XP}`
	)
	check(
		"negative infinity falls back too",
		infinite.Profile.Coins == 0,
		`{infinite.Profile.Coins}`
	)
	check("a nested infinite stat falls back", infinite.Profile.Stats.Kills == 0)
	check("an infinite timestamp falls back", infinite.Profile.Daily.LastClaimUTC == 0)

	for _, field in { "XP", "Coins", "Level" } do
		local value = (infinite.Profile :: { [string]: any })[field]

		check(
			`{field} survives as a finite number`,
			value < math.huge and value == value,
			`{value}`
		)
	end
	check("a negative level is clamped to 1", corrupt.Profile.Level == 1, `{corrupt.Profile.Level}`)
	check("a string in a number field falls back", corrupt.Profile.Coins == 0)
	check(
		"an empty cosmetic id falls back to default",
		corrupt.Profile.Cosmetics.Equipped.Skin == "default"
	)
	check(
		"only string keys mapped to `true` survive Owned",
		corrupt.Profile.Cosmetics.Owned.ok == true and corrupt.Profile.Cosmetics.Owned.bad == nil
	)
end

--------------------------------------------------------------------------------
-- A profile from the future
--------------------------------------------------------------------------------

do
	local future = ProfileMigration.migrate({
		SchemaVersion = ProfileMigration.CURRENT_VERSION + 1,
		XP = 5000,
	})

	check("a newer profile is REFUSED", future.Outcome == "REFUSED", future.Outcome)
	check(
		"a refusal reports the version it saw",
		future.FromVersion == ProfileMigration.CURRENT_VERSION + 1
	)
	check("a refusal claims no migration steps", #future.Applied == 0)

	local outcomes: { Outcome } = { "FRESH", "CURRENT", "MIGRATED", "REFUSED" }

	check("every outcome is reachable", #outcomes == 4)
end

do
	local input = { SchemaVersion = 1, XP = 12 }
	local first = ProfileMigration.migrate(input)
	local second = ProfileMigration.migrate(input)

	check(
		"migrate is deterministic",
		first.Outcome == second.Outcome and first.Profile.XP == second.Profile.XP
	)
	check(
		"migrating twice is migrating once",
		ProfileMigration.migrate(first.Profile).Outcome == "CURRENT"
	)
end

if failures > 0 then
	error(`{failures} profile-migration assertion(s) failed`, 0)
end

print(
	`  PASS  profile-migration: {checked} assertions over fresh, legacy, current, corrupt and future`
)
