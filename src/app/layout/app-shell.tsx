import { Link, Outlet } from 'react-router-dom'
import { useRuntimeIdentity } from '@/app/providers/runtime-identity'
import { useAuth } from '@/app/auth/use-auth'

export function AppShell() {
  const { clientCorrelationId, release } = useRuntimeIdentity()
  const { state, signOut } = useAuth()

  return (
    <div className="min-h-screen bg-background text-foreground">
      <a
        className="sr-only z-50 rounded-md bg-primary px-4 py-2 text-primary-foreground focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
        href="#main-content"
      >
        Ir para o conteúdo principal
      </a>

      <header className="border-b border-border bg-card">
        <div className="mx-auto flex min-h-16 max-w-6xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
          <Link
            className="rounded-sm font-semibold tracking-tight focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            to="/"
          >
            CW ERP <span className="text-muted-foreground">V2</span>
          </Link>
          <div className="flex items-center gap-3">
            <Link className="text-sm font-medium text-muted-foreground hover:text-foreground" to="/login">Acesso</Link>
            {state.status === 'unauthenticated' || state.status === 'booting' ? null : (
              <button className="text-sm font-medium text-muted-foreground hover:text-foreground" onClick={() => void signOut()} type="button">Sair</button>
            )}
          </div>
        </div>
      </header>

      <main
        className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 sm:py-12"
        id="main-content"
      >
        <Outlet />
      </main>

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
