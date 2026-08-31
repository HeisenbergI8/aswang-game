--!strict
--[[
	AmbientService — the barrio's cats, dogs, pigs, goats, chickens and villagers. (V07, §4.3/§5)

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

	NO PATHFINDING AND NO PHYSICS. Each entity is an anchored Model that the server steps toward a
	target CFrame. §5 asked for a wander and an idle, and `PathfindingService`'s cost at this
	population is a Roblox behaviour this plan has NOT verified — recorded in Follow Ups, not assumed.

	AND HUMANOIDS ARE NO LONGER ZERO — THERE ARE THREE, ALL VILLAGERS. This paragraph used to say "no
	Humanoid" and cite "16 Humanoids on a phone" as the reason. That number was the objection to a
	Humanoid PER ENTITY, and it still stands: the five animal forms are mesh bodies and always will be.
	VILLAGER is the exception because it is the one form a player recognises the gait of — a rigid
	human mesh slid along the ground with a sine on its Y reads as bouncing rather than walking, which
	is what a playtest reported. A mesh has no joints, so no amount of tuning the bob could have fixed
	it. `PerForm` is 3, so the cost is three Humanoids rather than eighteen.

	THE APPEARANCE IS MESHES, PLUS ONE R15 RIG. Generated meshes per animal form (`FORM_LOOKS`) and a
	default R15 body for VILLAGER, both built in code. Still placeholder-grade on purpose; V15 is where
	that stops being true.

	────────────────────────────────────────────────────────────────────────────────────────────────
	THE MAP'S SPAWN-POINT CONTRACT (V07 Step 3.5) — WHAT A HUMAN HAS TO DO IN STUDIO

	This service reads points from the place file, and the place file is NOT IN GIT. Nothing in
	`npm run verify` can check the following, which is why it is written here rather than asserted
	somewhere: a check over gitignored geometry either always passes or checks the wrong thing.

	  - TAG: `AmbientSpawn`, applied with CollectionService (Studio's Tag Editor) to a BasePart.
	    Anything tagged that is not a BasePart is SKIPPED rather than erroring.
	  - ATTRIBUTE: `Form`, a string, one of CAT / DOG / PIG / GOAT / CHICKEN / VILLAGER. A tagged
	    part WITHOUT it is skipped with a warning rather than defaulted — see `spawnPointsByForm`.
	  - COUNT: `Config.Ambient.PerForm` points PER FORM — three each, eighteen in total. A form with
	    fewer gets rigs stacked on shared points; a form with more gets a territory no rig occupies,
	    which refuses a claim to a monster standing visibly inside it. ZERO points overall triggers
	    the code fallback ring below, which is scaffolding and not a map.
	  - PLACEMENT IS NOW A GAMEPLAY CONTRACT, NOT ONLY A DISTRIBUTION ONE. Entities wander
	    `Config.Ambient.WanderRadius` from their point and no further, and the Aswang may only claim
	    a slot within `Config.Ambient.ClaimRadius` of where it stands. So THE POINTS DECIDE WHERE EACH
	    DISGUISE IS AVAILABLE: pigs at mud, chickens in house yards, goats at field edges, cats in
	    alleys, dogs on roads, villagers on porches and at the store bench.
	  - EVERY POINT OWES ITS PROP. A pig territory with no wallow beside it is a rule a player cannot
	    see, and an invisible rule is a trap rather than counterplay. Whoever moves a point moves the
	    prop with it; neither this file nor `npm run verify` can check that, which is why it is
	    written here.
	  - THE PART ITSELF IS INVISIBLE SCAFFOLDING. Anchored, CanCollide = false, Transparency = 1.
	    Only its CFrame is read.
	  - PUBLISH AFTERWARDS. The place file's only backup is Roblox's cloud version history, and a
	    missing marker will never show up in `git status`.
	────────────────────────────────────────────────────────────────────────────────────────────────
]]

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AmbientRoster = require(Shared.pure.AmbientRoster)
local AmbientRig = require(Shared.pure.AmbientRig)
local AmbientMotion = require(Shared.pure.AmbientMotion)
local AmbientTerritory = require(Shared.pure.AmbientTerritory)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local AmbientService = {}

--[[
	THERE IS NO GENERATOR IN THIS FILE ANY MORE, AND THE ABSENCE IS DELIBERATE.

	V07 drew a random free slot and a random available form here, because an exploit audit found that
	a first-free pick sent every hide in every round to the same slot and a survivor could camp it.
	Phase 3 answers that differently: the slot is the NEAREST free territory of the requested form, and
	which territory that is depends on where the monster chose to walk — which is not campable without
	following it, and which produces a shorter visible jump than a random in-range pick would.

	SO `Random.new()` WAS REMOVED RATHER THAN LEFT UNUSED. CLAUDE.md names a seeded draw in replicated
	code as fatal, and a live generator in a file that no longer draws is an invitation to seed one.
]]

--[[
	WHY THE SIX FORMS ARE NOT A LIST IN THIS FILE.

	Two shapes were tried and neither typechecks under `--!strict`. `for _, form in
	Enums.CamouflageForm` yields `unknown` — a frozen table's iteration loses the
	`:: Types.CamouflageForm` casts its values carry. And a `{ Types.CamouflageForm }` literal list
	fails differently: the element comes back out as a widened `string`, because A
	LITERAL UNION SURVIVES A REQUIRE AS A SCALAR AND DOES NOT SURVIVE IT INSIDE A LIST. That is
	`.claude/lessons/pure-module-unions-widen-in-lists.md` exactly. A nil-refinement through a
	narrowing function did not survive either, because the refinement does not carry across the
	nested loop body that needed it.

	WHAT WORKS IS A PARAMETER. `Start`'s `spawnForm(form: Types.CamouflageForm, ...)` is called six
	times with six literals, and a literal checked against an annotated parameter is narrowing the
	analyzer actually performs. The cost is six lines instead of a loop; the benefit is that the
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

--[[
	WHERE EACH SLOT'S TERRITORY IS, IN LOCKSTEP WITH `roster`.

	`AmbientTerritory.nearestFreeIndex` returns a POINT index and `AmbientService` uses it as a SLOT
	index, so the two lists must be the same length in the same order. THAT IS BUILT, NOT ASSUMED:
	`Start` appends to this list inside the same loop that appends to `roster`, because
	`CollectionService:GetTagged` GIVES NO ORDER GUARANTEE and a list built by walking the tagged parts
	would pair slot 7 with whichever pig pad the engine happened to hand back third.
]]
local territories: { AmbientTerritory.Point } = {}

--[[
	HOW LONG EACH RIG HAS BEEN ANIMATING, in seconds, accumulated per index.

	PER RIG RATHER THAN ONE SHARED CLOCK, so a rig spawned late does not start mid-stride — and
	cleared in `Init` alongside the other stores, or a restarted round resumes every animation at
	whatever phase the last one ended on.
]]
local elapsed: { [number]: number } = {}

--[[
	EACH RIG'S BASE FACING — ROTATION ONLY, WITH NO MOTION IN IT.

	STORED RATHER THAN READ BACK OFF THE MODEL, and the version that read it back was wrong in a way
	only the running game could show. A still rig reused `model:GetPivot()`'s rotation as its base,
	which ALREADY CONTAINED the previous frame's sway — so the roll compounded every Heartbeat and a
	stationary animal slowly rolled over. Measured in Studio: 4-degree sway, 5.98 degrees of observed
	tilt, and a roll span approaching a full turn over four seconds.

	SO THE BASE IS WRITTEN ONLY WHEN THE RIG ACTUALLY TURNS, and every frame composes
	position -> base -> sway from scratch. There is nothing to accumulate.
]]
local facings: { [number]: CFrame } = {}

--[[
	THE DISTANCE BELOW WHICH A RIG COUNTS AS NOT HAVING MOVED, in studs.

	A GEOMETRIC TOLERANCE, NOT A BALANCE KNOB — it exists because `Vector3.Unit` on a near-zero vector
	is not a number and `CFrame.lookAt` on a zero direction errors, so both need a floor and the floor
	wants to be the same value in both places. Moving it changes nothing a player can feel; it is a
	hundredth of a millimetre.

	WAIVED RATHER THAN MOVED TO `Config`, and named rather than left inline in three places. Putting a
	floating-point guard band in the balance table would invite someone to tune it at V16 alongside
	numbers that actually change how the game plays, which is precisely the confusion `check:config`
	exists to prevent in the other direction.
]]
local MOTION_EPSILON = 0.0001 -- config-ok: a float guard band, not a tunable; see above
local targets: { [number]: CFrame? } = {}
local nextRetargetAt: { [number]: number } = {}
local entities: Folder? = nil
local wanderConnection: RBXScriptConnection? = nil

--[[
	LIFT PER SLOT — HOW FAR A RIG'S PIVOT SITS ABOVE ITS OWN FEET, MEASURED WHEN IT IS BUILT.

	THIS REPLACES THREE INDEPENDENT ANSWERS TO THE SAME QUESTION, all of which used to say
	"half the body's height" in slightly different words: `buildEntity` read `look.Size.Y`,
	`wanderTick`'s retarget read `model.PrimaryPart.Size.Y`, and `PuppetSlot` read `body.Size.Y`.
	`AmbientRig`'s header calls the last two "the two that must agree" — there were three, and they
	agreed only because every form happened to be a single centred box.

	VILLAGER STOPPED BEING ONE. An R15 model pivots on its `HumanoidRootPart`, so `PrimaryPart.Size.Y`
	is 2 — the root block — rather than the five studs of character standing on the ground. All three
	expressions would have sunk the villager, and `PuppetSlot`'s and `buildEntity`'s would have sunk it
	by the same amount only by coincidence, which is not a property worth relying on for the one thing
	in this file that must not differ between a free rig and a claimed one.

	SO IT IS MEASURED ONCE, FROM THE MODEL ITSELF, and every seating rule reads this table.
]]
local lifts: { [number]: number } = {}

--[[
	THE ANIMATION TRACKS OF THE RIGGED FORMS, and nothing else goes in here.

	Keyed by slot index, exactly like `models`, so a claimed slot and a free one are looked up the same
	way and there is no branch that could animate one and not the other.
]]
type Stride = { Idle: AnimationTrack, Walk: AnimationTrack }

local strides: { [number]: Stride? } = {}

--[[
	WHICH FORMS ARE R15 RIGS RATHER THAN A SINGLE MESH BODY.

	A TABLE RATHER THAN `form == "VILLAGER"` SPRINKLED AT FOUR SITES. Four separate equality tests is
	four chances for a later form to be added to three of them, and the failure that produces is a rig
	that is animated on the free path and not on the claimed one — which is a leak, not a glitch.
]]
local RIGGED: { [string]: boolean } = { VILLAGER = true }

--[[
	Roblox's stock R15 idle and walk clips. Not balance and not secret — they are asset ids, the same
	class of constant as `FORM_LOOKS`'s meshes, and they carry the same waiver for the same reason.
]]
--[[
	NEITHER TRACK IS EVER GIVEN A WEIGHT OF EXACTLY ZERO.

	A track at weight 0 stops contributing, and a blend that reaches zero is a MODE SWITCH wearing a
	number — the same discrete threshold `AmbientMotion`'s header rejects for the bob, and for the same
	reason: two rigs would arrive at it at different moments, and the one that arrived on the monster's
	movement rather than on its own schedule is a tell. Both clips stay live at all speeds.
]]
local STRIDE_WEIGHT_FLOOR = 0.001 -- config-ok: a float guard band, not a tunable; see above

local RIG_IDLE_ANIMATION = "rbxassetid://507766388" -- config-ok: stock R15 idle clip, not balance
local RIG_WALK_ANIMATION = "rbxassetid://507777826" -- config-ok: stock R15 walk clip, not balance

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
		--[[
			EVERY `Size` IS THE GENERATED MESH'S OWN BOUNDING BOX, UNIFORMLY SCALED — NEVER A BOX THE
			MESH IS SQUASHED INTO.

			`buildEntity` assigns `body.Size = look.Size` outright, and a MeshPart STRETCHES to whatever
			it is given. The Phase 1 sizes were the boxes the meshes were REQUESTED in, and the
			generator fits inside a request while preserving aspect: the cat came back 0.46 wide, so
			forcing it into the requested 1.4 would have made it three times too broad. Six animals
			each distorted on a different axis is a barrio of funhouse mirrors, and nothing in
			`npm run verify` looks at a shape.

			SO THE ONLY FREEDOM TAKEN IS A UNIFORM SCALE TO THE RESEARCHED HEIGHT, applied to two of
			the six. GOAT came back 1.71 tall against a dog's 1.90, which is both wrong for a standing
			goat and the exact pair §4.5's "which one" is most likely to confuse; VILLAGER came back
			3.64, which is child-height beside a 5-stud player. The other four already matched.

			HEIGHT IS ALSO WHAT `AmbientRig.restingY` READS, so these numbers are the ones that put
			feet on the ground. Changing one changes where that form stands.
		]]
		CAT = {
			Size = Vector3.new(0.46, 1.2, 1.22), -- config-ok: generated mesh proportions, not balance
			Colour = Color3.fromRGB(64, 60, 58), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://96211506575053", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://130634110713517", -- config-ok: generated texture asset, not balance
		},
		DOG = {
			Size = Vector3.new(0.74, 1.9, 2.14), -- config-ok: generated mesh proportions, not balance
			Colour = Color3.fromRGB(122, 94, 62), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://95323271856112", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://80047444313330", -- config-ok: generated texture asset, not balance
		},
		PIG = {
			Size = Vector3.new(1.18, 1.8, 2.73), -- config-ok: generated mesh proportions, not balance
			Colour = Color3.fromRGB(58, 52, 50), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://108005880380762", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://120673320204813", -- config-ok: generated texture asset, not balance
		},
		--[[
			GOAT AND CHICKEN ARE THE TWO FORMS v2.0 ADDED, and both are TETHERED OR YARD-BOUND in life
			rather than free-roaming — which is what makes their territories accurate rather than
			arbitrary, and therefore what makes the constraint on the Aswang fair.

			BOTH ARE SMALL, AND THAT IS RESEARCHED. The Philippine native goat is 10.5-24.4 kg with
			erect ears — knee-height on an adult, not a Western dairy goat. The native chicken hen is
			1.0-1.3 kg. Six silhouettes have to stay tellable apart in fog at distance (§4.5: "which
			cat", never "is that a cat"), and the chicken is the one at real risk of reading as a rock.
			See `references/research-01-barrio-animals.md`.
		]]
		GOAT = {
			Size = Vector3.new(1.54, 2.2, 1.98), -- config-ok: generated mesh proportions, not balance
			Colour = Color3.fromRGB(74, 64, 58), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://100545159776343", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://104493613437573", -- config-ok: generated texture asset, not balance
		},
		CHICKEN = {
			Size = Vector3.new(0.61, 1.1, 1.23), -- config-ok: generated mesh proportions, not balance
			Colour = Color3.fromRGB(150, 108, 52), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://115234736069936", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://113527179344004", -- config-ok: generated texture asset, not balance
		},
		VILLAGER = {
			-- The tall one, and that is the whole of what these six silhouettes must convey: §4.5's
			-- deduction is "which cat", never "is that a cat". Scaled to five studs so it stands at a
			-- player's height rather than a child's.
			Size = Vector3.new(1.95, 5.0, 1.65), -- config-ok: generated mesh proportions, not balance
			Colour = Color3.fromRGB(96, 108, 128), -- config-ok: fallback rig colour, not balance
			Mesh = "rbxassetid://124492172741324", -- config-ok: generated mesh asset, not balance
			Texture = "rbxassetid://119550214494630", -- config-ok: generated texture asset, not balance
		},
	}

--[[
	THE SIX FORM IDS, AS PLAIN STRINGS, FOR KEYING A TABLE — NOT FOR RETURNING.

	The list this file's header refuses is a `{ Types.CamouflageForm }`, because a literal union does
	not survive a require inside a list and the element comes back widened. THIS list is different in
	the one way that matters: nothing is ever returned from it. It is used to KEY `{ [string]: ... }`
	tables and to size the fallback ring, both of which want plain `string` anyway, so there is no
	narrowing to lose. `spawnForm` is still called with six literals for exactly that reason.

	`tests/camouflage-forms.test.luau` pins it against `Types.CamouflageForm`.
]]
local FORM_IDS = { "CAT", "DOG", "PIG", "GOAT", "CHICKEN", "VILLAGER" }

--[[
	WHERE THE POPULATION STANDS, PARTITIONED BY THE FORM EACH POINT NAMES.

	A PART TAGGED `AmbientSpawn` WITH NO `Form` ATTRIBUTE IS SKIPPED WITH A WARNING, not defaulted.
	That is what a half-updated place file looks like — someone added a marker in Studio and did not
	set the attribute — and defaulting it to CAT would put a cat in a rice paddy and make the territory
	rule quietly untrue for one entity. A skipped point leaves its form short of `PerForm`, which is
	visible in Studio, in this file's warning, and in the builder's own assert.

	THE FALLBACK MUST NOT SILENTLY REPLACE A REAL MAP. It fires only when NOT ONE point survived,
	never on "fewer than we wanted" — a map with three markers and a Config asking for eighteen gets
	three points reused, which is visibly wrong in Studio and therefore fixable, rather than a ring of
	pigs at the origin overlapping the barrio.
]]
local function spawnPointsByForm(): { [string]: { CFrame } }
	local byForm: { [string]: { CFrame } } = {}
	local found = 0

	for _, tagged in CollectionService:GetTagged(SPAWN_TAG) do
		if not tagged:IsA("BasePart") then
			continue
		end

		local form = tagged:GetAttribute("Form")

		if type(form) ~= "string" then
			warn(
				`[AmbientService] {tagged:GetFullName()} is tagged {SPAWN_TAG} with no Form attribute `
					.. `— skipped. The map contract in this file's header names the six valid values.`
			)
			continue
		end

		local list = byForm[form]

		if list == nil then
			list = {}
			byForm[form] = list
		end

		table.insert(list, (tagged :: BasePart).CFrame)
		found += 1
	end

	if found > 0 then
		return byForm
	end

	--[[
		THE FALLBACK RING, DEALT ROUND-ROBIN RATHER THAN IN BLOCKS. Six consecutive arc positions per
		form would put every pig in one 60-degree wedge, which is the clustering the territory rule
		exists to prevent — and the fallback is precisely the state nobody looks at closely, so it
		should not be the one that teaches the wrong shape.
	]]
	local total = Config.Ambient.PerForm * #FORM_IDS

	for index = 1, total do
		local angle = (index / total) * math.pi * 2 -- config-ok: a full turn, not a knob
		local radius = Config.Ambient.FallbackScatterRadius

		local form = FORM_IDS[((index - 1) % #FORM_IDS) + 1]
		local list = byForm[form]

		if list == nil then
			list = {}
			byForm[form] = list
		end

		table.insert(
			list,
			CFrame.new(
				math.cos(angle) * radius,
				Config.Ambient.FallbackHeight,
				math.sin(angle) * radius
			)
		)
	end

	return byForm
end

--[[
	BUILD ONE ENTITY. Named by form and index — `Ambient_PIG_2` — and NEVER by anything derived from
	who claimed it. `workspace` replicates to every client, so a Model named after a player, or
	carrying an attribute or tag recording its claim state, would be a client-readable index of where
	the monster is standing. There is no such attribute and no such tag anywhere in this file.
]]
--[[
	THE GROUND UNDER A SPAWN POINT, MEASURED RATHER THAN ASSUMED.

	The pad is a marker, not a floor: `anchor()` builds it 0.8 tall with its CENTRE at y = 0.4, and it
	is `CanCollide = false`, so the surface a rig actually stands on is whatever is beneath it. Seating
	a body at the pad's own CFrame buried it by half its height, which is what shipped.

	THE RAYCAST IGNORES `AmbientLife` so a rig cannot land on another rig — eighteen entities spawning
	in sequence would otherwise stack wherever two pads overlap, and the second one's ground would be
	the first one's back.

	A MISS FALLS BACK TO THE PAD'S UNDERSIDE, not to zero. A pad floating over a hole in the map is a
	map bug; putting the rig at the origin's height would move it across the barrio, which turns a
	visible local error into an invisible global one.

	ONCE PER RIG AT BOOT, NEVER PER FRAME. Eighteen casts inside `Start` is nothing; eighteen casts a
	Heartbeat is a number §5's mobile budget refuses, so this must not migrate into `wanderTick`.
]]
local function groundYUnder(at: CFrame): number
	local parameters = RaycastParams.new()

	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = if entities ~= nil then { entities :: Folder } else {}
	--[[
		ONLY COLLIDABLE GEOMETRY COUNTS AS GROUND, and without this the probe lands on scenery.

		A raycast hits anything with `CanQuery` on, which is nearly every part in the barrio — the
		dressing is `CanCollide = false` but fully queryable, and so is the entity's OWN `AmbientSpawn`
		pad, an 0.8-tall slab sitting directly under it. So a rig could be seated on the top face of its
		own marker, on a swept-yard slab, or on a road decal, none of which are floors.

		MEASURED, NOT SUSPECTED: `Ambient_CAT_3` was standing at pivot Y = -0.15 with the ground beneath
		it at 0 — a cat sunk into the dirt to its shoulders — while `CAT_1` and `CAT_2` on the same form
		sat at 0.61 and 0.73. Three rigs of one form at three different elevations is the difference
		this whole subsystem exists to prevent, and it varied by whatever decorative slab happened to be
		nearest.

		`RespectCanCollide` IS THE WHOLE FIX and it is one line, because "what can I stand on" and "what
		can I collide with" are the same question — which is also what `PathfindingService` uses to build
		the navmesh the rigs walk over.
	]]
	parameters.RespectCanCollide = true

	local hit = workspace:Raycast(
		at.Position + Vector3.new(0, Config.Ambient.GroundProbeUp, 0),
		Vector3.new(0, -Config.Ambient.GroundProbeDown, 0),
		parameters
	)

	if hit ~= nil then
		return hit.Position.Y
	end

	return at.Position.Y - Config.Ambient.SpawnPadHalfHeight
end

--[[
	BUILD THE ONE FORM THAT HAS JOINTS. Returns nil on any failure, and the caller falls back to the
	mesh body — a stiff villager is worse-looking than a walking one and strictly better than no slot
	at all, which is the same trade `buildEntity`'s mesh fallback already makes.

	`CreateHumanoidModelFromDescription` WITH A BLANK DESCRIPTION gives the default R15 body: a real
	rig with Motor6D joints and an `Animator`, which is the whole point — a `MeshPart` has no joints,
	so no animation can play on one and the only motion available to it was the bob that read as
	bouncing.

	THE `Animate` LOCALSCRIPT IS DELETED. It ships inside the model and is Roblox's own animation
	driver; left in place it would be a second writer on the same Animator, which is the exact shape
	`PuppetSlot`'s header spent a Critical learning to avoid. `stepEntity` is the only thing that may
	drive these tracks.

	EVERY PART IS NON-COLLIDING AND NON-QUERYING, like every other ambient body. A collidable villager
	would be a wall the navmesh can see, and eighteen of them would change the crossing time the map
	is measured on.
]]
local function buildRigBody(model: Model): (Humanoid?, number?)
	local ok: boolean, rig: Model? = pcall(function()
		return Players:CreateHumanoidModelFromDescription(
			Instance.new("HumanoidDescription"),
			Enum.HumanoidRigType.R15
		)
	end)

	if not ok or rig == nil then
		return nil, nil
	end

	local built = rig :: Model
	local humanoid = built:FindFirstChildWhichIsA("Humanoid")
	local root = built:FindFirstChild("HumanoidRootPart")

	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		built:Destroy()

		return nil, nil
	end

	local animate = built:FindFirstChild("Animate")

	if animate ~= nil then
		animate:Destroy()
	end

	--[[
		NO NAME AND NO HEALTH BAR OVER ITS HEAD. Both are on by default and both replicate to every
		client, so a villager would carry a floating "Humanoid" label that no other ambient form has —
		which is not a role leak but is an obvious "this one is different" marker on the one form the
		monster can wear.
	]]
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayName = ""

	for _, piece in built:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.CanCollide = false
			piece.CanQuery = false
			piece.CanTouch = false
			piece.Massless = true
		end
	end

	--[[
		ONLY THE ROOT IS ANCHORED. Anchoring every part would freeze the Motor6D joints along with it
		and the clips would play with nothing moving — the rig would slide exactly as the mesh did,
		with the animation cost added and none of the benefit.
	]]
	root.Anchored = true

	--[[
		THE LIFT, MEASURED RATHER THAN ASSUMED. `GetBoundingBox` gives the model's extents; the pivot
		is the root's CFrame. The gap between the pivot's Y and the box's bottom is how far the rig has
		to be raised to stand ON something, and it is not half the height of anything.
	]]
	local pivot = built:GetPivot()
	local boxCFrame, boxSize = built:GetBoundingBox()
	local lift = pivot.Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)

	for _, piece in built:GetChildren() do
		piece.Parent = model
	end

	built:Destroy()

	model.PrimaryPart = root

	return humanoid, lift
end

--[[
	LOAD THE IDLE AND WALK CLIPS ONTO A RIG. Returns nil if either fails, and the caller then leaves
	the rig unanimated rather than half-animated: one track playing without the other is a villager
	permanently mid-walk or permanently frozen, and either is worse than the stiff pose.
]]
local function loadStride(humanoid: Humanoid): Stride?
	local animator = humanoid:FindFirstChildWhichIsA("Animator")

	if animator == nil then
		return nil
	end

	local function track(id: string): AnimationTrack?
		local ok: boolean, loaded: AnimationTrack? = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = id

			return (animator :: Animator):LoadAnimation(animation)
		end)

		if not ok or loaded == nil then
			return nil
		end

		return loaded :: AnimationTrack
	end

	local idle = track(RIG_IDLE_ANIMATION)
	local walk = track(RIG_WALK_ANIMATION)

	if idle == nil or walk == nil then
		return nil
	end

	--[[
		BOTH PLAY AT ALL TIMES AND THE BLEND IS DONE WITH WEIGHT, not by starting and stopping. A
		start/stop switch is a discrete mode change, and `AmbientMotion`'s header rejects exactly that
		for exactly this reason: two rigs would cross the threshold at different moments, and the one
		that crossed on the monster's movement rather than on its own schedule is the tell.

		THE NEXT TWO PROPERTIES ARE WHY THE FIRST ATTEMPT SILENTLY DID NOTHING, and both failures looked
		identical from outside: a villager that walked around the barrio with its legs perfectly still.

		`Looped` — the stock walk clip is about a second long and STOPS at its end. It played once at
		spawn and was gone; `GetPlayingAnimationTracks` listed only the idle from then on. The idle clip
		loops on its own, so exactly half of this system appeared to work, which is what made it look
		like a blending problem rather than a playback one.

		`Priority` — AND THIS ONE WOULD HAVE SURVIVED THE FIRST FIX. Roblox does not blend across
		priorities: a higher-priority track MASKS a lower one outright on every joint it touches,
		regardless of weight. The stock clips ship at Idle and Movement respectively, so `AdjustWeight`
		would have gone on being called with correct numbers and changed nothing at all. Putting both on
		one priority is what makes the weight mean something.
	]]
	for _, loaded in { idle, walk } do
		loaded.Looped = true
		loaded.Priority = Enum.AnimationPriority.Movement
	end

	idle:Play(0)
	walk:Play(0)
	idle:AdjustWeight(1, 0)
	walk:AdjustWeight(STRIDE_WEIGHT_FLOOR, 0)

	return { Idle = idle, Walk = walk }
end

local function buildEntity(form: Types.CamouflageForm, index: number, at: CFrame): Model
	local look = FORM_LOOKS[form]
	local model = Instance.new("Model")
	model.Name = `Ambient_{form}_{index}`

	--[[
		A RIGGED FORM TAKES A DIFFERENT BODY AND THE SAME SEATING. If the rig fails to build we fall
		through to the mesh path below, so a villager is never missing — only stiff.
	]]
	if RIGGED[form] then
		local humanoid, lift = buildRigBody(model)

		if humanoid ~= nil and lift ~= nil then
			lifts[index] = lift

			local stride = loadStride(humanoid)

			if stride == nil then
				--[[
					SILENT UNTIL NOW, AND PER-RIG, WHICH IS THE WORSE HALF. `loadStride` has three
					independent nil exits and each of the three villagers calls it separately, so one
					transient asset fetch failure gives a barrio with two villagers walking and one bobbing
					with rigid legs. `Start` normalises that below; this warn is so it is not invisible.
				]]
				warn(
					`[AmbientService] {form} slot {index} built its rig but could not load a stride clip. `
						.. `Every rigged form is demoted to match it, so the population stays uniform.`
				)
			end

			strides[index] = stride

			model:PivotTo(
				CFrame.new(
					at.Position.X,
					AmbientRig.restingYFromLift(groundYUnder(at), lift),
					at.Position.Z
				) * (at - at.Position)
			)

			return model
		end

		warn(
			`[AmbientService] {form} R15 rig failed to build — falling back to the mesh body. `
				.. `The slot still exists and camouflage still works; it just will not walk.`
		)
	end

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
	--[[
		SEATED ON THE GROUND, NOT ON THE PAD. See `AmbientRig`'s header: this expression and
		`PuppetSlot`'s below are the two that must agree, and `tests/ambient-rig.test.luau` is where
		that agreement is stated over every form height rather than left to a reader.
	]]
	--[[
		A MESH BODY PIVOTS ON ITS OWN CENTRE, so its lift IS half its height — which is what
		`restingY` has always meant. It is recorded in `lifts` anyway so that every slot, rigged or
		not, answers the seating question from ONE table rather than from whichever expression its
		caller happened to use. See `lifts`' header for the three that used to disagree.
	]]
	lifts[index] = look.Size.Y / 2

	body.CFrame = CFrame.new(
		at.Position.X,
		AmbientRig.restingYFromLift(groundYUnder(at), lifts[index] :: number),
		at.Position.Z
	) * (at - at.Position)
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
local function freeFlags(): { boolean }
	local flags: { boolean } = {}

	for index = 1, #territories do
		local slot = roster[index]

		flags[index] = slot ~= nil and not slot.Claimed
	end

	return flags
end

function AmbientService.ClaimSlot(form: Types.CamouflageForm, at: Vector3): number?
	--[[
		THE NEAREST FREE SLOT OF THIS FORM WITHIN `ClaimRadius`, AND nil IF THERE IS NONE.

		THE RANDOM PICK IS GONE AND ITS REASON IS SATISFIED ANOTHER WAY. V07 replaced a first-free pick
		with a random one because an exploit audit found every hide landing on the same slot, so a
		survivor could camp it. Under territories the choice is made by WHERE THE MONSTER WALKED, which
		is not campable — and nearest is strictly better than random here, because on claim the entity
		is driven to the monster and a random in-range slot is a longer visible jump than the nearest.

		NO SEED CROSSES ANYTHING. `at` is the server's own copy of the monster's root position and the
		module it is handed to returns an index.
	]]
	local slotIndex = AmbientTerritory.nearestFreeIndex(
		territories,
		freeFlags(),
		form,
		at.X,
		at.Z,
		Config.Ambient.ClaimRadius
	)

	if slotIndex == nil then
		return nil
	end

	local claimed, granted = AmbientRoster.claim(roster, form, slotIndex)

	roster = claimed

	--[[
		AND IF THE ROSTER DISAGREED, REFUSE RATHER THAN FALL BACK. `AmbientRoster.claim` honours a
		hint and otherwise scans for the first free slot of that form — which is correct for its own
		contract and WRONG here, because that fallback slot could be anywhere in the barrio and would
		restore the map-wide jump this phase exists to close. So a granted index that is not the one
		asked for is released and refused.
	]]
	if granted ~= slotIndex then
		if granted ~= nil then
			roster = AmbientRoster.release(roster, granted)
		end

		return nil
	end

	--[[
		DROP THE STALE WANDER TARGET, SYMMETRICALLY WITH `ReleaseSlot`.

		`ReleaseSlot` already clears `targets[slotIndex]` on the way OUT, and its comment says why: a
		stale target is a rig walking somewhere nobody asked it to. Nothing cleared it on the way IN,
		and the claimed branch of `wanderTick` steps with `math.huge` — so on the first Heartbeat after
		a claim, before `MonsterService` has written a target, the rig SNAPPED to wherever it had been
		wandering, up to `WanderRadius` away, in a single frame.

		A free rig moves at most `WanderSpeed * dt` — about 0.067 studs a frame. A one-frame jump of
		tens of studs is not a subtle difference; it is a one-line client script with several hundred
		times the headroom it needs, and it fires at the exact instant somebody hides.

		THIS CLOSES THE STALE-TARGET JUMP AND NOT THE UNCAPPED STEP. With no target the claimed branch
		simply does nothing for that frame and the rig holds still, which is correct. The separate
		question of whether a claimed rig should be able to out-run every free one on EVERY frame is a
		design decision about how camouflage should feel, and it is deliberately not answered here.
	]]
	targets[slotIndex] = nil

	return granted
end

--[[
	DRIVE A CLAIMED ENTITY TO WHERE THE MONSTER IS. (V07, §4.3) Called every Heartbeat by
	`MonsterService` for each camouflaged Aswang.

	THIS IS WHAT REPLACED THE PARK. The entity is the visible half of the disguise and the player's
	own character is the hidden half — the inverse of the first implementation, and the reason the
	barrio's child set never changes.

	IT REFUSES TO DRIVE AN UNCLAIMED SLOT. A caller that could puppet any entity would be able to walk
	a pig around without owning it, and the wander loop would fight it every frame.

	IT TAKES A FOOT OFFSET NOW, AND THAT ARGUMENT CLOSED A LEAK THAT NEEDED NO MOTION TO READ.

	This function used to pivot the model straight onto the monster's HumanoidRootPart CFrame. A root
	centre stands about 3 studs above its own feet and a free rig's centre sat at its pad's 0.4, so
	the disguised animal FLOATED roughly 2.6 studs above every real one of its form — a static
	difference in a replicated `CFrame`, readable in one frame by any client, and never wrong.

	THAT IS A DIFFERENT KIND OF SIGNAL FROM THE ONE §4.5 INTENDS. "Which cat is behaving oddly" costs
	a survivor attention and can mislead them. "Which cat is in the air" costs nothing and cannot.
	`.claude/lessons/absence-is-observable.md`, and `check:secrecy` is a text tripwire that will report
	green over every version of this function.
]]
function AmbientService.PuppetSlot(slotIndex: number?, cframe: CFrame, footOffset: number)
	if slotIndex == nil then
		return
	end

	local slot = roster[slotIndex]
	local model = models[slotIndex]

	if slot == nil or not slot.Claimed or model == nil then
		return
	end

	local body = model.PrimaryPart

	if body == nil then
		return
	end

	--[[
		THIS FUNCTION NO LONGER MOVES ANYTHING. It records the same `targets[index]` a wander records,
		and `wanderTick` moves every rig — free and claimed — through the one `stepEntity`.

		THAT IS THE PHASE 4 CHANGE AND IT IS A SECRECY FIX, NOT A REFACTOR. Two writers on one CFrame
		meant two motion behaviours over one visible object, so any life added to the wander path would
		have made the disguised animal the only one that does not breathe.

		THE ROTATION IS THE MONSTER'S AND THE HEIGHT IS THE RIG'S. Taking the whole CFrame gave the
		right facing and the wrong elevation; taking only the position would lose the facing, and a cat
		that always points north is a second tell for the price of fixing the first.
	]]
	--[[
		THE LIFT COMES FROM `lifts`, NOT FROM `body.Size.Y`. For every mesh form those are the same
		number; for VILLAGER they are not, because the model pivots on a 2-stud HumanoidRootPart rather
		than on the centre of a 5-stud body. Reading the part would have put the disguised villager
		about two studs into the ground while every free villager stood on it — a static elevation
		difference, which is the exact class of leak this module was created to close.
	]]
	local lift = lifts[slotIndex]

	if lift == nil then
		return
	end

	targets[slotIndex] = CFrame.new(
		cframe.Position.X,
		AmbientRig.puppetYFromLift(cframe.Position.Y, footOffset, lift),
		cframe.Position.Z
	) * (cframe - cframe.Position)
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
	elseif id == "GOAT" then
		return "GOAT"
	elseif id == "CHICKEN" then
		return "CHICKEN"
	elseif id == "VILLAGER" then
		return "VILLAGER"
	end

	return nil
end

function AmbientService.PickAvailableFormNear(at: Vector3): Types.CamouflageForm?
	--[[
		THE FORM OF THE NEAREST CLAIMABLE TERRITORY, AND THE RENAME IS THE WARNING.

		THE RANDOM PICK IS GONE AND ITS EXPLOIT IS STILL ANSWERED. V07 replaced a first-found pick with
		a random one because a survivor could otherwise camp the one slot every hide landed on. Under
		territories the answer depends on WHERE THE MONSTER WALKED, which is not campable without
		following it — and asking the same question `ClaimSlot` asks is what guarantees a pick and a
		claim can never disagree. A random form among those with room could name a form whose only
		free territory is out of range, and the hide would then be refused after being offered.

		IT IS A NARROWER ORACLE THAN `PickAvailableForm` WAS, AND THAT IS WHY IT IS NAMED FOR ITS
		ARGUMENT. It encodes map information — which forms are available AT THIS POINT — and it is
		safe only because it is called for the requesting player, from the server's own copy of their
		own position, with the answer going back to them alone. Calling it for any OTHER player would
		hand one client a fact about where a second one is standing. There is no remote that does that
		today; the name is the only thing that will warn whoever adds one.
	]]
	local flags = freeFlags()
	local bestIndex: number? = nil
	local bestDistance = Config.Ambient.ClaimRadius * Config.Ambient.ClaimRadius

	for index, point in territories do
		if flags[index] ~= true then
			continue
		end

		local dx = point.X - at.X
		local dz = point.Z - at.Z
		local distance = dx * dx + dz * dz

		if distance < bestDistance then
			bestDistance = distance
			bestIndex = index
		end
	end

	if bestIndex == nil then
		return nil
	end

	--[[
		NARROWED THROUGH A FUNCTION, NOT RETURNED DIRECTLY. `point.Form` is plain `string` —
		`AmbientTerritory` declares it that way on purpose so nothing widens on the way out — and
		`MonsterService` wants the literal union. Re-narrowing beats a cast for the reason the lesson
		gives: an unknown id returns nil to be dropped, where `:: Types.CamouflageForm` would wave it
		through. See `.claude/lessons/pure-module-unions-widen-in-lists.md`.
	]]
	return formFromId(territories[bestIndex].Form)
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
		AND THE STALE TARGET GOES WITH IT, WHICH PHASE 4 MADE NECESSARY.

		`PuppetSlot` no longer moves the model — it writes `targets[index]`, the same slot a wander
		writes. So a released rig whose target still held the MONSTER'S last position would set off
		walking toward wherever the Aswang was standing when it dropped the disguise, which is a
		pointer at the monster drawn by the animal it just stopped being. Clearing it makes the next
		`wanderTick` retarget from `homes[index]` on its own.

		CLEARING A TARGET IS NOT TELEPORTING, and the rule below still stands. THE ENTITY RESUMES
		WANDERING FROM WHEREVER THE MONSTER LEFT IT: a released cat walks back toward its spawn point
		rather than snapping there. A `PivotTo(home)` added here for tidiness would be a tell — the
		entity crossing the barrio in one frame the instant the monster steps out of it.
	]]
	if slotIndex ~= nil then
		targets[slotIndex] = nil
	end
end

--[[
	ONE STEP FUNCTION FOR EVERY RIG, FREE OR CLAIMED, AND THAT IS THE SECRECY MECHANISM.

	Before this, `wanderTick` moved free rigs and `PuppetSlot` moved claimed ones — two functions in
	two files over one visible object. Every difference between them was a client-readable tell, and
	adding a bob to one of them would have made the disguised animal the only one that does not
	breathe: a better animation system producing a worse leak.

	NOW A CLAIM CHANGES TWO VALUES AND NO CODE. The target, and the cap on how far the rig may travel
	toward it this frame. Everything after that line is shared.

	THE SPEED THE MOTION READS IS MEASURED, NOT PASSED. `travel` below is the actual displacement, so a
	claimed rig keeping up with a sprinting monster animates like a fast animal and a free rig animates
	like a slow one — a difference of DEGREE in one function, which is §4.5's intended tell, rather
	than a difference of KIND, which is a free answer.
]]
local function stepEntity(index: number, model: Model, target: CFrame, maxStep: number, dt: number)
	local body = model.PrimaryPart

	if body == nil then
		return
	end

	local current = model:GetPivot()
	local offset = target.Position - current.Position
	local distance = offset.Magnitude
	local travel = math.min(distance, maxStep)
	local position = if distance > MOTION_EPSILON
		then current.Position + offset.Unit * travel
		else current.Position

	--[[
		FACING FOLLOWS TRAVEL IN THE HORIZONTAL PLANE ONLY, and a stationary rig keeps the facing it
		had. A vertical component would pitch the model, so a cat crossing a kerb tilts nose-down; and
		a rig that snapped to a default facing whenever it stopped would make STOPPING the tell, which
		is exactly what a hiding player does.

		THE STORED BASE IS ROTATION ONLY AND IS NEVER READ BACK OFF THE MODEL. See `facings`' header:
		reading it back re-applied the previous frame's sway as this frame's starting orientation, and
		the roll compounded until a still animal had rolled onto its side.
	]]
	local flat = Vector3.new(offset.X, 0, offset.Z)

	local stored: CFrame? = facings[index]

	if travel > MOTION_EPSILON and flat.Magnitude > MOTION_EPSILON then
		stored = CFrame.lookAt(Vector3.zero, flat.Unit)
	elseif stored == nil then
		-- First frame, never having moved: keep whatever the spawn gave it.
		stored = current - current.Position
	end

	local base = stored :: CFrame

	facings[index] = base

	elapsed[index] = (elapsed[index] or 0) + dt

	local t = elapsed[index] :: number
	local phase = AmbientMotion.phaseFor(index)
	local speed = AmbientMotion.speedFrom(travel, dt)

	--[[
		COMPOSED FROM SCRATCH EVERY FRAME: world position (plus the bob, which is vertical in WORLD
		space rather than in the rig's own, so a turning animal does not bounce sideways), then the
		base facing, then the sway.

		`Config.Ambient` IS PASSED WHERE AN `AmbientMotion.Tuning` IS EXPECTED. It satisfies the type
		structurally because it carries all six fields, which is why the tuning is a table rather than
		six arguments. Adding a field to `Config.Ambient` stays safe; RENAMING one of the six is an
		analyze error here, which is the point.
	]]
	--[[
		A RIGGED FORM ANIMATES ITS LEGS AND KEEPS ITS BODY LEVEL. Everything else bobs and sways.

		THE BOB IS A BODY-MOTION APPROXIMATION and it is only right for a rigid one. On a cat it reads
		as a gait; on a five-stud human mesh it read as "bouncing instead of walking", which is what was
		reported. A rig has joints, so it can be given an actual stride — and once it has one, adding a
		vertical sine ON TOP of it is a second, contradictory gait.

		THE BRANCH IS ON THE FORM, NEVER ON `slot.Claimed`, and that is the whole parity argument. Every
		villager is rigged and every cat is not, so this chooses the same path for a free rig and a
		claimed one at the same speed. A branch that read the claim state here — even to do something
		harmless — would make the disguised entity the one that moves differently, which is the leak
		`.claude/lessons/absence-is-observable.md` describes and which no check in this repo can see.
	]]
	local stride = strides[index]

	if stride ~= nil then
		--[[
			WEIGHT BLENDS THE TWO CLIPS AND RATE SCALES THE WALK. Both come from `AmbientMotion`, both
			read the SAME measured `speed` the bob would have, and neither is told what is driving the
			entity. A villager ambling at `WanderSpeed` and a puppeted one keeping pace with a sprinting
			monster differ in degree, continuously — which is §4.5's designed tell and not a mode switch.
		]]
		local walkWeight = AmbientMotion.strideWeight(speed, Config.Ambient)

		stride.Walk:AdjustWeight(
			math.max(walkWeight, STRIDE_WEIGHT_FLOOR),
			Config.Ambient.StrideBlendSeconds
		)
		stride.Idle:AdjustWeight(
			math.max(1 - walkWeight, STRIDE_WEIGHT_FLOOR),
			Config.Ambient.StrideBlendSeconds
		)
		stride.Walk:AdjustSpeed(AmbientMotion.strideRate(speed, Config.Ambient))

		-- No bob and no roll: the clip owns the vertical, and the rig stays upright.
		model:PivotTo(CFrame.new(position) * base)

		return
	end

	local bob = AmbientMotion.bobOffset(t, phase, speed, Config.Ambient)
	local sway = AmbientMotion.swayDegrees(t, phase, speed, Config.Ambient)

	model:PivotTo(
		CFrame.new(position + Vector3.new(0, bob, 0)) * base * CFrame.Angles(0, 0, math.rad(sway))
	)
end

--[[
	ONE SERVER LOOP FOR THE WHOLE POPULATION, not eighteen threads. Retarget every `WanderInterval`
	plus an idle, step at `WanderSpeed`, leashed to `WanderRadius` of the point the entity spawned at.

	IT DRIVES CLAIMED SLOTS TOO, AS OF PHASE 4. It used to skip them because `PuppetSlot` was writing
	their CFrame directly — two writers on one object, which is two motion behaviours, which is a free
	answer to "which cat is the monster". Now `PuppetSlot` only records a target and this loop is the
	single writer, so a claim changes the target and the step cap and nothing else.
]]
local function wanderTick(deltaTime: number)
	local now = os.clock()

	for index, model in models do
		local slot = roster[index]

		if model == nil or slot == nil then
			continue
		end

		--[[
			A CLAIMED SLOT IS NOT SKIPPED ANY MORE. It skips only the RETARGET — the monster decides
			where a claimed rig goes and `PuppetSlot` has already written it — and then falls through
			to the same `stepEntity` every free rig uses.

			THE CAP IS THE ONLY OTHER DIFFERENCE. A claimed rig may travel as far as it needs to keep
			up with a player; a free one is held to `WanderSpeed`. Two numbers, one code path.
		]]
		if slot.Claimed then
			local claimedTarget = targets[index]

			if claimedTarget ~= nil then
				stepEntity(index, model, claimedTarget, math.huge, deltaTime)
			end

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

			local flat = home
				* CFrame.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

			--[[
				THE TARGET IS SEATED ON ITS OWN GROUND, AND THIS IS THE THIRD SITE THAT DECIDES A
				RIG'S Y — the one that outlives the other two.

				`home` is the spawn pad's CFrame, whose centre is 0.4. Offsetting it by (dx, 0, dz)
				inherits that 0.4, so every free rig walked back to pad height within a Heartbeat of
				spawning, UNDOING `buildEntity`'s seating entirely. Measured in Studio: eighteen rigs,
				every centre at exactly 0.4 regardless of form height or of the ground beneath it, on
				a map whose ground under those pads ranges 0.0 to 2.0.

				ONE RAYCAST PER RETARGET, NOT PER FRAME. A retarget happens every
				`WanderInterval + IdleSeconds` per entity — about two casts a second across the whole
				population, against the eighteen-a-frame that `groundYUnder`'s header refuses.
			]]
			--[[
				THE THIRD SITE, and it now reads the same table the other two do. It used to take
				`PrimaryPart.Size.Y`, which is the root block on a rigged form rather than the body.

				IT REFUSES ON NIL RATHER THAN DEFAULTING, MATCHING `PuppetSlot`. This used to be
				`lifts[index] or 0`, and the disagreement was the bug: a nil lift would have seated a
				FREE rig at `groundY + 0` — buried by its own lift — while its CLAIMED twin froze in
				place, which is a static Y difference between two rigs of one form and exactly the leak
				`AmbientRig` exists to close. Two guards for one condition must answer the same way.

				Unreachable today: `buildEntity` writes `lifts[index]` on every exit path. Kept because
				"unreachable" is a property of today's call graph, not of the next one.
			]]
			local lift = lifts[index]

			if lift == nil then
				continue
			end

			target = CFrame.new(
				flat.Position.X,
				AmbientRig.restingYFromLift(groundYUnder(flat), lift),
				flat.Position.Z
			)
			targets[index] = target
			nextRetargetAt[index] = now + Config.Ambient.WanderInterval + Config.Ambient.IdleSeconds
		end

		if target == nil then
			continue
		end

		--[[
			NO EARLY EXIT WHEN THE RIG HAS ARRIVED, AND THAT IS THE PHASE 4 CHANGE. The old loop
			`continue`d once a rig was within one step of its target, which was harmless when a rig
			that had arrived simply stopped — and is a LEAK now that arriving means "stop breathing".
			A rig parked at its target for three idle seconds would freeze while its neighbours
			breathed, and a camouflaged monster standing still is exactly the case that must not stand
			out. `stepEntity` handles a zero-distance step: it keeps the facing and still animates.
		]]
		stepEntity(index, model, target, Config.Ambient.WanderSpeed * deltaTime, deltaTime)
	end
end

function AmbientService.Init()
	table.clear(roster)
	table.clear(models)
	table.clear(homes)
	table.clear(targets)
	table.clear(nextRetargetAt)
	table.clear(territories)
	table.clear(elapsed)
	table.clear(facings)
	table.clear(lifts)
	table.clear(strides)
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
	local byForm = spawnPointsByForm()

	if next(byForm) == nil then
		return
	end

	entities = Instance.new("Folder");
	(entities :: Folder).Name = ENTITIES_FOLDER;
	(entities :: Folder).Parent = workspace

	--[[
		SPAWN `PerForm` OF ONE FORM, FROM THAT FORM'S OWN POINTS.

		`placed` IS GONE AND SO IS THE SHARED RUNNING INDEX. Points used to be dealt sequentially from
		one pooled list, which is why a form could be sited anywhere; now each form walks its own
		partition and a pig can only ever start at a pig point.

		THE SLOT INDEX AND THE TERRITORY INDEX ARE THE SAME NUMBER, AND THIS LOOP IS WHERE THAT BECOMES
		TRUE. `AmbientTerritory.nearestFreeIndex` returns a point index that `ClaimSlot` uses as a slot
		index, so the two lists have to agree — and they cannot be built by walking
		`CollectionService:GetTagged`, which promises no order. They are appended together, here, in
		one loop, which makes the identity structural rather than a convention someone has to maintain.

		A FORM WITH NO POINTS IS SKIPPED WITH A WARNING RATHER THAN FILLED FROM ANOTHER FORM'S LIST.
		Borrowing would site pigs on a goat's stake, which is the territory rule made silently false;
		skipping leaves the form with no slots, so `ClaimSlot` refuses it and the Aswang simply never
		gets that disguise — visibly, and reported.

		THE PARAMETER IS THE NARROWING. `form` arrives as the literal union because each call site
		below passes a LITERAL checked against this annotation — which is narrowing the analyzer
		performs, unlike a cast or a nil-refinement carried across a nested loop. Both of those were
		tried here and neither survived; see this file's header and
		`.claude/lessons/pure-module-unions-widen-in-lists.md`.
	]]
	local function spawnForm(form: Types.CamouflageForm)
		local list = byForm[form]

		if list == nil or #list == 0 then
			warn(
				`[AmbientService] no {SPAWN_TAG} point carries Form="{form}" — that form gets no `
					.. `entities, so the Aswang can never wear it. Check the map's pads.`
			)
			return
		end

		for offset = 1, Config.Ambient.PerForm do
			-- Points are reused in order when the map supplies fewer than the population needs.
			local at = list[((offset - 1) % #list) + 1]
			local index = #roster + 1
			local model = buildEntity(form, index, at)

			model.Parent = entities

			roster[index] = { Form = form, Claimed = false }
			models[index] = model
			homes[index] = at
			territories[index] = { Form = form, X = at.Position.X, Z = at.Position.Z }
		end
	end

	--[[
		SIX CALLS RATHER THAN A LOOP OVER A LIST, and the order is the spawn order. A list would put
		the literals back inside a table and widen them again, which is the whole reason this is
		written out — and six is exactly the length at which someone will be tempted to "tidy" it
		into a loop. `.claude/lessons/pure-module-unions-widen-in-lists.md` is why that tidy does not
		typecheck, and the two shapes that fail are named in this file's header.
	]]
	spawnForm("CAT")
	spawnForm("DOG")
	spawnForm("PIG")
	spawnForm("GOAT")
	spawnForm("CHICKEN")
	spawnForm("VILLAGER")

	--[[
		UNIFORMITY BEATS FIDELITY — DEMOTE EVERY RIGGED FORM IF ANY ONE OF THEM FAILED.

		`loadStride` can fail per rig: three independent nil exits, called once per villager, so a
		transient asset failure is uncorrelated between them. The result was a barrio containing two
		villagers that walk and one that bobs with rigid legs — three "villagers" that are visibly
		three different objects.

		THAT IS NOT A ROLE LEAK, because it is fixed at boot and does not correlate with who is
		hiding. It breaks something this file's header asks for one line in: "so that no single one is
		conspicuous and a survivor who counts heads learns nothing." A memorable villager hands a
		survivor a free prior on the villager disguise.

		SO THE POPULATION AGREES OR NOBODY ANIMATES. Strictly worse-looking and strictly more uniform,
		which is this file's standing trade everywhere else it appears.
	]]
	local rigged, animated = 0, 0

	for index, slot in roster do
		if RIGGED[slot.Form] then
			rigged += 1

			if strides[index] ~= nil then
				animated += 1
			end
		end
	end

	if rigged > 0 and animated < rigged then
		warn(
			`[AmbientService] {animated}/{rigged} rigged entities loaded a stride, so ALL are demoted `
				.. `to the unanimated path. A population that animates unevenly makes one of them `
				.. `memorable, which is what the head-count argument in this file's header refuses.`
		)

		table.clear(strides)
	end

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
