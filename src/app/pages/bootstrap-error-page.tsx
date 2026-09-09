import type { AppError } from '@/shared/errors/app-error'
import type { ReleaseIdentity } from '@/shared/observability/release'
import { StatePanel } from '@/shared/ui/state-panel'

interface BootstrapErrorPageProps {
  error: AppError
  release: ReleaseIdentity
}

export function BootstrapErrorPage({ error, release }: BootstrapErrorPageProps) {
  return (
    <main className="mx-auto min-h-screen max-w-3xl px-4 py-12 sm:px-6">
      <StatePanel
        description={error.message}
        kind="error"
        title="Não foi possível iniciar a aplicação"
      />
      <dl className="mt-4 grid gap-1 text-xs text-muted-foreground">
        <div>
          <dt className="inline font-semibold">Código: </dt>
          <dd className="inline">{error.code}</dd>
        </div>
        <div>
          <dt className="inline font-semibold">Release: </dt>
          <dd className="inline">{release.releaseId}</dd>
        </div>
        <div className="break-all">
          <dt className="inline font-semibold">Correlação: </dt>
          <dd className="inline">{error.correlationId}</dd>
        </div>
      </dl>
    </main>
  )
}
