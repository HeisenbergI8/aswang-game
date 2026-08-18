# Plan: C29 — Audio Pass

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M8 (Track D, chunk C29 in `docs/BUILD-PLAN.md`)
- **Description:** Give the game its full cue set — ambient night bed, wind and distant dogs, footsteps,
  a heartbeat, the transform stinger, the gate opening and the sunrise — driven entirely from data every
  client already receives, with every asset ID declared in one `Config.Audio.Assets` table so that
  filling them in later is one edit and not a hunt.
- **Date:** 2026-08-18
- **What the client is told:** **nothing new.** C29 adds no remote, widens no payload and changes no
  server file. Every cue is derived on the client from `RoundSnapshot` (already sent),
  `MonsterTransformed` (already `FireAllClients`, public by design — `MonsterService.luau:447-476`) and
  the local player's own replicated character. `check:remotes` should see no new name and
  `check:secrecy` no new payload, exactly as C28 managed for the sky
  (`SkyController.luau:186-193`).

---

## Preamble — the six constraints every phase below is written against

Read this with any phase. `npm run plan:phase` hands Phase 1 this preamble; phases 2–4 are implemented by
someone who may never see it, so the load-bearing sentences are repeated inside each phase body rather
than cross-referenced.

### P1. The heartbeat decision, and why it is the reason this chunk is Large

Spec §5 asks for a *"heartbeat when the Aswang is near"*. **Taken literally that cue cannot be built in
this game**, and the plan delivers its safe subset instead: **a heartbeat that exists only while a monster
is transformed.** Three designs were on the table.

| | Design | Verdict |
| --- | --- | --- |
| **A** | A ranged `Sound` the CLIENT creates on the transformed character, engine rolloff doing the distance work — what the transform stinger already does (`AudioController.luau:32-62`) | **CHOSEN** |
| **B** | A server-gated cue: the server decides who is near and fires a remote | **Rejected** |
| **C** | No heartbeat at all | **Rejected, but only just** |

**Why B is rejected, and it is not a close call.** A "you are near" boolean is a per-player difference,
and `.claude/lessons/absence-is-observable.md` is this repo's record of what a difference costs: a leak
here is a *difference between players*, not a piece of data, and `check:secrecy` is a text tripwire that
cannot see one. Worse, the server would be computing that boolean from the Aswang's position, which is
the exact shape `MonsterService.luau:456-465` already refused once for the teaching cue — narrowing a
broadcast by proximity "would look like an improvement" and leaves a per-client mark derived from the
secret. B also buys nothing A does not: every client already receives `MonsterTransformed`.

**Why the literal §5 reading is impossible under ANY design.** For an *untransformed* Aswang, no client
may know which character to attach a sound to, and no server-side variant escapes either: a `Sound`
instance the server parents to a character **replicates**, so an exploiter reads
`workspace.<PlayerName>.Head.Heartbeat` in the instance tree and has the answer with the audio muted. The
cue would be a one-line reveal available to anyone with a script executor.

**Why C loses to A.** A transformed monster is *already* public — `MonsterTransformed` is
`FireAllClients` (`MonsterService.luau:468-476`), and the character carries a scale change, a red tint and
a head `PointLight` that every client renders (`Config.Monster.EyeGlowRgb`). A cue scoped to that state
publishes nothing that is not already on screen. Cutting it would forfeit §5's cheapest fear-per-hour for
no secrecy gain.

**What an observer on a compromised client can infer from the shipped heartbeat, stated precisely:** that
*a character they can already see is a monster* is a monster. The `Sound` is created by
`AudioController` on the local client, so it is a **local instance on a replicated character** — it exists
in no other client's tree and on no server. Its only tunable is a range, and Phase 1 pins
`Config.Audio.HeartbeatRange <= Config.Monster.TransformAudioRange` in `tests/config.test.luau` so the
heartbeat can never out-reach the 40-stud tell §4.3 specifies.

**This is a deliberate deviation from §5's wording and it is raised in Follow Ups, not resolved quietly**
(CLAUDE.md: the spec wins and the conflict gets raised).

### P2. Every other cue gets the same question, and footsteps get it hardest

A sound played to one player is a derived hint. So, for each cue in the set:

| Cue | Audience | Derived from | Safe because |
| --- | --- | --- | --- |
| Ambient night bed | every client, identical | `RoundSnapshot.Phase` | one bed per phase, no player input |
| Wind / distant dogs | every client, own RNG | `RoundSnapshot.Phase` | scheduled locally; a one-shot's timing is local noise |
| Footsteps | every character, identical | the character's own `Humanoid` | **a constant across all players — see below** |
| Heartbeat | every client in range | `MonsterTransformed` | scoped to a public state (P1) |
| Transform stinger | every client in range | `MonsterTransformed` | already shipped; C29 fills one field |
| Gate opening | every client, identical | `RoundSnapshot.GateOpen` false→true | already on every snapshot |
| Sunrise | every client, identical | `SkyCycle.progressFor` | same pure function the sky uses |

**Footsteps, answered explicitly because the brief asks: whose, heard by whom, and is there an
Aswang-only or Aswang-louder footstep anywhere in this design? No. There is not, in any state.** Every
character in the game gets the identical footstep `SoundId`, volume and range, applied client-side by the
local client to every `Humanoid` it can see, including its own. A *constant* across all players is safe;
a *difference* is the leak, in either direction — that is the whole finding of
`.claude/lessons/absence-is-observable.md`, and it means a louder footstep for the Aswang would be a
role broadcast wearing no role token, invisible to `check:secrecy`. **A transformed-only footstep variant
was considered and is NOT built**: it would be defensible (transformed is public) but it puts a
role-derived branch into the one code path that runs for every player, and the heartbeat already carries
that information at a tested range.

### P3. Blank IDs must fail safe and silent, exactly as the controller does today

The user sources and approves the actual sounds; "does this sound scary" is verifiable by no agent, which
is why C29 is marked 🧍. So **every cue must behave correctly with `SoundId = ""`** — the controller
creates, positions, ranges and destroys the `Sound` and the only thing missing is audio. That is the
precedent `AudioController.luau:8-12` set deliberately and this plan extends it: *"the spatial behaviour
that C04 cares about is testable now, and C29 fills in one field."* No cue may `error`, `warn` per-frame,
or skip its cleanup because an ID is empty.

### P4. All IDs in one declared table, in `Config.luau`

`Config.Audio.Assets` is a flat `{ [string]: string }` of `rbxassetid://…` strings, one key per cue id.
`Config.luau` is required under Lune by `tests/config.test.luau`, so strings are fine where a `Color3`
would not be (`Config.luau:98-106` explains that trap). Ranges, volumes and fade times go in
`Config.Audio` alongside them because `check:config` requires it — a volume typed in the controller is a
`check:config` finding and, at M12, a number nobody finds again.

`Config.luau` alone is not a durable record though: it cannot hold the creator, the duration or the date,
and a Creator Store asset that gets moderated away leaves a hole you cannot identify from an ID alone
(`asset-pipeline` SKILL: *"Record every asset ID you insert somewhere durable"*). Phase 4 adds
`docs/AUDIO-ASSETS.md` for that.

### P5. The rule goes in a pure module, and it returns strings

Which ambience belongs to which `RoundPhase`, and whether a given cue is permitted for a
`(phase, state)` pair, are rules over plain data — so they live in `src/shared/pure/AudioCues.luau` with
a Lune test, and every step that changes them is gated on `lune run tests/audio-cues.test.luau` rather
than on a grep.

Two constraints on writing it, both already paid for in this repo:

- **It must not `require(script.Parent.X)`.** Lune has no `script`. Re-declare `RoundPhase` and
  `PlayerState` locally; Luau unions are structural, so the local type and `Types.RoundPhase` are the
  same type (CLAUDE.md, "Where testable logic goes").
- **Return `{ string }` from anything returning a LIST, and narrow with a function, never a cast.**
  `.claude/lessons/pure-module-unions-widen-in-lists.md`: a literal union survives `require` as a scalar
  and does **not** survive it inside a list; the analyzer then reports the failure at the call site and
  every obvious fix is spelled in the wrong file. That cost eight failed attempts at C21. Scalar returns
  (`ambienceFor(phase): string?`) are safe and are what this module mostly does.

### P6. The mobile budget is counted, not assumed

§5's budget is non-negotiable and audio is not exempt. The ceiling this plan works to:

- **At most one looping `Sound` per bed** (ambience) plus **one per visible transformed monster**
  (heartbeat, and there is exactly one Aswang). Footsteps reuse the `Humanoid`'s existing sound rather
  than adding an instance per character.
- **Every one-shot destroys itself**, on the `task.delay` pattern `AudioController.luau:55-61` already
  uses and states a reason for — a local instance on a replicated character must be cleaned up by the
  client that made it, because the server's FX teardown will never see it.
- **`StreamingEnabled` (§5, live since C17) means a character can stream out mid-cue.** A `Sound` whose
  parent is destroyed under it is the failure mode; every cue that parents to a character must survive
  its parent vanishing. This is called out again inside Phases 2 and 3.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The cue vocabulary — Config, the pure rule, and its tests

Nothing audible ships in this phase. It creates the single table of asset IDs, the pure module that
decides which cue belongs to which phase, and the two Lune suites that every later phase is verified
against. Doing it first is what makes Phases 2–4 terminal-verifiable instead of grep-verifiable.

#### Step 1.1: Add `src/shared/pure/AudioCues.luau` — the catalogue and the phase rule

**File:** `src/shared/pure/AudioCues.luau`
**Verify:** `npm run analyze`

The cue ids, `ambienceFor(phase)`, `oneShotsFor(phase)` and `isCuePermitted(cueId, phase, state)`, over
plain tables, requiring nothing. Note the return types: `ambienceFor` returns `string?` (a scalar, safe)
and `oneShotsFor` returns `{ string }` and **not** `{ AudioCueId }` — a literal union does not survive
`require` inside a list, the analyzer reports it at the call site, and
`.claude/lessons/pure-module-unions-widen-in-lists.md` is eight failed fixes' worth of evidence for that.
The narrowing happens in the controller, where an unknown id resolves to `nil` in `Config.Audio.Assets`
and is dropped with a `warn`.

