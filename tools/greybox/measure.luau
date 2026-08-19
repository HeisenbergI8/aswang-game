--[[
	MEASURE — does the barrio actually meet §5, or does it only look like it does?

	Run after `barrio.luau`, in the same way (Studio command bar, or MCP `execute_luau`). It changes
	nothing permanent: the only instances it creates are temporary blockers, and it destroys them.

	═══ WHY THIS IS A SCRIPT AND NOT A STOPWATCH ═════════════════════════════════

	The build plan says "measure it — walk it with a stopwatch", and a stopwatch answers the question
	for ONE route that ONE person happened to pick. The two properties §5 actually asks for are both
	statements about every route:

	  1. ~35 seconds to cross end to end
	  2. "2–3 narrow alleys forming LOOPS, NEVER DEAD ENDS. Walk every alley and confirm you can run
	     a circle."

	A stopwatch cannot prove the second one at all. Walking an alley and coming out the far end shows
	the alley connects two streets; it does not show there is a SECOND way round, which is the whole
	property — a dead end is not a corridor that stops, it is a corridor whose only exit is its
	entrance. §5's reason is that dead ends are unfair and loops create chases, and unfairness is
	exactly the thing a designer walking their own map will not notice.

	So this file proves it the only way it can be proven: BLOCK EACH CORRIDOR IN TURN AND CHECK THE
	MAP IS STILL FULLY CONNECTED. If every task point is still reachable from spawn with a corridor
	sealed, that corridor is on a loop rather than being the sole way through. Seven corridors, one
	temporary wall at a time.

	═══ THE THREE MEASUREMENTS ═══════════════════════════════════════════════════

	  · CROSSING   the longest walked path between the map's extremities, in seconds at WalkSpeed 16.
	               Walked, not straight-line: buildings make the walk longer than the diagonal, and it
	               is the walk a player experiences. Target 30–40s
	  · REACH      every tagged anchor is reachable from the spawn. An unreachable task point is a
	               round that cannot be finished and whose only symptom is a stuck progress bar
	  · LOOPS      no single corridor is a cut edge

	PathfindingService is the right instrument for all three because it walks the same navmesh the
	player does — it goes around buildings, it refuses to climb walls, and it fails honestly when
	there is no route. `AgentCanJump = false` on purpose: a route that only exists if you jump a wall
	is not a route the map is offering.
]]

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

local WALK_SPEED = 16 -- Roblox default, and what MonsterService captures as BaseWalkSpeed
local root = workspace:FindFirstChild("Barrio")

assert(root, "no workspace.Barrio — run tools/greybox/barrio.luau first")

-- Asserted, not bound: nothing here reads the folder any more — the checks below go through
-- CollectionService, for the reason `tagged()` gives. Its absence still means the generator did not
-- finish, and failing here says so more clearly than an empty result set would.
assert(root:FindFirstChild("Anchors"), "workspace.Barrio.Anchors is missing")

local AGENT = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = false,
}

--[[
	THE SCALE IS READ OFF THE MAP, NOT COPIED FROM `barrio.luau`.

	Every coordinate in this file is written in the layout's own scale-1 units, exactly as the generator
	authors them, so the two files stay readable side by side. That leaves one number to reconcile, and
	a `local SCALE = 1.35` here would be a second copy of a constant that lives somewhere else — the
	kind that stays right for one edit and then silently measures the wrong places forever.

	`Wall_E` sits at x = HALF by construction, so dividing its position by HALF recovers whatever scale
	the barrio was actually built at. A measurement that reads its own subject cannot drift from it.
]]
local HALF = 180
local perimeter = root:FindFirstChild("Perimeter")

assert(perimeter, "workspace.Barrio.Perimeter is missing — cannot recover the scale")

local eastWall = perimeter:FindFirstChild("Wall_E") :: BasePart?

assert(eastWall, "workspace.Barrio.Perimeter.Wall_E is missing — cannot recover the scale")

local SCALE = eastWall.Position.X / HALF

local function at(x: number, y: number, z: number): Vector3
	return Vector3.new(x * SCALE, y, z * SCALE)
end

--[[
	Path length as the SUM OF WAYPOINT DISTANCES, not as the straight line between the endpoints.

	That difference is the entire point of measuring rather than estimating. A straight line from the
	chapel to the rice field says the map is small; the walk goes round four buildings and says
	something else. Returns nil when no route exists, which the loop test reads as a cut edge.
]]
local function walkLength(from: Vector3, to: Vector3): number?
	local path = PathfindingService:CreatePath(AGENT)
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end

	local waypoints = path:GetWaypoints()

	if #waypoints < 2 then
		return nil
	end

	local total = 0

	for index = 2, #waypoints do
		total += (waypoints[index].Position - waypoints[index - 1].Position).Magnitude
	end

	return total
