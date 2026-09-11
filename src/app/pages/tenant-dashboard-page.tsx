export function TenantDashboardPage() {
  return (
    <section aria-labelledby="dashboard-title" className="max-w-3xl">
      <p className="text-sm font-semibold uppercase tracking-wider text-primary">
        Contexto autenticado
      </p>
      <h1
        className="mt-2 text-3xl font-semibold tracking-tight"
        id="dashboard-title"
      >
        Visão Geral
      </h1>
      <p className="mt-4 leading-7 text-muted-foreground">
        Seu acesso ao empreendimento foi validado. Os indicadores operacionais
        serão adicionados nas etapas próprias dos módulos da V2.
      </p>
    </section>
  )
}
