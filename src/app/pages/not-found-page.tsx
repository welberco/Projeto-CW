import { Link } from 'react-router-dom'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'

export function NotFoundPage() {
  return (
    <StatePanel
      action={
        <Button asChild variant="secondary">
          <Link to="/">Voltar para a foundation</Link>
        </Button>
      }
      description="O endereço informado não corresponde a uma rota técnica disponível nesta etapa."
      title="Página não encontrada"
    />
  )
}
