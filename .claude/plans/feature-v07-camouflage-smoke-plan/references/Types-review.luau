--!strict
--[[
	REVIEW — src/shared/Types.luau (794 lines)

	Read for the two unions V02 declared with no producer, for the client contract V07 must NOT widen,
	and for one comment that already names this chunk.
]]

-- src/shared/Types.luau:1-9
--[[
	SECURITY NOTE: PlayerProfile and RoundState live on the SERVER ONLY. The Aswang's identity must
	never be replicated to another client in any form — not a tag, not an attribute, not a "hidden"
	value. Assume every client is compromised. See docs/MVP-SPEC.md §6.2.
]]
-- IMPORTANT: V07 adds two payload types to this file and they are the whole of what crosses. Neither
-- may carry a role, a UserId, a health value or a charge count. The file's own header is the rule.

-- src/shared/Types.luau:33-39
-- MonsterState's comment: FEEDING (§4.3) replaced the kill cooldown. CAMOUFLAGED (§4.3) is the
-- ambient-animal form. EXPOSED is the odd one — a LATCH rather than an activity.
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
-- IMPORTANT: `CAMOUFLAGED` is already declared and V07 is its first producer. Nothing needs adding to
-- this union; `monsterStateOf` gains a branch (plan Step 4.5) and that is the whole change.
-- NOTE: the "EXPOSED is a latch" observation is why `monsterStateOf` never returns it — a salted
-- Aswang is Exposed AND still transformed. V07's camouflage is a second layer with the same property:
-- a camouflaged monster is Camouflaged AND still Transformed, which is why the derivation checks
-- `Camouflaged and Transformed` rather than `Camouflaged` alone.

-- src/shared/Types.luau:61
export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"
-- IMPORTANT: already declared, at V02, with no producer. V07 must reuse this rather than declaring a
-- second copy — `Types.CamouflageForm` on the server record, and a structurally identical local
-- re-declaration inside `pure/AmbientRoster` and `pure/CamouflageRules` (Lune has no `script`).

-- src/shared/Types.luau:~515-525
-- NOTE: the comment about union collisions — `WRONG_PHASE` and `NORMAL` already appear bare in two
-- different unions, and "a third union sharing" them is called out as the risk. This is why V07's
-- `CamouflageVerdict` PREFIXES every value (`CAMO_OK`, `CAMO_WRONG_PHASE`) rather than reusing the
-- bare strings from `pure/CamouflageRules.Verdict`. Two unions containing the same literals are one
-- refactor away from being passed to each other's handler, and --!strict would typecheck that.

-- src/shared/Types.luau:~605-615
-- IMPORTANT: THIS COMMENT NAMES THIS CHUNK. "· NO CAMOUFLAGE CHARGE. V07's reward rides
-- `MonsterService.FeedCompleted`, a server-side [BindableEvent]" — i.e. the decision that the charge
-- must NOT be a field on the feed's client payload was made at V06 and V07 must honour it. The charge
-- lives on the server record and has no wire representation anywhere.

-- ClientRoundSnapshot — the contract for what may cross
-- IMPORTANT: V07 DOES NOT WIDEN IT. Nothing about camouflage, the charge or the reveal flag is added
-- to the snapshot in any form. The public half of camouflage is geometry — an avatar is gone and a
-- pig is standing there — and it needs no field. If a later chunk wants one, that is a decision for a
-- plan's Follow Ups, not a field slipped into a diff.
-- NOTE: this is the file where a leak would be EASIEST to introduce and hardest to see, because
-- `check-secrecy.mjs` enforces its payload rule only on the two allowlisted remotes. The `ProfileUpdated`
-- comment in `Remotes.luau` records the same trap in its own words: "a whole-profile payload here
-- would pass `npm run verify` GREEN. Nothing mechanical stops it; this comment is the stop."

-- src/shared/Types.luau — FeedUpdatePayload
-- NOTE: the shape V07's `CamouflageUpdatePayload` copies. A verdict and a duration, fired to one
-- player, with no victim, no body, no health and no UserId. `CamouflageUpdatePayload` is a verdict and
-- an optional form — the form being the receiver's own appearance, which every client can see on the
-- model in any case.
-- NOTE: `Types.FeedVerdict` collapses six interruption paths into ONE `FEED_INTERRUPTED`, because
-- "telling the Aswang whether that was salt or a drift is a fact about a survivor's aim". V07's
-- camouflage verdicts do NOT collapse, and the reason they may not is the mirror of that one: every
-- value concerns the receiver's own state, and none of them is a fact about another player.
