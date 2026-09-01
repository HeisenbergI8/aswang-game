--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau (1287+ lines)
	Read for V10 planning for exactly one function: what happens when the Aswang becomes DEAD. This
	is the whole of the V10/V11 boundary.
]]

-- src/server/Services/RoundService.luau:99-117 — the two accessors V10 uses
function RoundService.GetAswangUserId(): number? end
function RoundService.GetPlayerState(player: Player): PlayerState end
-- NOTE `ResolveStrikeTarget` calls the first; the strike handler calls the second for both the
--      striker and the resolved target. Both are already called from `MonsterService` and
--      `ItemService`, so V10 introduces no new dependency edge.

-- src/server/Services/RoundService.luau:867-886 — MarkKilled's header
--[[
	A survivor died (C05). The ONLY writer of a death, and it lives here because this service owns
	PlayerStates — MonsterService asks rather than writes ...

	Guarded on ACTIVE and on the victim currently being ALIVE, so a duplicate call — two kill requests
	landing in the same tick, a retry after a dropped packet — is a no-op rather than a second death.
]]
-- IMPORTANT IDEMPOTENT, WHICH V10 DEPENDS ON. Two `RequestStrike` calls racing (the AntiCheat
--           capacity is 2) cannot produce two deaths. Note this is belt-and-braces: the first swing
--           already emptied the slot, so the second refuses at `STRIKE_NOT_HELD`.
-- NOTE      "MonsterService asks rather than writes" is why `StrikeDown` calls this rather than
--           setting a PlayerState itself. Nothing outside this file writes a death, and nothing
--           outside it sets a phase.

-- src/server/Services/RoundService.luau:915-938 — THE V11 HANDOFF, in full
	--[[
		THE ASWANG DIED, SO THE ROUND IS OVER. Mirrors onPlayerRemoving's abort exactly.

		That handler already ends the round when the Aswang DISCONNECTS ... Routing non-kill deaths
		through here opened a second door to that same state ...

		A kill can never reach this branch — `TARGET_IS_ASWANG` refuses it — so in practice this fires
		only for a reset, a fall, or whatever C14's salt does. It is written unconditionally anyway,
		because "the monster is gone" is the thing that matters and not how it happened.

		ABORTED rather than SURVIVORS_ESCAPED: they did not escape, and the round was void.
	]]
	if state.AswangUserId == player.UserId then
		enterEnding(Enums.RoundResult.Aborted)
		return
	end
-- IMPORTANT THIS IS THE LINE V10 SHIPS WRONG ON PURPOSE. A successful buntot pagi strike reaches it
--           and the round scores `ABORTED` — the end screen says the round was void after the
--           survivors won it. V11 owns `RoundResult` and the six §6.5 invariants land with it;
--           changing the result here would be building half of V11 with none of them.
-- IMPORTANT THE COMMENT IS ALREADY STALE AND V10 IS WHAT MAKES IT STALE. "A kill can never reach
--           this branch — TARGET_IS_ASWANG refuses it" is true of `RequestKill` and false of
--           `RequestStrike`. The plan's Step 4.3 writes the handoff into `docs/BUILD-PLAN.md`'s V11
--           entry; whoever implements V11 should also repair THIS comment.
-- QUESTION  Should V10 amend the comment even though it does not amend the code? The plan says no —
--           an amendment here without the result change reads like the result is intentional. Raise
--           it if the auditor disagrees.

-- src/server/Services/RoundService.luau:940-958 — why `causedByKill = false`
	--[[
		THE ONLY PLACE A KILL IS COUNTED, and the reason `causedByKill` exists at all.

		A death the Aswang did not cause — a reset, a fall, C14's salt later — still makes the player a
		DEAD ... It just does not advance the win, because §4.8's rule now asks how many people the
		Aswang KILLED rather than how many are still standing.
	]]
	if causedByKill == true then
		state.AswangKills += 1
	end
-- IMPORTANT `StrikeDown` MUST PASS `false`. This counter is the ASWANG's progress toward ITS win
--           condition; a survivor killing the monster must not advance it. Passing `true` by reflex
--           (because "it was a kill") would be a real bug and a quiet one — the round ends either
--           way, so nothing would report it until V11 read the counter.

-- src/server/Services/RoundService.luau:895-913 — the body rule, and the unconfirmed claim
	--[[
		KILLED, AND IT IS NOW A NO-OP FOR A DEAD — deliberately ... `BodyTransitions` answers KEEP for
		every DEAD cause since the C15 redesign, because a dead player's character IS THE CORPSE and
		`MonsterService` owns it. So this call changes nothing today.
	]]
	applyBodyRule(player, "KILLED")
-- QUESTION  THE PLAN READS THIS COMMENT RATHER THAN `pure/BodyTransitions` ITSELF. If KEEP is not
--           what `BodyTransitions` actually answers, the struck Aswang's avatar could be destroyed
--           in the same frame the round's best clip happens. **Confirm before Phase 3 lands** —
--           Follow Up 6. It is one `lune run tests/body-transitions.test.luau` and one read.
-- NOTE      `StrikeDown` deliberately does NOT detach the character or call `makeCorpse`. That is
--           `commitKill`'s job for a survivor, and V12 owns what body a dead Aswang leaves.
