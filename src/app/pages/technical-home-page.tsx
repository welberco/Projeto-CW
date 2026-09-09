export function TechnicalHomePage() {
  return (
    <section aria-labelledby="foundation-title" className="space-y-6">
      <div className="max-w-3xl">
        <p className="text-sm font-semibold uppercase tracking-wider text-primary">
          W0A
        </p>
        <h1
          className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl"
          id="foundation-title"
        >
          Foundation frontend executável
        </h1>
        <p className="mt-4 text-base leading-7 text-muted-foreground">
          Este shell comprova bootstrap, providers, rotas profundas e estados
          técnicos. Nenhum domínio, tenant ou autorização funcional foi criado.
        </p>
      </div>

      <dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <TechnicalFact
          description="createBrowserRouter com boundaries de URL reais."
          title="Router Data Mode"
        />
        <TechnicalFact
          description="Cache em memória, sem persistência de payloads no navegador."
          title="TanStack Query"
        />
        <TechnicalFact
          description="Contrato público validado antes da criação de infraestrutura."
          title="Configuração segura"
        />
      </dl>

      <div className="rounded-xl border border-border bg-muted/60 p-5">
        <h2 className="font-semibold">Boundaries disponíveis</h2>
        <p className="mt-2 text-sm leading-6 text-muted-foreground">
          As rotas <code>/e/:tenantRef/*</code> e{' '}
          <code>/plataforma/*</code> existem apenas como limites técnicos. O valor
          de <code>tenantRef</code> permanece opaco e nunca representa autorização.
        </p>
      </div>
    </section>
  )
}

interface TechnicalFactProps {
  title: string
  description: string
}

function TechnicalFact({ title, description }: TechnicalFactProps) {
  return (
    <div className="rounded-xl border border-border bg-card p-5 shadow-sm">
      <dt className="font-semibold">{title}</dt>
      <dd className="mt-2 text-sm leading-6 text-muted-foreground">
        {description}
      </dd>
    </div>
  )
}
