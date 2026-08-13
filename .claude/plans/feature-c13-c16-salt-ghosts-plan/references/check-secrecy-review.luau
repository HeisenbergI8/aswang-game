--!strict
--[[
	REVIEW — .claude/scripts/check-secrecy.mjs (600+ lines; a Node script, excerpted as Luau comments)

	Excerpted ranges:
	  · check-secrecy.mjs:67-86    REVEAL_ALLOWLIST and the field allowlist
	  · check-secrecy.mjs:185      the SECRET regex
	  · check-secrecy.mjs:337-367  the broadcast rule, attributes and tags
	  · check-secrecy.mjs:599      an ALLOW case that matters to Phase 4

	Read because C14's reveal glow is visible to everyone by design, and the plan has to argue why that
	is not a third role-carrying remote. This file is where that argument is adjudicated.
]]

-- check-secrecy.mjs:67-71
-- Remotes that are ALLOWED to carry the secret, each with the reason it is safe. Anything not on this
-- list...
export const REVEAL_ALLOWLIST = new Map([ /* RoundEnded, RoleAssigned */ ])
-- IMPORTANT TWO ENTRIES, AND THIS PLAN ADDS NONE. The reveal glow is not a remote at all: the server
--      attaches a Highlight to a character already standing in the workspace. No payload carries a role,
--      no remote is fired, and the inference a witness makes is the one §4.6 is selling.
-- NOTE The precedent is `Types.MonsterTransformedPayload`: "'this character transformed' is a fact about
--      the world, while 'this player is the Aswang' is an inference the client is welcome to make and the
--      server never states." The glow is the same shape, and it is why `MonsterTransformed` is also not
--      on this list despite being the game's one public tell.

-- check-secrecy.mjs:77-86
-- REVEAL_ALLOWLIST exempts a CALL. Until this existed it exempted the whole call, so the scanner
-- [skipped the payload entirely] ... THIS file, which shows up in review — the same asymmetry that
-- makes REVEAL_ALLOWLIST worth having.
-- NOTE The asymmetry IS the design: adding a third carrier requires editing this script, which appears in
--      a diff and can be argued with. Nothing in this plan edits it, and that is a claim worth checking
--      at implementation time rather than trusting.

-- check-secrecy.mjs:185
const SECRET = /\b(aswang\w*|imposter|impostor|monsteruserid|killer\w*|iskiller|isaswang|secretrole)\b/i
-- IMPORTANT WHAT THIS CAN AND CANNOT SEE, and the plan depends on the second half:
--      · CAUGHT — a field named `AswangUserId`, `KillerUserId`, `IsAswang` on a scanned payload.
--      · NOT CAUGHT — `AlivePlayerCount`. A count matches no token here, which is why Amendment A3 is a
--        spec sentence and a comment in Types.luau rather than a check.
--      · NOT CAUGHT — `SurvivorsRemaining`, `DeadCount`, `RosterSize`, or a roster a client can count.
--        Every substitute for the field this plan removes is invisible to this regex.
--      · NOT CAUGHT — a recipient LIST. `FireClient(player, payload)` inside a loop over the wrong set
--        is textually identical to the right one, which is why `GhostRoster`'s state test lives at the
--        fire site (Step 6.5) rather than in a helper.

-- check-secrecy.mjs:350-357
// 2. Attributes and tags replicate to every client. There is no private attribute.
for (const match of withStrings.matchAll(/:SetAttribute\s*\(\s*["']([^"']+)["']/g)) {
  if (!SECRET.test(match[1]) && !ROLE_TOKEN.test(match[1])) continue
  // ...'There is no private attribute. Keep the role in a server-side table keyed by UserId.'
}
-- IMPORTANT THE SHAPE STEP 4.2 IS TEMPTED INTO. `character:SetAttribute("Revealed", true)` is the
--      two-line version of the whole reveal function, and it would let any client poll every player for
--      the flag, every frame, for as long as the attribute exists.
-- NOTE The same block scans `AddTag`. Both replicate; there is no private one.

-- check-secrecy.mjs:599
  check('an unrelated attribute', 'character:SetAttribute("Stunned", true)', false)
-- IMPORTANT AN EXPLICIT ALLOW CASE, AND IT IS A WARNING RATHER THAN A PERMISSION. A neutrally-named
--      attribute passes this check and would still be a per-frame readable brand on a player — "Stunned"
--      on exactly one character during ACTIVE is "salt hit the monster", readable by any client.
--      Step 4.1's stun writes no attribute at all (it sets WalkSpeed/JumpPower and keeps its state in a
--      server-side table keyed by UserId), which avoids the question rather than passing it.
-- NOTE This is the concrete case behind CLAUDE.md's "check:secrecy and check:ratelimit are TEXT TRIPWIRES
--      on obvious shapes. They cannot follow data flow. That is what exploit-auditor is for."

-- check-secrecy.mjs:433-435
// The ALLOW cases outnumber the BLOCK cases deliberately. A guard that only proves it can refuse has
// not been shown to be usable.
-- NOTE Worth knowing before reading a green `check:secrecy` as evidence of anything: the script's own
--      self-test is mostly about not producing false positives. Passing it means the obvious shapes are
--      absent, not that the design is sound.
