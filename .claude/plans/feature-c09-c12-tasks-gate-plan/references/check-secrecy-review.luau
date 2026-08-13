--!strict
--[[
	REVIEW — .claude/scripts/check-secrecy.mjs
	Read 2026-08-12 for the C09-C12 plan, and RE-READ after the tree changed mid-plan.

	*** READ THIS FILE BEFORE IMPLEMENTING PHASE 7. IT CONTAINS THE ONE BLOCKER IN THE PLAN. ***

	`check:secrecy` gained a RULE 5 after the plan document was written and frozen. The plan does not
	mention it, cannot be edited, and Step 7.3 as written WILL FAIL until the waiver below is added.
	This review is the correction.
]]

-- .claude/scripts/check-secrecy.mjs:183
local ROLE_BLIND = { "TaskService.luau" }
-- IMPORTANT — EXACTLY ONE FILE IS SCOPED BY THIS RULE, AND IT IS THE FILE PHASE 7 EDITS.

-- .claude/scripts/check-secrecy.mjs:402-413  (rule 5)
-- if (ROLE_BLIND.some(name => file.endsWith(name))) {
--   for (const match of code.matchAll(/\b(IsAswang|GetAswangUserId|AswangUserId|GetRole)\b/g)) {
-- IMPORTANT: `TaskService.luau` may not contain `IsAswang`, `GetAswangUserId`, `AswangUserId` or
-- `GetRole` at all, waiver aside. The plan's Step 7.3 writes exactly this line:
--
--     local aswangUserId = RoundService.GetAswangUserId()
--
-- That is TWO matches on one line (`GetAswangUserId` and, in the local's name, `AswangUserId`), and
-- `npm run check:secrecy` — Step 7.3's own **Verify:** command — goes RED.
--
-- THE FIX IS THE WAIVER, AND THE RULE'S OWN COMMENT SANCTIONS IT BY NAME:
--   "If the read is legitimate — C12 must know who to send a fake list to — waive it with
--    `-- secrecy-ok: <why>` so it lands in a diff."
--
-- So Step 7.3's diff needs the waiver on the read, with a reason that would survive being argued
-- with. Suggested, and deliberately stating the SCOPE rather than just the need:
--
--   -- secrecy-ok: C12 must know who to send a decoy task list to (spec §4.4 + Amendment A2). Read
--   -- ONCE per round, at STARTING, into a local that dies with this function. It reaches no
--   -- contribution path: weightFor, the tick, notePresence and publishProgress are all untouched by
--   -- it, which is the property rule 5 exists to protect.
--   local aswangUserId = RoundService.GetAswangUserId()
--
-- NOTE: `hasWaiver` is line-scoped, so the comment must sit on or directly above the read.

-- .claude/scripts/check-secrecy.mjs:382-401 (rule 5's rationale)
-- "a grid guarantees exactly ONE function, and an exploit audit made the consequence concrete: the
--  oracle's natural home moved to TaskWeight's CALLERS, where nothing looked."
-- The four shapes it names:
--   weightFor         `if RoleService.IsAswang(player) then return 0 end`
--   the tick loop     skip the Aswang's presence entry, never build it a bucket
--   notePresence      refuse the Aswang's stamp
--   publishProgress   send the Aswang a different YourTaskProgress
-- IMPORTANT: this VALIDATES the plan's design and narrows only its placement. Every one of those four
-- shapes is a thing this plan already refuses to do — Phases 4 and 5 route through `weightFor`
-- untouched precisely so they cannot. Rule 5 is the mechanical version of the argument the plan makes
-- in prose at §1.2.

-- QUESTION, answered: should Phase 7's publish move OUT of TaskService to avoid the waiver?
-- NO, and the reasoning should be recorded rather than re-derived:
--   · RoleService knows the roles but not the drawn task Ids, so it would have to require TaskService
--     — and TaskService already requires RoundService, so the cycle risk moves rather than goes away.
--   · A new service for one function at STARTING is a file, a SERVICE_ORDER entry and a require edge
--     to buy silence from a check that is asking for one comment.
--   · The waiver IS the design. The rule's header says so: the read "will show up in a diff where it
--     can be argued with — which is the whole design." Moving the code to dodge the check moves the
--     read somewhere nothing is watching, which is strictly worse than a waived read in the file
--     everybody now knows to watch.

-- .claude/scripts/check-secrecy.mjs:70-91 — REVEAL_ALLOWLIST and PAYLOAD_FIELDS
-- Only `RoundEnded` and `RoleAssigned`, each with a field allowlist. NOTE: this plan touches NEITHER,
-- and `TaskListAssigned` is deliberately NOT added to either map — it carries no role, so it must
-- keep being scanned like any other remote. Being on the allowlist would EXEMPT it from rule 1.

-- .claude/scripts/check-secrecy.mjs:185-186
local SECRET = "\\b(aswang\\w*|imposter|impostor|monsteruserid|killer\\w*|iskiller|isaswang|secretrole)\\b"
local ROLE_TOKEN = "\\b(role|roles)\\b"
-- IMPORTANT for Phase 7's FireClient: rule 1 tests the raw ARGUMENT TEXT of every
-- `:FireClient` / `:FireAllClients` (after dropping the recipient) AND the resolved payload's FIELD
-- names. So `FireClient(player, TaskListView.forPlayer(realIds, decoyIds, role))` fails on
-- ROLE_TOKEN, while a typed local resolving to `{ TaskIds = ... }` passes. The plan already requires
-- the typed local for this exact reason — but note it is now enforced twice over, and the local's
-- name `shownRole` never enters the argument text.
-- NOTE: `SECRET` matching `aswang\w*` is also why the waived local above is safest named
-- `aswangUserId` on a line that mentions neither ReplicatedStorage nor Workspace (rule 4, :417-425).

-- WHAT RULE 5 DOES *NOT* COVER, and what the plan should still be audited for by a human:
-- IMPORTANT: it is a TEXT TRIPWIRE on four identifiers in one file. It cannot follow data flow, and
-- three of this plan's surfaces are outside it entirely:
--   · GateService.luau (Phase 6) reads `GetAswangUserId()` on a 4 Hz loop and is NOT in ROLE_BLIND.
--     That is correct — §4.8 needs the role — but it means the only thing standing between that loop
--     and an oracle is `pure/GateEscape.luau`'s 64-cell grid and review.
--   · The fetch item (Phase 4) is a replicated part following one player. No regex sees a Part.
--   · A field named `IsDecoy` on TaskListAssigned matches neither SECRET nor ROLE_TOKEN.
-- All three are in the plan's §4 Issues table. `exploit-auditor` is the answer to all three, and
-- CLAUDE.md is explicit that a text tripwire and an adversarial reader do not replace each other.

-- Self-test: 41/41, both directions, per the coordinator. NOTE: `check-secrecy.mjs --self-test`
-- proves each rule fires AND does not fire, which is the standard `harness-selftest.mjs` requires.
return nil
