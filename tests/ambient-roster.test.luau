--!strict
--[[
	The barrio's head count does not move when the monster hides. (V07, §4.3/§5)

	ONE PROPERTY, ASSERTED OVER THE WHOLE ROSTER SPACE. `visibleCount(claim(r, form), form) ==
	visibleCount(r, form)`, for every form, at every occupancy from empty to fully claimed. §4.3: "it
	must never SPAWN a new one: two pigs where there was one is a head count with extra steps."

	THE EXHAUSTION CASE IS THE ONE THAT MATTERS MOST and it is the last row of every loop: claim every
	slot of a form, then claim once more. The correct answer is nil, and the tempting wrong answer —
	appending a slot so the hide always works — passes every test about camouflage functioning.
]]

local Config = require("../src/shared/Config")
local AmbientRoster = require("../src/shared/pure/AmbientRoster")

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

local FORMS = { "CAT", "DOG", "PIG", "VILLAGER" }
-- SYNTHETIC, not Config's — V16 retunes `Ambient.PerForm` and must not be able to red this file. The
-- live value is cross-checked at the bottom, as `feed-rules` and `monster-health` both do.
local PER_FORM = 3

local function build(): AmbientRoster.Roster
	local roster: AmbientRoster.Roster = {}

	for _, form in FORMS do
		for _ = 1, PER_FORM do
			table.insert(roster, { Form = form :: any, Claimed = false })
		end
	end

	return roster
end

for _, form in FORMS do
	local roster = build()
	local before = AmbientRoster.visibleCount(roster, form :: any)

	-- Claim every slot of this form in turn. The count must never move, and every claim must succeed
	-- until the form is exhausted.
	for attempt = 1, PER_FORM do
		local claimed, slotIndex = AmbientRoster.claim(roster, form :: any)

		check(`claim {attempt} of {form} succeeds`, slotIndex ~= nil, tostring(slotIndex))
		check(
			`head count invariant after claim {attempt} of {form}`,
			AmbientRoster.visibleCount(claimed, form :: any) == before,
			`{AmbientRoster.visibleCount(claimed, form :: any)} vs {before}`
		)

		-- AND NO OTHER FORM MOVED. A claim that reached across forms would let one hide depopulate
		-- the pigs while the monster became a cat, which is the same leak by a longer route.
		for _, other in FORMS do
			if other ~= form then
				check(
					`claiming {form} does not touch {other}`,
					AmbientRoster.visibleCount(claimed, other :: any) == PER_FORM
				)
			end
		end

		roster = claimed
	end

	-- EXHAUSTED. The refusal is the rule.
	local exhausted, none = AmbientRoster.claim(roster, form :: any)

	check(`claim past exhaustion refuses`, none == nil, tostring(none))
	check(
		`refused claim spawns nothing`,
		AmbientRoster.visibleCount(exhausted, form :: any) == before
	)

	-- AND THE INPUT WAS NOT MUTATED. Asserted explicitly because an in-place edit is invisible until
	-- two callers share a roster, which is what a rejoin looks like.
	check(`claim does not mutate its argument`, roster ~= exhausted)
end

--[[
	RELEASE IS IDEMPOTENT AND TOTAL. Phase 4 releases from five exits, at least two of which can fire
	for the same slot in the same frame.
]]
local roster = build()
local claimed, slotIndex = AmbientRoster.claim(roster, "CAT")
local released = AmbientRoster.release(claimed, slotIndex)

local _, reclaimed = AmbientRoster.claim(released, "CAT")

