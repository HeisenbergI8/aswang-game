--!strict
--[[
	REVIEW — src/shared/Types.luau:1-46
	Read for: whether PlayerProfile matches §6.6, and what the file's own security note commits us to.
]]

--------------------------------------------------------------------------------
-- :4-8 — the header, which is a constraint and not documentation
--------------------------------------------------------------------------------

--	SECURITY NOTE: PlayerProfile and RoundState live on the SERVER ONLY.
-- IMPORTANT: PlayerProfile is named here, alongside RoundState, as server-only. C31 is the chunk that
-- gives that sentence something to be true about. It rules out `leaderstats`, attributes, and any
-- remote carrying the profile — including a "harmless" XP number, because Stats.AswangRounds sits in
-- the same table and the next person to add a field will follow the precedent, not the comment.

--------------------------------------------------------------------------------
-- :18-33 — the sub-tables, already correct
--------------------------------------------------------------------------------

export type PlayerStats = {
	Rounds: number,
	Survived: number,
	AswangRounds: number, -- NOTE: role HISTORY. Safe at rest, fatal on the wire.
	AswangWins: number,
	Kills: number,
	TasksDone: number,
}
-- NOTE: matches §6.6's `Stats = { Rounds, Survived, AswangRounds, AswangWins, Kills, TasksDone }`
-- field for field. ProfileMigration re-declares this shape locally rather than requiring this file.

export type Cosmetics = {
	Owned: { [string]: boolean },
	Equipped: { Skin: string, Lantern: string, DeathFX: string },
}
-- NOTE: `Owned` is an unbounded map keyed by an arbitrary string, and it comes back from a DataStore.
-- The plan's `ownedFrom` bounds both the key length and the entry count on read — not because a
-- client can write it (none can), but because a corrupt save should not become a 4MB write.

--------------------------------------------------------------------------------
-- :35-46 — the gap
--------------------------------------------------------------------------------

export type PlayerProfile = {
	SchemaVersion: number, -- versioned from day one; write the migration path
	XP: number,
	Level: number,
	Coins: number,
	Stats: PlayerStats,
	Cosmetics: Cosmetics,
	Daily: {
		LastClaimUTC: number,
		Streak: number,
	},
	-- IMPORTANT: §6.6's fourth field, `Purchases = { GamepassCacheUTC = 0 }`, IS MISSING. Step 1.1
	-- adds it. Adding it now rather than at C35 matters because SchemaVersion 1 must be the shape the
	-- spec describes — shipping v1 short a field means the first migration is v1 -> v2 for a field
	-- that was always meant to be there.
}
-- NOTE: `SchemaVersion: number` and not a literal `1`. Correct: a stored profile can hold any number,
-- including one from a newer build, and the migration's REFUSED branch depends on being able to
-- represent that.
-- QUESTION (settled in the plan): this type and `ProfileMigration.Profile` are two declarations of the
-- same shape, because a pure module cannot require this file under Lune. Luau unions and tables are
-- structural, so they pass to each other uncast — and if that ever stops compiling, the analyzer is
-- reporting a real drift rather than a nuisance.
