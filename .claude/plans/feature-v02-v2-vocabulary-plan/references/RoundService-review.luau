--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau:616-641 (plus fire sites at :933 and :1029).
	Read for: V02 Step 1.2 only — to establish whether ClientRoundSnapshot may carry a carry slot.
	NOT CHANGED BY THIS PLAN. V02 touches no service.
]]

-- src/server/Services/RoundService.luau:617-624
--[[
	IMPORTANT THE PRECEDENT THAT MAKES STEP 1.2 A ZERO-SERVICE-CHANGE STEP.

	`YourRole` is DECLARED on the type and deliberately never set by buildSnapshot. The header explains
	why — RoleAssigned is the single allowlisted carrier of a role in check-secrecy.mjs, and one
	carrier is auditable in a way that two are not.

	So an optional field on ClientRoundSnapshot with no producer is an established, reviewed pattern in
	this file, not a novelty. `YourCarriedItem` follows it exactly: V02 declares it, V02 sets nothing,
	`analyze` stays clean because the field is optional.
]]
local function buildSnapshot(player: Player): Types.ClientRoundSnapshot
	return {
		Phase = state.Phase,
		SecondsRemaining = RoundService.GetSecondsRemaining(),
		RoundNumber = state.RoundNumber,
		YourState = RoundService.GetPlayerState(player),
	}
end

-- src/server/Services/RoundService.luau:636-641
--[[
	IMPORTANT THE STRUCTURAL FACT THE CARRY SLOT DEPENDS ON.

	The snapshot is per player and sent with :FireClient. There is NO FireAllClients form of this
	payload anywhere — all three fire sites (:639, :933, :1029) are FireClient. The stated reason is
	that YourState already differs between a survivor and a mid-round spectator, so a broadcast could
	only ever carry one of them.

	That is what makes `YourCarriedItem` safe rather than merely "probably fine": there is no shape of
	this remote in which another player's carry could ride along, and adding one would require
	rewriting this function's contract, which is a visible change.

	NOTE the safety is a property of the CALL SITE, not of the type. If a later chunk adds a
	FireAllClients of a snapshot for a lobby or an end screen, this argument evaporates. Types.luau's
	own comment at :1726 in UIController records a related refusal — reusing ClientRoundSnapshot for a
	lobby label "would move the round contract for a cosmetic reason".
]]
local function broadcastSnapshot()
	for _, player in Players:GetPlayers() do
		snapshotRemote:FireClient(player, buildSnapshot(player))
	end
end

--[[
	QUESTION for whichever chunk first SETS YourCarriedItem: the snapshot fires every
	Config.Round.SnapshotInterval (0.5s) to every player. A carry slot that changes on pickup means the
	HUD can lag a pickup by up to half a second, which for an item you walked over is noticeable. The
	pattern already in this file is an immediate extra push on the transition that matters (see the
	push right after setPhase). Use that rather than lowering SnapshotInterval — §5 puts ~60% of
	players on a phone and the interval is a per-player-per-tick network cost.

	NOTE this is a V03+ question. V02 sets nothing, so it has no latency to answer for.
]]
