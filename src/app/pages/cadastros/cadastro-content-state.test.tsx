import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { CadastroContentState } from '@/app/pages/cadastros/cadastro-content-state'
import { CadastroPageHeader } from '@/app/pages/cadastros/cadastro-page-header'

describe('cadastro UI foundation', () => {
  it('keeps loading, empty and error semantically distinct', () => {
    const { rerender } = render(<CadastroContentState kind="loading" />)
    expect(screen.getByRole('heading', { name: 'Carregando registros' })).toBeVisible()
    rerender(<CadastroContentState kind="empty" />)
    expect(screen.getByRole('heading', { name: 'Nenhum registro encontrado' })).toBeVisible()
    rerender(<CadastroContentState kind="error" />)
    expect(screen.getByRole('alert')).toHaveTextContent('A consulta falhou')
    expect(screen.queryByText('Nenhum registro encontrado')).not.toBeInTheDocument()
  })

  it('provides keyboard-reachable retry and a semantic page heading', () => {
    const retry = vi.fn()
    render(<><CadastroPageHeader title="Locais" description="Lista" /><CadastroContentState kind="error" onRetry={retry} /></>)
    expect(screen.getByRole('heading', { name: 'Locais' })).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Tentar novamente' }))
    expect(retry).toHaveBeenCalledOnce()
  })
})
