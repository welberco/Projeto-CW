import type { ReactNode } from 'react'
import { StatePanel } from '@/shared/ui/state-panel'

export function CadastroContentState({ kind, onRetry }: {
  kind: 'loading' | 'empty' | 'error'
  onRetry?: () => void
}) {
  if (kind === 'loading') {
    return <StatePanel title="Carregando registros" description="Aguarde enquanto os dados são consultados." headingLevel={2} live="polite" />
  }
  if (kind === 'empty') {
    return <StatePanel title="Nenhum registro encontrado" description="Ainda não há registros para os filtros selecionados." headingLevel={2} live="polite" />
  }
  const retryAction: ReactNode = onRetry === undefined ? undefined : (
    <button className="min-h-11 rounded-md border px-4 font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" onClick={onRetry} type="button">
      Tentar novamente
    </button>
  )
  return <StatePanel title="Não foi possível carregar os registros" description="A consulta falhou. Tente novamente." kind="error" headingLevel={2} action={retryAction} />
}
