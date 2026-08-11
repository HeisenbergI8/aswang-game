# `.claude/scripts/check-secrecy.mjs` — review

Read to answer one question: **would this gate catch a killer field on `PlayerKilled`?** It would not.
That answer is Issues Found row 1 in the plan.

## The call allowlist — `check-secrecy.mjs:39-42`

```js
export const REVEAL_ALLOWLIST = new Map([
  ['RoundEnded', 'the round is over — the reveal is the point (spec §4.8)'],
  ['RoleAssigned', 'fired to exactly one player, carrying only that player\'s OWN role (spec §4.2)']
])
```

**NOTE** — two entries, and this plan adds none. `PlayerKilled` does not carry a role and must not be
allowlisted; being off this list is correct.

## The field allowlist, and the exact reason it does not help here — `check-secrecy.mjs:56-62`

```js
export const PAYLOAD_FIELDS = new Map([
  ['RoundEnded', new Set(['Result', 'AswangUserId', 'RoundNumber'])],
  ...
```

**IMPORTANT** — the field check is driven off `REVEAL_ALLOWLIST`, not off `PAYLOAD_FIELDS`:

```js
// check-secrecy.mjs:186
if (!remote || !REVEAL_ALLOWLIST.has(remote)) continue
```

So adding `PlayerKilled` to `PAYLOAD_FIELDS` alone would change nothing — `strayFields` also returns
`[]` for any remote absent from the map (`:118-124`). Getting `PlayerKilled`'s fields checked requires
iterating over `PAYLOAD_FIELDS` instead, which is a guard change with a both-direction self-test
obligation (`harness-selftest.mjs`'s `SUITES`). **Out of this plan's scope, and recorded as High.**

## The token regex — `check-secrecy.mjs:127-129`

```js
const SECRET = /\b(aswang|imposter|impostor|monsteruserid|iskiller|isaswang|aswanguserid|secretrole)\b/i
const ROLE_TOKEN = /\b(role|roles)\b/i
```

**IMPORTANT** — this is the general scan that runs on *every* `FireAllClients`, allowlisted or not. It
matches `IsKiller`. It does **not** match `KillerUserId`, `KillerName`, or `Killer`. Combined with the
above, a `KillerUserId` field on `PlayerKilled` would:

- typecheck (Luau silently accepts an extra field on an annotated table — `Types.luau:57-75`),
- pass the field check (never runs on this remote),
- pass the token scan (no match),

and reach eight clients with `npm run verify` green. This is the single most valuable field an attacker
could ask for and no automated gate in this repo would object. `exploit-auditor` is the only thing
between it and a release, which is why the plan names that agent as mandatory on Phase 4 and repeats the
warning in three places in the source.

## Why a payload built as a typed local is followed backwards — `check-secrecy.mjs:86-92`

```
//    :FireAllClients({ Result = r })                  -> read inline
//    local payload: T = { ... } ; :FireAllClients(payload) -> follow the local BACKWARDS
```

**NOTE** — the window is 1200 characters (`:107`). The plan's `commitKill` builds its payload two lines
above the fire, well inside it. Worth knowing that a payload assembled further away than that is
invisible to the scanner even on an allowlisted remote.

## The remote-name resolution — `check-secrecy.mjs:146-160`

```js
const match = /Remotes\.Get\(\s*["']([\w]+)["']\s*\)\s*$/.exec(window)
```

**NOTE** — the name is resolvable only when `Remotes.Get("X")` is written inline at the call. Both
`MonsterService` remotes are held in module locals (`transformedRemote`, and the plan's `killedRemote`),
so the name is unknown at the fire site. The comment at `:222-224` says an unknown name is **not**
allowlisted, which is the conservative direction — but since `PlayerKilled` is not allowlisted anyway,
this changes nothing for this plan. It would matter if someone later tried to allowlist it.
