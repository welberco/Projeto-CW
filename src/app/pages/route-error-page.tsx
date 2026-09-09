import { useEffect, useMemo } from 'react'
import { useRouteError } from 'react-router-dom'
import { useRuntimeIdentity } from '@/app/providers/runtime-identity'
import { normalizeAppError } from '@/shared/errors/app-error'
import { logSafeError } from '@/shared/observability/safe-logger'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'

export function RouteErrorPage() {
  const routeError = useRouteError()
  const { clientCorrelationId, release } = useRuntimeIdentity()
  const error = useMemo(
    () => normalizeAppError(routeError, clientCorrelationId),
    [clientCorrelationId, routeError],
  )

  useEffect(() => {
    logSafeError(error, release)
  }, [error, release])

  return (
    <div className="mx-auto min-h-screen max-w-3xl px-4 py-12 sm:px-6">
      <StatePanel
        action={
          <Button onClick={() => window.location.reload()} type="button">
            Tentar novamente
          </Button>
        }
        description={error.message}
        kind="error"
        title="A aplicação encontrou um erro"
      />
      <p className="mt-4 break-all text-xs text-muted-foreground">
        Código: {error.code} · Correlação: {error.correlationId}
      </p>
    </div>
  )
}
