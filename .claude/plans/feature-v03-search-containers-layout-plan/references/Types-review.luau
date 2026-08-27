--!strict
--[[
	REVIEW — src/shared/Types.luau:11-61, 278-317, 429-465, 509-515
	Read for V03 to find what V02's vocabulary already provides and where the new types belong.
	Answer: ItemType exists and is exactly right; two types are added.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING" -- :11
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR" -- :13

export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI" -- :27
-- NOTE V02 landed this and V03 needs no change. ContainerLayout re-declares it locally as `Item`
-- (pure modules cannot require Types); Luau unions are structural, so the two are the same type and
-- `SearchUpdatePayload.Found` accepts what `itemAt` returns without a cast.

export type SearchPoolVerdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED" -- :294
-- NOTE Already mirrors server/pure/SearchPool.Verdict (:284 says so). V03 uses SearchPool.Report
-- directly, as ItemService does, so this is context rather than a dependency.

--[[
	IMPORTANT — THE PRECEDENT FOR PREFIXING V03'S VERDICT UNION (Types.luau:509-515):

	  "`TrialSnapshot` is the other half. It carries no field name `ClientRoundSnapshot` carries [...]
	   so a handler wired to the wrong remote fails to typecheck rather than rendering trial state as
	   round state. `check:remotes` and `check:secrecy` are text tripwires and would both pass a
	   semantic mix-up like that; the type is what actually catches it."

	Hence `SEARCH_OK`, `SEARCH_WRONG_PHASE` and so on rather than bare `OK`/`WRONG_PHASE`.
	`SaltVerdict` (:317) already owns the bare spellings:

		export type SaltVerdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"

	A third union sharing those literals would make a mis-wired handler a working program with the
	wrong meaning. Note SaltVerdict is ALSO the model for the gate order V03 copies: phase first,
	liveness second, positional facts last.
]]

--------------------------------------------------------------------------------
-- ClientRoundSnapshot, :429-465. V03 DOES NOT WIDEN IT.
--------------------------------------------------------------------------------
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	YourRole: Role?, -- "only ever the receiving player's OWN role"
	YourState: PlayerState,
	YourCarriedItem: ItemType?, -- :464
}

--[[
	IMPORTANT — WHY V03 ADDS NO PRODUCER FOR `YourCarriedItem`, in its own words (:461-462):

	  "V02 ADDS NO PRODUCER. `buildSnapshot` does not set it, exactly as it deliberately does not set
	   `YourRole`, so no service changes and `analyze` stays clean."

	V03 grants no items, so it adds none either. V08 owns the carry slot. A V03 that set this field
	would be claiming a carry the game does not implement.

	FOUR RULES FROM THIS COMMENT BLOCK THAT V03'S OWN PAYLOAD MUST HONOUR (:435-459):
	  · "`RoundSnapshot` is built per player and sent with `:FireClient` [...] There is no broadcast
	     form of this payload to accidentally put someone else's inventory on." — SearchUpdate is
	     FireClient-only for the same structural reason.
	  · "IT IS NOT A ROLE ORACLE. The Aswang carries nothing [...] so its slot is `nil`, which is also
	     what an empty-handed survivor's slot is." — V03's inverse: the Aswang DOES search and CAN
	     find, so `Found`'s distribution is identical across roles. Same conclusion, opposite mechanism.
	  · "IT IS NOT A DEATH SIGNAL. It is not a count" — SearchUpdate carries no count either, and a
	     "3 of 7 found" field would break this and Amendment A3's spirit at once.
	  · "never mirror it onto an attribute or a tag, both of which replicate to everyone."
]]

--[[
	NOTE — THE ABSENCE AT :467-469 ("THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD
	BEARING", Amendment A3, §4.7). Death is not public; you learn someone died by finding the body.

	V03 touches nothing here, but the rule shapes one V03 decision: `SEARCH_OCCUPIED` says a container
	is busy and NOT who is on it. A verdict naming the other searcher would be a per-player presence
	fact delivered without anyone finding anything, which is the shape A3 exists to refuse.
]]

-- ADDED BY STEP 2.1: `SearchVerdict` (9 members) and `SearchUpdatePayload` (3 fields). The full
-- reasoning, including the absent-field list, is in the plan's Step 2.1 diff — it belongs in the file
-- rather than here, because Types.luau's comments are where the next author will look.
