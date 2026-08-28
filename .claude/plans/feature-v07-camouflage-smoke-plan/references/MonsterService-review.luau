--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (2173 lines)

	Read for V07. Excerpts only, with the lines an annotation is attached to. Ranges are cited so a
	reader can jump to the live code and see whether it has moved; this is a frozen snapshot.
]]

-- src/server/Services/MonsterService.luau:120-141
-- The V07 seam, added at V06 and connected to by nothing. This is where the camouflage refresh hangs.
MonsterService.FeedCompleted = Instance.new("BindableEvent")
-- IMPORTANT: fired from `completeFeed` and NOWHERE else. `endFeed` — which all six interruption paths
-- go through — fires neither this nor `HealFromFeed`. That is what makes §4.3's "interrupting a feed
-- is a real victory" a STRUCTURAL property: there is no code that could grant the refresh on an
-- interrupted feed, so nobody has to remember to withhold it. V07 must attach exactly one listener
-- and must NOT add a direct call inside `completeFeed` as a shortcut.
-- NOTE: it carries a Player and nothing else. No health, no victim, no charge count, no body. A
-- listener needing more is expected to take the UserId and ask the service.

-- src/server/Services/MonsterService.luau:169-230, 265-300
type MonsterState = {
	Applied: boolean, -- the look is physically on a character and needs undoing
	AppliedTo: Model?, -- IMPORTANT: the character the look was applied TO, not player.Character
	OriginalParts: { PartLook },
	Health: number,
	Feeding: boolean,
}
-- SERVER-ONLY, keyed by UserId, never replicated. Every field added since V05 has stayed off the wire.
-- IMPORTANT: V07 adds six fields here and none may become an attribute, a tag or a Humanoid property.
-- The `Health` comment's argument applies verbatim, and `HasBeenRevealed` is worse than Health: it is
-- true for exactly one player in the round, so one GetAttribute sweep would name the Aswang outright.
-- NOTE: `Health`'s reset rule is the one V07's flag copies — "survives a transform cycle, dies with
-- the round", reset ONLY by `onPhaseChanged`'s `table.clear(monsters)`. `revert()` must not clear it:
-- reverting does not un-see a reveal.

-- src/server/Services/MonsterService.luau:326-340
local function monsterStateOf(monster: MonsterState): Types.MonsterState
	if monster.Feeding and monster.Transformed then
		return Enums.MonsterState.Feeding
	end
	if monster.Transformed then
		return Enums.MonsterState.Transformed
	end
	return Enums.MonsterState.Normal
end
-- IMPORTANT: V07's CAMOUFLAGED branch must go ABOVE the Feeding one. A camouflaged Aswang is still
-- `Transformed` underneath, so checking Transformed first reports TRANSFORMED for a monster standing
-- in the barrio as a pig — `FeedRules` would then grant it a feed and `CamouflageRules` would never
-- see ALREADY_CAMOUFLAGED, leaking an ambient slot per hide.
-- NOTE: the header explicitly says "`CAMOUFLAGED` has no producer until V07". This is that chunk.
-- IMPORTANT: `Feeding AND Transformed`, never `Feeding` alone. V07 must copy that: written as
-- `if Camouflaged then`, a monster whose transform was reverted by an unforeseen path reports
-- CAMOUFLAGED forever and every "the form went away" backstop stops firing.

-- src/server/Services/MonsterService.luau:748-836
local function revert(player: Player)
	local monster = monsters[player.UserId] -- NOTE: READ, never `stateFor` — a stale timer firing for
	-- a departed player would re-insert their UserId and grow `monsters` unbounded inside one round.
	-- ... restores OriginalScales, BaseWalkSpeed, FeedBaseJumpPower, FeedBaseJumpHeight
	restoreLook(monster)
	clearEffects(monster)
