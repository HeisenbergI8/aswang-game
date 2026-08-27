--!strict
--[[
	REVIEW — src/shared/Types.luau (745 lines)

	V06 adds two exports: `FeedVerdict` and `FeedUpdatePayload`. Everything else here is read to make
	sure they are shaped like their neighbours and carry the same absent-field arguments.
]]

-- src/shared/Types.luau:39
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
-- NOTE  `pure/FeedRules` RE-DECLARES this locally rather than importing it. Lune has no `script`, so
--       a pure module that reaches for `Types` stops being runnable from a terminal. Luau unions are
--       structural, so the local type and this one are the same type and pass without a cast.

-- src/shared/Types.luau:51
export type BodyKind = "CORPSE" | "HUSK"
-- IMPORTANT  Declared at V02, referenced by nothing until V06's `bodyKindOf`. `FeedRules` re-declares
--       it locally for the same reason as above.

-- src/shared/Types.luau:428-465
-- What the client is allowed to know. Note the absence of AswangUserId.
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
	YourCarriedItem: ItemType?,
}
-- IMPORTANT  V06 DOES NOT WIDEN THIS. No `YouAreFeeding`, no `FeedSecondsRemaining`, nothing. The
--       feeder's own five seconds go on `FeedUpdate`, a per-player remote with a per-player payload,
--       which is the same shape `SearchUpdate` chose for the same reason. Widening the snapshot would
--       be a contract change to argue in a plan, and there is no need to argue it.
-- NOTE  The `Your` prefix is described here as "the whole contract", and it is safe because
--       `RoundSnapshot` is built per player and sent with `FireClient`. `FeedUpdatePayload` needs no
--       prefix because it has no field that could belong to anyone else.

-- src/shared/Types.luau:536-546
export type SearchVerdict =
	"SEARCH_STARTED" -- the hold began; HoldSeconds is how long it will take
	| "SEARCH_OK" -- the hold completed; `Found` is the item, or nil for an empty container
	| "SEARCH_INTERRUPTED" -- you cancelled, moved out of range, died, or the round moved on
	| "SEARCH_WRONG_PHASE"
	| "SEARCH_NOT_ALIVE"
	-- …four more
-- IMPORTANT  THE MODEL FOR `FeedVerdict`, AND THE PART V06 DOES NOT COPY. `SearchVerdict` carries
--       nine values because a SEARCH IS CLIENT-REQUESTED and a refusal has to be explained to the
--       player who pressed the button. A feed is a consequence of a kill: there is no button, no
--       request, and therefore no refusal to explain. `FeedVerdict` is the first three values only —
--       started, completed, broke.
-- NOTE  `SEARCH_INTERRUPTED` already collapses four causes into one value. `FEED_INTERRUPTED`
--       collapses six, on the stronger version of the same argument: telling the Aswang whether that
--       was salt or a drift is a fact about a survivor's aim.

-- src/shared/Types.luau:548-580
--   THE ABSENT FIELDS ARE THE SECURITY DESIGN, so they are listed rather than merely omitted:
--     · NO CONTAINER ID, in either direction… There is therefore NO KEY ON WHICH TWO CLIENTS COULD
--       DIFFERENCE THEIR PAYLOADS.
--     · NO LAYOUT, NO REMAINING COUNT…
--     · NO SEARCHER.
export type SearchUpdatePayload = {
	Verdict: SearchVerdict,
	-- Config.Search.SearchTime on SEARCH_STARTED, 0 on every other verdict… It carries no
	-- information — Config is replicated, so the client already knew it.
	HoldSeconds: number,
	Found: ItemType?,
}
-- IMPORTANT  `FeedUpdatePayload` IS THIS MINUS `Found`, and its absent-field list is written out in
--       full rather than pointed at this one: no health, no victim, no position, no camouflage
--       charge. V01 deleted an entry that inherited its reasoning from a neighbour and the lesson
--       stuck — see `TeachingCue`'s comment at line 76.
-- NOTE  The HoldSeconds-is-zero-on-every-ending rule is copied verbatim. It is not padding: a client
--       that could read a timing difference off an ending could distinguish the six paths
--       `FEED_INTERRUPTED` deliberately collapses.
-- NOTE  Placement: `FeedVerdict` and `FeedUpdatePayload` go immediately after this block, so the two
--       timed-hold payloads in this game sit together and a reader comparing them does not have to
--       search.
