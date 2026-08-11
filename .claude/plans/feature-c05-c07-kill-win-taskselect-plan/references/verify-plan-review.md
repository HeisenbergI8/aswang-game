# `.claude/scripts/verify-plan.mjs` — review

Read to design the `**Verify:**` lines so the plan can drive a loop rather than halt one.

## Check shape — `verify-plan.mjs:172-178`

```js
export const shape = command => {
  if (!command) return 'none'
  if (/^\s*test\s+-[fde]\s/.test(command)) return 'exists'
  if (/^\s*grep\s/.test(command)) return 'self'

  return 'real'
}
```

**IMPORTANT** — `grep` is classified `self` and `test -f` is `exists`; both count as *weak*. Everything
else is `real`. The plan has **20 steps, 19 real and 1 `test -f`** (Step 1.1's Studio probe), which is
95% discriminating.

## The hard gate — `verify-plan.mjs:150-160, 423`

```js
const STRICT_MIN_REAL = 0.5
...
if (strict && checkable > 0 && tally.real < checkable * STRICT_MIN_REAL) { /* exit 2 */ }
```

**IMPORTANT** — `--strict` exits **2** when under half the checkable steps discriminate, and the task
loop runs it at run start. A plan that trips this halts before a single phase is attempted. At 19/20
there is a wide margin.

## Duplicates are per-phase, not per-plan — `verify-plan.mjs:180-196`

```js
const phaseOf = step => step.id.split(' ')[1]?.split('.')[0]
const key = `${phaseOf(step)}::${step.command}`
```

**IMPORTANT** — this is the rule the plan is shaped around. Two identical commands **in one phase** are
reported as `shared`, the second is SKIPped, and a phase containing a SKIP reports `needs-human`, which
halts the run. The same command closing two *different* phases is explicitly fine (`:189-193`) and is
called "a correct and deliberate idiom".

So: `npm run analyze` appears as the check for Steps 1.2, 3.1, 4.1, 5.1 and 6.1 — five different phases,
zero duplicates. Within each phase every command is distinct. Verified: `--lint` reports
`20 steps · 0 unrunnable · 0 unverifiable · 0 shared · 0 unsatisfiable · 0 phase(s) would report needs-human`.

## Per-phase confidence — `.claude/scripts/next-phase.mjs:216-251`

```js
const LOW_CONFIDENCE_RATIO = 0.66
...
const lowConfidence = executed.length > 0 && weak > executed.length * LOW_CONFIDENCE_RATIO
if (passed === list.length) status = lowConfidence ? 'low-confidence' : 'done'
```

**IMPORTANT** — measured **per phase**, deliberately, because "a strong plan carrying one all-grep
phase averages out above the threshold and the cursor walks straight through the phase nobody checked".
`low-confidence` is treated exactly like `needs-human` by the driver — it halts. Phase 1 is the only
phase with a weak check, at 1 of 4 (0.25), well under 0.66.

## A step with no `**Verify:**` line

**IMPORTANT** — reported as `unverifiable`, and `next-phase.mjs` marks the phase `needs-human`, which
halts the run. That is the right outcome for a genuinely unprovable step and the wrong one here: the
plan has to drive eight iterations. Step 1.1's deliverable is therefore a *written finding file*, gated
on `test -f`, which can genuinely fail (the file does not exist until the probe is run) and is honest
about proving only that the probe was done.

## The step pattern — `verify-plan.mjs:118-135`

```js
const verify = body.match(/^\*\*Verify:\*\*\s*`(.+?)`\s*$/m)
```

**NOTE** — the line must be `**Verify:** \`command\`` on its own line, and fenced blocks are stripped
before matching (`:99-116`). An **unterminated fence blanks every line after it**, so the steps below it
silently stop existing and the plan reports a smaller, entirely green step count. The plan's 20 steps
parsing correctly is itself evidence that no fence is left open.
