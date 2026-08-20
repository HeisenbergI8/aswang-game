--!strict
--[[
	Cosmetics — who may wear what, and what it costs. (C34, §7, §8.2)

		find(catalogue, id)              -> Item?
		grantsAtLevel(catalogue, level)  -> { string }        -- ids a level has earned
		evaluateEquip(input)             -> EquipResult
		evaluatePurchase(input)          -> PurchaseResult

	§7 asks for "~6 unlockable cosmetics at launch — enough to see progress, not enough to burn your
	content", and §8.2 says which six: "sell what appears in clips — death effects, transform auras,
	lantern colours". The profile has carried three slots since C31 (`Skin`, `Lantern`, `DeathFX`), so
	the six are two per slot and no schema version moves.

	THE CATALOGUE IS NOT IN HERE. It is `Config.Cosmetics.Catalogue`, because a price and a level gate
	are exactly the kind of number M12 tunes and `Config` is the one file that gets tuned. This module
	is the RULES over that data — the same split `SkyCycle` uses for the sky, and for the same reason:
	the numbers move without the logic being touched, and the logic is proven without the numbers
	being real.

	NO `script.Parent` REQUIRES (tests/README.md). Every verdict is a SCALAR union in a returned
	record; nothing here returns a list of literal unions — see
	`.claude/lessons/pure-module-unions-widen-in-lists.md`. `Item.Slot` and `Item.Source` are plain
	`string` for that reason, and callers branch on them with `if` rather than casting.

	── WHY THE PHASE GATE IS A RULE RATHER THAN A UI CHOICE ──────────────────────

	Both verdicts refuse while a round exists at all — STARTING, ACTIVE or ENDING — and it is not
	politeness about interrupting play. `MonsterService` CAPTURES every part's `Color` and `Material` at transform and
	restores exactly those values on revert — that capture is C04's bug fixed, and the fix depends on
	the captured appearance still being the appearance the player should have. A skin equipped between
	the capture and the revert is silently undone by the revert, and a skin equipped between the
	revert and the next transform is silently captured as if it had always been there. Neither errors.

	Refusing the request outright is one branch and removes the whole class. Cosmetics are a lobby
	activity in §9.3 anyway, which is where the preview stand lives — see `roundExists` for why the
	gate names three phases rather than the two in which the capture can actually be outstanding.

	── SECRECY ───────────────────────────────────────────────────────────────────

	NOTHING SECRET PASSES THROUGH, and the catalogue being client-readable is fine by CLAUDE.md's own
	rule that logic is not secret: `Config` already replicates, a cosmetic id publishes nothing, and
	the inputs are one player's own level, coins and inventory.

	What DOES need saying is the render, which this module does not do: a cosmetic is applied to a
	character and therefore replicates to every client, so a cosmetic that varied by ROLE would be an
	instant reveal readable map-wide. Nothing in this catalogue's shape permits that — an item is
	chosen by its owner and its appearance depends on nothing else — and `CosmeticsService` is where
	that stays true.
]]

--[[
	One catalogue entry. `Slot` is one of the three PROFILE FIELD NAMES — "Skin", "Lantern",
	"DeathFX" — spelled exactly, because that is what the caller assigns into.

	`Source` is "DEFAULT", "LEVEL", "COINS" or "GAMEPASS". Both are plain `string` rather than literal
	unions, deliberately: this type travels inside `{ Item }`, and a literal union does not survive
	`require` inside a list.
]]
export type Item = {
	Id: string,
	Slot: string,
	Name: string,
	Source: string,
	Level: number, -- the level that unlocks it; 0 unless Source == "LEVEL"
	Price: number, -- coins; 0 unless Source == "COINS"
	-- The single visual parameter, an RGB triple exactly as `Config.Monster` stores colours. Never a
	-- Color3: Lune has no Roblox datatypes and the caller constructs it.
	Rgb: { number },
}

export type EquipVerdict = "OK" | "UNKNOWN_ITEM" | "NOT_OWNED" | "WRONG_PHASE"

export type PurchaseVerdict =
	"OK"
	| "UNKNOWN_ITEM"
	| "ALREADY_OWNED"
	| "NOT_FOR_SALE"
	| "LOCKED_BY_LEVEL"
	| "NOT_ENOUGH_COINS"
	| "WRONG_PHASE"

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"

export type EquipInput = {
	Catalogue: { Item },
	Id: string,
	Owned: { [string]: boolean },
	Phase: RoundPhase,
}

export type EquipResult = {
	Verdict: EquipVerdict,
	Slot: string, -- "" unless the verdict is OK
}

export type PurchaseInput = {
	Catalogue: { Item },
	Id: string,
	Owned: { [string]: boolean },
	Level: number,
	Coins: number,
	Phase: RoundPhase,
}

export type PurchaseResult = {
	Verdict: PurchaseVerdict,
	Cost: number, -- 0 unless the verdict is OK
}

local Cosmetics = {}

--[[
	A ROUND EXISTS. Both verdicts refuse here — see the header for why this is a rule and not a
	courtesy.

	ENDING IS INCLUDED, AND THAT IS THE POINT OF WRITING IT AS THREE PHASES RATHER THAN TWO. The
	capture window `MonsterService` holds is opened at a transform and closed at a revert, and reverts
	happen on the way OUT of ACTIVE — so a transformed Aswang is still transformed for the instant
	ENDING begins. Two other things already make that unreachable today: the lobby panel is built at
	IDLE only, and `MonsterService`'s phase handler reverts every monster on any non-ACTIVE phase. Both
	are true and neither is this module's to rely on.

	What is left is a rule that states itself: cosmetics change BETWEEN rounds. That is one sentence a
	reader can hold, instead of a two-phase gate that is correct because of two facts in two other
	files.
]]
local function roundExists(phase: RoundPhase): boolean
	return phase == "STARTING" or phase == "ACTIVE" or phase == "ENDING"
