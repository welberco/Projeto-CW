import { spawnSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url))
const projectRoot = path.resolve(scriptDirectory, '..')
const supabaseCli = path.join(
  projectRoot,
  'node_modules',
  'supabase',
  'dist',
  'supabase.js',
)
const generatedTypesPath = path.join(
  projectRoot,
  'src',
  'infrastructure',
  'supabase',
  'database.types.ts',
)
const baselineVersion = '20260909000000'
const supportedCommands = new Set(['start', 'stop', 'reset', 'types', 'smoke'])

const command = process.argv[2]

if (
  process.argv.length !== 3 ||
  command === undefined ||
  !supportedCommands.has(command)
) {
  fail('Uso: node scripts/supabase-local.mjs <start|stop|reset|types|smoke>')
}

const localEnvironment = {
  ...process.env,
  DO_NOT_TRACK: '1',
  SUPABASE_TELEMETRY_DISABLED: '1',
}

function runLocal(args, options = {}) {
  const result = spawnSync(process.execPath, [supabaseCli, ...args], {
    cwd: projectRoot,
    env: localEnvironment,
    encoding: 'utf8',
    stdio: 'pipe',
  })

  if (result.error !== undefined) {
    fail(result.error.message)
  }

  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`
  const cliReportedError = output.includes('"_tag":"Error"')

  if (result.status !== 0 || cliReportedError) {
    process.stdout.write(result.stdout ?? '')
    process.stderr.write(result.stderr ?? '')

    process.exit(result.status === 0 ? 1 : (result.status ?? 1))
  }

  if (!options.capture) {
    process.stdout.write(result.stdout ?? '')
    process.stderr.write(result.stderr ?? '')
  }

  return result.stdout ?? ''
}

function assertLocalRuntime() {
  const result = spawnSync(
    'docker',
    ['info', '--format', '{{.ServerVersion}}'],
    {
      cwd: projectRoot,
      encoding: 'utf8',
      stdio: 'pipe',
    },
  )

  if (result.error !== undefined || result.status !== 0) {
    fail(
      'LOCAL_RUNTIME_BLOCKER: Docker compatível não está instalado ou acessível.',
    )
  }
}

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

if (command !== 'stop') {
  assertLocalRuntime()
}

switch (command) {
  case 'start':
    runLocal(['start'])
    break
  case 'stop':
    runLocal(['stop'])
    break
  case 'reset':
    runLocal(['db', 'reset', '--local', '--no-seed'])
    break
  case 'types': {
    const generatedTypes = runLocal(
      ['gen', 'types', 'typescript', '--local', '--schema', 'public'],
      { capture: true },
    )

    if (generatedTypes.trim().length === 0) {
      fail('O Supabase CLI não produziu tipos a partir do banco local.')
    }

    const normalizedGeneratedTypes = `${generatedTypes.trimEnd()}\n`

    writeFileSync(generatedTypesPath, normalizedGeneratedTypes, 'utf8')
    process.stdout.write(
      'database.types.ts gerado pelo Supabase CLI a partir do banco local.\n',
    )
    break
  }
  case 'smoke': {
    runLocal(['db', 'lint', '--local', '--schema', 'public', '--level', 'error'])

    const migrations = runLocal(['migration', 'list', '--local'], {
      capture: true,
    })

    if (!migrations.includes(baselineVersion)) {
      fail(`Migration baseline ${baselineVersion} ausente no banco local.`)
    }

    const publicSchema = runLocal(
      ['db', 'dump', '--local', '--schema', 'public'],
      { capture: true },
    )

    if (/CREATE\s+TABLE\s+(?:"?public"?\.)/iu.test(publicSchema)) {
      fail('A baseline W0B não pode conter tabelas no schema public.')
    }

    process.stdout.write(
      `DB_SMOKE_OK: banco local alcançável, migration ${baselineVersion} aplicada e schema public sem tabelas.\n`,
    )
    break
  }
  default:
    fail(`Comando local não permitido: ${command}`)
}
