import { useAuth } from '@/app/auth/use-auth'
import { SessionStatePage } from '@/app/pages/session-state-page'
import { StatePanel } from '@/shared/ui/state-panel'

export function PlatformBoundaryPage() {
  const { state, signOut } = useAuth()

  if (state.status !== 'ready') {
    return (
      <div className="px-4 py-10 sm:px-6">
        <SessionStatePage state={state} onSignOut={signOut} />
      </div>
    )
  }

  return (
    <div className="px-4 py-10 sm:px-6">
      <StatePanel
        className="mx-auto max-w-3xl"
        description="Nenhuma função de Administrador Global ou bypass de segurança foi implementado nesta etapa."
        title="Operações de plataforma indisponíveis"
      />
    </div>
  )
}
