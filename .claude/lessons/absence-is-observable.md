---
id: absence-is-observable
trigger: ghost, dead player, who is dead, invisible, hide, enumerate, leak, spectator, body, corpse
scope: gameplay
learned: 2026-08-14
evidence: C15's ghost body was redesigned three times — hidden server body, then no body, then the corpse kept — because the first two both let any client list the dead set in one line
---

**Lesson:** In this game a secrecy leak is a DIFFERENCE between players, not a piece of data — so
removing state from one group leaks exactly as loudly as adding it, and `x == nil` is as enumerable as
`x == "aswang"`.

**Why:** CLAUDE.md's derived-hint paragraph lists only things you ADD — a speed multiplier, a
Highlight, a tool, a sound. C15 needed ghosts to have a position, and both attempts leaked through the
gap it does not name. A hidden server character: `Transparency = 1` hides pixels, not existence, so it
was still a player-named Model in `workspace` with a tag and a distinct WalkSpeed. No character at all:
`dead[p] = (p.Character == nil)` is one line, and `GetPropertyChangedSignal("Character")` makes it a
timestamped death alert. Both eliminate candidates outright, because the Aswang can never be a ghost —
their death aborts the round. Amendment A3's oracle, restored twice by code written to protect it, with
`verify` and `check:secrecy` green over both.

**Do:**
- Ask "what is TRUE of the living and FALSE of the dead" — for every server-owned, replicated property.
  `Character`, `Humanoid.WalkSpeed`, membership of any folder, tag or channel. A constant across all
  players is safe; a difference is the leak, in either direction.
- **`check:secrecy` cannot see any of this.** It matches role tokens in tag names, attributes and
  payload fields. "GhostBody" contains none, and an absent Character has no name at all.
- Prefer making the dead INDISTINGUISHABLE over making them HIDDEN. The shipped answer keeps the corpse
  attached as `player.Character`, so every player has one; you learn a death by looking at the body,
  which is what §4.7 always described.
- Note that this is only fully true once §5's `StreamingEnabled` lands at C17 — a distant corpse then
  does not replicate. Before that a property scan still tells a corpse from a walker.
