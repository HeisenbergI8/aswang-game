--!strict
--[[
	CosmeticsService — the six cosmetics, on the avatar. (C34, §7, §8.2)

	WHAT IT OWNS. Two remote handlers (`RequestEquipCosmetic`, `RequestBuyCosmetic`) and the rendering
	of whatever is equipped: a body tint, a lantern light, and a burst at the corpse. It decides
	nothing — `shared/pure/Cosmetics` decides, `ProgressionService` writes, `Config.Cosmetics` holds
	the catalogue — and it owns none of the numbers.

	WHY IT IS NOT PART OF `ProgressionService`, same answer as `DailyService`: that file has no
	`OnServerEvent` handler in it and its header makes that a promise. The request lands here and is
	rate-limited here; the profile is written there, through the guarded setters.

	── THE RENDER IS THE PART THAT CAN LEAK, AND THE PART THAT CAN BREAK ─────────

	Everything this file draws is on a CHARACTER, which replicates to every client. The `ui-polish`
	skill's table is blunt about it: a Highlight, a ParticleEmitter or a light on a character is seen
	by everyone, so it may never be role-conditional. Nothing here reads a role, and the shape makes
	that hard to reintroduce: an item's appearance depends on the item, the item is chosen by its
	owner, and neither `RoundService.GetAswangUserId` nor `MonsterService.IsTransformed` is required
	by this file.

	THE BREAKAGE IS C04's REVERT BUG, and it is the reason the skin tint captures.
	`MonsterService.transform` reads every part's `Color` and `Material`, and its revert writes exactly
	those values back — the fix for the original bug, where the revert restored hardcoded defaults and
	permanently branded the ex-Aswang. A tint applied on top of a capture is undone by the revert; a
	tint applied before one is captured as though it had always been there.

	Two things keep that from happening, and both are needed:

	  · `pure/Cosmetics` refuses every equip and purchase during STARTING and ACTIVE, which is the only
	    window in which a capture can be outstanding.
	  · This file captures the character's OWN colours before its first tint and restores from that
	    capture when the player goes back to a default — the same discipline, for the same reason.

	A DEFAULT SKIN PAINTS NOTHING. §7's cosmetics are meant to be a visible change, and repainting
	every player's own avatar to a neutral tan on join would be a change nobody asked for — so the
	default is "whatever Roblox gave you" and only an owned, chosen skin repaints.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.pure.Cosmetics)
local Remotes = require(Shared.Remotes)
local AntiCheatService = require(script.Parent.AntiCheatService)
local MonsterService = require(script.Parent.MonsterService)
local ProgressionService = require(script.Parent.ProgressionService)
local RoundService = require(script.Parent.RoundService)

local CosmeticsService = {}

local CATALOGUE: { Cosmetics.Item } = Config.Cosmetics.Catalogue

local LANTERN_NAME = "CosmeticLantern"
local BURST_NAME = "CosmeticDeathFX"

--[[
	WHAT A CHARACTER LOOKED LIKE BEFORE THIS FILE TOUCHED IT.

	Keyed by UserId and holding the CURRENT character's parts, so a respawn drops the old capture with
	the old body. Captured lazily — the first time a non-default skin is applied — because a player who
	never equips one must never have their own avatar restored over, and a capture taken at spawn is a
	capture that could be written back by mistake.
]]
type PartLook = {
	Part: BasePart,
	Color: Color3,
	Material: Enum.Material,
}

local baseline: { [number]: { PartLook } } = {}

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3]) -- config-ok: RGB channel indices, not knobs
end

local function itemOrDefault(id: string, slot: string): Cosmetics.Item?
	local item = Cosmetics.find(CATALOGUE, id)

	if item ~= nil and item.Slot == slot then
		return item
	end

	--[[
		FALL BACK TO THE SLOT'S DEFAULT RATHER THAN TO NOTHING. A stored id can be absent from the
		catalogue for two ordinary reasons — an item retired between builds, or a profile written by a
		newer server — and in both cases the player should look like a player rather than like an
		error. `ProfileMigration.str` already floors a malformed field to "default"; this covers the
		id that is well-formed and simply unknown.
	]]
	for _, candidate in CATALOGUE do
		if candidate.Slot == slot and candidate.Source == "DEFAULT" then
			return candidate
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- The render
--------------------------------------------------------------------------------

