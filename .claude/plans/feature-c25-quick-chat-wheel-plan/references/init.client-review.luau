--!strict
--[[
	REVIEW — src/client/init.client.luau:17-24, 60-70

	READ TO ANSWER ONE QUESTION: where is QuickChatController registered, and does C25 need to move it?

	ANSWER: it is fourth, before InputController, and it needs NO CHANGE. The comment sitting under it
	was written for a controller that did nothing yet and describes C25's requirement exactly.
]]

local CONTROLLER_ORDER = {
	"AudioController",
	"CameraFXController",
	"UIController",
	"QuickChatController",
	-- Before InputController, deliberately. The order governs Init/Start rather than requires — the
	-- require is direct — but InputController.Start binds a key that calls into this controller, and a
	-- bind that can fire before Init has run is a race worth not having.
	"TaskController",
	-- ...
	"InputController",
}

--[[
	IMPORTANT — THE COMMENT IS ALREADY CORRECT FOR C25, and more precisely than it looks.

	The plan has `QuickChatController.Init` call `buildWheel`, and Step 5.1 binds the wheel action.
	Wherever that bind ends up living — in this controller's own Start, or registered through
	InputController the way Transform and Kill are — a press that arrives before `Init` has built the
	GUI would hit a nil `wheelFrame`. This ordering is what makes that unreachable.

	NOTE — the comment says the order governs Init/Start "rather than requires — the require is
	direct". That matters for C25's Step 4.1: `QuickChatController` requires `Config`,
	`QuickChatPhrases`, `Remotes` and `Types` at module scope, all from Shared, none of them a sibling
	controller. So it introduces no ordering dependency of its own and cannot create the one-way arrow
	TrialController documents at lines 39-46.

	QUESTION — resolved during planning: should the wheel bind go through `UIController.BindActions`,
	the way Transform and Kill do (InputController.luau:322-330)? NO. That registration exists so a
	HUD button and a key run the SAME code — it was added because C18 shipped a KILL button that
	fired with no target. The wheel's button IS its own UI and is built by this controller, so there
	is no second copy to keep in sync. Adding it to BindActions would create the duplication the
	mechanism exists to remove.
]]

--[[
	init.client.luau:60-70 — every controller is loaded under pcall.

	NOTE: `Init` and `Start` errors are caught and warned, not raised. So a QuickChatController that
	throws during `buildWheel` — a missing PlayerGui, a nil Config field — produces one warn line and
	a client with no wheel, while every other controller carries on. That is the right failure mode
	but it is a QUIET one: the playtester must confirm the wheel EXISTS, not just that the client
	booted. `print("[Client] Ready. N controllers loaded.")` at the end of this file will say 9
	either way.
]]
