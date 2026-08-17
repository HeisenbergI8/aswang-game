--!strict
--[[
	QuickChatPhrases — the eight §4.5 phrases, and the wheel's geometry. (C25)

	THE PHRASE SET IS FIXED AND CLOSED, AND THAT IS THE FEATURE. §4.5 names eight phrases; C25's
	BUILD-PLAN row and §C22's scope warning both say the same thing in different words — this is a
	wheel with eight fixed phrases, not a chat system. A ninth phrase is a design decision, not an
	implementation detail, and it lands here where it is one line in a diff.

	WHY THE STRINGS LIVE ON THE CLIENT SIDE OF THE WIRE. `Text` is a TEMPLATE rendered by the
	RECEIVER from a `PhraseId`. Nothing here is ever sent. That is what makes the entire TextService
	question go away: the only user-generated string anywhere near this feature is a player's display
	name, and it is never transmitted either — the payload carries a UserId and each client resolves
	the name itself. No free text crosses the boundary, so there is no free text to filter.

	It is callable by any client and that is fine, for exactly the reason `pure/GhostChat`'s header
	gives: this is eight author-written strings and a division. Logic is not secret, and there is no
	seed and no client-suppliable input here to make it one.

	NO `script.Parent` REQUIRES. The union is re-declared; Luau unions are structural, so this type
	and `Types.QuickChatPhraseId` are the same type and pass to each other without a cast.
]]

export type QuickChatPhraseId =
	"SAW_TRANSFORM"
	| "BODY_HERE"
	| "FOLLOW_ME"
	| "ACCUSE"
	| "TASK_HERE"
	| "RUN"
	| "IM_ALONE"
	| "TRUST_ME"

export type Phrase = {
	Id: QuickChatPhraseId,
	-- The display template. Contains `{name}` if and only if `NeedsTarget`, and `tests` pins the iff.
	Text: string,
	-- Sector index, 0..7, clockwise from straight up. The wheel's layout and the gesture's angle
	-- maths both read this, so the hit region and the selection cannot drift apart.
	Order: number,
	-- Resolves a target player SERVER-SIDE. Exactly one phrase does.
	NeedsTarget: boolean,
	-- Carries a world ping. A PROPERTY OF THE PHRASE, not a client choice — the three locative
	-- phrases ping and the five social ones do not, which removes a boolean from the wire.
	Pings: boolean,
	--[[
		May a GHOST send this? All but one, and the exception is not squeamishness.

		A ghost has NO SERVER CHARACTER (see `ReportGhostPosition`'s header in Remotes.luau), so the
		only position available to resolve "nearest" from is the client-reported one that the same
		header says the server cannot independently verify. Resolving an accusation target from a
		client-supplied position IS the impersonation exploit C25's row forbids, one level of
		indirection removed — the client does not name the player, it names the point the server
		will pick the player from, which is the same power with an extra step.

		`Pings` phrases are allowed for ghosts because a ghost's ping goes only to other ghosts, and
		the ping is the sender's own reported position — a ghost lying about where it is buys it
		nothing it does not already have.
	]]
	GhostMay: boolean,
}

local QuickChatPhrases = {}

local SECTORS = 8
local TAU = math.pi * 2

-- §4.5's list, in its own order. `Order` is the sector, and the two locative "here" phrases sit
-- adjacent on the wheel because they are the pair a player reaches for under pressure.
local PHRASES: { Phrase } = {
	{
		Id = "SAW_TRANSFORM" :: QuickChatPhraseId,
		Text = "I saw it transform!",
		Order = 0,
		NeedsTarget = false,
		Pings = false,
		GhostMay = true,
	},
	{
		Id = "BODY_HERE" :: QuickChatPhraseId,
		Text = "Body here!",
		Order = 1,
		NeedsTarget = false,
		Pings = true,
		GhostMay = true,
	},
	{
		Id = "TASK_HERE" :: QuickChatPhraseId,
		Text = "Task here",
		Order = 2,
		NeedsTarget = false,
		Pings = true,
		GhostMay = true,
	},
	{
		Id = "FOLLOW_ME" :: QuickChatPhraseId,
		Text = "Follow me",
		Order = 3,
		NeedsTarget = false,
		Pings = true,
		GhostMay = true,
	},
	{
		-- THE ONLY PHRASE WITH A SERVER-RESOLVED TARGET. `{name}` is filled by the RECEIVER from
		-- `TargetUserId`, never by the sender.
		Id = "ACCUSE" :: QuickChatPhraseId,
		Text = "It's {name}!",
		Order = 4,
		NeedsTarget = true,
		Pings = false,
		GhostMay = false,
	},
	{
		Id = "RUN" :: QuickChatPhraseId,
		Text = "Run!",
		Order = 5,
		NeedsTarget = false,
		Pings = false,
		GhostMay = true,
	},
	{
		Id = "IM_ALONE" :: QuickChatPhraseId,
		Text = "I'm alone",
		Order = 6,
		NeedsTarget = false,
		Pings = false,
		GhostMay = true,
	},
	{
		Id = "TRUST_ME" :: QuickChatPhraseId,
		Text = "Trust me",
		Order = 7,
		NeedsTarget = false,
		Pings = false,
		GhostMay = true,
	},
}

local BY_ID: { [string]: Phrase } = {}

for _, phrase in PHRASES do
	BY_ID[phrase.Id] = phrase
end

QuickChatPhrases.All = PHRASES
QuickChatPhrases.Sectors = SECTORS

--[[
	Look up a phrase by id, returning nil for anything not in the set.

	THE SERVER CALLS THIS BEFORE IT DOES ANYTHING ELSE WITH A REQUEST. A `nil` here is a refusal, not
	a lookup that fails later — an unvalidated id from a compromised client would otherwise index a
	table and produce a `nil` field access several lines further down, where the error is about
	something else entirely.
]]
function QuickChatPhrases.get(id: string): Phrase?
	return BY_ID[id]
end

--[[
	Which sector an angle falls in, 0..SECTORS-1, clockwise from straight up.

	THIS IS THE FUNCTION THE MOBILE ARGUMENT RESTS ON, which is why it is pure and tested rather than
	inline in a touch callback. Eight equal sectors means each is 45 degrees wide, so a thumb drag
	only has to be accurate to +/-22.5 degrees — that is the concrete reason a radial menu is usable
	one-handed mid-chase and a vertical list is not.

	TOTAL OVER ALL REALS, deliberately. `angleRadians` comes from `math.atan2` on a drag delta, which
	returns (-pi, pi], and a function that answered nil at the wrap point would drop exactly the
	sector sitting at straight up. The modulo makes every input land somewhere.
]]
function QuickChatPhrases.sectorFor(angleRadians: number): number
	local normalised = angleRadians % TAU
	-- Offset by half a sector so a sector is CENTRED on its angle rather than starting at it.
	local shifted = (normalised + TAU / (SECTORS * 2)) % TAU

	return math.floor(shifted / (TAU / SECTORS)) % SECTORS
end

return QuickChatPhrases
