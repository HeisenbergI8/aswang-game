--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau:9-13, 45-107, 647
	Read for V03 as the reference service shape AND as the owner of the phase. SearchService
	subscribes; it never sets. 1296 lines; only the surface V03 touches is excerpted.
]]

--[[
	IMPORTANT — THE RULE, from the header (RoundService.luau:9-13):

	  "DESIGN RULE: nothing outside this module mutates the phase. Other services subscribe via
	   RoundService.PhaseChanged. Round logic is the single most bug-prone area of a game like this;
	   funnelling every transition through one SetPhase() function is what keeps it debuggable."

	`setPhase` is a FILE-LOCAL at line 647, so this is not merely convention — it is unreachable from
	outside. V03 needs nothing from it.
]]

-- IMPORTANT SearchService must also never DELAY a transition. `seedLayout` runs synchronously inside
-- the STARTING handler and must not yield: `GetTagged`, `table.sort`, `SearchPool.evaluate` and
-- `ContainerLayout.draw` are all non-yielding, and `Random.new()` is too. If a future step wants to
-- do anything async at seed time it must task.spawn it and accept that the layout may be nil for a
-- frame.
RoundService.PhaseChanged = Instance.new("BindableEvent") -- :77

-- NOTE This is the subscription API. `RoundService.PhaseChanged.Event:Connect(onPhaseChanged)` in
-- Start, exactly as ItemService:694 does. The handler receives the new phase and nothing else.

--------------------------------------------------------------------------------
-- The three queries V03 calls, and the one it must NOT.
--------------------------------------------------------------------------------

function RoundService.GetPhase(): RoundPhase -- :86
-- V03 gates every search on this being Enums.RoundPhase.Active.

function RoundService.GetAswangUserId(): number? -- :99
-- IMPORTANT "Deliberately NOT exposed to any client-facing code path." AND NOT TO SEARCHSERVICE
-- EITHER. §4.4 has the Aswang searching on identical rules and Amendment A2 generalises it: any
-- activity the monster cannot perform sincerely becomes an oracle that identifies it. This symbol
-- must not appear anywhere in SearchService.luau. It is the single grep an auditor should run first.

function RoundService.GetPlayerState(player: Player): PlayerState -- :103
-- NOTE Returns Enums.PlayerState.Lobby for an unknown player, so it is total and needs no nil guard.
-- V03 requires Alive to start OR continue a hold; DEAD and SPECTATOR both fail, which is how a
-- mid-round joiner and a killed player are handled by one line rather than two.

--[[
	NOTE — SERVER-ONLY STATE, AND THE SHAPE V03 COPIES (RoundService.luau:45-75).

	  local state = { ... }  -- "SERVER-ONLY state. Never replicate this table."

	Every service in this repo keeps its secrets in a file-local table keyed by UserId and exposes
	QUERIES rather than the table. SearchService's `layout`, `opened`, `holds`, `occupied` and
	`foundByPlayer` follow it. Note also that `PlayerStates` is keyed by UserId rather than by Player —
	the same choice V03 makes, and for the same reason: a Player instance goes away, a UserId does not,
	so cleanup on PlayerRemoving is a single nil assignment.
]]

--[[
	NOTE — THE TICK LOOP SHAPE (RoundService.luau:1272-1278), which V03 copies verbatim:

		task.spawn(function()
			while true do
				step()
				task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
			end
		end)

	ItemService:784-789 has the identical block with the identical waiver text. Three copies agreeing
	is better than a fourth number: 0.25 is the repo's server-side tick, and the waiver comment is
	what keeps `check:config` quiet without hiding it.
]]

--[[
	IMPORTANT — WHAT `Start()` ORDER BUYS (RoundService.luau:1265-1270).

	  "Connections and loops go first; the player backfill, which is the part that touches remotes and
	   could throw, goes last."

	And init.server.luau starts RoundService LAST of all services, so every subscriber is connected
	before a phase can change. That is why SearchService's SERVICE_ORDER position must be ABOVE
	RoundService: a SearchService started afterwards could miss the STARTING that seeds its layout, and
	the resulting nil layout would NOT warn — only the EMPTY path warns, and this would not take it.
	That failure looks like "the map has no items in it" and points at the map.
]]

--[[
	QUESTION — DOES A HOLD NEED TO SURVIVE `ENDING`?

	V03 says no: every phase that is not ACTIVE releases every hold. The alternative — letting a hold
	that began at second 299 finish during ENDING — would hand a player an item after the round
	resolved. §4.8's reveal is running by then and nothing can consume the find. Releasing is right,
	and it is also the only choice that keeps `opened` and `layout` consistent with `holds` through the
	INTERMISSION clear.
]]
