--!strict
--[[
	The six cosmetics — who may wear what, and what it costs (C34, §7, §8.2).

	C34's Verify line is the playtester equipping each one and screenshotting it, and that is the right
	evidence for "does it render". It is the wrong evidence for the rules underneath, all of which fail
	quietly:

	  · A cosmetic reachable by a path it should not be — a level unlock bought with coins, a gamepass
	    item granted for free — is a monetisation hole that nothing on screen names.
	  · A DEFAULT that is not owned means a fresh player is wearing something `evaluateEquip` refuses,
	    so their first equip press appears broken.
	  · The PHASE GATE is the one that costs real bugs: `MonsterService` captures every part's colour
	    at transform and restores exactly those on revert, so a skin equipped mid-round is either
	    silently undone or silently captured as the new baseline. That is C04's revert bug, reopened.

	And the shipped catalogue is checked against §7's actual sentence — "~6 unlockable cosmetics at
	launch" — because a catalogue is content that grows by accident.
]]

local Config = require("../src/shared/Config")
local Cosmetics = require("../src/shared/pure/Cosmetics")
local ProfileMigration = require("../src/shared/pure/ProfileMigration")

type Item = Cosmetics.Item

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

--[[
	A fixture catalogue, not the shipped one, so the rules are proven against arbitrary ids, prices and
	levels rather than against the six that happen to exist today. The shipped table gets its own
	section at the end.
]]
local FIXTURE: { Item } = {
	{
		Id = "d_skin",
		Slot = "Skin",
		Name = "plain",
		Source = "DEFAULT",
		Level = 0,
		Price = 0,
		Rgb = { 1, 2, 3 },
	},
	{
		Id = "by_level",
		Slot = "Skin",
		Name = "earned",
		Source = "LEVEL",
		Level = 6,
		Price = 0,
		Rgb = { 4, 5, 6 },
	},
	{
		Id = "by_coins",
		Slot = "Lantern",
		Name = "bought",
		Source = "COINS",
		Level = 0,
		Price = 300,
		Rgb = { 7, 8, 9 },
	},
	{
		Id = "by_pass",
		Slot = "DeathFX",
		Name = "paid",
		Source = "GAMEPASS",
		Level = 0,
		Price = 0,
		Rgb = { 1, 1, 1 },
	},
}

local NOTHING: { [string]: boolean } = {}

--------------------------------------------------------------------------------
-- Lookup and ownership
--------------------------------------------------------------------------------

check("find returns a known item", Cosmetics.find(FIXTURE, "by_coins") ~= nil)
check("find returns nil for an unknown id", Cosmetics.find(FIXTURE, "by_vibes") == nil)
check("find returns nil for an empty id", Cosmetics.find(FIXTURE, "") == nil)

--[[
	DEFAULTS ARE OWNED BY DEFINITION rather than by a row in the profile. `ProfileMigration.template`
	ships `Owned = {}` and `Equipped = { Skin = "default", … }`, so a fresh player is already WEARING
	three items that appear in nobody's inventory — and materialising them would cost a v2 migration
	for a fact that cannot change.
]]
local defaultItem = Cosmetics.find(FIXTURE, "d_skin") :: Item
local levelItem = Cosmetics.find(FIXTURE, "by_level") :: Item

check("a default is owned with an empty inventory", Cosmetics.isOwned(defaultItem, NOTHING))
check(
	"a non-default is not owned with an empty inventory",
	not Cosmetics.isOwned(levelItem, NOTHING)
)
check(
	"a non-default is owned once it is in the set",
	Cosmetics.isOwned(levelItem, { by_level = true })
)

--------------------------------------------------------------------------------
-- Level grants — idempotent, and cumulative
--------------------------------------------------------------------------------

