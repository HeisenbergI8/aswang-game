--!strict
--[[
	REVIEW — docs/BUILD-PLAN.md:178-192, the V02 chunk definition.
	Read for: the chunk's Tier / Runner / Deps / Done / Verify contract.

	This is a .luau file by naming convention only; the source is markdown.
]]

--[[
	THE CHUNK, quoted:

		V02 — The v2 vocabulary: Enums, Types, Config
		Tier Large · Runner robot · Deps V01

		Nothing works until the words exist. This chunk adds no behaviour.

		- Enums: ItemType, MonsterState, BodyKind, CamouflageForm. Keep the `:: Types.X` casts.
		- Types: ClientRoundSnapshot gains a carry slot and loses nothing. It still has no alive count
		  and no role field — Amendment A3's list of forbidden names is carried into v2 verbatim.
		- Config: the full v2 block from spec §6.5.

		Done   spec §6.5's Config block present with the comment for every number; enums cast;
		       analyze clean.
		Verify verify green; `lune run tests/config.test.luau` — which will FAIL until V11 writes the
		       six invariants, so this chunk's gate is analyze + lint only, stated explicitly so the
		       red is expected.
]]

--[[
	IMPORTANT THE Done AND Verify LINES CONTRADICT EACH OTHER, AND THE PLAN RESOLVES IT WITH EVIDENCE.

	"analyze clean" and "config.test will FAIL" cannot both describe the same edit here.

	  · The only V02-scale change that reds config.test is renaming Config.Salt.* to §6.5's
	    Items.Salt* names — the file indexes Config.Salt at :67, :75, :84, :99 and :105.
	  · That same rename reds `analyze`, because five live modules read the old keys and a missing
	    Config key is a hard analyzer error. Measured:
	        TypeError: Key 'SpawnCount' not found in table '{| CarryLimit: number |}'
	  · Measured separately: config.test PASSES today, 82 invariants, exit 0. So the red is not
	    pre-existing and not something V11 inherits — it would be caused BY V02.

	The plan takes the branch that keeps Done satisfiable: Items is canonical, Config.Salt's four
	renamed keys alias into it, analyze stays green and config.test stays green.

	QUESTION for the author: the Verify line should be corrected to "verify green, including
	test:unit". Raised in the plan's Follow Ups Q1 rather than edited here — CLAUDE.md's precedence
	rule says to report a stale document rather than plan around it silently.
]]

--[[
	NOTE "Tier Large · Runner robot" is the deliberate override recorded in CLAUDE.md: every V-chunk is
	Large tier by the author's decision, so the supervised loop can own all of them (`/build V02`).
	That is why a three-file vocabulary chunk gets an architect at all — the routing table would
	otherwise call this Medium and skip straight to implementation.

	NOTE "Deps V01" is satisfied: V01 is committed (25e9a16, "V01 — remove the task game, and arm the
	guard against its return") and the `ghosts?` scope rule it armed is live.

	IMPORTANT the chunk says "adds no behaviour" and the plan holds to it literally: no service, no
	controller, no remote, no producer for the new field. Three phases map to three files. If an
	implementer finds themselves opening a file under src/server/ or src/client/, the plan has been
	exceeded — stop and re-read Follow Ups Q2, which is where that decision lives.
]]
