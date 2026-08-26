--!strict
--[[
	KillValidation — may this Aswang kill this player right now, and if not, why not.

		(request) -> verdict

	§4.3's five verbatim server-side rules are "distance ≤ 8 studs, raycast line-of-sight, cooldown
	elapsed, both alive, round ACTIVE". Four of the five are comparisons over numbers and string enums
	and live here. The fifth — the raycast — is irreducibly Roblox and stays in MonsterService, which is
	the split TransformRules' header predicted for this module.

	SEVEN CONDITIONS, NOT SIX, and the two extras are not scope creep:

	  · the killer must BE the Aswang and the target must NOT be — C05's own Done line lists these, and
	    they are the whole of §6.2 applied to one remote.
	  · the killer must be TRANSFORMED. §4.3 step 3 reads "While transformed: +25% move speed, can kill
	    on touch/prompt within 8 studs" — the kill is a property of the monster form, not of the role.
	    Without it an Aswang kills from inside a crowd wearing a survivor's face and the risk/reward
	    pillar (§2) is gone. It is called out in Follow Ups because C05's bullet list does not say it.

	NO Vector3. Lune has no Roblox datatypes at all, so a Vector3 here would not fail to typecheck — it
	would fail at TEST time, which is the same trap Config's RGB triples exist to avoid (Config.luau
	lines 66–69). Positions are plain tables; MonsterService converts at the call site.

	NO `script.Parent` REQUIRES. The two enums are re-declared; Luau literal unions are structural, so
	these and their Types.luau counterparts are the same types.

	THIS ONE MAY LIVE IN src/shared/pure/, on the same test RoleDraw's header sets. A client can require
	and call it, and it learns nothing: every input is either a fact that client already holds about
	itself, a Config number that already replicates, or a position it can read off the workspace. The
	verdict it computes locally has no authority — the server evaluates its own copy against its own
	state, which is the only one that counts. Logic is not secret; inputs and seeds are, and this
	function has neither.

	THE VERDICT NEVER REACHES A CLIENT. TARGET_IS_ASWANG is a role oracle in one word.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"

-- A position, as plain numbers. See the Vector3 note above.
export type Vec3 = { X: number, Y: number, Z: number }

export type Verdict =
	"OK"
	| "WRONG_PHASE"
	| "KILLER_NOT_ALIVE"
	| "SELF"
	| "NOT_ASWANG"
	| "NOT_TRANSFORMED"
	| "ON_COOLDOWN"
	| "TARGET_NOT_ALIVE"
	| "TARGET_IS_ASWANG"
	| "OUT_OF_RANGE"

export type Request = {
	Phase: RoundPhase,
	KillerUserId: number,
	TargetUserId: number,
	KillerIsAswang: boolean,
	TargetIsAswang: boolean,
	KillerState: PlayerState,
	TargetState: PlayerState,
	Transformed: boolean,
	KillerPos: Vec3,
	TargetPos: Vec3,
	Range: number,
	Now: number,
	LastRevertedAt: number?, -- nil means "has not reverted this round"; never on cooldown
	Cooldown: number,
}

local KillValidation = {}

--[[
	SQUARED, so there is no square root and no float-comparison surprise at the boundary. `<=` rather
	than `<`: §4.3 says "within 8 studs", and a player standing at exactly the range is within it.
]]
local function withinRange(a: Vec3, b: Vec3, range: number): boolean
	--[[
		A DEGENERATE RANGE FAILS CLOSED. `range * range` is what makes this necessary: it maps -8 onto
		the same 64 as 8, so a typo'd minus sign in Config would silently keep working, and `math.huge`
		would make every kill in the map land. Both are M12 tuning traps rather than exploits — no
		client supplies this number — but the failure direction is the whole point. A range that cannot
		be honoured must refuse the kill, not grant it.

		FINITE AND POSITIVE, tested as one condition. `not (range > 0)` alone is not enough — it catches
		zero, negatives and NaN, but `math.huge > 0` is true, so an infinite range sailed past it and
		`25000000 <= inf` granted a kill from five thousand studs. Caught by the test below, which is
		why the boundary cases are written before the guard is trusted.

		Expressed as `not (positive and finite)` rather than as two negative tests, because NaN compares
		false to EVERYTHING: `NaN > 0` and `NaN < math.huge` are both false, so the conjunction is false
		and the negation refuses. Written the other way round — `range <= 0 or range >= math.huge` —
		every NaN comparison is false and NaN would pass straight through.
	]]
	if not (range > 0 and range < math.huge) then
		return false
	end

	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z

	return dx * dx + dy * dy + dz * dz <= range * range
end

--[[
	THE ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in TransformRules. It decides which
	reason a log line carries when more than one applies, and C41 reads those lines to tell an exploiter
	probing the boundary apart from a real player mashing a button.

	World facts first (phase), then the killer (alive, not itself, role, form, cooldown), then the
	target (alive, not the Aswang), then geometry last. Geometry is last deliberately: it is the only
	condition an honest player hits routinely, so a log full of OUT_OF_RANGE is a UX finding and a log
	full of anything above it is a security finding.

	A NOTE ON THE COOLDOWN CHECK BEING HERE AT ALL. Today it is redundant: a kill requires the
	transformed form, and TransformRules already refuses to grant that form until Cooldown has elapsed
	since the last revert, so an on-cooldown Aswang cannot be transformed in the first place. It is kept
	because C05's own bullet list names it, because the redundancy costs one comparison, and because the
	day something else grants the form — a C14 salt interaction, a debug path, a bug — this is the only
	check standing between that and a chain kill.
]]
function KillValidation.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	-- AN ALLOWLIST, on both sides, never `~= "SPECTATOR"`. See pure/PlayerBody.luau: PlayerState has
	-- four values, exactly one of them may kill and exactly one of them may be killed, and C15 makes
	-- DEAD real. A denylist here is the C01 bug wearing a different hat.
	if request.KillerState ~= "ALIVE" then
		return "KILLER_NOT_ALIVE"
	end

	-- Before the role check, so a compromised client cannot use "kill myself" as a role probe with a
	-- different refusal shape than "kill someone else".
	if request.KillerUserId == request.TargetUserId then
		return "SELF"
	end

	if not request.KillerIsAswang then
		return "NOT_ASWANG"
	end

	-- §4.3 step 3. The kill belongs to the monster form, not to the role.
	if not request.Transformed then
		return "NOT_TRANSFORMED"
	end

	-- §4.3 step 5: FROM THE REVERT, not from the kill. Measured from the kill, an Aswang holding the
	-- form for its full MaxTransformTime serves most of the penalty while still being a monster.
	-- tests/config.test.luau already pins KillCooldown > TransformTime + RevertTime for the same reason.
	local lastRevertedAt = request.LastRevertedAt

	--[[
		FAIL CLOSED ON EVERY CLOCK INPUT, and test the SUBTRACTION'S RESULT rather than its operands.

		A NaN cooldown (`0/0`, reachable from a Config typo like `KillCooldown = x / y` with `y` unset)
		makes `elapsed < NaN` false, so the gate silently never trips and the Aswang chain-kills.

		THIS TOOK THREE ATTEMPTS AND THE FIRST TWO BOTH SHIPPED. Recorded because the pattern is the
		lesson, not the line:

		  1. `Cooldown ~= Cooldown` only — missed both other inputs entirely.
		  2. Each operand tested individually — still missed `inf - inf`, which is NaN even though
		     neither operand is.
		  3. `elapsed ~= elapsed` on the result — subsumed every NaN, and still failed OPEN on a
		     non-NaN INFINITE result (`Now = inf`, `Last = 99` gives `elapsed = inf`, and `inf < 30` is
		     false), and on a NEGATIVE cooldown, where `Cooldown = -1` silently disabled the gate.

		So it is now POSITIVE-AND-FINITE on both the cooldown and the elapsed time, as one negated
		conjunction — the identical idiom `withinRange` above already uses, for the identical reason.
		A negative elapsed means the clock ran backwards, which must also refuse.

		No client supplies any of these today (`os.clock()` and Config), so none of it is an exploit.
		It is written because this module's header sells fail-closed as a PROPERTY, and a property that
		holds for some fields is a claim rather than a property — and `src/shared/pure/` is where the
		next author will copy the pattern from.
	]]
	--[[
		`> 0`, NOT `>= 0`, and the difference is a decision rather than a typo.

		A zero cooldown means "no cooldown", which reads as a sensible thing to want and is not: §4.3
		step 5 makes the 30 seconds after a revert the whole cost of a kill, and the pillar in §2 —
		every kill is a gamble — is that number. So zero is degenerate here in the same way a zero
		range is, and it must refuse rather than quietly disable the gate. An audit caught this line
		saying `>= 0` while the comment below claimed positive-and-finite; they now agree.
	]]
	if not (request.Cooldown > 0 and request.Cooldown < math.huge) then
		return "ON_COOLDOWN"
	end

	if lastRevertedAt ~= nil then
		local elapsed = request.Now - lastRevertedAt

		if not (elapsed >= 0 and elapsed < math.huge) or elapsed < request.Cooldown then
			return "ON_COOLDOWN"
		end
	end

	if request.TargetState ~= "ALIVE" then
		return "TARGET_NOT_ALIVE"
	end

	-- With AswangCount = 1 this is unreachable today. It is here because Config.Roles.AswangCount is a
	-- knob and §3's OUT list bans MULTIPLE ASWANGS PER ROUND — so the day someone sets it to 2 in a
	-- Studio session, the failure must be "the kill is refused", not "the monsters eat each other".
	if request.TargetIsAswang then
		return "TARGET_IS_ASWANG"
	end

	if not withinRange(request.KillerPos, request.TargetPos, request.Range) then
		return "OUT_OF_RANGE"
	end

	return "OK"
end

return KillValidation
