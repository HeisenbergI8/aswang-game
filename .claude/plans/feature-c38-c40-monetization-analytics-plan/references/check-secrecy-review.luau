--!strict
--[[
	REVIEW — .claude/scripts/check-secrecy.mjs:70-93, :169-183, :257-276, :402

	Read to answer the third part of Q2: "state how `check:secrecy` sees it". The answer is that it
	does NOT see an analytics call site at all, and that is the gap Step 3.2 fills.
]]

-- .claude/scripts/check-secrecy.mjs:70-73
export const REVEAL_ALLOWLIST = new Map([
  ['RoundEnded', 'the round is over — the reveal is the point (spec §4.8)'],
  ['RoleAssigned', 'fired to exactly one player, carrying only that player\'s OWN role (spec §4.2)']
])
-- NOTE: the two remotes allowed to carry a role. Adding a third means editing this file, which
--       shows up in review. THE ASYMMETRY IS THE DESIGN, and Rule 6 in Step 3.2 copies it: adding a
--       remote to the analytics emitter also becomes an edit to this file.

-- .claude/scripts/check-secrecy.mjs:87-93
export const PAYLOAD_FIELDS = new Map([
  ['RoundEnded', new Set(['Result', 'AswangUserId', 'RoundNumber'])],
  ['RoleAssigned', new Set(['Role'])]
])
-- IMPORTANT: an allowlisted remote must also declare which FIELDS it may carry, because Luau
--            "independently accepts an EXTRA field on an annotated table (measured: a wrong type
--            and a missing field are caught, an extra one is not)".
--
--            This is why C40's `role_assigned` analytics is a SEPARATE STATEMENT after the
--            `RoleAssigned:FireClient`, never a field added to that payload. A `role` field there
--            would be a stray and correctly refused; the temptation exists because both lines are
--            about the same fact.

-- .claude/scripts/check-secrecy.mjs:169-183
//[ Rule 5 ] Server files that must never branch on who the Aswang is.
const ROLE_BLIND = ['TaskService.luau']
-- IMPORTANT: the header says the scan applies to "broadcast payloads, attribute names and tag
--            names — NEVER general server code."
--
--            THIS IS THE WHOLE ANSWER TO "how does check:secrecy see it": a line reading
--            `RobloxAnalytics:LogCustomEvent(player, "role_assigned", nil, { role = role })`
--            matches NO rule and passes `npm run verify` green. That outcome is CORRECT — it is not
--            a leak — but it means nothing mechanical distinguishes it from a line one character
--            different that fires a remote instead, in the one file guaranteed to be holding the
--            role while someone wires up funnels.
--
-- NOTE: Rule 5 and the plan's new Rule 6 are deliberate mirrors. Rule 5 names files that must not
--       be ABLE TO TELL who the Aswang is. Rule 6 names a file that must be able to tell and must
--       not be able to SAY.

-- .claude/scripts/check-secrecy.mjs:257-276
for (const match of withStrings.matchAll(/:Fire(?:AllClients|Client)\s*\(/g)) {
  const remote = remoteNameBefore(withStrings, match.index)
  if (!remote || !REVEAL_ALLOWLIST.has(remote)) continue
-- NOTE: the scan hangs off `:Fire*(` call sites. An analytics call is not one, which is the
--       mechanical reason the emitter is invisible to it.
-- IMPORTANT: the comment above this loop records that the FIRST version of the field check "fired
--            on neither of them" — an audit added `KillerName` to a real reveal payload and the
--            scan returned zero findings. A check that looks correct and matches nothing is the
--            failure mode this whole file is defensive about, which is why Rule 6's self-test must
--            prove BOTH directions.

-- .claude/scripts/check-secrecy.mjs:402
if (ROLE_BLIND.some(name => file.endsWith(name))) {
-- NOTE: the shape Rule 6's scan clause copies — a filename filter, then a regex over the file's
--       code, honouring `-- secrecy-ok:` waivers via `hasWaiver`.
-- IMPORTANT: Rule 6 protects the EMITTER, not the call sites. A `FireAllClients` added in
--            RoundService beside the `player_killed` emit is caught by rules 0-4 only if its
--            payload text names the secret — and Amendment A3's point is that a payload naming
--            NOBODY (a bare "someone died") is already fatal. Nothing mechanical catches that,
--            which is why `exploit-auditor` is mandatory on Phase 3.

-- NOTE: `check-secrecy` is already listed in `harness-selftest.mjs`'s SUITES (:93), so Rule 6 needs
--       no SUITES edit — only new cases inside the script's existing `--self-test`.
