--!strict
--[[
	REVIEW — src/shared/Types.luau (982 lines)
	Read for V10 planning: where `StrikeVerdict` lands, the prefixing rule it must follow, and the
	never-echoed rule it inherits.
]]

-- src/shared/Types.luau:305-312 — the never-echoed rule, in its original form
export type SearchPoolVerdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"
--[[
	KillVerdict: a union so the server can log WHY, and NEVER echoed to any client.
]]
-- IMPORTANT V10 INHERITS THIS AND GOES ONE STEP FURTHER. `StrikeVerdict` is never echoed AND is
--           shaped so that echoing it would leak nothing: the four target-side worlds are one value.
--           "Never echoed" is a rule someone has to keep; "nothing to echo" is a property.

-- src/shared/Types.luau:341-350 — the prefixing rule, stated as a bug-prevention measure
--[[
	ALL THREE ARE PREFIXED `ITEM_`, and that is `SearchVerdict`'s rule below, restated because it is
	not decoration. `SaltVerdict` above carries a bare `WRONG_PHASE` and `MonsterState` a bare ...

	NONE OF THE THREE IS EVER ECHOED TO A CLIENT. This is `SaltVerdict`'s rule inherited verbatim ...
]]
-- IMPORTANT A THIRD UNION SHARING THE BARE `WRONG_PHASE` SPELLING makes a handler wired to the wrong
--           path a working program with the wrong meaning. `StrikeVerdict` is prefixed `STRIKE_`
--           throughout for exactly this. It matters more here than elsewhere because
--           `ItemService`'s strike handler tests three verdict values by name to decide whether to
--           spend — a spelling collision there is a destroyed win condition.

-- src/shared/Types.luau:385 — the union Step 1.3 edits
export type ItemUseVerdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD" | "USE_PLACE"
-- IMPORTANT `USE_NOT_IMPLEMENTED` IS DELETED, NOT LEFT AS AN UNUSED VALUE. After Step 1.4 no item
--           returns it, and `pure/ItemUse`'s header refuses dead paths in as many words ("it is not
--           a feature flag"). The analyzer finds every remaining reader; `verify:fast` is Step 1.4's
--           verify for that reason.
-- NOTE      This union MIRRORS `pure/ItemUse.Verdict` rather than importing it — the pure module
--           cannot `require(script.Parent)` under Lune. The two must be edited together, and Luau
--           unions being structural is what makes the duplication safe rather than a divergence.

-- src/shared/Types.luau:390-404 — where `StrikeVerdict` goes, and the template it follows
--[[
	PREFIXED `GARLIC_`, which is `ItemCarryVerdict`'s rule and `SearchVerdict`'s before it. A fourth
	union sharing the bare spelling ...
]]
export type GarlicPlaceVerdict =
	"GARLIC_OK"
	| "GARLIC_WRONG_PHASE"
	-- ...
-- NOTE `StrikeVerdict` lands immediately after this block. Same shape, one fewer value, and the
--      difference is documented in its own header: garlic distinguishes three world-side refusals
--      because a doorway is a public object; the strike distinguishes none, because the thing being
--      resolved is a person.

-- src/shared/Types.luau — `ClientRoundSnapshot.YourCarriedItem`
-- IMPORTANT THIS FIELD IS WHY DECISION B IS A SECRECY DECISION RATHER THAN A BALANCE ONE, and it is
--           worth reading its own comment before touching the spend. The server pushes this client
--           its own slot every `Round.SnapshotInterval`, so whether the buntot pagi survived a swing
--           is DIRECTLY OBSERVABLE by the striker with no exploit at all. A spend conditional on the
--           kill therefore publishes "that target was not the Exposed, Weakened Aswang" through the
--           HUD, once per swing, for free.
-- IMPORTANT THE FIELD'S OWN COMMENT ALSO STATES THE SYMMETRY V10 MUST NOT BREAK: "an empty-handed
--           survivor and the Aswang are indistinguishable only if the monster genuinely fills
--           slots." So the Aswang can hold, swing and spend a buntot pagi on identical rules, and
--           `ResolveStrikeTarget` deliberately resolves the Aswang's own swing to itself.
-- QUESTION  V10 ADDS NOTHING TO THIS TYPE. Confirm that at implementation time — if a HUD change
--           later wants "you are holding the only thing that kills", that is a client-side string
--           over a field that already exists, never a new field.

-- src/shared/Types.luau:726-732 — `FeedVerdict`, which `StrikeDown` must pass one of
export type FeedVerdict = -- ... FEED_OK | FEED_INTERRUPTED | ...
-- QUESTION `MonsterService.StrikeDown` calls `endFeed(userId, <interrupted>)`. Confirm the exact
--          member name against the six existing `endFeed` callers rather than against this review —
--          passing `nil` is reserved for `completeFeed` and would leave a struck feeder with no
--          message at all.
