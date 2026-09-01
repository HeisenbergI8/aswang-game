--!strict
--[[
	REVIEW — src/client/Controllers/InputController.luau
	Read for V10 planning: where the strike branch goes, what it must not do, and why `Q` rather than
	a new key.
]]

-- src/client/Controllers/InputController.luau:524-580 — the existing binds
	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)
	ContextActionService:BindAction(THROW_ACTION, onThrowAction, false, Enum.KeyCode.Q)
	ContextActionService:BindAction(SEARCH_ACTION, onSearchAction, false, Enum.KeyCode.E)
	ContextActionService:BindAction(CAMOUFLAGE_ACTION, onCamouflageAction, false, Enum.KeyCode.C)
	ContextActionService:BindAction(SMOKE_ACTION, onSmokeAction, false, Enum.KeyCode.G)
	ContextActionService:BindAction(DROP_ACTION, onDropAction, false, Enum.KeyCode.X)
-- IMPORTANT SEVEN BINDS ALREADY, AND `ContextActionService` DRAWS A MOBILE BUTTON FOR EACH. §5 caps
--           the mobile budget and ~60% of players are on a phone; an eighth thumb target is a real
--           cost. V10 therefore adds NO bind — it adds a branch inside `Q`'s existing handler.
-- IMPORTANT `F` WAS THE TEMPTING ALTERNATIVE AND IS REFUSED. `KILL_ACTION` is bound
--           UNCONDITIONALLY for every player, which is what stops the bind itself being a tell.
--           Giving it a second, role-dependent meaning would put a role-shaped branch in the input
--           path of a controller every player runs — the shape `ItemCarry`'s header refuses for the
--           slot table.

-- src/client/Controllers/InputController.luau:283-292 — what the client may not do
--[[
	THE SALT THROW (§4.6, C14). The client's entire contribution to this mechanic is a direction.

	It sends `camera.CFrame.LookVector` and stops. It does not raycast, does not pick a target, does
	not check range, does not check whether anyone is in front of it, and — critically — does not
	predict a hit and render one optimistically. A client that renders a hit the server refused is a
	client that has told its player the monster is stunned when it is not, which is worse than latency.
]]
-- IMPORTANT V10'S VERSION OF THE LAST SENTENCE IS BIGGER: a client that optimistically rendered a
--           kill would tell its player the ROUND IS OVER. The strike branch sends and stops —
--           no target, no direction, no predicted outcome, no HUD change.

-- src/client/Controllers/InputController.luau:314-336 — the branch V10 extends
	if TrialController.IsActive() then
		Remotes.Get("RequestTrialThrow"):FireServer(camera.CFrame.LookVector)
	elseif ItemUse.verbFor(carriedItem) == "USE_PLACE" then
		--[[
			V09, §4.6. THE CLIENT'S CHOICE IS A CONVENIENCE AND NEVER AN AUTHORITY.

			`ClientRoundSnapshot.YourCarriedItem` is the receiving player's OWN slot, which the server
			owns and pushes every `Round.SnapshotInterval`. A client that guesses wrong — because its
			snapshot is half a second stale, or because it lied — gets a refusal rather than an
			advantage ...

			IT ASKS `pure/ItemUse`, NOT `== "BAWANG"`. That is the same call `ItemService`'s throw
			handler makes, so the client and the server route on one rule rather than two copies of
			it ...

			NO DIRECTION IS SENT. A placement has no aim ...
		]]
		Remotes.Get("RequestPlaceGarlic"):FireServer()
	else
		Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
	end
-- NOTE THE V10 BRANCH IS A COPY OF THIS ONE WITH THREE WORDS CHANGED. `USE_STRIKE`,
--      `RequestStrike`, and "a strike has no aim". Every argument in the comment transfers
--      unchanged, which is the point of having routed garlic through `ItemUse` in the first place.
-- IMPORTANT THE `else` BRANCH IS SALT AND MUST STAY LAST. Inserting the strike branch AFTER the
--           `else` is a syntax error; inserting it before `USE_PLACE` is harmless but reorders a
--           chain whose order currently mirrors the chunk sequence. Add it as the third `elseif`.

-- src/client/Controllers/InputController.luau:322-324 — the sentence that licenses Step 4.1
	-- "the server re-checks either way, so a client that picks wrongly gets a refusal rather than an
	--  advantage"
-- IMPORTANT TRUE FOR V10 AND WORTH RE-VERIFYING RATHER THAN INHERITING. A client that fires
--           `RequestStrike` while holding SALT reaches `pure/StrikeValidation`, gets
--           `STRIKE_NOT_HELD` — which is ABOVE the spend line — and loses nothing. Confirm that
--           ordering survives into the landed handler; it is the only thing standing between a
--           mis-routed key press and a destroyed win condition.

-- src/client/Controllers/UIController.luau:1868-1871 — no change needed
	local carriedWord = if snapshot.YourCarriedItem == Enums.ItemType.Salt
		-- ...
		elseif snapshot.YourCarriedItem == Enums.ItemType.BuntotPagi then "   buntot pagi"
-- NOTE The HUD already names the item. QUESTION for the implementer: does anything nearby hint at a
--      verb? "Press Q" is fine; anything naming the two CONDITIONS is a tutorial line for §9.1's
--      FTUE, not a HUD label, and it belongs to whoever builds that.
