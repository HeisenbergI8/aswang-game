--!strict
--[[
	REVIEW — src/server/Services/AmbientService.luau

	Read to answer the brief's question: are the cats/dogs/pigs/villagers map-authored or
	service-spawned? NOT changed by this plan.

	ANSWER: SERVICE-SPAWNED AT RUNTIME. The map's only job is to say WHERE, and today it does not.
]]

--------------------------------------------------------------------------------
-- src/server/Services/AmbientService.luau:118-119 and :169-186
--------------------------------------------------------------------------------

local SPAWN_TAG = "AmbientSpawn"
local ENTITIES_FOLDER = "AmbientLife"

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

	-- ... a ring at the origin ...

-- IMPORTANT: `tools/greybox/barrio.luau` EMITS ZERO `AmbientSpawn` PARTS. Confirmed by grepping every
-- AddTag call in the builder. So the fallback below is what is running in the game RIGHT NOW: sixteen
-- ambient entities in a circle at the origin, through the middle of the spawn plaza.
-- IMPORTANT: this is why `workspace.AmbientLife` holds 16 single-part models in the live datamodel —
-- they were created by this service at Start, not by the builder. No visual treatment of them belongs
-- in a builder plan. Step 2.4 adds the sixteen spawn points; the RIGS stay this service's business.

--	THE FALLBACK MUST NOT SILENTLY REPLACE A REAL MAP. It fires only on ZERO tagged parts, never on
--	"fewer than we wanted" — a map with three markers and a Config asking for sixteen gets three
--	spawn points reused, which is visibly wrong in Studio and therefore fixable.

-- NOTE: excellent failure design, and it has a consequence for Step 2.4: adding even ONE AmbientSpawn
-- changes the behaviour away from the ring. So the step must add all sixteen in one go, or the barrio
-- ends up with a handful of reused points, which is worse than the ring and less obviously wrong.

--------------------------------------------------------------------------------
-- src/server/Services/AmbientService.luau:145-165  — THE PLACEHOLDER RIGS
--------------------------------------------------------------------------------

local FORM_LOOKS: { [Types.CamouflageForm]: { Size: Vector3, Colour: Color3 } } = {
	CAT = { Size = Vector3.new(1.4, 1.2, 2.6), Colour = Color3.fromRGB(64, 60, 58) },
	DOG = { Size = Vector3.new(1.8, 1.9, 3.2), Colour = Color3.fromRGB(122, 94, 62) },
	PIG = { Size = Vector3.new(2.0, 1.8, 3.4), Colour = Color3.fromRGB(198, 148, 148) },
	VILLAGER = { Size = Vector3.new(2.0, 5.0, 1.2), Colour = Color3.fromRGB(96, 108, 128) },
}

-- Four coloured blocks, sized so the forms are distinguishable at distance.
-- IMPORTANT: THIS IS THE LARGEST REALISM GAP THIS PLAN LEAVES OPEN, and it is out of scope by
-- construction. `FORM_LOOKS` is game code under `src/`, inside all five repo checks; the builder is
-- not. In a hyper-realistic barrio, sixteen coloured blocks wandering past a photoreal chapel will be
-- the most obviously unfinished thing in the map. Raised in the plan's Follow Ups as needing its own
-- small plan — four of the eight hero meshes could have gone here instead.
-- NOTE: the comment's design rule is the constraint any future mesh must satisfy — §4.5's deduction is
-- "which cat", never "is that a cat". So four UNMISTAKABLE silhouettes matter more than four good
-- models, which is a cheap requirement to hit.

--	NO LIGHT AND NO PARTICLE EMITTER, deliberately: §5's mobile budget is about exactly those two and
--	`PerformanceController` enforces the light cap. Sixteen anchored parts spend neither.

-- IMPORTANT: any future ambient-life mesh work inherits this rule. Sixteen entities is the one place
-- in the game where a per-entity light or emitter would be multiplied by sixteen.

--------------------------------------------------------------------------------
-- SECRECY — src/server/Services/AmbientService.luau:17-36 and :242
--------------------------------------------------------------------------------

--	CLIENT — and `workspace.AmbientLife.ChildRemoved` then hands any listener the exact position the
--	`#workspace.AmbientLife:GetChildren()` dropping below the spawned count is also a bare "someone is

-- IMPORTANT and directly relevant to Step 2.4. The COUNT of AmbientLife children is itself a signal:
-- if an entity is ever removed, a client watching `ChildRemoved` learns something. The service is
-- built so the entity "stays in workspace.AmbientLife exactly where it was" when claimed.
-- IMPORTANT: the consequence for the MAP is that sixteen spawn points must not be distinguishable
-- from each other in any way a client could correlate with a form. Step 2.4's sixteen anchors are
-- IDENTICAL pads with sequential names (`AmbientSpawn_1`..`_16`) and NO per-form attribute. Do not
-- "helpfully" tag them `AmbientSpawn_CAT` etc. — that would publish which spawn holds which form, and
-- combined with the camouflage rules it narrows who a given animal might be.
-- NOTE: `check:secrecy` is `src/`-scoped and would NOT catch that mistake in the builder. This is the
-- one place in the whole plan where a map-side change could genuinely leak, and it leaks past the
-- automated guard. It is why Step 2.4's diff names the anchors numerically.

--	NONE OF THIS IS KEYED BY PLAYER. There is no UserId anywhere in this file, which is why no
--	arrangement of it can distinguish one client's view from another's.

-- NOTE: the standard this plan holds itself to as well. Nothing added to the builder is keyed by
-- player, because the builder runs once in Edit mode before any player exists.
