import { StrictMode } from 'react'
import { render } from '@testing-library/react'
import { QueryClient } from '@tanstack/react-query'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AppProviders } from '@/app/providers/app-providers'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'
import type { AuthorizationGateway } from '@/infrastructure/supabase/authorization-gateway'
import type { ClientCorrelationId } from '@/shared/observability/correlation'

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('app provider lifecycle', () => {
  it('keeps its BroadcastChannel alive across StrictMode replay and closes on unmount', () => {
    vi.useFakeTimers()
    const close = vi.fn()
    class FakeBroadcastChannel {
      constructor() {}
      postMessage() {}
      close() {
        close()
      }
      addEventListener() {}
      removeEventListener() {}
    }
    vi.stubGlobal('BroadcastChannel', FakeBroadcastChannel)

    const authGateway: AuthGateway = {
      resolveSession: () => Promise.resolve({ status: 'unauthenticated' }),
      signIn: vi.fn(() => Promise.resolve()),
      signOut: vi.fn(() => Promise.resolve()),
      acceptInvitation: vi.fn(() => Promise.resolve()),
      onAuthChange: () => () => undefined,
    }
    const authorizationGateway: AuthorizationGateway = {
      resolveProjection: vi.fn(
        (): ReturnType<AuthorizationGateway['resolveProjection']> =>
          Promise.resolve({ status: 'unauthenticated' }),
      ),
    }
    const view = render(
      <StrictMode>
        <AppProviders
          authGateway={authGateway}
          authorizationGateway={authorizationGateway}
          clientCorrelationId={'correlation-test' as ClientCorrelationId}
          queryClient={new QueryClient()}
          release={{ environment: 'test', releaseId: 'w2d-test' }}
          routerCoordinator={{
            navigateToLogin: () => undefined,
            revalidate: () => undefined,
          }}
        >
          <span>child</span>
        </AppProviders>
      </StrictMode>,
    )

    vi.runAllTimers()
    expect(close).not.toHaveBeenCalled()

    view.unmount()
    vi.runAllTimers()
    expect(close).toHaveBeenCalledOnce()
  })
})
