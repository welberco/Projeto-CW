import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'
import type { AuthorizationState } from '@/app/authorization/use-authorization'

export function AuthorizationStatePage({
  state,
  onSignOut,
}: {
  state: AuthorizationState
  onSignOut: () => Promise<void>
}) {
  if (state.status === 'loading' || state.status === 'refreshing' || state.status === 'idle') {
    return (
      <StatePanel
        className="mx-auto max-w-3xl"
        description="Atualizando suas permissões e módulos disponíveis."
        live="polite"
        title="Carregando autorização"
      />
    )
  }

  return (
    <StatePanel
      action={
        <Button onClick={() => void onSignOut()} variant="secondary">
          Encerrar sessão
        </Button>
      }
      className="mx-auto max-w-3xl"
      description="Não foi possível liberar este acesso com segurança."
      kind={state.status === 'unavailable' ? 'error' : 'neutral'}
      title="Autorização indisponível"
    />
  )
}