```diff
+--!strict
+--[[
+	AudioCues — which sound belongs to which moment. (C29, §5)
+
+		ambienceFor(phase) -> string?                       -- the looping bed for a round phase
+		oneShotsFor(phase) -> { string }                    -- wind/dogs eligible in that phase
+		isCuePermitted(cueId, phase, state) -> boolean      -- may this cue fire at all
+
+	§5: "Audio matters more than visuals in horror… the cheapest fear-per-hour you can buy." This
+	module is the part of that sentence a terminal can check. It owns no Sound, no Instance and no
+	clock — `AudioController` plays cues, `RoundService` owns the phase (§6.4), and this answers
+	"which one, and is it allowed" over plain strings.
+
+	NOTHING SECRET PASSES THROUGH HERE, and that is structural rather than careful: the inputs are a
+	phase and the RECEIVER'S OWN state, both of which are already on every client's `RoundSnapshot`.
+	There is no role parameter and no player parameter, so there is no arrangement of this module in
+	which two clients in the same phase get different answers. `.claude/lessons/absence-is-observable`
+	is the long version — in this game the leak is a DIFFERENCE between players, and a rule that
+	cannot see a player cannot produce one.
+
+	This module is REQUIRABLE AND CALLABLE BY ANY CLIENT (`src/shared` maps wholesale into
+	ReplicatedStorage) and that costs nothing: a table saying "crickets play at night" publishes
+	nothing that is not audible.
+
+	NO `script.Parent` REQUIRES (tests/README.md), so no Types, no Enums, no Config. `RoundPhase` and
+	`PlayerState` are re-declared — Luau unions are structural, so these and the `Types.` ones are the
+	same type. Every ASSET ID and every DURATION lives in `Config.Audio`; this file holds only the
+	mapping, so C29's sourcing pass and M12's tuning never touch it.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
+
+local AudioCues = {}
+
+--[[
+	THE BEDS. One per phase, and the lobby shares INTERMISSION's deliberately: a player waiting must
+	never experience a silent screen for the same reason C24 says they must never see a static one —
+	silence reads as broken, not as waiting.
+
+	Keyed by plain `string` rather than by `RoundPhase`, because a literal union in a table-VALUE or
+	table-KEY annotation resolves to plain `string` anyway (the C21 lesson's sixth failed fix). The
+	union is enforced at the PARAMETER, which is where it works.
+]]
+local BEDS: { [string]: string } = {
+	IDLE = "CUE_BED_LOBBY",
+	INTERMISSION = "CUE_BED_LOBBY",
+	STARTING = "CUE_BED_NIGHT",
+	ACTIVE = "CUE_BED_NIGHT",
+	ENDING = "CUE_BED_DAWN",
+}
+
+-- Wind is always plausible; distant dogs belong to the barrio at night and would undercut the reveal
+-- if they kept barking over it, so ENDING gets neither and lets the sunrise cue own the moment.
+local ONE_SHOTS: { [string]: { string } } = {
+	IDLE = { "CUE_WIND" },
+	INTERMISSION = { "CUE_WIND" },
+	STARTING = { "CUE_WIND", "CUE_DOGS" },
+	ACTIVE = { "CUE_WIND", "CUE_DOGS" },
+	ENDING = {},
+}
+
+--[[
+	WHICH PHASES EACH EVENT CUE MAY FIRE IN. A cue absent from this table is refused everywhere, so
+	adding a cue id without deciding its phases fails closed rather than playing during the reveal.
+]]
+local PERMITTED_PHASES: { [string]: { [string]: boolean } } = {
+	CUE_TRANSFORM = { STARTING = true, ACTIVE = true },
+	CUE_HEARTBEAT = { ACTIVE = true },
+	CUE_GATE_OPEN = { ACTIVE = true },
+	CUE_SUNRISE = { ACTIVE = true, ENDING = true },
+	CUE_FOOTSTEP = {
+		IDLE = true,
+		INTERMISSION = true,
+		STARTING = true,
+		ACTIVE = true,
+		ENDING = true,
+	},
+}
+
+--[[
+	THE STATE GATE, AND THE ONE RULE IN IT THAT IS A SECRECY RULE.
+
+	A player in LOBBY or SPECTATOR is not in the round. They must not hear the monster — not the
+	stinger, not the heartbeat — because a cue is information, and information reaching somebody
+	outside the round is information reaching a Discord call. §4.3's tell is for players who are in
+	the barrio and can be killed by it.
+
+	GHOST is allowed. A ghost is in the world with a local body (C15) and can already SEE a
+	transformed monster; refusing them the audio would remove nothing and would make dead players
+	audibly different from living ones, which is the failure mode `absence-is-observable` names.
+]]
+local MONSTER_CUES: { [string]: boolean } = {
+	CUE_TRANSFORM = true,
+	CUE_HEARTBEAT = true,
+}
+
+local OUTSIDE_THE_ROUND: { [string]: boolean } = {
+	LOBBY = true,
+	SPECTATOR = true,
+}
+
+-- The looping bed for a phase, or nil if the phase has none. Nil is a legitimate answer and the
+-- caller stops its bed rather than treating it as an error.
+function AudioCues.ambienceFor(phase: RoundPhase): string?
+	return BEDS[phase]
+end
+
+--[[
+	`{ string }`, NOT `{ AudioCueId }`, and never `{ Types.AudioCueId }`. A literal union survives
+	`require` as a scalar and does NOT survive it inside a list: the element arrives as a union of
+	plain strings, `::` widens every option rather than narrowing, and the analyzer reports it in the
+	CALLING file. See `.claude/lessons/pure-module-unions-widen-in-lists.md`. The caller narrows by
+	LOOKUP — `Config.Audio.Assets[id]` returns nil for an unknown id — which is a function, not a
+	cast, and drops the bad id with a warn instead of waving it onward.
+]]
+function AudioCues.oneShotsFor(phase: RoundPhase): { string }
+	local ids = ONE_SHOTS[phase]
+
+	if ids == nil then
+		return {}
+	end
+
+	return table.clone(ids)
+end
+
+function AudioCues.isCuePermitted(cueId: string, phase: RoundPhase, state: PlayerState): boolean
+	local phases = PERMITTED_PHASES[cueId]
+
+	if phases == nil or not phases[phase] then
+		return false
+	end
+
+	if MONSTER_CUES[cueId] and OUTSIDE_THE_ROUND[state] then
+		return false
+	end
+
+	return true
+end
+
+return AudioCues
```

#### Step 1.2: Add `tests/audio-cues.test.luau`

**File:** `tests/audio-cues.test.luau`
**Verify:** `lune run tests/audio-cues.test.luau`

Every phase maps to exactly one bed; the heartbeat is permitted in `ACTIVE` and refused everywhere else;
an unknown cue id returns `false` rather than erroring. Follows the shape of `tests/sky-cycle.test.luau`
— a `check(label, ok, detail)` counter and a non-zero exit on any failure — so `npm run test:unit` picks
it up with no wiring.

```diff
+--!strict
+--[[
+	The cue rules (C29, §5), proven where a listen cannot reach.
+
+	C29's real verification is a person with headphones, and that is correct for "does this sound
+	scary". It is useless for the two properties that break silently:
+
+	  · A CUE FIRING IN THE WRONG PHASE. A transform stinger during the reveal, or a dog barking over
+	    the sunrise, is a bug you hear once, cannot reproduce on demand, and cannot screenshot.
+	  · A MONSTER CUE REACHING SOMEBODY OUTSIDE THE ROUND. A player sitting in LOBBY who hears the
+	    heartbeat has learned that a transform is happening right now, from outside the barrio. That
+	    is information leaving the round, and no screenshot of the round would ever show it.
+
+	Both are one assertion each here.
+]]
+
+local AudioCues = require("../src/shared/pure/AudioCues")
+
+local failures = 0
+local checked = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	checked += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local PHASES = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
+local STATES = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
+
+print("AudioCues")
+
+-- EVERY phase has a bed. A phase with no bed is a silent screen, and §9.3's point about the lobby
+-- ("a player waiting must never see a static screen — that reads as broken") is true of silence too.
+for _, phase in PHASES do
+	check(`bed exists for {phase}`, AudioCues.ambienceFor(phase) ~= nil)
+end
+
+check("night and lobby beds differ", AudioCues.ambienceFor("ACTIVE") ~= AudioCues.ambienceFor("IDLE"))
+check("ENDING has its own bed", AudioCues.ambienceFor("ENDING") ~= AudioCues.ambienceFor("ACTIVE"))
+
+-- The returned list is a COPY. A caller that sorted or cleared it in place would silently rewrite the
+-- rule for every later call in that client's session.
+local first = AudioCues.oneShotsFor("ACTIVE")
+table.clear(first)
+check("oneShotsFor returns a copy", #AudioCues.oneShotsFor("ACTIVE") > 0)
+
+check("ENDING schedules no one-shots", #AudioCues.oneShotsFor("ENDING") == 0)
+check("unknown phase yields no one-shots", #AudioCues.oneShotsFor("NOT_A_PHASE" :: any) == 0)
+
+-- THE HEARTBEAT'S PHASE WINDOW. It exists only while a monster can be transformed, which is ACTIVE
+-- and nothing else — see the plan's preamble P1 for why this cue is transformed-only at all.
+for _, phase in PHASES do
+	local permitted = AudioCues.isCuePermitted("CUE_HEARTBEAT", phase, "ALIVE")
+	check(`heartbeat in {phase}`, permitted == (phase == "ACTIVE"), `got {permitted}`)
+end
+
+-- THE STATE GATE. A player outside the round hears no monster cue, in any phase.
+for _, state in STATES do
+	local outside = state == "LOBBY" or state == "SPECTATOR"
+
+	check(
+		`heartbeat for {state}`,
+		AudioCues.isCuePermitted("CUE_HEARTBEAT", "ACTIVE", state) == not outside
+	)
+	check(
+		`stinger for {state}`,
+		AudioCues.isCuePermitted("CUE_TRANSFORM", "ACTIVE", state) == not outside
+	)
+end
+
+-- A ghost is in the world and can SEE the monster. Refusing them the audio would make the dead
+-- audibly different from the living, which is the leak `absence-is-observable` describes.
+check("ghosts hear the monster", AudioCues.isCuePermitted("CUE_HEARTBEAT", "ACTIVE", "GHOST"))
+
+-- FAILS CLOSED. An id nobody assigned phases to plays nowhere, rather than everywhere.
+check("unknown cue is refused", not AudioCues.isCuePermitted("CUE_NOPE", "ACTIVE", "ALIVE"))
+
+-- Footsteps are the one cue with no phase restriction, because they are the one cue that is a
+-- CONSTANT across every player and every state. See the plan's preamble P2.
+for _, phase in PHASES do
+	check(`footsteps in {phase}`, AudioCues.isCuePermitted("CUE_FOOTSTEP", phase, "ALIVE"))
+end
+
+print(`  {checked - failures}/{checked} checks passed`)
+
+if failures > 0 then
+	error(`{failures} AudioCues check(s) failed`, 0)
+end
```

#### Step 1.3: Add the `Config.Audio` block

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

`Assets` (all `""` for now), `HeartbeatRange`, volumes, fades and the sunrise trigger point — every
number C29 will need, declared before any of them is used. Insert after the `Sky` block and before
`AntiCheat` (`Config.luau:610-688`), which keeps the two presentation systems C28 and C29 adjacent.

**Strings only, no Roblox datatypes.** `tests/config.test.luau` requires this file under Lune, which has
no `Color3`, no `Vector3` and no `Enum` — `Config.luau:98-106` records that a `Color3.fromRGB` here does
not fail to typecheck, it fails at TEST time in every balance test at once with an error naming Config
rather than the edit that broke it. An `rbxassetid://` is a string and is safe.

