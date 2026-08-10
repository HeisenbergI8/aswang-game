#!/usr/bin/env node
// PreToolUse guard on the Roblox Studio MCP tools: refuses to let an agent EDIT SCRIPTS INSIDE STUDIO.
//
// ── THE GOLDEN RULE, MADE MECHANICAL ───────────────────────────────────────────
//
// README.md states it in prose:
//
//   > Files on disk are the source of truth. Studio is the renderer.
//   > Never let Claude edit scripts directly inside Studio via MCP while Rojo is connected — the next
//   > sync will overwrite them and the work is gone.
//
// That is a rule with real teeth and no enforcement. Rojo two-way sync means a script written into
// `ServerScriptService.Server` is destroyed the next time a file under `src/server/` is saved — with no
// error, no diff, and no way to recover it, because it never existed on disk. An agent that spends
// twenty minutes writing a service inside Studio loses all of it and cannot tell you why.
//
// It is also a rule an agent will break in good faith. `multi_edit` and `execute_luau` are exactly the
// tools it reaches for when Studio is open, and from inside Studio the write LOOKS like it worked.
//
// ── WHAT IS STILL ALLOWED, AND WHY THAT MATTERS MOST ───────────────────────────
//
// Everything that makes Studio useful: inspecting instances, searching the game tree, reading console
// output, pressing Play, capturing the screen, generating meshes and materials, inserting assets. Those
// are how the `playtester` agent produces the artifacts `goal-check.mjs` demands, and blocking them
// would remove the one piece of real behavioural evidence this repo has.
//
// So the guard is narrow by construction: it denies WRITES TO SCRIPT SOURCE, and nothing else.

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const deny = reason => {
  process.stdout.write(
    `${JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: reason
      }
    })}\n`
  )
  process.exit(0)
}

// Studio classes whose Source property Rojo owns in this project. Anything else — a Part, a Light, an
// Atmosphere, a Sound — lives in the place file, is NOT synced, and is legitimately edited in Studio.
// That is the map, and the map is deliberately outside Git.
const SCRIPT_CLASSES = /\b(Script|LocalScript|ModuleScript)\b/i

// The three Rojo-managed roots, from default.project.json. A write anywhere under these is overwritten
// on the next sync; a write elsewhere in the DataModel is not.
export const SYNCED_ROOTS = [
  'ServerScriptService.Server',
  'ReplicatedStorage.Shared',
  'StarterPlayer.StarterPlayerScripts.Client'
]

const WRITE_TOOLS = /^mcp__Roblox_Studio__(multi_edit|script_(write|edit|set_source))$/

