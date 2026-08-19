--!strict
--[[
	ProfileMigration — what a saved player looks like, and how an old one becomes a current one.
	(§6.6, C31)

		migrate(whatever the DataStore returned) -> { Outcome, Profile, FromVersion, Applied }

	WHY THIS EXISTS BEFORE IT IS NEEDED. C31's brief is explicit: "SchemaVersion = 1 and the migration
	path written on day one, before you need it. You will change the schema; the question is only
	whether the migration exists when you do." The expensive version of this module is the one written
	in a hurry against live player data.

	NO `script` REQUIRES, AND THE SHAPE IS RE-DECLARED. Lune has no `script`, so a pure module that
	reaches for `Types` stops being runnable from a terminal and the whole point is lost. `Profile`
	below and `Types.PlayerProfile` are the same structural type and pass to each other uncast.

	`Outcome` IS A SCALAR AND NEVER TRAVELS IN A LIST. A literal union survives `require` as a scalar
	and does NOT survive inside an array — see `.claude/lessons/pure-module-unions-widen-in-lists.md`,
	which cost eight failed fixes to learn. `Applied` is deliberately `{ string }`.

	EVERY FIELD IS COERCED, NOT TRUSTED. A stored profile is attacker-adjacent input: not because a
	client can write it (nothing here takes a client value — §6.6's fourth rule), but because a
	corrupt or truncated save must degrade to a default rather than propagate a `nil` into a service.
]]

export type Stats = {
	Rounds: number,
	Survived: number,
	AswangRounds: number,
	AswangWins: number,
	Kills: number,
	TasksDone: number,
}

export type Cosmetics = {
	Owned: { [string]: boolean },
	Equipped: {
		Skin: string,
		Lantern: string,
		DeathFX: string,
	},
}

export type Profile = {
	SchemaVersion: number,
	XP: number,
	Level: number,
	Coins: number,
	Stats: Stats,
	Cosmetics: Cosmetics,
	Daily: {
		LastClaimUTC: number,
		Streak: number,
	},
	Purchases: {
		GamepassCacheUTC: number,
	},
}

--[[
	FRESH    nothing was stored — a first-time player.
	CURRENT  stored at the version we run; fields reconciled, version untouched.
	MIGRATED stored at an older version; upgraded, and `Applied` says how.
	REFUSED  stored at a NEWER version than this server understands. See `migrate`.
]]
export type Outcome = "FRESH" | "CURRENT" | "MIGRATED" | "REFUSED"

export type Result = {
	Outcome: Outcome,
	Profile: Profile,
	FromVersion: number,
	Applied: { string },
}

local ProfileMigration = {}

ProfileMigration.CURRENT_VERSION = 1

-- A cosmetic id longer than this is not a cosmetic id. Bounds on a stored string keep a corrupt save
-- from becoming a 4MB key in the next write.
local MAX_ID_LENGTH = 64
local MAX_OWNED_COSMETICS = 256

--[[
	NON-FINITE IS THE POINT, NOT JUST NaN. `value ~= value` catches NaN; it does NOT catch infinity,
	and infinity is the more likely arrival. `math.floor(math.huge)` returns `inf` rather than erroring,
	`inf ~= inf` is false, and `inf < 0` is false — so an infinite XP passes a NaN-and-negative guard
	untouched and lands in the profile.

	That is the expensive one: JSON cannot encode `inf`, so a single infinite field makes EVERY
	subsequent DataStore write for that player fail, silently, forever. An XP multiplier chain that
	overflows to ~1e308 gets there without a single division by zero.

	`value < math.huge` is the finite test, and it rejects NaN as well — a NaN fails every comparison —
	so the two guards collapse into one.
]]
local function num(value: any, fallback: number): number
	if type(value) ~= "number" or not (value >= 0 and value < math.huge) then
		return fallback
	end

	return math.floor(value)
end

local function str(value: any, fallback: string): string
	if type(value) ~= "string" or #value == 0 or #value > MAX_ID_LENGTH then
		return fallback
	end

	return value
end

local function ownedFrom(value: any): { [string]: boolean }
	local owned: { [string]: boolean } = {}

	if type(value) ~= "table" then
		return owned
	end

	local count = 0

	for key, flag in value do
		if type(key) ~= "string" or flag ~= true or #key > MAX_ID_LENGTH then
			continue
		end

		count += 1

		if count > MAX_OWNED_COSMETICS then
			break
		end

		owned[key] = true
	end

	return owned
end

function ProfileMigration.template(): Profile
	return {
		SchemaVersion = ProfileMigration.CURRENT_VERSION,
		XP = 0,
		Level = 1,
		Coins = 0,
		Stats = {
			Rounds = 0,
			Survived = 0,
			AswangRounds = 0,
			AswangWins = 0,
			Kills = 0,
			TasksDone = 0,
		},
		Cosmetics = {
			Owned = {},
			Equipped = {
				Skin = "default",
				Lantern = "default",
				DeathFX = "default",
			},
		},
		Daily = {
			LastClaimUTC = 0,
			Streak = 0,
		},
		Purchases = {
			GamepassCacheUTC = 0,
		},
	}
end

--[[
	Field-by-field, defaulting anything missing or malformed. This is what makes a v0 profile — one
	written before `SchemaVersion` existed, so a bare `{ XP = 120 }` — become a whole v1 profile that
	keeps the 120.
]]
local function reconcile(stored: { [string]: any }): Profile
	local base = ProfileMigration.template()
	local stats: any = if type(stored.Stats) == "table" then stored.Stats else {}
	local cosmetics: any = if type(stored.Cosmetics) == "table" then stored.Cosmetics else {}
	local equipped: any = if type(cosmetics.Equipped) == "table" then cosmetics.Equipped else {}
	local daily: any = if type(stored.Daily) == "table" then stored.Daily else {}
	local purchases: any = if type(stored.Purchases) == "table" then stored.Purchases else {}

	return {
		SchemaVersion = ProfileMigration.CURRENT_VERSION,
		XP = num(stored.XP, base.XP),
		Level = math.max(num(stored.Level, base.Level), 1),
		Coins = num(stored.Coins, base.Coins),
		Stats = {
			Rounds = num(stats.Rounds, 0),
			Survived = num(stats.Survived, 0),
			AswangRounds = num(stats.AswangRounds, 0),
			AswangWins = num(stats.AswangWins, 0),
			Kills = num(stats.Kills, 0),
			TasksDone = num(stats.TasksDone, 0),
		},
		Cosmetics = {
			Owned = ownedFrom(cosmetics.Owned),
			Equipped = {
				Skin = str(equipped.Skin, base.Cosmetics.Equipped.Skin),
				Lantern = str(equipped.Lantern, base.Cosmetics.Equipped.Lantern),
				DeathFX = str(equipped.DeathFX, base.Cosmetics.Equipped.DeathFX),
			},
		},
		Daily = {
			LastClaimUTC = num(daily.LastClaimUTC, 0),
			Streak = num(daily.Streak, 0),
		},
		Purchases = {
			GamepassCacheUTC = num(purchases.GamepassCacheUTC, 0),
		},
	}
end

function ProfileMigration.migrate(stored: any): Result
	if type(stored) ~= "table" then
		return {
			Outcome = "FRESH",
			Profile = ProfileMigration.template(),
			FromVersion = 0,
			Applied = {},
		}
	end

	local version = num(stored.SchemaVersion, 0)

	--[[
		A PROFILE FROM THE FUTURE IS NOT MIGRATED, IT IS REFUSED — and this is the branch that matters
		most, because it is the one that loses data if it is wrong.

		A player who joined a server running a newer build, then joins an older one (a rolled-back
		deploy, a lagging server that has not restarted), arrives with fields this code has never heard
		of. Reconciling them DELETES those fields, and the next autosave writes the deletion back. The
		refusal is the only safe answer: the caller latches the profile read-only, touches nothing, and
		whatever is saved is byte-identical to what was read.

		The returned `Profile` is a template purely so callers never handle a `nil`. It must never be
		written — see `ProgressionService`'s read-only latch.
	]]
	if version > ProfileMigration.CURRENT_VERSION then
		return {
			Outcome = "REFUSED",
			Profile = ProfileMigration.template(),
			FromVersion = version,
			Applied = {},
		}
	end

	local applied: { string } = {}

	if version < 1 then
		table.insert(applied, "v0->v1 defaults filled, SchemaVersion stamped")
	end

	-- Annotated local with literal branches. The analyzer narrows a literal checked against a declared
	-- type; it does NOT narrow a `::` cast over a union, which is the trap the lesson documents.
	local outcome: Outcome = if version < ProfileMigration.CURRENT_VERSION
		then "MIGRATED"
		else "CURRENT"

	return {
		Outcome = outcome,
		Profile = reconcile(stored),
		FromVersion = version,
		Applied = applied,
	}
end

return ProfileMigration
