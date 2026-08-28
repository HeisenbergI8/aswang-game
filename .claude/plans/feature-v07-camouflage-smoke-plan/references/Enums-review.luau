--!strict
--[[
	REVIEW — src/shared/Enums.luau (92 lines)

	Read because two of its blocks were written FOR this chunk and one of them names V07 explicitly as
	the chunk that answers a deferred design question.
]]

-- src/shared/Enums.luau:9-11
-- The `:: Types.X` casts are load-bearing under --!strict. Without them every field infers as plain
-- `string`, and passing one to a parameter typed as the literal union fails to typecheck.
-- IMPORTANT: six of the scaffold's seven original analyze errors were exactly this. Anywhere V07
-- constructs a form or a state from a bare string literal — in `AmbientService`, in `MonsterService`,
-- in a test loop — it needs the cast or `npm run analyze` reds.

-- src/shared/Enums.luau:60-79
--[[
	V02, §4.3. What the Aswang is doing.

	V02 DECLARES THESE AND WIRES NONE OF THEM. Read `Types.MonsterState`'s comment before building the
	state machine: `Exposed` reads as a LATCH (§4.3 — camouflage is locked "until it has taken a salt
	hit", and §4.6 — the buntot pagi kills an Aswang that is Exposed AND weakened) while the other four
	read as mutually-exclusive activities. Whether this is one field or a field plus a flag is that
	chunk's decision, and V02 must not pre-empt it by wiring a `setState`.
]]
Enums.MonsterState = table.freeze({
	Normal = "NORMAL" :: Types.MonsterState,
	Transformed = "TRANSFORMED" :: Types.MonsterState,
	Exposed = "EXPOSED" :: Types.MonsterState,
	Feeding = "FEEDING" :: Types.MonsterState,
	Camouflaged = "CAMOUFLAGED" :: Types.MonsterState,
})
-- IMPORTANT: "that chunk's decision" IS V07 — this is the chunk that gives `Camouflaged` a producer.
-- The plan's answer is A FIELD PLUS A FLAG, matching what V06 chose for `Feeding`: `Camouflaged`
-- and `Transformed` are separate booleans on the server record and `monsterStateOf` derives the enum
-- on demand. The reason is the one V06 gave — `Transformed` has four readers outside `MonsterService`
-- and `Exposed` is a latch that coexists with the form, so collapsing them into one field would
-- shadow a state that must remain simultaneously true.
-- QUESTION: this comment still says the decision is pending. Whichever chunk next edits this file
-- should update it to record the answer — raised in the plan's Follow Ups (Q7) rather than edited
-- here, because V07's diff has no other reason to touch this block.
-- NOTE: "`Weakened` is deliberately absent. It is a HEALTH PREDICATE, not a state." The same test
-- applies to V07's two booleans and both pass: `HasBeenRevealed` and `HasCamouflageCharge` are facts
-- about history and resources, not activities, so neither belongs in this enum either.

-- src/shared/Enums.luau:81-90
-- V02, §4.3. The four forms a REVEALED Aswang may wear. §4.5's "It's the [animal]!" phrase names one
-- of these, which is what stops camouflage being unbeatable — a barrio full of scenery becomes a
-- barrio with one monster in it. Villager is in the set because three animals in an empty street is
-- a tell; a fourth option that looks like a person is what makes the guess cost something.
Enums.CamouflageForm = table.freeze({
	Cat = "CAT" :: Types.CamouflageForm,
	Dog = "DOG" :: Types.CamouflageForm,
	Pig = "PIG" :: Types.CamouflageForm,
	Villager = "VILLAGER" :: Types.CamouflageForm,
})
-- IMPORTANT: "A REVEALED Aswang" — the gate is written into the enum's own comment, at V02, before
-- any code could enforce it. V07 is where it becomes enforceable.
-- IMPORTANT: §4.5's counterplay — "It's the cat!" — is why `Config.Ambient.PerForm` has a FLOOR
-- rather than just a value. At one entity per form, the quick-chat phrase stops being a guess and
-- becomes a lookup: the only cat left standing IS the monster. `tests/config.test.luau` pins >= 2.
-- NOTE: `AmbientService` iterates this table to spawn the population, and `AmbientRoster` re-declares
-- the union locally (Lune has no `script`). The two are structurally the same type.

-- src/shared/Enums.luau:41-49
-- NOTE: worth reading before adding anything to `check:scope`'s neighbourhood. `BuntotPagi` "splits to
-- Buntot + Pagi under check:scope's word splitter and matches neither `weapons?` nor anything else on
-- the list; that is by design, not by luck." V07 adds `Ambient`, `Camouflage` and `Smoke` tokens to
-- `src/` — none is on §3's OUT list, but the note is a reminder that the check reads WORDS, so a new
-- identifier is worth a glance at that list before it ships.
