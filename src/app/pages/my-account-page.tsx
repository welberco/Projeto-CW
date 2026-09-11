export function MyAccountPage() {
  return (
    <section aria-labelledby="my-account-title" className="max-w-3xl">
      <p className="text-sm font-semibold uppercase tracking-wider text-primary">
        Conta
      </p>
      <h1
        className="mt-2 text-3xl font-semibold tracking-tight"
        id="my-account-title"
      >
        Minha Conta
      </h1>
      <p className="mt-4 leading-7 text-muted-foreground">
        Esta rota está protegida pelo contexto autenticado. A edição dos dados
        pessoais será implementada na etapa funcional correspondente.
      </p>
    </section>
  )
}
