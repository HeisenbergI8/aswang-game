--!strict
--[[
	tests/quick-chat-phrases.test.luau

	The phrase set is a CLOSED SET and the wheel's geometry is arithmetic. Both are exactly the kind
	of thing that is obviously right when written and quietly wrong six chunks later, and both are
	cheap to enumerate.

	THE `{name}` IFF IS THE ONE WORTH READING TWICE. A template carrying `{name}` for a phrase the
	server never resolves a target for renders the literal text "It's {name}!" to every player; a
	phrase that needs a target but has no slot silently drops the accusation and reads as a phrase
	that does nothing. Neither throws, and neither shows up in `analyze`.
]]

local Config = require("../src/shared/Config")
local QuickChatPhrases = require("../src/shared/pure/QuickChatPhrases")

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
-- The set itself. §4.5 names eight; C25's row and §C22 both say eight is the number.
--------------------------------------------------------------------------------

check(
	"§4.5 ships exactly eight phrases",
	#QuickChatPhrases.All == 8,
	`got {#QuickChatPhrases.All}`
)
check("the wheel has one sector per phrase", QuickChatPhrases.Sectors == #QuickChatPhrases.All)

local seenIds: { [string]: boolean } = {}
local seenOrders: { [number]: boolean } = {}
local targetTaking = 0
local pinging = 0
local ghostForbidden = 0

for _, phrase in QuickChatPhrases.All do
	check(`{phrase.Id} has a unique id`, seenIds[phrase.Id] ~= true)
	seenIds[phrase.Id] = true

	check(
		`{phrase.Id} has a unique sector`,
		seenOrders[phrase.Order] ~= true,
		`Order={phrase.Order}`
	)
	seenOrders[phrase.Order] = true

	check(
		`{phrase.Id}'s sector is in range`,
		phrase.Order >= 0 and phrase.Order < QuickChatPhrases.Sectors,
		`Order={phrase.Order}`
	)

	check(`{phrase.Id} has non-empty text`, #phrase.Text > 0)

	--[[
		THE IFF. `{name}` appears in the template if and only if the server resolves a target for it.
		Both directions matter and both fail silently — see this file's header.
	]]
	local hasSlot = string.find(phrase.Text, "{name}", 1, true) ~= nil

	check(
		`{phrase.Id}: has a name slot iff it needs a target`,
		hasSlot == phrase.NeedsTarget,
		`slot={hasSlot}, NeedsTarget={phrase.NeedsTarget}`
	)

	if phrase.NeedsTarget then
		targetTaking += 1
	end

	if phrase.Pings then
		pinging += 1
	end

	if not phrase.DeadMay then
		ghostForbidden += 1
	end
end

-- Every sector 0..7 is occupied. A gap would leave a wedge of the wheel that selects nothing, which
-- on a phone is a dead zone the thumb finds and the developer does not.
for sector = 0, QuickChatPhrases.Sectors - 1 do
	check(`sector {sector} is occupied`, seenOrders[sector] == true)
end

--[[
	EXACTLY ONE PHRASE RESOLVES A TARGET, and exactly that one is closed to dead players.

	These two counts are the security shape of the whole feature in two numbers. A second
	target-taking phrase is a second place the server picks a player from a position; a dead player-allowed
	accusation resolves "nearest" from a client-reported position the server cannot verify, which is
	the impersonation exploit C25's row forbids with one extra step.
]]
check("exactly one phrase takes a target", targetTaking == 1, `got {targetTaking}`)
check("exactly one phrase is closed to dead players", ghostForbidden == 1, `got {ghostForbidden}`)

local accuse = QuickChatPhrases.get("ACCUSE")

check("ACCUSE exists", accuse ~= nil)
check("ACCUSE is the target-taking one", accuse ~= nil and accuse.NeedsTarget == true)
check("ACCUSE is the one the dead may not send", accuse ~= nil and accuse.DeadMay == false)
check("ACCUSE does not also ping", accuse ~= nil and accuse.Pings == false)

check("some phrases ping", pinging > 0, `got {pinging}`)
check("not every phrase pings", pinging < #QuickChatPhrases.All, `got {pinging}`)

--------------------------------------------------------------------------------
-- Lookup. An unknown id must refuse rather than resolve.
--------------------------------------------------------------------------------

for _, phrase in QuickChatPhrases.All do
	local found = QuickChatPhrases.get(phrase.Id)

	check(`get("{phrase.Id}") round-trips`, found ~= nil and found.Id == phrase.Id)
end

check("an unknown id resolves to nil", QuickChatPhrases.get("NOT_A_PHRASE") == nil)
check("an empty id resolves to nil", QuickChatPhrases.get("") == nil)
-- The shapes a compromised client actually sends. None may resolve.
check("a lowercase id does not resolve", QuickChatPhrases.get("accuse") == nil)
check("a whitespace-padded id does not resolve", QuickChatPhrases.get(" ACCUSE ") == nil)

--------------------------------------------------------------------------------
-- `sectorFor`. Total over all reals, and correct on every boundary.
--------------------------------------------------------------------------------

local TAU = math.pi * 2
local SECTORS = QuickChatPhrases.Sectors
local SECTOR_WIDTH = TAU / SECTORS

-- The centre of each sector must map to that sector. This is the property a thumb relies on.
for sector = 0, SECTORS - 1 do
	local centre = sector * SECTOR_WIDTH

	check(
		`the centre of sector {sector} maps to itself`,
		QuickChatPhrases.sectorFor(centre) == sector,
		`got {QuickChatPhrases.sectorFor(centre)}`
	)
end

--[[
	A drag is accurate to +/-22.5 degrees, and that tolerance IS the mobile argument. Just inside
	either edge of a sector must still select it — if this fails, the wheel needs a steadier thumb
	than a player being chased has.
]]
local EPSILON = SECTOR_WIDTH * 0.4

for sector = 0, SECTORS - 1 do
	local centre = sector * SECTOR_WIDTH

	check(
		`just clockwise inside sector {sector} still selects it`,
		QuickChatPhrases.sectorFor(centre + EPSILON) == sector
	)
	check(
		`just anticlockwise inside sector {sector} still selects it`,
		QuickChatPhrases.sectorFor(centre - EPSILON) == sector
	)
end

--[[
	TOTAL OVER ALL REALS. `math.atan2` returns (-pi, pi], and the wrap point sits at straight up —
	which is sector 0, the one a player reaches for first. A function that answered nil, or a
	negative, or 8 anywhere here would drop precisely that sector.
]]
local PROBES = {
	0,
	-0,
	math.pi,
	-math.pi,
	TAU,
	-TAU,
	TAU * 3,
	-TAU * 3,
	0.0001,
	-0.0001,
	123.456,
	-123.456,
}

for _, angle in PROBES do
	local sector = QuickChatPhrases.sectorFor(angle)

	check(
		`sectorFor({angle}) is a valid sector`,
		sector >= 0 and sector < SECTORS and sector == math.floor(sector),
		`got {sector}`
	)
end

-- Rotating by a full turn changes nothing, which is what makes the wrap point safe.
for _, angle in PROBES do
	check(
		`sectorFor is periodic at {angle}`,
		QuickChatPhrases.sectorFor(angle) == QuickChatPhrases.sectorFor(angle + TAU)
	)
end

check(
	"sectorFor is deterministic",
	QuickChatPhrases.sectorFor(1.23) == QuickChatPhrases.sectorFor(1.23)
)

--------------------------------------------------------------------------------
-- The wheel's geometry against Config's accessibility floor.
--------------------------------------------------------------------------------

--[[
	EIGHT SECTORS ON A WHEEL OF THIS RADIUS MUST STILL CLEAR THE TOUCH-TARGET FLOOR.

	A sector's narrowest dimension is its arc at the radius, `2 * pi * r / 8`. Below
	`MinTouchTargetPx` it is a target that gets mis-hit mid-chase — and for this feature a mis-hit
	means accusing the wrong person, which is worse than sending nothing. Shrinking `WheelRadiusPx`
	for a tidier HUD is exactly the innocent-looking edit this catches.
]]
local arc = TAU * Config.QuickChat.WheelRadiusPx / SECTORS

check(
	"a wheel sector is wide enough to hit with a thumb",
	arc >= Config.QuickChat.MinTouchTargetPx,
	`arc={math.floor(arc)}px, floor={Config.QuickChat.MinTouchTargetPx}px`
)

-- The cancel radius must sit well inside the wheel, or cancelling and selecting overlap.
check(
	"the cancel radius is inside the wheel",
	Config.QuickChat.DeadRadiusPx > 0
		and Config.QuickChat.DeadRadiusPx < Config.QuickChat.WheelRadiusPx,
	`DeadRadiusPx={Config.QuickChat.DeadRadiusPx}, WheelRadiusPx={Config.QuickChat.WheelRadiusPx}`
)

if failures > 0 then
	error(`{failures} quick-chat-phrase failure(s)`, 0)
end

print(`  PASS  quick-chat-phrases: {checked} assertions over the closed set and the wheel`)
