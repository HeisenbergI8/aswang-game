# Plan: V09 — Bawang, the silent doorway

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V09 (`docs/BUILD-PLAN.md` §V09; spec §4.6, §6.5 invariant 4)
- **Description:** Two bawang per round, placed on a doorway, deny the Aswang that doorway for 15
  seconds, then burn out. The block is **silent and invisible in its effect** — no knockback, no VFX,
  no sound, no camera hitch, no correction. A blocked Aswang and a player choosing to stand still
  must be byte-identical from a third player's client.
- **Date:** 2026-08-31
- **What the client is told:** one new down-remote, `GarlicBarriers`, `FireClient` to **exactly the
  Aswang**, carrying a full list of live barriers — each `{ Position, Yaw, Width, Height,
  SecondsRemaining }`. No role, no UserId, no placer, no doorway id. Every other client is told
  **nothing new**: the placed garlic part and its disappearance are public geometry, and the
  `ITEM_USE` noise cue is the one the throw already emits. `ClientRoundSnapshot` is **not** widened.

---

### The question this chunk is actually about

> How do you stop a character from passing a doorway with **zero** client-observable difference
> between "blocked" and "voluntarily standing still"?

Roblox character movement is client-authoritative through network ownership. The three candidate
mechanisms, and the ruling on each:

**1. Collision groups — RULED OUT, and it would be a total secrecy failure, not a cosmetic one.**
`BasePart.CollisionGroup` is a replicated string property on every `BasePart`, including every part
of every character. Any `LocalScript` on any client can walk another player's character and read it.
So *any* scheme where the Aswang's parts sit in a different collision group from the survivors' parts
is a permanent, map-wide, remote-free role oracle — the exact shape of C04's revert bug and C14's
`WalkSpeed` brand, both of which shipped with `npm run verify` and `check:secrecy` green over them
(`MonsterService.luau:26-29`). The inverse (move the survivors instead) has the identical difference.
And there is no per-observer collision: parts and their properties are global, so a group scheme
cannot be made to exist for one client and not another. Ruled out. Phase 4 hands the playtester the
one-line probe that confirms the premise rather than assuming it.

**2. A client-local barrier on the Aswang's own machine — THE RECOMMENDATION.** The Aswang's client
already knows its own role (`RoleAssigned`), so telling *that one client* "there is a wall here"
leaks nothing it did not already have. The client creates an **anchored, invisible, collidable part**
in its own `workspace`. Instances created by a client are not replicated to the server or to other
clients, so no second client can see it, enumerate it, or tell it exists. The Aswang's own character
is simulated on the Aswang's own machine, so its own physics stops it — its movement simply does not
carry it through, which is the spec's sentence rendered literally. **Nothing on the character changes:
no `WalkSpeed`, no `CollisionGroup`, no attribute, no tag, no `Highlight`, no sound, no animation
state.** The only thing that replicates outward is a position, and a position that stops at a
threshold is what a player who declined to walk in also produces.

**3. Server-side clamping / rejection — used only as the anti-cheat backstop, never as the
mechanic.** A server correction that snaps the character back rubber-bands, and a rubber-band at a
garlic doorway is exactly the tell §4.6's blockquote forbids. But the observability constraint binds
the **honest** case, not the cheating one: an honest client never crosses the plane, so the correction
never fires for it. Phase 4 samples the Aswang's replicated position against the barrier plane and
corrects **only** on a crossing past a Config tolerance — a path reachable only by a client that has
deleted or ignored its own barrier. The correction is observable, and it is only producible by
cheating.

**Rejected outright: `SetNetworkOwner(nil)` on the Aswang's character.** Server-simulating one
character and not the others is a difference the owner feels as input lag and others may read in
motion smoothness, and it would make the monster's movement feel different for the whole round rather
than for fifteen seconds.

### What a third player's client can observe — the table the reviewers will be sent to check

| Case | What a third player's client can observe |
| --- | --- |
| A survivor walks through a garlic doorway | Nothing at all. No remote reaches them, no property changes, no correction runs. They walk through. |
| **The Aswang is honestly blocked** | Its character stops at the threshold. The only thing that replicates is its position. No property on the character differs from a survivor's, in any frame. The barrier part exists solely in the Aswang's own client's `workspace` and never replicates. |
| **The Aswang declines to walk in** | Identical to the row above, by construction. This is the row the entire mechanic exists for. |
| An Aswang on a modified client crosses | The server restores the last position it saw outside the plane. A third player sees a rubber-band. Only reachable by a client that ignored its own barrier. |
| Garlic is placed | Everyone sees a garlic part appear on the doorway; everyone in `Noise` radius gets the same `ITEM_USE` cue the salt throw already emits, from the placer's position, identical whoever placed it. |
| Garlic burns out | Everyone sees the part vanish after `GarlicDuration`. A public clock, which is what makes the loyalty test playable. |

### Constraints that bind every phase, repeated where they are needed rather than cross-referenced

