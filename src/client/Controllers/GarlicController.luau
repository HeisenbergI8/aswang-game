--!strict
--[[
	GarlicController — the wall that exists on exactly one machine. (V09, §4.6)

	THIS FILE IS THE MECHANIC AND IT IS ALSO THE SECRECY ARGUMENT, so read both before changing a
	line of it.

	§4.6: "A garlic barrier is silent and invisible in its effect on the Aswang. No knockback, no VFX,
	no sound — its movement simply does not carry it through." That sentence is a MECHANIC, not a
	rendering note. Garlic invites a loyalty test — place it, ask everyone to walk in, whoever cannot
	enter is the Aswang — and the test only stays a game if REFUSING is indistinguishable from BEING
	UNABLE. The moment the barrier plays any effect on the monster, bluffing dies and the test becomes
	a perfect oracle.

	SO THE BLOCK IS A MOVEMENT THIS CLIENT NEVER ISSUES. Roblox gives a client network ownership of its
	own character, so the character is simulated here and the movement vector originates here. Each
	frame, after the control module has read the player's input, this file removes the component that
	would carry the character through a live doorway and re-issues the rest. The only thing that leaves
	this machine is a position, and it is the position of a character that walked where it walked.

	IT WAS A COLLIDABLE WALL FIRST, AND THAT WAS MEASURED AND REJECTED. A character held against a
	`CanCollide` part reports `Humanoid.MoveDirection` of `(-1, 0, -0)`; one standing still reports
	`(0, 0, 0)`. That was read FROM THE SERVER off a live character, three times over two seconds, and
	reproduced from a second approach angle — see `artifacts/movedirection-oracle.md`. `MoveDirection`
	is an ordinarily replicated Humanoid property, so every other client can read it off a peer, and
	§4.6's loyalty test becomes a perfect oracle for anyone willing to script one. Nothing here could
	suppress it after the fact: the engine computes it from the input being held, not from whether the
	motion succeeded. The movement has to never be issued, which is why this file no longer builds a
	part at all.

	THAT IS ALSO THE SPEC'S OWN SENTENCE READ LITERALLY — "its movement simply does not carry it
	through". Not "it is stopped". Not carried.

	ONLY THE COMPONENT INTO THE DOORWAY IS REMOVED. Movement along the wall and away from it are
	untouched, so the monster walks, turns and slides past an opening it cannot enter. A dead stop at a
	threshold would be its own tell, louder than the one this replaced.

	WHAT THIS FILE MUST NEVER DO, and the list is the deliverable: no `WalkSpeed` write, no attribute,
	no CollectionService tag, no Highlight, no sound, no animation, no Humanoid STATE change, no camera
	effect, no BodyVelocity or AlignPosition, no collidable part, and NO HUD LINE — not even for the
	Aswang. `SmokeController`'s header has the reason: the moment feedback exists on screen, a screen
	recording of an Aswang's client is a document of the system and a streamer's overlay is a permanent
	one. Every other controller in this folder that speaks to the Aswang uses
	`OnboardingController.ShowLine`; this one deliberately does not.

	`Humanoid:Move` IS THE ONE CALL IT MAKES, and it is the same call the default control module makes
	every frame with the same signature. It sets `MoveDirection` to what was asked for — which, when
	the ask has been reduced to sliding along a doorway, is a value indistinguishable from a player who
	chose to walk that way.

	COLLISION GROUPS WERE RULED OUT AND MUST STAY RULED OUT. `BasePart.CollisionGroup` is a replicated
	property on every character part and any client can read another player's. A scheme that put the
	Aswang's parts in a different group would be a permanent, map-wide, remote-free role oracle — the
	shape of C04's revert bug and C14's WalkSpeed brand, both of which shipped green.

	IT OWNS NO TRUTH. A player who deletes this script, or never receives a payload, walks through
	garlic — and the server notices, because `ItemService` compares the positions it sampled against
	`pure/GarlicBarrier.crossed`. This file is what the block LOOKS LIKE from inside; it is never what
	makes it. That is `SmokeController`'s property restated, and it is why the barrier is safe to hand
	to a client at all.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local GarlicBarrier = require(Shared.pure.GarlicBarrier)

local GarlicController = {}

--[[
	THE LIVE BARRIERS, AS THIS CLIENT LAST HEARD THEM, IN `pure/GarlicBarrier`'S OWN SHAPE.

	A FULL SNAPSHOT REPLACES THE LIST WHOLESALE — never merged, never appended. `Remotes.luau`'s
	declaration has the argument: two messages for one state are how a client and a server come to
	disagree, and a snapshot is idempotent on a duplicate and self-healing on a rejoin.

	`CreatedAt`/`ExpiresAt` ARE REBUILT ON THIS CLIENT'S OWN CLOCK from `SecondsRemaining`. The server's
	`os.clock()` is meaningless here, which is why the payload carries a duration — see
	`Types.GarlicBarrierSpec`. `CreatedAt` is set to now: the barrier is enforceable here the instant
	it is known here, because there is no round trip left to wait for on this side.
]]
local barriers: { GarlicBarrier.Barrier } = {}

local function rebuild(payload: Types.GarlicBarriersPayload)
	local now = os.clock()
	local next: { GarlicBarrier.Barrier } = {}

	for _, spec in payload.Barriers do
		table.insert(next, {
			X = spec.Position.X,
			Y = spec.Position.Y,
			Z = spec.Position.Z,
			Yaw = spec.Yaw,
			HalfWidth = spec.Width / 2,
			Height = spec.Height,
			CreatedAt = now,
			ExpiresAt = now + spec.SecondsRemaining,
		})
	end

	barriers = next
end

--[[
	THE BLOCK, ONCE PER FRAME, AFTER THE CONTROL MODULE HAS HAD ITS SAY.

	BOUND AFTER `Enum.RenderPriority.Input`, WHICH IS THE WHOLE MECHANISM. The default `PlayerModule`
	reads the keyboard and calls `Humanoid:Move` at Input priority; re-issuing a reduced vector after
	it is what makes the movement never happen rather than happen and be undone. Binding BEFORE it
	would be overwritten every frame and the block would silently do nothing.

	IT RETURNS EARLY ON AN EMPTY LIST, which is the state four of five clients are in for an entire
	round and the state everybody is in for most of one. No barriers, no work, no `Humanoid:Move` call
	at all — so this controller cannot perturb ordinary movement in the case where it has nothing to
	say.

	IT CALLS `Move` ONLY WHEN SUPPRESSION ACTUALLY CHANGED SOMETHING. On every other frame it returns
	without touching the humanoid at all, so this controller cannot perturb ordinary movement — which
	is most frames, for every player, for most of a round. `Humanoid:Move(v, false)` is world-space,
	the same call with the same signature the control module itself makes.
]]
local function onStep()
	if #barriers == 0 then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return
	end

	local desired = humanoid.MoveDirection

	if desired.Magnitude == 0 then
		return
	end

	local now = os.clock()
	local position = root.Position
	local at: GarlicBarrier.Vec3 = { X = position.X, Y = position.Y, Z = position.Z }
	local move: GarlicBarrier.Vec3 = { X = desired.X, Y = desired.Y, Z = desired.Z }
	local margin = Config.Items.GarlicSuppressMarginStuds
	local changed = false

	for _, barrier in barriers do
		if not GarlicBarrier.isLive(barrier, now) then
			continue
		end

		local allowed = GarlicBarrier.suppress(barrier, at, move, margin)

		if allowed.X ~= move.X or allowed.Z ~= move.Z then
			changed = true
		end

		move = allowed
	end

	if not changed then
		return
	end

	humanoid:Move(Vector3.new(move.X, move.Y, move.Z), false)
end

function GarlicController.Init() end

function GarlicController.Start()
	--[[
		EVERY CLIENT LOADS THIS FILE AND CONNECTS THIS HANDLER. Four of five never receive a payload, so
		`barriers` stays empty and `onStep` returns on its first line — `SmokeController`'s header makes
		the same argument for `CamouflageUpdate`. The asymmetry that WOULD leak is on the server side,
		and there is none: `GarlicBarriers` is FireClient to one player, never a broadcast, so no client
		can time or count another's barriers.
	]]
	Remotes.Get("GarlicBarriers").OnClientEvent
		:Connect(function(payload: Types.GarlicBarriersPayload)
			rebuild(payload)
		end)

	RunService:BindToRenderStep("GarlicBarrier", Enum.RenderPriority.Input.Value + 1, onStep)
end

return GarlicController
