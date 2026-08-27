--!strict
--[[
	REVIEW — src/shared/Types.luau (558 lines). Excerpted, not transcribed.
	Ranges cited below: :11-22, :326-353, :382-389, :391-417, :311-318.
	Read for: V02, which adds four unions and one optional field to this file.
]]

-- src/shared/Types.luau:11-14
-- The four existing unions. V02's four go directly beneath, matching this style: `export type`,
-- UPPER_SNAKE literals, one line each unless a comment is warranted.
-- IMPORTANT `export`, not bare `type`. A bare `type` compiles here and then fails from Enums.luau
-- with `Unknown type 'ItemType'` — which is exactly what Step 2.3's analyze gate catches.
export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type Role = "SURVIVOR" | "ASWANG"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
export type RoundResult = "SURVIVORS_ESCAPED" | "ASWANG_WINS" | "TIMEOUT" | "ABORTED"

-- src/shared/Types.luau:16-23
-- IMPORTANT `TasksDone` is stale under v2.0. Spec §6.6 mandates `TasksDone` -> `ItemsFound` plus a
-- new `AswangKilled`, at SchemaVersion = 2, as part of the v1->v2 profile migration. That has live
-- readers (ProfileService, BadgeService) AND a DataStore migration path, so it is not V02's.
-- See Follow Ups Q5.
export type PlayerStats = {
	Rounds: number,
	Survived: number,
	AswangRounds: number,
	AswangWins: number,
	Kills: number,
	TasksDone: number,
}

--[[
	src/shared/Types.luau:328-333 (inside the RoundEndedPayload comment)

	IMPORTANT THE MEASUREMENT THAT GOVERNS STEP 1.2. This repo tested its own analyzer:

	  · a field of the WRONG TYPE      -> caught
	  · a MISSING field                -> caught
	  · an EXTRA field                 -> NOT CAUGHT. Silently accepted.

	So annotating `ClientRoundSnapshot` does NOT stop a later chunk adding a leaking field to it. The
	type is documentation plus two thirds of a guard. V02 adds one field and argues it in prose for
	exactly this reason.
]]

-- src/shared/Types.luau:382-389
-- The client contract. V02 appends ONE optional field after YourState and removes nothing.
-- NOTE the naming convention: `Your*` means "about the receiver and nobody else". The carry slot must
-- be `YourCarriedItem`, not `carriedItem` — camelCase would be the only one in the file, and the
-- prefix is what makes the per-receiver rule readable at the call site.
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}

--[[
	src/shared/Types.luau:391-417 — AMENDMENT A3'S BLOCK.

	IMPORTANT THIS IS THE ONE THING IN THESE THREE FILES THAT MUST NOT MOVE. It sits directly under
	the field Step 1.2 edits, which is precisely why Step 1.3 exists as a separate step with a
	preservation check (`grep -q 'SurvivorsRemaining'` — nothing in V02 types that token).

	Spec line 52 confirms it survives the rewrite verbatim: "Amendment A3 survives intact (§4.7):
	death is not public, there is no global death signal, and ClientRoundSnapshot still carries no
	alive-count."

	Its forbidden-name list — `SurvivorsRemaining`, `DeadCount`, `RosterSize`, and a YourState-derived
	tally over a roster field — is the load-bearing sentence. None of those tokens matches anything in
	check-secrecy.mjs, so the comment IS the enforcement.

	NOTE the block records that this hole "was reopened twice by code written to protect it, with
	verify and check:secrecy green over both". Treat any edit inside it as a decision, not a cleanup.
]]

-- src/shared/Types.luau:311-318
-- IMPORTANT A v1.3 LIST. `TASK_HERE` names the retired task system. §4.5's v2 list (spec line 341)
-- replaces it with "Searching — cover me" and ADDS two phrases that are load-bearing rather than
-- flavour: "It's the [animal]!" (spec line 344 — without it camouflage is unbeatable) and "I have the
-- buntot pagi" (line 345 — what makes the single item a protection problem).
-- NOTE `check:scope` reads string literals, but "TASK" is not on the OUT list, so this passes today.
-- Owned by the quick-chat chunk, not V02. See Follow Ups Q6.
export type QuickChatPhraseId =
	"SAW_TRANSFORM"
	| "BODY_HERE"
	| "FOLLOW_ME"
	| "ACCUSE"
	| "TASK_HERE"
	| "RUN"
	| "IM_ALONE"
	| "TRUST_ME"

-- src/shared/Types.luau:325 and :363
-- NOTE these two comments contain `GhostService` and `GhostRoster`, and check-scope.mjs has armed
-- `/^ghosts?$/i` since V01. `npm run check:scope` is GREEN anyway — measured — because it scans code
-- and STRING LITERALS but strips comments. Do not "fix" these; V02 has no reason to touch them, and
-- the fact is worth knowing before someone assumes the check covers prose. See Follow Ups Q8.
