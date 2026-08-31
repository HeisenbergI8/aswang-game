--!strict
--[[
	AmbientRig — where an ambient body sits, so that a disguised one sits in the same place.

		restingYFromLift(groundY, lift)           -> the Y a FREE rig's pivot takes
		puppetYFromLift(rootY, footOffset, lift)  -> the Y a CLAIMED rig's pivot takes
		restingY(groundY, bodyHeight)             -> the same, for a body that pivots on its centre
		puppetY(rootY, footOffset, bodyHeight)    -> ditto

	TWO FUNCTIONS THAT MUST AGREE, WHICH IS THE ENTIRE REASON THIS FILE EXISTS. `AmbientService` seats
	free rigs from a spawn pad and `MonsterService` drives claimed ones from a HumanoidRootPart. Those
	are different reference points in different files, and before this module they disagreed by about
	2.6 studs — so the camouflaged animal FLOATED above every real one of its form, permanently and
	visibly, with nothing in the game or in `npm run verify` reporting it.

	`check:secrecy` CANNOT SEE THIS AND NEVER COULD. It is a text tripwire over role tokens in tag
	names, attributes and payload fields. The leak here is a NUMBER that differs between two entities,
	which is `.claude/lessons/absence-is-observable.md` in its purest form: the difference is the leak,
	and it does not need a name to be readable.

	CALLABLE BY ANY CLIENT AND THAT IS FINE. `src/shared` maps wholesale into `ReplicatedStorage`, so a
	LocalScript can require and RUN this. What it learns is that a body's centre is half its height
	above the ground, which is arithmetic every client can already perform on parts it can see. There
	is no seed here, no draw, and no client-suppliable input — the two conditions CLAUDE.md names for a
	pure module to become a leak.

	NO `script.Parent` REQUIRES — Lune has no `script`, and a module that reached for `Types` would
	stop being runnable from a terminal, which is the whole point of putting it here.
]]

local AmbientRig = {}

--[[
	LIFT — THE DISTANCE FROM A MODEL'S PIVOT TO THE LOWEST POINT OF THE THING IT DRAWS.

	THE TWO FUNCTIONS BELOW ARE THIS PAIR WITH `lift` SPELLED `bodyHeight / 2`, and they stay that way
	because their callers and their suite are written in those terms. This pair exists because that
	spelling is only true for a body whose pivot sits at its own centre — which every mesh rig here
	satisfies and an R15 VILLAGER does not.

	AN R15 MODEL PIVOTS ON ITS `HumanoidRootPart`, which is a 2-stud block sitting about three studs
	above the soles of a five-stud character — nowhere near the half-height a box uses. Seating one
	with `restingY(groundY, 5.18)` puts it 0.4 studs into the ground, which is small enough to look
	like a modelling flaw rather than an arithmetic one, and it would apply to the disguised villager
	and the free ones equally only by luck.

	SO THE CALLER MEASURES ITS OWN LIFT — `pivotY - boundingBoxMinY`, read off the built model — and
	both seating rules take it from here. Nothing is assumed about where a pivot sits.
]]
function AmbientRig.restingYFromLift(groundY: number, lift: number): number
	return groundY + lift
end

-- The claimed-rig twin, and it is `restingYFromLift` with the ground recovered from the monster's
-- root. Two expressions that must agree are one expression called twice — see `puppetY` below, which
-- is the same argument and now defers to this one.
function AmbientRig.puppetYFromLift(rootY: number, footOffset: number, lift: number): number
	return AmbientRig.restingYFromLift(rootY - footOffset, lift)
end

--[[
	WHERE A FREE RIG'S CENTRE GOES. Half its own height above the ground it stands on.

	`groundY` IS THE GROUND, NOT THE SPAWN PAD. The pad is a 0.8-tall marker whose CENTRE sits at 0.4,
	so using its CFrame directly buried every rig by half its own height — 0.2 studs for a cat and 2.1
	for a villager. Taller forms sank further, which is why the fault was easiest to see on exactly the
	form Phase 6 rebuilds as a Humanoid.
]]
function AmbientRig.restingY(groundY: number, bodyHeight: number): number
	return AmbientRig.restingYFromLift(groundY, bodyHeight / 2)
end

--[[
	WHERE A CLAIMED RIG'S CENTRE GOES, given the monster's root.

	`footOffset` IS PASSED IN RATHER THAN ASSUMED, and that is the parameter this whole module turns
	on. The transform SCALES the avatar (§4.3), so the distance from a monster's root to its feet is
	not the R15 default and is not a constant. Hard-coding 3 here would put the disguise back in the
	air for exactly the state the monster is in whenever it is allowed to camouflage — which is to say,
	always.

	IT IS ALGEBRAICALLY `restingY` WITH THE GROUND RECOVERED FROM THE ROOT, and it is written that way
	on purpose: the ground is `rootY - footOffset`, and everything after that is the free rig's own
	rule. Two expressions that must agree are one expression called twice.
]]
function AmbientRig.puppetY(rootY: number, footOffset: number, bodyHeight: number): number
	return AmbientRig.puppetYFromLift(rootY, footOffset, bodyHeight / 2)
end

return AmbientRig
