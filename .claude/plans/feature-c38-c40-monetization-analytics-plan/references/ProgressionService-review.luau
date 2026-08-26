--!strict
--[[
	REVIEW — src/server/Services/ProgressionService.luau:60-93, :317-340, :344-372, :374-400

	The profile API C38 builds on. Two things changed here recently and both matter to this plan:
	the schema is now v2, and there are two new BindableEvents.
]]

-- src/server/Services/ProgressionService.luau:60-72
--[[
	FIRED WHEN A PLAYER'S PROFILE IS LOADED AND READABLE (C35), with the value of `FirstSeenUTC` from
	BEFORE this session stamped it.
]]
ProgressionService.ProfileLoaded = Instance.new("BindableEvent")
-- IMPORTANT: this is EXACTLY what C40's funnel step 4 ("returned on day 2") needs, and the plan uses
--            it rather than racing `Players.PlayerAdded` against session start.
--
--            The second argument is the whole point. `startSession` stamps `FirstSeenUTC` for anyone
--            who has none, so a subscriber reading the LIVE profile always sees "today" and could
--            never tell a returning player from a new one. `firstSeenBefore` is the pre-stamp value.
--
-- NOTE: not fired at all when the load failed, so a subscriber cannot award on a DataStore outage.
-- NOTE: fired inside a `task.spawn` (:363-368) because subscribers yield on badge web calls.

-- src/server/Services/ProgressionService.luau:75-93
ProgressionService.StatChanged = Instance.new("BindableEvent")
-- NOTE: `(player, statName)`, fired after a stat actually moved. Its own comment rejects the shape
--       C40 might otherwise reach for: "Two services listening to one event and depending on which
--       runs first is the shape of bug that only appears once the service list is reordered."
--       C40 does not currently need this one, but it is the precedent for how a per-player hook is
--       done in this repo — a BindableEvent off the owning service, not a second PhaseChanged
--       subscriber.
-- IMPORTANT: "IT CARRIES NO ROLE AND MUST NOT. `AswangRounds` is a stat NAME, not a role." An
--            analytics subscriber to this must not turn the stat name back into a role claim.

-- src/server/Services/ProgressionService.luau:317-323
local function saveNow(userId: number)
	local profile = sessions[userId]

	if profile ~= nil and profile:IsActive() then
		profile:Save()
	end
end
-- IMPORTANT: this returns BEFORE anything is durable — see ProfileStore-review.luau. It is correct
--            for an XP award and insufficient for a receipt, which is why Phase 2 adds a separate
--            yielding path rather than reusing this.
-- NOTE: its header defines "meaningful change" as "after a change a player would be angry to lose",
--       and explicitly names a cosmetic purchase as one. A gamepass CACHE STAMP is not one, which
--       is why `SetGamepassChecked` in Phase 2 deliberately omits the save.

-- src/server/Services/ProgressionService.luau:344-358 (GetProfile's header)
-- IMPORTANT: "READ, AND ONLY READ. Returns the LIVE table" … "`local p = GetProfile(player);
--            p.Coins += price` is the natural line for C34 to write. It compiles, it runs, and it
--            silently writes into a profile this server has latched read-only."
--
--            This is why C38's grant is a new guarded write path INSIDE this module rather than
--            arithmetic in MonetizationService. The same trap applies to the gamepass stamp, which
--            is why the plan adds `SetGamepassChecked` instead of writing `Purchases` directly.

-- src/server/Services/ProgressionService.luau:365-372
function ProgressionService.IsReadOnly(player: Player): boolean
	return readOnly[player.UserId] == true
end
-- IMPORTANT: its header states the C38 contract directly — "C33/C34/C35 should refuse a purchase or
--            a claim rather than take a payment that will never be saved — a silent no-op is worse
--            here than a visible refusal."
--
--            For a RECEIPT the refusal has a specific shape: NotProcessedYet, not PurchaseGranted.
--            Roblox re-delivers, and a later server grants it. Answering PurchaseGranted here would
--            take the money and grant nothing, permanently.

-- src/server/Services/ProgressionService.luau:398-415 (Award's finite guard)
-- NOTE: `x >= 0 and x < math.huge` rejects NaN, negatives AND infinity — the case a `~= itself`
--       test misses. Reused verbatim by `ApplyReceipt` and `SetGamepassChecked` in Phase 2.
--       A malformed value here does not just fail once; it fails every subsequent DataStore write
--       for that player, silently, forever.
