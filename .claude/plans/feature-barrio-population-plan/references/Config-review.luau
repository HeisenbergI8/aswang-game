--!strict
--[[
	REVIEW — src/shared/Config.luau (1,549 lines), the `Ambient` block and its invariants
	         and tests/config.test.luau:1036-1049
]]

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/Config.luau:670-702 — the Ambient block and the secrecy floor above it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

--	SO PerForm IS A BALANCE NUMBER WITH A SECRECY FLOOR UNDER IT, and `tests/config.test.luau`
--	pins it: below 2, a camouflaged Aswang is the ONLY entity of its form once the real one has
--	wandered off, and §4.5's "It's the cat!" stops being a guess. It is the same class of silent
--	invariant as `SaltDamage x (SaltSpawnCount - 1)` — nothing in the game tells you when it has
--	been tuned away.
--
--	THE CEILING IS §5'S MOBILE BUDGET. Four forms at four each is 16 wandering models

	Ambient = {
		PerForm = 4,
		WanderRadius = 24,
		WanderSpeed = 4,
		WanderInterval = 6,
		IdleSeconds = 3,
		FallbackScatterRadius = 60,
		FallbackHeight = 3,
	},

-- IMPORTANT: THE FLOOR IS 2 AND THE PLAN MOVES THIS TO 3, so the floor is cleared and its argument is
-- untouched. What the drop DOES change is the strength of the disguise: claiming one of three leaves
-- two free entities where claiming one of four left three. That is a real weakening and it is the
-- price of six silhouettes instead of four at +2 entities instead of +8. The comment must say so
-- rather than quietly moving the number — this is exactly the class of change the floor exists to
-- make someone argue with.
--
-- IMPORTANT: there is NO CEILING on `PerForm`, and at four forms nobody would have wanted one. At six,
-- `PerForm = 5` is 30 rigs on a phone and §5's budget refuses it with no error anywhere. Phase 1 adds
-- the ceiling next to the floor.
--
-- NOTE: the "16 wandering models" sentence in the header is arithmetic that goes stale silently. It is
-- rewritten in Phase 1 alongside the number.
--
-- NOTE: `tests/barrio-ambient.test.luau:36` parses `PerForm` out of this file as TEXT, with a
-- two-tab-indent pattern `"\n\t\tPerForm = (%d+),"`. Re-indenting or re-nesting the key breaks that
-- parse — it asserts with a message saying so, but the constraint is real and undocumented here.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- src/shared/Config.luau:1128-1166 — Performance, the light budget this plan must not spend
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

	Performance = {
		MaxVisibleLights = 8,
		ReservedGameplayLights = 3,
		LightCullRadiusStuds = 140,
	},

-- Eight visible lights, three of which are reserved for gameplay tells rather than scenery.
--
-- IMPORTANT: THE RESERVED THREE ARE WHY INTERIORS AND LANTERNS MUST USE `Neon`. The Aswang's eye glow
-- and salt-pouch glows are §4.3's warning and §4.6's counterplay; they are protected by NEVER carrying
-- the `MapLight` tag, so the culler cannot see them and cannot switch them off. That leaves five slots
-- for the whole barrio, which fourteen spaced lanterns already fill by distance.
--
-- Seven lit interiors would break this outright. `Neon` glows for no light slot, which is how the
-- container bands and banderitas bulbs already work — and the builder ASSERTS zero dressing lights, so
-- a `PointLight` added in an interior fails the build rather than degrading the map quietly.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- tests/config.test.luau:1036-1049 — the floor, as it is actually written
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

check(
	"Ambient.PerForm >= 2 — a lone entity of a form IS the monster",
	Config.Ambient.PerForm >= 2,
	`PerForm={Config.Ambient.PerForm}`
)

-- NOTE: this file pins RELATIONSHIPS between numbers rather than the numbers themselves, which is the
-- convention every new check in this plan follows. `ClaimRadius < WanderRadius` (Phase 3) is the same
-- shape and guards the same class of silent failure: above it, the monster can wear a pig where no pig
-- has ever been, the territory constraint becomes advisory, and every test stays green.
