--!strict
--[[
	FeedController — what the five seconds look like from inside. (V06, §4.3)

	OWNS NO TRUTH, and here that is not a slogan either. The server decides whether a feed started,
	whether it finished and whether the heal was paid; this file holds a deadline so a bar can be drawn
	between two messages, and drops it the moment the server says otherwise. A client-side timer that
	completed on its own would be a client deciding it had healed.

	IT IS THE ONLY CONTROLLER ONLY ONE PLAYER EVER RUNS MEANINGFULLY, and that is worth stating because
	it looks like a secrecy problem and is not. Every client loads this file — `src/client/` is
	replicated wholesale — and every client connects the handler. Four of the five never receive a
	payload, so the branch never runs, and nothing about that is observable to anyone but themselves.
	The asymmetry that WOULD leak is on the server side and there is none: `FeedUpdate` is FireClient
	to the feeder, never a broadcast, so no client can time or count another's feeds.

	NO NEW HUD, AND NO HEALTH READOUT. §4.6 is explicit that a health value attached to a player is the
	reveal, so a "you healed 25" line is not a thing this file may draw even to the Aswang — the moment
	it exists, a screen recording of an Aswang's client is a document of the health system, and the
	number has one home on the server. The feed renders through `OnboardingController.ShowLine`, which
	`SearchController` and `TeachingService` already use this way, plus whatever bar `UIController`
	draws from `IsFeeding()`.

	NO INPUT, EITHER. There is no RequestFeed and there is nothing to press — §4.3 makes the feed a
	consequence of a kill, not a choice — so this controller listens and never fires.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnboardingController = require(script.Parent.OnboardingController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)

local FeedController = {}

-- os.clock() at which the current feed is due to finish, or nil when not feeding. A DISPLAY estimate:
-- the server owns the real deadline and re-derives it four times a second.
local feedEndsAt: number? = nil

function FeedController.IsFeeding(): boolean
	return feedEndsAt ~= nil
end

--[[
	SECONDS LEFT, FOR WHOEVER DRAWS THE BAR. Clamped at zero rather than allowed to go negative: the
	server's tick can land up to a quarter-second after the deadline, and a bar that reads -0.2 for a
	frame is the kind of thing that ships.
]]
function FeedController.SecondsRemaining(): number
	local endsAt = feedEndsAt

	if endsAt == nil then
		return 0
	end

	return math.max(endsAt - os.clock(), 0)
end

local function onUpdate(payload: Types.FeedUpdatePayload)
	if payload.Verdict == "FEED_STARTED" then
		feedEndsAt = os.clock() + payload.HoldSeconds
		OnboardingController.ShowLine("Feeding.")
		return
	end

	-- Both endings drop the deadline. THE CLIENT NEVER COMPLETES A FEED ON ITS OWN — if this file
	-- decided that `os.clock() >= feedEndsAt` meant success, a client whose FEED_INTERRUPTED was
	-- dropped would draw a heal that did not happen.
	feedEndsAt = nil

	if payload.Verdict == "FEED_INTERRUPTED" then
		-- ONE LINE FOR ALL SIX INTERRUPTION PATHS. `Types.FeedVerdict` collapses them on purpose:
		-- telling the Aswang whether that was salt or a drift is a fact about a survivor's aim.
		OnboardingController.ShowLine("Interrupted.")
		return
	end

	-- §4.3: the feed restored health and, once V07 lands, the ability to hide. NO NUMBER — §4.6 says
	-- a health value attached to a player is the reveal, and that holds on the monster's own screen.
	OnboardingController.ShowLine("Fed.")
end

function FeedController.Init()
	feedEndsAt = nil
end

function FeedController.Start()
	Remotes.Get("FeedUpdate").OnClientEvent:Connect(onUpdate)
end

return FeedController
