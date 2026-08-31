--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau (1241+ lines). Phase 5 Step 5.1 only.

	The reference service shape, and the file that owns the snapshot. V08 adds one field producer and
	one registration function, and the dependency direction is why the second one exists.

	Cited against the file as read on 2026-08-29.
]]

-- src/server/Services/RoundService.luau:23-36 — the requires
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local RoleService = require(script.Parent.RoleService)
local ShutdownFlush = require(script.Parent.Parent.ShutdownFlush)
local BodyTransitions = require(Shared.pure.BodyTransitions)
local RejoinResolve = require(Shared.pure.RejoinResolve)
local RoundTransitions = require(Shared.pure.RoundTransitions)
local Types = require(Shared.Types)
-- IMPORTANT: ONE service require, `RoleService`. ItemService requires THIS service
-- (ItemService.luau:34), so a `require(script.Parent.ItemService)` here is a cycle — and Luau answers
-- a cycle with a partially-initialised table rather than an error, so it would fail at runtime in
-- whichever direction init.server.luau resolved first. That is the whole reason Step 5.1 injects a
-- provider instead.

-- src/server/Services/RoundService.luau:617-633 — buildSnapshot
--[[
	Everything a HUD needs and nothing else. Compare against Types.ClientRoundSnapshot: there is no
	AswangUserId field to forget to strip, because the type does not have one.

	`YourRole` is deliberately left unset. The snapshot is built per player, so a role here would be
	*technically* safe — but RoleAssigned (fired to exactly one player) is the single allowlisted
	carrier of a role in `check-secrecy.mjs`, and one carrier is auditable in a way that two are not.
]]
local function buildSnapshot(player: Player): Types.ClientRoundSnapshot
	return {
		Phase = state.Phase,
		SecondsRemaining = RoundService.GetSecondsRemaining(),
		RoundNumber = state.RoundNumber,
		YourState = RoundService.GetPlayerState(player),
	}
end
-- NOTE: four fields; `YourCarriedItem` is the fifth and V02 deliberately left it unproduced.
-- IMPORTANT: "one carrier is auditable in a way that two are not" is the standard V08's new field
-- must meet, and it does — `YourCarriedItem` has exactly one producer (the injected reader) and one
-- consumer (UIController). Do NOT add a second channel for the carry; that is the reason Step 5.1
-- picks the provider seam over an ItemService-owned `CarryUpdate` remote.

-- src/server/Services/RoundService.luau:635-641
-- Per player, not FireAllClients: YourState differs between a survivor and a mid-round spectator,
-- and a broadcast could only ever carry one of them.
local function broadcastSnapshot()
	for _, player in Players:GetPlayers() do
		snapshotRemote:FireClient(player, buildSnapshot(player))
	end
end
-- IMPORTANT: THE STRUCTURAL PROPERTY THAT MAKES `YourCarriedItem` SAFE, and Types.luau:438-441 cites
-- it by name. This loop already exists for YourState's sake, so the carry field costs no new
-- send-shape decision. There is no broadcast form of this payload to accidentally put an inventory on.
-- NOTE: three other call sites fire it individually (:639, :933, :1029) — on a kill, on a join. Each
-- will now carry the carry field too, which is correct: a killed player's slot is emptied by Step
-- 3.4's death path, and the immediate snapshot after MarkKilled is how their HUD learns.

-- src/server/Services/RoundService.luau:86-128 — the public getters
function RoundService.GetPhase(): RoundPhase
function RoundService.GetPlayerState(player: Player): PlayerState
function RoundService.GetAswangUserId(): number?
-- NOTE: the three ItemService already calls. `GetAswangUserId` is called EXACTLY ONCE in ItemService,
-- inside resolveThrow, and Step 5.4's check is that it stays exactly once — grep the finished file.
-- NOTE: `GetPhase` and `GetPlayerState` feed every pure module in this plan. Neither is a secret;
-- both ride the snapshot already.

-- src/server/Services/RoundService.luau:841 and :1032-1040
function RoundService.MarkKilled(player: Player, causedByKill: boolean?)
local function onPlayerRemoving(player: Player)
	--[[
		THE HUSK (§6.4, C15). A disconnect during a live round leaves the body behind and CHANGES
		NOTHING about the player's state.
	]]
end
-- IMPORTANT: THE TWO EDGE CASES STEP 3.4 MUST HANDLE FROM ITEMSERVICE'S SIDE. `MarkKilled` is the one
-- place a player becomes DEAD, and ItemService must not hook it directly — the dependency runs the
-- right way for a require, but §4.6 needs the position the player DIED at, which means watching the
-- character rather than the state change.
-- IMPORTANT: the husk rule is what ItemService.luau:715-727 left as an open question, and V08 answers
-- it: the item goes to the floor at the husk's position. See that review.
-- NOTE: `RoundService.GetHuskCharacter(userId)` (:1186) is public and is how Step 3.4 finds where to
-- drop a departing player's item.

-- src/server/Services/RoundService.luau:77
RoundService.PhaseChanged = Instance.new("BindableEvent")
-- NOTE: the seam ItemService already subscribes to, and the pattern the plan's provider seam is
-- compared against. A BindableEvent cannot do the provider's job — events PUSH, and buildSnapshot
-- needs to PULL synchronously at snapshot time. That asymmetry is the written justification Hard
-- Rule 4 asks for when deviating from the established shape.