end

local function finite(value: number, fallback: number): number
	if type(value) ~= "number" or not (value >= 0 and value < math.huge) then
		return fallback
	end

	return math.floor(value)
end

function Cosmetics.find(catalogue: { Item }, id: string): Item?
	for _, item in catalogue do
		if item.Id == id then
			return item
		end
	end

	return nil
end

--[[
	EVERY DEFAULT IS OWNED BY EVERYBODY, and it is checked here rather than written into the profile.

	`ProfileMigration.template` ships `Owned = {}` and `Equipped = { Skin = "default", … }` — so a
	fresh player is already WEARING three items they do not own. Materialising the defaults into
	`Owned` at load would fix that and cost a v2 migration for a fact that is true by definition; a
	predicate costs nothing and cannot drift out of date.
]]
function Cosmetics.isOwned(item: Item, owned: { [string]: boolean }): boolean
	if item.Source == "DEFAULT" then
		return true
	end

	return owned[item.Id] == true
end

--[[
	THE IDS A LEVEL HAS EARNED, whether or not they are already granted.

	Returned as `{ string }` — plain strings, no literal union — so the caller can loop it and grant
	what is missing. Idempotent by construction: it answers "what should be owned at this level",
	never "what is new", which means a caller that runs it every round and a caller that runs it once
	after a level-up produce the same profile.
]]
function Cosmetics.grantsAtLevel(catalogue: { Item }, level: number): { string }
	local earned: { string } = {}
	local at = finite(level, 1)

	for _, item in catalogue do
		if item.Source == "LEVEL" and finite(item.Level, 0) <= at then
			table.insert(earned, item.Id)
		end
	end

	return earned
end

--[[
	MAY THIS PLAYER WEAR THIS.

	Ownership is re-checked here even though the client only offers owned items, because a client's
	offer is a hint and never a permission — the same inversion the trial door uses (§6.2: the client
	requests, the server decides). A compromised client firing `RequestEquipCosmetic("deathfx_apoy")`
	is the expected traffic, not the surprise.
]]
function Cosmetics.evaluateEquip(input: EquipInput): EquipResult
	local item = Cosmetics.find(input.Catalogue, input.Id)

	if item == nil then
		local verdict: EquipVerdict = "UNKNOWN_ITEM"

		return { Verdict = verdict, Slot = "" }
	end

	if roundExists(input.Phase) then
		local verdict: EquipVerdict = "WRONG_PHASE"

		return { Verdict = verdict, Slot = "" }
	end

	if not Cosmetics.isOwned(item, input.Owned) then
		local verdict: EquipVerdict = "NOT_OWNED"

		return { Verdict = verdict, Slot = "" }
	end

	local verdict: EquipVerdict = "OK"

	return { Verdict = verdict, Slot = item.Slot }
end

--[[
	MAY THIS PLAYER BUY THIS, AND FOR HOW MUCH.

	`Cost` is the authority on the price and the server spends exactly it — the client never names an
	amount, so there is no number in the request for a compromised client to shrink.

	THE FOUR SOURCES ANSWER DIFFERENTLY, and one of them is a placeholder on purpose:

	  DEFAULT  never for sale; it is already owned.
	  LEVEL    never for sale either — it is GRANTED by `grantsAtLevel` when the level arrives. A
	           coin path to a level unlock would make the level meaningless, which is the reward §7 is
	           actually building.
	  COINS    the only path that spends anything.
	  GAMEPASS refused with `NOT_FOR_SALE` until C37 exists. C37 depends on C34, not the reverse, so a
	           gamepass item is LISTED and locked here rather than being invented early — the
	           alternative is a cosmetic wired to a gamepass id of 0, which is a purchase flow that
	           silently succeeds for everybody.
]]
function Cosmetics.evaluatePurchase(input: PurchaseInput): PurchaseResult
	local item = Cosmetics.find(input.Catalogue, input.Id)

	if item == nil then
		local verdict: PurchaseVerdict = "UNKNOWN_ITEM"

		return { Verdict = verdict, Cost = 0 }
	end

	if roundExists(input.Phase) then
		local verdict: PurchaseVerdict = "WRONG_PHASE"

		return { Verdict = verdict, Cost = 0 }
	end

	if Cosmetics.isOwned(item, input.Owned) then
		local verdict: PurchaseVerdict = "ALREADY_OWNED"

		return { Verdict = verdict, Cost = 0 }
	end

	if item.Source == "LEVEL" then
		--[[
			Reported as LOCKED_BY_LEVEL rather than NOT_FOR_SALE, because the two mean different
			things to the player: one is "keep playing" and the other is "this is not a thing you can
			get". Unreachable at or above the level, since `grantsAtLevel` will already have granted
			it and `isOwned` above would have returned — unless a grant was missed, in which case
			this is the honest answer and the next award repairs it.
		]]
		local verdict: PurchaseVerdict = "LOCKED_BY_LEVEL"

		return { Verdict = verdict, Cost = 0 }
	end

	if item.Source ~= "COINS" then
		local verdict: PurchaseVerdict = "NOT_FOR_SALE"

		return { Verdict = verdict, Cost = 0 }
	end

	local price = finite(item.Price, 0)

	if finite(input.Coins, 0) < price then
		local verdict: PurchaseVerdict = "NOT_ENOUGH_COINS"

		return { Verdict = verdict, Cost = 0 }
	end

	local verdict: PurchaseVerdict = "OK"

	return { Verdict = verdict, Cost = price }
end

return Cosmetics
