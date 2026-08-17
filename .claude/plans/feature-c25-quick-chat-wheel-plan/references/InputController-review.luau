--!strict
--[[
	REVIEW — src/client/Controllers/InputController.luau:322-368

	Read for the mobile precedent. This file contains the only `createTouchButton = true` in the game
	and the reasoning that justified it — which is the reasoning C25's wheel button reuses, and the
	caveat it inherits.
]]

	UIController.BindActions({
		Transform = function()
			performTransform()
		end,
		Kill = function()
			performKill()
		end,
	})

-- NOTE: this registration exists because "C18 shipped a KILL button that fired with no target and
-- silently burned the Aswang's rate limit" — one behaviour, two entry points, kept as one function.
-- IMPORTANT for C25: the wheel does NOT go through this. Its button is its own UI, built by
-- QuickChatController, so there is no second copy to keep in sync and registering it here would
-- create the duplication this mechanism exists to remove.

	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)
	ContextActionService:BindAction(TASK_ACTION, onTaskAction, false, Enum.KeyCode.E)
	ContextActionService:BindAction(TIMING_ACTION, onTimingAction, false, Enum.KeyCode.R)

-- NOTE: four binds, all `false` for createTouchButton, each commented as "a known hole rather than an
-- oversight" deferred to C27. Taken as a group they establish that mobile buttons are C27's subject
-- and that an exception needs an argument.

	--[[
		`Q`, and `true` for createTouchButton — THE FIRST BIND IN THIS FILE THAT ASKS FOR ONE.

		... Salt is the case where that trade stops being defensible: §5 puts ~60% of players on a
		phone, and §4.6 is the ONLY counterplay in the game. A mobile player with no throw button is
		not missing a convenience, they are playing a version of the round with no answer to the
		monster at all — which is Appendix C's failure mode, not a polish item.
	]]
	ContextActionService:BindAction(THROW_ACTION, onThrowAction, true, Enum.KeyCode.Q)

--[[
	IMPORTANT — THIS IS THE ARGUMENT C25 REUSES, and the parallel is close enough to state precisely.

	Salt's case: §5 puts 60% on a phone, §4.6 is the only counterplay, so a phone player with no
	button has no answer to the monster.

	The wheel's case: §5 puts 60% on a phone, §4.5 is the only communication channel (voice needs 13+
	verification this audience lacks, typing mid-chase is impossible), so a phone player with no
	wheel cannot communicate at all. That is the accusation game removed for most of the players, and
	§4.5 says "do not cut it" in bold about exactly this.

	So C25 is the SECOND exception to the C27 deferral, on the same shape of argument. Anything beyond
	one button for this one feature is C27 and out of scope.

	NOTE — the salt comment adds a second reason the touch button works there: "the throw is aimed by
	the CAMERA, which a phone player is already controlling, so the button carries no aiming burden."
	The wheel has the analogous property for a different reason — selection is ANGULAR, +/-22.5 degrees
	per sector, so the gesture carries no positional-accuracy burden either. Both features work on a
	phone because neither asks the thumb to be precise.

	IMPORTANT — THE CAVEAT C25 INHERITS VERBATIM, from the `R` and `Q` binds:
	  "⚠ `Q` is NOT confirmed free of a CoreScript claim ... C08 shipped unreachable because
	   ProximityPrompt's default `E` silently swallowed an identical bind, and nothing static can
	   prove `Q` is unclaimed. Playtester."
	C25's key is a placeholder for the same reason and carries the same flag. This has already cost
	this project one shipped-unreachable chunk.

	QUESTION — UNRESOLVED, in the plan's Follow Up 4: `ContextActionService` places touch buttons in a
	CoreGui-managed region. Nothing in this file or anywhere in the repo establishes how a SECOND
	requested button is positioned relative to the salt one, or whether the order is stable between
	sessions. If they collide, salt is the one that must win — see the argument above. Fallback named
	in Step 5.1: a hand-placed button in QuickChatController's own ScreenGui.
]]
