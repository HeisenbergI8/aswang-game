--!strict
--[[
	REVIEW — src/shared/Types.luau:35-83

	Read for the `Purchases` block, whose existing comment already states C38's hardest data rule.
	NOTE the profile has grown since this plan was first drafted: `FirstSeenUTC` and
	`GroupRewardClaimed` are v2 fields added by C35.
]]

-- src/shared/Types.luau:46-55
	--[[
		§6.6's fourth field, missing from the scaffold. A CACHE STAMP, not an entitlement: it records
		when this server last asked Roblox which gamepasses the player owns, so C35 can avoid a
		`UserOwnsGamePassAsync` call on every check. Ownership itself is never stored here — a cached
		"owns it" is a value that survives a refund, and the authority is Roblox, not us.
	]]
	Purchases: {
		GamepassCacheUTC: number,
	},
-- IMPORTANT: THIS COMMENT IS THE SPEC FOR C38's CACHE, already written. The plan does not restate
--            the rule, it implements it: `server/pure/GamepassCache.isStale` decides when to re-ask,
--            and the boolean answer lives in server memory and dies with the server.
--
-- IMPORTANT: "a cached owns-it is a value that survives a refund" is the failure with no expiry and
--            no error message. Any future chunk tempted to persist ownership "just for the lobby"
--            is reopening it.
--
-- NOTE: the plan ADDS `Receipts: { string }` to this same table. That field is a different kind of
--       thing from the stamp beside it — it IS durable state, deliberately, because the whole point
--       is that it survives a server restart. Its own comment in the plan says so, because two
--       fields in one table with opposite persistence rationales is a trap for the next reader.

-- src/shared/Types.luau:65
	FirstSeenUTC: number,
-- IMPORTANT: ADDED IN v2 BY C35, along with `GroupRewardClaimed`. This is why C38's `Receipts` field
--            is a v3 bump and not a v2 one — v2 is spent. See ProfileMigration-review.luau.
-- NOTE: this field is what `ProgressionService.ProfileLoaded`'s second argument carries the
--       pre-stamp value of, and it is therefore how C40's funnel step 4 detects a returning player.

-- src/shared/Types.luau:71-80
	--[[
		THE CLIENT DOES SEE THIS ONE — `ProfileSnapshot.GroupRewardClaimed` mirrors it, unlike
		`FirstSeenUTC` above, and the difference is what the field is FOR.
	]]
	GroupRewardClaimed: boolean,
-- NOTE: C39's field, not this plan's. Read only to confirm the plan does not collide with C39's
--       in-flight work. It does not — C38 touches `Purchases`, C39 touches this.
-- NOTE: the "client does see this one" / "unlike FirstSeenUTC" contrast is the model for how the
--       plan's `ShopOffer` payload is reasoned about: per-player, explicitly field-listed, and
--       justified by what the field is FOR rather than by whether it looks harmless.

-- QUESTION (resolved): does adding a field to `Purchases` need a schema bump, given `reconcile`
--   defaults absent fields anyway? YES, and not for the reader — for the `version > CURRENT_VERSION`
--   refusal. A v3 profile read by a v2 server loses the ring to `reconcile`, the next autosave
--   writes the deletion back, and every un-retired receipt re-arms and grants a second time. That is
--   the double-grant arriving through the data model instead of the handler. See Phase 1 Step 1.3.
