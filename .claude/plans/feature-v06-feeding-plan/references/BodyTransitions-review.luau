--!strict
--[[
	REVIEW — src/shared/pure/BodyTransitions.luau (161 lines)

	The body model V06's `FeedRules` must consume rather than duplicate. V06 changes nothing here.

	THE SHORT ANSWER TO "WHERE DOES THE HUSK -> CORPSE TRANSITION LIVE": NOT IN THIS FILE. This module
	answers "may this player have a body, and what should happen to it", keyed by PlayerState and
	cause. The husk/corpse DISTINCTION is not modelled here at all — it lives in two workspace folders
	and in `MonsterService.validateAndKillHusk`, which moves a body between them.
]]

-- src/shared/pure/BodyTransitions.luau:38
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
-- src/shared/pure/BodyTransitions.luau:45
export type Cause = "JOINED" | "PHASE_CHANGE" | "KILLED" | "DIED" | "LOAD_FAILED"
-- src/shared/pure/BodyTransitions.luau:56
export type Action = "GRANT" | "REVOKE" | "KEEP" | "DEFER"
-- IMPORTANT  NO `BodyKind` ANYWHERE IN THIS MODULE, and no cell that distinguishes a corpse from a
--       husk. So `FeedRules` cannot get its answer from here and is not duplicating anything by
--       taking a `BodyKind` input. What it must not do is invent a SECOND notion of what makes a body
--       feedable — hence `bodyKindOf` reading the folder, which is where the fact already lives.
-- NOTE  Four states x five causes, every cell stated. That grid is the precedent the build plan cites
--       for `FeedRules`'s test, and this module's header says why: five patches across four review
--       rounds, every defect the same shape — "one entry point handled and its twin not".

-- src/shared/pure/BodyTransitions.luau:100-127
	--[[
		A DEAD PLAYER'S BODY IS NOT THIS FUNCTION'S BUSINESS, on any cause. KEEP, always…
		A dead player's character IS THE CORPSE, and `MonsterService` owns it — it anchored it, it
		fades it, and `clearCorpses` destroys it when the round ends. Every other action here would
		break that: REVOKE would destroy the corpse…
	]]
	if state == "DEAD" then
		return "KEEP"
	end
-- IMPORTANT  THIS IS WHY A CORPSE SURVIVES LONG ENOUGH TO BE FED ON. `commitKill` calls
--       `RoundService.MarkKilled` between `makeCorpse` and `beginFeed`; MarkKilled applies the body
--       rule, and without this short-circuit the rule would revoke the body V06 is about to pin a
--       monster to. The feed depends on a decision made three chunks ago.
-- NOTE  It also means the corpse stays as `victim.Character` for the whole round, so `feedDistance`
--       resolving through `rootOf(body)` keeps working for the full 45 seconds.

-- src/shared/pure/BodyTransitions.luau:60-92
--   THE DEAD WERE ADMITTED HERE AND HAVE BEEN TAKEN BACK OUT… A server character REPLICATES. Hidden
--   with `Transparency = 1` it is still a player-named Model in `workspace` that any client can
--   enumerate, and since the Aswang can never be dead… each such body ELIMINATES A CANDIDATE.
--   …Three separate patch rounds tried to hide the body better and each one found new leaks, because
--   HIDING A REPLICATED OBJECT IS NOT A THING YOU CAN WIN.
-- IMPORTANT  THE SENTENCE THAT GOVERNS V06'S MOVEMENT LOCK. `WalkSpeed` is a replicated property on a
--       living character, and there is no private version. The answer is not to hide the difference,
--       it is to BOUND it: the lock exists only while the monster is transformed and announced, and
--       every exit restores it. Bounded audience, bounded lifetime.
-- NOTE  "Absence is as observable as presence" is the same lesson and it applies to the feed too —
--       which is why feeding emits NO `NoiseCue`. A noise only one role can make is a presence
--       exclusive to the Aswang, which is the leak in its more obvious direction.

-- src/shared/pure/BodyTransitions.luau:33-35
--   NO `script.Parent` REQUIRES — Lune has no `script`. PlayerState is re-declared; Luau literal
--   unions are structural, so this and `Types.PlayerState` are the same type.
-- NOTE  Copied verbatim into `FeedRules` for its three unions. `tests/body-transitions.test.luau` is
--       Step 3.3's verify — a tree gate over the module whose DEAD/KEEP row the corpse path depends
--       on, and disclosed in the plan as not proving that step.
