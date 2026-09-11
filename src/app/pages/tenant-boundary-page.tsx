import { useEffect } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'

export function TenantBoundaryPage() {
  const { tenantRef } = useParams<{ tenantRef: string }>()
  const { state, resolveTenantRef } = useAuth()

  useEffect(() => {
    if (tenantRef !== undefined) void resolveTenantRef(tenantRef)
  }, [resolveTenantRef, tenantRef])

  if (state.status === 'booting') {
    return <StatePanel description="Resolvendo o contexto autoritativo." live="polite" title="Carregando empreendimento" />
  }

  if (state.status === 'unauthenticated') {
    return <StatePanel action={<Button asChild><Link to="/login">Entrar</Link></Button>} description="Autentique-se para acessar este contexto." title="Autenticação necessária" />
  }

  if (state.status !== 'ready' || state.context.tenantRef !== tenantRef) {
    return <StatePanel description="O empreendimento solicitado não está disponível para esta conta." kind="error" title="Contexto indisponível" />
  }

  return (
    <section aria-labelledby="tenant-boundary-title" className="max-w-3xl">
      <p className="text-sm font-semibold uppercase tracking-wider text-primary">
        Boundary técnica
      </p>
      <h1
        className="mt-2 text-3xl font-semibold tracking-tight"
        id="tenant-boundary-title"
      >
        {state.context.tenantDisplayName}
      </h1>
      <p className="mt-4 leading-7 text-muted-foreground">
        A referência <code className="break-all">{tenantRef}</code> selecionou
        um contexto que já foi autorizado pelo resolver server-side. A URL não
        concede autoridade.
      </p>
    </section>
  )
}
