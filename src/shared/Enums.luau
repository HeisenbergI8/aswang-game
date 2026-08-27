--!strict
--[[
	Enums — shared string constants.

	Using string literals (not numbers) so they're readable in logs and analytics.
]]

-- The `:: Types.X` casts are load-bearing under --!strict. Without them every field
-- infers as plain `string`, and passing one to a parameter typed as the literal union
-- fails to typecheck — which is how the scaffold shipped six analyze errors.
local Types = require(script.Parent.Types)

local Enums = {}

Enums.RoundPhase = table.freeze({
	Idle = "IDLE" :: Types.RoundPhase,
	Intermission = "INTERMISSION" :: Types.RoundPhase,
	Starting = "STARTING" :: Types.RoundPhase,
	Active = "ACTIVE" :: Types.RoundPhase,
	Ending = "ENDING" :: Types.RoundPhase,
})

Enums.Role = table.freeze({
	Survivor = "SURVIVOR" :: Types.Role,
	Aswang = "ASWANG" :: Types.Role,
})

Enums.PlayerState = table.freeze({
	Lobby = "LOBBY" :: Types.PlayerState,
	Alive = "ALIVE" :: Types.PlayerState,
	Dead = "DEAD" :: Types.PlayerState, -- V01: killed in-round. Spectates; the corpse is the body
	Spectator = "SPECTATOR" :: Types.PlayerState, -- joined mid-round
})

Enums.RoundResult = table.freeze({
	SurvivorsEscaped = "SURVIVORS_ESCAPED" :: Types.RoundResult,
	AswangWins = "ASWANG_WINS" :: Types.RoundResult,
	Timeout = "TIMEOUT" :: Types.RoundResult,
	Aborted = "ABORTED" :: Types.RoundResult, -- e.g. the Aswang disconnected
})

-- V02, §4.4/§4.6. The three items, and the only three there will ever be — §3's OUT list is explicit
-- that nothing else damages the Aswang, and §8.3 adds that a SECOND buntot pagi would be selling the
-- win condition. `BuntotPagi` splits to Buntot + Pagi under check:scope's word splitter and matches
-- neither `weapons?` nor anything else on the list; that is by design, not by luck.
Enums.ItemType = table.freeze({
	Salt = "SALT" :: Types.ItemType,
	Bawang = "BAWANG" :: Types.ItemType,
	BuntotPagi = "BUNTOT_PAGI" :: Types.ItemType,
})

-- V02, §4.7. A corpse is a killed player; a husk is one who left or went AFK. `PlayerState.Dead`
-- already spells the state, so this names the BODY rather than the player — a husk's owner is not
-- dead, they are gone, and §4.7's roster deliberately does not shrink for either.
Enums.BodyKind = table.freeze({
	Corpse = "CORPSE" :: Types.BodyKind,
	Husk = "HUSK" :: Types.BodyKind,
})

--[[
	V02, §4.3. What the Aswang is doing.

	V02 DECLARES THESE AND WIRES NONE OF THEM. Read `Types.MonsterState`'s comment before building the
	state machine: `Exposed` reads as a LATCH (§4.3 — camouflage is locked "until it has taken a salt
	hit", and §4.6 — the buntot pagi kills an Aswang that is Exposed AND weakened) while the other four
	read as mutually-exclusive activities. Whether this is one field or a field plus a flag is that
	chunk's decision, and V02 must not pre-empt it by wiring a `setState`.

	`Weakened` is deliberately absent. It is a HEALTH PREDICATE — `health <= Config.Monster
	.WeakenedThreshold` — not a state, and duplicating it as an enum member is how two sources of truth
	for one fact get out of step.
]]
Enums.MonsterState = table.freeze({
	Normal = "NORMAL" :: Types.MonsterState,
	Transformed = "TRANSFORMED" :: Types.MonsterState,
	Exposed = "EXPOSED" :: Types.MonsterState,
	Feeding = "FEEDING" :: Types.MonsterState,
	Camouflaged = "CAMOUFLAGED" :: Types.MonsterState,
})

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

return Enums
