--!strict
--[[
	REVIEW — docs/BUILD-PLAN.md, chunks C02/C03/C04 and their warning blocks, plus §12's pure-module
	table and the C05 entry this plan hands off to.

	The Done and Verify lines are quoted verbatim INSIDE the plan document, as phase gates. This review
	records the warning blocks and the two places the chunks' own text drove a decision.
]]

--[[
	C02 — Tier Medium, Deps C01, 🔒. The ordering argument, verbatim, and the reason it is Phase 1–3:

		"Do this before any other remote handler exists. `check:ratelimit` fails any `OnServerEvent` that
		 doesn't consult `AntiCheatService`, so building it now means every later chunk is born compliant
		 instead of retrofitted. It is also the cheapest chunk in the plan that stays load-bearing to
		 launch."

	NOTE the four deliverables map 1:1 onto Phases 1–3: pure/TokenBucket, Consume over per-player
	per-remote buckets, budgets in a new Config.AntiCheat, log-only rejection.

	NOTE a discrepancy worth recording: C02's body says kicking "comes at C47" while its bullet and the
	rest of the document say C41 (Anti-cheat sweep), and there is no C47 — the plan has 45 chunks. C41
	is plainly meant. This plan says C41 throughout.
]]

--[[
	C03 — Tier Large, Deps C02, 🔒, plan-backed. THE WARNING BLOCK, which is the reason this plan
	exists in this shape. Verbatim:

		"`src/shared/pure/` SHIPS ITS SOURCE TO EVERY CLIENT. `default.project.json` maps `src/shared`
		 wholesale into `ReplicatedStorage`, so `RoleDraw.luau` is readable by any exploiter. That is
		 fine — a published algorithm is not a leak. A reproducible one is. Two rules follow, and they
		 are the whole security of this chunk:

		  - Seed the draw from server-only entropy. If the seed is derivable from anything a client can
		    observe — round number, player list, a timestamp — an exploiter replays the draw locally and
		    knows the Aswang *before the round starts*, with no remote to intercept and nothing for
		    `check:secrecy` to see.
		  - The anti-repeat history must never replicate — not because it is secret (every past round's
		    Aswang was already revealed to everyone by `RoundEnded`, per §4.8) but because it is a draw
		    input. Algorithm + inputs + seed = this round's assignment, and every input the client
		    already holds shrinks the search space for the seed it doesn't.

		 Concretely: `Random.new()` with no argument is fine. `Random.new(state.RoundNumber)` and
		 `Random.new(os.time())` are fatal — both are client-observable.

		 If either is awkward, put the module in `src/server/pure/` and point the test at that path
		 instead. Testability is the reason `pure/` exists; `Shared` is not."

	IMPORTANT — that last paragraph is EXPLICIT AUTHORISATION for the plan's §1.1 decision. The plan
	takes it not because either rule is awkward but because both rules stay enforced AND the class of
	failure is removed structurally. Both rules are implemented regardless.

	IMPORTANT — the gate: "exploit-auditor is mandatory on this chunk — if it finds one leak here, the
	chunk is not done regardless of what the tests say." §12 lists C03 as one of only four chunks where
	its verdict GATES the chunk (with C12, C15, C41).
]]

--[[
	C04 — Tier Medium, Deps C03, 🔒. Verbatim on why the broadcast is correct:

		"The transform is public by design — replicating it is correct, and it is the only thing in this
		 game that legitimately reveals the Aswang."

	And "No custom mesh (§4.3 — this is why the mechanic is cheap)."

	THE CARRIED-OVER WARNING, which this plan only half-delivers and says so:

		"Carried over from C01 — SPECTATOR is bookkeeping with nothing behind it. C01 marks a mid-round
		 joiner SPECTATOR and excludes them from the alive count. It does not give them a spectator's
		 *body*: they spawn normally, walk the Barrio, and collide with everything. Harmless until this
		 chunk, at which point an alt account joins mid-round and watches the transform from ten studs
		 away while being uncounted and — once C05 validates 'both alive' — unkillable.

		 Add the containment half here, before the kill exists: no character for SPECTATOR, or an
		 observer camera and no collision. Gate on `RoundService.GetPlayerState(player) ==
		 Enums.PlayerState.Alive` — an allowlist, never `~= SPECTATOR`. PlayerState has four values, so a
		 denylist also admits LOBBY and GHOST; C15 makes GHOST real and a ghost must not be killable.

		 Verify the premise in Studio before building the fix. What is established is that nothing in
		 `src/` prevents a spectator spawning — no `CharacterAutoLoads`, `LoadCharacter` or teleport logic
		 exists anywhere in the tree. The place file is gitignored, so a `SpawnLocation` or a property set
		 in Studio could already handle this and no check in the repo would see it."

	IMPORTANT — the allowlist half IS delivered (Steps 6.1/6.3/7.2, proven over all four PlayerStates).
	The BODY half is NOT, because the warning itself says to verify the premise in Studio first and this
	plan does not guess about Roblox behaviour. Recorded as the plan's one High-severity deferred issue,
	with the ordering the warning implies: before C05, not before C04.

	NOTE C04's Verify is the only one in these three chunks that no command can satisfy: "playtester:
	two clients in Studio, one transforms, screenshot from the *other* client's camera showing the
	silhouette. That screenshot is the artifact." Step 7.5 carries no Verify line for exactly this reason.
]]

--[[
	§12 — the pure-module table and the warning under it, verbatim:

		"Everything in `src/shared/pure/` is requirable and callable by any client — `src/shared` maps
		 wholesale into `ReplicatedStorage`, so a LocalScript can `require()` the module and run it.
		 (Callable, not merely readable: reading `.Source` needs plugin security, and assuming that
		 protects you is the mistake.) Harmless for six of these eight, and harmless for a reason worth
		 knowing — `Config.luau` is itself replicated, so `KillValidation` and `TokenBucket` publish
		 nothing that `Config.Monster.KillRange` already hands over. Logic is not secret. Inputs and
		 seeds are."

	IMPORTANT this is the sentence the plan's §1.1 rule is derived from, and it is why TokenBucket and
	TransformRules stay in shared while RoleDraw does not. It also pre-flags C07's TaskSelection: "a
	client-derivable seed is a pacing advantage — an exploiter who knows which 5 of 12 spawn can
	pre-position." Left as a Follow Up rather than decided here.

	NOTE the table lists `pure/RoleDraw.luau` under C03 with test `tests/role-draw.test.luau`. The test
	path is unchanged by the plan's decision; only the module path moves.
]]

--[[
	C05 — read only to know what this plan must leave in place, not to build:
	  · `RequestKill(targetUserId)` — the first handler that validates a CLIENT-SUPPLIED value
	  · `pure/KillValidation.luau` — "everything except the raycast, which needs the DataModel"
	  · "Kill cooldown starts from *revert*, not from the kill."  <- MonsterState.LastRevertedAt exists
	    for this, and is written by Phase 7.
]]
