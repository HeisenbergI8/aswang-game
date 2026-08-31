--!strict
--[[
	FeedRules — may this Aswang feed on this body, right now? (V06, §4.3)

		evaluate(request)    -> verdict    may a feed START
		mayContinue(request) -> verdict    may a feed still be RUNNING

	§4.3: "After a kill, the Aswang must feed on the corpse for 5 seconds — transformed, locked in
	place, visible, and interruptible." This module owns the FIRST and THIRD words of that sentence
	and nothing else. It holds no clock, no player, no Instance and no body; `MonsterService` owns the
	five seconds, the lock, the corpse and the heal.

	WHY THE VERDICT NAMES THE REASON. There is no client request behind a feed — the server starts it
	as a consequence of a kill it already validated — so the refusal reasons exist for the SERVER's
	log, which is where a feed that never starts gets diagnosed. They are also what a client hint
	would be built from later, and the union is written so that such a hint could not become a role
	oracle: every value here concerns THE RECEIVER'S OWN monster state, and a client that is not the
	Aswang can never cause this function to run at all.

	CONTRAST `ItemThrow`, WHICH DELIBERATELY COLLAPSES ITS REFUSALS INTO ONE `MISS`. That module is
	called on a request a SURVIVOR sends about ANOTHER PLAYER, so a split verdict would let a client
	stand in front of each player in turn and read the monster off the refusal shape. This module is
	called about the feeder itself, by the server, unprompted. Different question, different answer.

	WHY `src/shared/pure/` IS SAFE FOR THIS. The rule is in the spec, in this comment, and visible in
	one round of play; a client that requires this module learns that feeding needs a corpse and six
	studs. What it cannot obtain is any INPUT: `MonsterState` is derived from `monsters[userId]` in
	server memory, `BodyKind` from which workspace folder a model is parented to, and `Distance` from
	two server-read positions. There is no seed here and no draw. `.claude/lessons/absence-is-
	observable.md` applies in its structural direction: the module mentions no player and no UserId,
	so there is no arrangement of it in which one player's answer is distinguishable from another's.

	NO `script.Parent` REQUIRES — Lune has no `script`. The three unions are re-declared; Luau unions
	are structural, so these and the matching ones in `Types` are the same types and pass to each
	other without a cast. The verdict is returned as a SCALAR and never inside a list:
	`.claude/lessons/pure-module-unions-widen-in-lists.md` is what that rule costs when it is broken.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
export type BodyKind = "CORPSE" | "HUSK"

--[[
	`NOT_A_CORPSE` COVERS BOTH A HUSK AND NO BODY AT ALL, and that is one value on purpose.

	The build plan's rule is "a husk is not feedable until it has been killed, at which point it is a
	corpse". Splitting `HUSK` from `NO_BODY` would buy a log line one adjective and would create the
	only place in this module where the answer varies by something a MAP AUTHOR controls — a body that
	stopped existing mid-feed and a body that was never a corpse are the same fact to a feeder.
]]
export type Verdict =
	"OK"
	| "WRONG_PHASE" -- feeding is an ACTIVE-phase activity and nothing else
	| "ALREADY_FEEDING" -- a feed is already running; one body at a time
	| "NOT_TRANSFORMED" -- the feed belongs to the monster form, not to the role
	| "NOT_A_CORPSE" -- a husk, or no body resolved at all
	| "OUT_OF_RANGE" -- past the leash, or a degenerate distance or range

export type Request = {
	MonsterState: MonsterState,
	-- OPTIONAL, and nil is a real answer rather than a caller's mistake: `MonsterService.bodyKindOf`
	-- returns nil for a model in neither the Corpses nor the Husks folder, which is what a corpse
	-- destroyed mid-feed looks like from the tick.
	BodyKind: BodyKind?,
	Distance: number,
	Phase: RoundPhase,
	-- Config.Monster.FeedLeashStuds at the call site. Taken as a field rather than read here, so the
	-- test can hand this module a synthetic range and `check:config` has no literal to flag.
	Range: number,
}

local FeedRules = {}

--[[
	FAIL CLOSED ON EVERY DEGENERATE NUMBER, and test the values rather than trusting them.

	Lifted from `KillValidation.withinRange`, whose header records what each guard cost. The idiom is
	`not (positive and finite)` rather than two negative tests, because NaN compares false to
	EVERYTHING: written the other way round, `range <= 0 or range >= math.huge`, every NaN comparison
	is false and a NaN sails straight through into `distance <= NaN`, which is also false, which
	GRANTS the feed.

	A NEGATIVE DISTANCE IS REFUSED TOO. It cannot arise from a `Magnitude`, and that is exactly why:
	if one ever appears, something upstream has stopped being a distance and the safe answer is to
	break the feed rather than to hold a monster in place on a number nobody can explain.
]]
local function withinRange(distance: number, range: number): boolean
	if not (range > 0 and range < math.huge) then
		return false
	end

	if not (distance >= 0 and distance < math.huge) then
		return false
	end

	-- `<=`, so a feeder at exactly the leash is still on the body. Same boundary choice as
	-- KillValidation's "within 8 studs", and the test asserts it rather than leaving it to a reader.
	return distance <= range
end

--[[
	THE SHARED CORE: everything that must be true for a feed to be HAPPENING, in the order that
	decides which reason a log line carries when more than one applies.

	World facts first (phase), then the feeder's own form, then the body, then geometry. Geometry is
	LAST for `KillValidation`'s reason: it is the only condition an honest Aswang hits routinely, so a
	log full of OUT_OF_RANGE is a UX finding and a log full of anything above it is a bug.

	`FEEDING` COUNTS AS THE FORM HERE. A feed in progress is a transform being held — see
	`MonsterService.monsterStateOf`, which returns FEEDING only when `Feeding AND Transformed`, so
	this value can never mean "feeding, but reverted". The two callers below decide what to do about
	FEEDING before they get here.
]]
local function feedable(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	--[[
		AN ALLOWLIST OVER FIVE STATES, NEVER `~= "NORMAL"`. `MonsterState` has five values and exactly
		two of them are the monster form. `EXPOSED` and `CAMOUFLAGED` are refused here and neither has
		a producer today — `monsterStateOf` never returns them (Exposed is a LATCH that coexists with
		the form; camouflage is V07) — but a state with no stated answer is how `pure/BodyTransitions`
		says these tables acquire bugs, so both are answered and both are in the grid.
	]]
	if request.MonsterState ~= "TRANSFORMED" and request.MonsterState ~= "FEEDING" then
		return "NOT_TRANSFORMED"
	end

	--[[
		THE HUSK RULE, AND IT IS A READ RATHER THAN A RE-IMPLEMENTATION.

		The husk -> corpse transition already exists in `MonsterService.validateAndKillHusk`: it marks
		the husk killed in `RoundService` and calls `makeCorpse`, which reparents the body into
		`workspace.Corpses` as `Corpse_{userId}`. A killed husk therefore IS a corpse, physically, in
		a different folder. This module does not model that; it compares the answer.
	]]
	if request.BodyKind ~= "CORPSE" then
		return "NOT_A_CORPSE"
	end

	if not withinRange(request.Distance, request.Range) then
		return "OUT_OF_RANGE"
	end

	return "OK"
end

--[[
	MAY A FEED START? Called once, by `MonsterService.beginFeed`, on a kill the server already
	validated.

	THE `ALREADY_FEEDING` CHECK MUST PRECEDE `feedable`, AND IT IS NOT AN ORDERING PREFERENCE. Left to
	`feedable`, a monster mid-feed would be told `OK` — FEEDING passes that allowlist — and the server
	would start a second feed on a second body while the first one's tick was still running. Two live
	feeds is two heals for one corpse.

	THE PHASE CHECK IS REPEATED ABOVE IT RATHER THAN INHERITED, and the duplicated comparison is the
	price of keeping this module's stated contract true: world facts first, always. Without it,
	`FEEDING` during `ENDING` reports ALREADY_FEEDING — a fact about the feeder — when the fact worth
	acting on is that the round is over. `tests/feed-rules.test.luau`'s precedence table pins it.
]]
function FeedRules.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	if request.MonsterState == "FEEDING" then
		return "ALREADY_FEEDING"
	end

	return feedable(request)
end

--[[
	MAY A FEED STILL BE RUNNING? Called four times a second by `MonsterService.feedTick`, and it is
	the whole of §4.3's "interruptible" that lives in a pure module.

	NOT `FEEDING` MEANS THE FORM WENT AWAY UNDER THE FEED, which is what a salt hit looks like from
	here: `ApplySaltHit` reverts, `monsterStateOf` stops returning FEEDING, and the next tick reads
	NOT_TRANSFORMED and ends the feed. That path is a BACKSTOP rather than the mechanism —
	`ApplySaltHit` ends the feed explicitly and in order — but it is the one that also covers a revert
	from any source nobody has thought of yet.
]]
function FeedRules.mayContinue(request: Request): Verdict
	-- World facts first, for `evaluate`'s reason: a feed running when the round ends is refused
	-- because the ROUND ended, not because of anything about the feeder.
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	if request.MonsterState ~= "FEEDING" then
		return "NOT_TRANSFORMED"
	end

	return feedable(request)
end

return FeedRules
