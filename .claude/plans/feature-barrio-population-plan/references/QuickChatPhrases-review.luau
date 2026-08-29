--!strict
--[[
	REVIEW — src/shared/pure/QuickChatPhrases.luau (185 lines)
	         and tests/quick-chat-phrases.test.luau

	READ THIS ONE FIRST IF YOU ARE CHECKING THE PLAN'S SCOPE DECISION. The brief said adding GOAT and
	CHICKEN means adding two phrases. That is not possible and it is also not what is missing.

	THE FINDING, IN THREE FACTS:
	  1. There is NO animal accusation phrase in the game. `ACCUSE` names a PLAYER.
	  2. The wheel is eight phrases in eight sectors, CLOSED, and the test hard-asserts the eight.
	  3. The shipped set is v1.3's. §4.5's v2.0 list is a different eight and nothing has done it.

	This plan therefore adds NO phrases and changes NO file in this review. The §4.5 rewrite is
	recommended as the next chunk.
]]

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/pure/QuickChatPhrases.luau:24-32 — the closed id union
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

export type QuickChatPhraseId =
	"SAW_TRANSFORM"
	| "BODY_HERE"
	| "FOLLOW_ME"
	| "ACCUSE"
	| "TASK_HERE"
	| "RUN"
	| "IM_ALONE"
	| "TRUST_ME"

-- The eight ids, mirrored in `src/shared/Types.luau:415-423`.
--
-- IMPORTANT: FOUR OF THESE ARE v1.3's AND THE SPEC HAS MOVED. `docs/MVP-SPEC.md:341` lists v2.0's
-- eight as: "I saw it transform!" · "It's the [animal]!" · "Body here!" · "Follow me" ·
-- "Searching — cover me" · "Run!" · "I'm alone" · "I have the buntot pagi". So v2.0 DROPS `ACCUSE` and
-- `TRUST_ME` and ADDS the animal phrase and the buntot-pagi phrase, and renames `TASK_HERE`.
--
-- NOTE: `TASK_HERE`'s own comment (:88-92) says V03 owns its rename and deliberately left the id
-- stale. So one of the four is already accounted for. The other three are unowned:
-- `docs/BUILD-PLAN.md:29` lists quick-chat plumbing under "survives untouched", and no V-chunk claims
-- the §4.5 vocabulary. This is genuinely unbuilt work, not work in flight.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/pure/QuickChatPhrases.luau:108-117 — ACCUSE, the only targeted phrase
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

	{
		-- THE ONLY PHRASE WITH A SERVER-RESOLVED TARGET. `{name}` is filled by the RECEIVER from
		-- `TargetUserId`, never by the sender.
		Id = "ACCUSE" :: QuickChatPhraseId,
		Text = "It's {name}!",
		Order = 4,
		NeedsTarget = true,
		Pings = false,
		DeadMay = false,
	},

-- IMPORTANT: this names a PLAYER, not an animal. §4.5 calls "It's the [animal]!" the thing without
-- which "camouflage is unbeatable" — and it does not exist. So camouflage currently has no naming
-- counterplay at all, for four forms; this plan raises it to six. **That is a real, accepted balance
-- regression for as long as the rewrite is deferred**, and it is why the rewrite is recommended next.
--
-- NOTE: THE RIGHT SHAPE IS ALREADY HERE, and it is why the fix is cheap when it comes. `ACCUSE`
-- resolves its target server-side by range and a 60° FOV cone (`Config.QuickChat.AccuseRangeStuds`,
-- `AccuseHalfAngleDegrees`) and puts a `TargetUserId` on the wire, never a string. An animal phrase is
-- the same machinery pointed at `workspace.AmbientLife` instead of at `Players`, carrying a form id.
--
-- NOTE: THAT MAKES IT ONE PHRASE, NOT SIX, AND ADDING FORMS THEN COSTS ZERO PHRASES FOREVER. The
-- entity names in `AmbientLife` already replicate, so naming one leaks nothing.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- tests/quick-chat-phrases.test.luau:36-42 — why per-animal phrases are impossible
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

check(
	"§4.5 ships exactly eight phrases",
	#QuickChatPhrases.All == 8,
	`got {#QuickChatPhrases.All}`
)
check("the wheel has one sector per phrase", QuickChatPhrases.Sectors == #QuickChatPhrases.All)

-- IMPORTANT: THIS IS THE STRUCTURAL REFUSAL. Eight phrases, eight sectors, one each — and
-- `sectorFor` divides a full turn by `SECTORS` so the geometry follows the count. Six per-animal
-- phrases would take six of the eight sectors and leave two for everything else, and the mobile
-- argument in `sectorFor`'s comment (a thumb only has to be accurate to ±22.5°) degrades with every
-- sector added.
--
-- So "two new animals means two new phrases" cannot be built. The brief's premise is corrected in the
-- plan's Follow Ups rather than worked around.
--
-- NOTE: 121 assertions over a closed set of eight. The `{name}` iff — a template carries `{name}` if
-- and only if the server resolves a target for it — is the assertion an animal phrase would have to
-- satisfy too, with `{animal}` and a form id.
