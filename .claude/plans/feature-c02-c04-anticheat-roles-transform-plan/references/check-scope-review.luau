--!strict
--[[
	REVIEW — .claude/scripts/check-scope.mjs and .claude/scripts/lib/luau-source.mjs

	Read to confirm nothing this plan names can trip the scope alarm, and to understand the shared
	stripping every check depends on.
]]

--[[
	check-scope.mjs — the OUT-list tokens, matched as WHOLE WORDS after identifiers are split on case
	and on the letter/digit boundary:

		manananggal, tiktik, kapre, tiyanak, tikbalang, meeting(s), vote/votes/voted/voter/voting,
		eject(ed|ion|s), campaign(s), zone(s), weapon(s), machete, bolo, sabotage(d|s), trade(s),
		trading, guild(s), pet(s), season(s)

	IMPORTANT — the splitting is why `startVote` is a hit and `devotion` is a miss:

		"`\b` anchors were the first attempt and they failed on every realistic spelling:
		 `ManananggalService` has no word boundary after 'manananggal', and neither does `startVote`
		 before 'vote' — so the four most likely first appearances of a scope breach all read as clean."

	CHECKED against every identifier this plan introduces — AntiCheatService, TokenBucket, RoleDraw,
	TransformRules, MonsterState, AswangTransformFX, AswangEye, TransformedTintRgb, EyeGlowRgb,
	RequestTransform, BeginTransform, ScheduleForcedRevert, RoleAssignedPayload. None splits into any
	listed token. Clean.

	NOTE it scans `withStrings`, so a UI label counts too — "Vote to eject" would be flagged. The role
	intro strings this plan writes ("YOU ARE THE ASWANG. Do not get seen.", "You are a survivor. Finish
	five tasks and escape.") contain no listed token.

	NOTE it is scoped to `src/` deliberately: "docs, ROADMAP and plans are exactly where these ideas
	SHOULD live, and flagging them there would train everyone to ignore it." So this plan document
	naming C15's ghosts or C05's kill costs nothing.
]]

--[[
	lib/luau-source.mjs — the shared reader. Two properties this plan relies on:

	  1. COMMENTS AND STRING LITERALS ARE REPLACED WITH SPACES, preserving line count and every offset.
	     "a comment saying 'never fire the role to all clients' contains the exact tokens the secrecy
	      check hunts for. Matching raw source means any file DOCUMENTING a rule trips the check written
	      to enforce it."
	     Consequence: the long security headers this plan writes into RoleService, RoleDraw and
	     MonsterService cannot trip check:secrecy or check:scope, however explicit they are. Writing the
	     rule down is free.

	  2. `code` has strings blanked; `withStrings` keeps them. Different checks read different views —
	     check:secrecy reads `withStrings` to find a remote's NAME, check:scope reads it to catch a UI
	     label, check:config reads `code`. Relevant because a magic number inside a string
	     (`print("waited 30 seconds")`) is NOT flagged, and one inside an interpolated string is treated
	     as text wholesale.

	  3. The waiver helper `hasWaiver(rawLines, line, kind)` reads the RAW line, so `-- config-ok: ...`
	     works even though comments are stripped from the matching view. Format is
	     `-- <kind>-ok: <reason>` with a MANDATORY reason.
]]
