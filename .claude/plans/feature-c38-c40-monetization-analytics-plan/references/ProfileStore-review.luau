--!strict
--[[
	REVIEW — vendor/ProfileStore.luau:1172-1190, :860-930, :1090

	THE MOST IMPORTANT FILE READ FOR THIS PLAN. The whole shape of Q1's answer comes from three
	observations here, and the first one contradicts the obvious implementation of C38.
]]

-- vendor/ProfileStore.luau:1172-1190
function Profile:Save()

	if self.view_mode == true then
		error(`[{script.Name}]: Can't save profile in view mode; Should you be calling :SetAsync() instead?`)
	end

	if self:IsActive() == false then
		warn(`[{script.Name}]: Attempted saving an inactive profile (STORE:{self.ProfileStore.Name}; KEY:{self.Key});`
			.. ` Traceback:\n` .. debug.traceback())
		return
	end

	-- Move the profile right behind the auto save index to delay the next auto save for it:
	RemoveProfileFromAutoSave(self)
	AddProfileToAutoSave(self)

	-- Perform save in new thread:
	task.spawn(SaveProfileAsync, self)

end
-- IMPORTANT: `Save()` DOES NOT YIELD AND DOES NOT REPORT SUCCESS. It ends in a `task.spawn` and
--            returns immediately. This is the single finding that reshaped C38's entire design.
--
--            The natural implementation of BUILD-PLAN's "granting before returning PurchaseGranted"
--            is: mutate, `Save()`, return `PurchaseGranted`. That returns PurchaseGranted for a
--            write that has not happened and may never happen — Roblox retires the receipt, and the
--            grant is lost with no error anywhere. It is the "eats a real purchase" half of the
--            failure BUILD-PLAN calls unrecoverable.
--
-- NOTE: `ProgressionService.saveNow` (:317-323) wraps this and is CORRECT for what it is used for —
--       an XP award nobody would be angry to lose. It is simply not enough for a receipt.
--
-- NOTE: the `IsActive() == false` branch WARNS AND RETURNS rather than erroring. So a save attempted
--       on a profile whose session ended is a silent no-op, which is why the durability wait in
--       Phase 2 polls `IsActive()` rather than trusting a signal to arrive.

-- vendor/ProfileStore.luau:877 (inside SaveProfileAsync's success branch)
profile.KeyInfo = key_info
profile.LastSavedData = loaded_data.Data
-- IMPORTANT: `LastSavedData` is assigned from the DATASTORE'S OWN RETURNED DATA, not from the local
--            table we mutated. That is what makes it a durability oracle rather than an echo: if the
--            receipt id is in here, the DataStore has it.

-- vendor/ProfileStore.luau:924
profile.OnAfterSave:Fire(profile.LastSavedData)
-- IMPORTANT: fired ONLY on this branch. The `elseif repeat_save_flag == true` branch immediately
--            below (:926) does `task.wait(exp_backoff)` and retries WITHOUT firing anything.
--            So a fire of OnAfterSave carrying our receipt id is proof of a durable write, and a
--            timeout waiting for it is not proof of failure — only of "not yet".
--
-- IMPORTANT: this is why the receipt id MUST live inside the profile. `LastSavedData` can only
--            confirm what is in the profile; a receipt id in a side DataStore makes the question
--            "is this grant durable" unanswerable with the tools ProfileStore gives us.

-- vendor/ProfileStore.luau:1090
function Profile:EndSession()
-- NOTE: `ProgressionService.endSession` (:325-340) comments that this "SAVES AND THEN RELEASES THE
--       LOCK, in that order". So a player leaving mid-durability-wait may still have their grant
--       land on the way out — which is why Phase 2's wait re-checks `LastSavedData` after breaking
--       out of the loop rather than returning false on `IsActive()` going away.

-- QUESTION: nothing here tells us whether Roblox serialises concurrent ProcessReceipt callbacks for
--           one player. The durability wait yields inside that callback, so if two receipts for the
--           same player can be in flight at once they will interleave. The design is safe either
--           way — `Receipts.record` is idempotent and `decide` reads the live ring — but that is
--           reasoning rather than evidence, and it is in the plan's Follow Ups.
