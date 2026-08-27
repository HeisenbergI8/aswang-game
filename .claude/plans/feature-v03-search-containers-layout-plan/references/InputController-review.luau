--!strict
--[[
	REVIEW — src/client/Controllers/InputController.luau:3-26, 43-70, 262-282, 312
	Read for V03's client request path. This file's header contains the exact warning V03 re-triggers.
]]

--[[
	IMPORTANT — THE HEADER'S CLOSING PARAGRAPH (InputController.luau:25-26), AND V03 RE-OPENS IT:

	  "The hole this header used to name — mobile could not do a TASK, the thing all eight players do
	   all round — is closed. If it reopens, it reopens in `UIController.buildTouchPad`."

	V01 deleted tasks. §4.4 replaced them with SEARCHING, which is now "the thing all players do all
	round", and `buildTouchPad` draws Transform / Kill / Say / Salt — no Search. The hole is open again,
	in exactly the file the header predicted. §5 puts ~60% of players on a phone. Logged as the plan's
	one High-severity issue; it must close before V16's playtest or that playtest cannot answer its
	third question for most of its players.
]]

--[[
	IMPORTANT — THE BUG THAT MADE REGISTRATION A RULE (InputController.luau:9-12):

	  "THAT REGISTRATION IS NOT PLUMBING, IT IS THE FIX FOR A REAL BUG. C18's KILL button first built
	   its own request, omitted the target UserId, and so fired something the server refuses AFTER
	   spending a rate-limit token. Two implementations of one action drift; one implementation with
	   two triggers cannot."

	So V03's `performSearch` / `performCancelSearch` are plain functions registered with
	`UIController.BindActions`, and both the key bind and any future touch button call THEM.
]]

--[[
	IMPORTANT — NO BIND IN THIS FILE CREATES A TOUCH BUTTON (InputController.luau:17-24), and the
	reasoning is why V03's bind passes `false` like every other:

	  "a CAS touch button appears for EVERY client that runs the bind, so it cannot be Aswang-only (the
	   role gate lives inside the handler, not on the bind), cannot appear only while a timing bar
	   exists, and cannot be placed in a thumb zone this game chose. The pad does all three. What is
	   left in this file is the KEYS."
]]

local TRANSFORM_ACTION = "AswangTransform" -- :43
local KILL_ACTION = "AswangKill" -- :44
local THROW_ACTION = "SaltThrow" -- :45
-- + local SEARCH_ACTION = "SearchContainer" (Step 4.2)

--[[
	THE MODEL V03 COPIES — and the ONE line of it V03 deliberately omits.
]]
local function performTransform(): boolean -- :60
	-- IMPORTANT :51-58 — "GATED ON THIS CLIENT'S OWN ROLE, from its own RoleAssigned. Never on a
	-- broadcast, never on anything derived from another player. This gate is UX and rate-limit
	-- courtesy, NOT security: the server re-evaluates every rule [...] A compromised client can delete
	-- this check and gain exactly nothing, which is the correct relationship between a client-side
	-- gate and a server-side one."
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return false
	end

	-- NOTE :65-66 "No arguments. The server knows who fired it and reads every other input from its
	-- own state; anything passed here would be a client-supplied value the server must then refuse to
	-- trust." Exactly V03's two requests.
	Remotes.Get("RequestTransform"):FireServer()

	return true
end

--[[
	IMPORTANT — V03'S `performSearch` HAS NO ROLE GATE, AND THE ABSENCE IS THE DESIGN.

	Transform and Kill are Aswang verbs, so they check GetMyRole. Searching is everyone's: §4.4 has the
	Aswang searching on identical rules, because rummaging in a house is blending justified by
	mechanics rather than performed. A gate here would make the monster's CLIENT behave differently
	from a survivor's — Amendment A2's oracle in the one place nobody would think to look for it, since
	it would live in an input controller rather than in a service.

	Nor is there a client-side phase or distance pre-check. The client does not know `opened` and
	cannot; a local guess would only ever disagree with the server's verdict.
]]

	UIController.BindActions({ -- :262
		Transform = performTransform,
		Kill = performKill,
		Throw = performThrow,
		-- + Search = performSearch, CancelSearch = performCancelSearch (Step 4.2)
	})
-- IMPORTANT `UIController.ActionHandlers` (UIController.luau:249-253) is `{ Transform, Kill, Throw }`,
-- all `() -> ()`. Adding two fields to this literal WITHOUT widening that type is an analyze error.
-- Step 4.2 widens it. NOTE `() -> ()` accepts V03's `(): boolean` — Luau discards return values — so
-- the pair stays consistent with the three above.

	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T) -- :281
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F) -- :282
	ContextActionService:BindAction(THROW_ACTION, onThrowAction, false, Enum.KeyCode.Q) -- :312
	-- + SEARCH_ACTION on Enum.KeyCode.E (Step 4.2)

--[[
	QUESTION — EVERY EXISTING HANDLER HERE IS A PRESS, V03'S IS A HOLD.

	All three `on*Action` functions return early unless `inputState == Enum.UserInputState.Begin`, so
	no bind in this repo has ever handled `End` or `Cancel`. V03's does both, and it treats `Cancel` as
	a release because CAS fires it when a bind is unbound or the input is stolen — a chat box opening
	mid-hold. I have NOT confirmed that behaviour in this codebase, so it is flagged in the plan's
	Follow Ups; handling it costs one branch and being wrong about it costs nothing, whereas ignoring
	it and being wrong leaves a player holding a container no input can release.
]]
