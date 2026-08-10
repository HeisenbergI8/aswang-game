--!strict
--[[
	TokenBucket — the rate limiter's arithmetic, as a pure function.

		(bucket, now, cost) -> (allowed, newBucket)

	WHY THIS IS A MODULE AND NOT THREE LINES INSIDE AntiCheatService
	----------------------------------------------------------------
	It is four lines of arithmetic with one genuinely hostile input: `now`. A rate limiter is the piece
	of infrastructure that must keep working while everything around it misbehaves, and its failure mode
	is silent in both directions — too loose and it refuses nothing, too tight and it refuses a real
	player on a bad connection while looking exactly like lag. Neither shows up in Studio.

	Pulled out here, `tests/token-bucket.test.luau` walks steady state, burst, refill and a clock jump
	backwards in milliseconds. Left inline, "does the limiter refill correctly after the clock moves
	backwards" is a question nobody can answer without waiting for it to happen on a live server.

	IT IS SAFE THAT THIS FILE REPLICATES. `src/shared` maps wholesale into ReplicatedStorage, so any
	client can require AND call this (docs/BUILD-PLAN.md §12). It publishes nothing:
	`Config.AntiCheat.Budgets` is itself replicated, so the numbers were already public, and knowing the
	algorithm does not let a client spend tokens it does not have — the buckets live on the server. Only
	a module whose INPUTS or OUTPUT are secret belongs in `src/server/pure/`; see RoleDraw.

	NO `script.Parent` REQUIRES — the rule for everything under `pure/` (tests/README.md). The bucket
	type is therefore re-declared here rather than required from Types; Luau records are structural, so
	this type and `Types.TokenBucketState` are the same type.
]]

export type Bucket = {
	Tokens: number,
	LastRefillAt: number,
	Capacity: number,
	RefillPerSecond: number,
}

local TokenBucket = {}

-- A full bucket. Starting full rather than empty is deliberate: a player's first action after joining
-- is legitimate, and a limiter that refuses it teaches them the game is broken.
function TokenBucket.new(capacity: number, refillPerSecond: number, now: number): Bucket
	return {
		Tokens = capacity,
		LastRefillAt = now,
		Capacity = capacity,
		RefillPerSecond = refillPerSecond,
	}
end

--[[
	Refill for the elapsed time, then spend if there is enough.

	Returns a NEW bucket every time, including on refusal — the refusal still refilled, and a caller
	that discards the returned bucket on `false` would freeze the player's tokens at whatever they held
	when they were first refused. That is the shape of bug this signature exists to make obvious: there
	is no in-place mutation to forget to save.

	THE CLOCK MOVING BACKWARDS
	--------------------------
	`now` comes from os.clock(), which this repo already uses for every round timer. It is not
	guaranteed monotonic, and the failure is asymmetric:

	  · Left unhandled, `elapsed` goes negative, tokens go DOWN on a refill, and a large enough jump
	    drives the bucket negative — the player is refused until real time makes up the difference.
	  · Clamping `elapsed` to zero but LEAVING `LastRefillAt` in the future is the subtler version of
	    the same bug: every subsequent call also computes a negative elapsed, so the bucket does not
	    refill at all until the clock catches up. A 60-second backwards jump mutes the remote for 60
	    seconds.

	So it clamps AND RE-ANCHORS: `LastRefillAt` is set to `now` unconditionally. A backwards jump costs
	the player the refill they had accrued and nothing more. `tests/token-bucket.test.luau` pins the
	re-anchoring specifically, because the clamp alone passes a naive test.
]]
function TokenBucket.consume(bucket: Bucket, now: number, cost: number): (boolean, Bucket)
	local elapsed = now - bucket.LastRefillAt

	if elapsed < 0 then
		elapsed = 0
	end

	local tokens = math.min(bucket.Capacity, bucket.Tokens + elapsed * bucket.RefillPerSecond)
	local allowed = tokens >= cost

	return allowed,
		{
			Tokens = if allowed then tokens - cost else tokens,
			LastRefillAt = now,
			Capacity = bucket.Capacity,
			RefillPerSecond = bucket.RefillPerSecond,
		}
end

return TokenBucket