end

--[[
	EVERYTHING THE SERVICES WILL LOOK FOR, GATHERED THE WAY THEY GATHER IT.

	This was `anchors:GetChildren()` and that was a real hole, found in audit: the `EscapeGate` is
	parented under `Arko`, not under `Anchors`, so it was in neither the reachability check nor the
	loop check. A corridor that sealed off the gate — the one part survivors must reach to win — would
	have printed `ok` on every line.

	Reading CollectionService instead of a folder closes it permanently, and for the same reason the
	generator prints its receipt from tags rather than from its own tables: the folder is where I put
	things, the tag is what the server actually finds. Only the second one can contradict me.
]]
--[[
	THE RANGE EACH TAG IS ACTUALLY GOVERNED BY, because "reachable" is a claim about the SERVER'S rule,
	not about the geometry.

	A first version of this check pathed straight to each tagged part's centre, and that is wrong in
	both directions. The pads are non-collidable so a path to their centre succeeds and tells you
	little; the `EscapeGate` is a SOLID part, so a path into the middle of it fails no matter where it
	sits — it reported the gate unreachable on a map where walking up to it works fine.

	What the services ask is whether the player's HumanoidRootPart is within a range of the part's
	position. So that is what gets tested: is there a spot a character can WALK TO, from which the
	server's own distance check would pass. Nothing else is a reachability claim about this game.
]]
local RANGE_BY_TAG: { [string]: number } = {
	TaskPoint = 9, -- Config.Tasks.PresenceRangeStuds
	FetchSource = 9, -- picked up by the same presence rule
	SaltSpawn = 6, -- Config.Salt.PickupRangeStuds
	EscapeGate = 6, -- Config.Tasks.GateRangeStuds
}

-- Where a character's HumanoidRootPart sits above the floor. Every range check in the game is a 3D
-- distance from it, which is exactly how the gate's height came to matter.
local ROOT_HEIGHT = 3

local function tagged(): { { Part: BasePart, Range: number } }
	local found: { { Part: BasePart, Range: number } } = {}

	for tag, range in RANGE_BY_TAG do
		for _, instance in CollectionService:GetTagged(tag) do
			--[[
				`TrialOnly` IS SKIPPED HERE FOR THE SAME REASON `TaskService.discoverPool` SKIPS IT,
				and leaving it out made this script cry wolf on every run since C21.

				The Solo Trial's two practice points carry the ordinary `TaskPoint` tag and live in a
				sealed corner at (-300, 300) that is reachable ONLY by being teleported into it —
				`barrio.luau` says so at length, and it is deliberate: a player who can walk into the
				tutorial mid-round finds objectives that do not count.

				So they are unreachable BY DESIGN, and every check in this file that asks "can a
				character walk here" was correctly answering "no" and reporting it as a map defect.
				That was 1 reach failure and 7 loop failures — every corridor test "cut off" the two
				trial points, because sealing any corridor anywhere cannot connect what was never
				connected. Eight red lines that meant nothing, on a report whose whole value is that
				a red line means something.
			]]
			if instance:GetAttribute("TrialOnly") == true then
				continue
			end

			if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
				table.insert(found, { Part = instance, Range = range })
			end
		end
	end

	return found
end

