--!strict
--[[
	SearchController — what the six seconds look like from inside. (V03, §4.4)

	OWNS NO TRUTH, and in this file that is not a slogan. The server decides whether a search started,
	whether it finished and what was in the container; this file holds a deadline so a bar can be drawn
	between two messages, and drops it the moment the server says otherwise. A client-side timer that
	completed on its own would be a client deciding it found something.

	NO CONTAINER IS NAMED, IN EITHER DIRECTION. The request carries no argument — the server resolves
	the nearest container from this player's own character position — and the update carries no id
	back. So there is nothing in this controller that could be logged, differenced or accumulated into
	a map of where the items are, which is the property §6.2 asks for and `Types.SearchUpdatePayload`
	explains at length.

	NO NEW LABEL AND NO NEW HUD. The find renders through `OnboardingController.ShowLine`, which
	already exists and is already used this way by `TeachingService`'s cues. A carry slot with an icon
	is V08's — this chunk grants no item, so a carry HUD would be drawing something that is not there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnboardingController = require(script.Parent.OnboardingController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)

local SearchController = {}

-- os.clock() at which the current hold is due to finish, or nil when not searching. A DISPLAY
-- estimate: the server owns the real deadline and re-derives it every tick.
local holdEndsAt: number? = nil

function SearchController.IsHolding(): boolean
	return holdEndsAt ~= nil
end

--[[
	0 to 1 through the current hold, or nil when there is none. Exposed for the bar a later HUD chunk
	will draw; nothing renders it yet, and that is why this controller adds no GUI of its own.

	CLAMPED AT 1 RATHER THAN COMPLETING. Reaching 1 means "the server should be about to answer", not
	"the search succeeded" — the server's tick runs at 0.25s, so the bar can sit full for a moment
	before SEARCH_OK arrives. A bar that cleared itself at 1 would be the client deciding.
]]
function SearchController.GetHoldFraction(): number?
	local endsAt = holdEndsAt

	if endsAt == nil then
		return nil
	end

	local remaining = math.max(endsAt - os.clock(), 0)

	return math.clamp(1 - remaining / Config.Search.SearchTime, 0, 1)
end

-- Player-facing copy lives on the client, the same rule `TeachingLines` follows: the payload carries
-- an ItemType, never a sentence, so text never crosses the wire.
local FOUND_LINES: { [string]: string } = {
	SALT = "You found a pouch of salt.",
	BAWANG = "You found bawang.",
	BUNTOT_PAGI = "You found the buntot pagi.",
}

local function onUpdate(payload: Types.SearchUpdatePayload)
	if payload.Verdict == "SEARCH_STARTED" then
		holdEndsAt = os.clock() + payload.HoldSeconds
		return
	end

	-- EVERY other verdict ends the hold. Listing them individually would mean a verdict added later
	-- silently leaves a bar on screen forever.
	holdEndsAt = nil

	if payload.Verdict ~= "SEARCH_OK" then
		--[[
			REFUSALS ARE SILENT IN V03, deliberately. A line for each of six refusal reasons is copy
			that has to be written, localised and tuned, and §4.4's loop is worth playtesting before
			any of it is. V16 asks whether searching feels like survival or a chore; six error messages
			are a good way to make it feel like a chore before anyone has answered that.
		]]
		if Config.Debug.VerboseLogging then
			print(`[SearchController] {payload.Verdict}`)
		end

		return
	end

	local found = payload.Found

	if found == nil then
		-- §4.4: "You will open empty ones, and that is the point."
		OnboardingController.ShowLine("Empty.")
		return
	end

	OnboardingController.ShowLine(FOUND_LINES[found] or "You found something.")
end

function SearchController.Init()
	holdEndsAt = nil
end

function SearchController.Start()
	Remotes.Get("SearchUpdate").OnClientEvent:Connect(onUpdate)
end

return SearchController
