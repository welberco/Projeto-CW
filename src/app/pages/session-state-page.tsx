import { Link } from 'react-router-dom'
import type { SessionState } from '@/shared/session/tenant-context'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'

const unavailableStateCopy: Partial<
  Record<SessionState['status'], { title: string; description: string }>
> = {
  profile_missing: {
    title: 'Identidade indisponível',
    description: 'Sua identidade ainda não está disponível para acesso.',
  },
  principal_unavailable: {
    title: 'Usuário bloqueado ou inativo',
    description:
      'Esta conta não possui acesso operacional ativo. Procure o suporte responsável.',
  },
  no_membership: {
    title: 'Vínculo não encontrado',
    description: 'Não há vínculo operacional disponível para esta conta.',
  },
  membership_unavailable: {
    title: 'Vínculo indisponível',
    description:
      'O vínculo desta conta está bloqueado, inativo ou não pode mais ser utilizado.',
  },
  tenant_unavailable: {
    title: 'Empreendimento indisponível',
    description:
      'O empreendimento está suspenso, inativo ou temporariamente indisponível.',
  },
  feature_unavailable: {
    title: 'Módulo indisponível',
    description: 'O módulo de Manutenção não está disponível para esta conta.',
  },
  tenant_context_unavailable: {
    title: 'Contexto indisponível',
    description:
      'O empreendimento solicitado não está disponível para esta conta.',
  },
  error: {
    title: 'Não foi possível verificar o acesso',
    description:
      'O contexto seguro está indisponível no momento. Tente novamente mais tarde.',
  },
}

export function SessionStatePage({
  state,
  onSignOut,
}: {
  state: SessionState
  onSignOut: () => Promise<void>
}) {
  if (state.status === 'booting') {
    return (
      <StatePanel
        className="mx-auto max-w-3xl"
        description="Validando sua sessão e o contexto autorizado."
        live="polite"
        title="Carregando acesso"
      />
    )
  }

  if (state.status === 'unauthenticated') {
    return (
      <StatePanel
        action={
          <Button asChild>
            <Link to="/login">Entrar</Link>
          </Button>
        }
        className="mx-auto max-w-3xl"
        description="Autentique-se para acessar este endereço."
        title="Autenticação necessária"
      />
    )
  }

  const copy = unavailableStateCopy[state.status] ?? {
    title: 'Acesso indisponível',
    description: 'Não foi possível liberar este acesso com segurança.',
  }

  return (
    <StatePanel
      action={
        <Button onClick={() => void onSignOut()} variant="secondary">
          Encerrar sessão
        </Button>
      }
      className="mx-auto max-w-3xl"
      description={copy.description}
      kind={state.status === 'error' ? 'error' : 'neutral'}
      title={copy.title}
    />
  )
}
