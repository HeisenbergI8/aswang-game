--!strict
--[[
	REVIEW — src/client/Controllers/OnboardingController.luau:114-126, 141-153
	Read for V03 because SearchController renders the find through it. Short review: one signature and
	one dependency rule.
]]

function OnboardingController.ShowLine(text: string) -- :114
	ensureHint()

	local teach = hint

	if teach == nil then
		return
	end

	teach.Text = text
	teach.Visible = true

	lineToken += 1 -- :126
-- NOTE Takes a plain string and returns nothing. Lazily builds its label (`ensureHint`) and returns
-- silently if it cannot, so a caller needs no guard. `lineToken` is a self-expiring token, so
-- consecutive lines replace rather than stack — which is the behaviour V03 wants when a player
-- searches three containers in a row.

--[[
	IMPORTANT — THE PRECEDENT V03 FOLLOWS EXACTLY (OnboardingController.luau:143-149):

	  "C23. NO NEW LABEL AND NO NEW CONTROLLER — the cue resolves to copy through the same pure module
	   the server used to decide it was owed, and renders through the same `ShowLine` this file already
	   owns.

	   THE COPY IS RESOLVED HERE RATHER THAN SENT. The payload is an id, so player-facing text never
	   crosses the wire — a localisation and a trust problem avoided for no cost."

	V03's `SearchUpdate` carries an `ItemType`, never a sentence, and `SearchController.FOUND_LINES`
	resolves it client-side. Same rule, one chunk later.
]]

--[[
	IMPORTANT — THE DEPENDENCY DIRECTION, AND WHY IT DECIDES CONTROLLER_ORDER.

	`TrialController` already requires this module for `ShowLine`, and `init.client.luau`'s comment
	(:39-46) calls that "a real dependency rather than a preference [...] deliberately one-way —
	`OnboardingController` knows nothing about the trial, so the arrow cannot become a cycle."

	`SearchController` is the second such requirer, and the same sentence applies unchanged:
	OnboardingController knows nothing about searching. So SearchController goes AFTER
	OnboardingController and BEFORE InputController in CONTROLLER_ORDER.
]]

--[[
	QUESTION — IS "Empty." THE RIGHT LINE FOR A SEARCH THAT FOUND NOTHING?

	V03 shows it because silence after six seconds reads as a bug, and §4.4 insists the empty container
	is the POINT rather than a failure ("You will open empty ones, and that is the point"). But this
	label is the ONBOARDING hint surface — it is where a new player is taught things — and using it for
	a routine, several-times-a-minute outcome may wear it out or make genuine teaching cues invisible
	by association.

	Not V03's call to make permanently. Flagged so the V16 playtest watches for it; the cheap fix if it
	grates is a dedicated line under the search bar, which is the same HUD chunk that owes mobile a
	Search button.
]]
