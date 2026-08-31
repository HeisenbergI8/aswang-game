--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (3343 lines at time of reading)

	V09 does not modify this file. It is reviewed because it holds the argument the whole chunk rests
	on: which differences between two characters are observable, and which of them have already
	shipped as bugs in this repo.
]]

-- src/server/Services/MonsterService.luau:24-29
-- THE PARAGRAPH THAT DECIDES V09'S MECHANISM.
--
-- IMPORTANT: read this as the general rule it is, not as a statement about health. "One character
-- reading 75 while four read 100 is a permanent, map-wide, remote-free role oracle." Substitute any
-- replicated property: `WalkSpeed`, `CollisionGroup`, `Anchored`, an attribute, a tag. That is the
-- entire reason V09 cannot use collision groups — `BasePart.CollisionGroup` is replicated on every
-- character part, so an Aswang in a different group is this bug with a different property name.
--
-- IMPORTANT: "both of which shipped with `verify` and `check:secrecy` green over them". Static green
-- over a secrecy surface means very little here. V09's mechanism must be argued from what
-- replicates, not from what the checks accept.
--[[
	IT IS NOT ON THE HUMANOID, AND THAT IS THE WHOLE POINT. `Humanoid.Health` and `Humanoid.MaxHealth`
	replicate. One character reading 75 while four read 100 is a permanent, map-wide, remote-free role
	oracle — the same shape as C04's revert bug and C14's WalkSpeed brand, both of which shipped with
	`verify` and `check:secrecy` green over them. See `.claude/lessons/absence-is-observable.md`: the
	leak is a DIFFERENCE between players, not a piece of data.
]]

-- src/server/Services/MonsterService.luau:42-45
-- The one replicated difference the game already accepts, and the conditions under which it is safe.
--
-- IMPORTANT: this is the bar V09's block has to clear and does NOT clear the same way. The feed's
-- `WalkSpeed = 0` is licensed by three facts: the character is already in monster form, the
-- transform was already announced, and it lasts exactly `FeedDuration`. None of those hold for
-- garlic — a blocked Aswang may be untransformed, unannounced and standing in a doorway with four
-- survivors watching. So V09 may not write ANY replicated property on the character. Not one.
--
-- NOTE: "`endFeed` is the single restore path and all six exits go through it; a seventh exit that
-- does not is the C04/C14 brand again." V09 sidesteps this entire class of bug by writing no
-- property at all — there is nothing to restore, so there is no seventh exit to get wrong.
--[[
	THE ONE REPLICATED DIFFERENCE A FEED CREATES IS `WalkSpeed = 0`, on a character already in monster
	form and already announced, for exactly FeedDuration seconds. `endFeed` is the single restore path
	and all six exits go through it; a seventh exit that does not is the C04/C14 brand again.
]]

-- src/server/Services/MonsterService.luau:56-62
-- The four seams other services are told to call.
--
-- NOTE: V09 needs NONE of them. Garlic does not care whether the Aswang is Exposed, Weakened,
-- Transformed, Camouflaged or Feeding — the block is on the PLAYER, not on a monster state. That is
-- a deliberate design position and it is worth stating: a camouflaged Aswang that could walk through
-- garlic would make camouflage an anti-garlic tool, and `pure/GarlicBarrier` takes no monster state
-- at all so the option is not available to a later editor without a signature change.
--
-- IMPORTANT: it follows that V09 adds NO new seam to this file and requires no change to it. The
-- only cross-service call the chunk makes is `RoundService.GetAswangUserId()`, which `ItemService`
-- can already reach.
--[[
	  · `IsExposed(userId) -> boolean` — V08's strike gate, half one.
	  · `IsWeakened(userId) -> boolean` — V08's strike gate, half two.
]]

-- src/server/Services/MonsterService.luau:92-96
-- The proximity inference this game already accepts and cannot fix.
--
-- NOTE: relevant to V09 as a calibration rather than a constraint. "A client reading replicated
-- character positions at the instant of the broadcast can see who was within eight studs." Garlic
-- is the same shape inverted — a client reading positions can see who did NOT enter a doorway — and
-- §4.6's blockquote is explicit that this is FINE, because declining is a choice a survivor can also
-- make. The oracle only appears if the game distinguishes "did not" from "could not". It must not.