- **The Aswang can carry and place bawang, on identical rules** (§4.4, and `ItemCarry.luau`'s header).
  It is then blocked by its own garlic. Nothing in the placement path may read a role — a placement
  rule that differed for the monster would be a role oracle readable by pressing a key.
- **`ItemUse.verbFor` is the boundary.** `tests/item-use.test.luau` asserts BAWANG returns
  `USE_NOT_IMPLEMENTED`; this chunk turns that cell red on purpose (`ItemUse.luau:14-19`).
- **Pure modules must not `require(script.Parent.X)`.** Re-declare the literal unions locally.
  Return **scalars**, never a list of literal-union values — `.claude/lessons/pure-module-unions-widen-in-lists.md`.
- **Every tunable in `Config.Items`.** `check:config` enforces it.
- **Every `OnServerEvent` handler consults `AntiCheatService.Consume` first, inline**, within 1200
  characters of the `:Connect(` — `check-ratelimit.mjs` is a proximity tripwire.
- **`RoundService` owns the phase.** This chunk subscribes; it never calls `setPhase`.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The contract — a doorway, the numbers, and two pure decisions

Nothing is wired in this phase. It leaves the tree runnable and adds three Lune suites that can fail.

#### Step 1.1: Add the five garlic tunables to `Config.Items`

Adds `GarlicPlaceRangeStuds`, `GarlicBarrierHeight`, `GarlicBarrierPadStuds`,
`GarlicBreachToleranceStuds` and `GarlicBreachSampleInterval` beside the existing `GarlicSpawnCount` /
`GarlicDuration`. **No new colour** — `Items.BawangRgb` already exists for the dropped-item part and
the placed one reuses it, so a bulb on a doorway and a bulb on the floor are the same object to the
eye, which is what makes "someone put garlic there" legible.

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

```diff
 	GarlicSpawnCount = 2,
 	GarlicDuration = 15,
 
+	--[[
+		V09. HOW CLOSE TO A DOORWAY YOU MUST BE STANDING TO PLACE BAWANG ON IT.
+
+		DELIBERATELY SMALLER THAN `Search.RangeStuds` (10), for `DropForwardStuds`' reason: a player
+		standing at a container must not also be able to seal the doorway they came through without
+		walking back to it. Placing garlic is a trip, and the trip is the cost.
+
+		THE SERVER RESOLVES THE DOORWAY, NOT THE CLIENT. `RequestPlaceGarlic` has no argument, so this
+		is the radius the server measures from the placer's OWN character position — the same rule
+		`RequestSearch` applies to containers, and the reason there is no doorway probe.
+	]]
+	GarlicPlaceRangeStuds = 8,
+
+	--[[
+		V09. THE BARRIER'S SHAPE. It is never seen by anybody, including the Aswang, so these are
+		physics numbers rather than art numbers.
+
+		HEIGHT IS TALL ENOUGH THAT A JUMP DOES NOT CLEAR IT. A Roblox character's default jump peaks
+		around 7 studs; the barrier stands from the doorway's floor upward, and a doorway a monster can
+		hop through is a doorway that is not denied. Raise this rather than adding a second rule.
+
+		THE PAD WIDENS THE BARRIER PAST THE WALKABLE GAP so the Aswang cannot squeeze between the
+		barrier's edge and the jamb. `barrio.luau`'s door gap is `6 * SCALE` = 9.3 studs and the
+		`Doorway` anchor carries that as its `Width` attribute; this is added to each side.
+	]]
+	GarlicBarrierHeight = 12,
+	GarlicBarrierPadStuds = 1.5,
+
+	--[[
+		V09. THE ANTI-CHEAT BACKSTOP, AND ITS ONLY JOB IS TO NOT FIRE ON HONEST PLAYERS.
+
+		The block itself is a collidable part that exists on the ASWANG'S OWN CLIENT and nowhere else
+		(see `GarlicController`). An honest client is stopped by its own physics and never crosses the
+		plane, so the server-side correction below never runs for it. These two numbers exist for the
+		client that deleted its barrier.
+
+		THE TOLERANCE IS WHY A CORRECTION CANNOT BRAND AN HONEST ASWANG. A crossing is only a breach
+		when the destination sample is more than this far PAST the plane, so a character standing in
+		the threshold, jittering across it under lag or shoved by a corpse's physics, is never
+		corrected. A rubber-band at a garlic doorway is the exact tell §4.6's blockquote forbids, so
+		this number fails toward doing nothing.
+
+		THE SAMPLE INTERVAL IS SLOW ON PURPOSE. Two barriers at most, one player sampled, for at most
+		`GarlicDuration` seconds — the loop starts on the first placement and stops when the last
+		barrier burns out, so `ItemService`'s "there is no tick any more" rule survives with a bound
+		on it rather than an exception to it.
+	]]
+	GarlicBreachToleranceStuds = 2.5,
+	GarlicBreachSampleInterval = 0.25,
+
```

#### Step 1.2: Pin §6.5 invariant 4 in the config suite

`GarlicDuration < Round.Duration / 4` is named in the spec (line 758) and in `Config.luau`'s comment
and is pinned nowhere. Adds it, plus a sanity pin on the breach tolerance.

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

```diff
+--[[
+	V09, §6.5 INVARIANT 4. GARLIC BUYS TIME, NEVER SAFETY.
+
+	`GarlicDuration < Round.Duration / 4` is written in the spec (line 758) and restated in
+	`Config.Items`' own comment, and until this line it was pinned NOWHERE. It is pillar six's
+	invariant: §3's OUT list forbids a permanent safe room outright, and a garlic duration that crept
+	toward a quarter of the round would build one a doorway at a time, with two bawang in play and no
+	symptom anywhere — the round would simply start ending in a locked house.
+
+	A QUARTER RATHER THAN SOME OTHER FRACTION, because two bawang is the whole supply: at the shipped
+	values two consecutive placements deny one doorway for 30 of 300 seconds, a tenth of the round.
+	The pin is the ceiling on ONE of them.
+]]
+check(
+	"garlic buys time, never safety — one bawang is under a quarter of the round",
+	Config.Items.GarlicDuration < Config.Round.Duration / 4,
+	`GarlicDuration={Config.Items.GarlicDuration}, Round.Duration={Config.Round.Duration}`
+)
+
+--[[
+	V09. THE BREACH TOLERANCE IS A SANITY BOUND, NOT A BALANCE RELATIONSHIP, and it is here because
+	the failure is silent in the direction that matters.
+
+	Positive-and-finite is `ItemCarry`'s `Limit` guard in a second file: `0` makes every jitter across
+	the threshold a breach and rubber-bands an HONEST Aswang, which is the one observable this whole
+	chunk exists to prevent, and `math.huge` deletes the backstop with nothing to say so. Under the
+	place range because a tolerance wider than the reach that placed the garlic is not a tolerance.
+]]
+check(
+	"the garlic breach tolerance is positive, finite, and under the place range",
+	Config.Items.GarlicBreachToleranceStuds > 0
+		and Config.Items.GarlicBreachToleranceStuds < Config.Items.GarlicPlaceRangeStuds,
+	`tolerance={Config.Items.GarlicBreachToleranceStuds}, range={Config.Items.GarlicPlaceRangeStuds}`
+)
```

#### Step 1.3: Declare the garlic unions and the barrier payload in `Types.luau`

`GarlicPlaceVerdict`, `GarlicBarrierSpec`, `GarlicBarriersPayload`, and `"USE_PLACE"` added to
`ItemUseVerdict`. The payload's absent fields are the security design and are documented as such.

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

```diff
 export type ItemUseVerdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"
+	| "USE_PLACE"
+
+--[[
+	V09, §4.6. MAY THIS PLAYER PUT BAWANG ON THIS DOORWAY?
+
+	PREFIXED `GARLIC_`, which is `ItemCarryVerdict`'s rule and `SearchVerdict`'s before it. A fourth
+	union sharing the bare `WRONG_PHASE` spelling makes a handler wired to the wrong path a working
+	program with the wrong meaning, and this one runs beside three others in the same service.
+
+	NOTHING HERE IS ECHOED BACK TO THE CALLER, on any path including OK — the throw handler's rule and
+	the drop handler's, inherited. `GARLIC_DOORWAY_TAKEN` in particular would be a free doorway probe:
+	fire the remote from across the barrio and difference the refusals to learn which doorways are
+	sealed without walking to any of them. It exists so the server can log WHY.
+
+	IT IS NOT A ROLE ORACLE IN EITHER DIRECTION. §4.4 has the Aswang searching and carrying on
+	identical rules, so the monster reaches this union and gets `GARLIC_OK` exactly as a survivor
+	does — and is then blocked by its own garlic, which is correct and is the funniest outcome in the
+	chunk. A "the monster may not place" verdict would be an oracle readable by pressing a key.
+]]
+export type GarlicPlaceVerdict =
+	"GARLIC_OK"
+	| "GARLIC_WRONG_PHASE"
+	| "GARLIC_NOT_ALIVE"
+	| "GARLIC_NOT_HELD"
+	| "GARLIC_NO_DOORWAY"
+	| "GARLIC_DOORWAY_TAKEN"
+
+--[[
+	V09, §4.6. ONE LIVE BARRIER, AS THE ASWANG'S OWN CLIENT NEEDS IT TO BUILD A COLLIDABLE PART.
+
+	WHAT IS ABSENT IS THE SECURITY DESIGN, and every absence is deliberate:
+
+	  · NO PLACER. Not a UserId, not a name, not a `PlacedByYou`. Who put the garlic there is a fact
+	    about a player, and the recipient is the one player in the round who must not be handed a
+	    survivor's movements for free. `placeItem`'s header refuses the same field on the dropped part.
+	  · NO DOORWAY ID. With no key in the payload there is nothing to log, difference or accumulate —
+	    `SearchUpdatePayload`'s structural argument. The Aswang can see the garlic on the doorway; the
+	    server never tells it which doorway the doorway is.
+	  · NO ROLE, AND NO FLAG THAT WOULD IMPLY ONE. The recipient is resolved server-side from
+	    `RoundService.GetAswangUserId()`, exactly as `FeedUpdate` and `CamouflageUpdate` resolve theirs.
+
+	`SecondsRemaining` RATHER THAN AN EXPIRY TIMESTAMP. A server `os.clock()` is meaningless on a
+	client and an `os.time()` would be a shared clock two clients could difference. A duration is what
+	the client needs and states nothing about when the round started.
+]]
+export type GarlicBarrierSpec = {
+	Position: Vector3,
+	Yaw: number,
+	Width: number,
+	Height: number,
+	SecondsRemaining: number,
+}
+
+--[[
+	V09. A FULL SNAPSHOT OF THE LIVE BARRIERS, NOT A DELTA, and `RequestSearch`/`RequestCancelSearch`'s
+	header is the argument: two messages for one state are how a client and a server come to disagree
+	about it. A dropped "barrier added" leaves the Aswang walking through garlic; a dropped "barrier
+	expired" leaves it walled out of a room forever. A snapshot cannot desync, is idempotent on a
+	duplicate, and re-sending it on `CharacterAdded` is the whole of the rejoin path.
+
+	AT MOST `Config.Items.GarlicSpawnCount` ENTRIES — two. The list is not a cost worth optimising.
+]]
+export type GarlicBarriersPayload = {
+	Barriers: { GarlicBarrierSpec },
+}
```

> `{ GarlicBarrierSpec }` is a list of **tables**, not a list of literal-union values, so
> `.claude/lessons/pure-module-unions-widen-in-lists.md` does not bite here. It would bite instantly
> if a `Verdict` field were ever added to the spec — do not add one.

#### Step 1.4: `pure/GarlicPlacement` — may this player place bawang here, right now?

A scalar verdict over phase, player state, held item, the distance to the nearest doorway the server
resolved, and whether that doorway already carries garlic. Takes no role, and must not start.

**File:** `src/shared/pure/GarlicPlacement.luau`
**Verify:** `lune run tests/garlic-placement.test.luau`

```diff
+--!strict
+--[[
+	GarlicPlacement — may this player put bawang on this doorway right now? (§4.6, V09)
+
+		(request) -> verdict
+
+	THE FOURTH ITEM VERDICT, AND IT IS A SEPARATE MODULE FROM `ItemDrop` FOR THE REASON `ItemDrop`'S
+	OWN HEADER PREDICTED: "a placement rule would be V09's, not V08's. Bawang is PLACED on a doorway
+	and that placement has conditions — a doorway, a duration, a burn-out. Dropping is the plain act
+	of ceasing to hold something." This is that module, and merging the two would give each a verdict
+	it can never return.
+
+	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It never takes a role and it must not
+	start. §4.4 has the Aswang searching and carrying on identical rules, so the monster reaches this
+	module, gets `GARLIC_OK`, places bawang, and is then blocked by its own garlic. That is correct.
+	A rule that refused the monster would be a role oracle readable by pressing a key, and it would
+	also delete the best bluff in the design — an Aswang that seals a doorway and then declines to
+	walk through it is playing the loyalty test rather than failing it.
+
+	IT DECIDES NOTHING ABOUT THE BLOCK. Whether a barrier stops a character is physics on one client
+	and geometry on the server (`pure/GarlicBarrier`); this module only decides whether one is
+	created. Keeping the two apart is what lets the block's mechanism change without re-arguing the
+	placement rule.
+
+	THE CALLER RESOLVES THE DOORWAY. `DoorwayDistance` is nil when the server found no tagged
+	`Doorway` at all, which is a different world from "there is one and you are too far from it" —
+	the second is a UX finding, the first is a map fault. Both land on `GARLIC_NO_DOORWAY` because
+	nothing is echoed to the client either way, and the SERVER logs which by looking at its own
+	lookup.
+
+	NO `script.Parent` REQUIRES. All three unions are re-declared; Luau unions are structural.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
+export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
+
+export type Verdict =
+	"GARLIC_OK"
+	| "GARLIC_WRONG_PHASE"
+	| "GARLIC_NOT_ALIVE"
+	| "GARLIC_NOT_HELD"
+	| "GARLIC_NO_DOORWAY"
+	| "GARLIC_DOORWAY_TAKEN"
+
+export type Request = {
+	Phase: RoundPhase,
+	PlayerState: PlayerState,
+	-- The slot's CURRENT occupant, or nil for an empty hand. Anything that is not BAWANG refuses.
+	Held: ItemType?,
+	-- Distance to the nearest tagged doorway the SERVER resolved, or nil if there was none.
+	DoorwayDistance: number?,
+	Range: number,
+	-- Whether that doorway already carries live garlic. Two bawang on one doorway would double the
+	-- denial to 30s from a supply of two, which is the safe room §3 forbids assembled by accident.
+	DoorwayOccupied: boolean,
+}
+
+local GarlicPlacement = {}
+
+--[[
+	ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in `ItemCarry`, `ItemDrop` and
+	`ItemThrow`: world facts first, then the player, then the slot, then the geometry.
+
+	`GARLIC_NOT_ALIVE` IS AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`, for `pure/PlayerBody`'s
+	reason. A DEAD player must not seal a doorway: the death path already spills what they held
+	(§4.6), and a body that can still deny the monster a room is a corpse playing the round.
+
+	FAIL CLOSED ON THE RANGE, tested positive-and-finite rather than for zero — `ItemCarry.Limit`'s
+	guard, fifth time. A `Range` of `math.huge` deletes the walk that IS the cost of placing garlic,
+	and nothing in the game would say so.
+]]
+function GarlicPlacement.evaluate(request: Request): Verdict
+	if request.Phase ~= "ACTIVE" then
+		return "GARLIC_WRONG_PHASE"
+	end
+
+	if request.PlayerState ~= "ALIVE" then
+		return "GARLIC_NOT_ALIVE"
+	end
+
+	if request.Held ~= "BAWANG" then
+		return "GARLIC_NOT_HELD"
+	end
+
+	if not (request.Range > 0 and request.Range < math.huge) then
+		return "GARLIC_NO_DOORWAY"
+	end
+
+	local distance = request.DoorwayDistance
+
+	if distance == nil or distance ~= distance or distance > request.Range then
+		return "GARLIC_NO_DOORWAY"
+	end
+
+	if request.DoorwayOccupied then
+		return "GARLIC_DOORWAY_TAKEN"
+	end
+
+	return "GARLIC_OK"
+end
+
+return GarlicPlacement
```

`tests/garlic-placement.test.luau` walks the grid the way `tests/item-carry.test.luau` does: every
phase against ALIVE-with-BAWANG-in-range; every player state; all three item types plus the empty
hand; a nil distance, a NaN distance, a distance exactly at `Range` (accepted) and one stud past it
(refused); an occupied doorway; and a `Range` of `0`, `-1`, `0/0` and `math.huge`. The **order** is
asserted directly — a dead player holding nothing at no doorway must return `GARLIC_NOT_ALIVE`, not
`GARLIC_NOT_HELD` — because the order is what makes the server's log readable.

#### Step 1.5: `pure/GarlicBarrier` — the burn-out clock and the crossing predicate

`isLive`, `secondsRemaining` and `crossed(barrier, from, to, tolerance)`. `crossed` is the server's
breach detector in Phase 4; it is plain geometry over plain tables, with no seed and no secret.

**File:** `src/shared/pure/GarlicBarrier.luau`
**Verify:** `lune run tests/garlic-barrier.test.luau`

```diff
+--!strict
+--[[
+	GarlicBarrier — the burn-out clock, and did something cross this doorway? (§4.6, V09)
+
+		isLive(barrier, now) -> boolean
+		secondsRemaining(barrier, now) -> number
+		crossed(barrier, from, to, tolerance) -> boolean
+
+	IT IS NOT THE BLOCK. The block is a collidable part on the ASWANG'S OWN CLIENT and the Aswang's
+	own physics is what stops it — see `GarlicController` and the plan's observability table. This
+	module is the SERVER'S answer to "did that happen anyway", which is the only question left once
+	the block lives on a machine the server does not control.
+
+	WHY THE SERVER NEEDS A PREDICATE AT ALL. A client that deletes its own barrier walks through. The
+	server cannot see the barrier and cannot re-simulate the character, so the one thing it can do is
+	compare two positions it DID see against a plane it owns. That is this function.
+
+	THE TOLERANCE IS THE HALF THAT MATTERS AND IT ONLY EVER MAKES THE ANSWER `false`. §4.6's
+	blockquote forbids the barrier playing any effect on the monster, and a server correction that
+	rubber-bands IS an effect. So a crossing is only reported when the destination is more than
+	`tolerance` PAST the plane: a character standing in the threshold, drifting across it under lag or
+	shoved by a corpse's physics, is not a breach. This fails toward doing nothing, deliberately, and
+	the cost of a false negative is at most fifteen seconds of a doorway.
+
+	NOTHING HERE IS SECRET AND THERE IS NO SEED. The barrier's position is a garlic bulb every client
+	can see on a doorway every client can walk to; the two positions are the SERVER'S samples of a
+	character that replicates anyway. A client that requires and runs this module learns geometry it
+	is already looking at, which is CLAUDE.md's test applied rather than assumed.
+
+	ANGLES ARE RADIANS HERE AND DEGREES ON THE MAP. `barrio.luau` writes a `Yaw` attribute in degrees
+	because that is what a human editing a layout reads; `ItemService` converts once, at the boundary.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes — `Vec3` is a plain table, converted at the
+	call site, exactly as `pure/ItemThrow` does it.
+]]
+
+export type Vec3 = { X: number, Y: number, Z: number }
+
+--[[
+	`Y` IS THE DOORWAY'S FLOOR, not its centre, and `Height` runs upward from it. A doorway's floor is
+	what the map gives us (the anchor pad sits on it) and a centre would have to be derived from a
+	height that is in Config, which would put the same number in two places.
+
+	`ExpiresAt` IS ON THE SERVER'S CLOCK and never crosses to a client — `Types.GarlicBarrierSpec`
+	carries a DURATION for that reason. This field exists so `isLive` has one comparison to make.
+]]
+export type Barrier = {
+	X: number,
+	Y: number,
+	Z: number,
+	Yaw: number,
+	HalfWidth: number,
+	Height: number,
+	ExpiresAt: number,
+}
+
+local GarlicBarrier = {}
+
+--[[
+	THE TWO AXES, AND THE CONVENTION IS `barrio.luau`'S RATHER THAN AN INVENTED ONE.
+
+	`along` is the direction the doorway's WIDTH runs; `normal` is the direction you cross. At yaw 0
+	`along` is +X and `normal` is +Z, which is a door in an N or S wall; at 90 degrees they swap,
+	which is a door in an E or W wall. The builder writes `yaw = if nx ~= 0 then 90 else 0` on exactly
+	that reading, so the two files agree by construction rather than by a comment.
+]]
+local function axes(yaw: number): (Vec3, Vec3)
+	local c, s = math.cos(yaw), math.sin(yaw)
+
+	return { X = c, Y = 0, Z = s }, { X = -s, Y = 0, Z = c }
+end
+
+local function planarDot(a: Vec3, b: Vec3): number
+	return a.X * b.X + a.Z * b.Z
+end
+
+function GarlicBarrier.isLive(barrier: Barrier, now: number): boolean
+	return now < barrier.ExpiresAt
+end
+
+-- Floored at zero so a barrier the sweep has not reached yet never sends a negative duration to a
+-- client, which would render as a wall that is already gone.
+function GarlicBarrier.secondsRemaining(barrier: Barrier, now: number): number
+	return math.max(0, barrier.ExpiresAt - now)
+end
+
+--[[
+	DID A CHARACTER MOVE FROM ONE SIDE OF THIS DOORWAY TO THE OTHER, THROUGH THE OPENING?
+
+	FOUR TESTS, AND EVERY ONE OF THEM CAN ONLY REFUSE:
+
+	  1. A STRICT SIGN CHANGE. `dFrom * dTo >= 0` is not a crossing — which deliberately includes a
+	     sample that landed exactly ON the plane, because a character standing in the threshold is the
+	     honest case and must never be corrected.
+	  2. THE DESTINATION IS PAST THE PLANE BY MORE THAN `tolerance`. See the header.
+	  3. THE CROSSING POINT IS INSIDE THE OPENING'S WIDTH. Walking around the house and through a
+	     different wall crosses the same infinite plane and is not a breach — this is the test that
+	     makes the plane a doorway rather than a fence across the barrio.
+	  4. THE CROSSING POINT IS UNDER THE BARRIER'S HEIGHT and at or above its floor. A character on a
+	     roof passing over the doorway is not passing through it.
+]]
+function GarlicBarrier.crossed(barrier: Barrier, from: Vec3, to: Vec3, tolerance: number): boolean
+	local along, normal = axes(barrier.Yaw)
+	local centre: Vec3 = { X = barrier.X, Y = barrier.Y, Z = barrier.Z }
+
+	local dFrom = planarDot({ X = from.X - centre.X, Y = 0, Z = from.Z - centre.Z }, normal)
+	local dTo = planarDot({ X = to.X - centre.X, Y = 0, Z = to.Z - centre.Z }, normal)
+
+	if dFrom * dTo >= 0 then
+		return false
+	end
+
+	if math.abs(dTo) <= tolerance then
+		return false
+	end
+
+	-- Where along the segment the plane was met. The denominator cannot be zero: the sign test above
+	-- already proved the two are strictly opposite, so they differ.
+	local t = dFrom / (dFrom - dTo)
+	local at: Vec3 = {
+		X = from.X + (to.X - from.X) * t,
+		Y = from.Y + (to.Y - from.Y) * t,
+		Z = from.Z + (to.Z - from.Z) * t,
+	}
+
+	local lateral = planarDot({ X = at.X - centre.X, Y = 0, Z = at.Z - centre.Z }, along)
+
+	if math.abs(lateral) > barrier.HalfWidth then
+		return false
+	end
+
+	return at.Y >= centre.Y and at.Y <= centre.Y + barrier.Height
+end
+
+return GarlicBarrier
```

`tests/garlic-barrier.test.luau` covers, at yaw `0` and yaw `math.pi / 2` so the axis convention is
proven rather than assumed: both samples on the same side; both on the far side (already through, no
new crossing); a crossing dead through the middle; a crossing offset past `HalfWidth` (the walk
around the house); a crossing over the top of the barrier; a crossing under the floor; a destination
inside `tolerance` of the plane; a sample landing exactly on the plane; and `isLive` /
`secondsRemaining` either side of `ExpiresAt` including exactly at it.

#### Step 1.6: Tag the nine doorways in the barrio builder

Seven kubo doors plus the chapel's two, emitted as invisible `Doorway` anchor pads carrying `Yaw` and
`Width` attributes, using the existing `anchor()` helper. Doorways are not tagged today; this is what
tagging them costs.

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-doorways.test.luau`

