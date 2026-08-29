--!strict
--[[
	REVIEW — src/shared/Types.luau (907 lines), the camouflage surface
	         plus src/shared/Enums.luau:81-90 and the two pure-module copies.

	THE ONE THING TO TAKE FROM THIS FILE: `CamouflageForm` is written down in FIVE places and nothing
	checks that they agree. That is why Phase 1 is a whole phase for what looks like a find-and-replace.
]]

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/Types.luau:53-61 — the union itself
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

--[[
	§4.3. What a revealed Aswang can turn into. Four ambient forms so the barrio's scenery is a place
	the monster can hide IN rather than a backdrop, and so §4.5's "It's the [animal]!" phrase has a
	closed set of things it can name.

	NOT A PET SYSTEM, and the distance matters because `check:scope` arms `pets?`. These are forms the
	Aswang wears, owned by nobody, purchasable never (§8.3).
]]
export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"

-- IMPORTANT: THE FIVE DECLARATION SITES, none of which reference each other:
--   1. here
--   2. src/shared/Enums.luau:85-90       — a frozen table, each member with a `:: Types.X` cast
--   3. src/shared/pure/AmbientRoster.luau:29    — re-declared; Lune has no `script`
--   4. src/shared/pure/CamouflageRules.luau:43  — re-declared, same reason
--   5. src/server/Services/AmbientService.luau  — FORM_LOOKS keys, formFromId, the spawnForm calls
--
-- Luau unions are STRUCTURAL, so 3 and 4 are genuinely the same type as 1 and pass to each other
-- without a cast. That is what makes drift silent: a missed site does not fail where it is wrong, it
-- widens to plain `string` on `require` and the analyzer reports it at a CALL SITE IN ANOTHER FILE.
-- `.claude/lessons/pure-module-unions-widen-in-lists.md` — eight failed fixes and an hour at C21,
-- every error naming the wrong file.
--
-- IMPORTANT: the `NOT A PET SYSTEM` sentence is the prepared defence for `check:scope`, which arms
-- `pets?`. Two new animals is precisely the shape that check exists to catch. If it fires, the answer
-- is a waiver citing this sentence — not a rename that hides the word.
--
-- NOTE: "so §4.5's 'It's the [animal]!' phrase has a closed set of things it can name" — that phrase
-- does not exist. See `QuickChatPhrases-review.luau`. This comment describes an intent, not a wiring.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/Types.luau:709-722 — what the Aswang's own client is told
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

export type CamouflageUpdatePayload = {
	Verdict: CamouflageVerdict,
	Form: CamouflageForm?,
}

-- Fired to ONE player about themselves: a verdict, and the form when there is one.
--
-- IMPORTANT: THIS IS THE ONLY PAYLOAD THIS PLAN TOUCHES, AND IT TOUCHES IT ONLY BY WIDENING THE DOMAIN
-- OF AN EXISTING FIELD. Six literals instead of four in a field that already crosses, to an audience
-- of one, about that player's own state. No new field, no new remote, no new recipient.
--
-- NOTE: `CAMO_NO_SLOT` will fire far more often once Phase 3 bounds the claim to a territory, and it
-- is the only feedback the Aswang gets. It still says nothing a second client can read — it is a fact
-- about the requester's own position, which their client already has.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/Enums.luau:8-10 and :81-90 — the casts, which are the load-bearing half
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- The `:: Types.X` casts are load-bearing under --!strict. Without them every field
-- infers as plain `string`, and passing one to a parameter typed as the literal union
-- fails to typecheck — which is how the scaffold shipped six analyze errors.

Enums.CamouflageForm = table.freeze({
	Cat = "CAT" :: Types.CamouflageForm,
	-- ...
})

-- IMPORTANT: a member added WITHOUT its cast passes a key scan and breaks at the first call site. That
-- is why Phase 1's suite matches on `"([A-Z_]+)" :: Types%.CamouflageForm` rather than on the keys —
-- it checks the thing that is actually load-bearing.
--
-- NOTE: `AmbientService`'s header (:101-117) documents two shapes that were tried here and do NOT
-- typecheck — iterating the frozen table (yields `unknown`) and a `{ Types.CamouflageForm }` literal
-- list (widens the element). What works is a LITERAL checked against an ANNOTATED PARAMETER, which is
-- why `Start` has four calls rather than a loop. Six is exactly the length at which someone will try
-- to tidy it back into a loop; the plan says so at that line.
