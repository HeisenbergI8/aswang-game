# Step 7.1 — the `TextChatService` spike (partial: Edit mode only)

**Run:** 2026-08-14, Studio Edit mode, Rojo connected. Everything below is measured, not documented.

This probe was specified because ghost chat is the surface where being wrong ends rounds rather than
degrading them, and `GhostService` was written entirely against documentation.

## Answers

### Q1 — is `ChatVersion` the modern service? ✅ YES

```
ChatVersion = Enum.ChatVersion.TextChatService
CreateDefaultTextChannels = true
CreateDefaultCommands = true
```

**This closes the worst open question.** `GhostService.configureChannels` warns and returns under
`LegacyChatService`, which would have left every ghost talking to every living player for the life of
the server — a round-ending condition behind one warn, invisible to every check in the repo because
`ChatVersion` lives in the place file and the place file is not in Git.

It is `TextChatService`. **Note this is a per-place setting: it is true for THIS place and guarantees
nothing about any other**, which is exactly why the warn stays.

### Q2 — do the default channels exist when `Start()` runs? ⚠️ THE RACE IS REAL

```
TextChannels present at EDIT time = false
```

`TextChatService.TextChannels` does **not** exist at edit time; the default channels are created at
runtime. `configureChannels` calls `FindFirstChild("TextChannels")` with no `WaitForChild`.

Edit-time absence does not prove absence at server `Start()` — that needs a Play-mode re-check — but it
does prove the folder is created dynamically, which is the precondition for the race. **The
`ChildAdded` fallback added after the last audit is doing real work, not defensive work.** Without it,
a server that started before the channels existed would run the whole round with no delivery guard
attached and one warn line as the only symptom.

### Q3 — can layer 3's mechanism actually be installed? ✅ YES

```
ASSIGN ShouldDeliverCallback = true
ASSIGN OnIncomingMessage     = true
AddUserAsync type            = function
PARENT TextChannel to TextChatService = true
```

Reading `ShouldDeliverCallback` **errors** ("not a valid member" on read) while assigning it succeeds —
Roblox callbacks are write-only. That is worth recording because the obvious defensive pattern
(`if channel.ShouldDeliverCallback == nil then`) would throw rather than guard.

Layer 2's `AddUserAsync` exists and channels parent correctly.

### Q4 — is `TextSource` membership client-visible? ⚠️ PARTIALLY ANSWERED, AND THE AUDIT'S PREMISE IS WRONG

```
TextChannel.GetTextSource -> NOT a valid member of TextChannel
TextSource is constructible = false ("Unable to create an Instance")
```

The exploit audit raised a **Critical** on the theory that a living client could call
`RBXGeneral:GetTextSource(userId)`, get nil for exactly the dead, and enumerate them — meaning layer 1
would leak the thing it protects.

**That method does not exist**, so the attack as described is not available. The concern is downgraded
but **not closed**: `TextSource` instances are engine-created children of a `TextChannel`, and whether
those children replicate to clients — making `channel:GetChildren()` an enumeration — is still open and
needs a two-client Play-mode test.

If they do replicate, the fix stands as the audit described it: layer 1 becomes "revoke `CanSend`"
rather than "destroy the source" — same enforcement, no observable delta.

## Still unanswered — needs Play mode with two clients

1. Does `ShouldDeliverCallback` returning `false` actually **suppress delivery**, or is it advisory?
   This is the entire load of layer 3 and it is unmeasured.
2. Does destroying a `TextSource` actually remove the user from the channel (layer 1)?
3. Do `TextSource` children replicate to clients? (Q4's remainder.)
4. Does Roblox re-add a `TextSource` on respawn — and since C15 a dead player keeps their corpse as
   their character, does the corpse count as a respawn for that purpose?

## Verdict for the implementation

Two of `GhostService`'s three layers have **confirmed mechanisms**. The third (layer 1) has a confirmed
`AddUserAsync` but an unconfirmed removal. The catastrophic `LegacyChatService` case does not apply to
this place. The `ChildAdded` race guard is justified by measurement.

**Ghost chat still cannot be called enforced** until item 1 above is tested with two clients, because
"a ghost's message did not appear" and "chat is broken" look identical from one screen.
