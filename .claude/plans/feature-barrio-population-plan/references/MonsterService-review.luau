--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (3,270 lines)

	Excerpts only, from the camouflage path. This plan changes two call sites in this file and reads
	the rest to establish that the puppet contract holds.

	SUMMARY. The camouflage design is sound and the inversion it documents — hide the PLAYER, puppet the
	ENTITY — is what makes upgrading rigs upgrade the disguise for free. One pre-existing leak is
	recorded below that this plan does NOT fix and must not leave unrecorded.
]]

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/server/Services/MonsterService.luau:1041-1082 — enterCamouflage
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

local function enterCamouflage(player: Player, form: Types.CamouflageForm): boolean
	-- ...guards...
	local slotIndex = AmbientService.ClaimSlot(form)

	if slotIndex == nil then
		return false
	end

	monster.AmbientSlot = slotIndex
	monster.Camouflaged = true
	monster.CamouflageForm = form
	monster.HasCamouflageCharge =
		CamouflageRules.chargeAfter(monster.HasCamouflageCharge, "CAMOUFLAGE_ENTERED")

	hideCharacter(monster, character, humanoid)

	return true
end

-- Claims a slot, marks the state, hides the player's own body. No broadcast, deliberately.
--
-- NOTE: THIS IS THE CONTRACT THE WHOLE PLAN RESTS ON AND IT MUST STAY TRUE. There is no re-skin here —
-- the Aswang wearing a cat IS one of `AmbientService`'s rigs. So there is no second appearance path
-- that could drift from the first, which is exactly the kind of divergence that hands survivors a free
-- tell. Every phase of this plan preserves it; Phase 5's rig upgrade is valuable BECAUSE of it.
--
-- IMPORTANT: `ClaimSlot(form)` gains a position argument in Phase 3, so the claim can be refused
-- unless the monster stands inside a territory of that form. That is what makes the per-form territory
-- a real constraint rather than a signal, and it is also what bounds the visible jump on claim.
--
-- NOTE: the "no broadcast" argument is correct and worth keeping in mind for any later change. §4.3's
-- public half is that a player avatar is gone and an animal is standing there, and BOTH replicate as
-- geometry. A down-remote here would be the server stating what the world already shows.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/server/Services/MonsterService.luau:978-992 — hideCharacter
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

local function hideCharacter(state: MonsterState, character: Model, humanoid: Humanoid)
	local hidden: { HiddenPart } = {}

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(hidden, { Part = descendant, Transparency = descendant.Transparency })
			descendant.Transparency = 1
		end
	end

	state.CamouflageHiddenParts = hidden
	state.CamouflageNameDisplay = humanoid.DisplayDistanceType
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

-- Hides every part of the player's character and suppresses the name plate.
--
-- QUESTION — PRE-EXISTING, OUT OF SCOPE, AND IT MUST BE ASKED. Part `Transparency` is a replicated
-- property. The character is not reparented and not destroyed; it stays in `workspace` as a
-- player-named Model. So a client can walk `Players`, find the one character whose parts are ALL at
-- Transparency 1, and name the camouflaged Aswang without watching anything.
--
-- That is `.claude/lessons/absence-is-observable.md` in its own terms: "ask what is TRUE of one group
-- and FALSE of another, for every server-owned replicated property". `check:secrecy` cannot see it —
-- there is no role token in a Transparency value.
--
-- It is PRE-EXISTING from V07 and this plan does not touch it. It is recorded here and in Follow Ups
-- because a plan that edits the camouflage path and stays silent about it would read, later, as though
-- nobody looked. For `exploit-auditor` to confirm and for its own fix.
--
-- NOTE: `DisplayDistanceType = None` here is the mirror of what Phase 6's villager Humanoids need. A
-- rig that draws a name plate reading `Ambient_VILLAGER_2` would be the same bug from the other side.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/server/Services/MonsterService.luau:3245-3260 — the camouflage Heartbeat
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

	RunService.Heartbeat:Connect(function()
		for userId, monster in monsters do
			if not monster.Camouflaged then
				continue
			end

			local player = Players:GetPlayerByUserId(userId)
			local character = if player ~= nil then player.Character else nil
			local root = if character ~= nil then rootOf(character) else nil

			if root ~= nil then
				AmbientService.PuppetSlot(monster.AmbientSlot, root.CFrame)
			end
		end
	end)

-- IMPORTANT: `root.CFrame` UNMODIFIED is the source of the floating-rig leak. A HumanoidRootPart's
-- centre is roughly 3 studs above the character's feet; a free rig's centre sits at its pad's 0.4. The
-- disguised animal therefore floats ~2.6 studs above every real one of its form. Phase 2 passes a
-- MEASURED foot offset instead — measured, because the transform scales the avatar and the R15 default
-- is not the monster's.
--
-- QUESTION: `Humanoid.HipHeight`'s reference point is not verified anywhere in this codebase — nothing
-- in `src/` reads it. Centre-of-root versus underside-of-root differ by `root.Size.Y / 2` ≈ 1 stud,
-- which is small enough to pass for a modelling choice and large enough to be a tell. Step 2.6's
-- capture is the only thing that settles it. Do not infer it from documentation.
--
-- NOTE: the comment above this block is right that Heartbeat rather than the 0.25s feed cadence is the
-- correct rate, and right about why — "the cat that stutters" is the free tell the redesign avoids.
-- The same argument is why Phase 4's motion must be per-frame and shared between both paths.