--[[
	Can a character walk to somewhere the server would accept?

	Tries the part's own position first — right for the flat non-collidable pads — then a ring of
	standing spots around it, keeping only those that both pass the server's distance test AND can
	actually be walked to. A solid part like the gate is only ever reached this second way.
]]
local function reachableFrom(from: Vector3, entry: { Part: BasePart, Range: number }): boolean
	local target = entry.Part.Position

	if walkLength(from, target) ~= nil then
		return true
	end

	--[[
		SAMPLE THE ADMISSIBLE REGION, DO NOT GUESS A RADIUS.

		A ring at `max(Size.X, Size.Z) / 2 + 2` was tried and was wrong for exactly the part this
		function exists to handle. The gate is a thin slab 27.9 studs wide and 2.3 deep: half its
		widest dimension is 14, so every candidate landed 16+ studs out and failed the range test
		before walkability was ever considered — while the spot a player actually uses, three studs
		in front of its face, was never sampled at all.

		So the candidates are the region the SERVER would accept — every ground spot whose 3D distance
		to the part's centre is inside `Range` — walked nearest-first and returning on the first one
		that can be reached. Nearest-first matters: it finds the spot in front of the gate in a handful
		of path computations instead of exhausting the grid.
	]]
	local candidates: { Vector3 } = {}
	local vertical = ROOT_HEIGHT - target.Y

	for dx = -entry.Range, entry.Range, 1.5 do
		for dz = -entry.Range, entry.Range, 1.5 do
			if dx * dx + dz * dz + vertical * vertical <= entry.Range * entry.Range then
				table.insert(candidates, Vector3.new(target.X + dx, ROOT_HEIGHT, target.Z + dz))
			end
		end
	end

	table.sort(candidates, function(a: Vector3, b: Vector3): boolean
		return (a - target).Magnitude < (b - target).Magnitude
	end)

	for _, spot in candidates do
		if walkLength(from, spot) ~= nil then
			return true
		end
	end

	return false
end

local lines: { string } = {}

local function report(line: string)
	table.insert(lines, line)
end

--------------------------------------------------------------------------------
-- 1. CROSSING TIME
--
-- Six extremities rather than one diagonal, because "end to end" has no single
-- meaning on a square map and the honest number is the WORST of them — that is
-- the walk a player complains about.
--------------------------------------------------------------------------------

local EXTREMES = {
	{ Name = "chapel", At = at(0, 2, -158) },
	{ Name = "riceSE", At = at(150, 2, 160) },
	{ Name = "riceSW", At = at(35, 2, 158) },
	{ Name = "well", At = at(-70, 2, 40) },
	{ Name = "kuboNE", At = at(78, 2, -78) },
	{ Name = "ringSW", At = at(-130, 2, 130) },
}

local worstSeconds = 0
local worstPair = "none"

for i = 1, #EXTREMES do
	for j = i + 1, #EXTREMES do
		local length = walkLength(EXTREMES[i].At, EXTREMES[j].At)

		if length then
			local seconds = length / WALK_SPEED

			if seconds > worstSeconds then
				worstSeconds = seconds
				worstPair = `{EXTREMES[i].Name} -> {EXTREMES[j].Name}`
			end
		else
			report(`  CROSSING  UNREACHABLE {EXTREMES[i].Name} -> {EXTREMES[j].Name}`)
		end
	end
end

local crossingOk = worstSeconds >= 30 and worstSeconds <= 40

report(
	`  {if crossingOk then "ok  " else "FAIL"}  crossing: {string.format("%.1f", worstSeconds)}s `
		.. `worst ({worstPair}) — §5 target 30-40s at WalkSpeed {WALK_SPEED}`
)

--------------------------------------------------------------------------------
-- 2. REACHABILITY from the plaza spawn
--------------------------------------------------------------------------------

local spawnPad = workspace:FindFirstChildWhichIsA("SpawnLocation")

assert(spawnPad, "no SpawnLocation in workspace — every distance here is measured from it")

local spawnAt = spawnPad.Position
local targets = tagged()
local unreachable: { string } = {}

for _, entry in targets do
	if not reachableFrom(spawnAt, entry) then
		table.insert(unreachable, entry.Part.Name)
	end
end

report(
	`  {if #unreachable == 0 then "ok  " else "FAIL"}  reach: {#targets - #unreachable}`
		.. `/{#targets} tagged parts have a walkable spot inside their own range`
		.. `{if #unreachable > 0 then ` — {table.concat(unreachable, ", ")}` else ""}`
)

--------------------------------------------------------------------------------
-- 3. LOOPS — the cut-edge test described in the header.
--
-- Each corridor is sealed with a temporary wall, then every task point is
-- re-checked from spawn. Still connected means the corridor was one of at least
-- two ways round; disconnected means it was the only way, which is a dead end
-- wearing a corridor's clothes.
--------------------------------------------------------------------------------

