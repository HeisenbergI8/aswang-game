--!strict
--[[
	REVIEW — src/client/Controllers/UIController.luau (2010+ lines). Phase 5 Step 5.2 only.

	The HUD currently GUESSES what the player is carrying, because C13 had no truthful channel. V08
	has one, and the whole estimate apparatus is deleted rather than adapted.

	Cited against the file as read on 2026-08-29.
]]

-- src/client/Controllers/UIController.luau:1975-2010 — the pouch estimate, abridged
if pouches ~= nil then
	pouches.ChildRemoved:Connect(function(pouch: Instance)
		--[[
			DISTANCE-GATED, or every client counts every pickup. `ChildRemoved` fires on ALL clients
			when ANY pouch is taken, so an ungated increment would show a survivor across the map
			collecting salt they never touched.

			The pouch is already destroyed by the time this fires, so its position cannot be read from
			it — but a `Part` retains its last CFrame after Destroy, which is enough to compare.
		]]
		if (pouch.Position - root.Position).Magnitude <= Config.Salt.PickupRangeStuds then
			saltSeen = math.min(saltSeen + 1, Config.Salt.CarryLimit)
		end
	end)
end
-- IMPORTANT: ALL OF THIS GOES. The `SaltPouches` folder it watches is deleted in Step 3.1, so the
-- `pouches` lookup returns nil and the connection is dead code the moment Phase 3 lands. Leaving it
-- would be a silently-never-firing handler that looks like a working feature.
-- NOTE: `Config.Salt.PickupRangeStuds` and `Config.Salt.CarryLimit` here are two of the five
-- readers that must be gone before Phase 2's table deletion can land. This is why the plan defers
-- that deletion to Step 5.2.
-- NOTE: "a Part retains its last CFrame after Destroy" is a genuine Roblox behaviour finding worth
-- keeping in mind, though V08 needs it nowhere.

-- src/client/Controllers/UIController.luau:1996-2005 — the clamp comment
--[[
	THE SERVER'S OWN RADIUS, NOT A GENEROUS ONE, AND CLAMPED TO THE CARRY LIMIT.

	This read `PickupRangeStuds * 2` on the theory that a generous display was kinder than a strict
	one. It is not: the server picks up at `PickupRangeStuds` (6) and `CarryLimit` is 1, so two
	players 7-12 studs apart near one pouch BOTH incremented, and the HUD could show `~2` — a number
	the rules make impossible. An impossible number reads as a broken game, not as an estimate.
]]
-- IMPORTANT: THE ARGUMENT FOR REPLACING THE ESTIMATE ENTIRELY, made by the estimate's own author.
-- The bug was fixed by clamping; V08 removes the class of bug by removing the guess. Quote this in
-- the replacement comment — "an estimate that can be wrong is worse than a value that lags half a
-- second" is the finding, and it was learned here the hard way.

-- src/client/Controllers/UIController.luau:2012-2020
--[[
	Called by InputController when this client actually presses the throw key. Kept here rather than
	letting InputController touch the HUD directly, so `saltSeen` has one owner.

	`math.max` because the estimate can drift below zero if a pickup was missed.
]]
function UIController.NoteThrow()
	saltSeen = math.max(0, saltSeen - 1)
end
-- IMPORTANT: PUBLIC API BEING DELETED. Grep for other callers before removing it. InputController
-- (:289-292) is the only one this plan found, but the function is on the module table, and
-- OnboardingController and TrialController both draw HUD.
-- NOTE: "the estimate can drift below zero if a pickup was missed" is the guess admitting it is a
-- guess. The `~` prefix on screen exists for the same reason and goes with it.

-- src/client/Controllers/UIController.luau:190-196
--[[
	`Config.Monster` and `Config.Salt` store colours as `{ r, g, b }` rather than as `Color3`, so
	...
]]
-- NOTE: a third `Config.Salt` reader in this file, in a comment rather than in code — but a comment
-- naming a table that no longer exists is a comment that sends the next reader to nothing. Update it
-- to `Config.Items` when the table dies.

-- WHAT REPLACES ALL OF IT
-- ONE FIELD READ in the existing `RoundSnapshot` handler: `snapshot.YourCarriedItem`, which is
-- `Types.ItemType?` — server-owned, per-player, FireClient-only, refreshed every
-- Config.Round.SnapshotInterval (0.5s).
-- IMPORTANT: the label shows the item's NAME, not a count, and shows NOTHING for an empty hand rather
-- than "NONE". An empty hand is the common case for a survivor between finds AND for the Aswang; a
-- persistent element whose text varies is fine, but one that is conditionally HIDDEN is a thing whose
-- absence is readable. Keep the element's presence constant if it is drawn at all.
-- IMPORTANT: the HUD shows only THIS client's slot. `ClientRoundSnapshot` has no field for another
-- player's carry and must not grow one — §4.5's "I have the buntot pagi" is a phrase a player CHOOSES
-- to say, and a HUD that showed who held what would delete its reason to exist (Types.luau:451-455).
-- QUESTION: what does the Solo Trial's HUD show now? C22 hands the player a scripted pouch that is
-- not in a container and not in ItemService.slot, and `saltSeen` was driving that display. Either
-- TrialService gains its own field or TrialController draws it locally. NOT ANSWERED BY THIS PLAN —
-- the playtester must open the trial and look. Follow Up 4.
