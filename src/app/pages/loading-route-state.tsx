import { StatePanel } from '@/shared/ui/state-panel'

export function LoadingRouteState() {
  return (
    <StatePanel
      description="Preparando as boundaries técnicas da aplicação."
      live="polite"
      title="Carregando"
    />
  )
}