--[[
	Each blocker is placed on the PLAZA SIDE of its corridor, not at its midpoint.

	That is the stronger cut: sealing a radial right where it leaves the plaza severs the plaza from
	everything the radial serves, so the only surviving route is out via a different radial and back
	round the ring. A midpoint blocker on Road_N would still leave the plaza→alley stub connected and
	would pass on a map where the ring did not exist at all.
]]
local CORRIDORS = {
	{ Name = "Alley_NE", At = at(65, 6, -100), Size = at(2, 12, 14) },
	{ Name = "Alley_SW", At = at(-100, 6, 65), Size = at(14, 12, 2) },
	{ Name = "Alley_SE", At = at(65, 6, 100), Size = at(2, 12, 14) },
	{ Name = "Road_N", At = at(0, 6, -60), Size = at(26, 12, 2) },
	{ Name = "Road_S", At = at(0, 6, 60), Size = at(26, 12, 2) },
	{ Name = "Road_E", At = at(60, 6, 0), Size = at(2, 12, 26) },
	{ Name = "Road_W", At = at(-60, 6, 0), Size = at(2, 12, 26) },
}

--[[
	THE LOOP TEST CHECKS EVERY TAGGED PART, NOT ONLY THE TASK POINTS.

	It used to filter to names beginning `Task_`, which made the printed line — "leaves every task point
	reachable" — literally true and quietly narrower than what a reader skimming for "no dead ends"
	takes from it. A corridor that cut off a `SaltSpawn`, a `FetchSource` or the `EscapeGate` while
	leaving all twelve task points connected still printed `ok`.

	Each of those is a way to lose the round: no salt in reach is §4.6's counterplay missing, an
	unreachable source demotes a FETCH task, and an unreachable gate means survivors cannot win at all.
	They belong in the same check as the task points, and the wording now says what is actually tested.
]]
for _, corridor in CORRIDORS do
	local blocker = Instance.new("Part")

	blocker.Name = `Blocker_{corridor.Name}`
	blocker.Anchored = true
	blocker.Size = corridor.Size
	blocker.Position = corridor.At
	blocker.Transparency = 0.5
	blocker.Parent = workspace

	-- The navmesh is rebuilt asynchronously after a collidable part appears. Without this the first
	-- path is computed against the OLD mesh and every corridor passes, which is the failure mode where
	-- a test reports what you hoped rather than what is true.
	--
	-- 0.4 is empirical and it is the weakest assumption in this file. It held on the machine this was
	-- written on; a slower or busier one could return a stale path and PASS a corridor that is a real
	-- cut edge. If a run ever reports all seven ok on a map you have visibly broken, raise this first.
	task.wait(0.4)

	local cut: { string } = {}

	for _, entry in targets do
		if not reachableFrom(spawnAt, entry) then
			table.insert(cut, entry.Part.Name)
		end
	end

	blocker:Destroy()
	task.wait(0.2)

	report(
		`  {if #cut == 0 then "ok  " else "FAIL"}  loop: sealing {corridor.Name} `
			.. `{if #cut == 0
				then `leaves all {#targets} tagged parts reachable`
				else `CUTS OFF {table.concat(cut, ", ")}`}`
	)
end

--------------------------------------------------------------------------------
-- 4. LIGHT DENSITY — §5's mobile budget, which had no mechanical check at all.
--
-- "Cap dynamic lights to ~8 visible at once" was asserted in a comment in the
-- generator and measured by nothing. This does not compute true visibility —
-- that needs occlusion, and a part-level occlusion test is its own project — but
-- it does compute the thing the FPS cost actually tracks: how many PointLights
-- have a given point inside their Range. A light you are standing inside is a
-- light being rendered, whatever is between you and it.
--
-- Sampled on a grid rather than at hand-picked spots, because the interesting
-- number is the WORST place a player can stand, and hand-picked spots are the
-- ones the author already knows are fine.
--------------------------------------------------------------------------------

local lightBudget = 8
local lightsInRange = 0
local worstAt = Vector3.zero
local samples = 0

for gx = -170, 170, 20 do
	for gz = -170, 170, 20 do
		local point = at(gx, 3, gz)
		local overlapping = 0

		samples += 1

		for _, descendant in root:GetDescendants() do
			if descendant:IsA("PointLight") then
				local source = descendant.Parent :: BasePart

				if (source.Position - point).Magnitude <= descendant.Range then
					overlapping += 1
				end
			end
		end

		if overlapping > lightsInRange then
			lightsInRange = overlapping
			worstAt = point
		end
	end
end

report(
	`  {if lightsInRange <= lightBudget then "ok  " else "FAIL"}  lights: {lightsInRange} `
		.. `overlapping at worst of {samples} sampled points ({math.round(worstAt.X)}, {math.round(
			worstAt.Z
		)}) `
		.. `— §5 mobile cap ~{lightBudget}`
)

print(`[measure] barrio\n{table.concat(lines, "\n")}`)
