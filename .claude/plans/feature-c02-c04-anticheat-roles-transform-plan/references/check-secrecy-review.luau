--!strict
--[[
	REVIEW — .claude/scripts/check-secrecy.mjs

	THE check for this game, and the one whose LIMITS matter more to this plan than its coverage.
	Step 5.2 and Step 7.3 are gated on it; Phase 5's real gate is exploit-auditor, for the reasons below.
]]

--[[
	IMPORTANT — the allowlist, verbatim. Note that BOTH remotes this plan relies on are already on it,
	and that adding a third would require editing this file:

		['RoundEnded',   'the round is over — the reveal is the point (spec §4.8)'],
		['RoleAssigned', "fired to exactly one player, carrying only that player's OWN role (spec §4.2)"]

	"Anything not on this list is refused, so adding a leak requires editing this file — which shows up
	 in a diff and in review. That asymmetry is the whole design."
]]

-- The four shapes it catches. Verified against its own self-test.
--   1. :FireAllClients(...) whose ARGUMENT TEXT matches /aswang|imposter|isaswang|aswanguserid|.../i
--      or the word `role`, on a remote not on the allowlist.
--   2. :SetAttribute("Role"|"Aswang", ...)      — attributes replicate to EVERY client
--   3. CollectionService:AddTag(x, "Aswang")    — tags replicate to EVERY client
--   4. `AswangUserId` appearing anywhere under src/client/, and the secret written near
--      ReplicatedStorage or Workspace on the same line

-- NOTE — allowed by its own self-test, and exactly the shape Phase 6/7 uses:
--   Remotes.Get("MonsterTransformed"):FireAllClients(character)   -- "public by design"
--   Remotes.Get("RoleAssigned"):FireClient(player, role)          -- "a private role assignment"
--   local roles: { [number]: Types.Role } = {}                    -- "a server-side role table"

--[[
	IMPORTANT — WHAT IT CANNOT SEE, quoted because it is the reason exploit-auditor GATES C03:

		"Data flow. `local x = state.AswangUserId` followed twenty lines later by
		 `event:FireAllClients(x)` passes this check. Renaming the variable defeats it entirely. This is
		 a tripwire on the OBVIOUS forms, not a proof of secrecy."

	Add to that the two gaps this plan specifically depends on knowing about:

	  · An allowlisted remote's payload is NEVER INSPECTED — the scanner `continue`s past the whole
	    call. Combined with Luau accepting an EXTRA field on an annotated table, a second field on
	    RoleAssignedPayload passes both analyze and this check. High-severity Follow Up.
	  · A DERIVED HINT contains none of its tokens: a Highlight, a walkspeed multiplier, a tool in the
	    backpack, a sound played to one player. §6.2 names this class explicitly. It is why RoleService
	    adds nothing to the Aswang's character, and why Phase 7's biggest risk is a revert that does not
	    fully revert.
]]

-- Waiver form, unused by this plan:
--   Remotes.Get("Custom"):FireAllClients({ Role = r }) -- secrecy-ok: debug build only
