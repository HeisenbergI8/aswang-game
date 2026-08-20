--!strict
--[[
	Remotes — single place where every RemoteEvent/RemoteFunction is declared.

	The server creates them; the client waits for them. Declaring them in one
	file means you can audit your entire network surface at a glance, which
	matters a lot in a game where one secret (who is the Aswang) decides
	everything.

	RULE: every remote listed here must be rate-limited and fully validated in
	AntiCheatService / the owning service. The client only ever *requests*.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

-- Server -> Client (the server tells you things)
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
	"PhaseChanged",
	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
	"TaskProgressChanged",
	-- C09. FireClient to the ONE player standing at a TIMING point. Carries a task point's bar, never
	-- a player: the server owns the phase and re-derives it on every stop, so this is a rendering
	-- hint and not an input to any decision.
	"TimingBarChanged",
	-- C12. FireClient to EVERY player, at STARTING, one loop, one payload shape. Survivors get this
	-- round's real five; the Aswang gets a decoy five. The uniformity is the design — see
	-- Types.TaskListPayload. Deliberately NOT on check-secrecy's REVEAL_ALLOWLIST: it carries no role,
	-- so it must keep being scanned like any other remote.
	"TaskListAssigned",
	"PlayerKilled",
	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
	"SaltEffect",
	"RoundEnded", -- includes the reveal
	"QuickChatBroadcast",
	--[[
		C32/C33. STILL UNWIRED, AND THE PAYLOAD IS THE TRAP. `Types.PlayerProfile` contains
		`Stats.AswangRounds` and `AswangWins` — a per-player history of drawing the role — so the
		obvious implementation, "send the player their profile", ships role history to a client.

		`check-secrecy.mjs` enforces its payload rule ONLY on the two allowlisted remotes (`RoundEnded`,
		`RoleAssigned`), so a whole-profile payload here would pass `npm run verify` GREEN. Nothing
		mechanical stops it; this comment is the stop.

		Send an explicit field list — XP, Level, Coins, Equipped. If a whole profile is ever genuinely
		wanted, add this remote to `check-secrecy.mjs`'s allowlist WITH a reason first, so the decision
		appears in a diff instead of in a payload. (Raised by `exploit-auditor` during C31.)

		WIRED AT C32/C33/C34, AND THE FIELD LIST ABOVE WAS FOLLOWED. `Types.ProfileSnapshot` is the
		payload: XP, Level, Coins, the level bar's two spans, the equipped ids, the OWNED set, the
		daily preview, and the last round's award breakdown. `Stats` is absent in full — not trimmed,
		absent — so `AswangRounds` and `AswangWins` have no field to leak through.

		FireClient TO ONE PLAYER, ALWAYS, carrying only that player's own profile. There is no
		FireAllClients path for this remote and there must not be: every field in it is per-player, so
		a broadcast would hand eight clients eight players' inventories, and `Owned` plus a level is
		enough to fingerprint who is who across rounds.
	]]
	"ProfileUpdated",
	--[[
		C15. FireClient to ghosts ONLY, one payload per recipient, NEVER FireAllClients.

		It carries the UserIds of dead players, and what makes that safe is its AUDIENCE rather than its
		contents — the mirror of RoleAssigned, which is safe because its payload is minimal. Being dead
		is not a role, but WHICH of the eight are dead is precisely the death oracle Amendment A3
		removed `AlivePlayerCount` to close, so a living client must never receive this.

		`check-secrecy.mjs` cannot police that: it reads payload fields and call shapes, and
		`FireClient(player, roster)` inside a loop over the wrong list is textually identical to one
		over the right list. The state test therefore lives at the fire site in GhostService.
	]]
	"GhostRoster",
	--[[
		C20. FireClient to ONE player, at ACTIVE, carrying a single task Id and nothing else.

		Sent only to players the server has never seen finish a task — §10's answer to Appendix C's
		single worst number, 79.9% of a competitor's 1.4M players never completing one objective.

		WHAT IT REVEALS, stated plainly because a per-player down-remote deserves it: that the RECEIVER
		is new. It cannot reveal anything about anyone else — the recipient list is never sent anywhere,
		and the payload is one task Id already painted in-world on every client by `TaskController` off
		the replicated `ActiveTaskPoint` tag, out to `Config.Tasks.MarkerVisibleStuds`.

		THE TAG IS THE REASON, NOT `TaskListAssigned`. An earlier version of this comment cited both,
		and for the Aswang the second one is a lie the server deliberately told them: C12 sends them a
		DECOY five, so a real task Id is something their task list denies. The tag is what makes this
		harmless anyway — `TaskController` paints every genuinely-active point for every role, so an
		Aswang can already see the true five in the world, and `TaskListView`'s own header concedes it.
		C20's marginal gift is "this one is nearest your spawn", which they could also see.

		That the two channels disagree is a coherence cost, not an information one, and it is taken
		deliberately: pointing a new Aswang at a decoy point would teach them that holding E does
		nothing, which is precisely the failure §10 exists to delete.

		Being new is not a role, and the asymmetry runs the safe way: the Aswang learning that some
		unnamed player is a beginner tells them nothing they cannot get by watching, and no survivor
		learns anything about the Aswang. Compare `GhostRoster` above, which is dangerous for exactly
		the reason this one is not — it names WHICH players are in a set.

		The waypoint it drives is drawn CLIENT-SIDE into PlayerGui. A Beam or Billboard created on the
		server would be a permanent replicated marker on one player, which is the shape §6.2 exists to
		refuse.
	]]
	"FirstObjectiveAssigned",
	--[[
		C21. FireClient to the ONE player in a Solo Trial. Never FireAllClients.

		THE INTERESTING PROPERTY IS THAT THERE IS NO SECRET HERE AT ALL, and saying so is the point:
		the trial's Aswang is a scripted rig, so no role exists to leak inside a trial. The risk runs
		the other way — a trial remote that could be confused with a round one, or fired at a player
		who is in a round. `Types.TrialSnapshot` shares no field name with `ClientRoundSnapshot`
		precisely so that confusion is a type error rather than a subtle bug, and the server refuses
		to open a session at all unless RoundService is IDLE.

		WHAT A SECOND PLAYER LEARNS: nothing from this remote, which they never receive. They can of
		course SEE a trial player walk to the trial corner and see the rig, and that is harmless by
		construction — a trial only runs while no round is running, so there is no round-secret to
		correlate it against. `.claude/lessons/absence-is-observable.md` applies in its mild direction
		and resolves the same way OnboardingController's waypoint does.
	]]
	"TrialSnapshot",
	--[[
		C23. FireClient to ONE player, carrying a `Types.TeachingCueId` and nothing else.

		The generalisation of `FirstObjectiveAssigned` directly above, and it inherits that entry's
		argument wholesale: what it reveals is that the RECEIVER is new, it names nobody else, and the
		events it fires on (a salt pickup, a transform, a ghost death) are already public or already
		the receiver's own. An id rather than a string so the copy has one home.
	]]
	"TeachingCue",
}

-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	"RequestTaskProgress",
	-- C09. NO ARGUMENTS, and that is the whole security design: the server resolves which task from
	-- the player's own position and reads the bar's phase off its own clock at the moment this lands.
	-- There is no argument in which a client could name a moment, a position or an outcome.
	"RequestTimingStop",
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
	--[[
		C15. A ghost tells the server where its LOCAL body is.

		THIS IS THE ONE PLACE IN THE GAME WHERE THE CLIENT OWNS A POSITION, and it is a deliberate
		trade. Ghosts have no server character — a replicated body per dead player named the dead set
		to every client, which is Amendment A3's death oracle — so the two things that needed a ghost's
		position (`TaskService` presence at 25%, and the spook's origin) read it from here instead.

		WHAT A LYING CLIENT BUYS, stated plainly because it is the cost of the trade: a ghost can claim
		to stand at a task point it is not at, and contribute 25% of one player's rate from anywhere.
		It cannot claim to be ALIVE, cannot be seen, cannot kill, cannot be killed, and cannot make the
		claim at all unless the server already believes it is a ghost. Compare what the server body was
		leaking in exchange and this is not a close call.

		Continuity is checked server-side against `Config.Ghost.FlySpeed`, so the lie has to be walked
		rather than teleported.
	]]
	"ReportGhostPosition",
	"RequestGhostSpook",
	--[[
		C34. Carries a cosmetic id and nothing else — no slot, no price, no "and equip it".

		THE SLOT IS NOT AN ARGUMENT, deliberately: it is a property of the item in
		`Config.Cosmetics.Catalogue`, so a client cannot name an id in one slot and a slot in another
		and see which of the two the server believes. `pure/Cosmetics.evaluateEquip` re-checks
		ownership on every call, because the lobby only OFFERS what it thinks is owned and an offer is
		a hint rather than a permission (§6.2).
	]]
	"RequestEquipCosmetic",
	--[[
		C34. Also carries an id alone, and the ABSENT argument is the security design.

		There is no price in this request. `pure/Cosmetics.evaluatePurchase` returns the cost out of
		the catalogue and the server spends exactly that, so there is no number here for a compromised
		client to shrink and no path where a client's arithmetic decides what a cosmetic costs.
	]]
	"RequestBuyCosmetic",
	--[[
		C33. NO ARGUMENTS. The day is `os.time()` on the server, the streak is in the profile, and
		`pure/DailyStreak.evaluate` decides — there is nothing a client could legitimately name, and a
		claimed timestamp is precisely the field that would make the streak forgeable.
	]]
	"RequestClaimDaily",
	--[[
		C21. NO ARGUMENTS, deliberately, and for the same reason `RequestTimingStop` above has none.

		There is nothing a client could legitimately name here: which trial, where, and whether it is
		allowed are all server facts. The handler re-runs `shared/pure/TrialAdmission` on every call
		rather than trusting that C24's button was only shown when a trial was actually available —
		the button is a hint to an honest player, never a permission.
	]]
	"RequestStartTrial",
	-- C22. Also argument-free: it means "I am done", and the server already knows whose session it is.
	"RequestEndTrial",
	--[[
		C22. A throw INSIDE a trial, and it is a separate remote from `RequestThrowSalt` on purpose.

		§9.1 asks that the player "learn to throw salt", and they could not: `ItemService` resolves
		every throw through `pure/SaltThrow` against `RoundService.GetPhase()`, and a trial runs while
		the phase is IDLE — so the real remote answers WRONG_PHASE and the tutorial taught an action
		the player could not perform.

		THE TWO WAYS TO FIX IT WERE A NEW REMOTE OR A LOOSER `ItemService`, AND THE LOOSER SERVICE IS
		THE ONE THAT WOULD HAVE HURT. Relaxing the phase gate means the salt system starts consulting
		trial state to decide a live round's throws — coupling the two services this entire feature
		exists to keep apart, on the 🔒 surface, for a tutorial. This remote costs one budget entry and
		couples nothing.

		It carries a direction and nothing else, exactly as `RequestThrowSalt` does. The server owns
		the range, the cone, the target and the outcome — and both remotes resolve through the SAME
		`SaltThrow.inCone`, so the throw a player learns here is the throw that works in a round.
	]]
	"RequestTrialThrow",
}

local Remotes = {}

local function getFolder(): Folder
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local folder = getFolder()

local function getEvent(name: string): RemoteEvent
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Eagerly create on the server so the client's WaitForChild always resolves.
if IS_SERVER then
	for _, name in EVENTS_DOWN do
		getEvent(name)
	end
	for _, name in EVENTS_UP do
		getEvent(name)
	end
end

-- Usage: Remotes.Get("RequestKill"):FireServer(targetUserId)
function Remotes.Get(name: string): RemoteEvent
	return getEvent(name)
end

Remotes.Down = EVENTS_DOWN
Remotes.Up = EVENTS_UP

return Remotes
