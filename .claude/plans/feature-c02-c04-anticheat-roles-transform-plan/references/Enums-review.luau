--!strict
--[[
	REVIEW — src/shared/Enums.luau

	Read for two reasons: the values Phases 5–7 compare against, and the require that keeps this file
	out of every pure module.
]]

-- IMPORTANT: this require is why NO pure module may require Enums. `script.Parent` does not exist under
-- Lune, so a pure module that reached for Enums.RoundPhase.Active would stop being runnable from a
-- terminal — the exact failure RoundTransitions.luau's header warns about.
local Types = require(script.Parent.Types)

--[[
	IMPORTANT — the casts are load-bearing, and the header says why:

		"The `:: Types.X` casts are load-bearing under --!strict. Without them every field infers as
		 plain `string`, and passing one to a parameter typed as the literal union fails to typecheck —
		 which is how the scaffold shipped six analyze errors."

	Consequence for this plan: `Enums.Role.Aswang` and `Enums.RoundPhase.Active` already carry their
	types, so `RoleService.IsAswang` and MonsterService's phase comparison typecheck without a cast.
	A NEW enum added without its cast is where the next analyze error comes from.
]]
Enums.Role = table.freeze({
	Survivor = "SURVIVOR" :: Types.Role,
	Aswang = "ASWANG" :: Types.Role, -- RoleService compares against this
})

Enums.PlayerState = table.freeze({
	Lobby = "LOBBY" :: Types.PlayerState,
	Alive = "ALIVE" :: Types.PlayerState, -- the ONLY state TransformRules admits
	Ghost = "GHOST" :: Types.PlayerState,
	Spectator = "SPECTATOR" :: Types.PlayerState, -- joined mid-round
})

Enums.RoundPhase = table.freeze({
	Active = "ACTIVE" :: Types.RoundPhase, -- MonsterService's phase subscription pivots on this
	Starting = "STARTING" :: Types.RoundPhase, -- where the draw happens, and where monsters reset
})

-- NOTE table.freeze means these are read-only at runtime; nothing in this plan mutates them.
