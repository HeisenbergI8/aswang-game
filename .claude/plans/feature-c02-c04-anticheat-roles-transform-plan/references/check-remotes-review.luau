--!strict
--[[
	REVIEW — .claude/scripts/check-remotes.mjs

	Read because Steps 1.4 and 5.3 are gated on it, and because what it does NOT fail on changes what
	those steps can honestly claim.
]]

-- IMPORTANT — it parses the two lists out of Remotes.luau rather than duplicating them, using source
-- with COMMENTS ALREADY STRIPPED. So Step 1.4's comment-only edits inside EVENTS_DOWN / EVENTS_UP
-- cannot change what the file declares. Confirmed by reading lib/luau-source.mjs.
local lists = declared(readSource("src/shared/Remotes.luau").withStrings)

-- IMPORTANT — only the 40 characters after `Remotes.Get("Name")` are inspected for direction. A remote
-- captured into a variable and fired later is ALLOWED and unchecked (its own self-test pins this). So
-- both new call sites in this plan chain inline:
--   Remotes.Get("RequestTransform").OnServerEvent:Connect(...)   -- server, UP  ✅
--   Remotes.Get("MonsterTransformed"):FireAllClients(payload)    -- server, DOWN ✅
--   Remotes.Get("RoleAssigned"):FireClient(player, payload)      -- server, DOWN ✅
--   Remotes.Get("RequestTransform"):FireServer()                 -- client, UP  ✅
--   Remotes.Get("MonsterTransformed").OnClientEvent:Connect(...) -- client, DOWN ✅

--[[
	IMPORTANT — declared-but-unused is a NOTE, never a failure:

		"Declared-but-unused is reported as a NOTE, never a failure. The scaffold declares the whole
		 network surface up front on purpose — that is what makes it auditable at a glance — so failing
		 on it would mean the repo is red until the last milestone lands."

	Consequence for Step 1.4: `npm run check:remotes` does NOT prove the three names exist. It proves
	nothing in the tree USES an undeclared or wrong-direction remote. The existence half was proven by
	reading, and it is recorded in Remotes-review.luau.
]]

--[[
	NOTE — why this is the first check to reach for, quoted:

		"`Remotes.Get(name)` resolves through `folder:WaitForChild(name)` on the client. A name the
		 server never created does not error — IT HANGS FOREVER. The screen loads, nothing happens, no
		 output, no stack trace."
]]
