--!strict
--[[
	REVIEW — src/shared/Remotes.luau
	Read for V10 planning. The five headers below are the standing conventions `RequestStrike`
	inherits; the plan's Step 2.3 diff is written to match them rather than to restate them.
]]

-- src/shared/Remotes.luau — EVENTS_UP, `RequestSearch`
-- The rule in its original form. Every later no-argument remote points back at this paragraph.
--[[
	THE CONTAINER IS NOT NAMED BY THE CLIENT. The server resolves the nearest `SearchContainer` part
	within `Config.Search.RangeStuds` of that player's OWN character position ...

	A `RequestSearch(containerName)` would have been strictly worse in three ways, and the third is
	the one that matters. ... it hands a compromised client a PROBE — name every tagged part in turn,
	read the verdicts, and learn which containers are spent and which are occupied without walking
	anywhere.
]]
-- IMPORTANT This is the argument V10 reuses, escalated. A `RequestStrike(targetUserId)` probes
--           PEOPLE rather than parts: aim at one named player, observe whether they died, and the
--           answer is "yes" for exactly one of five. The plan refuses the argument on this basis and
--           states it as Decision A above Phase 1.
"RequestSearch",

-- src/shared/Remotes.luau — EVENTS_UP, `RequestDropItem`
--[[
	THE ITEM IS NOT NAMED BY THE CLIENT. `Config.Items.CarryLimit` is 1, so there is exactly one
	thing a player can be holding and the server already knows what it is. ...

	A `RequestDropItem(itemType)` WOULD HAVE BEEN A FREE PROBE AND A FREE DUPLICATOR. ... There is
	exactly one buntot pagi per round (§4.6) and it IS the second win condition, so a handler that
	spawns an item the client named is the sharpest exploit surface this chunk has.

	IT IS NOT A ROLE ORACLE IN EITHER DIRECTION. §4.4 has the Aswang searching on identical rules ...
	Nothing is returned to the caller on any path, including OK.
]]
-- IMPORTANT Three separate rules V10 inherits verbatim: no item argument (CarryLimit is 1), the
--           Aswang can carry and use items on identical rules, and NOTHING IS RETURNED ON ANY PATH
--           INCLUDING OK. The third is why the plan's handler stays silent even on STRIKE_KILL.
-- NOTE      "an empty-handed survivor and the Aswang are indistinguishable only if the monster
--           genuinely fills slots" — this is why `ResolveStrikeTarget` must not refuse the Aswang's
--           own swing. A monster whose buntot pagi behaves differently is a monster you can find by
--           handing it one.
"RequestDropItem",

-- src/shared/Remotes.luau — EVENTS_UP, `RequestPlaceGarlic`
-- The precedent the task brief names, and the closest structural match to `RequestStrike`.
--[[
	THE DOORWAY IS NOT NAMED BY THE CLIENT. The server resolves the nearest part tagged `Doorway`
	within `Config.Items.GarlicPlaceRangeStuds` of that player's OWN character position ...

	A `RequestPlaceGarlic(doorway)` WOULD HAVE BEEN A FREE MAP PROBE. It needs a verdict for "that
	doorway is not near you", which is the distance comparison the server was already positioned to
	make ...

	NOR IS THERE AN ITEM ARGUMENT. `Config.Items.CarryLimit` is 1 ...
]]
-- NOTE The shape transfers exactly: a range constant in Config, a server-side nearest-resolution, a
--      verdict for "not near you" the server was already making, and no item argument. V10 differs
--      in one way only — the thing being resolved is a PLAYER, so the probe it refuses is sharper.
"RequestPlaceGarlic",

-- src/shared/Remotes.luau — EVENTS_DOWN, `SmokeBurst` and `NoiseCue`
-- Read to decide whether V10 needs a downward remote. It does not.
-- IMPORTANT Both of these refuse `FireAllClients` with a position, and both argue that the public
--           half of a mechanic needs no remote when it replicates as geometry. A strike's public
--           half is a monster falling over, which replicates. So V10 adds NOTHING to EVENTS_DOWN,
--           and there is no `StrikeEffect` to match `SaltEffect`.
-- QUESTION  `SaltEffect` exists and broadcasts a burst at the impact point. Should a strike have a
--           visual at all? The plan says no and defers it to V14's audio/VFX pass with the argument
--           written down (Follow Up 4). If V14 adds one, it must fire on every SPENT swing, not on
--           kills — a kill-only effect is a role broadcast with a position attached.
"SmokeBurst",
