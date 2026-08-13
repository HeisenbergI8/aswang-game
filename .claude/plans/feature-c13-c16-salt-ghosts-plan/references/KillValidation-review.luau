--!strict
--[[
	REVIEW — src/shared/pure/KillValidation.luau (221 lines)

	Excerpted ranges:
	  · src/shared/pure/KillValidation.luau:108-123  the fixed verdict ordering
	  · src/shared/pure/KillValidation.luau:130-135  the allowlist rule, on both sides
	  · src/shared/pure/KillValidation.luau:157-201  the fail-closed idiom, and its three failed attempts
	  · src/shared/pure/KillValidation.luau:203-216  target checks and geometry last

	Read as the TEMPLATE. `pure/SaltThrow` (Step 3.1) is written to this module's shape deliberately, and
	three of its decisions are inherited rather than re-derived.
]]

-- src/shared/pure/KillValidation.luau:108-116
--	THE ORDER IS FIXED AND IS PART OF THE CONTRACT... It decides which reason a log line carries when
--	more than one applies, and C41 reads those lines to tell an exploiter probing the boundary apart
--	from a real player mashing a button.
--	World facts first (phase), then the killer... then the target..., then geometry last. Geometry is
--	last deliberately: it is the only condition an honest player hits routinely, so a log full of
--	OUT_OF_RANGE is a UX finding and a log full of anything above it is a security finding.
-- IMPORTANT COPIED VERBATIM BY `SaltThrow.evaluate` and by `SaltCarry.evaluate`: phase, then the actor,
--      then the resource, then geometry. The UX-finding / security-finding split is what makes C41's job
--      possible at all, and it is free.

-- src/shared/pure/KillValidation.luau:130-135
	-- AN ALLOWLIST, on both sides, never `~= "SPECTATOR"`. See pure/PlayerBody.luau: PlayerState has
	-- four values, exactly one of them may kill and exactly one of them may be killed, and C15 makes
	-- GHOST real. A denylist here is the C01 bug wearing a different hat.
	if request.KillerState ~= "ALIVE" then
		return "KILLER_NOT_ALIVE"
	end
-- IMPORTANT THIS FILE NEEDS NO EDIT IN THIS PLAN AND THAT IS THE POINT. Phase 6 gives a ghost a body;
--      this module keeps refusing a ghost as both killer and target because it names the state it
--      permits. "C15 makes GHOST real" was written in anticipation and the anticipation held.
-- NOTE `SaltCarry` and `SaltThrow` both allowlist ALIVE for the same reason — a ghost must not pick up
--      or throw salt, and after Phase 6 a ghost is walking over pouches with a body.

-- src/shared/pure/KillValidation.luau:157-175
--	FAIL CLOSED ON EVERY CLOCK INPUT, and test the SUBTRACTION'S RESULT rather than its operands.
--	THIS TOOK THREE ATTEMPTS AND THE FIRST TWO BOTH SHIPPED...
--	  1. `Cooldown ~= Cooldown` only — missed both other inputs entirely.
--	  2. Each operand tested individually — still missed `inf - inf`, which is NaN even though
--	     neither operand is.
--	  3. `elapsed ~= elapsed` on the result — subsumed every NaN, and still failed OPEN on a
--	     non-NaN INFINITE result... and on a NEGATIVE cooldown
-- IMPORTANT THE LESSON, NOT THE LINE, AND THIS PLAN APPLIES IT FIRST TIME IN THREE PLACES:
--      · SaltCarry's `Limit` — `math.huge` is not NaN, passes every "is it a number" test, and makes
--        `Carried < Limit` true forever. The limit silently stops existing.
--      · SaltThrow's `Range` and `ConeDegrees` — same shape, plus a NaN `Direction` a CLIENT can send,
--        which is the first time this idiom guards something an attacker controls.
--      · SpookBudget's `Allowance`.
-- NOTE Each is written as one negated conjunction — `not (x > 0 and x < math.huge)` — which is the
--      identical idiom `withinRange` uses at line ~105, for the identical reason.

-- src/shared/pure/KillValidation.luau:177-181
--	No client supplies any of these today (`os.clock()` and Config), so none of it is an exploit.
--	It is written because this module's header sells fail-closed as a PROPERTY, and a property that
--	holds for some fields is a claim rather than a property
-- IMPORTANT `SaltThrow` IS THE CASE THIS SENTENCE WAS WAITING FOR. Its `Direction` comes straight off a
--      remote, so `normalise` returning nil for a zero-length or non-finite vector is a live guard rather
--      than a discipline: without it, a NaN direction sails past the cone test, because every comparison
--      against NaN is false and "not outside the cone" is what the test asks.

-- src/shared/pure/KillValidation.luau:118-123
--	A NOTE ON THE COOLDOWN CHECK BEING HERE AT ALL. Today it is redundant: a kill requires the
--	transformed form... It is kept because... the day something else grants the form — a C14 salt
--	interaction, a debug path, a bug — this is the only check standing between that and a chain kill.
-- NOTE C14 IS THIS CHUNK AND IT DOES NOT GRANT THE FORM — salt only ever REMOVES it, via
--      `MonsterService.ForceRevert`. The redundancy stays redundant, and `revert` stamping
--      `LastRevertedAt` means a salt hit actively charges the cooldown rather than bypassing it.

-- src/shared/pure/KillValidation.luau:150-156
--	`TARGET_IS_ASWANG` is a direct role oracle — fire RequestKill at every player in turn and the one
--	that answers differently is the monster — and KILLER_NOT_ASWANG is the same oracle pointed inward.
--	There is no "safe subset" to return, which is why the handler returns nothing at all on every
--	refusal rather than filtering the verdict.
-- IMPORTANT THE ARGUMENT `Types.SaltVerdict` INHERITS AND EXTENDS. Salt's version is sharper: splitting
--      MISS into MISS_NOT_ASWANG and MISS_OUT_OF_RANGE would build the same oracle, and salt's cost — one
--      pouch — is exactly what §4.6 already charges for an HONEST reveal. So the probe would be free.
--      `tests/salt-throw.test.luau` asserts the four non-hit worlds are one indistinguishable verdict,
--      which is the only mechanism that would notice a future "improvement" to salt's logging.
