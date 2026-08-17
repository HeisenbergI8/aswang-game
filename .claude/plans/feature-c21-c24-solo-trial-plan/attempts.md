# Attempt ledger: `Types.TrialBeat` cannot be narrowed to inside `TrialService`

**Symptom (verbatim):**

```
src/server/Services/TrialService.luau [.../TrialService](388,23): TypeError: Expected this to be
	'"BEAT_HANDOFF" | "BEAT_SALT_GIVEN" | "BEAT_SALT_TAUGHT" | "BEAT_TASKS" | "BEAT_TRANSFORM" | "BEAT_WELCOME"'
but got
	'string | string | string | string | string | string'
caused by:
  Not all union options are compatible.
Expected this to be '"BEAT_HANDOFF" | ...', but got 'string'; none of the union options are compatible
```

**Reproduction:** `npm run analyze`

## Measurements (not fixes) — these are facts, not guesses

- Inside `TrialTimeline`, `due` is genuinely `{"BEAT_HANDOFF" | ... | "BEAT_WELCOME"}`. The literals are
  intact in the pure module. (Probed with `local probe: number = due`.)
- At the call site in `TrialService`, `due` is plain `string`. (Probed the same way.)
- After `local beat = (due :: string) :: Types.TrialBeat`, `beat` is
  `string | string | string | string | string | string`. (Probed the same way.)

**That third measurement is the finding.** Casting a plain `string` to a six-member literal union does
not produce the literal union — it produces a six-member union of plain `string`, i.e. the analyzer
distributes the cast across the union's options and widens every one. The value is unnarrowable
afterwards, and the error surfaces at the *use* site rather than at the cast.

| # | Hypothesis | Change made | Result |
| --- | --- | --- | --- |
| 1 | Element needs the documented pure-module cast | `local beat = due :: Types.TrialBeat` | FAIL — same error, moved lines |
| 2 | `AT`'s table literal widens its `beat` fields | `:: TrialBeat` on all six `AT` entries | FAIL — same error |
| 3 | The optional `at = nil` field splits `AT`'s element type | Extracted `type Entry`, cast each entry | FAIL — same error |
| 4 | Luau needs an upcast before a downcast | `(due :: string) :: Types.TrialBeat` | FAIL — same error |
| 5 | A list of a literal union does not survive `require` | Declared `dueBeats(): { string }` | FAIL at call site (did fix the module side) |
| 6 | Arrays are invariant, so the local must match | `local due: { string }` | Fixed the module; call site unchanged |
| 7 | Casting to `Types.X` differs from a local alias (RoundService precedent) | `type TrialBeat = Types.TrialBeat`, cast to alias | FAIL — same error |
| 8 | Multi-line union declarations widen; single-line ones do not | Rewrote `Types.TrialBeat` on one line | FAIL — same error. **Reverted.** |

Hypotheses 1, 2, 3, 4, 7 and 8 are all the same shape underneath: *find the spelling of a cast that
Luau will accept*. Six spellings is enough to conclude the cast form is not the variable.

## Where the ladder goes next

Rung 3 — shrink the surface. `RoundService` performs a structurally identical cast
(`resolved :: PlayerState`, a four-member literal union out of `pure/RejoinResolve`) and analyzes
clean, so the difference between that call and this one is the thing to isolate, rather than another
spelling.

The candidate difference: `RejoinResolve.evaluate` returns a **scalar** literal union, and this
returns a **list** of one. `phaseAt`'s scalar `TrialPhase` crosses the same boundary in the same file
and casts in one step with no complaint — which is consistent, and is the strongest evidence that the
list is the variable rather than anything about `TrialBeat` itself.

## Resolution

**Root cause, measured:** a LIST of a literal union does not keep its literals across `require` in this
repo's analyzer, though a SCALAR does — `phaseAt`'s `TrialPhase` casts in one step twenty lines away
from the code that could not be made to work. Once the elements arrive as plain `string`, `::` cannot
narrow them back: it distributes across the union's options and yields
`string | string | string | string | string | string`, which is unnarrowable and reports at the *use*
site, not at the cast. That displaced error is why six spellings of the cast all looked plausible.

**Fix:** `TrialTimeline.dueBeats` declares `{ string }` honestly, and `TrialService.asBeat` narrows one
id at a time through a six-branch `if` whose literals are written directly in `return` position, where
the analyzer will do the narrowing. It is called inline at the payload — `Beat = asBeat(beat)` — which
is the only place the literal type is actually required.

**Better than the cast it replaced,** rather than a workaround with a cost: an id the timeline emits and
`asBeat` does not know about returns `nil` and is dropped with a `warn`, where every cast form would
have waved a bad id straight into a client payload.

**What was reverted:** the single-line `Types.TrialBeat` (attempt 8) and the two dead local aliases from
attempt 7. Nothing speculative was left in the tree.

**Lesson candidate:** this is worth `/lessons-review` attention — it cost more than an hour, the error
message points at the wrong file, and the next pure module returning a list of a literal union will hit
it identically.
