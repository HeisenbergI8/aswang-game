--!strict
--[[
	REVIEW — .claude/scripts/check-config.mjs

	Read because four steps in this plan are gated on it, and because its PATH FILTER is one of the two
	measured consequences of putting RoleDraw under src/server/pure/.
]]

--[[
	IMPORTANT — THE PATH FILTER, and the reason it changes a design decision:

		const GOVERNED = /(^|\/)src\/(server|client)\//

	  · src/shared/pure/TokenBucket.luau    -> NOT governed. Literals allowed.
	  · src/shared/pure/TransformRules.luau -> NOT governed.
	  · src/server/pure/RoleDraw.luau       -> GOVERNED. A weight typed inline FAILS the check.
	  · src/client/Controllers/*.luau       -> GOVERNED. `task.delay(3, ...)` FAILS.
	  · src/shared/Config.luau              -> NOT governed. It IS the file.

	This is why RoleDraw takes `weights` as a parameter rather than holding them, and why UIController
	reads Config.Roles.IntroDuration. Both are the right shape anyway; the check just makes it binding.
]]

-- IMPORTANT — the allowed literals. Everything else in a governed file is flagged.
local IDIOMATIC = { "0", "1", "2", "-1", "0.5", "100" }
-- Consequences used by this plan:
--   `applyScale(humanoid, 1)` on revert          -> allowed
--   `math.max(#candidates - 1, 0)` in RoleDraw   -> allowed
--   `UDim2.fromScale(1, 1)`, `Color3.new(1,1,1)` -> allowed
--   `label.BackgroundTransparency = 0.35`        -> FLAGGED. Waive it; see below.
--   `light.Range = 6`                            -> FLAGGED. Hence Config.Monster.EyeGlowRange.

-- NOTE — two escape hatches that are NOT waivers, and both are used by this plan:
--   a `for i = 1, n` header is control flow, not balance      -> skipped
--   any line that already contains `Config.` is a comparison  -> skipped

-- The waiver form. Used once in this plan, for placeholder UI styling that C18 deletes — a scrim
-- opacity is not a balance knob and does not belong in Config.luau:
--   label.BackgroundTransparency = 0.35 -- config-ok: placeholder styling, replaced at C18

--[[
	NOTE — the calibration note in the header, quoted because it explains why the check is worth
	obeying rather than waiving:

		"A check that flags every numeric literal is a check somebody disables on day two, and then the
		 rule is gone. So the threshold is drawn where a number stops looking like an index or an idiom
		 and starts looking like a KNOB."
]]
