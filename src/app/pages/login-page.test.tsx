import { fireEvent, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { LoginPage } from '@/app/pages/login-page'
import { renderWithAuthGateway } from '@/test/render-with-providers'

const failingGateway = {
  getAccessState: () => Promise.resolve({ status: 'anonymous' }),
  signIn: () => Promise.reject(new Error('provider detail and account existence')),
  signOut: () => Promise.resolve(),
  acceptInvitation: () => Promise.resolve(),
  onAuthChange: () => () => undefined,
} satisfies Parameters<typeof renderWithAuthGateway>[1]

describe('login page', () => {
  it('renders an unauthenticated form without public signup', async () => {
    renderWithAuthGateway(<LoginPage />, failingGateway)
    expect(await screen.findByRole('heading', { name: 'Entrar' })).toBeVisible()
    expect(screen.queryByText(/cadastre-se/iu)).not.toBeInTheDocument()
  })

  it('maps provider failures to a non-enumerative message', async () => {
    renderWithAuthGateway(<LoginPage />, failingGateway)
    fireEvent.change(await screen.findByLabelText('E-mail'), {
      target: { value: 'person@example.invalid' },
    })
    fireEvent.change(screen.getByLabelText('Senha'), {
      target: { value: 'not-a-real-password' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Entrar' }))

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent(
        'Não foi possível entrar com as credenciais informadas.',
      )
    })
    expect(screen.queryByText(/provider detail/iu)).not.toBeInTheDocument()
  })

  it('projects a valid session and signs out through the Auth boundary', async () => {
    const signOut = vi.fn(() => Promise.resolve())
    const authenticatedGateway = {
      ...failingGateway,
      getAccessState: () =>
        Promise.resolve({ status: 'authenticated', userId: 'user-1' } as const),
      signOut,
    }

    renderWithAuthGateway(<LoginPage />, authenticatedGateway)
    expect(
      await screen.findByRole('heading', { name: 'Sessão autenticada' }),
    ).toBeVisible()

    fireEvent.click(screen.getByRole('button', { name: 'Sair' }))
    await waitFor(() => expect(signOut).toHaveBeenCalledOnce())
    expect(await screen.findByRole('heading', { name: 'Entrar' })).toBeVisible()
  })
})
