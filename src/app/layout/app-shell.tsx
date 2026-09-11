import { Outlet } from 'react-router-dom'
import { useRuntimeIdentity } from '@/app/providers/runtime-identity'

export function AppShell() {
  const { clientCorrelationId, release } = useRuntimeIdentity()

  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <a
        className="sr-only z-50 rounded-md bg-primary px-4 py-2 text-primary-foreground focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
        href="#main-content"
      >
        Ir para o conteúdo principal
      </a>

      <div className="flex-1" id="main-content">
        <Outlet />
      </div>

      <footer className="mx-auto grid w-full max-w-6xl gap-1 border-t border-border px-4 py-5 text-xs text-muted-foreground sm:grid-cols-2 sm:px-6">
        <span>
          Ambiente: {release.environment} · Release: {release.releaseId}
        </span>
        <span className="break-all sm:text-right">
          Correlação local, não autoritativa: {clientCorrelationId}
        </span>
      </footer>
    </div>
  )
}
