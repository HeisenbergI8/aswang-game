--!strict
--[[
	REVIEW — src/shared/pure/ProfileMigration.luau:103, :194-231, :271-279, :295-333

	Read to decide whether C38's receipt ring needs a schema bump. IT DOES, and the version this
	plan must claim is v3 — v2 was consumed by C35 while this plan was being written.
]]

-- src/shared/pure/ProfileMigration.luau:103
ProfileMigration.CURRENT_VERSION = 2
-- IMPORTANT: THE VERSION MOVED UNDER THIS PLAN. It was 1 when the C38 design started; C35 took v2
--            for `FirstSeenUTC` and `GroupRewardClaimed`. So C38's `Purchases.Receipts` is a v3
--            bump with its own `Applied` line, and it cannot ride along on v2 the way those two
--            rode together.

-- src/shared/pure/ProfileMigration.luau:295-315
	--[[
		A PROFILE FROM THE FUTURE IS NOT MIGRATED, IT IS REFUSED — and this is the branch that matters
		most, because it is the one that loses data if it is wrong.
		...
		Reconciling them DELETES those fields, and the next autosave writes the deletion back.
	]]
	if version > ProfileMigration.CURRENT_VERSION then
		return { Outcome = "REFUSED", ... }
	end
-- IMPORTANT: THIS BRANCH IS THE ENTIRE REASON C38 BUMPS THE VERSION. `reconcile` would default
--            `Receipts` to `{}` happily, so the bump buys nothing for the READER. What it buys is
--            this refusal: without it, a v3 profile carrying granted receipt ids is read by a v2
--            server, `reconcile` drops the ring, the autosave writes the deletion back, and EVERY
--            RECEIPT ROBLOX HAS NOT YET RETIRED RE-ARMS AND GRANTS A SECOND TIME.
--
--            The ring is the one field in this profile where losing it is not cosmetic.
--
-- NOTE: the accepted cost is stated in the plan: during a staged deploy a v3 player on a v2 server
--       is latched read-only, so `ApplyReceipt` answers UNAVAILABLE -> NotProcessedYet. The
--       purchase is not lost; Roblox re-delivers on a v3 server. That is strictly better than
--       granting twice.

-- src/shared/pure/ProfileMigration.luau:319-333
	if version < 1 then
		table.insert(applied, "v0->v1 defaults filled, SchemaVersion stamped")
	end

	--[[
		v1->v2 IS ADDITIVE AND HAS NO STEP TO RUN. `reconcile` defaults both new fields like every
		other absent field, and both defaults are the correct answer...
		The line is recorded anyway so `Applied` reads as a migration in the log rather than as a
		version bump nothing did.
	]]
	if version < 2 then
		table.insert(applied, "v1->v2 FirstSeenUTC and GroupRewardClaimed added")
	end
-- NOTE: the exact template C38's v2->v3 line copies, including the "additive, no step to run,
--       recorded anyway" reasoning. Consistency here matters more than it looks: `Applied` is what
--       the log prints, and a bump with no line reads as a version that did nothing.

-- src/shared/pure/ProfileMigration.luau:194-231 (reconcile)
	local purchases: any = if type(stored.Purchases) == "table" then stored.Purchases else {}
	...
		Purchases = {
			GamepassCacheUTC = num(purchases.GamepassCacheUTC, 0),
		},
-- NOTE: field-by-field defaulting, every value sanitised through `num` / `str` / `ownedFrom`. The
--       plan's `receiptsFrom` follows `ownedFrom`'s shape exactly, including the cap-on-read.
-- IMPORTANT: `ownedFrom` caps the inventory ON THE WAY IN because "a write path that could exceed
--            it would produce a profile that silently loses entries the next time it is loaded".
--            The receipt ring inherits that reasoning, and `receiptsFrom` keeps the TAIL rather than
--            the head — the newest ids are the ones a re-delivery could still be about.

-- IMPORTANT: this is a `shared/pure/` module, so it may not require Config (CLAUDE.md: no
--            `script.Parent` requires, or Lune cannot run it). `MAX_RECEIPTS` must therefore be a
--            local duplicate of `Config.Monetization.ReceiptHistory` with a `-- config-ok:` waiver,
--            exactly as `MAX_OWNED_COSMETICS` already is. Named in the plan's Follow Ups.
