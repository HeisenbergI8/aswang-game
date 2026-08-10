#!/usr/bin/env node
// Regression suite for `guard-destructive.mjs`.
//
//   node .claude/scripts/tests/guards.test.mjs
//
// ── THE ALLOW HALF IS THE IMPORTANT HALF ───────────────────────────────────────
//
// Proving a guard can refuse is the cheap half. The expensive failure is refusing CORRECT commands
// until somebody switches the guard off — and then it protects nothing at all. This suite therefore
// carries more allow cases than block cases, and several of them are shapes that a naive version of
// this guard genuinely did refuse: an arrow function inside `node -e`, a `->` in a string, an escaped
// quote inside a sed script, a grep whose PATTERN mentions a dangerous command.
//
// `judge()` is imported rather than re-implemented, so the test drives the identical decision the hook
// makes. A suite that reproduces the logic tests the reproduction.

import { judge } from '../guard-destructive.mjs'

let failures = 0
let ran = 0

const check = (label, command, shouldBlock) => {
  ran += 1

  const blocked = judge(command) !== null

  if (blocked === shouldBlock) return

  failures += 1
  console.log(`  FAIL  ${label} — expected ${shouldBlock ? 'BLOCK' : 'ALLOW'}: ${command.slice(0, 80)}`)
}

// ── BLOCK: destruction reaching outside the repo ───────────────────────────────
check('rm in the home directory', 'rm -rf ~/Documents', true)
check('rm at the filesystem root', 'rm -rf /', true)
check('rm of the git directory', 'rm -rf .git', true)
check('rm via an absolute outside path', 'rm -rf /Users/someone/Desktop/other-project', true)
check('mv out of the repo', 'mv src/shared/Config.luau ~/Config.luau', true)
check('a relative climb out of the repo', 'rm -rf ../../other-project', true)
check('cd out, then delete', 'cd ~/Desktop && rm -rf stuff', true)
check('cd out via a relative path, then delete', 'cd ../other && rm -rf src', true)
check('git -C on another repository', 'git -C ~/other-repo clean -fd', true)
check('a redirect into the home directory', 'echo hi > ~/notes.txt', true)
check('a redirect to an absolute outside path', 'npm run verify > /Users/someone/out.log', true)
check('a shell variable whose value cannot be checked', 'T=~/Documents && rm -rf $T', true)
check('xargs rm, whose targets arrive on stdin', 'find . -name "*.tmp" | xargs rm', true)
check('an interpreter carrying a deletion', 'node -e "require(\'fs\').rmSync(process.env.HOME, {recursive:true})"', true)
check('a fork bomb', ':(){ :|:& };:', true)
check('sudo, ever', 'sudo rm -rf /tmp/x', true)
check('rsync --delete', 'rsync -a --delete src/ ../backup/', true)
check('find -delete', 'find . -name "*.luau" -delete', true)
check('find -exec rm', 'find . -name "*.tmp" -exec rm {} \\;', true)

// ── BLOCK: in-repo commands that destroy work irrecoverably ────────────────────
check('git clean -fd', 'git clean -fd', true)
check('git clean -fdx, which would take the harness with it', 'git clean -fdx', true)
check('git reset --hard', 'git reset --hard origin/main', true)
check('git checkout -- .', 'git checkout -- .', true)
check('git restore .', 'git restore .', true)
check('removing the repository root', 'rm -rf .', true)

// A KNOWN CONSERVATIVE LIMIT, pinned so it is a decision rather than a surprise. Every path is
// resolved against the REPOSITORY ROOT, not against the working directory a `cd` established — the
// guard cannot execute the command to find out where it ends up. So `cd src && rm -rf ../build` is
// refused even though it targets `build/` inside the repo.
//
// Left as-is rather than "fixed" by tracking cwd: guessing the effective directory of a shell string is
// exactly the reasoning that lets `cd ~ && rm -rf Documents` through. Write destructive paths from the
// repository root and the ambiguity does not arise.
check('a relative delete after cd, which cannot be resolved safely', 'cd src && rm -rf ../build', true)

// ── BLOCK: repo-specific — the map is not in Git ───────────────────────────────
check('deleting a place file', 'rm ASWANG.rbxl', true)
check('deleting a place file by path', 'rm -f places/dev.rbxlx', true)

// ── ALLOW: ordinary work, and the shapes a blunter guard refused ───────────────
check('running the gate', 'npm run verify', false)
check('running the analyzer', 'npm run analyze', false)
check('rojo serve', 'rojo serve', false)
check('building a place', 'rojo build default.project.json --output build/aswang.rbxl', false)
check('formatting', 'stylua src tests', false)
check('linting', 'selene src', false)
check('a lune test', 'lune run tests/config.test.luau', false)
check('deleting build output inside the repo', 'rm -rf build', false)
check('deleting a temp file', 'rm /tmp/scratch.json', false)
check('moving a file within the repo', 'mv src/shared/Old.luau src/shared/New.luau', false)
check('git status', 'git status --porcelain', false)
check('git log', 'git log -5', false)
check('git stash, which is the recoverable form', 'git stash push -m "wip"', false)
check('git restore --staged, which discards nothing', 'git restore --staged sourcemap.json', false)
check('a redirect into the repo', 'npm run verify > build/verify.log', false)
check('a redirect to /dev/null', 'npm run lint > /dev/null 2>&1', false)
check('grepping for a dangerous command as TEXT', 'grep -rn "git clean" docs/', false)
check('grepping for rm -rf in the harness', 'grep -rn "rm -rf" .claude/scripts/', false)
check('an arrow function inside node -e', 'node -e "const f = x => x + 1; console.log(f(1))"', false)
check('a comparison operator inside a string', 'node -e "console.log(1 >= 0)"', false)
check('an arrow in a quoted string', 'echo "a -> b"', false)
check('an escaped quote inside a sed script', 'sed -i "" "s/\\"a\\"/\\"b\\"/" src/x.luau', false)
check('reading a file', 'cat package.json', false)
check('listing the tree', 'ls -la src/server/Services', false)
check('a harness self-test', 'node .claude/scripts/check-secrecy.mjs --self-test', false)
check('cd within the repo, then read', 'cd src/server && ls', false)
check('deleting build output by its path from the root', 'rm -rf build', false)
check('curl of the type definitions', 'curl -sL -o .luau-defs/globalTypes.d.luau https://example.com/g.luau', false)
check('rokit install', 'rokit install', false)

console.log(failures ? `  FAIL  guards: ${ran - failures}/${ran}` : `  PASS  guards: ${ran}/${ran} cases`)
process.exit(failures ? 1 : 0)
