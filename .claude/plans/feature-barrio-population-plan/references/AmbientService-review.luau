--!strict
--[[
	REVIEW — src/server/Services/AmbientService.luau (582 lines)

	Excerpts only. Every block below carries an annotation; open the real file for anything else.

	SUMMARY. This service is well-built and its header is unusually honest — it documents the V07
	Critical it was written to fix and names the lesson it was written against. Two defects survive it,
	and BOTH are arithmetic rather than architecture, which is why the header's careful reasoning did
	not catch them: the resting height of a rig, and the fact that free and claimed rigs are moved by
	two different functions.
]]

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/server/Services/AmbientService.luau:163-193 — FORM_LOOKS
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- The four forms, their bounding boxes and their generated mesh ids.
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
		VILLAGER = {
			Size = Vector3.new(2.0, 5.0, 1.2), -- config-ok: rig proportions, not balance
			Mesh = "rbxassetid://131254025115965", -- config-ok: generated mesh asset, not balance
		},
	}

-- IMPORTANT: this table is one of SEVEN places the six-form set has to be written down, and it is the
-- only one that is a table of KEYS rather than a literal union. Phase 1's suite checks all seven,
-- because a form present here and missing from `Start`'s spawn list has a look and no entities —
-- `ClaimSlot` refuses it forever and nothing reports it.
--
-- IMPORTANT: these mesh ids are the ONLY record of four generated meshes, and they are recorded with
-- no triangle count. `tests/barrio-assets.test.luau` sums `ASSETS.Meshes` in the builder against a
-- 27,000 ceiling and has never known these exist — so four meshes at sixteen instances are spent
-- against §5's non-negotiable mobile budget and counted by nothing. Phase 5 registers them.
--
-- NOTE: the `-- config-ok:` waivers are load-bearing. `check:config` flags every literal in a service
-- and cannot tell a mesh id from a balance number. Two new rows means eight new waivers.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/server/Services/AmbientService.luau:203-233 — spawnPoints
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

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
	-- ...ring fallback...
end

-- Reads tagged parts, falls back to a ring at the origin when there are none.
--
-- IMPORTANT: `tagged.CFrame` is the PAD's CFrame, and `anchor()` in the builder puts a pad's CENTRE at
-- y = 0.4 (`barrio.luau:653-688`; `v()` at :277 does not scale Y). `buildEntity` assigns that straight
-- onto the body, so every rig's centre sits at 0.4 and every rig is buried by half its own height —
-- 0.2 studs for a cat, 2.1 for a villager. Phase 2 fixes it with a raycast and a pure function.
--
-- IMPORTANT: `* 4` is a hand-written form count in the FALLBACK path, which is the path nothing
-- exercises until the map is missing. At six forms it silently sizes the ring wrong.
--
-- NOTE: the fallback fires only on ZERO tagged parts, never on "fewer than we wanted". That asymmetry
-- is deliberate and correct — a partial list stays visibly wrong in Studio instead of being replaced.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/server/Services/AmbientService.luau:330-343 — PuppetSlot, and :444-490 — wanderTick
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

function AmbientService.PuppetSlot(slotIndex: number?, cframe: CFrame)
	-- ...guards...
	model:PivotTo(cframe)
end

local function wanderTick(deltaTime: number)
	for index, model in models do
		local slot = roster[index]

		if model == nil or slot == nil or slot.Claimed then
			continue
		end
		-- ...retarget, step at WanderSpeed, PivotTo...
	end
end

-- IMPORTANT: THESE ARE THE TWO FUNCTIONS THE WHOLE SECRECY ARGUMENT TURNS ON. `wanderTick` moves free
-- rigs and skips claimed ones; `PuppetSlot` moves claimed ones. Two code paths over one visible object
-- class, in the same file, and every behavioural difference between them is client-readable.
--
-- IMPORTANT: `PivotTo(cframe)` takes the monster's HumanoidRootPart CFrame unmodified
-- (`MonsterService.luau:3256`). A root centre is ~3 studs above its own feet, so the claimed rig's
-- centre is at ~3 while every free rig's is at 0.4. THE DISGUISED ANIMAL FLOATS, statically, readable
-- in one frame with no motion required. This is not the "which cat is behaving oddly" tell §4.5
-- designed — it is a free answer. Phases 2 and 4.
--
-- QUESTION: on claim, the rig is driven from its spawn point to wherever the monster stands — possibly
-- 200 studs, in one frame. Today that reads as "a pig appeared". Under per-form territories it reads
-- as an answer, because a pig on the road is categorically wrong. Phase 3 bounds it to `ClaimRadius`.
--
-- NOTE: the comment above `wanderTick` correctly explains why a claimed slot must be skipped — two
-- writers on one CFrame would judder. That reasoning is right and the fix is not to un-skip it but to
-- give both paths ONE step function whose target differs.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/server/Services/AmbientService.luau:46-49 — the header's Humanoid refusal
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

--	NO HUMANOID, NO PATHFINDING, NO PHYSICS. Each entity is a small anchored Model that the server
--	steps toward a target CFrame. §5 asked for a wander and an idle; a Humanoid per entity is 16
--	Humanoids on a phone, and `PathfindingService`'s cost at this population is a Roblox behaviour
--	this plan has NOT verified — recorded in Follow Ups rather than assumed.

-- IMPORTANT: Phase 6 adds three Humanoids and must REWRITE this paragraph rather than leave the file
-- contradicting its own header. The reason it becomes acceptable is narrow and must be stated: the
-- state machine is disabled and physics never runs, which is a different thing from what this
-- paragraph refused. A header describing a rule the file below it breaks is worse than no header.
