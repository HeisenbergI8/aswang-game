--!strict
--[[
	SearchPool — is this map's tagged pool usable, and which names are actually distinct? (C07, V01)

		(names, required, expected) -> report

	WHY THIS IS A MODULE AND NOT AN `if #pool == 0 then warn()` IN THE SERVICE.

	The stub this chunk replaces refused to ship discovery for one stated reason: a service whose only
	observable behaviour is finding an empty pool is indistinguishable from a broken one. A warn() does
	not fix that — a warn is only as good as somebody reading the output window on the one run where it
	fires, and the run where it fires is the run where nothing else is working either. Making the
	verdict a pure function makes "the pool is empty" something a test asserts from a terminal. That is
	the difference between loud and merely noisy.

	WHY src/server/pure/ AND NOT src/shared/pure/ — and the argument is about the INPUTS, not the
	algorithm. Anything under `src/shared/` is replicated, so a client can require AND CALL it; that is
	fine for logic, which is never secret. It is not fine when a client can supply the inputs. The
	inputs here are the pool contents themselves — the full list of tagged names in the map — and a
	verdict on them is a thing the client renders nothing from and an exploiter reads a map index out
	of. Keeping the pool off the wire is the rule; this placement is that rule applied to the module
	that holds it. Lune resolves by file path, so none of this costs testability. RoleDraw is here for
	the same reason.

	NO `script.Parent` REQUIRES and no Roblox datatypes: names are plain strings so Lune can run this.
	The verdict union is re-declared locally; Luau unions are structural, so this type and
	Types.SearchPoolVerdict are the same type and pass to each other without a cast.
]]

export type Verdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"

export type Report = {
	Verdict: Verdict,
	Unique: { string },
	Duplicates: { string },
}

local SearchPool = {}

--[[
	PRECEDENCE IS BLOCKING-FIRST, and the order is the whole content of this function.

		EMPTY        no usable point at all — the map has no TaskPoint tags, or every one is a dupe
		SHORT        fewer distinct points than TotalRequired — the gate could never reach 5/5
		DUPLICATE_ID enough points, but two share a Name — the server cannot tell them apart
		OVERSIZED    more points than PoolSize expects — harmless, and a sign C17 left one behind
		OK

	SHORT OUTRANKS DUPLICATE_ID on purpose. Both are map defects; only one of them means the round is
	unwinnable. A reader who sees DUPLICATE_ID and fixes a name, then discovers the pool was also two
	points short, has been sent to the second-most-urgent problem first.

	`Duplicates` is returned on EVERY path, including OK, because the caller wants to name the offending
	parts in its log regardless of whether they blocked anything. `Unique` preserves discovery order,
	which is `GetTagged`'s order — see Step 2.2 for why the caller sorts it before drawing.
]]
function SearchPool.evaluate(names: { string }, required: number, expected: number): Report
	local seen: { [string]: boolean } = {}
	local unique: { string } = {}
	local duplicates: { string } = {}

	for _, name in names do
		if seen[name] then
			table.insert(duplicates, name)
		else
			seen[name] = true
			table.insert(unique, name)
		end
	end

	local count = #unique
	local verdict: Verdict = "OK"

	if count == 0 then
		verdict = "EMPTY"
	elseif count < required then
		verdict = "SHORT"
	elseif #duplicates > 0 then
		verdict = "DUPLICATE_ID"
	elseif count > expected then
		verdict = "OVERSIZED"
	end

	return { Verdict = verdict, Unique = unique, Duplicates = duplicates }
end

return SearchPool
