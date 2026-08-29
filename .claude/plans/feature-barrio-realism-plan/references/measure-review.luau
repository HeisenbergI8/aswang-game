--!strict
--[[
	REVIEW — tools/greybox/measure.luau (445 lines)

	The file that proves this plan's central claim: THE LAYOUT DID NOT MOVE. It walks the map with
	PathfindingService and reports crossing time, reachability and loops.

	It is ALSO STALE, in exactly the way barrio.luau is, and the brief did not flag it. That makes it
	the most important finding in this review.
]]

--------------------------------------------------------------------------------
-- src: tools/greybox/measure.luau:146-149  — THE STALE REACHABILITY SET
--------------------------------------------------------------------------------

local RANGES = {
	TaskPoint = 9, -- Config.Tasks.PresenceRangeStuds
	EscapeGate = 6, -- Config.Tasks.GateRangeStuds
}

-- The set of tags measure.luau walks to, and how close counts as "arrived".
-- IMPORTANT: after Step 2.2, `TaskPoint` returns only the Solo Trial's TWO points (both walled
-- into a corner) and `EscapeGate` returns ZERO. So this file would report a healthy crossing time over
-- almost nothing, and the loop test would seal corridors against an empty set.
-- IMPORTANT: THIS IS A FALSE GREEN, NOT A CRASH. It would print a number in the 30-40s band and look
-- exactly like a passing measurement. Every phase in this plan cites `measure.luau` as its proof that
-- the layout held; if it is not repaired in the SAME PHASE that breaks it, every subsequent phase's
-- crossing-time claim is worthless. That is why Step 2.6 exists and why it is not deferred.
-- QUESTION: confirm both replacement constants against Config before applying — I read
-- `Config.Search.ProximityStuds` as the search-start distance (V03) but did not read its literal value,
-- and `PickupRangeStuds` moved namespace in the v2.0 rename (`Salt.*` -> `Items.*`). A wrong value here
-- makes a reachable container read as unreachable; it does not affect the crossing time itself.

--------------------------------------------------------------------------------
-- src: tools/greybox/measure.luau:160-168  — WHY IT ITERATES TAGS, NOT CHILDREN
--------------------------------------------------------------------------------

for _, instance in CollectionService:GetTagged(tag) do
	-- The Solo Trial's two practice points carry the ordinary `TaskPoint` tag and live in a
	-- walled corner ...

-- NOTE: this was `anchors:GetChildren()` and was fixed in audit. Iterating the TAG rather than the
-- folder is what makes the file honest — it measures what the services will actually find.
-- IMPORTANT: this is the same reason the builder's receipt counts from CollectionService rather than
-- from its own tables. A typo'd tag agrees with the table and disagrees with the tag. Step 2.5's new
-- asserts follow the same principle and should not be "simplified" into table lookups.

--------------------------------------------------------------------------------
-- src: tools/greybox/measure.luau:123-138  — THE ESCAPE GATE WAS A SOLID PART
--------------------------------------------------------------------------------

--	This was `anchors:GetChildren()` and that was a real hole, found in audit: the `EscapeGate` is
--	... the `EscapeGate` is a SOLID part, so a path into the middle of it fails no matter where it

-- NOTE: the gate needed special handling because it COLLIDES — a path into its centre always fails.
-- Deleting it at Step 2.2 removes that special case entirely, which is a small simplification.
-- IMPORTANT: it is also a warning for this plan. Every `SearchContainer` prop added at Step 6.3 sits
-- ON an anchor pad that the path test walks to. If a container prop is ever built collidable, it
-- reproduces exactly this bug — an unreachable point that reads as a broken map. `prop()` prevents it;
-- do not bypass `prop()`.

--------------------------------------------------------------------------------
-- src: tools/greybox/measure.luau:348  — THE LOOP TEST'S STALE PROSE
--------------------------------------------------------------------------------

--	takes from it. A corridor that cut off a `SaltSpawn`, a `FetchSource` or the `EscapeGate` while

-- NOTE: the loop test seals each of seven corridors with a temporary wall and re-checks that every
-- tagged point is still reachable. Still-connected means that corridor was one of at least two ways
-- through — which is the actual property §5 asks for ("loops, never dead ends") and which walking an
-- alley cannot demonstrate.
-- IMPORTANT: fifteen SearchContainers spread across every zone make this test STRICTER than the twelve
-- clustered task points did. A corridor that passed before may now legitimately fail. THAT IS
-- INFORMATION, NOT A REGRESSION — it means an alley was a dead end for a zone the old anchor set never
-- probed. Do not "fix" it by moving a container. Read which corridor, and raise it.
-- NOTE: two of the three tag names in this comment become stale at Step 2.2 and must be reworded, or
-- `tests/barrio-legacy.test.luau` fails on the leftover `FetchSource` token — which is the guard
-- working correctly, not a false positive.

--------------------------------------------------------------------------------
-- OPERATIONAL NOTE, from tools/greybox/README.md:22-26
--------------------------------------------------------------------------------

-- 1. barrio.luau    in Edit mode. Destroys workspace.Barrio and rebuilds it.
-- 2. measure.luau   in Edit mode, after. Reports crossing time, reachability and loops.
-- 3. File -> Publish to Roblox.        <- neither script can do this, and it is the only backup

-- IMPORTANT: measure.luau reads the LIVE DataModel. A reading taken before re-running the builder
-- describes the PREVIOUS barrio and looks exactly like a passing one. Always run them in this order,
-- every time, in Edit mode. Step 4.4 and Step 8.3 both depend on this and both say so.
-- IMPORTANT: step 3 is not optional. Every generated mesh and MaterialVariant in this plan lives only
-- in the place file, which is gitignored. An unpublished session of this work is one crash from gone.
