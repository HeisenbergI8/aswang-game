--!strict
--[[
	REVIEW — src/shared/Types.luau. Phase 2 adds the verdict unions; Phase 5 starts producing
	`YourCarriedItem`.

	The most important finding: the field V08 needs ALREADY EXISTS, with its secrecy argument already
	written, and V02 deliberately left it without a producer.

	Cited against the file as read on 2026-08-29.
]]

-- src/shared/Types.luau:27
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
-- NOTE: already correct and already three. `Enums.ItemType` (Enums.luau:46-49) carries the matching
-- `:: Types.ItemType` casts, which is what makes the three equality tests in `onItemFound` typecheck.
-- Nothing in V08 widens either.

-- src/shared/Types.luau:435-464 — YourCarriedItem, abridged
--[[
	V02, §4.4. WHAT THE RECEIVING PLAYER IS CARRYING, AND THE `Your` PREFIX IS THE WHOLE CONTRACT.

	Safe for a reason that is structural rather than argued: `RoundSnapshot` is built per player and
	sent with `:FireClient` precisely because `YourState` already differs ... There is no broadcast
	form of this payload to accidentally put someone else's inventory on.

	IT IS NOT A ROLE ORACLE. The Aswang carries nothing — the three items are the survivors' (§4.6) —
	so its slot is `nil`, which is also what an empty-handed survivor's slot is. The two are
	indistinguishable, and they must stay that way: do not add a "cannot carry" or "carry denied"
	value to `ItemType` for the monster's benefit.

	CARRY IS DELIBERATELY NOT PUBLIC. §4.5's v2 phrase list includes "I have the buntot pagi" —
	announcing what you hold is a CHOICE with a cost ... So: never widen this to another player's
	carry, and never mirror it onto an attribute or a tag, both of which replicate to everyone.

	OPTIONAL BECAUSE `Config.Items.*SpawnCount` PLUS `Config.Salt.CarryLimit = 1` MEAN ONE SLOT. If the
	carry limit ever rises this becomes a list, and that is a contract change to argue in a plan.

	V02 ADDS NO PRODUCER. `buildSnapshot` does not set it, exactly as it deliberately does not set
	`YourRole`, so no service changes and `analyze` stays clean.
]]
YourCarriedItem: ItemType?,
-- IMPORTANT: V08 PHASE 5 IS THE PRODUCER V02 DEFERRED. Every secrecy argument the field needs is
-- already here; Phase 5 relies on them rather than restating them.
-- IMPORTANT: ONE SENTENCE IS SUBTLY WRONG AND V08 MUST NOT INHERIT THE ERROR. "The Aswang carries
-- nothing" is false — §4.4 has the monster searching on identical rules, so it finds items and fills
-- this slot. The CONCLUSION is still right, and is right for a stronger reason: nil is what BOTH an
-- empty-handed survivor AND an empty-handed Aswang send, and the monster is empty-handed more often
-- only because it chooses to hunt rather than search. That difference is statistical and reversible,
-- not categorical. Correct the sentence while adding the producer, and note it in the log — a reader
-- who believes the Aswang cannot carry will "helpfully" add the special case that makes it true, and
-- an empty slot then becomes a tell.
-- NOTE: the last paragraph's `Config.Salt.CarryLimit` reference becomes `Config.Items.CarryLimit`.

-- src/shared/Types.luau:317
export type SaltVerdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"
-- NOTE: replaced by ItemThrowVerdict in Phase 2, but its last reader is ItemService.resolveThrow,
-- which Phase 4 fixes. Delete it in Step 4.2, not Step 2.2, or analyze goes red between phases.

-- src/shared/Types.luau:319-339 — SaltEffectPayload's header, abridged
--[[
	THREE FIELDS, ALL ABOUT A TRAJECTORY AND NONE ABOUT A PLAYER ... `Hit` IS SAFE AND IS NOT THE
	REVEAL ... READ THE RoundEndedPayload COMMENT BEFORE ADDING A FIELD. An EXTRA field on an
	annotated table is accepted silently by the typechecker, and `SaltEffect` is not on
	check-secrecy.mjs's REVEAL_ALLOWLIST — so its broadcast rule DOES run over this call, catching a
	field named `role` or `aswang` or `killer` and catching nothing else. A field named `TargetUserId`
	would pass every check in this repo and would name the monster to eight clients.
]]
-- IMPORTANT: V08 ADDS NO FIELD AND RENAMES NOTHING HERE. The remote stays `SaltEffect` because salt
-- is the only item with a throw. Renaming it `ItemEffect` for symmetry would buy nothing and would
-- invite exactly the extra field this paragraph refuses.
-- NOTE: "an EXTRA field on an annotated table is accepted silently" is why ItemService builds the
-- payload as a TYPED LOCAL rather than inline — FireAllClients takes `...any`, so an inline literal
-- is checked against nothing.

-- src/shared/Types.luau:518-524 — the prefix rule
--[[
	PREFIXED `SEARCH_` FOR `TrialPhase`'S REASON, restated because it is not decoration. `SaltVerdict`
	already carries a bare `WRONG_PHASE` and `MonsterState` a bare `NORMAL`; a third union sharing
	those spellings makes a handler wired to the wrong remote a working program with the wrong
	meaning. `check:remotes` and `check:secrecy` are text tripwires and would pass a semantic mix-up
	like that. The prefix makes it an analyzer error instead.
]]
-- IMPORTANT: THE RULE PHASE 2's THREE NEW UNIONS FOLLOW. `ITEM_WRONG_PHASE`, `ITEM_NOT_ALIVE`,
-- `ITEM_THROWER_NOT_ALIVE`, `ITEM_NO_ITEM`, `ITEM_SLOT_FULL`, `ITEM_NOTHING_HELD`.
-- NOTE: `MISS` stays bare and unprefixed in ItemThrowVerdict, deliberately — it is the value the four
-- (now five) worlds collapse into, and it is not a phase or a state that another union spells too.

-- src/shared/Types.luau:466-490 — the field that was REMOVED, abridged
--[[
	THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7).
	`AlivePlayerCount: number` ... made it a sub-second global death signal, and a death signal is an
	input to an attack this game cannot survive.
]]
-- IMPORTANT: THE SHAPE OF ARGUMENT V08's STEP 5.4 MUST APPLY TO ITS OWN FIELD. YourCarriedItem is
-- per-player and does not move when another player dies, so A3 is untouched — the field's own comment
-- says so. But the reasoning here is the template: a field that seems harmless because it carries no
-- role can still be an input to a correlation attack. Ask the same question of the dropped-item parts,
-- which DO appear in the world at the moment somebody dies.
