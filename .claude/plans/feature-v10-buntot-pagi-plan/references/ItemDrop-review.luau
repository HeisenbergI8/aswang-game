--!strict
--[[
	REVIEW — src/shared/pure/ItemDrop.luau
	Read to answer ONE question: does §4.6's "drops where the carrier falls" already exist? It does.
	This module plus `ItemService.spillItem` is the whole of it, and V10 writes no second path.
]]

-- src/shared/pure/ItemDrop.luau:9-13
--[[
	THE SMALLEST OF THE FOUR ITEM MODULES, AND IT HAS NO GEOMETRY AT ALL. You may put down what you
	are holding, wherever you are standing, whenever you are alive in an ACTIVE round. There is no
	"you cannot drop here", and the absence is deliberate.
]]
-- IMPORTANT THIS MODULE IS NOT THE DEATH DROP. It governs the DELIBERATE drop (`RequestDropItem`),
--           which routes to `dropItemInFront`. The death drop is `ItemService.spillItem`, which
--           consults NO pure module at all — it is unconditional, because a dead player has no
--           decision left to validate. Do not read this module's `ITEM_NOT_ALIVE` verdict as
--           blocking the death spill; it blocks a DEAD player from firing the drop remote.

-- src/shared/pure/ItemDrop.luau:44-48 — the sentence that settles Decision C
--[[
	ITEM_NOT_ALIVE IS AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"` ... A DEAD player must not drop:
	the death path already spills the item where they fell (§4.6), so a dead player who could also
	drop would be a duplication surface — and there is exactly one buntot pagi in the round.
]]
-- IMPORTANT "THE DEATH PATH ALREADY SPILLS THE ITEM WHERE THEY FELL (§4.6)" — written at V08, in the
--           present tense, about a mechanism that exists. V10's Done line asks for "drops where the
--           carrier falls" and the answer is that V08 shipped it. The plan's Decision C is this
--           sentence plus the two call sites in `ItemService` (`Humanoid.Died` at ~1400,
--           `Players.PlayerRemoving` at ~1468).
-- IMPORTANT "A DUPLICATION SURFACE — AND THERE IS EXACTLY ONE BUNTOT PAGI IN THE ROUND" is the whole
--           reason V10 must not add a second drop path. Two paths to the floor for the item that IS
--           the win condition is how one becomes two, and nothing in the game would report it.

-- src/shared/pure/ItemDrop.luau:15-19 — the V09 prediction that also covers V10
--[[
	A PLACEMENT RULE WOULD BE V09'S, NOT V08'S. Bawang is PLACED on a doorway and that placement has
	conditions ... Dropping is the plain act of ceasing to hold something. Conflating the two now
	would build half of V09 inside V08 with none of its rules written down ...
]]
-- NOTE THE SAME ARGUMENT SHAPE APPLIES TO V10 AND V11. V10 is the plain act of the monster dying;
--      what that death MEANS for the round has conditions (a roster, a kill count, a frozen
--      `RequiredKills`) and those are V11's. Conflating them builds half of V11 with none of §6.5's
--      six invariants written down. This is the precedent for the plan's §1.1 scope boundary.

-- src/shared/pure/ItemDrop.luau:21-24
--[[
	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It never takes a role. §4.4 has the
	Aswang searching, carrying and dropping on identical rules, so the monster reaches this module
	and gets OK exactly as a survivor does — which is what keeps an empty slot from being a tell.
]]
-- IMPORTANT "WHAT KEEPS AN EMPTY SLOT FROM BEING A TELL" is the property Decision B protects from
--           the other direction. If a refused swing did NOT consume the buntot pagi, the slot's
--           CONTENTS become the tell instead: the player who still has it after swinging has
--           learned who the Aswang is not. Both halves of the item economy have to stay symmetric.

export type Verdict = "OK" | "ITEM_WRONG_PHASE" | "ITEM_NOT_ALIVE" | "ITEM_NOTHING_HELD"
-- NOTE `StrikeValidation`'s three striker-side verdicts are these three renamed. That is not an
--      accident and is worth keeping visible: the strike's spend line falls exactly where a drop's
--      preconditions end, because both are asking "was this player entitled to act on their slot".
