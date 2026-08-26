--!strict
--[[
	REVIEW — docs/MVP-SPEC.md §8.2-8.4 (:466-500), §6.6 (:425-440), Appendix B (:692-712),
	          Amendment A3 (:219-244)

	The spec is the authority on WHAT to build. Cited, not restated — these are the four passages
	that directly constrain C38 and C40.
]]

-- docs/MVP-SPEC.md:474-486 — §8.2 What to sell
--   Private Server ~100/mo · Starter Pack 79 · Survivor Pack 249 · VIP 799 · Coin Pack 99/399
-- NOTE: five products, and `Config.Monetization.Catalogue` carries four of them. THE PRIVATE SERVER
--       IS DELIBERATELY ABSENT from the catalogue even though §8.2 calls it "your #1 earner":
--       Roblox sells it from its own UI and there is nothing for this service to prompt.
-- NOTE: "VIP (exclusive aura, 2x XP, …) — 2x XP is cosmetic progression, NOT round advantage, so
--       this stays fair." The BENEFITS are C35's job. This plan stops at `OwnsGamepass` returning a
--       boolean and deliberately renders nothing.

-- docs/MVP-SPEC.md:488-491 — §8.3 Explicitly do NOT sell
--   ❌ Extra salt, extra lives, revives, see-through-walls, longer transform
--   ❌ "Higher chance to be the Aswang" — "in a 1-imposter game it directly takes the fun role from
--      non-payers and breeds resentment… My recommendation for MVP: skip it."
-- IMPORTANT: `check:scope` DOES NOT COVER §8.3. Its OUT_OF_SCOPE list is monsters, meetings, voting,
--            weapons, zones, pets, trading, guilds, seasons — nothing about advantage-for-sale. So
--            the catalogue table is the whole surface and a reviewer is the whole guard. The plan
--            says this at the top of the Config block rather than trusting it to be remembered.

-- docs/MVP-SPEC.md:493-495 — §8.4 Placement
--   "Show the cosmetic shop ON THE END SCREEN (when the player just had a great round and is waiting
--    anyway), never mid-round."
-- IMPORTANT: the brief's Q4. THIS IS A CONVERSION ARGUMENT, not a security one — the reason given is
--            that contextual offers convert better, not that a mid-round shop leaks anything. That
--            matters for how hard the enforcement has to be: the plan's mechanism 2 (a server-side
--            ENDING phase gate) makes it structural for honest clients, and the honest limit — a
--            modified client can open Roblox's own prompt whenever it likes — costs the player their
--            own Robux and changes no round state.

-- docs/MVP-SPEC.md:425-440 — §6.6 Data model
--   Purchases = { GamepassCacheUTC = 0 }
--   "Rules: version from day one and write the migration path. Save on meaningful change + on leave
--    + on BindToClose. Never trust a client-supplied value into this table."
-- IMPORTANT: "version from day one and write the migration path" is why C38's `Receipts` field is a
--            v3 bump with an `Applied` line rather than a silent addition.
-- NOTE: "Save on meaningful change" is the rule `saveNow` implements and the reason a receipt needs
--       MORE than it — see ProfileStore-review.luau on `Save()` not yielding.

-- docs/MVP-SPEC.md:694 — Appendix B, the fifteen events, all on one line
--   player_joined · round_started (playerCount) · role_assigned (role) · task_completed (type,
--   secondsIntoRound) · player_killed (secondsIntoRound, wasIsolated) · transform_witnessed ·
--   salt_used (hit/miss) · round_ended (winner, duration, survivorsAlive) · player_left (phase,
--   secondsInSession) · shop_opened · purchase_completed (productId) · daily_claimed (streak) ·
--   trial_started · trial_completed · group_join_reward_claimed
-- IMPORTANT: hand-copied into `tests/analytics-events.test.luau` as EXPECTED, and into
--            `server/pure/AnalyticsEvents.luau` as a literal union. The test pins both directions so
--            a sixteenth event or a rename fails from a terminal.
-- QUESTION: `transform_witnessed` HAS NO DEFINITION ANYWHERE IN THE SPEC. "Witnessed" by whom, and
--           measured how? Counting broadcast recipients measures replication, not witnessing;
--           counting line-of-sight means a server-side visibility query whose RESULT is a fact about
--           who saw the Aswang. Follow Up #4 — a decision, not a detail.
-- NOTE: `group_join_reward_claimed` belongs to C39's claim path, which is in flight in parallel.
--       This plan declares the name and does not wire the call site.

-- docs/MVP-SPEC.md:219-244 — Amendment A3, the death oracle
--   "Death is not public. There is no global death signal, and the round snapshot no longer carries
--    a live player count."
--   "…record replicated character positions, timestamp each kill from the decrement, then ask who
--    was within Monster.KillRange of the victim's last position at that instant. In the open that is
--    frequently a single candidate — the Aswang, identified without anybody witnessing a transform."
-- IMPORTANT: DIRECTLY BINDS C40's `player_killed`. The event carries `secondsIntoRound` and
--            `wasIsolated`, both of which are exactly the inputs A3 removed from the wire. They are
--            safe going to Roblox's telemetry backend and fatal on a remote. Three rules at the call
--            site: log against the VICTIM, keep `wasIsolated` off every payload, add no broadcast.
-- IMPORTANT: "Delaying the count was considered and rejected. A fixed delay is a constant an
--            attacker subtracts. A jittered one is a statistical claim of safety." So there is no
--            "emit it late" compromise available for analytics either.
