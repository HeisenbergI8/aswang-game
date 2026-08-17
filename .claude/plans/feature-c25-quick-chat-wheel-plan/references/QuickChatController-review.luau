--!strict
--[[
	REVIEW — src/client/Controllers/QuickChatController.luau:1-19 (the whole file)

	Nineteen lines, all of it stub. Reviewed in full only because the file IS this short; the value
	here is the TODO, which turns out to be a design instruction rather than a placeholder.
]]

--[[
	QuickChatController — The radial quick-chat wheel.

	Milestone: M7
	Spec: docs/MVP-SPEC.md
]]

local QuickChatController = {}

-- TODO(M7): 8-phrase radial menu + world ping.
-- Voice chat needs 13+ verification and typing mid-chase is impossible, so
-- this IS the communication system. Do not cut it (spec §4.5).

function QuickChatController.Init() end

function QuickChatController.Start() end

return QuickChatController

--[[
	NOTE — the TODO names both deliverables and no more: "8-phrase radial menu + world ping". That is
	the scope line C25's row and §C22's warning both draw, and it is worth quoting back at any point
	during implementation where the wheel starts wanting a history panel, a mute list, a custom
	phrase slot or a reply. None of those is in §4.5 and none is in this TODO.

	IMPORTANT — the two empty lifecycle functions are the contract this file must keep. Both are
	called by `init.client.luau` under pcall, `Init` for every controller before any `Start`. The plan
	puts `buildWheel` in `Init` and the remote connection in `Start`, which is the same split
	TaskController and GhostController use — construct in Init, subscribe in Start, so no handler can
	fire against a half-built GUI.

	NOTE — there is no state here to preserve and no caller to keep compatible. `grep`ing the tree for
	`QuickChatController` finds only its entry in CONTROLLER_ORDER, so Step 4.1 is a free rewrite
	rather than a migration. That is unusual enough in this repo to be worth stating.

	QUESTION — resolved: does the stub's `Milestone: M7` header need updating to name C25? Yes, and
	the plan's Step 4.1 diff does it — every other controller in this repo cites its chunk (C15, C20,
	C21), and a header that names only the milestone is the one that goes stale first.
]]
