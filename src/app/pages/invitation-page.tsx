import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { useRuntimeIdentity } from '@/app/providers/runtime-identity'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'
import { parseInvitationToken } from '@/shared/auth/invitation-token'

export function InvitationPage() {
  const { state, acceptInvitation } = useAuth()
  const { clientCorrelationId } = useRuntimeIdentity()
  const [result, setResult] = useState<'idle' | 'working' | 'success' | 'error'>('idle')
  const token = parseInvitationToken(window.location.hash)

  if (token === null) {
    return <StatePanel description="O convite está ausente ou não pode ser utilizado." title="Convite indisponível" />
  }

  if (state.status === 'booting') {
    return <StatePanel description="Verificando sua identidade." live="polite" title="Carregando convite" />
  }

  if (state.status === 'unauthenticated') {
    return (
      <StatePanel
        action={<Button asChild><Link to="/login">Entrar</Link></Button>}
        description="Entre com o e-mail destinatário e retorne a este link para continuar."
        title="Autenticação necessária"
      />
    )
  }

  if (
    state.status === 'error' ||
    state.status === 'profile_missing' ||
    state.status === 'principal_unavailable'
  ) {
    return <StatePanel description="Este convite não está disponível para esta conta." title="Convite indisponível" />
  }

  if (result === 'success') {
    return <StatePanel description="O vínculo foi criado com segurança." title="Convite aceito" />
  }

  async function accept() {
    if (token === null) return
    setResult('working')
    try {
      await acceptInvitation(token, clientCorrelationId)
      window.history.replaceState(null, '', '/convite')
      setResult('success')
    } catch {
      setResult('error')
    }
  }

  return (
    <StatePanel
      action={<Button disabled={result === 'working'} onClick={() => void accept()}>{result === 'working' ? 'Aceitando…' : 'Aceitar convite'}</Button>}
      description={result === 'error' ? 'Este convite não está disponível para esta conta.' : 'Confirme para vincular sua conta ao empreendimento indicado pelo convite.'}
      kind={result === 'error' ? 'error' : 'neutral'}
      title="Aceitar convite"
    />
  )
}
