# Artifact — the secrecy premise: does a client-created `workspace` part reach the server?

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode, round ACTIVE. This is the single most
important check in the V09 run: `GarlicController`'s entire secrecy argument rests on this being true.
If it is false, garlic barriers are a role oracle and V09 must not ship.

## Client side — create the probe

```lua
-- execute_luau, datamodel_type = "Client"
local part = Instance.new("Part")
part.Name = "REPLICATION_PROBE_V09"
part.Anchored = true
part.Size = Vector3.new(4, 4, 4)
part.CFrame = CFrame.new(0, 200, 0)
part.Parent = workspace
```

Result: `"created Workspace.REPLICATION_PROBE_V09"` — the part exists on the client's own `workspace`.

## Server side — look for it

```lua
-- execute_luau, datamodel_type = "Server"
local found = workspace:FindFirstChild("REPLICATION_PROBE_V09")
return {found = found ~= nil, workspaceChildCount = #workspace:GetChildren()}
```

Result:

```json
{"found":false,"workspaceChildCount":9}
```

**The server's own `workspace` does not contain the part the client created**, and its own `workspace`
has only 9 direct children (the barrio root, camera-adjacent folders, etc — none of them the probe).
This is a direct DataModel read via `execute_luau`, not a require of a live service, so the
require-cache trap CLAUDE.md warns about does not apply here — `workspace` is the same Instance tree in
both calls, and the server's copy of it genuinely lacks the part.

## Verdict

**CONFIRMED.** A `Part` created by client-side `execute_luau` code under `workspace` is invisible to the
server. This is exactly the behaviour `GarlicController`'s header claims and depends on. The mechanism
`ItemService`/`GarlicController` uses for the block is not a secrecy failure by this evidence.

Caveat: this proves non-replication to the SERVER. It does not by itself prove non-replication to OTHER
CLIENTS, which needs a second connected player (see the "Not Verified" section of the main report) — but
the underlying Roblox mechanism (client-created instances stay local to the creating client, full stop)
is the same one, and nothing about the barrier's construction differs between the two audiences.