local function restoreSkin(userId: number)
	local captured = baseline[userId]

	if captured == nil then
		return
	end

	for _, look in captured do
		-- The character may have been destroyed under us by a respawn or a corpse. Writing to a
		-- destroyed part is harmless; reading its Parent first keeps the loop honest about what it did.
		if look.Part.Parent ~= nil then
			look.Part.Color = look.Color
			look.Part.Material = look.Material
		end
	end

	baseline[userId] = nil
end

--[[
	THE SKIN. Captures once, then repaints; going back to a default restores the capture.

	The Head is included deliberately. A tint that stops at the neck reads as a costume rather than as
	a character, and §5's whole art strategy is that darkness and fog do the work — a body that is one
	colour is exactly as legible in a foggy barrio as a body that is six.
]]
local function applySkin(player: Player, character: Model, item: Cosmetics.Item)
	local userId = player.UserId

	if item.Source == "DEFAULT" then
		restoreSkin(userId)

		return
	end

	if baseline[userId] == nil then
		local captured: { PartLook } = {}

		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(
					captured,
					{ Part = part, Color = part.Color, Material = part.Material }
				)
			end
		end

		baseline[userId] = captured
	end

	local colour = rgb(item.Rgb)

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = colour
		end
	end
end

--[[
	THE LANTERN. One PointLight on the root part, and the COLOUR is the only thing an item changes.

	Range and brightness come from `Config.Cosmetics` and are shared by every lantern, because a
	lantern that lit further would be a gameplay advantage sold for coins — §8.1's no-pay-to-win line,
	and the one place a purely cosmetic system could stop being cosmetic.

	Reused rather than recreated, so equipping four lanterns in a row leaves one light rather than
	four. Parented to the root rather than the Head because the Head is where `MonsterService` puts
	the eye glow, and two files adding lights to one part is how a revert deletes the wrong one.
]]
local function applyLantern(character: Model, item: Cosmetics.Item)
	local root = character:FindFirstChild("HumanoidRootPart")

	if root == nil or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild(LANTERN_NAME)
	local light: PointLight

	if existing ~= nil and existing:IsA("PointLight") then
		light = existing
	else
		--[[
			Anything under this name that is NOT a PointLight is replaced rather than worked around.
			Nothing else in the repo writes that name, so the case is a corrupt character or a future
			collision — and silently returning would leave a player permanently without a lantern for
			a reason no log would name.
		]]
		if existing ~= nil then
			existing:Destroy()
		end

		light = Instance.new("PointLight")
		light.Name = LANTERN_NAME
		light.Shadows = true
		light.Parent = root
	end

	light.Color = rgb(item.Rgb)
	light.Range = Config.Cosmetics.LanternRange
	light.Brightness = Config.Cosmetics.LanternBrightness
end

--[[
	EVERYTHING THIS FILE DRAWS ON A LIVING CHARACTER, from one profile read.

	Called on spawn and on a successful equip, and it is idempotent — every branch either writes the
	same value again or restores a capture that is already restored. That matters because both callers
	can fire in the same frame for a player who equips while dead.
]]
local function applyLook(player: Player)
	local character = player.Character

	if character == nil then
		return
	end

	local data = ProgressionService.GetProfile(player)

	if data == nil then
		return
	end

	local skin = itemOrDefault(data.Cosmetics.Equipped.Skin, "Skin")
	local lantern = itemOrDefault(data.Cosmetics.Equipped.Lantern, "Lantern")

	if skin ~= nil then
		applySkin(player, character, skin)
	end

	if lantern ~= nil then
		applyLantern(character, lantern)
	end
end

