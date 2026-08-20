--!strict
--[[
	tests/anti-cheat-budgets.test.luau

	Every client->server remote has a rate-limit budget, and every budget belongs to a real remote.

	WHY THE NAME LIST IS DUPLICATED HERE, AND WHY THAT IS THE LEAST-BAD OPTION
	--------------------------------------------------------------------------
	`src/shared/Remotes.luau` calls `game:GetService` at module scope, so Lune cannot require it — there
	is no DataModel. The list below is therefore a hand copy, and a hand copy can drift.

	It is still worth having, because drift in the direction that matters is caught from the other side:
	`check:remotes` fails on any remote used but not declared in Remotes.luau, and the EXTRA_BUDGETS
	assertion below fails on any budget naming a remote this list does not carry. What survives both is
	the narrow case of a remote added to Remotes.luau and to nothing else — which the C41 sweep
	("every OnServerEvent handler consults AntiCheatService") is the real answer to.

	The clean fix is a check script that parses both files. It is named in the plan's Follow Ups rather
	than built here, because C02 is not the chunk that should be growing the harness.
]]

local Config = require("../src/shared/Config")

-- Hand copy of Remotes.EVENTS_UP, last synced at C34. See the header for why.
-- C25 checked this list and added NOTHING: the quick-chat wheel ships on the `RequestQuickChat`
-- entry that was already here, because the world ping is a DERIVED FIELD on the broadcast rather
-- than a second remote. A ping remote would have handed the client a "draw an arrow anywhere"
-- primitive — including on top of a player, which accuses by geometry while the phrase says
-- something innocent.
local UP_REMOTES = {
	"RequestTaskProgress",
	"RequestTimingStop",
	"RequestTransform",
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
	-- C15. The one up-remote that is not a Request: a ghost REPORTS where its client-side body is,
	-- because ghosts have no server character. Named differently on purpose — it is the only remote in
	-- the game whose payload the server cannot independently verify, and the name should say so.
	"ReportGhostPosition",
	"RequestGhostSpook",
	"RequestEquipCosmetic",
	-- C34. The equip's sibling, and a separate remote rather than an argument on it: a shop press and
	-- a wardrobe press are different intents, and one remote doing both means an accidental tap on a
	-- cycler can spend coins.
	"RequestBuyCosmetic",
	"RequestClaimDaily",
	-- C21. Both argument-free button presses. `RequestStartTrial` is the only remote in the game whose
	-- handler spawns an NPC and teleports a character, which is why it is budgeted rather than left to
	-- `AllowUnbudgetedRemote = false` to refuse silently.
	"RequestStartTrial",
	"RequestEndTrial",
	-- C22. The trial's own throw. Separate from RequestThrowSalt because ItemService resolves against
	-- the round phase, and a trial runs at IDLE.
	"RequestTrialThrow",
}

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

--------------------------------------------------------------------------------
-- Coverage, both directions
--------------------------------------------------------------------------------

for _, name in UP_REMOTES do
	local budget = Config.AntiCheat.Budgets[name]

	check(`{name} has a declared budget`, budget ~= nil)

	if budget then
		check(
			`{name} allows at least one request`,
			budget.Capacity >= 1,
			`Capacity={budget.Capacity}`
		)
		check(
			`{name} refills, so the bucket is not a one-shot`,
			budget.RefillPerSecond > 0,
			`RefillPerSecond={budget.RefillPerSecond}`
		)
	end
end

local declared = {}
for _, name in UP_REMOTES do
	declared[name] = true
end

for name in Config.AntiCheat.Budgets do
	check(`the budget for {name} names a remote that exists`, declared[name] == true)
end

--------------------------------------------------------------------------------
-- The relationships. A limiter tighter than legitimate play is a gameplay bug.
--------------------------------------------------------------------------------

-- Spec §4.4: task progress is reported as PRESENCE while the server accumulates. A player standing at
-- a task point reports at least as often as the HUD updates, so a slower refill throttles correct play.
check(
	"task progress refills faster than the snapshot tick",
	Config.AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond
		>= 1 / Config.Round.SnapshotInterval,
	`refill={Config.AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond}`
)

