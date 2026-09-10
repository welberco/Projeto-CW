import { StatePanel } from '@/shared/ui/state-panel'

export function NoPermissionPage() {
  return (
    <StatePanel
      description="Sua sessão atual não possui acesso a este conteúdo. A interface não concede autorização."
      kind="error"
      title="Sem permissão"
    />
  )
}
