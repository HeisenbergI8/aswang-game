--!strict
--[[
	REVIEW — src/shared/Remotes.luau:20-39, :42-63, :138-190

	Read for the declaration convention and, more usefully, for the two traps this file has already
	documented about payloads. Phase 4 adds three names; the comments below are the house style they
	must match.
]]

-- src/shared/Remotes.luau:20-39 (EVENTS_DOWN)
local EVENTS_DOWN = {
	"RoundSnapshot",
	"PhaseChanged",
	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
	...
	"PlayerKilled",
	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
	"RoundEnded", -- includes the reveal
}
-- NOTE: `ShopOffer` joins this list. Per-player `FireClient`, like `RoleAssigned` and for the same
--       structural reason: the payload is about the receiving player (which passes they own), so a
--       broadcast would hand eight clients eight players' purchase histories.
-- IMPORTANT: `PlayerKilled` is still here but is now a FireClient TO THE VICTIM ALONE — Amendment A3
--            removed the broadcast. C40's `player_killed` analytics event must not resurrect it.

-- src/shared/Remotes.luau:42-63 (the ProfileUpdated comment)
	--[[
		C32/C33. STILL UNWIRED, AND THE PAYLOAD IS THE TRAP. `Types.PlayerProfile` contains
		`Stats.AswangRounds` and `AswangWins` — a per-player history of drawing the role — so the
		obvious implementation, "send the player their profile", ships role history to a client.

		`check-secrecy.mjs` enforces its payload rule ONLY on the two allowlisted remotes
		(`RoundEnded`, `RoleAssigned`), so a whole-profile payload here would pass `npm run verify`
		GREEN. Nothing mechanical stops it; this comment is the stop.
	]]
-- IMPORTANT: THE DIRECTLY APPLICABLE PRECEDENT FOR `ShopOffer`. The natural implementation — "send
--            the player their purchase state" — would reach for the profile, which now also carries
--            `Purchases.Receipts`. Send an EXPLICIT FIELD LIST: `{ Key, Kind, Price, Owned }` and
--            nothing else. A receipt id on the wire is not a secret, but it is purchase history no
--            client needs and it would pass verify green.
-- NOTE: the resolution recorded further down that comment ("`Types.ProfileSnapshot` is the payload
--       … `Stats` is absent in full — not trimmed, absent") is the standard to hold `ShopOffer` to.

-- src/shared/Remotes.luau:138-190 (EVENTS_UP)
	"RequestTimingStop",
	-- C09. NO ARGUMENTS, and that is the whole security design...
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
	...
	"RequestBuyCosmetic",
	--[[
		C34. Also carries an id alone, and the ABSENT argument is the security design.
		There is no price in this request. `pure/Cosmetics.evaluatePurchase` returns the cost out of
		the catalogue and the server spends exactly that...
	]]
-- IMPORTANT: `RequestPromptPurchase` is modelled directly on `RequestBuyCosmetic`. It carries a
--            CATALOGUE KEY and nothing else — no product id (a client could substitute a cheaper
--            product's), no price (a client could shrink it). The absent arguments ARE the design,
--            and the plan's declaration comment says so in this file's voice.
-- NOTE: `RequestOpenShop` follows `RequestClaimDaily` / `RequestEndTrial` — argument-free, because
--       there is nothing a client could legitimately name.

-- IMPORTANT: EVERY name added to EVENTS_UP must also get a `Config.AntiCheat.Budgets` entry.
--            `AllowUnbudgetedRemote = false` means a missing budget REFUSES the remote outright, so
--            the symptom of forgetting is "the button does nothing", with no error. Phase 4 Step 4.2
--            adds both entries and the hand copy in tests/anti-cheat-budgets.test.luau.
--
-- IMPORTANT: the file header's own rule — "every remote listed here must be rate-limited and fully
--            validated". `check:remotes` catches a name used but not declared; the failure it
--            prevents is the silent one, because on the client `WaitForChild` on a name the server
--            never created HANGS FOREVER with no error and no stack trace.
