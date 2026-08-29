--!strict
--[[
	AmbientService — the barrio's cats, dogs, pigs and villagers. (V07, §4.3/§5)

	WHAT THIS SERVICE IS FOR, IN ONE SENTENCE: camouflage needs a crowd, and §5 is explicit that "what
	matters is the *count*". Three or four of each form, wandering, so that no single one is
	conspicuous and a survivor who counts heads learns nothing.

	IT OWNS THE POPULATION AND `MonsterService` OWNS THE MONSTER. The seam is two functions —
	`ClaimSlot(form)` and `ReleaseSlot(index)` — and the decision behind them is `shared/pure/
	AmbientRoster`, which is where "the head count does not move" is asserted over the whole roster
	space. Nothing about a Player, a role or a UserId reaches this file.

	SWAP, NEVER SPAWN (§4.3) — AND NOTHING EVER LEAVES `workspace`. THIS IS THE V07 CRITICAL FIX.

	The first version of this service PARKED the claimed entity: reparented it out of `workspace` into
	a holding folder in `ServerStorage`. That was measured in a live Studio session and it is a total
	secrecy failure. `ServerStorage` does not replicate, so the reparent REMOVES THE INSTANCE ON EVERY
	CLIENT — and `workspace.AmbientLife.ChildRemoved` then hands any listener the exact position the
	monster is standing at, the instant it hides:

	    CLIENT count=15 | Ambient_CAT_1 present=false | events captured=1
	      REMOVED Ambient_CAT_1 at 46.014, 3, 20.102 (count now 15)

	`#workspace.AmbientLife:GetChildren()` dropping below the spawned count is also a bare "someone is
	camouflaged right now" bit, readable with no event hook at all.

	SO A CLAIM MOVES NOTHING AND REPARENTS NOTHING. The entity stays exactly where it is in the tree;
	the slot is marked claimed, and `MonsterService` PUPPETS the entity to follow the Aswang's own
	character while hiding that character instead. The monster genuinely takes the entity's place —
	which is what §4.3 describes — and the barrio's visible population is byte-identical whether or
	not anyone is hidden.

	THERE IS NO HOLDING FOLDER ANY MORE, AND THAT ABSENCE IS THE GUARANTEE. A reparent needs somewhere
	to reparent TO; with no parked folder in this file there is no code path that can remove a child
	from `AmbientLife`, and a future one would have to create the folder first — which shows up in a
	diff. `.claude/lessons/absence-is-observable.md` is the lesson this was written against, and the
	first version violated it while carrying a comment claiming it did not.

	WHERE THEY STAND, AND WHY THERE ARE TWO ANSWERS. The map is not in Git — geometry and spawn points
	live in the place file, which is gitignored — so this service reads `CollectionService` tagged
	`AmbientSpawn` parts when the map provides them, and falls back to a code-generated ring when it
	finds none. The fallback is scaffolding for `npm run build` and for a fresh Studio session, not a
	design: see the map contract below.

	NO HUMANOID, NO PATHFINDING, NO PHYSICS. Each entity is a small anchored Model that the server
	steps toward a target CFrame. §5 asked for a wander and an idle; a Humanoid per entity is 16
	Humanoids on a phone, and `PathfindingService`'s cost at this population is a Roblox behaviour
	this plan has NOT verified — recorded in Follow Ups rather than assumed.

	THE APPEARANCE IS PARTS (§3's OUT list, and the zero art budget). A scaled, coloured block rig per
	form, built in code, exactly as the transform re-uses the avatar rather than shipping a mesh. It
	is placeholder-grade on purpose and V15 is where it stops being.

	────────────────────────────────────────────────────────────────────────────────────────────────
	THE MAP'S SPAWN-POINT CONTRACT (V07 Step 3.5) — WHAT A HUMAN HAS TO DO IN STUDIO

	This service reads points from the place file, and the place file is NOT IN GIT. Nothing in
	`npm run verify` can check the following, which is why it is written here rather than asserted
	somewhere: a check over gitignored geometry either always passes or checks the wrong thing.

	  - TAG: `AmbientSpawn`, applied with CollectionService (Studio's Tag Editor) to a BasePart.
	    Anything tagged that is not a BasePart is SKIPPED rather than erroring.
	  - COUNT: at least `Config.Ambient.PerForm * 4` — sixteen at the shipped value. Fewer works;
	    points are reused in order, which looks visibly wrong in Studio and is therefore fixable.
	    ZERO triggers the code fallback ring below, which is scaffolding and not a map.
	  - PLACEMENT: spread across the bahay kubo, the chapel and the well area, matching §5's
	    sightline rule — "you should almost always be able to see *something*". Entities wander
	    `Config.Ambient.WanderRadius` from their point and no further, so THE POINTS DETERMINE THE
	    DISTRIBUTION and the distribution is half the disguise: four pigs clustered in the plaza
	    means the pig by the chapel is the monster.
	  - THE PART ITSELF IS INVISIBLE SCAFFOLDING. Anchored, CanCollide = false, Transparency = 1.
	    Only its CFrame is read.
	  - PUBLISH AFTERWARDS. The place file's only backup is Roblox's cloud version history, and a
	    missing marker will never show up in `git status`.
	────────────────────────────────────────────────────────────────────────────────────────────────
]]

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AmbientRoster = require(Shared.pure.AmbientRoster)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local AmbientService = {}

--[[
	SERVER-ONLY ENTROPY, AND `Random.new()` WITH NO ARGUMENT IS THE WHOLE POINT (V07).

	CLAUDE.md is explicit that a seeded draw in replicated code is fatal — `Random.new(roundNumber)`
	or `Random.new(os.time())` lets a client replay it. Unseeded, there is nothing to replay and
	nothing on the wire. This generator never leaves this file and its outputs are only slot indices,
	which are not secret; it exists so the disguise is not campable, not to hide anything.
]]
local rng = Random.new()

--[[
	WHY THE FOUR FORMS ARE NOT A LIST IN THIS FILE.

	Two shapes were tried and neither typechecks under `--!strict`. `for _, form in
	Enums.CamouflageForm` yields `unknown` — a frozen table's iteration loses the
	`:: Types.CamouflageForm` casts its values carry. And a `{ Types.CamouflageForm }` literal list
	fails differently: the element comes back out as `string | string | string | string`, because A
	LITERAL UNION SURVIVES A REQUIRE AS A SCALAR AND DOES NOT SURVIVE IT INSIDE A LIST. That is
	`.claude/lessons/pure-module-unions-widen-in-lists.md` exactly. A nil-refinement through a
	narrowing function did not survive either, because the refinement does not carry across the
	nested loop body that needed it.

	WHAT WORKS IS A PARAMETER. `Start`'s `spawnForm(form: Types.CamouflageForm, ...)` is called four
	times with four literals, and a literal checked against an annotated parameter is narrowing the
	analyzer actually performs. The cost is four lines instead of a loop; the benefit is that the
	literal union reaches `roster[index]` intact and `AmbientRoster.Slot` typechecks.
]]

local SPAWN_TAG = "AmbientSpawn"
local ENTITIES_FOLDER = "AmbientLife"

--[[
	SERVER-ONLY. The roster is the pure module's; these tables map a slot index back to the Model that
	slot spawned and to where it is wandering, which is the half Lune cannot see.

	NONE OF THIS IS KEYED BY PLAYER. There is no UserId anywhere in this file, which is why no
	arrangement of it can distinguish one client's view from another's.
]]
local roster: AmbientRoster.Roster = {}
local models: { [number]: Model? } = {}
local homes: { [number]: CFrame? } = {}
local targets: { [number]: CFrame? } = {}
local nextRetargetAt: { [number]: number } = {}
local entities: Folder? = nil
local wanderConnection: RBXScriptConnection? = nil

--[[
	THE PLACEHOLDER RIG. A block per form, sized and coloured so the four are distinguishable at
	distance — which is the entire requirement, because §4.5's deduction is "which cat", never "is
	that a cat".

	NO LIGHT AND NO PARTICLE EMITTER, deliberately: §5's mobile budget is about exactly those two and
	`PerformanceController` enforces the light cap. Sixteen anchored parts spend neither.
]]
--[[
	THE FOUR AMBIENT FORMS, AS GENERATED MESHES RATHER THAN COLOURED BLOCKS.

	These were four `SmoothPlastic` boxes — the "moving box" a player sees drifting across the plaza.
	`Mesh` and `Texture` are Studio-minted asset ids from `generate_mesh`; `Size` is the bounding box
	each is scaled to and stays what it always was, because §4.5's deduction is "WHICH cat", never "is
	that a cat", and the four silhouettes have to stay tellable apart at distance.

	UPGRADING THESE UPGRADES THE DISGUISE FOR FREE, and that is a property of the design rather than a
	coincidence. `MonsterService.enterCamouflage` does NOT re-skin the player — it hides their body and
	puppets one of these entities through `PuppetSlot`. So the Aswang wearing a cat is literally one of
	these rigs. There is no second appearance path that could drift from this one, which is exactly the
	kind of divergence that would hand survivors a free tell.

	A FAILED MESH LOAD FALLS BACK TO THE BOX rather than erroring. An ambient population that fails to
	spawn is a camouflage mechanic with no slots in it — `ClaimSlot` returns nil and the Aswang simply
	cannot hide — so a degraded look is strictly better than a missing entity.
]]
local FORM_LOOKS: {
	[Types.CamouflageForm]: { Size: Vector3, Colour: Color3, Mesh: string, Texture: string },
} =
	{
		CAT = {
			Size = Vector3.new(1.4, 1.2, 2.6), -- config-ok: rig proportions, not balance
			Colour = Color3.fromRGB(64, 60, 58), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://98654944459292", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://111446154045426", -- config-ok: generated texture asset, not balance
		},
		DOG = {
			Size = Vector3.new(1.8, 1.9, 3.2), -- config-ok: rig proportions, not balance
			Colour = Color3.fromRGB(122, 94, 62), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://131182319795370", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://108587618947011", -- config-ok: generated texture asset, not balance
		},
		PIG = {
			Size = Vector3.new(2.0, 1.8, 3.4), -- config-ok: rig proportions, not balance
			Colour = Color3.fromRGB(198, 148, 148), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://108719451589587", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://125798003654731", -- config-ok: generated texture asset, not balance
		},
		VILLAGER = {
			-- The tall one, and that is the whole of what these four silhouettes must convey: §4.5's
			-- deduction is "which cat", never "is that a cat".
			Size = Vector3.new(2.0, 5.0, 1.2), -- config-ok: rig proportions, not balance
			Colour = Color3.fromRGB(96, 108, 128), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://131254025115965", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://81445534883746", -- config-ok: generated texture asset, not balance
		},
	}

--[[
	WHERE THE POPULATION STANDS. Tagged points if the map has them; a ring if it does not.

	THE FALLBACK MUST NOT SILENTLY REPLACE A REAL MAP. It fires only on ZERO tagged parts, never on
	"fewer than we wanted" — a map with three markers and a Config asking for sixteen gets three
	spawn points reused, which is visibly wrong in Studio and therefore fixable, rather than a ring of
	pigs at the origin overlapping the barrio.
]]
local function spawnPoints(): { CFrame }
	local points: { CFrame } = {}

	for _, tagged in CollectionService:GetTagged(SPAWN_TAG) do
		if tagged:IsA("BasePart") then
			table.insert(points, tagged.CFrame)
		end
	end

	if #points > 0 then
		return points
	end

	local total = Config.Ambient.PerForm * 4 -- config-ok: four forms, and there are four of them

	for index = 1, total do
		local angle = (index / total) * math.pi * 2 -- config-ok: a full turn, not a knob
		local radius = Config.Ambient.FallbackScatterRadius

		table.insert(
			points,
			CFrame.new(
				math.cos(angle) * radius,
				Config.Ambient.FallbackHeight,
				math.sin(angle) * radius
			)
		)
	end

	return points
end

--[[
	BUILD ONE ENTITY. Named by form and index — `Ambient_PIG_2` — and NEVER by anything derived from
	who claimed it. `workspace` replicates to every client, so a Model named after a player, or
	carrying an attribute or tag recording its claim state, would be a client-readable index of where
	the monster is standing. There is no such attribute and no such tag anywhere in this file.
]]
local function buildEntity(form: Types.CamouflageForm, index: number, at: CFrame): Model
	local look = FORM_LOOKS[form]
	local model = Instance.new("Model")
	model.Name = `Ambient_{form}_{index}`

	--[[
		A MESH IF IT LOADS, A BOX IF IT DOES NOT. `CreateMeshPartAsync` yields and can fail — the asset
		may be moderated, or the place rolled back past the upload — and a nil entity here is worse
		than an ugly one: it removes a camouflage slot, and `ClaimSlot` returning nil means the Aswang
		cannot hide at all. So the box survives as the fallback rather than being deleted.
	]]
	local body: BasePart

	local ok, meshPart = pcall(function()
		return AssetService:CreateMeshPartAsync(look.Mesh)
	end)

	if ok and meshPart ~= nil then
		body = meshPart :: MeshPart
		(body :: MeshPart).TextureID = look.Texture
	else
		warn(
			`[AmbientService] {form} mesh {look.Mesh} failed to load — falling back to a plain body. `
				.. `The slot still exists, so camouflage still works; it just looks wrong.`
		)

		body = Instance.new("Part")
		body.Color = look.Colour
		body.Material = Enum.Material.SmoothPlastic
	end

	body.Name = "Body"
	body.Size = look.Size
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = at
	body.Parent = model

	model.PrimaryPart = body

	return model
end

--[[
	CLAIM A SLOT OF THIS FORM FOR THE MONSTER. Returns the index, or nil when this form is exhausted.

	`MonsterService` calls this and refuses the hide on nil — `CamouflageRules.evaluate` answers
	NO_SLOT. THERE IS NO PATH IN THIS FILE THAT CREATES AN ENTITY TO SATISFY A CLAIM, and that absence
	is the mechanic: `AmbientRoster.claim` returns nil rather than appending, and this function has
	nothing to add to it.

	IT MOVES NOTHING AND REPARENTS NOTHING — see the header. Marking the slot is the WHOLE of what a
	claim does here; the entity stays in `workspace.AmbientLife` exactly where it was, and
	`MonsterService` takes it over through `PuppetSlot` below. Any line in this function that touched
	`model.Parent` would restore the Critical.

	THE ONLY OBSERVABLE EFFECT OF A CLAIM IS THAT THE ENTITY STOPS WANDERING ON ITS OWN and starts
	moving with the monster — which is not a leak but the MECHANIC. §4.5's deduction is "which cat is
	behaving oddly", and that is exactly the signal a survivor is supposed to have to work for.
]]
function AmbientService.ClaimSlot(form: Types.CamouflageForm): number?
	--[[
		A RANDOM FREE SLOT OF THIS FORM, chosen HERE because this file is server-only and
		`AmbientRoster` is not. The pure module takes the index as a hint and falls back to its own
		scan, so exhaustion still refuses exactly as before.
	]]
	local free = AmbientRoster.freeSlots(roster, form)
	local prefer = if #free > 0 then free[rng:NextInteger(1, #free)] else nil

	local claimed, slotIndex = AmbientRoster.claim(roster, form, prefer)

	roster = claimed

	return slotIndex
end

--[[
	DRIVE A CLAIMED ENTITY TO WHERE THE MONSTER IS. (V07, §4.3) Called every Heartbeat by
	`MonsterService` for each camouflaged Aswang.

	THIS IS WHAT REPLACED THE PARK. The entity is the visible half of the disguise and the player's
	own character is the hidden half — the inverse of the first implementation, and the reason the
	barrio's child set never changes.

	IT REFUSES TO DRIVE AN UNCLAIMED SLOT. A caller that could puppet any entity would be able to walk
	a pig around without owning it, and the wander loop would fight it every frame.
]]
function AmbientService.PuppetSlot(slotIndex: number?, cframe: CFrame)
	if slotIndex == nil then
		return
	end

	local slot = roster[slotIndex]
	local model = models[slotIndex]

	if slot == nil or not slot.Claimed or model == nil then
		return
	end

	model:PivotTo(cframe)
end

--[[
	IS THERE A FREE SLOT OF ANY FORM, AND WHICH? (V07, §4.3) THE READ-ONLY COMPANION TO `ClaimSlot`.

	`CamouflageRules.evaluate` needs to be told `SlotAvailable` BEFORE it decides, and a claim that
	happened first would have to be undone on every refusal — five verdicts' worth of unwind, each of
	which could leak the slot it was meant to release. So this asks without taking.

	IT PICKS, RATHER THAN LETTING THE CLIENT PICK. `Remotes.luau` records why `RequestCamouflage`
	carries no argument: a client naming a form could ask for each of the four in turn, read the
	verdicts, and map which corners of the barrio have been depopulated without walking anywhere.

	FIRST FORM WITH ROOM, IN A FIXED ORDER, AND NOT A RANDOM ONE. A random pick would want a seed, and
	a seeded draw is the one shape CLAUDE.md names as fatal. Which form the monster gets is not a
	secret — a player can see what it turned into — so there is nothing here worth a draw.
]]
local function formFromId(id: string): Types.CamouflageForm?
	if id == "CAT" then
		return "CAT"
	elseif id == "DOG" then
		return "DOG"
	elseif id == "PIG" then
		return "PIG"
	elseif id == "VILLAGER" then
		return "VILLAGER"
	end

	return nil
end

function AmbientService.PickAvailableForm(): Types.CamouflageForm?
	--[[
		A RANDOM FORM AMONG THOSE WITH ROOM, not the first one found. The first-found version made
		every hide in every round the same form — an exploit audit's Medium — so a survivor learned
		one spot and camped it forever.
	]]
	local available: { number } = {}

	for index, slot in roster do
		if not slot.Claimed then
			table.insert(available, index)
		end
	end

	if #available == 0 then
		return nil
	end

	local pickIndex = available[rng:NextInteger(1, #available)]

	for index, slot in roster do
		if index == pickIndex then
			--[[
				NARROWED THROUGH A FUNCTION, NOT RETURNED DIRECTLY. `slot.Form` is a literal union
				INSIDE `AmbientRoster.Roster`, which is a list — and a literal union does not survive
				a require inside a list, so it arrives here as plain `string` and the caller in
				`MonsterService` rejects it. Re-narrowing beats a cast for the reason the lesson
				gives: an unknown id returns nil to be dropped, where `:: Types.CamouflageForm` would
				wave it through. See `.claude/lessons/pure-module-unions-widen-in-lists.md`.
			]]
			return formFromId(slot.Form)
		end
	end

	return nil
end

--[[
	GIVE THE SLOT BACK. IDEMPOTENT AND TOTAL, because Phase 4 releases from five exits and at least
	two of them can fire for the same slot in the same frame — `ApplySaltHit` walks
	`endFeed` -> `revert` -> exit camouflage, on a path `onPhaseChanged` may also be walking.

	IT DOES NOT REPOSITION THE ENTITY. Reparenting an anchored Model does not move it, so the cat
	comes back exactly where it vanished. A `PivotTo(home)` added here later for tidiness would be a
	tell — the entity teleporting to its spawn point the moment the monster steps out of it.
]]
function AmbientService.ReleaseSlot(slotIndex: number?)
	roster = AmbientRoster.release(roster, slotIndex)

	--[[
		AND THAT IS ALL IT DOES. Nothing to un-park, because nothing was parked.

		THE ENTITY RESUMES WANDERING FROM WHEREVER THE MONSTER LEFT IT, which is correct and is also
		the cheapest possible behaviour: `wanderTick` retargets from `homes[index]`, so a released cat
		walks back toward its spawn point on its own instead of teleporting there. A `PivotTo(home)`
		added here for tidiness would be a tell — the entity snapping across the barrio the instant
		the monster steps out of it.
	]]
end

--[[
	ONE SERVER LOOP FOR THE WHOLE POPULATION, not sixteen threads. Retarget every `WanderInterval`
	plus an idle, step at `WanderSpeed`, leashed to `WanderRadius` of the point the entity spawned at.

	A CLAIMED SLOT IS SKIPPED because `MonsterService` is driving it through `PuppetSlot`. Two writers
	on one CFrame would fight every frame — the wander pulling it toward its home point while the
	monster walks it the other way — which reads in game as an entity juddering in place, and is
	exactly the sort of "that one is behaving strangely" tell the disguise cannot afford to give for
	free.
]]
local function wanderTick(deltaTime: number)
	local now = os.clock()

	for index, model in models do
		local slot = roster[index]

		if model == nil or slot == nil or slot.Claimed then
			continue
		end

		local home = homes[index]

		if home == nil then
			continue
		end

		local target = targets[index]
		local retargetAt = nextRetargetAt[index] or 0

		if target == nil or now >= retargetAt then
			local angle = math.random() * math.pi * 2 -- config-ok: a full turn, not a knob
			local distance = math.random() * Config.Ambient.WanderRadius

			target = home * CFrame.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			targets[index] = target
			nextRetargetAt[index] = now + Config.Ambient.WanderInterval + Config.Ambient.IdleSeconds
		end

		if target == nil then
			continue
		end

		local current = model:GetPivot()
		local offset = target.Position - current.Position
		local distance = offset.Magnitude
		local step = Config.Ambient.WanderSpeed * deltaTime

		if distance <= step or distance <= 0 then
			continue
		end

		local direction = offset.Unit
		local moved = current.Position + direction * step

		model:PivotTo(CFrame.lookAt(moved, moved + direction))
	end
end

function AmbientService.Init()
	table.clear(roster)
	table.clear(models)
	table.clear(homes)
	table.clear(targets)
	table.clear(nextRetargetAt)
end

--[[
	SPAWN THE POPULATION ONCE, AT BOOT, AND NEVER AGAIN.

	NOTHING ELSE IN THIS FILE CALLS THE SPAWN PATH. A population that grows after `Start` is the
	swap-not-spawn rule broken from the other end — and it would be invisible, because the extra
	entity would look exactly like the fifteen legitimate ones.

	NO `PhaseChanged` SUBSCRIPTION, DELIBERATELY. Ambient life is barrio scenery: it wanders in the
	lobby too. A population that appeared when a round started would be a round-state readout in the
	geometry, readable by any client.
]]
function AmbientService.Start()
	local points = spawnPoints()

	if #points == 0 then
		return
	end

	entities = Instance.new("Folder");
	(entities :: Folder).Name = ENTITIES_FOLDER;
	(entities :: Folder).Parent = workspace

	--[[
		SPAWN `PerForm` OF ONE FORM. Takes the running placement count and returns it, so the point
		reuse stays sequential across all four calls.

		THE PARAMETER IS THE NARROWING. `form` arrives as the literal union because each call site
		below passes a LITERAL checked against this annotation — which is narrowing the analyzer
		performs, unlike a cast or a nil-refinement carried across a nested loop. Both of those were
		tried here and neither survived; see FORM_IDS above and
		`.claude/lessons/pure-module-unions-widen-in-lists.md`.
	]]
	local function spawnForm(form: Types.CamouflageForm, placed: number): number
		local running = placed

		for _ = 1, Config.Ambient.PerForm do
			running += 1

			-- Points are reused in order when the map supplies fewer than the population needs.
			local at = points[((running - 1) % #points) + 1]
			local index = #roster + 1
			local model = buildEntity(form, index, at)

			model.Parent = entities

			roster[index] = { Form = form, Claimed = false }
			models[index] = model
			homes[index] = at
		end

		return running
	end

	--[[
		FOUR CALLS RATHER THAN A LOOP OVER A LIST, and the order is the spawn order. A list would put
		the literals back inside a table and widen them again, which is the whole reason this is
		written out.
	]]
	local placed = 0
	placed = spawnForm("CAT", placed)
	placed = spawnForm("DOG", placed)
	placed = spawnForm("PIG", placed)
	placed = spawnForm("VILLAGER", placed)

	wanderConnection = RunService.Heartbeat:Connect(wanderTick)
end

--[[
	Exposed for Phase 4's tests and for the playtester's console probes ONLY. It reports a COUNT, not
	a claim state and not an index, so nothing readable here names which entity the monster is in.
]]
function AmbientService.VisibleCount(form: Types.CamouflageForm): number
	return AmbientRoster.visibleCount(roster, form)
end

function AmbientService.Stop()
	if wanderConnection ~= nil then
		wanderConnection:Disconnect()
		wanderConnection = nil
	end
end

return AmbientService