check("release frees the slot", reclaimed == slotIndex, tostring(reclaimed))
check("double release is a no-op", #AmbientRoster.release(released, slotIndex) == #released)
check("release of nil is a no-op", #AmbientRoster.release(released, nil) == #released)
check("release of a stale index is a no-op", #AmbientRoster.release(released, 9999) == #released)

--[[
	AND RELEASE RESTORES THE HEAD COUNT RATHER THAN GROWING IT. The mirror of the claim invariant:
	putting an entity back must not append a second one.
]]
check(
	"release does not grow the roster",
	AmbientRoster.visibleCount(released, "CAT") == AmbientRoster.visibleCount(roster, "CAT")
)

--[[
	THE INVARIANT THIS SUITE ORIGINALLY MISSED, AND THE ONLY ONE AN ATTACKER CAN READ.

	Everything above asserts `visibleCount` — the ROSTER count, a number that lives in a Lua table on
	the server. The number a client reads is `#workspace.AmbientLife:GetChildren()`, and the first
	implementation of `AmbientService` moved a claimed entity into `ServerStorage`, so THAT number
	dropped from 16 to 15 on every client the instant the Aswang hid. Measured in a live Studio
	session:

	    CLIENT count=15 | Ambient_CAT_1 present=false | events captured=1
	      REMOVED Ambient_CAT_1 at 46.014, 3, 20.102 (count now 15)

	78 assertions passed over the roster while the leak was wide open. Thorough coverage of the wrong
	quantity is worse than no coverage, because it reads as proof.

	LUNE CANNOT SEE `workspace`, so this file cannot assert the client-visible count directly. What it
	CAN assert is the property that makes the two counts equal: THE ROSTER'S LENGTH NEVER CHANGES.
	`AmbientService` spawns one Model per slot at Start and never spawns or destroys another, so as
	long as `claim` and `release` only ever flip a boolean, the tree and the roster cannot diverge.
	A `claim` that appended, or a `release` that removed, would break this and is the only shape of
	pure-module bug that could reintroduce the Critical from this end.

	The other half — that `AmbientService` performs no reparent — is structural rather than testable:
	there is no holding folder in that file any more, so there is nowhere to reparent TO.
]]
local lengthProbe = build()
local lengthBefore = #lengthProbe

for attempt = 1, PER_FORM * 4 do
	local claimed, slotIndex = AmbientRoster.claim(lengthProbe, "PIG")

	check(`roster length unchanged by claim {attempt}`, #claimed == lengthBefore, `{#claimed}`)

	lengthProbe = AmbientRoster.release(claimed, slotIndex)

	check(
		`roster length unchanged by release {attempt}`,
		#lengthProbe == lengthBefore,
		`{#lengthProbe}`
	)
end

-- And across the degenerate release cases, which is where an off-by-one would hide.
check("length unchanged by nil release", #AmbientRoster.release(lengthProbe, nil) == lengthBefore)
check(
	"length unchanged by stale release",
	#AmbientRoster.release(lengthProbe, 9999) == lengthBefore
)

--[[
	THE PREFERRED-INDEX HINT (V07 fix for the campable-disguise finding).

	`AmbientService` picks a random free slot with server-only entropy and passes it here. The hint
	must be HONOURED when valid and IGNORED when not — a version that trusted it blindly would let a
	caller claim a slot of the wrong form, or re-claim one already taken.
]]
local hintRoster = build()

-- Honoured: index 3 is a CAT (slots 1-3 are CAT at PER_FORM = 3) and free.
local hinted, hintedIndex = AmbientRoster.claim(hintRoster, "CAT", 3)
check("preferred index is honoured when valid", hintedIndex == 3, tostring(hintedIndex))

-- Ignored: index 3 is now claimed, so the scan must fall through to another free CAT.
local again, againIndex = AmbientRoster.claim(hinted, "CAT", 3)
check(
	"preferred index ignored when already claimed",
	againIndex ~= nil and againIndex ~= 3,
	tostring(againIndex)
)

-- Ignored: index 5 is a DOG, so a CAT claim must not take it.
local wrongForm, wrongIndex = AmbientRoster.claim(hintRoster, "CAT", 5)
check("preferred index ignored when the form differs", wrongIndex ~= 5, tostring(wrongIndex))
check(
	"a wrong-form hint still yields a slot of the REQUESTED form",
	wrongIndex ~= nil and hintRoster[wrongIndex].Form == "CAT"
)

-- Ignored: out of range.
local stale, staleIndex = AmbientRoster.claim(hintRoster, "CAT", 9999)
check(
	"out-of-range hint falls through",
	staleIndex ~= nil and staleIndex ~= 9999,
	tostring(staleIndex)
)
check("hint does not grow the roster", #stale == #hintRoster)

--[[
	`freeSlots` — the list the caller draws from. It must report only free slots OF THAT FORM, or the
	random pick would hand `claim` a hint it always rejects and the randomisation would silently
	degrade back to first-free.
]]
local freeRoster = build()
local freeCats = AmbientRoster.freeSlots(freeRoster, "CAT")

check("freeSlots reports every free slot of the form", #freeCats == PER_FORM, `{#freeCats}`)

for _, index in freeCats do
	check(`freeSlots index {index} is a CAT`, freeRoster[index].Form == "CAT")
	check(`freeSlots index {index} is unclaimed`, not freeRoster[index].Claimed)
end

local afterOne = (AmbientRoster.claim(freeRoster, "CAT"))
check(
	"freeSlots shrinks by one after a claim",
	#AmbientRoster.freeSlots(afterOne, "CAT") == PER_FORM - 1
)

--[[
	CONFIG CROSS-CHECK. The grid runs on PER_FORM = 3; this is where the live number is asserted to be
	usable at all, so a Config edit to 1 or 0 reds here as well as in `config.test.luau`.
]]
check("Ambient.PerForm >= 2", Config.Ambient.PerForm >= 2)

print(`  {checked - failures}/{checked} checks passed`)

if failures > 0 then
	error(`{failures} ambient-roster assertions failed`, 0)
end
