--!strict
--[[
	REVIEW — src/shared/Enums.luau:9-11, 14-32, 42-50
	Read for V03: the v2 vocabulary V02 landed, and the cast rule that bites.
]]

--[[
	IMPORTANT — THE CASTS ARE LOAD-BEARING (Enums.luau:9-11):

	  "The `:: Types.X` casts are load-bearing under --!strict. Without them every field infers as
	   plain `string`, and passing one to a parameter typed as the literal union fails to typecheck —
	   which is how the scaffold shipped six analyze errors."

	V03 adds no enum, so it adds no cast. It CONSUMES them, and the direction that matters is that
	`Enums.RoundPhase.Active` compares cleanly against a `Types.RoundPhase` parameter.
]]

Enums.RoundPhase = table.freeze({
	Starting = "STARTING" :: Types.RoundPhase, -- :18  V03 seeds the layout here
	Active = "ACTIVE" :: Types.RoundPhase, -- :19     V03 permits searching here and nowhere else
	Intermission = "INTERMISSION" :: Types.RoundPhase, -- :17  V03 clears the layout here
	Idle = "IDLE" :: Types.RoundPhase, -- :16                  and here
	Ending = "ENDING" :: Types.RoundPhase, -- :20  holds release; the layout is left alone
})

Enums.PlayerState = table.freeze({
	Alive = "ALIVE" :: Types.PlayerState, -- :30  the only state that may hold a search
	Dead = "DEAD" :: Types.PlayerState, -- :31  "V01: killed in-round. Spectates; the corpse is the body"
	Spectator = "SPECTATOR" :: Types.PlayerState, -- :32 "joined mid-round"
})
-- NOTE V03 gates on `== Alive` rather than `~= Dead`, so DEAD, SPECTATOR and LOBBY all fail through
-- one comparison. A mid-round joiner and a killed player need no separate handling.

--[[
	V02, §4.4/§4.6 (Enums.luau:42-50). THE THREE ITEMS, and the comment is worth quoting because it
	pre-empts a question V03's ContainerLayout raises:

	  "The three items, and the only three there will ever be — §3's OUT list is explicit that nothing
	   else damages the Aswang, and §8.3 adds that a SECOND buntot pagi would be selling the win
	   condition. `BuntotPagi` splits to Buntot + Pagi under check:scope's word splitter and matches
	   neither `weapons?` nor anything else on the list; that is by design, not by luck."
]]
Enums.ItemType = table.freeze({
	Salt = "SALT" :: Types.ItemType,
	Bawang = "BAWANG" :: Types.ItemType,
	BuntotPagi = "BUNTOT_PAGI" :: Types.ItemType,
})

--[[
	IMPORTANT — V03 DOES NOT USE `Enums.ItemType` INSIDE `ContainerLayout`, and that is not an
	oversight. A pure module may not `require(script.Parent.X)` — Lune has no `script`, so a pure
	module that reaches for Enums stops being runnable from a terminal and the whole point is lost.

	So ContainerLayout writes the three RAW STRINGS ("SALT", "BAWANG", "BUNTOT_PAGI") in its narrowing
	function. That is a duplication of these three literals, and it is the accepted cost: RoleDraw does
	the same with "SURVIVOR"/"ASWANG", and Luau's structural unions mean the analyzer still catches a
	typo the moment the value reaches a `Types.ItemType` field.

	QUESTION worth an implementer's eye: SearchService itself is NOT a pure module and CAN require
	Enums. It does not need to — it passes `item` straight from `ContainerLayout.itemAt` into the
	payload — but if a future branch compares against a literal there, use `Enums.ItemType.BuntotPagi`
	rather than a fourth copy of the string.
]]

--[[
	NOTE — WHAT V02 DECLARED AND DELIBERATELY DID NOT WIRE (Enums.luau:62-72): `MonsterState`, with an
	explicit instruction that "V02 DECLARES THESE AND WIRES NONE OF THEM" and that whether `Exposed` is
	a state or a latch "is that chunk's decision, and V02 must not pre-empt it by wiring a `setState`".

	V03 touches none of it and must not. Searching is role-blind (§4.4), so SearchService has no reason
	to read a monster state at all — and reading one would be the first step toward the oracle
	Amendment A2 forbids.
]]
