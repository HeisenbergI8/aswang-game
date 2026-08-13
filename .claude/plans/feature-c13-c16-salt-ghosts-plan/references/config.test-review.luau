--!strict
--[[
	REVIEW — tests/config.test.luau (348 lines)

	Excerpted ranges:
	  · tests/config.test.luau:69-90    the two salt relations and the ghost one, all pre-existing
	  · tests/config.test.luau:325-330  the ghost-versus-full-contribution relation
	  · tests/config.test.luau:92-98    the cycle check, and the `check` helper's shape

	Read because the brief said not to break the existing relations and to add new ones if C13–C16
	introduce any. It does — six of them, in Step 1.2.
]]

-- tests/config.test.luau:69-74
-- Spec §4.6: salt is thrown from outside kill range, or it is not counterplay — it is a suicide button.
check(
	"salt reaches further than the Aswang kills",
	Config.Salt.ThrowRange > Config.Monster.KillRange,
	`ThrowRange={Config.Salt.ThrowRange}, KillRange={Config.Monster.KillRange}`
)
-- IMPORTANT UNTOUCHED BY THIS PLAN. `ThrowRange` stays 25 and `KillRange` stays 8. Step 3.2 asserts the
--      same relation from the other side — a target at 20 studs is inside salt's reach and outside the
--      Aswang's — so the config relation and the hit rule now agree in two files.

-- tests/config.test.luau:76-82
-- Spec §4.6: the reveal must outlast the stun, or the Aswang is revealed only while it cannot move —
-- information nobody can act on.
check(
	"the salt reveal outlasts the stun",
	Config.Salt.RevealDuration > Config.Salt.StunDuration,
	`RevealDuration={Config.Salt.RevealDuration}, StunDuration={Config.Salt.StunDuration}`
)
-- IMPORTANT UNTOUCHED, AND IT IS THE RELATION PHASE 4's DESIGN RESTS ON. The six seconds between the stun
--      lifting (4s) and the glow fading (10s) are the whole of what salt buys: a reverted, human-looking
--      Aswang that everybody can still see. If these ever cross, Step 4.2's Highlight becomes decoration
--      on a stationary target and §4.6's counterplay stops existing.
-- NOTE It also shapes Step 4.1's ordering hazard: the stun ends first, so the captured WalkSpeed is
--      restored while the glow is still on. Whether that speed should be the transformed one is Follow
--      Up 4.

-- tests/config.test.luau:84-90
-- Spec §4.7: ghosts contribute at reduced speed. At 0 they are spectators, which is the retention leak
-- the ghost system exists to close; at 1 dying is free.
check(
	"ghosts contribute, but less than the living",
	Config.Ghost.TaskContributionMult > 0 and Config.Ghost.TaskContributionMult < 1,
	`TaskContributionMult={Config.Ghost.TaskContributionMult}`
)
-- NOTE Step 1.2 inserts the six new relations directly after this, so the salt block and the ghost block
--      each stay contiguous rather than interleaving.
-- NOTE Step 8.2 asserts the FUNCTION honours this range, which is a different claim: this pins the
--      number, that pins `TaskWeight.forPlayer` returning it. Both are needed — a correct constant read
--      by nothing is the failure `check:config` cannot see.

-- tests/config.test.luau:325-330
check(
	"ghosts contribute less than a full participant",
	Config.Ghost.TaskContributionMult < Config.Tasks.FullContributionWeight,
	`ghost={Config.Ghost.TaskContributionMult}, full={Config.Tasks.FullContributionWeight}, `
)
-- IMPORTANT THE PRE-EXISTING HALF OF THE TWO-PERSON PROPERTY. It pins one ghost below one full
--      contributor; Step 8.2 adds the pair — TWO ghosts below TWO full contributors — which is the claim
--      `Config.luau:180-183` actually makes and which nothing currently checks. At a ghostMult of 0.5
--      this relation still passes and two ghosts would open a two-person task.

-- tests/config.test.luau:16-23 (the helper, paraphrased from the file's shape)
local function check(label: string, ok: boolean, detail: string?)
-- NOTE `(label, condition, detail)` with the detail as an interpolated string naming both operands. Every
--      new check in Step 1.2 follows it, because the detail string is what makes a red run actionable —
--      "salt is scarcer than the roster" tells you what broke, `SpawnCount=8, MaxPlayers=8` tells you why.
-- IMPORTANT This file `require`s `Config` directly, which is why Step 8.2 may do the same from
--      `tests/task-weight.test.luau`. Lune resolves by file path and `Config.luau` is a plain table with
--      no Roblox datatypes precisely so it can. What is forbidden is a PURE MODULE requiring Config; a
--      test may.
