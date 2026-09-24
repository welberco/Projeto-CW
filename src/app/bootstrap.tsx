import { StrictMode } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
import { parsePublicConfig } from '@/app/config/public-config'
import { BootstrapErrorPage } from '@/app/pages/bootstrap-error-page'
import { AppProviders } from '@/app/providers/app-providers'
import { createAppQueryClient } from '@/app/query/create-query-client'
import { createAppRouter } from '@/app/router/app-router'
import { normalizeAppError } from '@/shared/errors/app-error'
import { createClientCorrelationId } from '@/shared/observability/correlation'
import {
  createReleaseIdentity,
  createUnconfiguredLocalReleaseIdentity,
} from '@/shared/observability/release'
import { logSafeError } from '@/shared/observability/safe-logger'
import { createAuthGateway } from '@/infrastructure/supabase/auth-gateway'
import { createAuthorizationGateway } from '@/infrastructure/supabase/authorization-gateway'
import { createAppSupabaseClient } from '@/infrastructure/supabase/client'
import { createStructuralCatalogGateway } from '@/infrastructure/supabase/structural-catalog-gateway'
import { createTeamGateway } from '@/infrastructure/supabase/team-gateway'

export function bootstrapApplication(
  root: Root,
  environment: Readonly<Record<string, unknown>>,
): void {
  const clientCorrelationId = createClientCorrelationId()

  try {
    const config = parsePublicConfig(environment)
    const release = createReleaseIdentity(config)
    const queryClient = createAppQueryClient()
    const router = createAppRouter()
    const supabaseClient = createAppSupabaseClient(config)
    const authGateway = createAuthGateway(supabaseClient)
    const authorizationGateway = createAuthorizationGateway(supabaseClient)
    const cadastroGateways = {
      structuralCatalog: createStructuralCatalogGateway(supabaseClient),
      teams: createTeamGateway(supabaseClient),
    }
    const routerCoordinator = {
      navigateToLogin: () => router.navigate('/login', { replace: true }),
      revalidate: () => router.revalidate(),
    }

    root.render(
      <StrictMode>
        <AppProviders
          clientCorrelationId={clientCorrelationId}
          queryClient={queryClient}
          release={release}
          authGateway={authGateway}
          authorizationGateway={authorizationGateway}
          cadastroGateways={cadastroGateways}
          routerCoordinator={routerCoordinator}
        >
          <RouterProvider router={router} />
        </AppProviders>
      </StrictMode>,
    )
  } catch (cause) {
    const release = createUnconfiguredLocalReleaseIdentity()
    const error = normalizeAppError(cause, clientCorrelationId)
    logSafeError(error, release)
    root.render(
      <StrictMode>
        <BootstrapErrorPage error={error} release={release} />
      </StrictMode>,
    )
  }
}

export function findRootElement(): Root {
  const element = document.getElementById('root')

  if (element === null) {
    throw new Error('Application root element is missing.')
  }

  return createRoot(element)
}