end
-- IMPORTANT: this function restores CAPTURED state, never a default, and the header records why —
-- C04 restored every part to white Plastic at scale 1.0 and branded the ex-Aswang permanently,
-- map-wide, with every check green. Camouflage is a SECOND appearance change on the same character,
-- so it must reuse `captureLook`/`restoreLook` and must not invent a parallel path.
-- IMPORTANT for V07: `captureLook` must NOT run twice. If camouflage captures a character the
-- transform already captured, the MONSTER's colours become the "originals" and the eventual revert
-- brands the player. `Applied` is the existing flag to guard on.
-- NOTE: the JumpPower/JumpHeight restore was moved here at V06 specifically so a future caller
-- "cannot restore the speed and forget the jump". V07's exit path inherits that expectation.

-- src/server/Services/MonsterService.luau:1255-1275
local function completeFeed(player: Player)
	endFeed(player.UserId, nil)
	MonsterService.HealFromFeed(player.UserId)
	MonsterService.FeedCompleted:Fire(player) -- V07's half hangs here
	sendFeedUpdate(player, "FEED_OK")
end
-- NOTE: the ONLY caller of `HealFromFeed` and the ONLY firer of `FeedCompleted`. That coupling is
-- deliberate and is what stops the heal and the camouflage refresh coming apart.

-- src/server/Services/MonsterService.luau:2024-2047
function MonsterService.ApplySaltHit(player: Player)
	endFeed(player.UserId, "FEED_INTERRUPTED")
	revert(player)
	applyHealthEvent(player.UserId, "SALT")
	applyExposed(player)
end
-- IMPORTANT: THE ONLY ENTRY POINT FOR A SALT HIT. V05 removed the bare `ForceRevert` precisely so a
-- caller "cannot revert without damaging". V07 inherits that property for the reveal flag: setting
-- `HasBeenRevealed` here means there is no way to salt a monster without revealing it and no way to
-- reveal one without salting it. Its one caller is `ItemService.applyHit` (ItemService.luau:448-449),
-- and V08's item rework does not move that call.
-- IMPORTANT: V07 must add `exitCamouflage(player)` as the FIRST line, above `endFeed`. `revert`
-- restores from `OriginalParts`, which camouflage overwrote on top of; exiting first leaves the
-- character in the state every one of `revert`'s comments was written about.

-- src/server/Services/MonsterService.luau:1744-1812
local function onPhaseChanged(phase: Types.RoundPhase)
	-- ... clearCorpses on INTERMISSION/IDLE; early-return on ACTIVE
	for userId in monsters do
		local player = Players:GetPlayerByUserId(userId)
		endFeed(userId, "FEED_INTERRUPTED")
		if player ~= nil then
			revert(player)
		end
		clearExposed(userId)
	end
	table.clear(monsters)
end
-- IMPORTANT: V07's camouflage exit joins this loop, BEFORE the revert and BEFORE `table.clear`. The
-- `clearExposed` comment makes the exact argument that applies: `table.clear` on its own orphans the
-- thing the state was holding. Here what is orphaned is an ambient entity parked outside `workspace`
-- with nothing left that knows it exists — a permanently missing pig, silent and cumulative.
-- QUESTION: this loop cannot cover a player who has ALREADY LEFT — `onPlayerRemoving`
-- (MonsterService.luau:1898-1936) removes them from `monsters` first, and its own comment says it
-- calls `clearExposed` before nilling "for what nilling alone leaves behind". V07 must add the
-- camouflage exit there too, and that is the one edge case nothing else can cover.

-- src/server/Services/MonsterService.luau:2093-2130
-- The handler shape every new remote must copy.
Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
	if not AntiCheatService.Consume(player, "RequestTransform") then
		return
	end
	validateAndTransform(player)
end)
-- IMPORTANT: `check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|...)` within 1200
-- CHARACTERS of the `.OnServerEvent:Connect(`. It is a proximity tripwire by its own admission, so a
-- handler that IS limited 250 lines away fails the build. Consume first, inline, at the connect site.
-- NOTE: `RequestKill` next door adds `typeof(targetUserId) ~= "number"` because "a remote argument is
-- whatever the client sent". V07's two remotes take NO arguments, so neither needs that guard — which
-- is itself the stronger anti-cheat property.
-- IMPORTANT: the refusal verdict is never echoed to a non-Aswang. Handing a client `NOT_ASWANG` would
-- be a free role oracle for anyone willing to spam the remote. V07's handlers must return silently
-- for a player who is not the Aswang, and send a real verdict only to one who is.
