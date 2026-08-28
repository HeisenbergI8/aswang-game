--!strict
--[[
	REVIEW — src/shared/Config.luau (1345 lines)

	Read for the `Monster` block V07 extends and for the anti-cheat budget table it adds two entries
	to. Excerpts only.
]]

-- src/shared/Config.luau:235-260
Monster = {
	TransformTime = 1.2,
	RevertTime = 1.0,
	MaxTransformTime = 8,
	KillRange = 8,
	KillCooldown = 30, -- NOTE: "dead under v2.0 by intent, alive in code by count" — V06 did not
	-- retire it because three call sites and three Lune suites depend on it. It dies with a
	-- `balance(monster):` chunk of its own. V07 must not touch it either.
	TransformedSpeedMult = 1.25,
}
-- IMPORTANT: `KillRange = 8` is the number V07's `CamouflageWitnessRadius` is pinned above in
-- `tests/config.test.luau`. A monster that may hide from further than it may kill from has to break
-- contact first; the other way round it kills and vanishes before the victim's partner, standing at
-- kill range watching, has anything to report.

-- src/shared/Config.luau:262-294
	MaxHealth = 100,
	WeakenedThreshold = 25,
	ExposedGlowTransparencyFull = 0.75,
	ExposedGlowTransparencyWeakened = 0.25,
-- NOTE: the glow ramp is "the whole presentation of the health system", and §4.6 forbids any UI:
-- "a health value attached to a player is the reveal". V07 inherits that rule for the charge — no
-- meter, no counter, not even on the Aswang's own screen, because a stream capture is permanent.

-- src/shared/Config.luau:295-332
	FeedDuration = 5,
	FeedHeal = 25,
	FeedLeashStuds = 6,
-- IMPORTANT: the `FeedHeal` comment already names V07's half: "once the Aswang has been revealed,
-- restores its ability to camouflage (§4.3) — which is why interrupting a feed with salt is a real
-- victory rather than a nuisance: the monster loses both at once."
-- NOTE: `FeedLeashStuds = 6` is deliberately SMALLER than `KillRange = 8`, pinned in
-- `tests/config.test.luau`. The pattern V07 copies for its two new relationships.

-- src/shared/Config.luau:334-347
	--[[
		SMOKE (§4.3) — the Aswang's escape, and it belongs to the monster on purpose.
	]]
	SmokeDuration = 4,
	SmokeRadius = 18,
-- IMPORTANT: THESE TWO ALREADY EXIST. V07 must not re-add them and must not move them — the header
-- explains why they sit under `Monster` rather than under `Items` (an early v2 draft gave the smoke
-- to salt, so "the survivor who landed the counterplay was the one blinded by it").
-- NOTE: "SmokeRadius is a VISUAL and LOS radius, not a damage radius. Nothing takes damage from
-- smoke. Counted against §5's mobile particle budget by whoever builds the effect." That last clause
-- is V07 Step 6.5, and it is the step with no verify line.
-- QUESTION: neither a cooldown nor a charge count exists here, and §6.5's canonical Config block
-- names none. V07 invents `SmokeCooldown` and `SmokeCueRadius`; both are first guesses and both are
-- flagged in the plan's Follow Ups as V16 balance questions.

-- src/shared/Config.luau:1248-1310
Budgets = {
	RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
	RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
	RequestSearch = { Capacity = 4, RefillPerSecond = 0.3 },
	RequestCancelSearch = { Capacity = 6, RefillPerSecond = 0.5 },
	RequestClaimGroupReward = { Capacity = 2, RefillPerSecond = 0.05 },
}
-- NOTE: budgets are sized "from the mechanic rather than from a feeling", and the comments show the
-- arithmetic — `RequestSearch` at 0.3/s "pays for one start every ~3.3s, which is roughly twice the
-- fastest honest rate". V07's two entries carry the same working: the charge and the 45s cooldown are
-- the real limiters, so these budgets exist for the REFUSALS.
-- IMPORTANT: `AllowUnbudgetedRemote = false` — `AntiCheatService.Consume` FAILS CLOSED. A remote with
-- no entry here is refused entirely rather than left unlimited, so a missing V07 budget disables
-- camouflage rather than opening a firehose. That is the safe direction and it is also why the
-- omission would be diagnosed as "the feature does not work" rather than as a security hole.
-- NOTE: `RequestStartTrial`'s comment flags it as "the only remote in this game whose handler SPAWNS
-- AN NPC". V07's `RequestCamouflage` handler PARKS one and un-parks it — no spawn, by design — which
-- is worth stating in its own budget comment for the next person reading this table.

-- src/shared/Config.luau:1078-1079 and SkyController.luau:101-113
DawnAmbientRgb = { 74, 66, 62 },
-- NOTE: the ONLY existing uses of the word "Ambient" in this repo are Lighting properties. V07's new
-- `Config.Ambient` block is unrelated and the collision is only lexical — but it is worth a sentence
-- in the block's header, because `grep -rn Ambient src/` currently returns lighting and will not
-- after this chunk.
-- NOTE: `SkyController` is also the precedent for `-- config-ok:` waivers on genuinely non-tunable
-- numbers ("Color3 channels are 0-1, RGB triples are 0-255"). `AmbientService`'s `math.pi * 2` and
-- the feed tick's `task.wait(0.25)` are the same shape.
