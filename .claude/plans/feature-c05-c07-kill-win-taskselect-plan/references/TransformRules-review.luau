--!strict
-- Review of src/shared/pure/TransformRules.luau — the template Phase 3's KillValidation copies.
-- Excerpts only.

-- src/shared/pure/TransformRules.luau:6-11
--[[
	§4.3 lists the transform's preconditions in prose. Every one of them is a comparison over numbers,
	booleans and two string enums ... (C05's kill validation is the opposite case: the raycast is
	irreducibly Roblox, which is why `pure/KillValidation.luau` will be everything EXCEPT the raycast.)
]]
-- IMPORTANT: this file already predicted C05's split and named the module. Phase 3 is delivering
-- exactly what this header promised, which is why no new pattern justification is needed for it.

-- src/shared/pure/TransformRules.luau:13-18
--[[
	THIS ONE STAYS IN src/shared/pure/, unlike RoleDraw ... A client can require and call this. It
	learns nothing: every input is either a value that client already holds (its own role, the phase,
	its own state) or a Config number that already replicates ... Logic is not secret; inputs and seeds
	are.
]]
-- IMPORTANT: the test KillValidation must pass to live in src/shared/. It does: positions are readable
-- off the workspace, Range and Cooldown are replicated Config values, and the role booleans are facts
-- the calling client already holds about itself. TaskSelection passes it too, but only because its RNG
-- is injected — a `seed` parameter would fail this test.

-- src/shared/pure/TransformRules.luau:25-27
--[[
	NO `script.Parent` REQUIRES. The three enums are re-declared; Luau literal unions are structural,
	so these and their Types.luau counterparts are the same types.
]]
export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
-- NOTE: copied verbatim into KillValidation, WinConditions and PlayerBody. The cost of the duplication
-- is keeping the lists in step; the benefit is that Lune can run all four from a terminal.

-- src/shared/pure/TransformRules.luau:52-59
--[[
	The order of these checks is FIXED, and it is part of the contract rather than an implementation
	detail: it decides which reason a log line carries when more than one applies.

	World-level facts first (phase, then liveness), then facts about this player (role), then facts
	about this player's monster state (already transformed, cooldown).
]]
-- IMPORTANT: KillValidation extends this ordering with a fourth tier — facts about the TARGET — and
-- puts geometry last. The reasoning in the plan: OUT_OF_RANGE is the only refusal an honest player hits
-- routinely, so a log full of it is a UX finding and a log full of anything above it is a security one.

-- src/shared/pure/TransformRules.luau:60-78
function TransformRules.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	--[[
		AN ALLOWLIST, NEVER A DENYLIST. `PlayerState ~= "SPECTATOR"` would read identically today and
		would admit LOBBY and GHOST — and C15 makes GHOST real, at which point a dead player transforms.
		`PlayerState` has four values and exactly one of them may act.

		This is C04's carried-over warning from C01, and Step 7.2 is where the test proves all four.
	]]
	if request.PlayerState ~= "ALIVE" then
		return "NOT_ALIVE"
	end
	-- IMPORTANT: C04 delivered THIS half of the warning — the rule — and deferred the body. Phase 1 of
	-- this plan is the other half. Reading only this file makes the containment look done.

-- src/shared/pure/TransformRules.luau:84-98
	--[[
		THE COOLDOWN RUNS FROM REVERT, NOT FROM THE TRANSFORM (§4.3 step 5).
		... `tests/config.test.luau` already pins `KillCooldown > TransformTime + RevertTime`.
		A nil LastRevertedAt means this is the round's first transform, which is never on cooldown.
	]]
	local lastRevertedAt = request.LastRevertedAt

	if lastRevertedAt ~= nil and request.Now - lastRevertedAt < request.Cooldown then
		return "ON_COOLDOWN"
	end
	-- IMPORTANT: copied verbatim into KillValidation, including the nil case. Because the transform is
	-- ALREADY gated on this, the kill's copy is redundant today — kept because C05 names it, because it
	-- costs one comparison, and because it is the only guard left if anything else ever grants the form.

	return "OK"
end
