--!strict
--[[
	REVIEW — src/client/Controllers/UIController.luau:249-295, 571-601, 773
	Read for V03 ONLY where Step 4.2 touches it: the ActionHandlers contract, and the touch pad that
	does NOT gain a button. 2011 lines; the rest was not read and is not reviewed.
]]

export type ActionHandlers = { -- :249
	Transform: () -> (),
	Kill: () -> (),
	Throw: () -> (),
	-- + Search: () -> (), CancelSearch: () -> ()   (Step 4.2)
}
-- IMPORTANT This type is the whole of Step 4.2's edit to this file. Adding fields to
-- InputController's `BindActions({...})` literal without widening it here is an analyze error, and
-- `gate-luau-analyze.mjs` typechecks at write time, so the two edits must land in one step.
-- NOTE `() -> ()` accepts V03's `(): boolean` handlers — Luau discards return values — which keeps
-- the pair consistent with the three above rather than introducing a second signature.

--[[
	NOTE — WHY V03 REGISTERS A PAIR WHERE EVERYTHING ELSE REGISTERS ONE (UIController.luau:255-263):

	  "[BindQuickChat] stays a PAIR because §4.5's gesture is press-drag-release rather than a tap: the
	   pad reports where the thumb went down and when it came up, and every decision in between is the
	   wheel's."

	§4.4's search is also a hold, so it needs both ends. Registering only `Search` would give a mobile
	player a way to start a search and no way to stop one — and since leaving RangeStuds is the only
	other release they could reach, they would have to walk away from every search they began.
]]

local function buildTouchPad(gui: ScreenGui) -- :571
	local aswangColumn = touchColumn(pad, "Aswang", 0) -- :589
	local mainColumn = touchColumn(pad, "Main", LAYOUT.TouchButton + LAYOUT.TouchGap) -- :590

	local transform = makeTouchButton(aswangColumn, "Transform", "SHIFT", 1, COLOUR.Aswang) -- :592
	local kill = makeTouchButton(aswangColumn, "Kill", "KILL", 2, COLOUR.Aswang) -- :593
	local say = makeTouchButton(mainColumn, "Say", "SAY", 1, COLOUR.Text) -- :594
	local salt = makeTouchButton(mainColumn, "Salt", "SALT", 2, COLOUR.Progress) -- :595

--[[
	IMPORTANT — FOUR BUTTONS, NO SEARCH. THIS IS THE PLAN'S ONE HIGH-SEVERITY ISSUE.

	Searching is the only activity in v2.0 (§4.4) and §5 puts ~60% of players on a phone, so V03 ships
	a core loop most players cannot perform. InputController's own header (:25-26) predicted exactly
	this file as where the hole would reopen.

	WHY V03 DOES NOT CLOSE IT HERE, stated plainly rather than hidden: I did not read `makeTouchButton`
	or `touchColumn` closely enough to write a paste-ready diff, and this repo's rule is that an
	unverified API shape gets flagged rather than invented. Two things a follow-up chunk will have to
	decide, neither of which is a one-liner:

	  · WHICH COLUMN. `mainColumn` holds Say and Salt at slots 1 and 2; a third slot means the pad's
	    Size (:581-584, "three buttons and two gaps", already waived) is sized for three ROWS in two
	    columns — so a fifth button may fit, but the geometry needs looking at rather than assuming.
	  · PRESS VS HOLD. Every existing touch button is a tap. Search needs down/up, which is what the
	    `Search` / `CancelSearch` pair registered in Step 4.2 is waiting to receive. `BindQuickChat`'s
	    press-drag-release plumbing (:264-267) is the nearest precedent and probably the model.

	The `ui-polish` skill is named in CLAUDE.md as the thing to load before any HUD change, and this is
	one. It is not V03's chunk; it must not be left past V16.
]]

--[[
	NOTE — THE SALT COUNTER'S HONESTY, WHICH V03'S SEARCH BAR SHOULD COPY (UIController.luau:287-295):

	  "Salt carried, counted BY THIS CLIENT from its own pickups and throws. The server owns the real
	   number and never sends it [...] So this is a display estimate, prefixed `~` on screen so a
	   tester reads it as a hint rather than a truth."

	`SearchController.GetHoldFraction()` is the same kind of value — a client-side estimate between two
	server messages. Nothing draws it yet. When something does, it must never COMPLETE on its own: the
	server's tick is 0.25s, so the bar can sit full for a moment before SEARCH_OK arrives, and a bar
	that cleared itself at 1.0 would be the client deciding it found something.
]]
