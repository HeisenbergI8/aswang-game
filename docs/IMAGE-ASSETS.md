# Image assets

Every image in the game, with the record nothing else holds. Companion to `docs/AUDIO-ASSETS.md`, and
kept for the identical reason: **Roblox moderation can pull an asset, and the symptom is a blank surface
with no error and nothing in `git status`.** The row below is how you know what used to be there.

Unlike audio, images here are **partly generated and partly sourced.** There is no image generation in
this toolchain — not in Claude Code, not in the Claude app — so anything in the Generated column came
from an external tool (Gemini, ChatGPT) run by the developer, with a prompt written here. That prompt is
recorded so the asset can be remade rather than re-invented.

Run by `.claude/skills/visual-pass/SKILL.md`. Source files live in `assets/`.

## Status: empty

Nothing has been generated, uploaded or applied yet. The pipeline exists; the first visual pass has not
run. **An empty table means untouched, not verified-as-unnecessary.**

## Applied

| File | What it is | Applied to | Asset id | Source | Added |
| --- | --- | --- | --- | --- | --- |
| _(none yet)_ | | | | | |

`Source` is `generated` (with the prompt recorded below), `creator-store` (with the creator's name), or
`photo` for a reference that never entered the game.

## Prompts, for anything generated

Recorded so a lost asset can be remade rather than re-invented from a memory of what it looked like.
The house constraints — flat-on orthographic, no baked lighting, transparent background, name the wear —
are in `visual-pass` and are not repeated per row.

_(none yet)_

## References on disk

Real photos and Roblox screenshots in `assets/references/`, which never enter the game. Listed because
what Claude was shown is part of why a thing looks the way it does, and a reference deleted later makes
a past decision unreadable.

| Subject | Files | What it was for |
| --- | --- | --- |
| _(none yet)_ | | |
