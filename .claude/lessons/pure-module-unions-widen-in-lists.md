---
id: pure-module-unions-widen-in-lists
trigger: pure module, literal union, string union, cast, "none of the union options are compatible", TrialTimeline, dueBeats, analyze error, Expected this to be
scope: luau
learned: 2026-08-17
evidence: C21's TrialTimeline.dueBeats cost 8 failed fixes and over an hour; every error pointed at TrialService, and the module the fix belonged in was never named by the analyzer
---

**Lesson:** A literal union survives `require` as a SCALAR and does not survive it inside a LIST. The
element arrives as a union of plain `string`s, `::` cannot narrow it back, and the analyzer reports the
failure at the CALL SITE — so every error names the wrong file, and the eight obvious fixes are all
spelled at the wrong end.

**Why:** `TrialTimeline.dueBeats` returned `{ TrialBeat }`. Inside the module the literals were intact —
measured with `local probe: number = due`. At the call site the same value read
`string | string | string | string | string | string`, and `x :: Types.TrialBeat` fails with *"none of
the union options are compatible"* because Luau distributes the cast and widens every option. Twenty
lines away, `phaseAt`'s SCALAR union crossed the identical boundary and cast in one step — which is what
made the list look innocent.

Eight fixes failed, so nobody re-walks them: casting the element; `:: T` on every source-table entry; an
extracted `Entry` type; `(x :: string) :: T`; a local `type X = Types.X` alias (works for scalars); a
`{ [string]: T }` lookup (that type resolves to plain `string` in a table-VALUE annotation); the union on
one line. Six are one hypothesis — *find the spelling Luau accepts* — and six is enough to conclude
spelling is not the variable.

**Do:**
- **Return `{ string }` and narrow with a FUNCTION, not a cast.** A literal in a `return`, checked
  against an annotated return type, is narrowing the analyzer will do — and it beats the cast, since an
  unknown id returns `nil` to drop with a `warn` where a cast waves it into a client payload.
- **When an error names a file, check whether the value was BORN there.** Three
  `local probe: number = x` probes — producer, boundary, after the cast — found this in minutes.
- **Scalars are fine.** Do not restructure a pure module that returns one value.