```diff
 	Sky = {
 		...
 	},
 
+	--[[
+		AUDIO (C29, §5 and §14.3: "audio matters more than visuals in horror… the cheapest
+		fear-per-hour you can buy").
+
+		EVERY ASSET ID IN THE GAME IS IN ONE TABLE, and that is the point of putting them here rather
+		than beside the code that plays them. The sounds are sourced and APPROVED BY A PERSON — "does
+		this sound scary" is not something any check can answer — so the ids arrive after the code
+		does, and when they arrive it must be one edit to this table and not a hunt through a
+		controller. `docs/AUDIO-ASSETS.md` carries the other half: creator, duration and date, which
+		a bare id cannot record and which is what you need when a Creator Store asset is moderated
+		away and leaves a hole.
+
+		A BLANK ID IS A VALID, SUPPORTED STATE, not a placeholder to be tidied up. `AudioController`
+		creates, positions, ranges and destroys the Sound either way and simply plays nothing — the
+		precedent the transform stinger set at C04 (see that controller's header). So the game is
+		fully playable with this table exactly as it ships below, and every phase of C29 before the
+		sourcing pass is verifiable with it empty.
+
+		KEYS MATCH `shared/pure/AudioCues` EXACTLY. `tests/config.test.luau` asserts that every cue
+		id the rule module names has a key here, so a cue with a rule and nowhere to put its sound is
+		a red test rather than a silent nothing at 3am in a playtest.
+	]]
+	Audio = {
+		Assets = {
+			CUE_BED_LOBBY = "",
+			CUE_BED_NIGHT = "",
+			CUE_BED_DAWN = "",
+			CUE_WIND = "",
+			CUE_DOGS = "",
+			CUE_FOOTSTEP = "",
+			CUE_TRANSFORM = "",
+			CUE_HEARTBEAT = "",
+			CUE_GATE_OPEN = "",
+			CUE_SUNRISE = "",
+		},
+
+		-- The bed sits UNDER everything. A night ambience loud enough to notice is a night ambience
+		-- competing with the one sound in the game that has to be heard through a wall (§4.3's tell).
+		BedVolume = 0.35,
+		BedFadeSeconds = 2,
+
+		-- Wind and dogs, scheduled locally at a random interval in this band. Random per client and
+		-- per phase, so two players do not hear the same dog — a shared schedule would be a clock
+		-- every client agrees on, and this game has enough of those.
+		OneShotVolume = 0.5,
+		OneShotMinSeconds = 25,
+		OneShotMaxSeconds = 70,
+
+		-- IDENTICAL FOR EVERY CHARACTER IN THE GAME. There is no per-role, per-state or transformed
+		-- variant of this number and there must not be: a louder footstep for one player is a role
+		-- broadcast with no role token in it, which `check:secrecy` cannot see. See
+		-- `.claude/lessons/absence-is-observable.md`.
+		FootstepVolume = 0.4,
+
+		StingerVolume = 0.9,
+
+		--[[
+			THE HEARTBEAT, AND THE ONE RELATIONSHIP THAT MATTERS ABOUT IT.
+
+			It plays only while a monster is TRANSFORMED — a state every client already knows about,
+			since `MonsterTransformed` is FireAllClients and the character wears a scale change, a red
+			tint and a head PointLight. It is created by the local client on a replicated character,
+			so it exists in no other client's instance tree.
+
+			`HeartbeatRange` MUST NOT EXCEED `Monster.TransformAudioRange` (40 studs), and
+			`tests/config.test.luau` pins that. §4.3 specifies exactly how far the transform carries;
+			a heartbeat audible past it would quietly rewrite the tell's range without anyone editing
+			the number that documents it.
+		]]
+		HeartbeatVolume = 0.7,
+		HeartbeatRange = 28,
+		HeartbeatFadeSeconds = 0.4,
+
+		GateVolume = 0.8,
+
+		-- Fired once per round when `SkyCycle.progressFor` crosses this. Before 1.0 deliberately: the
+		-- sound should land while the sky is still moving, not as a stamp on the reveal.
+		SunriseVolume = 0.6,
+		SunriseAtProgress = 0.92,
+
+		--[[
+			How long a one-shot Sound survives before the client destroys it. A `Sound.Ended` signal
+			would be the obvious answer and it is the wrong one: A BLANK SoundId NEVER ENDS, so every
+			cue would leak an instance for the whole of development, which is exactly the state §5's
+			budget cannot afford and exactly the state this project is in until the sourcing pass.
+			Longer than any stinger the `asset-pipeline` skill's 0.2-4s band can produce, and
+			`tests/config.test.luau` pins it BELOW `OneShotMinSeconds` so cleanup always beats the
+			next schedule and instances cannot accumulate.
+		]]
+		CueCleanupSeconds = 6,
+	},
+
 	AntiCheat = {
```

#### Step 1.4: Pin the audio relationships in `tests/config.test.luau`

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

Heartbeat range never exceeds `Monster.TransformAudioRange`; the sunrise trigger sits inside the round;
every declared asset id is either empty or a well-formed `rbxassetid://`. These are the same kind of
assertion as the thirteen relationships that file already pins — silent invariants where no symptom tells
you two numbers that must agree have stopped agreeing.

The id-format assertion is what makes **Step 4.2 checkable at all**: without it, filling in the ids is a
step whose only evidence is that somebody typed something.

