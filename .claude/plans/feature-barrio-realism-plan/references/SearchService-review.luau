--!strict
--[[
	REVIEW — src/server/Services/SearchService.luau

	Read to establish what the map must provide for v2.0 searching. NOT changed by this plan.
	This is the service that proves the map is currently broken.
]]

--------------------------------------------------------------------------------
-- src/server/Services/SearchService.luau:57 and :127-134
--------------------------------------------------------------------------------

local TAG_CONTAINER = "SearchContainer"

for _, instance in CollectionService:GetTagged(TAG_CONTAINER) do
	if not instance:IsA("BasePart") then
		warn(`[SearchService] {instance:GetFullName()} is tagged {TAG_CONTAINER} but is a `
			.. `{instance.ClassName}, not a BasePart — skipped.`)
		continue
	end

-- How the service finds containers: by tag, on BaseParts only.
-- IMPORTANT: `tools/greybox/barrio.luau` EMITS ZERO `SearchContainer` PARTS. I grepped every AddTag in
-- the builder to confirm. Searching is the entire v2.0 game loop (§4.4) and the map provides nothing
-- to search. This is a live bug, not merely an art gap, and Step 2.3 is the highest-value step in the
-- whole plan because of it.
-- NOTE: BasePart only — an anchor pad qualifies, a Model or Folder does not. Step 6.3 must therefore
-- keep the TAGGED part a BasePart and hang the visual prop off it, not replace it with a Model.

--------------------------------------------------------------------------------
-- src/server/Services/SearchService.luau:136-158
--------------------------------------------------------------------------------

	local existing: BasePart? = containersByName[instance.Name]

	if existing == nil then
		containersByName[instance.Name] = instance
	end

-- Keyed by NAME, and a duplicate name is silently the same container.
-- IMPORTANT: fifteen UNIQUE names is a hard requirement, not a style preference. Two parts both named
-- `Container_Kubo` are ONE container and a silently short pool. `tests/barrio-contract.test.luau`
-- asserts uniqueness for exactly this reason.

	table.sort(names)

-- NOTE: sorted before drawing, and the comment calls this "security rather than tidiness" —
-- `GetTagged`'s order is engine-defined and differs between servers, which would make the layout
-- irreproducible and make "same entropy, same layout" false. `ItemService` sorts for the same reason.
-- This plan changes nothing here; it is recorded so nobody "optimises" the sort away later.

--------------------------------------------------------------------------------
-- src/server/Services/SearchService.luau:113-120 and :158
--------------------------------------------------------------------------------

function SearchService.TotalItems(): number
	return Config.Items.SaltSpawnCount
		+ Config.Items.GarlicSpawnCount
		+ Config.Items.BuntotPagiSpawnCount
end

return SearchPool.evaluate(names, SearchService.TotalItems(), Config.Search.ContainerCount)

-- The pool requirement is SUMMED FROM CONFIG rather than typed.
-- NOTE: the comment says this is so "a V16 tune of any *SpawnCount* moves the pool requirement with it
-- and `check:config` has no literal to flag". Good pattern — and it means the container count is not
-- free to choose: it must exceed the total items placed, or items cannot be distributed.
-- IMPORTANT: `Config.Search.ContainerCount = 15` (Config.luau:534), which matches §5's "~15 searchable
-- containers" exactly. Step 2.3 builds fifteen and Step 2.5 asserts fifteen in the builder.
-- IMPORTANT: the builder CANNOT require Config — it runs through `loadstring` in Studio with no
-- `script` and no ReplicatedStorage path at build time. So the 15 is duplicated by hand in the
-- builder's assert, and `tests/barrio-contract.test.luau` reads BOTH files and fails when they
-- disagree. That test is the only thing preventing silent drift between them.

--------------------------------------------------------------------------------
-- src/server/Services/SearchService.luau:159-175  — WHY AN EMPTY POOL IS INVISIBLE
--------------------------------------------------------------------------------

--	THE LOUD HALF, ungated by VerboseLogging, on this repo's rule that routine tracing is gated and
--	faults warn unconditionally. A barrio with no containers in it is a fault whose only
--	player-visible symptom is that there is nothing to do and nobody knows why.

-- IMPORTANT: this comment describes the CURRENT state of the game exactly. The service is presumably
-- warning on every round start right now, into a console nobody reads during a build session.
-- NOTE: "not one of these lines names a content" — the reporting is counts and verdicts only, because
-- naming which container holds the buntot pagi would be a leak. Nothing in this plan changes the
-- reporting, and nothing in it should: a container's CONTENTS are secret, its POSITION is not.

--------------------------------------------------------------------------------
-- SECRECY NOTE — src/server/Services/SearchService.luau:100-106
--------------------------------------------------------------------------------

local layout: ContainerLayout.Layout? = nil
local opened: { [number]: boolean } = {}

-- THE SECRET. Server-only: which containers are still worth walking to.
-- IMPORTANT for this plan: the container LAYOUT is secret, the container GEOMETRY is not. Building
-- fifteen visually obvious containers leaks nothing — every client can already see every part of the
-- map. What must never happen is a container that LOOKS different depending on what is inside it:
-- a distinct model for the buntot pagi container, a glow on a full one, a different material on an
-- opened one. All of those are derived hints readable by any client.
-- IMPORTANT: Step 6.3's "three shapes, reused" is therefore a SECRECY constraint as well as a
-- readability one. The three shapes must be assigned by POSITION (a rice sack in the field, a crate at
-- the stall), never by contents, and never re-skinned at runtime.