**A doorway is not a thing in this map today.** `building()` cuts a door as a gap between two wall
segments; a **stilted** house additionally gets four decor parts per door — `{name}_DoorJamb{tag}1/2`,
`{name}_DoorLintel{tag}`, `{name}_DoorSill{tag}`, `{name}_DoorLeaf{tag}` — and the chapel, which is
not stilted, gets **none of them**. So there is no part shape that means "doorway" across the whole
map, and `DoorSill` cannot be reused: it exists for seven of the nine doors.

**What tagging them costs: nine calls to a helper that already exists.** `anchor(name, tag, cx, cz,
parent, attributes)` is the invisible tagged pad `SearchContainer`, `AmbientSpawn` and `TaskPoint` are
all discovered through, and it already takes attributes. Both new call sites sit **after** `anchor()`'s
declaration (line 1234) — the chapel at 1545 and the KUBO loop at 1648 — so nothing moves and
`building()` is not touched at all. That last point is the one that matters: `building()` owns the door
gap, the door gap is a **navmesh** number the file warns twice about, and this chunk has no reason to
be inside it.

```diff
 local chapel = building("Chapel", 0, -152, 46, 36, 16, { S = true, E = true }, STONE, Enum.Material.Cobblestone)
+
+--[[
+	V09. THE CHAPEL'S TWO DOORWAYS, TAGGED FOR `ItemService`'s BAWANG PLACEMENT (§4.6).
+
+	IT IS BUILT HERE RATHER THAN INSIDE `building()` FOR THE REASON THE DOOR FRAME IS NOT HERE EITHER:
+	the frame block is behind `if stilted`, the chapel is deliberately not stilted ("a visita sits on
+	the ground"), and moving the block out would put four decor parts in a doorway that has never had
+	them. The tag is scaffolding; the geometry is not this chunk's business.
+
+	THE OFFSETS ARE THE HALF-EXTENTS OF THE CALL ABOVE — 46 wide and 36 deep, so 23 and 18 — and the
+	sides match its `doors` set. Two literals typed twice is exactly the drift
+	`tests/barrio-interiors.test.luau` was written for, so `tests/barrio-doorways.test.luau` parses
+	both the call and these and compares them.
+]]
+doorway("Chapel", "S", 0, -152 + 18, chapel)
+doorway("Chapel", "E", 0 + 23, -152, chapel)
```

```diff
 for index, kubo in KUBO do
 	building(
 		kubo.Name,
 		kubo.X,
 		kubo.Z,
 		24,
 		20,
 		if kubo.Enterable then 12 else 9,
 		kubo.Doors,
 		WOOD,
 		nil,
 		true
 	)
 
+	--[[
+		V09. ONE `Doorway` PAD PER DOOR THIS HOUSE ACTUALLY HAS (§4.6).
+
+		DRIVEN OFF `kubo.Doors` RATHER THAN OFF A SECOND LIST. The KUBO table is this file's source of
+		truth for which face is open — `tests/barrio-interiors.test.luau` already rests three
+		invariants on it — so a doorway pad that disagreed with it would be a barrier in a wall, and
+		garlic would deny a doorway nobody can walk through. Sealed houses have an empty `Doors` set
+		and correctly get nothing.
+
+		24 WIDE AND 20 DEEP ARE THE `building()` CALL DIRECTLY ABOVE, so the half-extents are 12 and
+		10. They are hand-copied and the suite reconciles them, exactly as the container coordinates
+		are reconciled.
+	]]
+	for _, side in { "N", "S", "E", "W" } do
+		if kubo.Doors[side] then
+			local dx = if side == "E" then 12 elseif side == "W" then -12 else 0
+			local dz = if side == "S" then 10 elseif side == "N" then -10 else 0
+
+			doorway(kubo.Name, side, kubo.X + dx, kubo.Z + dz, root:FindFirstChild(kubo.Name))
+		end
+	end
+
 	--[[
 		A GENERATED SHELL OVER THE TWO SEALED KUBO, AND ONLY THOSE TWO.
```

The helper, declared beside `anchor()`:

```diff
+--[[
+	V09, §4.6. A DOORWAY, AS A SERVICE CAN FIND IT.
+
+	`ItemService.discoverDoorways` reads the `Doorway` tag exactly as `SearchService.discoverPool`
+	reads `SearchContainer`, and for the same reason: this file is outside `src/`, so a doorway that
+	failed to appear would be behind no gate at all and the symptom would be "bawang does nothing".
+
+	THE TAG AND THE ATTRIBUTES ARE REPLICATED, AND THAT IS FINE ON `placeItem`'s ARGUMENT. They
+	describe a hole in a wall every client can already walk through, they name no player, and they
+	carry no round state. `check:secrecy` inspects tags and this one passes because it carries nothing.
+
+	`Width` IS IN REAL STUDS, WHICH IS NOT WHAT THE BUILDER'S `door` IS. `building()` works in
+	pre-scale units and `box()` multiplies positions by `SCALE` (1.55), so the door gap of 6 units is
+	`6 * 1.55` = 9.3 STUDS on the ground — the file's own comment says "six is nine and a half studs".
+	Writing 6 here would build a barrier two thirds the width of the doorway it is supposed to deny,
+	and an Aswang would walk around its edge with nothing anywhere reporting a fault.
+
+	`Yaw` IS IN DEGREES because a human editing a layout reads degrees; `pure/GarlicBarrier` works in
+	radians and `ItemService` converts once, at the boundary. The convention is `building()`'s own:
+	an E or W door is a wall running along Z, so the barrier's width runs along Z, which is 90.
+]]
+local function doorway(house: string, side: string, cx: number, cz: number, parent: Instance): Part
+	return anchor(`{house}_Doorway{side}`, "Doorway", cx, cz, parent, {
+		Yaw = if side == "E" or side == "W" then 90 else 0,
+		Width = 6 * SCALE,
+	})
+end
```

And the receipt gains the count it can fail on:

```diff
 assert(
 	countTrialOnly() == 2,
 	`[barrio] {countTrialOnly()} TrialOnly TaskPoint parts, expected 2 — the Solo Trial has nothing to do`
 )
+--[[
+	V09. NINE DOORWAYS — seven kubo, one door each, plus the chapel's two.
+
+	ASSERTED RATHER THAN PRINTED, on the three above's argument: a missing doorway's player-visible
+	symptom is "I pressed the key and nothing happened", which is indistinguishable from bawang not
+	being implemented yet. The number is hand-copied from the KUBO table and the chapel call, and
+	`tests/barrio-doorways.test.luau` reconciles it against both.
+]]
+assert(
+	count("Doorway") == 9,
+	`[barrio] {count("Doorway")} Doorway parts, expected 9 — bawang will have nothing to be placed on`
+)
```

`tests/barrio-doorways.test.luau` parses the builder as text, the way `barrio-interiors` does, and
asserts: the `doorway()` helper exists and tags `Doorway`; every `kubo.Doors` entry in the KUBO table
has a matching pad and no pad exists for a sealed face; the chapel's two pads match the sides in its
`building()` call and its half-extents match its `w`/`d` arguments; the kubo offsets match `24`/`20`;
`Width` is written as `6 * SCALE` and not as a bare `6`; `Yaw` is `90` exactly for E and W and `0`
exactly for N and S; and the receipt's literal `9` equals the number of pads the table implies.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the `Doorway` tag and its two attributes replicate to every client. They
  describe a hole in a wall, name no player and carry no round state, so they are `SearchContainer`'s
  case. Nothing else in this phase reaches a client at all.
- **Remote direction** — no remotes in this phase.
- **Rate limiting** — no `OnServerEvent` handlers in this phase.
- **Magic numbers** — the five tunables are in `Config.Items`. The builder's `24`, `20`, `23`, `18`,
  `12`, `10` and `6 * SCALE` are **map geometry in a file outside `src/`**, hand-copied from the calls
  directly above them and reconciled by the new suite — the same arrangement the container
  coordinates already live under. `check:config` does not scan `tools/`.
- **Phase ownership** — nothing here reads or sets the phase.
- **Player leaving mid-round** — not reachable in this phase; Phase 2 owns it.
- **Strict Luau** — both pure modules return **scalar** literal unions, never a list of them. The
  `Barrier` and `GarlicBarrierSpec` lists are lists of TABLES, which is the shape the lesson does not
  bite on. `analyze` covers `Types.luau`'s new unions.
- **Mobile budget** — nine invisible, non-colliding, non-querying, shadowless anchor pads. No lights,
  no particles, no per-frame work. `tests/barrio-budget.test.luau` and `light-budget` are untouched.
- **Scope** — nothing from §3's OUT list. `Doorway`, `Garlic`, `Bawang` and `Barrier` are checked
  against `check:scope`'s word splitter in Step 2.1's verify, which is the first step to run it.

**Issues identified:**

- **`anchor()`'s pad is a fixed 6 x 0.8 x 6 box and its comment says the size is "a reading of a
  Config range".** The doorway pad borrows a helper whose size means something else. It is harmless —
  nothing reads a doorway pad's size, only its `CFrame` and attributes, and the barrier's dimensions
  come from `Width` plus `Config` — but the helper's comment will now be false for one of its four
  tags. Add a sentence to it rather than leaving a reader to reconcile it.
- **The pad's `Position.Y` is the builder's ground plane (0.4), and the kubo are built `stilted`.**
  The stilts are decoration — the file says a stilted floor "needs a ramp to be walkable and a ramp is
  a pathfinding problem this milestone has no reason to buy" — so the walkable floor is at ground
  level and the pad is at the right height. `ItemService` must nonetheless read the **pad's own
  `Position.Y`** as the barrier floor rather than assuming a constant, so that if a future pass does
  raise a floor the barrier follows the map instead of the plan. Recorded in Follow Ups.
- **`building()`'s half-extents are assumed to be `w / 2` and `d / 2`.** Read from the call signature
  and the `hw`/`hd` locals, not from running it. If they are anything else, every pad is offset and
  the new suite will not catch it because the suite compares the same two literals. The playtester's
  first artifact should be a screenshot of a `Doorway` pad selected in a doorway.

---

### Phase 2: The server — placing bawang, and the item that finally has a verb

#### Step 2.1: Declare `RequestPlaceGarlic` in `Remotes.luau`

Up-list, **no arguments**: the server resolves the nearest doorway from the placer's own character
position, exactly as `RequestSearch` resolves a container.

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

