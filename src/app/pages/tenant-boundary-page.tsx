import { useParams } from 'react-router-dom'

export function TenantBoundaryPage() {
  const { tenantRef } = useParams<{ tenantRef: string }>()

  return (
    <section aria-labelledby="tenant-boundary-title" className="max-w-3xl">
      <p className="text-sm font-semibold uppercase tracking-wider text-primary">
        Boundary técnica
      </p>
      <h1
        className="mt-2 text-3xl font-semibold tracking-tight"
        id="tenant-boundary-title"
      >
        Espaço de empreendimento
      </h1>
      <p className="mt-4 leading-7 text-muted-foreground">
        A referência <code className="break-all">{tenantRef}</code> foi lida da
        URL somente como seletor opaco. Ela não cria tenant, membership ou
        autoridade e ainda não dispara acesso a dados.
      </p>
    </section>
  )
}
