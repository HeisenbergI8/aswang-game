--!strict
--[[
	REVIEW — src/shared/pure/AmbientRoster.luau (164 lines)

	SUMMARY. This module needs ONE line changed by this plan — the re-declared union — and no logic at
	all. That is worth stating explicitly, because it is the check on Phase 1 Step 1.3: if
	`tests/ambient-roster.test.luau` needs editing to pass, a form was enumerated somewhere it should
	not have been.

	One thing here is being repurposed rather than changed, and it is why Phase 3 is cheap: `claim`
	already takes a preferred index, so the server can choose a slot without putting a draw in a
	replicated module.
]]

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/pure/AmbientRoster.luau:29-38 — the type surface
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"

-- One ambient entity. `Claimed` means the monster is wearing this slot; the real entity has wandered
-- off and `AmbientService` has parked its Model out of the world until the slot is released.
export type Slot = {
	Form: CamouflageForm,
	Claimed: boolean,
}

-- NOTE: this is declaration site 3 of 5. Re-declared rather than required because Lune has no
-- `script`; unions are structural so it is genuinely the same type.
--
-- IMPORTANT: the comment on `Slot` is STALE AND DESCRIBES THE V07 CRITICAL AS THOUGH IT WERE STILL THE
-- DESIGN. "`AmbientService` has parked its Model out of the world" is exactly the behaviour that was
-- measured as a total secrecy failure and removed — reparenting to `ServerStorage` fired `ChildRemoved`
-- on every client with the monster's exact position. `AmbientService.luau:14-38` documents the fix at
-- length. Nothing parks anything any more. Fix this comment while the union is being widened; a stale
-- comment describing a removed Critical as current is how someone re-implements it.
--
-- NOTE: `Form` is a literal union inside `Roster`, which is a LIST — so it widens to plain `string` on
-- the way out, which is why `AmbientService.PickAvailableForm` re-narrows through `formFromId` rather
-- than casting. That is the lesson's prescribed fix and it is already applied correctly here.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/pure/AmbientRoster.luau:75-116 — claim, and the preferIndex hint
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

--	THE CALLER MAY NAME A PREFERRED SLOT, AND THAT IS HOW RANDOMNESS STAYS OUT OF THIS FILE.
--	...
--	The fix is a random pick — but the randomness lives in `AmbientService`, which is server-only,
--	rather than here. THIS MODULE IS REPLICATED AND CALLABLE BY ANY CLIENT, so a draw performed here
--	would be a draw a client could replay. A preferred INDEX passed in is just a number.
--
--	`preferIndex` IS A HINT, NOT A COMMAND. It is honoured only when that slot exists, matches the
--	form and is free; otherwise the scan falls through to the first free slot.

function AmbientRoster.claim(roster, form, preferIndex): (Roster, number?)
	-- honour the hint if it is valid, else scan for the first free slot of that form
end

-- NOTE: THIS PARAMETER IS WHY PHASE 3 COSTS ALMOST NOTHING IN THIS FILE. The territory decision is
-- made by a new server-side module and arrives here as an index, exactly as the random pick already
-- does. The reasoning above — entropy stays server-side, only a number crosses — holds unchanged for a
-- position-derived choice, because the position is the server's own copy of the monster's root.
--
-- IMPORTANT: THE FALLBACK SCAN IS WRONG FOR PHASE 3'S CALLER, and it is defended against at the call
-- site rather than changed here. "Honour the hint, else first free" is correct for this module's
-- contract and for its tests — but that fallback slot could be anywhere in the barrio, which restores
-- the map-wide jump the territory bound exists to close. So `ClaimSlot` releases a grant that is not
-- the index it asked for and refuses. The narrower rule lives where it applies.
--
-- NOTE: the exhaustion behaviour — return nil rather than appending a slot — is §4.3's swap-not-spawn
-- rule and is the security of the whole mechanic. Nothing in this plan goes near it.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/pure/AmbientRoster.luau:9-18 — the property this module exists for
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

--	THE ONE PROPERTY THIS MODULE EXISTS TO MAKE TESTABLE: `visibleCount` is INVARIANT across a claim.
--	One entity stops being real and one starts being the monster; the number of things standing in the
--	barrio does not move.

-- NOTE: THE COUNT IS INVARIANT AND THE POSITION IS NOT, and that gap is where this plan's findings
-- live. `visibleCount` cannot see that the claimed rig is 2.6 studs higher than its neighbours, that
-- it jumped 200 studs to get there, or that it is the only one not bobbing. Those are the three things
-- Phases 2, 3 and 4 close, and none of them is a counting property — which is precisely why a Lune
-- suite over this module reported green across all three.