--[[
	`grantsAtLevel` answers "what SHOULD be owned at this level", never "what is new". That is what
	makes a caller that runs it after every round and a caller that runs it once on a level-up produce
	the same profile — and it means a grant missed during a DataStore outage repairs itself on the next
	award rather than being lost forever.
]]
check("nothing is earned below the unlock level", #Cosmetics.grantsAtLevel(FIXTURE, 5) == 0)
check("the unlock level itself earns it", #Cosmetics.grantsAtLevel(FIXTURE, 6) == 1)
check("levels above keep earning it", #Cosmetics.grantsAtLevel(FIXTURE, 60) == 1)
check(
	"grantsAtLevel is idempotent",
	#Cosmetics.grantsAtLevel(FIXTURE, 6) == #Cosmetics.grantsAtLevel(FIXTURE, 6)
)
check(
	"a corrupt level degrades to level 1 rather than granting everything",
	#Cosmetics.grantsAtLevel(FIXTURE, 0 / 0) == 0
)
check(
	"an infinite level does not grant everything either",
	#Cosmetics.grantsAtLevel(FIXTURE, math.huge) == 0
)

--------------------------------------------------------------------------------
-- Equipping
--------------------------------------------------------------------------------

local function equip(id: string, owned: { [string]: boolean }, phase: Cosmetics.RoundPhase)
	return Cosmetics.evaluateEquip({ Catalogue = FIXTURE, Id = id, Owned = owned, Phase = phase })
end

-- An affordable, unowned, coin-priced purchase, so the ONLY thing the phase loop below can be
-- measuring is the phase.
local function buyDuring(phase: Cosmetics.RoundPhase)
	return Cosmetics.evaluatePurchase({
		Catalogue = FIXTURE,
		Id = "by_coins",
		Owned = NOTHING,
		Level = 1,
		Coins = 99999,
		Phase = phase,
	})
end

check("an unknown id is refused", equip("by_vibes", NOTHING, "IDLE").Verdict == "UNKNOWN_ITEM")
check("a default may be equipped by anybody", equip("d_skin", NOTHING, "IDLE").Verdict == "OK")
check("an unowned item is refused", equip("by_coins", NOTHING, "IDLE").Verdict == "NOT_OWNED")
check("an owned item is allowed", equip("by_coins", { by_coins = true }, "IDLE").Verdict == "OK")

check(
	"an OK equip reports the slot to write into",
	equip("by_coins", { by_coins = true }, "IDLE").Slot == "Lantern"
)
check("a refused equip reports no slot", equip("by_coins", NOTHING, "IDLE").Slot == "")

--[[
	THE PHASE GATE, IN BOTH DIRECTIONS AND OVER ALL FIVE PHASES. Both halves are needed: a gate proven
	only to refuse is one that could refuse everything, and this one governs the lobby's only
	interactive panel.

	ENDING IS ON THE REFUSED SIDE, which is stricter than the window in which `MonsterService` can
	actually hold a captured appearance. See `roundExists` — the rule is "cosmetics change between
	rounds", stated once, rather than a narrower gate that is correct only because of two facts in two
	other files.
]]
for _, phase in { "STARTING", "ACTIVE", "ENDING" } :: { Cosmetics.RoundPhase } do
	check(
		`equipping is refused during {phase}`,
		equip("d_skin", NOTHING, phase).Verdict == "WRONG_PHASE"
	)
	check(`buying is refused during {phase}`, buyDuring(phase).Verdict == "WRONG_PHASE")
end

for _, phase in { "IDLE", "INTERMISSION" } :: { Cosmetics.RoundPhase } do
	check(`equipping is allowed during {phase}`, equip("d_skin", NOTHING, phase).Verdict == "OK")
	check(`buying is allowed during {phase}`, buyDuring(phase).Verdict == "OK")
end

--[[
	THE ORDER OF THE REFUSALS IS ITSELF A PROPERTY. An unknown id must be reported as unknown whatever
	the phase, because "wrong phase" for an id that does not exist tells a probing client that the
	phase gate is the only thing between them and it.
]]
check(
	"an unknown id is unknown even mid-round",
	equip("by_vibes", NOTHING, "ACTIVE").Verdict == "UNKNOWN_ITEM"
)

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------

local function buy(
	id: string,
	owned: { [string]: boolean },
	level: number,
	coins: number,
	phase: Cosmetics.RoundPhase
)
	return Cosmetics.evaluatePurchase({
		Catalogue = FIXTURE,
		Id = id,
		Owned = owned,
		Level = level,
		Coins = coins,
		Phase = phase,
	})
end

check(
	"an unknown id cannot be bought",
	buy("by_vibes", NOTHING, 99, 99999, "IDLE").Verdict == "UNKNOWN_ITEM"
)
check(
	"a default cannot be bought",
	buy("d_skin", NOTHING, 99, 99999, "IDLE").Verdict == "ALREADY_OWNED"
)
check(
	"an owned item cannot be bought twice",
	buy("by_coins", { by_coins = true }, 99, 99999, "IDLE").Verdict == "ALREADY_OWNED"
)

--[[
	A LEVEL UNLOCK HAS NO COIN PATH, and that is the whole reason a level unlock is a reward. If coins
	could buy it, the level would be a suggestion and §7's "levels unlock cosmetics" would be untrue.
]]
check(
	"a level unlock cannot be bought with coins",
	buy("by_level", NOTHING, 1, 99999, "IDLE").Verdict == "LOCKED_BY_LEVEL"
)
check(
	"a level unlock cannot be bought even at the unlock level",
	buy("by_level", NOTHING, 6, 99999, "IDLE").Verdict == "LOCKED_BY_LEVEL"
)

--[[
	AND A GAMEPASS ITEM IS NOT FREE. C37 depends on C34 and not the reverse, so the gamepass path is
	LISTED and refused rather than wired to a product id of 0 — which is a purchase flow that succeeds
	silently for everybody.
]]
check(
	"a gamepass item is not for sale before C37 exists",
	buy("by_pass", NOTHING, 99, 99999, "IDLE").Verdict == "NOT_FOR_SALE"
)

check(
	"coins short of the price refuses",
	buy("by_coins", NOTHING, 1, 299, "IDLE").Verdict == "NOT_ENOUGH_COINS"
)
check("exactly the price is enough", buy("by_coins", NOTHING, 1, 300, "IDLE").Verdict == "OK")

--[[
	THE COST COMES OUT OF THE CATALOGUE, NOT OUT OF THE REQUEST. `RequestBuyCosmetic` carries an id
	and nothing else for exactly this reason: there is no number in the request for a compromised
	client to shrink, and the server spends what this returns.
]]
check(
	"an OK purchase names the catalogue price",
	buy("by_coins", NOTHING, 1, 300, "IDLE").Cost == 300
)
check("a refused purchase costs nothing", buy("by_coins", NOTHING, 1, 299, "IDLE").Cost == 0)

--[[
	A CORRUPT COIN BALANCE MUST NOT BUY ANYTHING. `math.huge` is the case that matters: it survives a
	NaN check, it is larger than any price, and a profile that reached it is already unable to save.
]]
for _, corrupt in { 0 / 0, math.huge } do
	check(
		`a coin balance of {corrupt} cannot buy`,
		buy("by_coins", NOTHING, 1, corrupt, "IDLE").Verdict == "NOT_ENOUGH_COINS"
	)
end

--------------------------------------------------------------------------------
-- Purity
--------------------------------------------------------------------------------

local owned: { [string]: boolean } = { by_coins = true }
local before = #FIXTURE

Cosmetics.evaluateEquip({ Catalogue = FIXTURE, Id = "by_coins", Owned = owned, Phase = "IDLE" })
Cosmetics.evaluatePurchase({
	Catalogue = FIXTURE,
	Id = "by_level",
	Owned = owned,
	Level = 9,
	Coins = 5,
	Phase = "IDLE",
})

check("evaluating does not mutate the catalogue", #FIXTURE == before)
check("evaluating does not mutate the inventory", owned.by_coins == true and owned.by_level == nil)

--------------------------------------------------------------------------------
-- The SHIPPED catalogue
--------------------------------------------------------------------------------

local SHIPPED: { Item } = Config.Cosmetics.Catalogue

local SLOTS = { "Skin", "Lantern", "DeathFX" }
local SOURCES = { "DEFAULT", "LEVEL", "COINS", "GAMEPASS" }

local unlockable = 0
local defaults = 0
local bySlot: { [string]: number } = {}
local ids: { [string]: boolean } = {}
local duplicate = ""
local badSlot = ""
local badSource = ""
local badRgb = ""

for _, item in SHIPPED do
	if ids[item.Id] then
		duplicate = item.Id
	end

	ids[item.Id] = true

	if not table.find(SLOTS, item.Slot) then
		badSlot = `{item.Id} -> {item.Slot}`
	end

	if not table.find(SOURCES, item.Source) then
		badSource = `{item.Id} -> {item.Source}`
	end

	if #item.Rgb ~= 3 then
		badRgb = `{item.Id} has {#item.Rgb} channels`
	end

	for channel = 1, 3 do
		local value = item.Rgb[channel]

		if value == nil or value < 0 or value > 255 then
			badRgb = `{item.Id} channel {channel} = {tostring(value)}`
		end
	end

	if item.Source == "DEFAULT" then
		defaults += 1
	else
		unlockable += 1
	end

	bySlot[item.Slot] = (bySlot[item.Slot] or 0) + 1
end

check("every catalogue id is unique", duplicate == "", duplicate)

--[[
	THE SLOT NAMES ARE THE PROFILE'S FIELD NAMES, spelled exactly. `CosmeticsService` branches on this
	string to decide which of `Equipped.Skin`, `Equipped.Lantern` and `Equipped.DeathFX` to write, so a
	typo here is a cosmetic that equips into nothing and reports success.
]]
check("every slot is one the profile actually has", badSlot == "", badSlot)
check("every source is one the rules understand", badSource == "", badSource)
check("every colour is a valid RGB triple", badRgb == "", badRgb)

-- §7: "~6 unlockable cosmetics at launch — enough to see progress, not enough to burn your content."
check(`§7 asks for about six unlockables; the catalogue has {unlockable}`, unlockable == 6)
check(`every slot has a default; there are {defaults} for {#SLOTS} slots`, defaults == #SLOTS)

for _, slot in SLOTS do
	check(`the {slot} slot has a default and something to earn`, (bySlot[slot] or 0) >= 2)
end

-- A fresh profile must be wearing something the equip rules would accept, or the first press of the
-- lobby's cycle button reads as broken.
for _, item in SHIPPED do
	if item.Source ~= "DEFAULT" then
		continue
	end

	check(
		`the {item.Slot} default ({item.Id}) is equippable by a fresh player`,
		Cosmetics.evaluateEquip({
			Catalogue = SHIPPED,
			Id = item.Id,
			Owned = NOTHING,
			Phase = "IDLE",
		}).Verdict == "OK"
	)
end

--[[
	AND WHAT A FRESH PROFILE ACTUALLY WEARS IS IN THE CATALOGUE, IN THE RIGHT SLOT.

	This is the one invariant that spans the two files, and neither can see it alone: `ProfileMigration`
	writes three ids into a new profile and has never heard of a catalogue; the catalogue is content
	and has never heard of a template. When they disagree the game still RENDERS correctly — the
	service falls back to the slot's default — so the only symptom is that the lobby's wardrobe offers
	a player something they are already wearing, which reads as a broken button rather than as a
	mismatch.

	It was wrong the first time this was checked. All three ids were `"default"`, written at C31 before
	the catalogue existed.
]]
local fresh = ProfileMigration.template()
local freshEquipped = {
	{ Slot = "Skin", Id = fresh.Cosmetics.Equipped.Skin },
	{ Slot = "Lantern", Id = fresh.Cosmetics.Equipped.Lantern },
	{ Slot = "DeathFX", Id = fresh.Cosmetics.Equipped.DeathFX },
}

for _, worn in freshEquipped do
	local item = Cosmetics.find(SHIPPED, worn.Id)

	check(
		`a fresh profile's {worn.Slot} ("{worn.Id}") is a real catalogue entry`,
		item ~= nil,
		"not in the catalogue"
	)

	if item ~= nil then
		check(
			`a fresh profile's {worn.Slot} ("{worn.Id}") is in the {worn.Slot} slot`,
			item.Slot == worn.Slot,
			`it is a {item.Slot}`
		)
		check(
			`a fresh profile's {worn.Slot} ("{worn.Id}") is a default it already owns`,
			Cosmetics.isOwned(item, fresh.Cosmetics.Owned),
			`Source = {item.Source}`
		)
	end
end

--[[
	EVERY UNLOCKABLE HAS EXACTLY ONE REACHABLE PATH. An item with a level AND a price is one whose
	unlock rule depends on which branch `evaluatePurchase` reaches first, which is a rule nobody can
	read off the table.
]]
local mixedPath = ""
local levelUnlocks = 0
local coinUnlocks = 0
local passUnlocks = 0

for _, item in SHIPPED do
	if item.Source == "LEVEL" then
		levelUnlocks += 1

		if item.Level < 1 or item.Price ~= 0 then
			mixedPath = `{item.Id}: level {item.Level}, price {item.Price}`
		end
	elseif item.Source == "COINS" then
		coinUnlocks += 1

		if item.Price < 1 or item.Level ~= 0 then
			mixedPath = `{item.Id}: level {item.Level}, price {item.Price}`
		end
	elseif item.Source == "GAMEPASS" then
		passUnlocks += 1
	end
end

check("no unlockable has two paths to it", mixedPath == "", mixedPath)
check(
	"§7's mix is present: some by level, some by coins, some by gamepass",
	levelUnlocks >= 1 and coinUnlocks >= 1 and passUnlocks >= 1,
	`{levelUnlocks} level, {coinUnlocks} coins, {passUnlocks} gamepass`
)

--[[
	AND THE PRICES ARE REACHABLE. A coin cosmetic that costs more than a plausible week of play is a
	shop window rather than a reward, which is the "burn your content" failure §7 opens with pointed
	the other way. Measured against the FLOOR coin rate — a round pays `CoinsPerRound` unconditionally.
]]
local weekOfCoins = Config.Economy.CoinsPerRound * 30

for _, item in SHIPPED do
	if item.Source ~= "COINS" then
		continue
	end

	check(
		`{item.Id} is affordable inside about thirty rounds`,
		item.Price <= weekOfCoins,
		`{item.Price} coins vs {weekOfCoins}`
	)
end

--[[
	THE LEVEL GATES MUST SIT INSIDE THE CURVE. A cosmetic gated above `Economy.MaxLevel` is one nobody
	can ever earn, and nothing in the game would say so.
]]
for _, item in SHIPPED do
	if item.Source ~= "LEVEL" then
		continue
	end

	check(
		`{item.Id}'s unlock level is inside the curve`,
		item.Level <= Config.Economy.MaxLevel,
		`level {item.Level} vs cap {Config.Economy.MaxLevel}`
	)
end

check("a level-1 player has earned nothing yet", #Cosmetics.grantsAtLevel(SHIPPED, 1) == 0)
check(
	"the level cap has earned every level unlock",
	#Cosmetics.grantsAtLevel(SHIPPED, Config.Economy.MaxLevel) == levelUnlocks
)

if failures > 0 then
	error(`{failures} cosmetics failure(s)`, 0)
end

print(`  PASS  cosmetics: {checked} assertions over {#SHIPPED} catalogue entries`)
