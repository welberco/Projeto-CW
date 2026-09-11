import { Link } from 'react-router-dom'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'

export function NotFoundPage() {
  return (
    <StatePanel
      action={
        <Button asChild variant="secondary">
          <Link to="/">Voltar ao início</Link>
        </Button>
      }
      className="mx-auto max-w-3xl"
      description="O endereço informado não corresponde a uma rota disponível."
      title="Página não encontrada"
    />
  )
}
