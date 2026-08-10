--!strict
--[[
	REVIEW — docs/MVP-SPEC.md, the sections this plan is built against.
	§3 (scope), §4.2 (roles), §4.3 (the kill mechanic), §6.2 (server authority), §6.4 (state machine),
	§6.5 (Config), Appendix A (balance).
]]

--[[
	§3 — the hard line. The OUT items this plan is closest to, and stays clear of:
	  · "Custom animations, custom monster mesh, voice acting"  -> §4.3's whole point is no mesh
	  · "Weapons or combat beyond salt"                          -> C04 builds no attack; C05 does
	  · "Multiple Aswangs per round"                             -> AswangCount stays a Config value,
	    and RoleDraw supports n>1 only so the degenerate case is safe, never as a feature
	NOTE `check:scope`'s token list matches whole words after splitting identifiers, so nothing this
	plan names ("TransformedTintRgb", "AswangEye", "MonsterState") can trip it.
]]

--[[
	§4.2 — Roles. The three rules, all three implemented in Phase 5:

		"Server-side only. Never replicate the Aswang's identity to any other client. Not in a tag, not
		 in a name colour, not in an attribute, not 'hidden' in a value the client can read. Assume every
		 client is compromised."

		"Anti-repeat: track the last 2 rounds; a player who was Aswang last round has heavily reduced
		 weight. Nothing kills a session faster than never being the monster — or being it three times in
		 a row."

		"Aswang gets a 3-second private intro."

	IMPORTANT: "heavily reduced weight", not "excluded". That word is the whole reason the weights are
	positive numbers rather than a ban list, and why tests/role-draw.test.luau proves BOTH a lowered
	back-to-back rate AND no starvation. The second half of that sentence — "or being it three times in
	a row" — is the anti-repeat; the first half — "never being the monster" — is the starvation check.
]]

--[[
	§4.3 — the kill mechanic. Steps 1–3 are C04; steps 4–5 are C05. Verbatim:

		1. Aswang presses Transform (mobile button / key).
		2. 1.2s transform animation — visible to anyone with line of sight. Distinct silhouette, red eye
		   glow, audio cue that carries ~40 studs.
		3. While transformed: +25% move speed, can kill on touch/prompt within 8 studs.
		4. After a kill (or after 8s), it must revert (1.0s). Corpse remains for 45s, then fades.
		5. Kill cooldown: 30s from revert.

	IMPORTANT step 2: "visible to anyone with line of sight" describes the ANIMATION, not its aftermath.
	That is why MonsterTransformed is broadcast at the START of the windup rather than after it —
	broadcasting after would make the transform instantaneous to observers and delete the risk half of
	the risk/reward moment.

	IMPORTANT step 5: "from revert". MonsterState.LastRevertedAt is set when the 1.0s revert animation
	COMPLETES, and TransformRules measures from it.

	And the reason this is cheap, which is why §3 forbids a mesh:
		"It is cheap to build — no custom monster model needed. Reuse the player avatar with a scale
		 change, a colour/material shift, glowing eyes, and a particle emitter."

	NOTE §4.3's server-side rule list — "distance <= 8 studs, raycast line-of-sight, cooldown elapsed,
	both alive, round ACTIVE" — is C05's. C04 implements the subset that applies to transforming.
]]

--[[
	§6.2 — server authority. The four bullets, and the one that shapes Phase 7 most:

		"The Aswang's identity is server-only state. It is never sent to other clients in any form."
		"Clients request actions. The server validates and decides."
		"Every RemoteEvent is rate-limited and validates types, state, distance, and cooldown."
		"The transform *is* public — that's intentional design, so replicating it is correct."

	IMPORTANT the fourth bullet is the licence for MonsterTransformed:FireAllClients. It is the ONLY
	place in the spec where replicating something about the Aswang is called correct.
]]

--[[
	§6.4 — the state machine, and the five edge cases. Which apply to this plan:
	  · "The Aswang leaves mid-round -> end round immediately"  — C01 handles it; Phase 5 only fills in
	    the field it reads, Phase 7's phase subscription reverts on the way out
	  · "A player joins mid-round -> spectator until ENDING"    — Phase 7's allowlist; the BODY half is
	    unresolved and is this plan's highest-severity open issue
	  · "Player count drops below minimum -> finish the round"  — untouched
	  · timer-end and BindToClose                                — untouched

	And the rule stated twice: "Never let gameplay code mutate phase directly. Every service subscribes
	to phase changes."
]]

--[[
	§6.5 / Appendix A — every tunable in one file, and the tuning target:

		"Target: neither side wins more than ~60% of rounds."

	Appendix A names Transform time (1.2s) with "Raise if Aswang too sneaky / Lower if Aswang always
	caught" — which only reads correctly if the windup is the visible tell, as above. Kill cooldown 30s:
	"Raise if Aswang wins too often." Neither is measurable before C40 wires win rate per side.
]]