```diff
 local Config = require("../src/shared/Config")
+local AudioCues = require("../src/shared/pure/AudioCues")
 
 ...
 
+print("Audio (C29)")
+
+--[[
+	THE HEARTBEAT MUST NOT OUT-REACH THE TELL.
+
+	§4.3 fixes the transform's audio at ~40 studs and `Monster.TransformAudioRange` is that number.
+	The heartbeat is the sustained layer under it, so it plays inside that radius or not at all — a
+	heartbeat audible from further away would extend the monster's tell without anyone editing the
+	field that documents its range, and the two numbers live in different blocks of this file.
+]]
+check(
+	"heartbeat is inside the transform tell",
+	Config.Audio.HeartbeatRange <= Config.Monster.TransformAudioRange,
+	`{Config.Audio.HeartbeatRange} > {Config.Monster.TransformAudioRange}`
+)
+
+-- Cleanup must beat the next schedule, or one-shot Sounds accumulate for the length of a round. §5's
+-- budget is non-negotiable and the instance count is part of it.
+check(
+	"one-shot cleanup beats the next one-shot",
+	Config.Audio.CueCleanupSeconds < Config.Audio.OneShotMinSeconds
+)
+check("one-shot band is ordered", Config.Audio.OneShotMinSeconds < Config.Audio.OneShotMaxSeconds)
+
+-- The sunrise lands while the sky is still moving, not on top of the reveal.
+check(
+	"sunrise fires inside the round",
+	Config.Audio.SunriseAtProgress > 0 and Config.Audio.SunriseAtProgress < 1
+)
+
+-- The bed crossfade must fit inside the shortest phase it can be asked to cover.
+check("bed fade fits a phase", Config.Audio.BedFadeSeconds < Config.Round.EndScreen)
+
+--[[
+	EVERY CUE THE RULE MODULE NAMES HAS SOMEWHERE TO PUT A SOUND.
+
+	`AudioCues` decides WHICH cue; `Config.Audio.Assets` holds WHAT it plays. Nothing else connects
+	them, so a cue id added to one and not the other is silent in the exact way this whole chunk is
+	hard to verify — you find it by not hearing something, during a playtest, once.
+]]
+local NAMED_CUES = {
+	"CUE_BED_LOBBY",
+	"CUE_BED_NIGHT",
+	"CUE_BED_DAWN",
+	"CUE_WIND",
+	"CUE_DOGS",
+	"CUE_FOOTSTEP",
+	"CUE_TRANSFORM",
+	"CUE_HEARTBEAT",
+	"CUE_GATE_OPEN",
+	"CUE_SUNRISE",
+}
+
+for _, id in NAMED_CUES do
+	check(`{id} has an Assets entry`, Config.Audio.Assets[id] ~= nil)
+end
+
+for _, phase in { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" } do
+	local bed = AudioCues.ambienceFor(phase)
+	check(`bed for {phase} resolves`, bed ~= nil and Config.Audio.Assets[bed] ~= nil)
+
+	for _, id in AudioCues.oneShotsFor(phase) do
+		check(`one-shot {id} resolves`, Config.Audio.Assets[id] ~= nil)
+	end
+end
+
+--[[
+	AN ID IS EITHER EMPTY OR WELL-FORMED. Empty is the supported pre-sourcing state (the controller
+	plays nothing, silently, by design). Anything else must be a real asset URI — a bare number, an
+	`rbxasset://` typo or a copied Creator Store URL all fail at runtime with no error a player or a
+	log would ever surface, because a Sound with a bad id simply does not play.
+]]
+for id, assetId in Config.Audio.Assets do
+	check(
+		`{id} is blank or an rbxassetid`,
+		assetId == "" or string.match(assetId, "^rbxassetid://%d+$") ~= nil,
+		`got "{assetId}"`
+	)
+end
```

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — `AudioCues` takes a phase and the receiver's own state and nothing else. There is
  no role parameter, no player parameter and no position, so the module cannot produce a difference
  between two clients in the same phase. `Config.Audio` is replicated (it is in `ReplicatedStorage`) and
  publishes only "crickets play at night", which is audible anyway.
- **Remote direction** — no remote is touched in this phase.
- **Rate limiting** — no `OnServerEvent` handler is added anywhere in C29.
- **Magic numbers** — every number introduced lives in `Config.Audio`. `AudioCues` holds **no numbers at
  all**, deliberately: `src/shared/` is outside `check:config`'s `GOVERNED` paths
  (`check-config.mjs:33`), so a tunable hidden in a pure module is one the check would never catch.
- **Phase ownership** — `AudioCues` reads a phase and never sets one; `RoundService` remains the only
  writer (§6.4).
- **Player leaving mid-round** — not reachable from a pure module.
- **Strict Luau** — `ambienceFor` returns `string?`; `oneShotsFor` returns `{ string }` and NOT a list of
  literals (`.claude/lessons/pure-module-unions-widen-in-lists.md`).
- **Mobile budget** — no instances created in this phase.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **`tests/config.test.luau` gains a second `require`.** It has only ever required `Config`. Requiring
  `AudioCues` is safe (that module requires nothing) but it means a syntax error in the pure module now
  reds the balance suite too. Accepted: the cross-check it buys — a cue with a rule and no asset slot —
  is exactly the failure that is otherwise found by not hearing something, once, during a playtest.
- **`Config.Round.EndScreen` is assumed to exist** for the bed-fade assertion. Confirmed present in the
  `Round` block (`Config.luau:12-51`); if it has been renamed, pin the fade against `Round.Intermission`
  instead and note the change.

---

### Phase 2: `AudioController` becomes a cue player

Rewrites the 78-line single-cue controller into one that owns a small cue vocabulary, keeping its
existing stinger behaviour intact and its header's reasoning extended rather than replaced.

#### Step 2.1: Rewrite the header and add the `playCue` core

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `npm run verify:fast`

One function that resolves an id to a `Config.Audio.Assets` entry, creates the `Sound`, logs behind
`Debug.VerboseLogging`, and returns silently on a blank id.

**The log line is the deliverable, not a nicety.** C29's stated Verify is *"playtester captures console
confirmation of each cue"*, and the cue log has to fire **whether or not the asset id is filled in** —
otherwise the only phase that can be verified is the one after sourcing, and the playtester has nothing
to capture in Phases 2 and 3. It logs that the cue *fired*, which is the part a console can prove; the
part it cannot prove is what it sounded like, and that is Step 4.5's job.

```diff
 --!strict
 --[[
-	AudioController — ambient loops, stingers, the heartbeat.
+	AudioController — every sound in the game. (C29, §5 and §14.3)
 
-	Milestone: M8 owns the real audio pass (C29), where §14.3's point stands: audio is half of horror
-	and it is free. Today this file owns one cue — the transform stinger (§4.3).
+	§14.3's point is the whole reason this file is large: audio is half of horror and it is free.
+	Every cue in §5's list lives here — the night bed, wind and distant dogs, footsteps, the
+	heartbeat, the transform stinger, the gate, and the sunrise.
 
-	NO ASSET ID YET, AND THAT IS DELIBERATE. Sourcing audio is C29 with the `asset-pipeline` skill, and
-	inventing an ID here would either 404 at runtime or ship somebody else's sound with no licence
-	trail. So the Sound instance is created, positioned and RANGED correctly, and its SoundId is left
-	empty: the spatial behaviour that C04 cares about is testable now, and C29 fills in one field.
+	═══ THIS CONTROLLER ADDS NOTHING TO THE NETWORK SURFACE ════════════════════
+
+	No remote is declared, fired or widened for C29. Every cue is derived from data this client
+	already receives:
+
+	  · the bed, the one-shots, the gate and the sunrise ← `RoundSnapshot`, already sent every
+	    `Config.Round.SnapshotInterval` for the HUD
+	  · the stinger and the heartbeat ← `MonsterTransformed`, already `FireAllClients` and public by
+	    design (§4.3 — the tell IS the mechanic)
+	  · footsteps ← the character's own Humanoid, on this client
+
+	That is C28's shape and it is deliberate: `SkyController` renders the round clock as a sunrise off
+	the same snapshot and adds no remote either. `check:remotes` has no new name to learn here and
+	`check:secrecy` no new payload to argue with.
+
+	═══ WHAT A COMPROMISED CLIENT LEARNS FROM THIS FILE ════════════════════════
+
+	Nothing it did not already have. Stated per cue at the SECRECY STATEMENT further down, because
+	🔒 `exploit-auditor` gates this chunk and the answer belongs at a file:line rather than in a plan
+	document nobody re-reads.
+
+	The short version: no cue takes a role as an input, no cue is fired at one player and not
+	another, and no Sound this file creates is ever created by the server — every instance here is
+	LOCAL to the client that made it, so no other client can read it out of the workspace. The one
+	cue §5 asks for that CANNOT be built safely is a heartbeat keyed to an UNTRANSFORMED Aswang; see
+	the heartbeat's own comment for why, and the plan's Follow Ups for the spec deviation it implies.
+
+	═══ A BLANK ASSET ID IS A SUPPORTED STATE ═════════════════════════════════
+
+	The sounds are sourced from the Creator Store and APPROVED BY A PERSON — "does this sound scary"
+	is not something any check answers. So the ids arrive after this code does, and until they do,
+	every cue must create, position, range, log and destroy its Sound exactly as it will in the end
+	and simply play nothing. That is the precedent the transform stinger set at C04 and it is now the
+	rule for all ten cues: the spatial and lifecycle behaviour is testable today, and sourcing fills
+	in one table.
 
 	WHY THE SOUND IS PARENTED TO THE TRANSFORMING CHARACTER'S HEAD
 	--------------------------------------------------------------
 	`Config.Monster.TransformAudioRange` (40 studs) is a fact about WHERE the transform can be heard,
 	and Roblox's own rolloff is what enforces it. A sound played at the listener with a manual distance
-	check would be a second, wrong answer to a question the engine already answers — and it would be
-	wrong in the direction that matters, since it would ignore the geometry between the two players.
+	check would be a second, wrong answer to a question the engine already answers, and it would need
+	the monster's position on the client to ask it — which is the leak this whole file is arranged to
+	avoid. Every ranged cue below follows this precedent.
+
+	(An earlier version of this paragraph also claimed the engine accounts for the GEOMETRY between
+	the two players. That claim is unverified and is believed to be false for a classic `Sound`, which
+	attenuates by distance only. It is struck rather than relied on — the parenting decision stands on
+	the distance and the position alone. See the plan's Follow Ups.)
 ]]
 
+local Players = game:GetService("Players")
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
+local SoundService = game:GetService("SoundService")
+local TweenService = game:GetService("TweenService")
 
 local Shared = ReplicatedStorage:WaitForChild("Shared")
+local AudioCues = require(Shared.pure.AudioCues)
 local Config = require(Shared.Config)
 local Remotes = require(Shared.Remotes)
+local SkyCycle = require(Shared.pure.SkyCycle)
 local Types = require(Shared.Types)
 
 local AudioController = {}
 
 local STINGER_NAME = "AswangTransformStinger"
+
+-- The receiver's own phase and state, off the snapshot every client gets. Neither is a secret and
+-- neither describes anybody else.
+local phase: Types.RoundPhase = "IDLE"
+local state: Types.PlayerState = "LOBBY"
+
+--[[
+	THE NARROWING FUNCTION, and it is a function rather than a cast on purpose.
+
+	`AudioCues.oneShotsFor` returns `{ string }` because a literal union does not survive `require`
+	inside a list — `.claude/lessons/pure-module-unions-widen-in-lists.md`, eight failed fixes at C21.
+	So ids arrive here as plain strings and this lookup is what narrows them: an id with no Assets
+	entry returns nil and is dropped with a warn, where a cast would have waved it onward into a
+	Sound that silently never plays.
+
+	AN EMPTY STRING IS NOT AN ERROR. It is the pre-sourcing state and returns normally.
+]]
+local function assetFor(cueId: string): string?
+	local assetId = Config.Audio.Assets[cueId]
+
+	if assetId == nil then
+		warn(`[AudioController] no Config.Audio.Assets entry for cue "{cueId}" — nothing played.`)
+		return nil
+	end
+
+	return assetId
+end
+
+--[[
+	THE CUE LOG, AND WHY IT FIRES ON A BLANK ID.
+
+	C29's verification is "the playtester captures console confirmation of each cue". That has to
+	work BEFORE the sounds exist, or the only build anybody can verify is the last one. So this logs
+	that the cue FIRED — which a console can prove — and says nothing about what it sounded like,
+	which is the human step and stays the human step.
+
+	Behind `Debug.VerboseLogging` like every other non-fault line in this codebase; the playtester
+	turns it on. A missing ASSET is a warn above and is never gated, because a cue with no sound is a
+	fault and faults are ungated here (GateService's untagged-gate warn is the precedent).
+]]
+local function logCue(cueId: string, detail: string)
+	if Config.Debug.VerboseLogging then
+		print(`[AudioController] cue {cueId} — {detail}`)
+	end
+end
+
+--[[
+	Creates a Sound for a cue, or nil if the cue id is unknown. Never returns nil for a BLANK id:
+	the instance is still created, parented and ranged, so the lifecycle this file is responsible for
+	is exercised identically before and after the sourcing pass.
+]]
+local function newSound(cueId: string, volume: number, parent: Instance): Sound?
+	local assetId = assetFor(cueId)
+
+	if assetId == nil then
+		return nil
+	end
+
+	local sound = Instance.new("Sound")
+	sound.Name = cueId
+	sound.SoundId = assetId
+	sound.Volume = volume
+	sound.Parent = parent
+
+	return sound
+end
+
+--[[
+	A one-shot, cleaned up by the client that made it.
+
+	`Sound.Ended` is the obvious lifetime and it is the wrong one: A BLANK SoundId NEVER ENDS, so
+	every cue would leak an instance for the whole of development. `Config.Audio.CueCleanupSeconds`
+	is pinned below `OneShotMinSeconds` in `tests/config.test.luau` so cleanup always beats the next
+	schedule and instances cannot accumulate — §5's budget counts Sounds too.
+
+	The nil check inside the delay is not defensive noise: under §5's StreamingEnabled a character can
+	stream out mid-cue and take its parent with it.
+]]
+local function playOneShot(cueId: string, volume: number, parent: Instance, detail: string)
+	local sound = newSound(cueId, volume, parent)
+
+	if sound == nil then
+		return
+	end
+
+	logCue(cueId, detail)
+	sound:Play()
+
+	task.delay(Config.Audio.CueCleanupSeconds, function()
+		if sound.Parent ~= nil then
+			sound:Destroy()
+		end
+	end)
+end
```

#### Step 2.2: The ambient bed, driven by `RoundSnapshot`

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `npm run check:remotes`

One looping `Sound` in `SoundService`, swapped on a phase change via `AudioCues.ambienceFor`, crossfaded
over `Config.Audio.BedFadeSeconds`. `check:remotes` is the verify because the claim worth checking here
is the negative one: the bed reacts to `RoundSnapshot`, a remote that already exists and already flows
down, and **no new name enters `Remotes.luau`**.

```diff
+--[[
+	THE BED. Exactly one looping Sound exists on this client at a time, parented to SoundService so
+	it is non-positional — the night is everywhere, not at a point.
+
+	IDENTICAL ON EVERY SCREEN, and that is load-bearing rather than incidental, for the reason
+	`SkyController`'s header gives about the sky: it is driven from a snapshot every client receives
+	through a pure rule with no role input and no player input, so there is no arrangement of this
+	code in which one player's ambience differs from another's. A bed that changed when the monster
+	was near would be `absence-is-observable` played out loud.
+]]
+local bed: Sound? = nil
+local bedCueId: string? = nil
+
+local function setBed(cueId: string?)
+	if cueId == bedCueId then
+		return
+	end
+
+	local previous = bed
+	bedCueId = cueId
+	bed = nil
+
+	if previous ~= nil then
+		local fadeOut = TweenService:Create(
+			previous,
+			TweenInfo.new(Config.Audio.BedFadeSeconds),
+			{ Volume = 0 }
+		)
+
+		fadeOut.Completed:Connect(function()
+			previous:Destroy()
+		end)
+
+		fadeOut:Play()
+	end
+
+	if cueId == nil then
+		return
+	end
+
+	local sound = newSound(cueId, 0, SoundService)
+
+	if sound == nil then
+		return
+	end
+
+	sound.Looped = true
+	bed = sound
+
+	logCue(cueId, "bed")
+	sound:Play()
+
+	TweenService
+		:Create(sound, TweenInfo.new(Config.Audio.BedFadeSeconds), {
+			Volume = Config.Audio.BedVolume,
+		})
+		:Play()
+end
```

And in the snapshot handler added by this step:

```diff
+local function onSnapshot(snapshot: Types.ClientRoundSnapshot)
+	phase = snapshot.Phase
+	state = snapshot.YourState
+
+	setBed(AudioCues.ambienceFor(phase))
+end
```

```diff
 function AudioController.Start()
+	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
 	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
 end
```

#### Step 2.3: Footsteps — one sound, every character, no exceptions

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `npm run check:secrecy`

Retarget the `Humanoid`'s existing `Running` sound for every character the client sees, with no branch on
role, state or transform.

**Answering the brief's question directly, because it is the one an auditor will ask: whose footsteps,
heard by whom, and does an Aswang-only or Aswang-louder footstep exist anywhere in this design? Every
character's, heard by everyone in range, and NO — not in any state, including transformed.** One
`SoundId`, one `Volume` from `Config.Audio.FootstepVolume`, applied by the same code path to every
character this client can see including its own. A constant across all players is safe; a *difference* is
the leak, in either direction, and that is the entire finding of
`.claude/lessons/absence-is-observable.md`. A louder footstep for the Aswang would be a role broadcast
carrying no role token, which `check:secrecy` structurally cannot see.

**A transformed-only footstep variant was considered and is NOT built.** It would be defensible — the
transformed state is already public — but it puts a monster-derived branch inside the one code path that
runs for every player in the game, and the heartbeat (Step 3.2) already carries that information at a
range `tests/config.test.luau` pins. The cheap version of this cue is not worth the review surface.

**This step depends on unverified Roblox behaviour and is written to be skippable because of it.** How
Roblox's default character sounds are created — the `RbxCharacterSounds` script, what the Sound is named,
and whether the local client owns them for *remote* characters as well as its own — is not established
anywhere in this codebase. So the step **retargets a sound it finds and does nothing if it does not find
one**, and doing nothing is a correct outcome: Roblox's default footstep is *already* identical across
all players, so the secrecy property this step exists to protect holds whether or not the retarget lands.
Raised in Follow Ups; the playtester can settle it in one `inspect_instance` call.

```diff
+--[[
+	FOOTSTEPS — IDENTICAL FOR EVERY CHARACTER, WITH NO EXCEPTIONS ANYWHERE.
+
+	There is no per-role, per-state or transformed variant of this cue and there must not be. A
+	constant across all players is safe; a DIFFERENCE is the leak, in either direction
+	(`.claude/lessons/absence-is-observable.md`). A louder step for the Aswang carries no role token,
+	so `check:secrecy` would pass it, and any player could find the monster by listening.
+
+	It retargets the sound Roblox already creates rather than adding one per character: §5's budget
+	counts instances, and eight extra looping Sounds is eight for nothing.
+
+	IF THERE IS NOTHING TO RETARGET, THIS DOES NOTHING, and that is a correct outcome rather than a
+	failure — the default footstep is already identical for everybody, which is the property that
+	matters here. The engine's default character-sound arrangement is not established anywhere in
+	this repo, so this code asserts nothing about it.
+]]
+local FOOTSTEP_SOUND_NAME = "Running"
+
+local function applyFootsteps(character: Model)
+	local root = character:FindFirstChild("HumanoidRootPart")
+
+	if root == nil then
+		return
+	end
+
+	local running = root:FindFirstChild(FOOTSTEP_SOUND_NAME)
+
+	if running == nil or not running:IsA("Sound") then
+		return
+	end
+
+	local assetId = assetFor("CUE_FOOTSTEP")
+
+	if assetId == nil or assetId == "" then
+		return
+	end
+
+	running.SoundId = assetId
+	running.Volume = Config.Audio.FootstepVolume
+end
+
+--[[
+	EVERY player, including this one, through one function. The uniformity IS the security property,
+	so there is deliberately no branch here to add a condition to later.
+]]
+local function watchCharacters(player: Player)
+	if player.Character ~= nil then
+		applyFootsteps(player.Character)
+	end
+
+	player.CharacterAdded:Connect(applyFootsteps)
+end
```

```diff
 function AudioController.Start()
+	for _, player in Players:GetPlayers() do
+		watchCharacters(player)
+	end
+
+	Players.PlayerAdded:Connect(watchCharacters)
+
 	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
```

#### Step 2.4: Wind and distant dogs as scheduled one-shots

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `lune run tests/audio-cues.test.luau`

A local timer asking the pure module which one-shots are eligible in this phase, so the *rule* is tested
in Lune and only the *timing* is left in the controller.

**Non-positional, and that is a scope decision rather than a shortcut.** Placing a dog at the edge of the
rice field would need map geometry, and the map is not in Git — a plan step that depends on a prop
somebody has to build is a step nobody can verify (CLAUDE.md: *"The map is not code"*). C30 dresses the
barrio and is explicitly outside this run. If positional ambience is wanted later it is a C30 follow-up,
and the note is in Follow Ups.

```diff
+--[[
+	WIND AND DISTANT DOGS. Scheduled locally at a random interval, per client, so two players standing
+	together do not hear the same dog at the same instant — the barrio should not sound synchronised.
+
+	`AudioCues.oneShotsFor` owns WHICH cues are eligible in a phase and is tested in Lune; this loop
+	owns only WHEN, and both its bounds are in `Config.Audio`. ENDING returns an empty list on
+	purpose: the reveal is §4.8's "screenshot people share" and a dog barking over it is a joke.
+
+	NON-POSITIONAL, parented to SoundService like the bed. Placing these in the world would need map
+	geometry, and the map lives in the place file rather than in Git — C30 dresses the barrio, and
+	this run does not touch it.
+
+	`Random.new()` with NO ARGUMENT. Nothing secret rides on this schedule, but a seed derived from a
+	round number or `os.time()` is client-reproducible (CLAUDE.md, "Inputs and seeds are") and it is
+	not a habit worth forming in a file that also handles the monster's cues.
+]]
+local rng = Random.new()
+
+local function oneShotLoop()
+	while true do
+		task.wait(rng:NextNumber(Config.Audio.OneShotMinSeconds, Config.Audio.OneShotMaxSeconds))
+
+		local eligible = AudioCues.oneShotsFor(phase)
+
+		if #eligible > 0 then
+			local cueId = eligible[rng:NextInteger(1, #eligible)]
+			playOneShot(cueId, Config.Audio.OneShotVolume, SoundService, `ambient one-shot in {phase}`)
+		end
+	end
+end
```

```diff
 function AudioController.Start()
 	for _, player in Players:GetPlayers() do
 		watchCharacters(player)
 	end
 
 	Players.PlayerAdded:Connect(watchCharacters)
 
 	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
 	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
+
+	-- One loop for the session. It reads `phase` rather than being restarted per phase, so a phase
+	-- change can never leave two schedulers running against the same SoundService.
+	task.spawn(oneShotLoop)
 end
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — every cue in this phase is driven by the phase alone or by the character it is
  attached to. Footsteps are the risk surface and are answered above: one code path, one volume, no
  branch. Confirm by reading for a `YourRole` reference anywhere in the file — there should be none, and
  `ClientRoundSnapshot.YourRole` is only ever the receiver's own role in any case (`Types.luau:544`).
- **Remote direction** — `RoundSnapshot` and `MonsterTransformed` are both in `EVENTS_DOWN`
  (`Remotes.luau:22-36`), consumed with `OnClientEvent`. Nothing is fired from the client.
- **Rate limiting** — no `OnServerEvent` handler exists in C29; `AntiCheatService` is not involved
  because no client request is added.
- **Magic numbers** — `check:config` governs `src/client/`, so every number here must come from
  `Config.Audio`. The `Volume = 0` start of the bed fade is the idiomatic `0` the checker allows
  (`check-config.mjs:33`).
- **Phase ownership** — this file reads `snapshot.Phase` and never writes one. `RoundService` remains the
  only writer (§6.4).
- **Player leaving mid-round** — `watchCharacters` connects `CharacterAdded` per player and never
  disconnects. That is a real leak on a long-lived server; see Issues below.
- **Strict Luau** — `snapshot.Phase` is already `Types.RoundPhase` off the payload, so it assigns to the
  module-level `phase` with no cast. `AudioCues.ambienceFor` takes that same union.
- **Mobile budget** — steady state after this phase is **one** looping Sound (the bed) plus at most one
  one-shot alive at a time (`CueCleanupSeconds` < `OneShotMinSeconds`, pinned in Step 1.4). Footsteps add
  zero instances by design.
- **Scope** — nothing from §3's OUT list; no map geometry is touched, which keeps C30 out of this run.

**Issues identified:**

- **`player.CharacterAdded` connections are never disconnected.** Eight players joining and leaving
  repeatedly on a long-lived server accumulates connections to dead Player instances. The fix is a
  `Players.PlayerRemoving` handler dropping the stored connection; it is small enough to fold into Step
  2.3 and must not be deferred, because the symptom is a slow client-side memory climb that no check
  reports.
- **The bed's fade-out tween and a rapid phase change can race.** IDLE → INTERMISSION → STARTING inside
  `BedFadeSeconds` would start a second fade on an instance already fading. `setBed` returning early when
  `cueId == bedCueId` covers the common case (IDLE and INTERMISSION share a bed), and the `Completed`
  connection destroys the instance exactly once, but the implementer should confirm the tween on a
  destroyed instance does not error.
- **`SoundService` as a parent is assumed to give a non-positional 2D sound.** Standard Roblox behaviour
  and used exactly this way in countless places, but it is not established in this codebase — listed with
  the other two engine assumptions in Follow Ups so the playtester can settle all three in one pass.

---

### Phase 3: The event cues — stinger, heartbeat, gate, sunrise

Every cue here is derived from data the client already holds. No remote is added, no payload widened, and
no server file is touched.

#### Step 3.1: Fill the transform stinger's `SoundId` from Config

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `npm run check:config`

The `TODO(C29)` at `AudioController.luau:47-48` becomes a `Config.Audio.Assets` read. Parenting, range
and rolloff are unchanged — the existing reasoning stands, with one header sentence corrected (Step 2.1).
`check:config` is the verify because this step introduces the volume and the id, and a volume typed
inline here is precisely what that check exists to catch.

```diff
 local function playStinger(character: Model)
 	local head = character:FindFirstChild("Head")
 
 	if head == nil or not head:IsA("BasePart") then
 		return
 	end
 
 	local existing = head:FindFirstChild(STINGER_NAME)
 
 	if existing ~= nil then
 		existing:Destroy()
 	end
 
-	local sound = Instance.new("Sound")
-	sound.Name = STINGER_NAME
-	-- TODO(C29): a Creator Store transform stinger. Empty until then — see the header.
-	sound.SoundId = ""
+	local sound = newSound("CUE_TRANSFORM", Config.Audio.StingerVolume, head)
+
+	if sound == nil then
+		return
+	end
+
+	sound.Name = STINGER_NAME
 	sound.RollOffMaxDistance = Config.Monster.TransformAudioRange
 	sound.RollOffMode = Enum.RollOffMode.Linear
-	sound.Parent = head
 
+	logCue("CUE_TRANSFORM", `at {character.Name}, {Config.Monster.TransformAudioRange} studs`)
 	sound:Play()
```

**The `Name` assignment stays after `newSound`**, which sets `Name = cueId`. `STINGER_NAME` is the
existing-instance sentinel three lines above, so the two must agree; leaving the cue id as the name would
silently disable the duplicate-stinger cleanup.

### Reading for the heartbeat — the plan's central argument, repeated here

Read the plan's preamble P1 before implementing 3.2 (`npm run plan:phase -- <plan> 1 --with-preamble`
prints it). The one-paragraph version, repeated here because a phase must be implementable from its own
slice:

**§5 asks for "heartbeat when the Aswang is near". Taken literally that cue cannot be built.** A
client-side proximity check needs the Aswang's position on the client; a server-sent "you are near"
boolean is a per-player difference derived from the secret, and
`.claude/lessons/absence-is-observable.md` is this repo's record of what a difference costs. A
server-created `Sound` on the Aswang's character **replicates**, so an exploiter reads
`workspace.<PlayerName>.Head.Heartbeat` out of the instance tree with the audio muted. So the shipped
cue is **transformed-only**: a looping `Sound` the LOCAL client creates on a character that is already
publicly a monster (`MonsterTransformed` is `FireAllClients` — `MonsterService.luau:468-476`), ranged
under §4.3's 40-stud tell by a relationship `tests/config.test.luau` pins. This is a deliberate deviation
from §5's wording and is raised in Follow Ups.

#### Step 3.2: The heartbeat — transformed-only, local, ranged under the tell

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `lune run tests/audio-cues.test.luau`

A looping `Sound` created by the local client on the transformed character, started on
`MonsterTransformed(true)` and stopped on `(false)`, on the phase leaving `ACTIVE`, and on a hard
timeout. The verify is the Lune suite because the rule under test — *the heartbeat is permitted in
`ACTIVE` and in no other phase, and never for a player outside the round* — is the part of this step
that can be proven from a terminal.

**THE STOP CONDITIONS ARE THE SECURITY-RELEVANT HALF OF THIS STEP, not the start.** A heartbeat that
outlives its transform is a permanent audible brand on an ex-Aswang, audible to every player who walks
within `HeartbeatRange` of them for the rest of the round. That is the C04 bug in sound —
`MonsterService`'s revert once restored hardcoded defaults instead of captured state and permanently
branded the ex-Aswang; only `exploit-auditor` found it, with `verify` and all five checks green over it.

And the revert broadcast is **not guaranteed**: `MonsterService.luau:435` fires the `false` payload only
`if monster.Announced and character ~= nil`, so a transform whose character has gone away sends no stop.
That specific case is safe by construction here — the `Sound` is parented to the character and dies with
it — but it is exactly why this cue does not rely on one signal.

```diff
+--[[
+	THE HEARTBEAT. Read this whole comment before changing any of it.
+
+	WHAT IT IS: a looping Sound, created BY THIS CLIENT, on a character every client already knows is
+	a monster. `MonsterTransformed` is FireAllClients and public by design (§4.3 — the tell IS the
+	mechanic), and the character is wearing a scale change, a red tint and a head PointLight while
+	this plays. So the cue publishes nothing that is not already on screen.
+
+	WHAT §5 ASKED FOR AND WHY THIS IS NOT IT: "heartbeat when the Aswang is near". For an
+	UNTRANSFORMED Aswang that cue is unbuildable. A client-side proximity check needs the Aswang's
+	position on the client. A server-sent "you are near" flag is a per-player DIFFERENCE derived from
+	the secret, which `check:secrecy` is a text tripwire and cannot see
+	(`.claude/lessons/absence-is-observable.md`). And a Sound the SERVER parents to a character
+	REPLICATES — `workspace.<Name>.Head.Heartbeat` names the Aswang to anyone reading the instance
+	tree, with the volume at zero. The deviation is recorded in the C29 plan's Follow Ups.
+
+	WHY IT STOPS THREE WAYS. A heartbeat that outlives its transform is a permanent audible brand on
+	an ex-Aswang — C04's revert bug, in sound. `MonsterService.luau:435` only broadcasts the revert
+	`if monster.Announced and character ~= nil`, so the false payload is not guaranteed to arrive:
+	  1. the revert broadcast, the normal path;
+	  2. the phase leaving ACTIVE, so a round ending mid-transform cannot leave one playing under the
+	     reveal;
+	  3. a hard timeout at the longest a transform can physically last, as the backstop for any path
+	     that sends neither.
+	The Sound is parented to the character, so a character destroyed or streamed out takes it with it.
+]]
+local HEARTBEAT_NAME = "AswangHeartbeat"
+
+local heartbeats: { [Model]: Sound } = {}
+
+local function stopHeartbeat(character: Model)
+	local sound = heartbeats[character]
+
+	if sound == nil then
+		return
+	end
+
+	heartbeats[character] = nil
+	logCue("CUE_HEARTBEAT", `stopped on {character.Name}`)
+
+	if sound.Parent ~= nil then
+		sound:Destroy()
+	end
+end
+
+local function stopAllHeartbeats()
+	for character in heartbeats do
+		stopHeartbeat(character)
+	end
+end
+
+local function startHeartbeat(character: Model)
+	if not AudioCues.isCuePermitted("CUE_HEARTBEAT", phase, state) then
+		return
+	end
+
+	local head = character:FindFirstChild("Head")
+
+	if head == nil or not head:IsA("BasePart") then
+		return
+	end
+
+	stopHeartbeat(character)
+
+	local sound = newSound("CUE_HEARTBEAT", Config.Audio.HeartbeatVolume, head)
+
+	if sound == nil then
+		return
+	end
+
+	sound.Name = HEARTBEAT_NAME
+	sound.Looped = true
+	-- Pinned <= Monster.TransformAudioRange by tests/config.test.luau. The heartbeat must never carry
+	-- further than the tell §4.3 specifies.
+	sound.RollOffMaxDistance = Config.Audio.HeartbeatRange
+	sound.RollOffMode = Enum.RollOffMode.Linear
+
+	heartbeats[character] = sound
+	logCue("CUE_HEARTBEAT", `on {character.Name}, {Config.Audio.HeartbeatRange} studs`)
+	sound:Play()
+
+	-- STOP CONDITION 3. Longer than any legitimate transform: the forced revert fires at
+	-- MaxTransformTime and the revert itself takes RevertTime.
+	task.delay(Config.Monster.MaxTransformTime + Config.Monster.RevertTime, function()
+		if heartbeats[character] == sound then
+			stopHeartbeat(character)
+		end
+	end)
+end
```

```diff
 local function onTransformed(payload: Types.MonsterTransformedPayload)
-	-- Only the transform, not the revert. A revert stinger would tell every client the exact moment a
-	-- monster became a person again, which is information a witness should get by looking.
 	if payload.Transformed then
 		playStinger(payload.Character)
+		startHeartbeat(payload.Character)
+	else
+		-- STOP CONDITION 1. Still NO revert STINGER — a revert sound would announce the exact moment
+		-- a monster became a person again, which is information a witness should get by looking. The
+		-- heartbeat merely CEASES, which is the absence of a cue rather than a cue.
+		stopHeartbeat(payload.Character)
 	end
 end
```

```diff
 local function onSnapshot(snapshot: Types.ClientRoundSnapshot)
 	phase = snapshot.Phase
 	state = snapshot.YourState
 
 	setBed(AudioCues.ambienceFor(phase))
+
+	-- STOP CONDITION 2. A round ending mid-transform must not leave a heartbeat playing under the
+	-- reveal, and `AudioCues` permits this cue in ACTIVE only.
+	if phase ~= "ACTIVE" then
+		stopAllHeartbeats()
+	end
 end
```

#### Step 3.3: The gate cue, from `GateOpen` false→true

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `npm run check:remotes`

`GateService` fires no remote and has no sound by design; the gate opening is already a field on every
snapshot, so the cue is an edge detector on it. `check:remotes` is the verify for the same reason as Step
2.2 — the claim being checked is that **no `RequestEscape`-shaped remote appeared** and no new name
entered `Remotes.luau`.

**Do not add a remote or a server sound for this.** `GateService.luau:20-22` is explicit: *"NO REMOTE.
The gate is reached by walking, and the server measures the walk. There is no `RequestEscape` and there
must not be."* And `GateService.luau:5-9` is equally explicit that an Aswang reaching an open gate must
produce *"no refusal, no verdict, no remote, no sound, no prompt"* — a gate cue keyed to *arrival* rather
than to *opening* would break that. This cue fires on the gate **opening**, which is a global fact
already on every client's snapshot, and fires identically for all eight players.

**Non-positional, like the one-shots.** A cue at the gate's own position would be better navigation and
needs the `EscapeGate`-tagged part, i.e. the map — outside this run (see Follow Ups).

```diff
+--[[
+	THE GATE. §4.8's "5/5 tasks done AND at least one survivor reaches the escape gate" — this is the
+	first half becoming true, and it is the loudest good-news moment survivors get.
+
+	AN EDGE DETECTOR ON A FIELD EVERY CLIENT ALREADY HAS. `GateOpen` is on `ClientRoundSnapshot`
+	(`Types.luau:543`) and `RoundService` derives it from the task count — `GateService` fires no
+	remote at all and must not (`GateService.luau:20-22`), because a client-callable escape is a free
+	win behind whatever validation somebody remembers to write.
+
+	IT FIRES ON THE GATE OPENING, NOT ON ANYONE REACHING IT. `GateService`'s header requires that an
+	Aswang at an open gate produces "no refusal, no verdict, no remote, no sound, no prompt" — an
+	arrival cue would be exactly the sound that header forbids, and it would leak by omission the
+	moment an Aswang walked through and nothing played.
+]]
+local gateWasOpen = false
+
+local function onGateChanged(open: boolean)
+	if open == gateWasOpen then
+		return
+	end
+
+	gateWasOpen = open
+
+	if open then
+		playOneShot("CUE_GATE_OPEN", Config.Audio.GateVolume, SoundService, "gate opened")
+	end
+end
```

#### Step 3.4: The sunrise cue, from the same pure function the sky uses

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `lune run tests/config.test.luau`

`SkyCycle.progressFor` crossing `Config.Audio.SunriseAtProgress`, fired once per round. Verified by
`lune run tests/config.test.luau`, which pins the trigger strictly inside `(0, 1)` — a threshold at 1.0
would fire on the `ENDING` pin and land on top of the reveal, and a threshold at 0 would fire at
`STARTING`.

**Reuse `SkyCycle.progressFor`; do not re-derive the progress.** `SkyController.luau:160-166` already
calls it with exactly this input, and the sound and the sky must agree about when dawn is — two
independent derivations of the same moment is how they drift apart, and nobody would notice for weeks.

```diff
+--[[
+	THE SUNRISE. Appendix C.3's diegetic clock, given a sound.
+
+	SAME PURE FUNCTION AS THE SKY, deliberately. `SkyController` renders the round clock as a sunrise
+	from `SkyCycle.progressFor` over the same snapshot; if this cue derived "how far through the
+	night are we" its own way, the sound and the sky would drift apart and no check would say so.
+
+	FIRE-ONCE PER ROUND, reset on the round number changing rather than on a phase, because an
+	ABORTED round (§6.4's edge cases) can leave ENDING without ever passing through the threshold.
+]]
+local sunriseFiredFor: number? = nil
+
+local function onSunriseProgress(snapshot: Types.ClientRoundSnapshot)
+	if sunriseFiredFor == snapshot.RoundNumber then
+		return
+	end
+
+	local progress = SkyCycle.progressFor({
+		Phase = snapshot.Phase,
+		SecondsRemaining = snapshot.SecondsRemaining,
+		Duration = Config.Round.Duration,
+	})
+
+	if progress < Config.Audio.SunriseAtProgress then
+		return
+	end
+
+	if not AudioCues.isCuePermitted("CUE_SUNRISE", snapshot.Phase, snapshot.YourState) then
+		return
+	end
+
+	sunriseFiredFor = snapshot.RoundNumber
+	playOneShot("CUE_SUNRISE", Config.Audio.SunriseVolume, SoundService, "dawn")
+end
```

And the snapshot handler, now complete:

```diff
 local function onSnapshot(snapshot: Types.ClientRoundSnapshot)
 	phase = snapshot.Phase
 	state = snapshot.YourState
 
 	setBed(AudioCues.ambienceFor(phase))
 
 	if phase ~= "ACTIVE" then
 		stopAllHeartbeats()
 	end
+
+	onGateChanged(snapshot.GateOpen)
+	onSunriseProgress(snapshot)
 end
```

#### Step 3.5: The secrecy statement — one comment block an auditor can trace

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `npm run check:secrecy`

A header section naming, per cue, its audience and what a compromised client learns — the four
`exploit-auditor` questions answered at a `file:line` rather than in this document only. 🔒 gates this
chunk, and an auditor that has to reconstruct the argument from a plan directory is an auditor spending
its budget on reading.

```diff
+--[[
+	═══ THE SECRECY STATEMENT ═════════════════════════════════════════════════
+
+	Every cue in this file, its audience, and what a compromised client learns from it. 🔒
+	`exploit-auditor` gates C29; these are its four questions, answered here rather than in a plan
+	document.
+
+	1. DOES ANY CUE TAKE A ROLE AS AN INPUT?  No. Grep this file for `YourRole` and `Role` — there is
+	   no hit. The only inputs are `snapshot.Phase`, `snapshot.YourState`, `snapshot.GateOpen`,
+	   `snapshot.SecondsRemaining` and the Character on `MonsterTransformed`. `ClientRoundSnapshot`
+	   carries `YourRole`, and this file does not read it.
+
+	2. IS ANY CUE FIRED TO ONE PLAYER AND NOT ANOTHER?  No cue is FIRED at all — nothing here is a
+	   remote. Every decision is made on each client from a payload every client received, through
+	   `shared/pure/AudioCues`, which has no player parameter. Two clients in the same phase and the
+	   same PlayerState reach identical answers by construction. The one asymmetry is the STATE gate:
+	   a player in LOBBY or SPECTATOR hears no monster cue, which withholds information from someone
+	   outside the round rather than granting it to someone inside it.
+
+	3. DOES ANY Sound REPLICATE?  No. Every Sound in this file is created by `Instance.new` on the
+	   CLIENT, so it exists in no other client's tree and on no server. This is why the heartbeat is
+	   safe and why a server-created one would not be: an Instance the server parents to a character
+	   is readable by every client with `workspace.<Name>.Head` and the volume at zero.
+
+	4. CAN A CUE OUTLIVE THE STATE IT ANNOUNCES?  This is the live risk and it is the reason the
+	   heartbeat has three stop conditions. A looping monster cue left running is a permanent audible
+	   brand on an ex-Aswang — C04's revert bug in sound, which had `verify` and all five checks green
+	   over it. One-shots are bounded by `Config.Audio.CueCleanupSeconds`; the bed is not a monster
+	   cue; the heartbeat stops on the revert, on the phase leaving ACTIVE, and on a hard timeout.
+
+	WHAT AN OBSERVER ON A COMPROMISED CLIENT CAN INFER FROM ALL OF IT: that a character they can
+	already see is a monster is a monster. Nothing else.
+]]
```

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the four answers above, verified by reading rather than asserted. The specific
  thing to re-check after any edit to this phase: does any cue exist for a player whose role differs,
  in either direction? Absence is as observable as presence
  (`.claude/lessons/absence-is-observable.md`).
- **Remote direction** — `MonsterTransformed` and `RoundSnapshot` are both `EVENTS_DOWN`, consumed with
  `OnClientEvent`. No new remote is declared in either list.
- **Rate limiting** — no `OnServerEvent` handler is added, so `AntiCheatService` is not consulted and
  `check:ratelimit` has nothing new to inspect. This is a consequence of the design, not an omission: the
  client never asks the server for anything in C29.
- **Magic numbers** — `HeartbeatRange`, `HeartbeatVolume`, `StingerVolume`, `GateVolume`,
  `SunriseVolume` and `SunriseAtProgress` all read from `Config.Audio`. The timeout is composed from two
  existing `Config.Monster` fields rather than a new number.
- **Phase ownership** — this file reads the phase from the snapshot and calls no `setPhase`.
- **Player leaving mid-round** — §6.4's edge cases that apply here: (a) the Aswang leaves while
  transformed — no revert broadcast fires (`MonsterService.luau:435`), and the heartbeat dies with the
  character plus the hard timeout; (b) the round is aborted mid-transform — the phase leaves `ACTIVE` and
  `stopAllHeartbeats` runs; (c) a player joins mid-round — they never received the transform broadcast,
  so they start no heartbeat, which is a missing cue rather than a stale one and is the safe direction.
- **Strict Luau** — `snapshot.Phase` and `snapshot.YourState` arrive already typed off
  `ClientRoundSnapshot`, so `isCuePermitted(id, phase, state)` needs no cast. `heartbeats:
  { [Model]: Sound }` needs its annotation or it infers as an empty table.
- **Mobile budget** — worst case adds **one** looping Sound (there is exactly one Aswang) plus one bed
  plus one bounded one-shot. Under §5's constraint. No lights, no particles, no per-frame work: every
  cue in this phase is event-driven off a snapshot already arriving at `Round.SnapshotInterval`.
- **Scope** — nothing from §3's OUT list. No map geometry, so C30 stays out of this run.

**Issues identified:**

- **Iterating `heartbeats` while `stopHeartbeat` clears keys from it.** `stopAllHeartbeats` mutates the
  table it is iterating. Removing a key during `pairs` traversal is defined in Lua, but the implementer
  should collect the characters first if there is any doubt — the failure mode is one heartbeat surviving
  the round, which is the exact leak this cue is arranged to prevent.
- **The stinger and heartbeat both `FindFirstChild("Head")` with no wait.** `MonsterTransformed` arrives
  with a Character the server already applied the look to, so the Head exists server-side — but under
  §5's `StreamingEnabled` a *distant* character may not be replicated to this client at all, in which
  case both cues silently do nothing. That is the correct outcome (an unreplicated character is one you
  cannot hear anyway) and it is worth confirming with the playtester rather than assuming.
- **`Config.Audio.SunriseAtProgress` interacts with `SkyCycle`'s ENDING pin.** `progressFor` pins
  `ENDING` to 1, so a round that ends *early* (all survivors dead) jumps straight past the threshold and
  fires the sunrise cue on the reveal. Decide deliberately: either that is wanted (dawn as the round's
  full stop) or the cue should be refused in `ENDING` by removing it from `PERMITTED_PHASES`. **The
  plan's default is to allow it**, on the grounds that the sky does the same jump and the two should
  agree; flag it for the headphone listen in Step 4.5.

---

### Phase 4: Sourcing, the durable record, and the human listen

The half of C29 that is delegable (search) and the half that is not (approval), kept apart on purpose.

#### Step 4.1: Source the cues and write `docs/AUDIO-ASSETS.md`

**File:** `docs/AUDIO-ASSETS.md`
**Verify:** `test -f docs/AUDIO-ASSETS.md`

`search_asset` with `priceFilter: "free"`, `verifiedCreatorsOnly: true` and the duration split the
`asset-pipeline` skill specifies; every candidate recorded with id, creator, duration and date.

**The search half is delegable; the approval half is not.** Studio is connected, so this step legitimately
runs `search_asset` / `insert_asset` — but no agent can answer "does this sound scary", which is why C29
is 🧍 and why Step 4.5 exists.

**Duration filters are the whole trick** (`asset-pipeline` SKILL, "Audio — sourced, not generated"):
searching without them returns a useless mix. The split, per cue:

| Cue | Query direction | `audioMinDuration` | `audioMaxDuration` |
| --- | --- | --- | --- |
| `CUE_BED_LOBBY` | quiet village night, low crickets | 30 | 180 |
| `CUE_BED_NIGHT` | night ambience crickets, tense | 30 | 180 |
| `CUE_BED_DAWN` | dawn birds, morning ambience | 30 | 180 |
| `CUE_WIND` | wind gust through trees | 3 | 15 |
| `CUE_DOGS` | distant dogs barking at night | 2 | 10 |
| `CUE_FOOTSTEP` | single footstep dirt gravel | 0.2 | 2 |
| `CUE_TRANSFORM` | monster transformation growl stinger | 0.5 | 4 |
| `CUE_HEARTBEAT` | slow heartbeat loop | 1 | 10 |
| `CUE_GATE_OPEN` | heavy wooden gate opening creak | 1 | 6 |
| `CUE_SUNRISE` | warm rising swell, relief | 2 | 8 |

Two of these need a property the search cannot filter for and a person must confirm on the listen:
`CUE_BED_*` and `CUE_HEARTBEAT` are **looped**, so they must not have an audible seam. The heartbeat is
the harder one — a heartbeat that clicks on the loop point is worse than no heartbeat.

`CUE_TRANSFORM` gets the most time. The `asset-pipeline` skill says so plainly: *"the single
highest-value sound in the game… it is not decoration, it is the tell that makes the kill mechanic
fair."*

`docs/AUDIO-ASSETS.md` is the durable record, and it exists because `Config.Audio.Assets` **cannot be
one**: an id alone does not say who made it, how long it is, or when it was chosen, and a Creator Store
asset that gets moderated away leaves a hole you cannot identify from a number. The place file is not
searchable and `git log` will not have it.

```diff
+# Audio assets
+
+Every sound in the game, with the record `Config.Audio.Assets` cannot hold. C29 (§5, §14.3).
+
+**Sourced, never generated** — there is no text-to-audio tool in this toolchain. Everything here came
+from `search_asset` over the Creator Store with `priceFilter: "free"` and `verifiedCreatorsOnly: true`.
+
+**If a sound stops playing, look here first.** Roblox moderation can pull an asset, and the symptom is
+silence with no error and nothing in `git status`. The row below is how you know what used to be there.
+
+| Cue id | Asset id | Name | Creator | Duration | Sourced | Approved |
+| --- | --- | --- | --- | --- | --- | --- |
+| CUE_BED_LOBBY | | | | | | |
+| CUE_BED_NIGHT | | | | | | |
+| CUE_BED_DAWN | | | | | | |
+| CUE_WIND | | | | | | |
+| CUE_DOGS | | | | | | |
+| CUE_FOOTSTEP | | | | | | |
+| CUE_TRANSFORM | | | | | | |
+| CUE_HEARTBEAT | | | | | | |
+| CUE_GATE_OPEN | | | | | | |
+| CUE_SUNRISE | | | | | | |
+
+## Rejected candidates
+
+Kept deliberately: the second-best option for each cue, so a moderated asset is a one-line swap rather
+than a second search.
+
+| Cue id | Asset id | Why not chosen |
+| --- | --- | --- |
```

#### Step 4.2: Fill `Config.Audio.Assets` with the sourced ids

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

One edit, one table. The format test from Step 1.4 — every value is `""` or matches
`^rbxassetid://%d+$` — is what makes this step checkable at all; without it the only evidence would be
that somebody typed something.

Fill only the cues that were actually approved. **A cue left blank is a working state, not a bug**, so a
partial pass ships fine and the next pass fills the rest.

```diff
 		Assets = {
-			CUE_BED_NIGHT = "",
+			CUE_BED_NIGHT = "rbxassetid://0000000000",
```

#### Step 4.3: Whole-tree gate

**File:** `src/shared/Config.luau`
**Verify:** `npm run verify`

The full gate — analyze, lint, format, the five checks, every Lune suite and the harness. Runs here
because Step 4.2 is the last edit to tracked source, and `check:config` in particular should be re-run
after ids land: an asset id is a string, but a *volume* pasted alongside one is a number in the wrong
file, and this is the step where somebody would paste one.

#### Step 4.4: Playtester captures a console line per cue

**File:** `.claude/plans/feature-c29-audio-pass-plan/verification.md`
**Verify:** `test -f .claude/plans/feature-c29-audio-pass-plan/verification.md`

`Debug.VerboseLogging` on; drive a full round; capture `[AudioController] cue …` for every id in the set.

**Set the debug values before launching the playtester — it cannot edit `Config.luau` and will correctly
refuse.** A round cycle is 461s at committed values. Set `Round.Intermission/Duration/EndScreen` to
8/20/6 plus `Debug.SoloTesting` and `Debug.VerboseLogging`, and revert all five afterwards
(`guard-commit.mjs` runs `check:debug` and refuses to commit them).

Note the interaction this phase has with the shortened round: `Config.Audio.OneShotMinSeconds` is 25, so
**wind and dogs will not fire inside a 20-second test round**. Either drop `OneShotMinSeconds` for the
capture run or accept those two cues as unproven by console and confirmed by ear in Step 4.5 — but say
which, in `verification.md`, rather than leaving two cues quietly unobserved.

The brief for the playtester should name the files, the phase and the questions rather than "test the
audio":

> Verify Phase 3 of `.claude/plans/feature-c29-audio-pass-plan/` — load it with
> `npm run plan:phase -- .claude/plans/feature-c29-audio-pass-plan 3`. Drive one full round solo with
> `Debug.VerboseLogging` on and capture the console. Answer: (1) does a `[AudioController] cue
> CUE_BED_*` line appear at each phase change, (2) does `CUE_TRANSFORM` and then `CUE_HEARTBEAT` log on
> a transform and does `CUE_HEARTBEAT — stopped` log on the revert, (3) does `CUE_GATE_OPEN` log exactly
> once when the gate opens, (4) does `CUE_SUNRISE` log exactly once near the end, and (5) does any
> `AswangHeartbeat` instance survive the round — check `workspace` after ENDING.

Question (5) is the one that matters most and is the only one a console line cannot answer on its own.

#### Step 4.5: 🧍 The headphone listen

**File:** `docs/AUDIO-ASSETS.md`

No verify line, deliberately. "Does this sound scary" is not a check — this step reports as
`unverifiable` and marks the phase `needs-human`, which is accurate. Inventing a `grep` here would make
the plan look greener and tell nobody anything.

What the listen is actually for, since these are the failures a console cannot see:

1. **Do the two loops seam?** `CUE_BED_*` and `CUE_HEARTBEAT` loop; an audible click at the loop point
   is the single most common defect in free ambience and no filter finds it.
2. **Does the bed drown the tell?** §4.3's transform is the mechanic. If the night ambience competes with
   it at 40 studs, lower `Config.Audio.BedVolume` — that is a `balance(audio):` commit, which is what
   that commit type exists for.
3. **Does the sunrise cue on an early ENDING land wrong?** Flagged in Phase 3's Issues: a round that ends
   early jumps the sky's progress to 1 and fires dawn on the reveal. Decide by listening.
4. **Does the heartbeat read as dread or as noise at `HeartbeatRange` (28 studs)?** That number is a
   guess made against §4.3's 40 and is the first thing to tune.
5. **Is the gate cue audible from across the barrio?** It is non-positional, so it will be — confirm that
   is wanted rather than surprising.

Then publish the place (`asset-pipeline`: everything inserted lands in the place file, which is not in
Git, and Roblox's cloud version history is its only backup).

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — sourcing adds no code paths. The one thing to re-read: nothing in
  `docs/AUDIO-ASSETS.md` should describe a cue's *audience*, because a doc that says "played to the
  Aswang" is a design somebody will later implement.
- **Remote direction** — unchanged; C29 declares no remote.
- **Rate limiting** — not applicable.
- **Magic numbers** — the risk in this phase specifically: a volume pasted next to an asset id while
  filling the table is fine (it is in `Config`), but a volume pasted into the *controller* while
  eyeballing a mix is a `check:config` finding. Run `npm run verify` after any tuning.
- **Phase ownership** — unchanged.
- **Player leaving mid-round** — the playtester should be asked question (5) above explicitly: no
  `AswangHeartbeat` instance may survive a round under any exit path.
- **Strict Luau** — filling strings into an existing table cannot change a type.
- **Mobile budget** — this is where it becomes real. Confirm on the phone pass that the added Sounds cost
  nothing measurable against `Config.Performance.TargetFPSMobile` (30). Audio decode is cheap but
  simultaneous streams are not free, and C27's number is the baseline to compare against.
- **Scope** — `search_asset` makes it easy to wander into props. **C30 is explicitly not in this run**:
  audio only, no geometry, no map dressing.

**Issues identified:**

- **A short debug round hides two cues.** `OneShotMinSeconds` (25) exceeds a 20-second debug round, so
  wind and dogs never fire during the capture. Named in Step 4.4 with the two acceptable resolutions;
  the unacceptable one is not noticing.
- **Moderation risk is permanent, not one-off.** A Creator Store asset can be pulled months later and the
  symptom is silence — no error, no `git status` entry. `docs/AUDIO-ASSETS.md`'s rejected-candidates
  table is the mitigation, and it is only a mitigation if it is actually filled in.
- **Approval is a gate, not a formality.** If the user does not approve a sound, the correct action is to
  leave that cue blank and ship. Every phase of this plan works with a blank id, which is the property
  that makes that possible.

---

---

## 3. Related Files

| File | Role in this plan | Review |
| --- | --- | --- |
| `src/client/Controllers/AudioController.luau` | Rewritten. Owns all ten cues | `AudioController-review.luau` |
| `src/shared/pure/AudioCues.luau` | **New.** The phase/state rule, Lune-tested | — |
| `tests/audio-cues.test.luau` | **New.** Proves the rule | — |
| `src/shared/Config.luau` | Gains the `Audio` block | `Config-review.luau` |
| `tests/config.test.luau` | Gains the audio relationship pins | `config.test-review.luau` |
| `docs/AUDIO-ASSETS.md` | **New.** The durable asset record | — |
| `src/client/Controllers/SkyController.luau` | The precedent this plan follows; `SkyCycle` reused | `SkyController-review.luau` |
| `src/shared/pure/SkyCycle.luau` | `progressFor` drives the sunrise cue | `SkyCycle-review.luau` |
| `src/server/Services/MonsterService.luau` | **Read only.** Broadcast shape and revert guarantees | `MonsterService-review.luau` |
| `src/server/Services/GateService.luau` | **Read only.** Why the gate cue is snapshot-derived | `GateService-review.luau` |
| `src/shared/Types.luau` | `ClientRoundSnapshot`, `MonsterTransformedPayload` | `Types-review.luau` |
| `src/shared/Remotes.luau` | **Unchanged.** No new name in either list | `Remotes-review.luau` |

**Not touched by this plan, deliberately:** every file under `src/server/`. C29 adds no server code, no
remote and no payload field. If an implementation of this plan finds itself editing a service, something
has gone wrong with the design and it should stop and re-read preamble P1.

## 4. Follow Ups

### Questions / Clarifications

**1. 🔴 The heartbeat deviates from §5's wording, and the spec should be amended rather than quietly
reinterpreted.** §5 lists *"heartbeat when the Aswang is near"*. This plan ships *"heartbeat while a
transformed Aswang is near"*, because the literal cue is unbuildable under §6.2 — the argument is in
preamble P1 and the short version is that a server-created `Sound` on the Aswang's character replicates
and names them in the instance tree. CLAUDE.md's precedence rule says the spec wins and the conflict gets
raised, so: **this needs a one-line amendment to §5, or a decision to cut the cue.** Both are fine; a
plan that silently narrowed the spec's wording is not.

**2. 🟡 A factual correction to `AudioController.luau`'s existing header, offered rather than assumed.**
Lines 13–18 justify parenting the stinger to the transforming character's Head partly on the grounds that
a manual distance check *"would ignore the geometry between the two players"*, implying Roblox's rolloff
does not. **I believe that is false for a classic `Sound`**, which attenuates by distance and does not
model occlusion — but I have not confirmed it and this codebase contains no evidence either way, so under
CLAUDE.md's "never guess a Roblox API's behaviour" I am flagging it rather than asserting it. **The
decision it supports is unaffected**: parenting to the Head is still right because the engine owns the
position and the falloff, and because a manual check would need the monster's position on the client.
Step 2.1 rewrites the paragraph to stand on those two reasons alone. Someone should confirm and either
delete the parenthetical or restore the original claim with a citation.

**3. 🟡 Three engine behaviours this plan relies on that are not established in this repo.** All three are
standard and all three are cheap for the playtester to settle in one pass — grouped so it is one question,
not three:
   - a `Sound` parented to `SoundService` plays non-positionally (the bed, the one-shots, the gate, the
     sunrise all assume this);
   - Roblox's default character footstep sound — where it lives, what it is named, and whether the local
     client owns it for *remote* characters. **Step 2.3 is written to no-op if this is wrong**, so it is
     a quality question rather than a correctness one;
   - a `Sound` whose parent is destroyed (a character streaming out under §5's `StreamingEnabled`) is
     destroyed with it and does not error a pending `task.delay` that touches it.

**4. 🟢 Positional ambience is a C30 question, not a C29 one.** Wind, dogs and the gate cue are
non-positional here because placing them needs map geometry, and the map is not in Git. When C30 dresses
the barrio it can attach emitters to props; that is a better sound and it is a different chunk.

**5. 🟢 Should the Aswang hear their own heartbeat?** A cue played on the Aswang's own client, derived
from `snapshot.YourRole`, would be safe by the same argument as the HUD showing them their role — it is
local, it names nobody else, and it reaches no second client. It is also good design (it makes the
transform feel like a commitment). **Not built here**, purely to keep this chunk at four phases; it would
be one cue id and one condition. Raise it after the headphone listen, when there is an opinion about
whether the mix has room.

**6. 🟢 `check:secrecy` cannot see any of this and that is expected.** Every leak this plan is arranged
against — a per-player cue, a louder footstep, a heartbeat outliving its transform — carries no role
token and would pass the text tripwire. That is what 🔒 `exploit-auditor` is for, which is why Step 3.5
writes the four answers into the file rather than leaving them here.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| — | §5's literal "heartbeat when the Aswang is near" is unbuildable under §6.2; plan ships the transformed-only subset | 🔴 High | Open — needs a spec amendment or a decision to cut |
| 2 | `AudioController.luau:13-18` claims Roblox rolloff accounts for geometry between players; believed false, unconfirmed | 🟡 Medium | Open — paragraph rewritten to not depend on it |
| 2 | `player.CharacterAdded` connections never disconnected; leaks on a long-lived server | 🟡 Medium | Fix inside Step 2.3 |
| 2 | Bed crossfade can race a rapid phase change | 🟢 Low | Confirm tween-on-destroyed does not error |
| 3 | `stopAllHeartbeats` mutates the table it iterates | 🟡 Medium | Collect keys first if in doubt |
| 3 | Early ENDING jumps sky progress to 1 and fires the sunrise cue on the reveal | 🟢 Low | Deliberate default; decide on the listen (4.5) |
| 3 | A character not replicated under `StreamingEnabled` silently gets no stinger and no heartbeat | 🟢 Low | Correct behaviour; confirm with playtester |
| 4 | A 20s debug round is shorter than `OneShotMinSeconds` (25), so wind and dogs never fire during capture | 🟡 Medium | Named in 4.4; must be resolved in `verification.md` |
| 4 | Creator Store assets can be moderated away later; symptom is silence with no error | 🟡 Medium | `docs/AUDIO-ASSETS.md` rejected-candidates table |
| — | Footsteps depend on unverified default-character-sound behaviour | 🟢 Low | Step 2.3 no-ops if absent; secrecy property holds either way |