-- Spec §4.3: the Aswang may transform once per kill cycle. One token must be available at least that
-- often or the limiter, not the cooldown, becomes the thing gating the monster.
check(
	"a transform token is available well inside the kill cooldown",
	1 / Config.AntiCheat.Budgets.RequestTransform.RefillPerSecond <= Config.Monster.KillCooldown,
	`{1 / Config.AntiCheat.Budgets.RequestTransform.RefillPerSecond}s per token`
)

-- Spec §4.6: one pouch carried at a time, so a burst larger than the carry limit is never legitimate —
-- but it must at least cover it, plus a retry.
check(
	"salt throws burst at least as far as the carry limit",
	Config.AntiCheat.Budgets.RequestThrowSalt.Capacity >= Config.Salt.CarryLimit
)

-- Spec §4.7: one spook per round. Capacity below that refuses the feature outright.
check(
	"the ghost can afford its one spook",
	Config.AntiCheat.Budgets.RequestGhostSpook.Capacity >= Config.Ghost.SpooksPerRound
)

--[[
	§4.4, C09. The honest cadence at a timing bar is one stop per sweep, so a refill slower than that
	throttles a player for playing the minigame at the only rate the minigame allows. This is the same
	failure the RequestTaskProgress budget's comment warns about, one remote over.
]]
check(
	"an honest timing player out-paces nothing but the bar",
	Config.Tasks.TimingBarPeriod > 0
		and 1 / Config.Tasks.TimingBarPeriod
			< Config.AntiCheat.Budgets.RequestTimingStop.RefillPerSecond,
	`{1 / Config.Tasks.TimingBarPeriod}/s vs refill=`
		.. `{Config.AntiCheat.Budgets.RequestTimingStop.RefillPerSecond}/s`
)

--------------------------------------------------------------------------------
-- The policy switches
--------------------------------------------------------------------------------

-- C02 is log-only by design; C41 turns this off with real data behind it. Pinned so that flipping it
-- early is a deliberate act that breaks a test rather than a quiet edit.
check("rate limiting is still log-only until C41", Config.AntiCheat.LogOnly == true)

-- Fail closed. See the Config comment.
check("an unbudgeted remote is refused", Config.AntiCheat.AllowUnbudgetedRemote == false)

check("a request costs at least one token", Config.AntiCheat.DefaultCost >= 1)

--[[
	C25, and the second half of the plan's Step 2.4 — dropped by the first implementation and caught
	by a plan audit. It was true by coincidence, which is exactly the state this file exists to end.

	A wheel is pressed in bursts: you say "Body here!" and "Run!" in the same breath. A capacity below
	that throttles the communication system §4.5 says must not be cut, and the symptom is a player
	pressing a button that silently does nothing mid-chase.
]]
check(
	"the quick-chat wheel bursts wide enough for consecutive calls",
	Config.AntiCheat.Budgets.RequestQuickChat.Capacity >= 3,
	`Capacity={Config.AntiCheat.Budgets.RequestQuickChat.Capacity}`
)

--[[
	AND A TOKEN MUST RETURN BEFORE THE LAST MESSAGE HAS FADED. If refilling took longer than a message
	stays on screen, a player would watch their own words disappear before they could add to them,
	which reads as the feature being broken rather than rate-limited.
]]
check(
	"a quick-chat token refills before a message fades",
	1 / Config.AntiCheat.Budgets.RequestQuickChat.RefillPerSecond
		<= Config.QuickChat.MessageLifetimeSeconds,
	`{1 / Config.AntiCheat.Budgets.RequestQuickChat.RefillPerSecond}s per token vs `
		.. `{Config.QuickChat.MessageLifetimeSeconds}s on screen`
)

if failures > 0 then
	error(`{failures} anti-cheat budget failure(s)`, 0)
end

print(`  PASS  anti-cheat-budgets: {#UP_REMOTES} remotes budgeted, {checked} assertions`)
