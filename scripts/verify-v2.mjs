import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { collectPreflight, printPreflight } from './v2-preflight.mjs'

const requireDatabase = process.argv.includes('--require-db')
const report = collectPreflight()
printPreflight(report)
const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

function run(label, command, args) {
  process.stdout.write(`VERIFY_GATE: ${label}\n`)
  const result = spawnSync(command, args, { cwd: projectRoot, stdio: 'inherit' })
  if (result.error !== undefined || result.status !== 0) {
    process.stdout.write(`${label}: FAIL\n`)
    return false
  }
  process.stdout.write(`${label}: PASS\n`)
  return true
}

function runNpm(label, script) {
  if (process.platform === 'win32') {
    return run(label, process.env.ComSpec ?? 'cmd.exe', [
      '/d', '/s', '/c', `npm run ${script}`,
    ])
  }
  return run(label, 'npm', ['run', script])
}

let failed = report.result === 'FAIL'
const databaseAvailable = report.docker === 'available' && report.supabase_cli === 'available' && report.supabase_local === 'running'

if (databaseAvailable) {
  failed = !runNpm('DB_GATE', 'test:v2:db') || failed
} else {
  process.stdout.write('DB_GATE: NOT_RUN (Docker or Supabase local is unavailable or stopped)\n')
  failed = requireDatabase || failed
}

for (const [label, script] of [
  ['UNIT_GATE', 'test:v2:unit'],
  ['E2E_GATE', 'test:v2:e2e'],
  ['TYPECHECK_GATE', 'typecheck'],
  ['LINT_GATE', 'lint'],
  ['BUILD_GATE', 'build'],
]) {
  failed = !runNpm(label, script) || failed
}

failed = !run('DIFF_CHECK_GATE', 'git', ['diff', '--check']) || failed

const result = failed ? 'FAIL' : databaseAvailable && report.result === 'PASS' ? 'PASS' : 'WARN'
process.stdout.write(`VERIFY_V2\nDB_GATE: ${databaseAvailable ? 'PASS_OR_FAIL_ABOVE' : 'NOT_RUN'}\nresult: ${result}\n`)
process.exitCode = failed ? 1 : 0
