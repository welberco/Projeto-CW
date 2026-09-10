import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createServer } from 'vite'
import { publicTestEnvironment } from '../../src/test/public-test-environment'
import { e2eHost, e2ePort } from './e2e-environment'

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
)

export default async function startV2TestServer() {
  Object.assign(process.env, publicTestEnvironment)

  const server = await createServer({
    configFile: path.join(projectRoot, 'vite.config.ts'),
    server: {
      host: e2eHost,
      port: e2ePort,
      strictPort: true,
    },
  })

  await server.listen()

  return async () => {
    await server.close()
  }
}
