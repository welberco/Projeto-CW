import { fireEvent, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { LoginPage } from '@/app/pages/login-page'
import { renderWithAuthGateway } from '@/test/render-with-providers'

const failingGateway = {
  resolveSession: () => Promise.resolve({ status: 'unauthenticated' } as const),
  signIn: () => Promise.reject(new Error('provider detail and account existence')),
  signOut: () => Promise.resolve(),
  acceptInvitation: () => Promise.resolve(),
  onAuthChange: () => () => undefined,
} satisfies Parameters<typeof renderWithAuthGateway>[1]

function LocationProbe() {
  const location = useLocation()
  return <output aria-label="current-route">{location.pathname}</output>
}

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

  it('redirects a valid session to its canonical tenant route', async () => {
    const authenticatedGateway = {
      ...failingGateway,
      resolveSession: () => Promise.resolve({
        status: 'ready',
        context: {
          principalId: 'user-1',
          tenantId: 'tenant-1',
          tenantRef: '34000000-0000-4000-8000-000000000001',
          tenantDisplayName: 'Tenant 1',
          membershipId: 'membership-1',
          membershipVersion: 1,
        },
      } as const),
    }

    renderWithAuthGateway(
      <MemoryRouter initialEntries={['/login']}>
        <LoginPage />
        <LocationProbe />
      </MemoryRouter>,
      authenticatedGateway,
    )

    await waitFor(() => {
      expect(screen.getByLabelText('current-route')).toHaveTextContent(
        '/e/34000000-0000-4000-8000-000000000001/dashboard',
      )
    })
    expect(screen.queryByRole('heading', { name: 'Entrar' })).not.toBeInTheDocument()
  })
})
