--!strict
--[[
	TimingWindow — where is the bar, and did that stop land in the green? (§4.4, C09)

		phaseAt(elapsed, period)          -> 0..1 through one sweep
		positionFromPhase(phase)          -> 0..1 across the visible track
		positionAt(elapsed, period)       -> the two composed
		effectiveHalfWidth(request)       -> the zone, widened by the latency allowance
		isHit(request)                    -> boolean

	THE SERVER OWNS THE BAR AND THIS MODULE IS WHY THAT COSTS NOTHING TO SAY.

	C09's brief: "the client renders the bar; the SERVER owns the bar's position and decides the hit.
	A client-decided timing minigame is a free task for any exploiter." The shape that delivers it is
	that `elapsed` is the only input describing time, and TaskService computes it as
	`os.clock() - task.BarStartAt` at the instant a request lands. No client timestamp, no client
	position, no client-reported outcome reaches here — there is no parameter one could arrive in.

	PHASE AND POSITION ARE DIFFERENT THINGS AND THE WIRE CARRIES THE PHASE.

	`phase` runs 0..1 once per sweep and is monotonic; `position` is the triangle fold of it and is
	what a player sees. The bar passes every position TWICE per sweep, so a position on its own does
	not say where the bar is going — it would need a direction flag beside it, a second field that can
	disagree with the first. Types.TimingBarPayload carries `Phase` for exactly this reason.

	THE GRACE IS SYMMETRIC AND THAT IS A DELIBERATE SIMPLIFICATION WITH A NAMED COST.

	The player pressed; the request travelled; the server evaluates a bar that has moved on. The
	error is therefore one-directional — the true press was always BEHIND the evaluated position, by
	the latency, in the direction of travel. A correct allowance would widen the window only backwards
	along that direction.

	This widens it both ways, which additionally accepts a press that was genuinely early by up to the
	grace. The cost is a slightly more generous zone, bounded by `tests/config.test.luau` pinning the
	grace smaller than the half-width it widens. The benefit is that the rule stays a function of
	position alone, so `tests/timing-window.test.luau` can enumerate it. Directional grace needs the
	sweep direction as an input and doubles the grid; it is in the plan's Follow Ups.

	NO `script.Parent` REQUIRES, no Roblox datatypes, and every tunable arrives as a PARAMETER rather
	than being read from Config — the same rule as every other pure module here, and the reason
	`check:config` (which governs `src/server/`, this directory included) has nothing to flag.
]]

export type Request = {
	-- SERVER seconds since this task's bar started. Never a client-supplied value.
	Elapsed: number,
	Period: number,
	-- Both in BAR UNITS, 0..1 across the visible track.
	GreenCenter: number,
	GreenHalfWidth: number,
	-- In SECONDS. Converted to bar units here, using the sweep speed, and nowhere else.
	GraceSeconds: number,
}

local TimingWindow = {}

--[[
	A NON-POSITIVE PERIOD RETURNS A STOPPED BAR RATHER THAN ERRORING.

	It cannot arrive through Config — `tests/config.test.luau` pins `TimingBarPeriod > 0` as part of
	the grace invariant — and "cannot happen" is precisely how a nan reaches a client and renders a
	bar that never moves again. `TaskProgress.tick` carries the same guard for the same reason.

	Lua's `%` with a positive divisor already returns a value in [0, period), including for a negative
	`elapsed`, so there is no second branch to write here.
]]
function TimingWindow.phaseAt(elapsed: number, period: number): number
	if period <= 0 then
		return 0
	end

	return (elapsed % period) / period
end

-- The triangle fold: phase 0 -> 0, 0.5 -> 1, 1 -> 0. `% 1` because the CLIENT extrapolates a phase
-- forward from the last one it was sent and will hand this values well above 1.
function TimingWindow.positionFromPhase(phase: number): number
	local wrapped = phase % 1

	return if wrapped <= 0.5 then wrapped * 2 else 2 - wrapped * 2
end

function TimingWindow.positionAt(elapsed: number, period: number): number
	return TimingWindow.positionFromPhase(TimingWindow.phaseAt(elapsed, period))
end

--[[
	The zone the server will actually accept, in bar units.

	The conversion is the whole content: the bar crosses the 0..1 track twice per period, so it moves
	at `2 / Period` bar units per second and a grace of `g` seconds is worth `g * 2 / Period` bar
	units. `tests/config.test.luau` restates this arithmetic against Config's own numbers, so lowering
	the period at M12 cannot silently widen the window.

	`math.max(0, ...)` because a negative grace would NARROW the zone, which is a knob nobody meant to
	build and which would present as "the timing task got hard after a Config edit".
]]
function TimingWindow.effectiveHalfWidth(request: Request): number
	if request.Period <= 0 then
		return request.GreenHalfWidth
	end

	return request.GreenHalfWidth + math.max(0, request.GraceSeconds) * (2 / request.Period)
end

function TimingWindow.isHit(request: Request): boolean
	local position = TimingWindow.positionAt(request.Elapsed, request.Period)

	return math.abs(position - request.GreenCenter) <= TimingWindow.effectiveHalfWidth(request)
end

return TimingWindow
