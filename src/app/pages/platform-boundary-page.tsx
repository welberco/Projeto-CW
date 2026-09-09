export function PlatformBoundaryPage() {
  return (
    <section aria-labelledby="platform-boundary-title" className="max-w-3xl">
      <p className="text-sm font-semibold uppercase tracking-wider text-primary">
        Boundary técnica
      </p>
      <h1
        className="mt-2 text-3xl font-semibold tracking-tight"
        id="platform-boundary-title"
      >
        Operações de plataforma
      </h1>
      <p className="mt-4 leading-7 text-muted-foreground">
        Esta rota prova a separação física do namespace de plataforma. Nenhuma
        função de Administrador Global ou bypass de segurança existe nesta etapa.
      </p>
    </section>
  )
}
