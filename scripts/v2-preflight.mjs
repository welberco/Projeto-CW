import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const localSupabaseCli = path.join(projectRoot, 'node_modules', 'supabase', 'dist', 'supabase.js')

function command(commandName, args) {
  return spawnSync(commandName, args, { cwd: projectRoot, encoding: 'utf8', stdio: 'pipe' })
}

function output(result) {
  return `${result.stdout ?? ''}${result.stderr ?? ''}`.trim()
}

function trackedFiles() {
  const result = command('git', ['ls-files', '-z'])
  return result.status === 0 ? output(result).split('\0').filter(Boolean) : []
}

function ignored(file) {
  return command('git', ['check-ignore', '-q', '--', file]).status === 0
}

function safeFileContents(file) {
  try {
    return readFileSync(path.join(projectRoot, file), 'utf8')
  } catch {
    return ''
  }
}

export function findTrackedSecretRisks() {
  const risks = []
  for (const file of trackedFiles()) {
    const basename = path.basename(file)
    if (basename.startsWith('.env') && basename !== '.env.example') {
      risks.push({ file, category: 'tracked_env_file' })
      continue
    }

    if (/(?:^|\/)tests?(?:\/|$)|\.test\.[cm]?[jt]sx?$/u.test(file)) continue

    const content = safeFileContents(file)
    if (/\bsb_secret_[A-Za-z0-9_-]{8,}\b/iu.test(content)) {
      risks.push({ file, category: 'supabase_secret' })
    }
    if (/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/u.test(content)) {
      risks.push({ file, category: 'jwt_like_token' })
    }
    if (/(?:SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_(?:KEY|TOKEN)|OPENAI_API_KEY|AWS_SECRET_ACCESS_KEY|DATABASE_URL)\s*(?:=|:)\s*['"`]?(?!process\.env\b|import\.meta\.env\b|\$\{)[A-Za-z0-9_./+=:-]{16,}/iu.test(content)) {
      risks.push({ file, category: 'inline_credential' })
    }
  }
  return risks
}

function dockerState() {
  const result = command('docker', ['info', '--format', '{{.ServerVersion}}'])
  return result.status === 0 ? 'available' : 'unavailable'
}

function localSupabaseState(docker) {
  if (docker !== 'available') return 'unknown'
  const result = command('docker', [
    'ps', '--filter', 'label=com.supabase.cli.project=cw-erp-v2-local', '--format', '{{.ID}}',
  ])
  if (result.status !== 0) return 'unknown'
  return output(result) === '' ? 'stopped' : 'running'
}

function requiredFilesExist(files) {
  return files.every((file) => existsSync(path.join(projectRoot, file)))
}

function packageManifestIsValid() {
  try {
    JSON.parse(safeFileContents('package.json'))
    return true
  } catch {
    return false
  }
}

function hasMigrations() {
  const directory = path.join(projectRoot, 'supabase', 'migrations')
  return existsSync(directory) && readdirSync(directory).some((file) => file.endsWith('.sql') && statSync(path.join(directory, file)).isFile())
}

export function collectPreflight() {
  const branch = output(command('git', ['branch', '--show-current'])) || 'unknown'
  const status = output(command('git', ['status', '--porcelain=v1']))
  const worktree = status === '' ? 'clean' : 'dirty'
  const docker = dockerState()
  const localSupabase = localSupabaseState(docker)
  const docs = requiredFilesExist([
    'AGENTS.md', 'README.md', 'PRODUCT_SPEC.md', 'docs/ARQUITETURA-TECNICA-V2.md', 'docs/IMPLEMENTACAO-V2-W1.md',
  ])
  const scripts = requiredFilesExist([
    'package.json', 'scripts/supabase-local.mjs', 'scripts/v2-preflight.mjs', 'scripts/verify-v2.mjs',
  ])
  const envIgnore = ignored('.env.local') && ignored('v2/.env.local')
  const risks = findTrackedSecretRisks()
  const packageJson = packageManifestIsValid()
  const result = !docs || !scripts || !packageJson || !envIgnore || risks.length > 0
    ? 'FAIL'
    : worktree === 'dirty' || docker === 'unavailable' || localSupabase !== 'running'
      ? 'WARN'
      : 'PASS'

  return {
    branch, worktree, node: process.version, npm: process.env.npm_config_user_agent?.match(/npm\/([^\s]+)/u)?.[1] ?? 'unknown',
    docker, supabase_cli: existsSync(localSupabaseCli) ? 'available' : 'unavailable',
    supabase_local: localSupabase, env_ignore: envIgnore ? 'pass' : 'fail',
    tracked_env_risk: risks.length === 0 ? 'pass' : 'fail', docs: docs ? 'pass' : 'fail',
    package_json: packageJson ? 'pass' : 'fail', migrations: hasMigrations() ? 'pass' : 'fail',
    scripts: scripts ? 'pass' : 'fail', risks, result,
  }
}

export function printPreflight(report) {
  process.stdout.write('PREFLIGHT_V2\n')
  for (const [key, value] of Object.entries(report)) {
    if (key === 'risks') continue
    process.stdout.write(`${key}: ${value}\n`)
  }
  for (const risk of report.risks) process.stdout.write(`risk: ${risk.file} [${risk.category}]\n`)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const report = collectPreflight()
  printPreflight(report)
  process.exitCode = report.result === 'FAIL' ? 1 : 0
}
