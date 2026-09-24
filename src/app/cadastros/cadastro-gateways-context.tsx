import { createContext, useContext } from 'react'
import type { StructuralCatalogGateway } from '@/infrastructure/supabase/structural-catalog-gateway'
import type { TeamGateway } from '@/infrastructure/supabase/team-gateway'

export interface CadastroGateways {
  readonly structuralCatalog: StructuralCatalogGateway
  readonly teams: TeamGateway
}

export const CadastroGatewaysContext = createContext<CadastroGateways | null>(null)
export function useCadastroGateways(): CadastroGateways | null { return useContext(CadastroGatewaysContext) }
