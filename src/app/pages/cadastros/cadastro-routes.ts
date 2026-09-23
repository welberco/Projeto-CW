export type CadastroGroup = 'Estrutura' | 'Pessoas e Equipes' | 'Manutenção'

export interface CadastroRouteDefinition {
  path: string
  title: string
  group: CadastroGroup
  permissionCodes: readonly string[]
  entitlementKey?: 'maintenance'
  idParam?: string
  showOnIndex?: boolean
}

/** Navigation metadata only. Effective grants are supplied by AuthorizationProvider. */
export const cadastroRoutes: readonly CadastroRouteDefinition[] = [
  { path: 'cadastros/tipos-de-local', title: 'Tipos de Local', group: 'Estrutura', permissionCodes: ['shared.location_types.read.all_tenant'], showOnIndex: true },
  { path: 'cadastros/tipos-de-local/:locationTypeId', title: 'Tipo de Local', group: 'Estrutura', permissionCodes: ['shared.location_types.read.all_tenant'], idParam: 'locationTypeId' },
  { path: 'cadastros/locais', title: 'Locais', group: 'Estrutura', permissionCodes: ['shared.locations.read.all_tenant'], showOnIndex: true },
  { path: 'cadastros/locais/:locationId', title: 'Local', group: 'Estrutura', permissionCodes: ['shared.locations.read.all_tenant'], idParam: 'locationId' },
  { path: 'cadastros/centros-de-custo', title: 'Centros de Custo', group: 'Estrutura', permissionCodes: ['shared.cost_centers.read.all_tenant'], showOnIndex: true },
  { path: 'cadastros/centros-de-custo/:costCenterId', title: 'Centro de Custo', group: 'Estrutura', permissionCodes: ['shared.cost_centers.read.all_tenant'], idParam: 'costCenterId' },
  { path: 'cadastros/setores', title: 'Setores', group: 'Estrutura', permissionCodes: ['shared.sectors.read.all_tenant'], showOnIndex: true },
  { path: 'cadastros/setores/:sectorId', title: 'Setor', group: 'Estrutura', permissionCodes: ['shared.sectors.read.all_tenant'], idParam: 'sectorId' },
  { path: 'cadastros/equipes', title: 'Equipes', group: 'Pessoas e Equipes', permissionCodes: ['shared.teams.read.all_tenant', 'shared.teams.read.team'], showOnIndex: true },
  { path: 'cadastros/equipes/:teamId', title: 'Equipe', group: 'Pessoas e Equipes', permissionCodes: ['shared.teams.read.all_tenant', 'shared.teams.read.team'], idParam: 'teamId' },
  { path: 'cadastros/equipes/:teamId/membros', title: 'Membros da Equipe', group: 'Pessoas e Equipes', permissionCodes: ['shared.team_memberships.read.all_tenant'], idParam: 'teamId' },
  { path: 'manutencao/categorias', title: 'Categorias e Subcategorias', group: 'Manutenção', permissionCodes: ['maintenance.maintenance_categories.read.all_tenant'], entitlementKey: 'maintenance', showOnIndex: true },
  { path: 'manutencao/categorias/:categoryId', title: 'Categoria', group: 'Manutenção', permissionCodes: ['maintenance.maintenance_categories.read.all_tenant'], entitlementKey: 'maintenance', idParam: 'categoryId' },
  { path: 'manutencao/categorias/:categoryId/subcategorias/:subcategoryId', title: 'Subcategoria', group: 'Manutenção', permissionCodes: ['maintenance.maintenance_subcategories.read.all_tenant'], entitlementKey: 'maintenance', idParam: 'subcategoryId' },
  { path: 'manutencao/categorias/template-cw', title: 'Template CW', group: 'Manutenção', permissionCodes: ['maintenance.catalog_templates.apply.all_tenant'], entitlementKey: 'maintenance', showOnIndex: true },
  { path: 'manutencao/motivos', title: 'Motivos', group: 'Manutenção', permissionCodes: ['maintenance.maintenance_reasons.read.all_tenant'], entitlementKey: 'maintenance', showOnIndex: true },
  { path: 'manutencao/motivos/:reasonId', title: 'Motivo', group: 'Manutenção', permissionCodes: ['maintenance.maintenance_reasons.read.all_tenant'], entitlementKey: 'maintenance', idParam: 'reasonId' },
  { path: 'cadastros/tipos-de-documento', title: 'Tipos de Documento', group: 'Manutenção', permissionCodes: ['maintenance.document_types.read.all_tenant'], entitlementKey: 'maintenance', showOnIndex: true },
  { path: 'cadastros/tipos-de-documento/:documentTypeId', title: 'Tipo de Documento', group: 'Manutenção', permissionCodes: ['maintenance.document_types.read.all_tenant'], entitlementKey: 'maintenance', idParam: 'documentTypeId' },
  { path: 'manutencao/modelos-de-checklist', title: 'Modelos de Checklist', group: 'Manutenção', permissionCodes: ['maintenance.checklist_templates.read.all_tenant'], entitlementKey: 'maintenance', showOnIndex: true },
  { path: 'manutencao/modelos-de-checklist/:templateId', title: 'Modelo de Checklist', group: 'Manutenção', permissionCodes: ['maintenance.checklist_templates.read.all_tenant'], entitlementKey: 'maintenance', idParam: 'templateId' },
] as const

export const cadastroGroups: readonly CadastroGroup[] = [
  'Estrutura',
  'Pessoas e Equipes',
  'Manutenção',
]