--[[
	THE DEATH EFFECT, PLAYED AT THE BODY (§8.2: "sell what appears in clips").

	IT IS DRIVEN OFF THE CORPSE FOLDER RATHER THAN OFF A DEATH EVENT, and that is a secrecy decision as
	much as a plumbing one. Since Amendment A3, `PlayerKilled` is fired to the VICTIM alone — which of
	the eight are dead is an oracle the round does not publish — so there is no death broadcast to hang
	this on and there must not be one. A corpse, by contrast, is already a body standing in the open:
	an effect on it is seen by exactly the people who can already see it, and says nothing they did not
	just watch happen.

	§4.9 BOUNDS WHAT IT MAY BE. "Creepy and tense, not graphic": a puff, a fade, no blood and no
	dismemberment. That is a rating constraint disguised as a design note, and it cuts off the entire
	audience that plays and spends the most if it is got wrong.

	A husk — the body of someone who disconnected mid-round — has no `Player`, so it gets the slot's
	default. Their profile left with them; guessing would be worse than a neutral puff.
]]
local function playDeathEffect(corpse: Instance)
	local userId = tonumber(corpse.Name:match("^Corpse_(%d+)$"))

	if userId == nil or not corpse:IsA("Model") then
		return
	end

	--[[
		The root part if there is one, and any part if there is not. `makeCorpse` anchors every part
		and reparents the whole model, so either is a real world position — but an R6 husk built by
		`RoundService` is not guaranteed to carry a root under that name, and an emitter parented to
		nothing draws nothing and reports nothing.
	]]
	local named = corpse:FindFirstChild("HumanoidRootPart")
	local anchor: BasePart? = if named ~= nil and named:IsA("BasePart")
		then named
		else corpse:FindFirstChildWhichIsA("BasePart")

	if anchor == nil then
		return
	end

	--[[
		THE EMPTY STRING RATHER THAN A DEFAULT ID, because `itemOrDefault` resolves an unmatched id to
		the slot's default and an id-shaped sentinel would be one more thing that has to agree with the
		catalogue. This says "we have no id" and lets one function own what that means.
	]]
	local equippedId = ""
	local player = Players:GetPlayerByUserId(userId)

	if player ~= nil then
		local data = ProgressionService.GetProfile(player)

		if data ~= nil then
			equippedId = data.Cosmetics.Equipped.DeathFX
		end
	end

	local item = itemOrDefault(equippedId, "DeathFX")

	if item == nil then
		return
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = BURST_NAME
	emitter.Color = ColorSequence.new(rgb(item.Rgb))
	emitter.Lifetime = NumberRange.new(Config.Cosmetics.DeathFXLifetime)
	emitter.Speed = NumberRange.new(Config.Cosmetics.DeathFXSpeed)
	emitter.SpreadAngle = Vector2.new(180, 180) -- config-ok: a full hemisphere, not a knob
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = anchor

	emitter:Emit(Config.Cosmetics.DeathFXParticles)

	--[[
		DESTROYED AFTER THE PARTICLES HAVE LIVED OUT, not on the corpse's own timer. `Config.Monster`'s
		corpse duration is 45s and this is under two, so leaving it parented would keep an idle emitter
		on every body for the rest of the round. Destroying the emitter does not cut the particles
		short only because `Emit` has already released them.
	]]
	task.delay(Config.Cosmetics.DeathFXLifetime, function()
		emitter:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- The two requests
--------------------------------------------------------------------------------

--[[
	EQUIP. One argument, an id, and the type check comes BEFORE the profile read but AFTER the limiter.

	The ordering is C18's lesson made general: `MonsterService`'s kill handler consumed a rate-limit
	token before its type guard, so a malformed request from a broken client spent a real player's
	budget. Here the limiter is first because it is the cheapest thing in the function and the whole
	point of a limiter is that a firehose costs nothing — and the type check is second so a malformed
	id never reaches a table lookup.

	THE SLOT IS NOT AN ARGUMENT. `evaluateEquip` reads it off the catalogue entry, so a client cannot
	name an item in one slot and a slot in another and see which the server believes.
]]
local function onEquip(player: Player, id: unknown)
	if typeof(id) ~= "string" then
		return
	end

	local data = ProgressionService.GetProfile(player)

	if data == nil then
		return
	end

	local verdict = Cosmetics.evaluateEquip({
		Catalogue = CATALOGUE,
		Id = id,
		Owned = data.Cosmetics.Owned,
		Phase = RoundService.GetPhase(),
	})

	if verdict.Verdict ~= "OK" then
		--[[
			A REFUSAL PUSHES, so the lobby's cycler snaps back to what is actually equipped rather than
			sitting on a selection the server rejected. `check:ratelimit`'s LogOnly stance applies to
			the limiter; a rejected equip is ordinary traffic (a stale client, a round that started
			between the tap and the packet) and is not warned about.
		]]
		ProgressionService.PushProfile(player, nil)

		return
	end

	if not ProgressionService.SetEquipped(player, verdict.Slot, id) then
		return
	end

	applyLook(player)
	ProgressionService.PushProfile(player, nil)
end

--[[
	BUY. Also one argument, and the price is not in it.

	SPEND FIRST, GRANT SECOND, AND THE ORDER IS THE CORRECTNESS ARGUMENT — the same shape as
	`DailyService`'s stamp-then-pay. `SpendCoins` returns false when the player cannot afford it, so a
	failed spend cannot leave a granted cosmetic behind. The reverse order would grant the item and
	then discover the coins were gone, and there is no rollback that survives a server dying between
	the two.

	The purchase does NOT equip. A player buying a second lantern while wearing the first should not
	have their look changed by a shop press; equipping is its own remote and its own decision.
]]
local function onBuy(player: Player, id: unknown)
	if typeof(id) ~= "string" then
		return
	end

	local data = ProgressionService.GetProfile(player)

	if data == nil then
		return
	end

	local verdict = Cosmetics.evaluatePurchase({
		Catalogue = CATALOGUE,
		Id = id,
		Owned = data.Cosmetics.Owned,
		Level = data.Level,
		Coins = data.Coins,
		Phase = RoundService.GetPhase(),
	})

	if verdict.Verdict ~= "OK" then
		ProgressionService.PushProfile(player, nil)

		return
	end

	if not ProgressionService.SpendCoins(player, verdict.Cost, `buy {id}`) then
		return
	end

	--[[
		THE COINS ARE ALREADY GONE IF THIS FAILS, and it is warned rather than swallowed. `SpendCoins`
		and `GrantCosmetic` pass identical guards — the same session, the same read-only latch, in the
		same frame — so the gap between them is not reachable by any path in this repo. If it ever is,
		the player has paid for nothing and the log is the only thing that will say so.
	]]
	if not ProgressionService.GrantCosmetic(player, id) then
		warn(`[Cosmetics] {player.Name} paid {verdict.Cost} for {id} and the grant failed`)
	end

	ProgressionService.PushProfile(player, nil)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onCharacterAdded(player: Player)
	--[[
		THE OLD CAPTURE BELONGS TO A BODY THAT NO LONGER EXISTS, so it is dropped rather than restored.
		Restoring it would write colours into destroyed parts, and keeping it would let a later
		`restoreSkin` paint this fresh body with the last one's values — which is C04's revert bug in
		miniature: state captured from one thing, applied to another.
	]]
	baseline[player.UserId] = nil

	--[[
		A DEFERRED PASS, because a character fires `CharacterAdded` before its parts have all
		replicated in — `GetDescendants` on the first frame can miss accessories and, on R15, limbs.
		One frame is enough and costs nothing that a player can perceive.
	]]
	task.defer(applyLook, player)
end

function CosmeticsService.Init()
	table.clear(baseline)
end

function CosmeticsService.Start()
	--[[
		THE LIMITER IS AT THE CONNECT SITE, above the type check and above everything else.

		`check:ratelimit` reads a character window AFTER `.OnServerEvent:Connect(`, so a handler
		limited inside a named function reads to it as unguarded — the same note QuickChatService
		carries. It is also the right place on its own terms: C18's kill button shipped broken because
		`MonsterService` consumed a token BEFORE its type guard, so every malformed tap spent a real
		player's budget. Here the token is spent first because the limiter is the cheapest thing in the
		path and a firehose must cost the server nothing; the type check follows immediately, so a
		malformed id never reaches a lookup.
	]]
	Remotes.Get("RequestEquipCosmetic").OnServerEvent:Connect(function(player: Player, id: unknown)
		if not AntiCheatService.Consume(player, "RequestEquipCosmetic") then
			return
		end

		onEquip(player, id)
	end)

	Remotes.Get("RequestBuyCosmetic").OnServerEvent:Connect(function(player: Player, id: unknown)
		if not AntiCheatService.Consume(player, "RequestBuyCosmetic") then
			return
		end

		onBuy(player, id)
	end)

	local function bind(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)

		if player.Character ~= nil then
			onCharacterAdded(player)
		end
	end

	Players.PlayerAdded:Connect(bind)

	-- Anyone who joined before this ran. The same backfill `RoundService.Start` and
	-- `ProgressionService.Start` do, for the same reason: connecting first means the window cannot
	-- drop a player, and the price is that someone arriving inside it is handled twice — which
	-- `applyLook` tolerates, being idempotent.
	for _, player in Players:GetPlayers() do
		bind(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		baseline[player.UserId] = nil
	end)

	--[[
		THE CORPSE FOLDER IS CREATED IN `MonsterService.Start`, and the bootstrap runs every `Init`
		before any `Start` — so this service must be listed AFTER MonsterService in `SERVICE_ORDER` or
		the folder is still nil here. It is, and the nil check is the belt to that braces: a missing
		folder costs the death effect, never an error in everyone's console.
	]]
	local corpses = MonsterService.GetCorpsesFolder()

	if corpses == nil then
		warn("[Cosmetics] no corpse folder — death effects are off this session")

		return
	end

	corpses.ChildAdded:Connect(playDeathEffect)
end

return CosmeticsService