export const judge = payload => {
  const tool = payload?.tool_name ?? ''
  const input = payload?.tool_input ?? {}
  const asText = JSON.stringify(input)

  if (WRITE_TOOLS.test(tool)) {
    return (
      `Blocked: \`${tool}\` writes script source inside Studio, and Rojo owns that source.\n\n` +
      `The next time any file under src/ is saved, Rojo overwrites what you just wrote — silently, with ` +
      `no diff and nothing to recover, because it never existed on disk. README.md: "Files on disk are ` +
      `the source of truth. Studio is the renderer."\n\n` +
      `Edit the file under src/ with Write/Edit instead. Rojo pushes it into Studio in under a second.\n\n` +
      `Studio MCP remains fully available for everything it is actually for: inspect_instance, ` +
      `search_game_tree, get_console_output, start_stop_play, screen_capture, generate_mesh, ` +
      `insert_asset. Those produce the artifacts the playtester's report has to cite.`
    )
  }

  // `execute_luau` is the interesting case: it is the playtester's most valuable tool AND the easiest
  // way around this guard. Reading state, probing a service, or firing a test event is exactly what it
  // is for. Assigning `.Source` on a synced script is not, and that is a shape a regex can see.
  if (tool === 'mcp__Roblox_Studio__execute_luau') {
    const code = typeof input.code === 'string' ? input.code : asText
    const writesSource = /\.Source\s*=/.test(code)
    const createsScript = /Instance\.new\s*\(\s*["'](Script|LocalScript|ModuleScript)["']/.test(code)

    if (writesSource || createsScript) {
      return (
        `Blocked: this Luau would ${writesSource ? 'assign a script\'s .Source' : 'create a new Script instance'} ` +
        `inside Studio, which Rojo overwrites on the next sync.\n\n` +
        `If you are testing behaviour, call the existing module instead of rewriting it. If you are ` +
        `adding code, add it under src/ — that is the only place it survives.\n\n` +
        `execute_luau is otherwise allowed and is the right tool for probing live state.`
      )
    }
  }

  // A generic instance write targeting a script under a synced root.
  //
  // No tool with this exact shape ships in the Studio MCP server today — `multi_edit` is the one that
  // writes source, and it is handled above. This branch exists because the server's tool list grows,
  // and a new write tool arriving is precisely the moment this guard would otherwise fall silent
  // without anyone noticing. Matching on the PAYLOAD (a script class plus a Source assignment under a
  // Rojo-managed root) rather than on a tool name is what makes it survive that.
  if (tool.startsWith('mcp__Roblox_Studio__') && SCRIPT_CLASSES.test(asText) && /"?Source"?\s*[:=]/.test(asText)) {
    const synced = SYNCED_ROOTS.find(root => asText.includes(root))

    if (synced) {
      return (
        `Blocked: this sets Source on a script under \`${synced}\`, which Rojo syncs from src/. The next ` +
        `sync overwrites it. Edit the file on disk instead.`
      )
    }
  }

  return null
}

if (process.argv[1]?.endsWith('guard-studio-sync.mjs')) {
  if (process.argv.includes('--self-test')) {
    let failures = 0
    let ran = 0

    const check = (label, payload, shouldBlock) => {
      ran += 1

      const blocked = judge(payload) !== null

      if (blocked === shouldBlock) return

      failures += 1
      console.log(`  FAIL  ${label} — expected ${shouldBlock ? 'BLOCK' : 'ALLOW'}, got ${blocked ? 'BLOCK' : 'ALLOW'}`)
    }

    // BLOCK — every one of these loses work on the next Rojo sync.
    check('multi_edit into Studio', { tool_name: 'mcp__Roblox_Studio__multi_edit', tool_input: {} }, true)
    check(
      'execute_luau assigning Source',
      { tool_name: 'mcp__Roblox_Studio__execute_luau', tool_input: { code: 'script.Parent.Source = "print(1)"' } },
      true
    )
    check(
      'execute_luau creating a script',
      { tool_name: 'mcp__Roblox_Studio__execute_luau', tool_input: { code: 'local s = Instance.new("ModuleScript")' } },
      true
    )
    check(
      'a generic write to a synced script',
      {
        tool_name: 'mcp__Roblox_Studio__set_property',
        tool_input: { path: 'ServerScriptService.Server.Services', className: 'ModuleScript', Source: 'x' }
      },
      true
    )

    // ALLOW — the larger half, deliberately. These are how the playtester earns its artifacts, and a
    // guard that blocked them would be switched off within a day.
    check('inspecting an instance', { tool_name: 'mcp__Roblox_Studio__inspect_instance', tool_input: { path: 'Workspace' } }, false)
    check('reading the console', { tool_name: 'mcp__Roblox_Studio__get_console_output', tool_input: {} }, false)
    check('pressing Play', { tool_name: 'mcp__Roblox_Studio__start_stop_play', tool_input: { play: true } }, false)
    check('capturing the screen', { tool_name: 'mcp__Roblox_Studio__screen_capture', tool_input: {} }, false)
    check('searching the game tree', { tool_name: 'mcp__Roblox_Studio__search_game_tree', tool_input: { query: 'Aswang' } }, false)
    check(
      'reading a script rather than writing it',
      { tool_name: 'mcp__Roblox_Studio__script_read', tool_input: { path: 'ServerScriptService.Server' } },
      false
    )
    check(
      'probing live state with execute_luau',
      { tool_name: 'mcp__Roblox_Studio__execute_luau', tool_input: { code: 'return #game.Players:GetPlayers()' } },
      false
    )
    check(
      'calling a service to test it',
      {
        tool_name: 'mcp__Roblox_Studio__execute_luau',
        tool_input: { code: 'local R = require(game.ServerScriptService.Server.Services.RoundService)\nreturn R.GetPhase()' }
      },
      false
    )
    check('generating a mesh for the map', { tool_name: 'mcp__Roblox_Studio__generate_mesh', tool_input: { prompt: 'bahay kubo' } }, false)
    check('inserting a Creator Store asset', { tool_name: 'mcp__Roblox_Studio__insert_asset', tool_input: { assetId: 123 } }, false)
    check(
      'setting a property on a MAP object, which Rojo does not own',
      { tool_name: 'mcp__Roblox_Studio__set_property', tool_input: { path: 'Lighting', className: 'Atmosphere', Density: 0.4 } },
      false
    )
    check('an ordinary Write tool call is not this guard\'s business', { tool_name: 'Write', tool_input: { file_path: 'src/x.luau' } }, false)

    console.log(failures ? `  FAIL  guard-studio-sync: ${ran - failures}/${ran}` : `  PASS  guard-studio-sync: ${ran}/${ran} cases`)
    process.exit(failures ? 1 : 0)
  }

  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  const verdict = judge(payload)

  if (verdict) deny(verdict)

  process.exit(0)
}