```diff
 	"RequestSmoke",
+	--[[
+		V09, §4.6. NO ARGUMENTS, and the absent argument is the entire security design.
+
+		THE DOORWAY IS NOT NAMED BY THE CLIENT. The server resolves the nearest part tagged `Doorway`
+		within `Config.Items.GarlicPlaceRangeStuds` of that player's OWN character position — the rule
+		`RequestSearch` states in full and `RequestDropItem` restates: the server resolves what a
+		player is standing at from that player's own character position, and the client names nothing.
+
+		A `RequestPlaceGarlic(doorway)` WOULD HAVE BEEN A FREE MAP PROBE. It needs a verdict for "that
+		doorway is not near you", which is the distance comparison the server was already positioned
+		to make; and it hands a compromised client the ability to name every tagged part in turn and
+		read back which doorways are already sealed — an index of where the survivors are fortifying,
+		delivered to whoever asks, including the one player who most wants it. The map's part names
+		are readable by any client because Workspace replicates, so the probe would be trivial.
+
+		NOR IS THERE AN ITEM ARGUMENT. `Config.Items.CarryLimit` is 1, so there is exactly one thing a
+		player can be holding and the server already knows what it is. `RequestDropItem`'s header has
+		the full argument; the sharp end is the same one — a handler that acts on an item the client
+		named is a handler that can be asked about the round's only win condition.
+
+		IT IS NOT A ROLE ORACLE IN EITHER DIRECTION. §4.4 has the Aswang searching and carrying on
+		identical rules, so the monster can place bawang exactly as a survivor can, and must — see
+		`Types.ClientRoundSnapshot.YourCarriedItem`. It is then blocked by its own garlic. Nothing is
+		returned to the caller on any path, including OK.
+	]]
+	"RequestPlaceGarlic",
 }
```

#### Step 2.2: Give it a rate-limit budget, and add it to the suite's hand-copied list

`Config.AntiCheat.Budgets.RequestPlaceGarlic`, plus the `UP_REMOTES` entry the suite needs or it
fails from the other side.

**File:** `tests/anti-cheat-budgets.test.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

The suite hand-copies `Remotes.EVENTS_UP` because Lune cannot require a module that calls
`game:GetService` at scope. Its `EXTRA_BUDGETS` assertion fails on a budget naming a remote the list
does not carry, so **the budget and the list entry must land in the same step or the step is red** —
which is exactly the coupling that makes this a real check rather than a grep.

```diff
 	"RequestSmoke",
+	-- V09. The doorway placement. Argument-free, like the two above it: the server resolves the
+	-- nearest tagged `Doorway` from the placer's own character position and the client names nothing.
+	"RequestPlaceGarlic",
 }
```

```diff
 			RequestCamouflage = { Capacity = 3, RefillPerSecond = 0.2 },
+			--[[
+				V09, §4.6. TWO BAWANG EXIST IN THE WHOLE ROUND, so the honest ceiling on this handler
+				is two successful calls in five minutes and the budget is not protecting throughput.
+
+				IT IS PROTECTING THE REFUSAL PATH, which is where the only interesting attack is. A
+				refused placement costs the server a `GetTagged` sweep and a distance comparison per
+				doorway, and an unbudgeted handler would let one client run that sweep as fast as it
+				can send — with no item in hand, forever. The capacity is small and the refill is slow
+				because a player who legitimately needs a third press within twelve seconds does not
+				exist: they are standing at a doorway with one item.
+			]]
+			RequestPlaceGarlic = { Capacity = 3, RefillPerSecond = 0.25 },
```

> This step edits **two** files — `src/shared/Config.luau` for the budget and
> `tests/anti-cheat-budgets.test.luau` for the list. The `**File:**` line names the suite because the
> suite is what the verify runs and what fails if either half is missing; `Config-review.luau` in
> `references/` covers the other half.

#### Step 2.3: `ItemUse.verbFor(BAWANG)` becomes `USE_PLACE`

The boundary V08 wrote down on purpose, moved. The suite's asserted cell flips in the same step.

**File:** `src/shared/pure/ItemUse.luau`
**Verify:** `lune run tests/item-use.test.luau`

`ItemUse`'s header says this out loud: *"V09 replaces `USE_NOT_IMPLEMENTED` for BAWANG with a real
verdict and a real mechanic in the same chunk, or it does not land."* This is that replacement, and
the suite's asserted cell flips with it.

```diff
-export type Verdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"
+export type Verdict = "USE_THROW" | "USE_PLACE" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"
```

```diff
 	if held == "SALT" then
 		return "USE_THROW"
 	end
 
+	--[[
+		BAWANG (V09). §4.6's second verb: placed on a doorway, denying it for `GarlicDuration`, then
+		burning out.
+
+		THE VALUE IS WHAT STOPS THE THROW HANDLER DESTROYING IT. `pure/ItemThrow` collapses a player
+		holding bawang into MISS — the fifth world, deliberately, so a refusal shape cannot be
+		differenced into a role oracle — and MISS reaches `ItemService`'s spend line. The throw
+		handler asks this module before spending, so the moment `USE_PLACE` exists a mis-press with
+		bawang in hand stops burning one of the round's two.
+	]]
+	if held == "BAWANG" then
+		return "USE_PLACE"
+	end
+
 	--[[
-		BAWANG (V09) AND BUNTOT PAGI (V10). Both answer the same thing, deliberately, and NOT two
-		distinct "not yet" values — a split here would be a hint about which chunk is closer to
-		landing, which is a fact about the roadmap and not about the game.
+		BUNTOT PAGI (V10), AND IT IS NOW THE ONLY ITEM WITHOUT A VERB. The reason a split between two
+		unimplemented items would have been a roadmap hint has expired with the split — there is one
+		left, and `tests/item-use.test.luau` is where its boundary is written down until V10 moves it.
 	]]
 	return "USE_NOT_IMPLEMENTED"
```

The suite's two asserted cells become three: SALT is `USE_THROW`, BAWANG is now `USE_PLACE`,
BUNTOT_PAGI is still `USE_NOT_IMPLEMENTED`, and the empty hand is `USE_NOTHING_HELD`. **Do not delete
the `USE_NOT_IMPLEMENTED` case** — V10 needs the boundary to still exist for the one item that has
not moved.

#### Step 2.4: `ItemService` — doorway discovery, the barrier table, the handler, and the burn-out

The whole server half: the tagged-doorway pool, the `RequestPlaceGarlic` handler with its inline
`AntiCheatService.Consume`, the public garlic part, the `ITEM_USE` noise emit, the `task.delay`
burn-out, and the INTERMISSION/IDLE sweep.

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:ratelimit`

**It goes in `ItemService`, not a new `GarlicService`, and that is a decision rather than a default.**
The slot is the authority for what a player holds and it lives here; the placement path needs
`RoundService`, `NoiseService` and `AntiCheatService`, all three of which this file already requires;
and a separate service would have to reach across for the slot on every call, which is the coupling
`ItemService`'s header spends its first paragraph refusing. The cost is that this file grows past
1,200 lines, and that is in Follow Ups.

```diff
 local ItemCarry = require(Shared.pure.ItemCarry)
 local ItemDrop = require(Shared.pure.ItemDrop)
 local ItemUse = require(Shared.pure.ItemUse)
 local ItemThrow = require(Shared.pure.ItemThrow)
+local GarlicBarrier = require(Shared.pure.GarlicBarrier)
+local GarlicPlacement = require(Shared.pure.GarlicPlacement)
 local Types = require(Shared.Types)
```

```diff
+--[[
+	V09, §4.6. THE DOORWAYS, AND THE LIVE BARRIERS STANDING IN THEM.
+
+	DISCOVERED BY TAG, NOT BY NAME, exactly as `SearchService.discoverPool` finds containers. The map
+	is not in git and the builder is outside `src/`, so a tag is the only contract the two can share;
+	a name pattern would silently stop matching the day a house is renamed.
+
+	`barriers` IS SERVER-ONLY AND IS NOT THE SAME KIND OF SECRET AS `slot`. A roster of who holds what
+	is a roster of who can answer the Aswang; a list of which doorways have garlic on them is public
+	by construction — every client can see the bulbs. It is server-owned because the BURN-OUT CLOCK
+	and the breach test must have one home, not because the contents are private.
+
+	AT MOST `Config.Items.GarlicSpawnCount` ENTRIES — two. A list rather than a map keyed by doorway,
+	because two is not a lookup problem and a list is what `Types.GarlicBarriersPayload` sends.
+]]
+local TAG_DOORWAY = "Doorway"
+local TAG_GARLIC = "PlacedGarlic"
+
+type ActiveBarrier = {
+	Doorway: BasePart,
+	Part: BasePart,
+	Spec: GarlicBarrier.Barrier,
+}
+
+local barriers: { ActiveBarrier } = {}
```

```diff
+--[[
+	THE NEAREST DOORWAY TO THIS PLAYER, MEASURED FROM THE SERVER'S COPY OF THEIR CHARACTER.
+
+	`RequestPlaceGarlic` HAS NO ARGUMENT, so this is the whole of how a doorway is chosen. It returns
+	the part AND the distance rather than a boolean, because `pure/GarlicPlacement` wants the distance
+	and the service wants the part, and computing it twice is how the two come to disagree.
+
+	NIL FOR NO CHARACTER, NOT (0,0,0). A player with no root has no position, and the origin is a
+	place in the barrio somebody can stand.
+]]
+local function nearestDoorway(player: Player): (BasePart?, number?)
+	local character = player.Character
+	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+
+	if root == nil or not root:IsA("BasePart") then
+		return nil, nil
+	end
+
+	local best: BasePart? = nil
+	local bestDistance = math.huge
+
+	for _, part in CollectionService:GetTagged(TAG_DOORWAY) do
+		if not part:IsA("BasePart") then
+			continue
+		end
+
+		local distance = (part.Position - root.Position).Magnitude
+
+		if distance < bestDistance then
+			best, bestDistance = part, distance
+		end
+	end
+
+	if best == nil then
+		return nil, nil
+	end
+
+	return best, bestDistance
+end
+
+-- Compared by INSTANCE, never by name. Two houses could carry the same door side and the pad names
+-- are interpolated in the builder; the instance is the identity the tag actually hands us.
+local function doorwayOccupied(doorway: BasePart): boolean
+	for _, active in barriers do
+		if active.Doorway == doorway then
+			return true
+		end
+	end
+
+	return false
+end
```

```diff
+--[[
+	V09, §4.6. PUT BAWANG ON A DOORWAY.
+
+	THE VISIBLE HALF IS PUBLIC AND MUST BE. §4.6's blockquote builds the loyalty test on everyone
+	being able to see the garlic and see it burn out — "place it, ask everyone to walk inside" is not
+	playable if only the placer knows where it is. So this part is a normal replicated part, painted
+	`Items.BawangRgb` like the dropped item, and its disappearance is the public clock.
+
+	IT CARRIES NO PLACER, in the Name, in an attribute or in a child value — `placeItem`'s rule, and
+	sharper here: a garlic bulb is placed at a moment, so a `PlacedBy` attribute would be a timestamped
+	record of one player's position lying on the floor of the barrio for fifteen seconds.
+
+	NON-COLLIDING, AND THAT IS THE WHOLE DESIGN IN ONE PROPERTY. If the visible part collided it would
+	block EVERYONE, which is a wall rather than a barrier and would make the loyalty test impossible to
+	fail honestly. The thing that stops the Aswang exists on the Aswang's own client and nowhere else.
+
+	THE BARRIER'S FLOOR IS THE DOORWAY PAD'S OWN `Position.Y`, read rather than assumed, so the
+	barrier follows the map if a future pass ever raises a floor.
+]]
+local function placeGarlic(player: Player, doorway: BasePart)
+	local folder = droppedItems
+
+	if folder == nil then
+		return
+	end
+
+	local part = Instance.new("Part")
+
+	part.Name = Enums.ItemType.Bawang
+	part.Size = Vector3.new(1, 1, 1) -- config-ok: the item's own size, not a balance knob
+	part.Anchored = true
+	part.CanCollide = false
+	part.CanQuery = false
+	part.Color = rgb(Config.Items.BawangRgb)
+	part.Material = Enum.Material.SmoothPlastic
+	-- config-ok: sits on the doorway's threshold where it was placed, not a knob
+	part.Position = doorway.Position + Vector3.new(0, 1, 0)
+
+	--[[
+		A DIFFERENT TAG FROM `DroppedItem`, AND THE DIFFERENCE IS LOAD-BEARING. `placeItem` connects a
+		`Touched` pickup to everything it tags `DroppedItem`; placed garlic must NOT be pickup-able,
+		or a survivor walks through their own barrier's doorway and takes it straight back off the
+		threshold. `PlacedGarlic` carries no player and no round state, so it passes `check:secrecy`
+		on `DroppedItem`'s argument.
+	]]
+	CollectionService:AddTag(part, TAG_GARLIC)
+	part.Parent = folder
+
+	table.insert(barriers, {
+		Doorway = doorway,
+		Part = part,
+		Spec = {
+			X = doorway.Position.X,
+			Y = doorway.Position.Y,
+			Z = doorway.Position.Z,
+			Yaw = math.rad(doorway:GetAttribute("Yaw") :: number? or 0),
+			HalfWidth = ((doorway:GetAttribute("Width") :: number? or 0) / 2)
+				+ Config.Items.GarlicBarrierPadStuds,
+			Height = Config.Items.GarlicBarrierHeight,
+			ExpiresAt = os.clock() + Config.Items.GarlicDuration,
+		},
+	})
+end
+
+--[[
+	BURN-OUT. §4.6: fifteen seconds, then it is gone.
+
+	`task.delay` RATHER THAN A TICK, AND THE FILE'S OWN RULE IS WHY. `ItemService` deleted C13's
+	quarter-second sweep and its closing comment says nothing should bring one back. A burn-out is an
+	event at a known time, so it is scheduled rather than polled — and the sweep re-checks `isLive`
+	rather than trusting the timer, so a barrier cleared early by a phase change cannot be cleared
+	twice.
+]]
+local function expireGarlic()
+	local now = os.clock()
+	local kept: { ActiveBarrier } = {}
+
+	for _, active in barriers do
+		if GarlicBarrier.isLive(active.Spec, now) then
+			table.insert(kept, active)
+		else
+			active.Part:Destroy()
+		end
+	end
+
+	barriers = kept
+end
+
+--[[
+	EVERY BARRIER GONE AT ONCE, for a phase change rather than for a clock. Separate from
+	`expireGarlic` because they answer different questions — "which of these has run out" versus
+	"none of these applies any more" — and a single function taking a flag would be one function with
+	two meanings, which is the argument `ItemDrop` makes for not being folded into `ItemCarry`.
+
+	IT DESTROYS THE PARTS TOO, even though `clearDroppedItems` will sweep the folder at INTERMISSION.
+	`ENDING` reaches here and does not reach that sweep, and a garlic bulb still sitting on a doorway
+	with no barrier behind it is the one thing in this chunk that would be a visible lie.
+]]
+local function clearBarriers()
+	for _, active in barriers do
+		active.Part:Destroy()
+	end
+
+	table.clear(barriers)
+end
```

