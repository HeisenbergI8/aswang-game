--!strict
--[[
	tests/token-bucket.test.luau

	The rate limiter's arithmetic, including the input that will actually break it.

	C02 names four scenarios — steady state, burst, refill, clock jump backwards. Three of them are the
	happy path in different clothes. The fourth is the one worth writing a test for, and it is written
	here in the form that a naive implementation FAILS: not "does a backwards jump grant free tokens"
	(clamping elapsed to zero passes that) but "does the bucket still refill AFTERWARDS".
]]

local TokenBucket = require("../src/shared/pure/TokenBucket")

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local function approx(a: number, b: number): boolean
	return math.abs(a - b) < 0.0001
end

--------------------------------------------------------------------------------
-- Steady state — a legitimate player at the sustained rate is never refused
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 0)
	local refused = 0

	-- One request per second against a 1/s refill, for twice as long as the bucket is deep. A limiter
	-- that leaks capacity — refunding less than it charges, or re-anchoring wrongly — fails here and
	-- nowhere else, because the deficit only becomes visible after it accumulates.
	for second = 1, 20 do
		local allowed, updated = TokenBucket.consume(bucket, second, 1)

		bucket = updated

		if not allowed then
			refused += 1
		end
	end

	check("steady state at the refill rate is never refused", refused == 0, `{refused} refused`)
	check(
		"steady state does not drift the bucket",
		approx(bucket.Tokens, 4),
		`tokens={bucket.Tokens}`
	)
end

--------------------------------------------------------------------------------
-- Burst — capacity is the burst, and the next one is refused
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 0)
	local allowedCount = 0

	-- Ten requests in the SAME instant. Capacity is 5, so exactly 5 get through.
	for _ = 1, 10 do
		local allowed, updated = TokenBucket.consume(bucket, 0, 1)

		bucket = updated

		if allowed then
			allowedCount += 1
		end
	end

	check("a burst is capped at capacity", allowedCount == 5, `{allowedCount} allowed`)
	check("an exhausted bucket holds no tokens", approx(bucket.Tokens, 0), `tokens={bucket.Tokens}`)
end

--------------------------------------------------------------------------------
-- Refill — and the ceiling, which is the half that is usually missing
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 0)

	for _ = 1, 5 do
		local _, updated = TokenBucket.consume(bucket, 0, 1)
		bucket = updated
	end

	-- 2.5 seconds at 1/s buys two whole requests and not a third.
	local first, afterFirst = TokenBucket.consume(bucket, 2.5, 1)
	local second, afterSecond = TokenBucket.consume(afterFirst, 2.5, 1)
	local third = TokenBucket.consume(afterSecond, 2.5, 1)

	check("refill grants the first whole token", first)
	check("refill grants the second whole token", second)
	check("refill does not grant a partial token", not third)

	-- Idle for far longer than it takes to fill. Without the min() a long-idle player banks an
	-- unbounded burst, which is the exact shape an exploiter waits for.
	local _, idle = TokenBucket.consume(TokenBucket.new(5, 1, 0), 1000, 1)

	check("an idle bucket never exceeds capacity", approx(idle.Tokens, 4), `tokens={idle.Tokens}`)
end

--------------------------------------------------------------------------------
-- The clock jumps BACKWARDS
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 100)

	for _ = 1, 5 do
		local _, updated = TokenBucket.consume(bucket, 100, 1)
		bucket = updated
	end

	-- The clock is now 60 seconds EARLIER than the last refill.
	local allowed, jumped = TokenBucket.consume(bucket, 40, 1)

	check("a backwards jump grants no free tokens", not allowed)
	check(
		"a backwards jump never drives the bucket negative",
		jumped.Tokens >= 0,
		`tokens={jumped.Tokens}`
	)

	-- THE ASSERTION THAT MATTERS. A limiter that clamps `elapsed` but leaves LastRefillAt in the
	-- future passes both checks above and then refuses this one for a further 60 seconds.
	check(
		"the bucket re-anchors, so it refills normally after the jump",
		jumped.LastRefillAt == 40,
		`LastRefillAt={jumped.LastRefillAt}`
	)

	local recovered = TokenBucket.consume(jumped, 45, 1)

	check("five seconds after the jump, requests flow again", recovered)
end

--------------------------------------------------------------------------------
-- Degenerate input, and purity
--------------------------------------------------------------------------------

do
	-- A cost above capacity can never be paid. It must REFUSE, not error: the limiter is the thing
	-- that has to keep working when the configuration is wrong.
	local allowed, updated = TokenBucket.consume(TokenBucket.new(2, 1, 0), 1000, 5)

	check("a cost above capacity is refused rather than erroring", not allowed)
	check(
		"a refused oversized cost still leaves a full bucket",
		approx(updated.Tokens, 2),
		`tokens={updated.Tokens}`
	)

	-- Purity: the input table is untouched, so a caller that discards the result changes nothing.
	local original = TokenBucket.new(5, 1, 0)
	local before = original.Tokens

	TokenBucket.consume(original, 0, 1)

	check(
		"consume does not mutate its input",
		original.Tokens == before,
		`tokens={original.Tokens}`
	)
end

if failures > 0 then
	error(`{failures} token-bucket failure(s)`, 0)
end

print("  PASS  token-bucket: steady state, burst, refill, backwards clock, degenerate cost, purity")
