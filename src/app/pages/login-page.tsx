import { useState, type FormEvent } from 'react'
import { useAuth } from '@/app/auth/use-auth'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'

const unavailableMessages: Record<string, string> = {
  profile_missing: 'Sua identidade ainda não está disponível para acesso.',
  blocked: 'Seu acesso está indisponível. Procure o suporte responsável.',
  inactive: 'Seu acesso está indisponível. Procure o suporte responsável.',
  no_access: 'Não há acesso operacional disponível para esta conta.',
  error: 'Não foi possível verificar o acesso agora. Tente novamente.',
}

export function LoginPage() {
  const { state, signIn, signOut } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setErrorMessage(null)
    try {
      await signIn(email, password)
      setPassword('')
    } catch {
      setErrorMessage('Não foi possível entrar com as credenciais informadas.')
    }
  }

  if (state.status === 'loading') {
    return <StatePanel description="Verificando sua sessão com segurança." live="polite" title="Carregando acesso" />
  }

  if (state.status === 'authenticated') {
    return (
      <StatePanel
        action={<Button onClick={() => void signOut()} variant="secondary">Sair</Button>}
        description="Sua identidade e seu acesso operacional foram verificados."
        title="Sessão autenticada"
      />
    )
  }

  if (state.status !== 'anonymous') {
    return (
      <StatePanel
        action={<Button onClick={() => void signOut()} variant="secondary">Encerrar sessão</Button>}
        description={unavailableMessages[state.status] ?? 'Não foi possível verificar o acesso agora.'}
        kind={state.status === 'error' ? 'error' : 'neutral'}
        title="Acesso indisponível"
      />
    )
  }

  return (
    <section className="mx-auto max-w-md rounded-xl border border-border bg-card p-6 shadow-sm" aria-labelledby="login-title">
      <p className="text-sm font-semibold uppercase tracking-wider text-primary">CW ERP</p>
      <h1 className="mt-2 text-2xl font-semibold tracking-tight" id="login-title">Entrar</h1>
      <p className="mt-2 text-sm leading-6 text-muted-foreground">Use a conta fornecida pela sua organização. Não há cadastro público.</p>
      <form className="mt-6 space-y-4" onSubmit={(event) => void submit(event)}>
        <label className="block text-sm font-medium" htmlFor="email">E-mail</label>
        <input
          autoComplete="email"
          className="min-h-11 w-full rounded-md border border-input bg-background px-3"
          id="email"
          onChange={(event) => setEmail(event.target.value)}
          required
          type="email"
          value={email}
        />
        <label className="block text-sm font-medium" htmlFor="password">Senha</label>
        <input
          autoComplete="current-password"
          className="min-h-11 w-full rounded-md border border-input bg-background px-3"
          id="password"
          minLength={8}
          onChange={(event) => setPassword(event.target.value)}
          required
          type="password"
          value={password}
        />
        {errorMessage === null ? null : <p aria-live="assertive" className="text-sm text-destructive" role="alert">{errorMessage}</p>}
        <Button className="w-full" type="submit">Entrar</Button>
      </form>
    </section>
  )
}
