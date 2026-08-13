--!strict
--[[
	SpookBudget — may this ghost spook right now? (§4.7, C16)

		(request) -> verdict

	§4.7: "Can trigger one spook per round (flicker a nearby light, rustle a bush) — no information,
	pure flavour, but it keeps them playing with the living."

	"ONE PER ROUND" IS THE WHOLE RULE and it is the reason this is a module rather than an `if`. C16's
	own acceptance criterion is *"second spook attempt refused"* — a human observation needing a running
	place, two attempts and somebody watching. As arithmetic it is a terminal test that runs in
	milliseconds, and the playtest stops being the only evidence.

	THE SPOOK CARRIES NO INFORMATION, AND THAT IS A CONSTRAINT ON THE CALLER, NOT ON THIS MODULE.
	Nothing here decides WHAT flickers or WHERE. If the effect were placed at the nearest light to the
	ghost, a living player would learn a dead player's position — and a dead player standing next to
	the Aswang is exactly the leak §4.7's last bullet is about. The server chooses uniformly at random
	within `Config.Ghost.SpookRangeStuds`, which is deliberately larger than both `Monster.KillRange`
	and `Tasks.PresenceRangeStuds` so that "a light flickered near me" narrows nothing.

	NO `script.Parent` REQUIRES. Both unions are re-declared; Luau unions are structural.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict = "OK" | "WRONG_PHASE" | "NOT_GHOST" | "NO_SPOOKS_LEFT"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Used: number,
	Allowance: number,
}

local SpookBudget = {}

--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT, the same world-then-player-then-count ordering
	`KillValidation` and `SaltCarry` use. A log full of NO_SPOOKS_LEFT is a UX finding — players
	pressing a button that is still on screen — and a log full of anything above it is a correctness
	finding.
]]
function SpookBudget.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	--[[
		AN ALLOWLIST OF GHOST, and the only allowlist in this repo that excludes ALIVE. A living player
		has no spook button, so reaching this value means either a stale button on someone a round
		ending just revived, or a compromised client. Both look identical from here, which is why C41
		reads the log rather than this function.
	]]
	if request.PlayerState ~= "GHOST" then
		return "NOT_GHOST"
	end

	--[[
		FAIL CLOSED ON THE ALLOWANCE, tested for positive-and-finite rather than for zero — the same
		asymmetry `pure/SaltCarry` documents. `math.huge` is the dangerous one: `Used < inf` is always
		true, so an infinite allowance does not raise the limit, it DELETES it, and §4.7's "one per
		round" becomes unlimited flickering with no symptom other than players finding it annoying.

		`tests/config.test.luau` pins `SpooksPerRound >= 1`, but this module is called with numbers
		rather than with Config, so it re-checks.
	]]
	if not (request.Allowance > 0 and request.Allowance < math.huge) then
		return "NO_SPOOKS_LEFT"
	end

	--[[
		`>=`, NOT `>`. With an allowance of 1, a ghost who has used one has `Used == Allowance` and must
		be refused; `>` would admit them and "one per round" would be two. This is the exact comparison
		C16's acceptance criterion exercises.

		A NaN `Used` is refused by the guard below rather than by this line, because `NaN >= 1` is false
		and would fall through to OK. The two guards are not symmetric and a reader would reasonably
		assume they were.
	]]
	if request.Used >= request.Allowance then
		return "NO_SPOOKS_LEFT"
	end

	if not (request.Used >= 0 and request.Used < math.huge) then
		return "NO_SPOOKS_LEFT"
	end

	return "OK"
end

return SpookBudget
