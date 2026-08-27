--!strict
--[[
	REVIEW — src/server/Services/ItemService.luau
	Excerpts only, all from the salt-hit path V05 rehomes. Ranges as of 2026-08-27, branch v2-rewrite.
]]

-- src/server/Services/ItemService.luau:412-428
type RevealState = {
	Instance: Highlight,
	Generation: number,
}
local reveals: { [number]: RevealState } = {}
local function clearReveal(userId: number)
	local state = reveals[userId]
	if state == nil then
		return
	end
	reveals[userId] = nil
	state.Instance:Destroy()
end
-- NOTE: the whole structure V05 moves into MonsterService. Note the ORDER inside clearReveal — the
-- table entry is nilled BEFORE the Destroy, so a re-entrant call cannot double-destroy.
-- NOTE: it destroys the instance it HOLDS rather than looking it up through the character, which is
-- why it still works after a disconnect. V05's `clearExposed` must keep that property.

-- src/server/Services/ItemService.luau:431-450  (applyReveal's header — the four load-bearing choices)
--[[
	A Highlight AND NOT: an attribute (replicates, and `check:secrecy` refuses role-named ones for
	exactly this reason), a CollectionService tag (same), a name colour (`TeamColor` and `Team` both
	replicate and are the classic version of this mistake), or a per-client effect (a "hidden" reveal
	is a reveal that a compromised client reads and an honest one does not — the worst of both).
	...
	`DepthMode = Occluded` is a design decision hiding in an enum value. `AlwaysOnTop` would render the
	glow THROUGH WALLS, turning a ten-second reveal into a ten-second wallhack on the monster.
]]
-- IMPORTANT: every clause here is a constraint on V05's `applyExposed`, not a style note. Losing
-- `Occluded` in the move is a wallhack; losing "parented to the character, stored as the instance"
-- is a branded respawn.

-- src/server/Services/ItemService.luau:451-465
local function applyReveal(target: Player)
	local character = target.Character
	if character == nil then
		return
	end
	clearReveal(target.UserId)
	local highlight = Instance.new("Highlight")
	local generation = os.clock()
	highlight.Name = "SaltReveal"
	highlight.FillColor = rgb(Config.Salt.RevealGlowFillRgb)
	highlight.OutlineColor = rgb(Config.Salt.RevealGlowOutlineRgb)
	highlight.FillTransparency = 0.6 -- config-ok: the glow's own opacity, tuned by eye at C34
-- IMPORTANT: this is the waiver V05 deletes. The `0.6` becomes the midpoint of a two-endpoint ramp
-- in `Config.Monster`, because the brightness is now a function of health (§4.6).
-- NOTE: `rgb` keeps two other callers in this file (lines 203, 237), so removing applyReveal does
-- not orphan it and `selene` stays quiet.
end

-- src/server/Services/ItemService.luau:472-480
	task.delay(Config.Salt.RevealDuration, function()
		local current = reveals[target.UserId]
		if current == nil or current.Generation ~= generation then
			return
		end
		clearReveal(target.UserId)
	end)
-- NOTE: `Config.Salt.RevealDuration` is an ALIAS of `Config.Items.SaltRevealDuration`
-- (Config.luau:341). V05 reads the canonical name; this is the alias's last reader.

-- src/server/Services/ItemService.luau:484-510  (applyHit's header — the audited ordering)
--[[
	  1. `revert()` writes `monster.BaseWalkSpeed` (16) straight onto the humanoid, overwriting the
	     stun's WalkSpeed 0 in the same frame. THE STUN NEVER HAPPENED.
	  2. Four seconds later `clearStun` restored the CAPTURED value — the TRANSFORMED speed, 20 — onto
	     a player who was no longer transformed. ... `Humanoid.WalkSpeed` is a replicated property, so
	     any client could poll every character and find the single one reading 20. A permanent role
	     brand, readable map-wide, with no remote to intercept — the same shape as C04's revert bug,
	     in the same pair of services, with `check:secrecy` green over it.

	THE INVARIANT, stated so the next edit has something to violate: no path through this file may
	leave a living player's WalkSpeed different from every other living player's.
]]
-- IMPORTANT: this is the single most useful paragraph in the repo for V05. It is the precedent for
-- why the Aswang's health may not become a Humanoid property, and it is why `ApplySaltHit` must
-- revert BEFORE ItemService's `applyStun` runs. The invariant binds V05's new code verbatim.

-- src/server/Services/ItemService.luau:508-514
local function applyHit(target: Player)
	MonsterService.ForceRevert(target)
	applyStun(target)
	applyReveal(target)
end
-- NOTE: becomes two lines at V05 — `MonsterService.ApplySaltHit(target)` then `applyStun(target)`.
-- The revert-before-stun ordering is preserved because ApplySaltHit reverts first.

-- src/server/Services/ItemService.luau:516-523
-- EVERY reveal and EVERY stun ends when the round does. ... without it a player hit at second 419 of
-- a 420-second round is still glowing in the lobby, where the glow is no longer an event that anybody
-- witnessed and is simply a mark on one of the eight people standing there.
-- src/server/Services/ItemService.luau:673-680
	if phase ~= Enums.RoundPhase.Active then
		clearAllEffects()
	end
-- IMPORTANT: EVERY non-ACTIVE phase, including ENDING — "pouches lying on the ground during ENDING
-- are scenery, a glow during ENDING is a mark on a player." MonsterService.onPhaseChanged's revert
-- loop already runs on exactly this condition, so the behaviour transfers with no timing change.

-- src/server/Services/ItemService.luau:710-733
		clearReveal(player.UserId)
		stunned[player.UserId] = nil
	end)
	--[[
		THE GLOWING CORPSE ... `MonsterService.makeCorpse` DETACHES the victim's character and keeps it
		in the workspace for `CorpseDuration`. A Highlight parented to that character goes with it — so
		a player revealed by salt and then killed leaves a glowing body lying in the Barrio, which reads
		to every passer-by as "this corpse was the monster".
	]]
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			clearReveal(player.UserId)
		end)
	end)
-- IMPORTANT: this connection and its comment MOVE to MonsterService at V05. It is the only written
-- record of the glowing-corpse failure; losing it in the move loses the reason.

-- src/server/Services/ItemService.luau:600-615
			and MonsterService.IsTransformed(candidate.UserId)
		TargetIsTransformedAswang = isTransformedAswang,
-- NOTE: the pattern V08's strike gate copies — the role is ANDed with a form query on the SERVER and
-- a single boolean is handed to the pure module, so the role never enters the pure layer.