The handler, beside the existing two:

```diff
+	--[[
+		THE RATE LIMIT IS INLINE AND FIRST, copying the throw and drop handlers above it exactly.
+		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
+		1200 characters of an `.OnServerEvent:Connect(`, by its own admission a proximity tripwire —
+		so a handler that IS limited but does it elsewhere reads as unguarded and fails the build.
+		Consume FIRST, before anything is read.
+
+		THERE IS NO ARGUMENT TO VALIDATE. See the declaration in `Remotes.luau`: the doorway is
+		resolved from the player's own character position and the item from the server's own slot.
+
+		PLACING MAKES NOISE, AND THAT IS A DECISION RATHER THAN AN INHERITANCE. §4.4's four noisy
+		actions include ITEM_USE and the salt throw already emits it — on a MISS as well as a hit,
+		precisely so a throw sounds the same either way. Garlic is the second item use in the game and
+		a silent one would be the only item use that makes no sound, which is
+		`.claude/lessons/absence-is-observable.md` in miniature: a survivor who hears nothing when
+		somebody uses an item learns something about which item it was. Both roles place bawang, both
+		emit the same cue, from the placer's own position.
+	]]
+	Remotes.Get("RequestPlaceGarlic").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestPlaceGarlic") then
+			return
+		end
+
+		local doorway, distance = nearestDoorway(player)
+
+		local verdict = GarlicPlacement.evaluate({
+			Phase = RoundService.GetPhase(),
+			PlayerState = RoundService.GetPlayerState(player),
+			Held = slot[player.UserId],
+			DoorwayDistance = distance,
+			Range = Config.Items.GarlicPlaceRangeStuds,
+			DoorwayOccupied = doorway ~= nil and doorwayOccupied(doorway),
+		})
+
+		--[[
+			NOTHING IS RETURNED TO THE CALLER ON ANY PATH, including OK — the throw handler's rule and
+			the drop handler's, inherited. `GARLIC_DOORWAY_TAKEN` echoed back would be a free map
+			probe; see the union's comment in `Types.luau`.
+		]]
+		if verdict ~= "GARLIC_OK" or doorway == nil then
+			if Config.Debug.VerboseLogging then
+				-- A UserId and a verdict. NEVER the doorway, and never the item: a doorway id beside
+				-- a UserId in the log is a record of where a player was standing, written to disk.
+				print(`[ItemService] Garlic placement refused for {player.UserId}: {verdict}`)
+			end
+
+			return
+		end
+
+		--[[
+			§4.6: "Once used, it's gone." THE SLOT IS SPENT ABOVE THE PLACEMENT so no future early
+			return can skip it, which is the throw handler's ordering and the reason it has it.
+		]]
+		slot[player.UserId] = nil
+		placeGarlic(player, doorway)
+
+		local placerRoot = if player.Character
+			then player.Character:FindFirstChild("HumanoidRootPart")
+			else nil
+
+		if placerRoot ~= nil and placerRoot:IsA("BasePart") then
+			NoiseService.Emit(player, "ITEM_USE", placerRoot.Position)
+		end
+
+		task.delay(Config.Items.GarlicDuration, expireGarlic)
+	end)
```

And the phase sweep, which reuses the split the file already draws:

```diff
 	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
 		clearDroppedItems()
 		table.clear(slot)
 	end
 
 	if phase ~= Enums.RoundPhase.Active then
 		clearAllEffects()
+		--[[
+			BARRIERS DIE THE MOMENT THE ROUND STOPS BEING ACTIVE, on the same side of this split as
+			the glow rather than the same side as the dropped items — and the file's own distinction
+			is the reason. Items lying on the ground during ENDING are scenery; a live barrier is a
+			rule still being applied to one player after the round it belonged to has finished. The
+			garlic PARTS are scenery and are swept above with everything else at INTERMISSION.
+		]]
+		clearBarriers()
 	end
```

#### Step 2.5: Route `Q` by what is in the hand

`Q` already means "use the thing I am holding". The client reads its own `YourCarriedItem` off the
snapshot and fires `RequestPlaceGarlic` instead of `RequestThrowSalt` for BAWANG. A convenience,
never an authority — the server re-derives the item from its own slot table.

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `npm run analyze`

**No new key and no new touch button.** `Q` is already "use the thing in my hand" and §5 puts ~60% of
players on a phone, where every `ContextActionService` button is thumb space. The controller already
routes `Q` two ways — `RequestTrialThrow` inside a trial, `RequestThrowSalt` otherwise — so this is a
third arm on a routing decision that exists, not a second mechanic.

**It asks `pure/ItemUse`, not `== "BAWANG"`.** That is the same call `ItemService`'s throw handler
makes, so the client and the server route on one rule rather than two copies of it, and Step 2.3's
suite covers both.

```diff
 	if TrialController.IsActive() then
 		Remotes.Get("RequestTrialThrow"):FireServer(camera.CFrame.LookVector)
-	else
+	elseif ItemUse.verbFor(UIController.GetCarriedItem()) == "USE_PLACE" then
+		--[[
+			V09, §4.6. THE CLIENT'S CHOICE IS A CONVENIENCE AND NEVER AN AUTHORITY.
+
+			`ClientRoundSnapshot.YourCarriedItem` is the receiving player's OWN slot, which the server
+			owns and pushes every `Round.SnapshotInterval`. A client that guesses wrong — because its
+			snapshot is half a second stale, or because it lied — gets a refusal rather than an
+			advantage: `RequestPlaceGarlic` re-reads the slot on the server and `pure/GarlicPlacement`
+			returns `GARLIC_NOT_HELD`, and `RequestThrowSalt` already asks `ItemUse` before it spends.
+			This is `TrialController.IsActive()`'s own reasoning one line above: "the server re-checks
+			either way, so a client that picks wrongly gets a refusal rather than an advantage".
+
+			NO DIRECTION IS SENT. A placement has no aim — the server resolves the doorway from the
+			placer's own position — so the camera's `LookVector` stops at this branch.
+		]]
+		Remotes.Get("RequestPlaceGarlic"):FireServer()
+	else
 		Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
 	end
```

> `UIController.GetCarriedItem()` is assumed to exist because the HUD already reads
> `ClientRoundSnapshot.YourCarriedItem` (`InputController.luau:309`). **Confirm the accessor's name
> before writing this line** — if the HUD keeps the value private, the smaller change is for
> `InputController` to hold the last snapshot's `YourCarriedItem` itself rather than to widen
> `UIController`'s surface. Recorded in Follow Ups.

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing new reaches a client in this phase. The placed garlic part carries no
  placer in its Name, in an attribute or in a child value; the `PlacedGarlic` tag names no player;
  the `ITEM_USE` noise cue is `NoiseService`'s existing payload, which has no player field and a
  position quantised to `Noise.CueGridStuds`. The refusal verdict is never echoed to the caller.
- **Remote direction** — `RequestPlaceGarlic` is in `EVENTS_UP`, fired with `:FireServer()` from the
  client, listened to with `OnServerEvent` on the server. `check:remotes` in Step 2.1 is the proof.
- **Rate limiting** — `AntiCheatService.Consume(player, "RequestPlaceGarlic")` is the first statement
  inside the connection, before the argument-free body reads anything.
- **Magic numbers** — `GarlicPlaceRangeStuds`, `GarlicDuration`, `GarlicBarrierHeight`,
  `GarlicBarrierPadStuds` and `BawangRgb` all read from `Config`. The two `config-ok` waivers copy
  `placeItem`'s existing ones verbatim and carry the same reason.
- **Phase ownership** — this phase subscribes to `RoundService.PhaseChanged` through the existing
  `onPhaseChanged` and calls `setPhase` nowhere.
- **Player leaving mid-round** — a placer who disconnects leaves a live barrier, and that is CORRECT:
  garlic belongs to the world once placed, and it burns out on its own clock regardless. The
  `PlayerRemoving` handler needs **no** garlic branch, which is worth asserting rather than assuming.
  The **Aswang** leaving is Phase 3's problem, not this one.
- **Strict Luau** — `doorway:GetAttribute("Yaw")` returns `any`; it is cast to `number?` and defaulted,
  never assumed. `GarlicPlacement.evaluate` returns a scalar union and is compared against string
  literals, so nothing widens.
- **Mobile budget** — at most two extra non-colliding, non-querying parts for fifteen seconds each. No
  lights, no particles, and the burn-out is a `task.delay` rather than a loop.
- **Scope** — `check:scope` runs for the first time here. `Doorway`, `Bawang`, `Garlic`, `Barrier` and
  `PlacedGarlic` split into no token on §3's OUT list; confirm rather than assume, since the check
  splits words and `Barrier` is the least obviously safe of the five.

**Issues identified:**

- **`placeGarlic` parents into `droppedItems`, a folder whose name now lies.** Everything else in it
  is a thing a player put on the floor and can pick back up; garlic is neither. Renaming the folder is
  a bigger change than this chunk wants (it is `MonsterService.Corpses`' sibling and other code reads
  it), so the cheapest honest fix is a sentence in the folder's own comment saying what else lives
  there now. Do not add a second folder — a second parent means a second sweep, and the phase sweep
  being one pass is why it is correct.
- **`nearestDoorway` sweeps `GetTagged` on every call, including refused ones.** Nine doorways and a
  budget of three tokens makes that trivially cheap, and caching the pool at `STARTING` the way
  `SearchService` does would add a discovery path that can go stale when nothing in this chunk moves a
  doorway. Left uncached deliberately; recorded so a later reader does not "fix" it.
- **A player can place garlic on a doorway they are standing behind, sealing themselves in.** That is
  §4.6 working: garlic denies a doorway to the Aswang and to nobody else, so the placer walks straight
  back through it. Worth one line in the playtester's brief, because it is the first thing a tester
  will try and it must produce nothing at all.

---

### Phase 3: The silent block — one remote, one client, one invisible part

This is the phase the whole chunk exists for. **Everything it depends on is restated here rather than
cross-referenced**, because `npm run plan:phase` hands a reader this slice and the preamble only ships
with Phase 1.

**The rule, in the spec's own words (§4.6, and `BUILD-PLAN` §V09):** *"A garlic barrier is silent and
invisible in its effect on the Aswang. No knockback, no VFX, no sound — its movement simply does not
carry it through."* And the blockquote that makes it a mechanic rather than a rendering note: garlic
invites a loyalty test — place it, ask everyone to walk in, whoever cannot enter is the Aswang — and
*"it only stays a game if refusing is indistinguishable from being unable… The moment the barrier
plays any effect on the monster, bluffing dies and the test becomes a perfect oracle."*

**Why the barrier is built on the Aswang's own client and nowhere else.** Roblox gives a client
network ownership of its own character, so the character is simulated on that machine. A part created
there by a `LocalScript` is not replicated to the server or to any other client. So the Aswang's own
physics stops the Aswang's own character, and the only thing that leaves that machine is a position —
which is byte-identical to the position of a player who chose to stand still. Telling *that one
client* about the wall leaks nothing new: it already knows its own role from `RoleAssigned`.

**Collision groups were ruled out and must stay ruled out.** `BasePart.CollisionGroup` is a replicated
property on every character part; any client can read another player's. Any scheme where the Aswang's
parts differ from the survivors' is a permanent, map-wide, remote-free role oracle — the shape of
C04's revert bug and C14's `WalkSpeed` brand, both of which shipped with `check:secrecy` green
(`MonsterService.luau:26-29`). There is no per-observer collision group; parts are global.

**What must not appear anywhere in this phase:** a `WalkSpeed` write, an attribute, a
`CollectionService` tag, a `Highlight`, a sound, an animation, a `Humanoid` state change, a camera
effect, a HUD line, or a `BodyVelocity`/`AlignPosition` on the character. **Including for the Aswang
itself** — `SmokeController`'s header has the argument: the moment feedback exists on screen, a screen
recording of an Aswang's client is a document of the system and a streamer's overlay is a permanent
one. The Aswang gets nothing. Its movement simply does not carry it through.

#### Step 3.1: Declare `GarlicBarriers` in the down-list, with the payload it may carry

`FireClient` to exactly the Aswang. A full snapshot of live barriers, not a delta — a snapshot cannot
desync and self-heals on a rejoin.

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

```diff
 	"SmokeBurst",
+	--[[
+		V09, §4.6. FireClient to the ONE player who is the Aswang. Never FireAllClients — there is no
+		broadcast form of this payload, and adding one would not be an optimisation, it would hand
+		every client a live list of where the survivors are fortifying.
+
+		WHAT A SECOND CLIENT LEARNS FROM THIS REMOTE: nothing, because it never receives it. The
+		PUBLIC half of garlic needs no remote at all and never gets one — a bulb appears on a doorway
+		and fifteen seconds later it is gone, and both of those replicate as geometry. That is the
+		whole of what the barrio is told, and it is exactly what §4.6's loyalty test needs: everyone
+		can see the garlic and everyone can see the clock.
+
+		IT IS THE ONLY REMOTE IN THIS GAME WHOSE RECIPIENT IS CHOSEN BY ROLE RATHER THAN BY ACTION,
+		and that difference is worth naming rather than glossing. `FeedUpdate` and `CamouflageUpdate`
+		also reach only the Aswang, but they are replies to that player's own request; this one is
+		fired UNPROMPTED, triggered by a survivor's placement. The safety argument is nonetheless
+		`RoleAssigned`'s and it is unchanged: it is fired to a single player, the payload carries no
+		role and no UserId, and the set of clients that learn anything is the set that already knew.
+		The recipient is resolved server-side from `RoundService.GetAswangUserId()`.
+
+		THE PAYLOAD NAMES NO PLACER AND NO DOORWAY. `Types.GarlicBarrierSpec` is a position, a yaw, a
+		width, a height and a remaining duration. With no player field there is nothing that would
+		hand the monster a survivor's movements; with no doorway id there is no key on which a
+		compromised Aswang client could log, difference or accumulate anything. It learns where the
+		garlic is, which it learns by looking at the doorway.
+
+		A FULL SNAPSHOT, NOT A DELTA. `RequestSearch`/`RequestCancelSearch`'s header is the argument
+		inverted: two messages for one state are how a client and a server come to disagree about it.
+		A dropped "added" leaves the Aswang walking through garlic; a dropped "expired" leaves it
+		walled out for the rest of the round. A snapshot is idempotent, and re-sending it on
+		`CharacterAdded` is the entire rejoin path.
+
+		IT IS NOT AN AUTHORITY. A client that deletes its barriers walks through, and that is what
+		Phase 4's server-side breach test is for. This remote is what the block LOOKS like, never what
+		makes it — `SmokeController`'s header states the same property about the smoke cloud.
+	]]
+	"GarlicBarriers",
 }
```

#### Step 3.2: The server's send path — to one player, on every change and on every spawn

`ItemService` builds the snapshot and fires it to `RoundService.GetAswangUserId()` alone, on
placement, on burn-out, on the phase sweep, on `RoleAssigned`, and on that player's `CharacterAdded`.

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:secrecy`

```diff
+local garlicRemote = Remotes.Get("GarlicBarriers")
+
+--[[
+	V09, §4.6. SEND THE ASWANG THE LIST OF LIVE BARRIERS, AND SEND IT TO NOBODY ELSE.
+
+	ONE `FireClient`, NEVER `FireAllClients`. `check-secrecy.mjs` allowlists two remotes to carry the
+	secret and this is not one of them, which is correct — the PAYLOAD carries no role. What is
+	role-derived is the RECIPIENT, and that is `FeedUpdate`'s and `CamouflageUpdate`'s arrangement
+	exactly: the server resolves who from `RoundService.GetAswangUserId()` and the wire says nothing.
+
+	EVERY CALLER IS A STATE CHANGE, NOT A CLOCK. Placement, burn-out, the phase sweep, and the
+	Aswang's own `CharacterAdded`. There is no periodic push: the Aswang's client owns its barriers'
+	countdowns from `SecondsRemaining` and re-syncs whenever the server's list actually moves. A
+	periodic push would be a fixed-rate signal arriving at exactly one client for the whole round,
+	which is a shape worth not building even though nobody else can observe it.
+
+	NIL-SAFE IN BOTH DIRECTIONS. No Aswang assigned (IDLE, INTERMISSION) sends nothing; an Aswang who
+	has left the server resolves to no Player and sends nothing. Neither is an error — `RoundService`
+	owns the roster and this function is a renderer for it.
+
+	IT SENDS AN EMPTY LIST RATHER THAN SKIPPING. `clearBarriers` must reach the client or the last
+	round's walls stand in the next one, and "no barriers" is a state the snapshot has to be able to
+	express. That is the half a delta protocol would have got wrong.
+]]
+local function pushBarriers()
+	local aswangUserId = RoundService.GetAswangUserId()
+
+	if aswangUserId == nil then
+		return
+	end
+
+	local player = Players:GetPlayerByUserId(aswangUserId)
+
+	if player == nil then
+		return
+	end
+
+	local now = os.clock()
+	local specs: { Types.GarlicBarrierSpec } = {}
+
+	for _, active in barriers do
+		table.insert(specs, {
+			Position = Vector3.new(active.Spec.X, active.Spec.Y, active.Spec.Z),
+			Yaw = active.Spec.Yaw,
+			Width = active.Spec.HalfWidth * 2,
+			Height = active.Spec.Height,
+			SecondsRemaining = GarlicBarrier.secondsRemaining(active.Spec, now),
+		})
+	end
+
+	local payload: Types.GarlicBarriersPayload = { Barriers = specs }
+
+	garlicRemote:FireClient(player, payload)
+end
```

Three call sites, and each is a place the list actually changed:

```diff
 	slot[player.UserId] = nil
 	placeGarlic(player, doorway)
+	pushBarriers()
```

```diff
 	barriers = kept
+	pushBarriers()
 end
```

```diff
 	table.clear(barriers)
+	pushBarriers()
 end
```

And the fourth, in the existing `watchCharacter`, which is why this chunk adds no new
`CharacterAdded` connection:

```diff
 local function watchCharacter(player: Player, character: Model)
+	--[[
+		V09. A RESPAWN OR A REJOIN REBUILDS THE ASWANG'S BARRIERS FROM THE SERVER'S LIST.
+
+		The barrier parts live in the Aswang's own client's workspace and are destroyed with its
+		character's session; without this line an Aswang who respawns mid-round walks through garlic
+		with nothing anywhere reporting a fault, and the symptom is "bawang stopped working" in one
+		round out of ten. `pushBarriers` filters by role itself, so this call is unconditional and
+		does nothing for the four players it does not concern.
+	]]
+	pushBarriers()
+
```

> `pushBarriers` is called unconditionally from `watchCharacter` **on purpose**. A `if player.UserId
> == RoundService.GetAswangUserId()` guard here would be a role branch in the character-spawn path of
> a service every player reaches — the exact shape `ItemCarry`'s header refuses for the slot table.
> The role test belongs in one function, and it is inside `pushBarriers`.

#### Step 3.3: `GarlicController` — the invisible wall that exists on one machine

Rebuilds local barrier parts from each snapshot. Anchored, `CanCollide = true`, `Transparency = 1`,
`CanQuery`/`CanTouch`/`CastShadow` off. No HUD, no line, no sound — for the Aswang either.

**File:** `src/client/Controllers/GarlicController.luau`
**Verify:** `npm run analyze`

```diff
+--!strict
+--[[
+	GarlicController — the wall that exists on exactly one machine. (V09, §4.6)
+
+	THIS FILE IS THE MECHANIC AND IT IS ALSO THE SECRECY ARGUMENT, so read both before changing a
+	line of it.
+
+	§4.6: "A garlic barrier is silent and invisible in its effect on the Aswang. No knockback, no VFX,
+	no sound — its movement simply does not carry it through." That sentence is a MECHANIC, not a
+	rendering note. Garlic invites a loyalty test — place it, ask everyone to walk in, whoever cannot
+	enter is the Aswang — and the test only stays a game if REFUSING is indistinguishable from BEING
+	UNABLE. The moment the barrier plays any effect on the monster, bluffing dies and the test becomes
+	a perfect oracle.
+
+	SO THE BARRIER IS A PART THIS CLIENT CREATES FOR ITSELF. Roblox gives a client network ownership
+	of its own character, so the character is simulated here; a part created here by a LocalScript is
+	not replicated to the server or to any other client. The Aswang's own physics stops the Aswang's
+	own character, and the only thing that leaves this machine is a position — which is the same
+	position a player who chose to stand still produces. There is no property on the character to
+	read, no remote for a third client to intercept, and nothing for `check:secrecy` to see because
+	there is nothing on the wire.
+
+	WHAT THIS FILE MUST NEVER DO, and the list is the deliverable: no `WalkSpeed` write, no attribute,
+	no CollectionService tag, no Highlight, no sound, no animation, no Humanoid state change, no
+	camera effect, no BodyVelocity or AlignPosition, and NO HUD LINE — not even for the Aswang.
+	`SmokeController`'s header has the reason: the moment feedback exists on screen, a screen
+	recording of an Aswang's client is a document of the system and a streamer's overlay is a
+	permanent one. Every other controller in this folder that speaks to the Aswang uses
+	`OnboardingController.ShowLine`; this one deliberately does not.
+
+	COLLISION GROUPS WERE RULED OUT AND MUST STAY RULED OUT. `BasePart.CollisionGroup` is a replicated
+	property on every character part and any client can read another player's. A scheme that put the
+	Aswang's parts in a different group would be a permanent, map-wide, remote-free role oracle — the
+	shape of C04's revert bug and C14's WalkSpeed brand, both of which shipped green.
+
+	IT OWNS NO TRUTH. A player who deletes this script, or never receives a payload, walks through
+	garlic — and the server notices, because `ItemService` compares the positions it sampled against
+	`pure/GarlicBarrier.crossed`. This file is what the block LOOKS LIKE to physics; it is never what
+	makes it. That is `SmokeController`'s property restated, and it is why the barrier is safe to hand
+	to a client at all.
+]]
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Remotes = require(Shared.Remotes)
+local Types = require(Shared.Types)
+
+local GarlicController = {}
+
+--[[
+	ONE LOCAL FOLDER, SO A REBUILD IS ONE PASS. `MonsterService.Corpses` and `ItemService
+	.DroppedItems` are the server-side shape of the same idea, and the reason is the same: a phase
+	change clears everything with a single loop rather than with a bookkeeping table.
+
+	IT IS CREATED ON THE CLIENT, so it never replicates. Parenting it to `workspace` rather than to
+	`Camera` is deliberate — parts under `Camera` are ignored by physics, and this part's entire job
+	is to be collided with.
+]]
+local barrierFolder: Folder? = nil
+
+local function rebuild(payload: Types.GarlicBarriersPayload)
+	local folder = barrierFolder
+
+	if folder == nil then
+		return
+	end
+
+	folder:ClearAllChildren()
+
+	for _, spec in payload.Barriers do
+		local part = Instance.new("Part")
+
+		part.Name = "GarlicBarrier"
+		part.Anchored = true
+		part.CanCollide = true
+		--[[
+			INVISIBLE, AND NOT AS A COURTESY. A visible wall on the Aswang's screen would be feedback,
+			and §4.6 forbids the barrier producing any. The monster experiences it the way the spec
+			describes it: its movement does not carry it through, and it is never told why.
+		]]
+		part.Transparency = 1
+		--[[
+			QUERY AND TOUCH OFF, SHADOW OFF. A raycast is how MonsterService decides line of sight for
+			a kill and how ItemService resolves a throw — those run on the SERVER, which cannot see
+			this part, but a client-side raycast that hit an invisible wall would be a way for a
+			modified client to map its own barriers, and `CanQuery = false` costs nothing to close it.
+			`CanTouch = false` keeps it out of every `Touched` connection in the game, including the
+			dropped-item pickup.
+		]]
+		part.CanQuery = false
+		part.CanTouch = false
+		part.CastShadow = false
+		part.Size = Vector3.new(spec.Width, spec.Height, 0.5)
+		--[[
+			THE PART IS BUILT FROM ITS FLOOR UP, because `GarlicBarrierSpec.Position` is the doorway
+			pad's position on the ground and `Height` runs upward from it — the same convention
+			`pure/GarlicBarrier.crossed` tests against, stated in that module's `Barrier` type. A
+			centre-based placement here and a floor-based test there would leave the server checking a
+			plane half a barrier below the wall the client is standing behind.
+		]]
+		part.CFrame = CFrame.new(spec.Position + Vector3.new(0, spec.Height / 2, 0))
+			* CFrame.Angles(0, spec.Yaw, 0)
+
+		--[[
+			A LOCAL BURN-OUT AS WELL AS THE SERVER'S. The server re-sends the snapshot on every change
+			including expiry, so this is redundant on a healthy connection — and it is the difference
+			between a dropped packet costing fifteen seconds and costing the rest of the round. It
+			destroys only this part, so a rebuild that has already replaced it destroys nothing.
+		]]
+		task.delay(spec.SecondsRemaining, function()
+			part:Destroy()
+		end)
+
+		part.Parent = folder
+	end
+end
+
+function GarlicController.Init() end
+
+function GarlicController.Start()
+	local folder = Instance.new("Folder")
+
+	folder.Name = "GarlicBarriers"
+	folder.Parent = workspace
+	barrierFolder = folder
+
+	--[[
+		EVERY CLIENT LOADS THIS FILE AND CONNECTS THIS HANDLER. Four of five never receive a payload,
+		so the branch never runs, and nothing about that is observable to anyone but themselves —
+		`SmokeController`'s header makes the same argument for `CamouflageUpdate`. The asymmetry that
+		WOULD leak is on the server side, and there is none: `GarlicBarriers` is FireClient to one
+		player, never a broadcast, so no client can time or count another's barriers.
+	]]
+	Remotes.Get("GarlicBarriers").OnClientEvent:Connect(function(payload: Types.GarlicBarriersPayload)
+		rebuild(payload)
+	end)
+
+	--[[
+		A RESPAWN TAKES THE FOLDER'S CONTENTS WITH IT ONLY IF THE FOLDER WAS UNDER THE CHARACTER, and
+		it is not — it is under `workspace`, so the barriers survive a respawn on this side. The
+		SERVER re-pushes anyway on `watchCharacter`, which is the authority; this connection exists so
+		the folder itself is rebuilt if anything ever removes it.
+	]]
+	Players.LocalPlayer.CharacterAdded:Connect(function()
+		if barrierFolder == nil or barrierFolder.Parent == nil then
+			local replacement = Instance.new("Folder")
+
+			replacement.Name = "GarlicBarriers"
+			replacement.Parent = workspace
+			barrierFolder = replacement
+		end
+	end)
+end
+
+return GarlicController
```

**And the line without which none of the above runs** — `src/client/init.client.luau` holds an
explicit ordered list of controller names (`"SmokeController"` is at line 74) and loads only what is
in it. A controller that exists on disk and is not in that list is a file Rojo syncs and nothing ever
calls, with no error anywhere:

```diff
 	"SmokeController",
+	-- V09. The Aswang's own barriers. Loaded by every client and does nothing for four of five —
+	-- see the file's header for why that asymmetry is not observable.
+	"GarlicController",
```

> **Two Roblox behaviours this plan has NOT confirmed in this codebase**, both flagged in Follow Ups
> and both on the playtester's list: (1) that a part created by a `LocalScript` under `workspace` is
> never replicated to the server or to other clients, and (2) that such a part collides with the local
> player's own character. Both are standard client-ownership behaviour and neither appears anywhere in
> this repo today. If (2) turns out false the whole mechanism changes and the fallback is in Follow
> Ups; if (1) turns out false the mechanism is a secrecy failure and must not ship.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the one new payload reaches one client. Read the whole of `GarlicController`
  for a `WalkSpeed`, an attribute, a tag, a `Highlight`, a sound or a HUD line; there must be none,
  including for the Aswang. On the server side, check that no call site of `pushBarriers` is wrapped
  in a role branch — the role test lives in one function and putting a second one in the spawn path
  would be a role-shaped `if` in a path every player reaches.
- **Remote direction** — `GarlicBarriers` is in `EVENTS_DOWN`, fired with `:FireClient` on the server,
  listened to with `OnClientEvent` on the client. There must be no `FireAllClients` anywhere near it.
- **Rate limiting** — no new `OnServerEvent` handler in this phase; `RequestPlaceGarlic`'s is Phase 2's
  and is already budgeted.
- **Magic numbers** — the barrier's width, height and yaw all arrive in the payload, which the server
  derived from `Config.Items` and the doorway's attributes. The `0.5` thickness is the part's own
  geometry rather than a balance knob and takes a `config-ok` waiver with that reason.
- **Phase ownership** — the client never sets a phase. Barriers are cleared by the server's sweep and
  by their own durations.
- **Player leaving mid-round** — **the Aswang leaving is this phase's edge case.** `pushBarriers`
  resolves the recipient through `Players:GetPlayerByUserId` and sends nothing when they are gone; a
  round that ends `ABORTED` because the Aswang disconnected reaches `clearBarriers` through the phase
  sweep. The Aswang **respawning** is the one that will actually happen, and `watchCharacter` is
  where it is handled.
- **Strict Luau** — `OnClientEvent`'s handler parameter is whatever the server sent; typing it as
  `Types.GarlicBarriersPayload` is an assertion rather than a check, and on a down-remote from our own
  server that is the convention every other controller here follows. Do not widen it to `unknown`
  without widening the others.
- **Mobile budget** — at most two invisible, non-querying, non-touching, shadowless parts on one
  device for fifteen seconds. No lights, no particles, no per-frame work, and no `RenderStepped`.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **A modified client walks through, and this phase does not stop it.** That is by construction: the
  block is on a machine the server does not control. Phase 4 is the backstop and it is not optional —
  this phase alone ships a mechanic any executor turns off. Do not merge the two phases and do not
  ship Phase 3 without Phase 4.
- **A rejoining Aswang has a gap between `CharacterAdded` and the payload arriving.** One round trip,
  during which it can walk through garlic. It is bounded, it is not exploitable on purpose (a player
  cannot choose when their character loads), and closing it would mean holding the character still,
  which is an observable effect. Accepted; recorded so it is not rediscovered as a bug.
- **`spec.Yaw` arrives in radians and `CFrame.Angles` wants radians, but the map attribute is in
  degrees.** The conversion happens once, in `placeGarlic`, and if it is done twice or not at all the
  barrier is rotated wrongly and the Aswang walks past its edge — with no error anywhere. The
  playtester's brief must include a screenshot of a blocked Aswang at an **E or W** doorway (yaw 90)
  as well as an N or S one (yaw 0), because a missing conversion is invisible at yaw 0.

---

### Phase 4: The server's authority — a breach is the only thing that is allowed to show

**Restated here because this slice is read alone.** The garlic block is a collidable part that exists
only in the Aswang's own client's `workspace` (Phase 3). That is what makes it silent: nothing on the
character changes, nothing crosses the wire to a third party, and the only thing that replicates is a
position identical to a player standing still. It is also what makes it **not an authority** — a
client that deletes the part walks through, and the server cannot see the part.

**The asymmetry this phase rests on:** §4.6's blockquote binds the **honest** case. An honest client is
stopped by its own physics and never crosses the plane, so the correction below never runs for it. The
only way to produce a visible correction is to have ignored a barrier, which no honest client does. A
rubber-band is therefore acceptable **here and nowhere else in the chunk**.

**What a third player's client can observe, in each case:**

| Case | Observable |
| --- | --- |
| Survivor walks through | Nothing. No remote reaches them, no property changes, no correction runs. |
| **Aswang honestly blocked** | Its position stops at the threshold. Nothing else. No `WalkSpeed`, no `CollisionGroup`, no attribute, no tag, no `Highlight`, no sound, no animation state. |
| **Aswang declines to walk in** | Identical to the row above. This is the row the mechanic exists for. |
| Aswang on a modified client crosses | The server restores the last position it *saw* outside the plane; a third player sees a rubber-band. Reachable only by ignoring a barrier. |
| Garlic placed / burns out | Public geometry plus the `ITEM_USE` cue the salt throw already emits. Identical whoever placed it. |

#### Step 4.1: Wire `GarlicBarrier.crossed` as a bounded breach sampler

Runs only while at least one barrier is live, at `Config.Items.GarlicBreachSampleInterval`, over the
Aswang's replicated root position. The suite gains the crossing grid.

**File:** `tests/garlic-barrier.test.luau`
**Verify:** `lune run tests/garlic-barrier.test.luau`

The suite gains the cases the service will actually hit, and they are the ones that decide whether an
honest Aswang is ever corrected. **Each of these must return `false`:** a character standing in the
threshold with both samples on the same side; a sample landing exactly on the plane; a destination
inside `tolerance` of the plane; a crossing whose lateral offset exceeds `HalfWidth` (walking around
the house and through a different wall of the same infinite plane); a crossing above `Height`; and a
crossing below the barrier's floor. **Only one shape returns `true`:** a strict sign change, past
tolerance, inside the width, within the height — proven at yaw `0` and at yaw `math.pi / 2` so the
axis convention is tested rather than assumed.

```diff
+--[[
+	V09, §4.6. THE BREACH SAMPLER, AND ITS ONLY JOB IS TO NOT FIRE ON HONEST PLAYERS.
+
+	IT IS A BOUNDED LOOP, NOT A TICK, AND `ItemService`'S OWN RULE IS WHY. This file deleted C13's
+	quarter-second sweep and its closing comment says nothing should bring one back. This runs only
+	while at least one barrier is live — started by the first placement, stopped when the list empties
+	— so its worst case is `Config.Items.GarlicDuration` seconds of sampling ONE player's root
+	position against at most two planes. That is a bound on the exception rather than an exception to
+	the rule, and if it ever becomes unbounded the rule has been broken.
+
+	IT SAMPLES ONE PLAYER. Survivors are not blocked by garlic and are never tested against it; there
+	is no per-player state here and no roster.
+
+	`lastSample` IS A POSITION THE SERVER SAW, WHICH IS WHY THE CORRECTION CANNOT TELEPORT ANYONE
+	SOMEWHERE THEY HAVE NEVER BEEN. Step 4.2 restores it verbatim.
+]]
+local breachRunning = false
+local lastSample: Vector3? = nil
+
+local function sampleBreaches()
+	if breachRunning then
+		return
+	end
+
+	breachRunning = true
+	lastSample = nil
+
+	task.spawn(function()
+		while #barriers > 0 do
+			local aswangUserId = RoundService.GetAswangUserId()
+			local player = if aswangUserId ~= nil
+				then Players:GetPlayerByUserId(aswangUserId)
+				else nil
+			local character = if player ~= nil then player.Character else nil
+			local root = if character ~= nil
+				then character:FindFirstChild("HumanoidRootPart")
+				else nil
+
+			if root ~= nil and root:IsA("BasePart") then
+				local from = lastSample
+				local to = root.Position
+
+				if from ~= nil then
+					checkBreach(root, from, to)
+				end
+
+				lastSample = to
+			else
+				--[[
+					NO CHARACTER MEANS NO BASELINE. Dropping the sample rather than keeping a stale one
+					is what stops a respawn on the far side of a doorway reading as a crossing — the
+					single most likely way this loop would brand an honest player.
+				]]
+				lastSample = nil
+			end
+
+			task.wait(Config.Items.GarlicBreachSampleInterval)
+		end
+
+		breachRunning = false
+		lastSample = nil
+	end)
+end
```

`sampleBreaches()` is called from `placeGarlic`'s call site, immediately after `pushBarriers()`. It
returns instantly when a loop is already running, so two barriers do not start two loops.

#### Step 4.2: The correction, and the tolerance that keeps it off honest clients

On a crossing past tolerance the server restores the last position it *saw* outside the plane — never
a position the character was never at. Everything it reads comes from `Config`.

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:config`

```diff
+--[[
+	V09, §4.6. THE ONE THING IN THIS CHUNK THAT IS ALLOWED TO BE SEEN, AND ONLY BY CHEATING.
+
+	READ THE BLOCKQUOTE BEFORE CHANGING THIS FUNCTION. §4.6: "The moment the barrier plays any effect
+	on the monster, bluffing dies and the test becomes a perfect oracle." A server correction that
+	snaps a character back IS an effect, and a third player watching a doorway would read it exactly
+	as the oracle the spec forbids.
+
+	THE ASYMMETRY THAT MAKES IT SAFE ANYWAY: that sentence binds the HONEST case. An honest client is
+	stopped by its own barrier and never crosses the plane, so this function never runs for it. The
+	only way to be corrected here is to have ignored a barrier, which no honest client does.
+
+	SO EVERY LINE IS WRITTEN TO FAIL TOWARD DOING NOTHING:
+
+	  · `crossed` needs a STRICT sign change, so a character standing in the threshold is not a breach.
+	  · It needs the destination more than `GarlicBreachToleranceStuds` PAST the plane, so lag,
+	    a corpse's physics or a shove is not a breach.
+	  · It needs the crossing point inside the doorway's width and under the barrier's height.
+	  · The restore uses `from` — a position the server SAW on its previous sample — never a computed
+	    one. It cannot put the Aswang somewhere it has never been, which is the failure mode that
+	    would turn a false positive from an annoyance into a report.
+
+	IT WRITES `CFrame` AND NOTHING ELSE. No WalkSpeed, no anchor, no network-ownership change, no
+	Humanoid state. C14's WalkSpeed brand and C04's revert bug are what a "while we are here" property
+	write becomes six weeks later, and both shipped with `check:secrecy` green.
+
+	`SetNetworkOwner(nil)` WAS CONSIDERED AND REJECTED. Server-simulating the Aswang's character would
+	make the block authoritative — and it would make ONE character in the round move differently for
+	the whole round, felt by its owner as input lag and plausibly readable by others in its motion.
+	That trades a fifteen-second observable for a five-minute one.
+]]
+local function checkBreach(root: BasePart, from: Vector3, to: Vector3)
+	local a: GarlicBarrier.Vec3 = { X = from.X, Y = from.Y, Z = from.Z }
+	local b: GarlicBarrier.Vec3 = { X = to.X, Y = to.Y, Z = to.Z }
+	local now = os.clock()
+
+	for _, active in barriers do
+		if not GarlicBarrier.isLive(active.Spec, now) then
+			continue
+		end
+
+		local tolerance = Config.Items.GarlicBreachToleranceStuds
+
+		if GarlicBarrier.crossed(active.Spec, a, b, tolerance) then
+			--[[
+				BACK TO WHERE IT WAS, ORIENTED AS IT IS. Position only: taking the character's current
+				`CFrame.Rotation` keeps the camera and the facing untouched, so the correction is a
+				position restore rather than a re-aim. A re-aim would be a second observable on top of
+				the first, and this function is already spending the only one it is allowed.
+			]]
+			root.CFrame = CFrame.new(from) * root.CFrame.Rotation
+
+			if Config.Debug.VerboseLogging then
+				-- No UserId. There is exactly one player this can ever be, so printing the id would
+				-- write the round's secret into the server log for anything that reads it later.
+				print("[ItemService] Garlic breach corrected")
+			end
+
+			return
+		end
+	end
+end
```

> `checkBreach` must be **declared above** `sampleBreaches`, which calls it. The diff in Step 4.1
> shows the call site; Luau has no hoisting for locals and the analyzer will name the wrong file if
> this is got wrong.

**Analytics: `garlic_placed` and `garlic_blocked` land in V19, not here — and V19 needs one finding
from this chunk.** `AnalyticsService` is a stub today (`Init()` and `Start()` are empty, with a
`TODO(M11)`), and `BUILD-PLAN` §V19 is "Badges and analytics, remapped". Emitting from here would
build V19's transport inside V09.

The finding V19 must not have to rediscover: **`garlic_placed` is trivially server-side — it is one
line in the placement handler. `garlic_blocked` is not observable to the server at all.** An honest
block happens inside the Aswang's client's physics and produces no event, no message and no state
change; the server sees a character that stopped moving, which is what a player standing still also
looks like. That is not an oversight, it is this chunk's central property. The closest honest
server-side proxy is *"the Aswang's sampled position came within N studs of a live barrier's outside
face during that barrier's lifetime and never crossed it"*, which `sampleBreaches` is already
positioned to compute. It counts approaches, not blocks, and V19 must label it as such — an event
named `garlic_blocked` that actually counts approaches would be a number nobody could interpret and
§11's whole point is that you cannot tune what you do not measure.

#### Step 4.3: The whole gate, and the header that now describes a different service

`ItemService`'s header says bawang is "CARRIED AND DROPPED ONLY in V08 — the doorway block is V09 and
the strike is V10, and neither is half-built here." That sentence is now false and the header is the
first thing anyone reads. Rewrite it to name the four things this file does, and run the full gate:
analyze, lint, format, all five checks, every Lune suite and the harness.

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run verify`

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the correction writes `CFrame` and nothing else. Confirm there is no
  `WalkSpeed`, no `Anchored`, no `SetNetworkOwner`, no `Humanoid` state change and no attribute
  anywhere in the breach path, and that the verbose log prints **no UserId** — this is the one code
  path in the game reachable by exactly one player, so any identifier in it is the secret written to
  a log.
- **Remote direction** — this phase adds no remotes. The breach path fires nothing to anybody, which
  is the point: there is no "you were corrected" message in either direction.
- **Rate limiting** — no new `OnServerEvent` handler. The sampler is server-initiated and its rate is
  `Config.Items.GarlicBreachSampleInterval`, not a client's.
- **Magic numbers** — the tolerance and the interval read from `Config.Items`. There must be no bare
  number in `checkBreach` at all.
- **Phase ownership** — the sampler exits when `#barriers` reaches zero, which the phase sweep causes
  by calling `clearBarriers`. It never reads or writes the phase itself.
- **Player leaving mid-round** — the Aswang leaving mid-sample resolves to no `Player`, which drops
  `lastSample` and the loop keeps running harmlessly until the barriers expire. The Aswang
  **respawning** must drop `lastSample`, or a spawn on the far side of a doorway reads as a crossing
  and corrects an honest player. That is the single most likely false positive in the chunk and the
  `else` branch of the sampler is the only thing preventing it — check it explicitly.
- **Strict Luau** — `GarlicBarrier.Vec3` is a plain table built at the boundary from a `Vector3`, the
  way `ItemService.vec` already does it for `ItemThrow`. Reuse the existing helper rather than adding
  a second one.
- **Mobile budget** — the sampler is server-side. Nothing new runs on any client in this phase.
- **Scope** — nothing from §3's OUT list. An anti-cheat correction is not a "ban system"; it writes
  one property and keeps no record.

**Issues identified:**

- **A false positive brands an honest Aswang, and it is the worst outcome available in this chunk.**
  Every guard is written to fail toward doing nothing, but the residual risk is real: a shove from a
  corpse's physics, a laggy sample pair straddling the plane by more than the tolerance, or an
  unusual spawn. **The V16 playtest is where this is answered**, and the question to bring to it is
  "did anyone ever see a monster snap backwards", not "does garlic work". If it happens even once,
  the correct response is to raise `GarlicBreachToleranceStuds` or to delete the correction and accept
  the bypass — never to add feedback that would make the snap "look intentional".
- **A patient exploiter beats the sampler by moving slowly.** `crossed` needs the destination more
  than `GarlicBreachToleranceStuds` past the plane in one sample interval; a client that noclips
  forward at less than that per 0.25s crosses without ever tripping it. Closing it needs a swept
  volume rather than a segment test, or a "you were inside the wall" occupancy test — both of which
  raise the false-positive risk this chunk is most afraid of. Left open deliberately: the prize is
  fifteen seconds of a doorway, and the cost of closing it is the observable the whole chunk exists
  to avoid.
- **The sampler's `while #barriers > 0` reads a local that `expireGarlic` REASSIGNS** (`barriers =
  kept`) rather than mutates. That works because both close over the same upvalue, but it is exactly
  the kind of thing a later refactor breaks silently — pick one style, mutation or reassignment, and
  use it in all three functions.

---

## 3. Related Files

Every file read while planning has an annotated review in `references/`.

| File | Role in this plan | Review |
| --- | --- | --- |
| `src/server/Services/ItemService.luau` | The slot, the placement path, the two existing handlers, the "no tick" rule | `ItemService-review.luau` |
| `src/server/Services/MonsterService.luau` | The replicated-property leak argument this chunk inherits; the Aswang's server-side state | `MonsterService-review.luau` |
| `src/shared/pure/ItemUse.luau` | The V08→V09 boundary this chunk moves | `ItemUse-review.luau` |
| `src/shared/pure/ItemCarry.luau` | The verdict shape, the order rule, the fail-closed limit guard | `ItemCarry-review.luau` |
| `src/shared/Remotes.luau` | The argument-free convention and the per-remote secrecy argument | `Remotes-review.luau` |
| `src/shared/Types.luau` | `ClientRoundSnapshot`'s contract, the `ITEM_`/`GARLIC_` prefix rule | `Types-review.luau` |
| `src/shared/Config.luau` | The Items block, invariant 4's comment, the AntiCheat budgets | `Config-review.luau` |
| `tools/greybox/barrio.luau` | What a doorway is, and what tagging one costs | `barrio-review.luau` |
| `src/client/Controllers/InputController.luau` | The `Q` routing this chunk adds a third arm to | `InputController-review.luau` |
| `src/client/Controllers/SmokeController.luau` | The precedent for an Aswang-only controller, and the no-HUD rule | `SmokeController-review.luau` |
| `src/server/Services/AnalyticsService.luau` | Why `garlic_placed` / `garlic_blocked` are deferred | `AnalyticsService-review.luau` |
| `tests/anti-cheat-budgets.test.luau` | The hand-copied list a new up-remote must join | `anti-cheat-budgets.test-review.luau` |

Read but not reviewed, because nothing in them constrains this plan beyond what is quoted above:
`src/shared/Enums.luau`, `src/shared/pure/ItemDrop.luau`, `src/shared/pure/ItemThrow.luau`,
`tests/config.test.luau`, `tests/barrio-contract.test.luau`, `tests/barrio-interiors.test.luau`,
`src/client/init.client.luau`, `.claude/scripts/check-secrecy.mjs`,
`.claude/lessons/pure-module-unions-widen-in-lists.md`.

## 4. Follow Ups

### Questions / Clarifications

1. **Two Roblox behaviours are assumed and appear nowhere in this repo.** Hard Rule 1 says say so
   rather than invent, so: (a) a `BasePart` created by a `LocalScript` under `workspace` is not
   replicated to the server or to other clients, and (b) such a part collides with the local player's
   own character. Both are standard client-network-ownership behaviour and the whole mechanism rests
   on them. **The playtester must confirm both before Phase 4 is trusted:** (a) with a
   `search_game_tree` / `inspect_instance` on the server's `workspace` while a client barrier exists,
   and (b) with a screenshot of the Aswang stopped at a doorway. If (b) is false the mechanism must
   change; if (a) is false it must not ship.
2. **`BasePart.CollisionGroup`'s replication is asserted, not measured.** The plan rules collision
   groups out on the premise that a third client can read another player's `CollisionGroup`. If that
   premise is wrong the option reopens, so the premise is worth one probe rather than one paragraph:
   a `LocalScript` on a third client printing `CollisionGroup` for every descendant of another
   player's character. `exploit-auditor` should be asked for the answer, not the reasoning.
3. **`UIController.GetCarriedItem()` is assumed to exist.** The HUD reads
   `ClientRoundSnapshot.YourCarriedItem` (`InputController.luau:309`) but the accessor's name was not
   confirmed. If it is private, have `InputController` keep the last snapshot's value itself rather
   than widening `UIController`'s surface for one branch.
4. **`building()`'s half-extents are read from its signature, not from running it.** Every doorway pad
   is offset if `hw`/`hd` are not `w / 2` and `d / 2`. The new suite cannot catch it because it
   compares the same two literals; the playtester's first artifact should be a `Doorway` pad selected
   in a doorway in Studio.
5. **`anchor()`'s comment becomes partly false.** It explains its fixed 6-stud pad as "a reading of a
   Config range"; that is true for the three tags it already carries and not for `Doorway`, which uses
   only the pad's `CFrame` and attributes. One sentence, not a refactor.
6. **Two files in `src/shared/` contradict each other about whether the Aswang carries items, and
   V09 is the chunk that trips over it.** `Types.luau:512-514` says *"The Aswang carries nothing — the
   three items are the survivors' (§4.6) — so its slot is `nil`, which is also what an empty-handed
   survivor's slot is."* `ItemCarry.luau:24-31` says the opposite and is right: *"§4.4 has the Aswang
   searching on identical rules, so the Aswang DOES reach this module, DOES get OK, and DOES fill a
   slot… an empty-handed survivor and the Aswang must be indistinguishable, which they are only if
   the monster can genuinely hold things."* The **field** is safe under either reading, so nothing is
   broken today — but the stale sentence reads as licence to special-case the monster, which is
   precisely the change `GarlicPlacement` must never receive. One sentence in `Types.luau`, not a
   design decision, and it should land in whichever chunk touches that block next.
7. **`ItemService` passes ~1,300 lines with this chunk.** It is the right home — the slot is the
   authority and the placement path needs three services it already requires — but V10 adds the strike
   to the same file. If V10 pushes it further, the split to argue is `ItemService` (the slot, carry,
   drop, pickup) versus a service that owns the three verbs, not a `GarlicService` that would have to
   reach across for the slot on every call.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 3 | A modified client deletes its barrier and walks through; Phase 3 alone ships a mechanic any executor turns off | High | Mitigated by Phase 4; **do not ship Phase 3 without Phase 4** |
| 4 | A patient exploiter crosses at under `GarlicBreachToleranceStuds` per sample and is never detected | Medium | Accepted — closing it needs a swept volume, which raises the false-positive risk the chunk is most afraid of. Prize is 15s of a doorway |
| 4 | A false positive rubber-bands an honest Aswang, which is exactly the tell §4.6 forbids | High | Guards fail toward doing nothing; **V16 question: "did anyone ever see a monster snap backwards"** |
| 3 | One round trip of gap between a rejoining Aswang's `CharacterAdded` and its barriers arriving | Low | Accepted; closing it needs an observable hold |
| — | **A husk behind a garlic doorway IS protected under this design, and spec line 493 forbids it** | Medium | **V12's**, and the note below is what stops V12 rediscovering it |
| 2 | `droppedItems` now holds things that were never dropped and cannot be picked up | Low | Comment, not a rename — a second folder means a second sweep |
| 1 | `Width` must be written `6 * SCALE`; a bare `6` builds a barrier two thirds of the doorway | High | Pinned by `tests/barrio-doorways.test.luau` |
| 3 | Yaw is degrees on the map and radians in the pure module; a doubled or missing conversion is invisible at yaw 0 | Medium | Playtester must record an **E or W** doorway, not only an N or S one |
| — | `garlic_placed` / `garlic_blocked` are not emitted | Low | **Deferred to V19** — `AnalyticsService` is a stub with no transport |

**The husk interaction, stated in full so V12 does not have to derive it.** Spec line 493: *"A husk
cannot benefit from garlic."* Under this design it does — the barrier exists on the Aswang's client
and blocks the Aswang, so a husk standing behind a garlic doorway is protected for fifteen seconds,
and §4.7's relocation rule does not help because it fires at 60 seconds and garlic lasts 15.

**The fix is cheap and it is cheap *because* of the snapshot.** `GarlicBarriers` is a full list the
server rebuilds and re-sends on every change, so V12 removes a barrier from the Aswang's snapshot when
the space behind it holds only husks — a **filter in `pushBarriers`**, not a redesign, and one that
requires no new remote, no new payload field and no client change. The two things V12 must not do:
do not let the client decide (the husk roster is server state and belongs there), and do not delete
the visible garlic part when the barrier is filtered out — the survivors placed it, they can see it,
and a bulb that vanishes early would tell everyone watching that a husk is in that house.

**Where this chunk stops.** V09 does not touch `ClientRoundSnapshot`, does not widen `RoundState`,
does not emit analytics, does not give bawang a model (V15's), does not add a HUD affordance for
placement, and does not implement §4.5's chat phrases about garlic. It adds one up-remote, one
down-remote, two pure modules, nine map tags and one client controller.
