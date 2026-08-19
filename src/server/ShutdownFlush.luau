--!strict
--[[
	ShutdownFlush — the one place work registers itself to run before the server dies. (C31, §6.4)

	§6.4's fifth edge case: "Server shutdown → `game:BindToClose()` must flush all player data."
	`RoundService` owns the single `BindToClose` binding (see its `onServerClosing`), and this module
	is how anything else gets onto that path WITHOUT RoundService requiring it — which would close a
	require cycle, because the services that need flushing also subscribe to `PhaseChanged`.

	IT IS NOT A BindableEvent. `BindableEvent:Fire` resumes each handler on its own thread and returns
	the moment one yields, so a yielding flush would let `BindToClose` return with its writes still in
	flight. These callbacks are CALLED, in order, on the closing thread, so a handler that yields is
	one Roblox waits for.

	WHAT ACTUALLY KEEPS THE PROCESS ALIVE TODAY IS NOT THIS MODULE — READ THIS BEFORE ADDING A HANDLER.
	`Profile:EndSession()` does NOT yield: it is `task.spawn(SaveProfileAsync, ...)`
	(`vendor/ProfileStore.luau:1090`). So the only handler registered today returns in microseconds, the
	budget below is never approached, and "flush complete" prints while the writes are still going. No
	data is lost, because ProfileStore registers its OWN `game:BindToClose` (`vendor:2208-2239`) which
	yields until its save jobs drain, and Roblox waits for both bindings.

	That is a guarantee for PROFILES, from a vendored file — not a property of this registry. A handler
	registered here that spawns its own work and returns will NOT be waited for by anything. Either
	yield until your work is done, or do not register it.

	NOT A SERVICE. It lives beside `Services/` rather than inside it precisely so `init.server.luau`'s
	loader, which walks `SERVICE_ORDER` inside that folder, never tries to `Init`/`Start` it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ShutdownFlush = {}

type Handler = {
	Name: string,
	Flush: () -> (),
}

local handlers: { Handler } = {}

--[[
	Registration happens in a service's `Start()`. Order is registration order, and callers should not
	depend on it: if two flushes must be sequenced, that is one flush with two steps inside it.
]]
function ShutdownFlush.register(name: string, flush: () -> ())
	table.insert(handlers, { Name = name, Flush = flush })
end

--[[
	Roblox allows roughly 30 seconds inside `BindToClose` and then kills the process mid-write, so the
	budget is checked BETWEEN handlers. It cannot interrupt one that is already running — nothing can,
	short of abandoning a DataStore call in flight — but it stops a stuck first handler from consuming
	the window that the rest needed. `Config.Profile.ShutdownFlushBudget` is pinned below 30 in
	`tests/config.test.luau`.

	With one non-yielding handler registered, this deadline is currently unreachable. It is kept because
	it costs nothing and because the FIRST yielding handler is exactly when it starts mattering.
]]
function ShutdownFlush.flushAll()
	local deadline = os.clock() + Config.Profile.ShutdownFlushBudget

	for _, handler in handlers do
		if os.clock() > deadline then
			warn(`[ShutdownFlush] budget exhausted before {handler.Name} ran`)
			continue
		end

		-- `:: any` because `pcall` over a `() -> ()` is typed as returning only the boolean, so
		-- binding `err` is an arity error under --!strict. Same bite as `init.server.luau:93-95`.
		local ok, err = pcall(handler.Flush :: any)

		if not ok then
			warn(`[ShutdownFlush] {handler.Name} errored: {err}`)
		end
	end
end

return ShutdownFlush
