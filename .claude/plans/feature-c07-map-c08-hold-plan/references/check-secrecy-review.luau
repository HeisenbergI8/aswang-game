--!strict
-- REVIEW: .claude/scripts/check-secrecy.mjs:1-60 (the header, which is an honest account of its own
-- limits) and REVEAL_ALLOWLIST at :62+
--
-- Read to answer one question exactly: what does `npm run check:secrecy` actually prove about
-- TaskProgressChanged, the ActiveTaskPoint tag, and the new client controller?

-- Four shapes:
--   1. A secret-bearing payload on a send — FireAllClients / FireClient carrying a role or a userId.
--      The payload is resolved back to its `local x = { … }` declaration.
-- NOTE: this rule DOES run over Step 4.2's call, because TaskProgressChanged is not on REVEAL_ALLOWLIST
-- — being on that list makes the scanner SKIP a call, so being off it is the good outcome.
-- IMPORTANT: it resolves a TABLE CONSTRUCTOR bound to a local within 1200 characters, read at its top
-- level. That is exactly the idiom Step 4.2 uses, so the payload is inspected rather than skipped.

--   2. Attributes and CollectionService tags. Both REPLICATE TO EVERY CLIENT.
-- IMPORTANT for the `ActiveTaskPoint` tag (Step 2.3) and the `TaskType` attribute (map contract). Both
-- replicate; neither carries a role or a UserId, so this rule passes them. That is a correct pass, not
-- a near miss: §1.3 of the plan argues the selection is public BY DESIGN. The tag is named for a place,
-- not for a person.

--   3. The client naming the secret at all. `AswangUserId` appearing anywhere under `src/client/`.
-- NOTE: this is the rule doing the work at Step 5.3, over the new TaskController. It fails whether the
-- token is received or merely guessed at.

-- ── WHAT IT CANNOT SEE, STATED PLAINLY ────────────────────────────────────────
-- Data flow. `local x = state.AswangUserId` followed twenty lines later by `event:FireAllClients(x)`
-- passes this check. Renaming the variable defeats it entirely.
-- IMPORTANT and the reason the plan does not treat a green check:secrecy as coverage. Concretely, for
-- THIS plan's payload:
--     caught     — Role, AswangUserId, KillerUserId added to TaskProgressPayload
--     NOT caught — PresentPlayerCount, HolderCount, Contributors
-- The second row is the actual leak shape here: any field that reveals HOW MANY people are contributing
-- reinstates the bystander oracle that §1.4 decision 2 exists to close, and it contains no secret token
-- at all. Risk R1, and the reason exploit-auditor is mandatory on this diff.

--   · a field assigned AFTER the constructor      — `payload.KillerUserId = k`
--   · a payload built by a helper
--   · a declaration further than 1200 characters from the call
-- NOTE: three ways to get a field past rule 1 even when it does carry a token. Step 4.2 builds the
-- table inline in the local, immediately above the FireClient, in the same function — inside the
-- envelope on all three counts. That is deliberate, not incidental.

-- Remotes that are ALLOWED to carry the secret ... Anything not on this list is refused, so adding a
-- leak requires editing this file — which shows up in a diff and in review.
export const REVEAL_ALLOWLIST = new Map([ /* RoundEnded, RoleAssigned */ ])
-- IMPORTANT: this plan does NOT touch REVEAL_ALLOWLIST. Two carriers of the secret remain two.
-- NOTE Types.luau proposes a FIELD allowlist for the two reveal remotes as the enforceable version of
-- its payload comments. This plan adds a third payload whose safety rests on a field name never
-- appearing, which strengthens that case — recorded as Follow Ups Q6 rather than built, since a harness
-- change carries its own self-test obligations in harness-selftest.mjs.

-- NOTE finally, from CLAUDE.md rather than this file: check:secrecy and check:ratelimit are "text
-- tripwires on obvious shapes. They cannot follow data flow." In this repo's C04 work every gate was
-- green over a Critical secrecy bug and only exploit-auditor found it. Static green over a secrecy
-- surface means very little, which is why the plan's risk table exists at all.
