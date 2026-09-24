import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { useForm } from 'react-hook-form'
import { Link, useParams } from 'react-router-dom'
import { z } from 'zod'
import { useAuthorization } from '@/app/authorization/use-authorization'
import { useAuth } from '@/app/auth/use-auth'
import { useCadastroGateways, type CadastroGateways } from '@/app/cadastros/cadastro-gateways-context'
import { CadastroContentState } from '@/app/pages/cadastros/cadastro-content-state'
import { CadastroPageHeader } from '@/app/pages/cadastros/cadastro-page-header'
import { tenantQueryKey } from '@/app/query/tenant-query-key'
import { canonicalTenantPath } from '@/app/router/tenant-route'
import type { CatalogStatus, StructuralCatalogLookup, StructuralCatalogResult } from '@/shared/catalogs/structural-catalog'
import { normalizeAppError } from '@/shared/errors/app-error'
import type { TeamListItem, TeamMembership } from '@/shared/teams/teams'
import { Button } from '@/shared/ui/button'
import { StatePanel } from '@/shared/ui/state-panel'

const optionalUuid = z.union([z.literal(''), z.string().uuid('Selecione uma opção válida.')])
const commandFormSchema = z.object({
  code: z.string().trim().max(64), name: z.string().trim().min(1, 'Informe um nome.').max(160),
  description: z.string().trim().max(2_000), reason: z.string().trim().min(1, 'Informe o motivo.').max(500),
  locationTypeId: optionalUuid, parentId: optionalUuid, sectorId: optionalUuid,
})
type CommandForm = z.infer<typeof commandFormSchema>

function commandContext(reason: string, prefix: string) {
  const id = globalThis.crypto.randomUUID()
  return { reason, correlationId: id, idempotencyKey: `${prefix}-${id}` }
}

function safeError(error: unknown) { return normalizeAppError(error).message }

function useTenantKey(resource: string, filters?: Record<string, unknown>) {
  const { state } = useAuthorization()
  if (state.status !== 'ready') throw new Error('Authorization projection is not ready.')
  return filters === undefined
    ? tenantQueryKey(state.projection, state.authorizationGeneration, resource)
    : tenantQueryKey(state.projection, state.authorizationGeneration, resource, filters)
}

function FieldError({ message }: { message: string | undefined }) {
  return message === undefined ? null : <span className="text-destructive" role="alert">{message}</span>
}

function ActionConfirmation({ action, message, busy, confirm }: { action: string; message: string; busy: boolean; confirm: () => void }) {
  const [open, setOpen] = useState(false)
  if (!open) return <Button onClick={() => setOpen(true)} type="button" variant="secondary">{action}</Button>
  return <div aria-label={`Confirmar ${action.toLocaleLowerCase('pt-BR')}`} className="grid gap-2 rounded-md border p-3" role="group"><p>{message}</p><div className="flex flex-wrap gap-2"><Button disabled={busy} onClick={confirm} type="button">Confirmar</Button><Button disabled={busy} onClick={() => setOpen(false)} type="button" variant="secondary">Cancelar</Button></div></div>
}

type StructuralResource = 'location_types' | 'locations' | 'cost_centers' | 'sectors'
interface CatalogRow { id: string; code: string | null; name: string; description: string | null; status: CatalogStatus; version: number; location_type_id?: string; parent_id?: string | null }
interface Definition {
  title: string; segment: string; read: string; create: string; update: string; inactivate: string; reactivate: string; codeRequired: boolean
  move?: string; lookupPermission?: string
  list: (g: CadastroGateways['structuralCatalog']) => Promise<readonly CatalogRow[]>
  detail: (g: CadastroGateways['structuralCatalog'], id: string) => Promise<CatalogRow | null>
  lookup?: (g: CadastroGateways['structuralCatalog']) => Promise<readonly StructuralCatalogLookup[]>
  createCommand: (g: CadastroGateways['structuralCatalog'], f: CommandForm) => Promise<StructuralCatalogResult>
  updateCommand: (g: CadastroGateways['structuralCatalog'], r: CatalogRow, f: CommandForm) => Promise<StructuralCatalogResult>
  moveCommand?: (g: CadastroGateways['structuralCatalog'], r: CatalogRow, parentId: string | null) => Promise<StructuralCatalogResult>
  lifecycle: (g: CadastroGateways['structuralCatalog'], r: CatalogRow, action: 'inactivate' | 'reactivate') => Promise<StructuralCatalogResult>
}

const definitions: Record<StructuralResource, Definition> = {
  location_types: {
    title: 'Tipos de Local', segment: 'tipos-de-local', read: 'shared.location_types.read.all_tenant', create: 'shared.location_types.create.all_tenant', update: 'shared.location_types.update.all_tenant', inactivate: 'shared.location_types.inactivate.all_tenant', reactivate: 'shared.location_types.reactivate.all_tenant', codeRequired: true,
    list: (g) => g.listLocationTypes(), detail: (g, id) => g.getLocationType(id),
    createCommand: (g, f) => g.createLocationType({ code: f.code, name: f.name, description: f.description || null, ...commandContext(f.reason, 'location-type-create') }),
    updateCommand: (g, r, f) => g.updateLocationType({ id: r.id, expectedVersion: r.version, code: f.code, name: f.name, description: f.description || null, ...commandContext(f.reason, 'location-type-update') }),
    lifecycle: (g, r, action) => g[action === 'inactivate' ? 'inactivateLocationType' : 'reactivateLocationType']({ id: r.id, expectedVersion: r.version, ...commandContext('Alteração de status', 'location-type-status') }),
  },
  locations: {
    title: 'Locais', segment: 'locais', read: 'shared.locations.read.all_tenant', create: 'shared.locations.create.all_tenant', update: 'shared.locations.update.all_tenant', move: 'shared.locations.move.all_tenant', lookupPermission: 'shared.locations.lookup.all_tenant', inactivate: 'shared.locations.inactivate.all_tenant', reactivate: 'shared.locations.reactivate.all_tenant', codeRequired: false,
    list: (g) => g.listLocations(), detail: (g, id) => g.getLocation(id), lookup: (g) => g.lookupLocations(null, 100),
    createCommand: (g, f) => g.createLocation({ locationTypeId: f.locationTypeId, parentId: f.parentId || null, code: f.code || null, name: f.name, description: f.description || null, ...commandContext(f.reason, 'location-create') }),
    updateCommand: (g, r, f) => g.updateLocation({ id: r.id, expectedVersion: r.version, locationTypeId: f.locationTypeId, code: f.code || null, name: f.name, description: f.description || null, ...commandContext(f.reason, 'location-update') }),
    moveCommand: (g, r, parentId) => g.moveLocation({ id: r.id, expectedVersion: r.version, parentId, ...commandContext('Alteração de vínculo hierárquico', 'location-move') }),
    lifecycle: (g, r, action) => g[action === 'inactivate' ? 'inactivateLocation' : 'reactivateLocation']({ id: r.id, expectedVersion: r.version, ...commandContext('Alteração de status', 'location-status') }),
  },
  cost_centers: {
    title: 'Centros de Custo', segment: 'centros-de-custo', read: 'shared.cost_centers.read.all_tenant', create: 'shared.cost_centers.create.all_tenant', update: 'shared.cost_centers.update.all_tenant', move: 'shared.cost_centers.move.all_tenant', lookupPermission: 'shared.cost_centers.lookup.all_tenant', inactivate: 'shared.cost_centers.inactivate.all_tenant', reactivate: 'shared.cost_centers.reactivate.all_tenant', codeRequired: true,
    list: (g) => g.listCostCenters(), detail: (g, id) => g.getCostCenter(id), lookup: (g) => g.lookupCostCenters(null, 100),
    createCommand: (g, f) => g.createCostCenter({ parentId: f.parentId || null, code: f.code, name: f.name, description: f.description || null, ...commandContext(f.reason, 'cost-center-create') }),
    updateCommand: (g, r, f) => g.updateCostCenter({ id: r.id, expectedVersion: r.version, code: f.code, name: f.name, description: f.description || null, ...commandContext(f.reason, 'cost-center-update') }),
    moveCommand: (g, r, parentId) => g.moveCostCenter({ id: r.id, expectedVersion: r.version, parentId, ...commandContext('Alteração de vínculo hierárquico', 'cost-center-move') }),
    lifecycle: (g, r, action) => g[action === 'inactivate' ? 'inactivateCostCenter' : 'reactivateCostCenter']({ id: r.id, expectedVersion: r.version, ...commandContext('Alteração de status', 'cost-center-status') }),
  },
  sectors: {
    title: 'Setores', segment: 'setores', read: 'shared.sectors.read.all_tenant', create: 'shared.sectors.create.all_tenant', update: 'shared.sectors.update.all_tenant', inactivate: 'shared.sectors.inactivate.all_tenant', reactivate: 'shared.sectors.reactivate.all_tenant', codeRequired: false,
    list: (g) => g.listSectors(), detail: (g, id) => g.getSector(id),
    createCommand: (g, f) => g.createSector({ code: f.code || null, name: f.name, description: f.description || null, ...commandContext(f.reason, 'sector-create') }),
    updateCommand: (g, r, f) => g.updateSector({ id: r.id, expectedVersion: r.version, code: f.code || null, name: f.name, description: f.description || null, ...commandContext(f.reason, 'sector-update') }),
    lifecycle: (g, r, action) => g[action === 'inactivate' ? 'inactivateSector' : 'reactivateSector']({ id: r.id, expectedVersion: r.version, ...commandContext('Alteração de status', 'sector-status') }),
  },
}

function CatalogForm({ definition, initial, locationTypes, parents, busy, submit }: { definition: Definition; initial?: CatalogRow; locationTypes: readonly StructuralCatalogLookup[]; parents: readonly StructuralCatalogLookup[]; busy: boolean; submit: (form: CommandForm) => void }) {
  const isLocation = definition === definitions.locations
  const schema = useMemo(() => commandFormSchema.superRefine((value, context) => {
    if (definition.codeRequired && value.code.length === 0) context.addIssue({ code: 'custom', path: ['code'], message: 'Informe um código.' })
    if (isLocation && value.locationTypeId.length === 0) context.addIssue({ code: 'custom', path: ['locationTypeId'], message: 'Selecione o tipo de local.' })
  }), [definition, isLocation])
  const form = useForm<CommandForm>({ resolver: zodResolver(schema), defaultValues: { code: initial?.code ?? '', name: initial?.name ?? '', description: initial?.description ?? '', reason: '', locationTypeId: initial?.location_type_id ?? '', parentId: initial?.parent_id ?? '', sectorId: '' } })
  return <form aria-label={initial === undefined ? `Criar ${definition.title}` : `Editar ${initial.name}`} className="mt-4 grid gap-3 rounded-lg border p-4 sm:grid-cols-2" onSubmit={(event) => { void form.handleSubmit(submit)(event) }}>
    <label className="grid gap-1 text-sm font-medium">Código<input aria-invalid={form.formState.errors.code !== undefined} aria-label="Código" className="min-h-11 rounded-md border px-3" {...form.register('code')} /><FieldError message={form.formState.errors.code?.message} /></label>
    <label className="grid gap-1 text-sm font-medium">Nome<input aria-invalid={form.formState.errors.name !== undefined} aria-label="Nome" className="min-h-11 rounded-md border px-3" {...form.register('name')} /><FieldError message={form.formState.errors.name?.message} /></label>
    {isLocation && <label className="grid gap-1 text-sm font-medium sm:col-span-2">Tipo de Local<select aria-invalid={form.formState.errors.locationTypeId !== undefined} aria-label="Tipo de Local" className="min-h-11 rounded-md border px-3" {...form.register('locationTypeId')}><option value="">Selecione</option>{locationTypes.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select><FieldError message={form.formState.errors.locationTypeId?.message} /></label>}
    {(definition === definitions.locations || definition === definitions.cost_centers) && initial === undefined && <label className="grid gap-1 text-sm font-medium sm:col-span-2">Vínculo superior<select aria-invalid={form.formState.errors.parentId !== undefined} aria-label="Vínculo superior" className="min-h-11 rounded-md border px-3" {...form.register('parentId')}><option value="">Sem vínculo superior</option>{parents.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select><FieldError message={form.formState.errors.parentId?.message} /></label>}
    <label className="grid gap-1 text-sm font-medium sm:col-span-2">Descrição<textarea aria-invalid={form.formState.errors.description !== undefined} aria-label="Descrição" className="min-h-20 rounded-md border px-3 py-2" {...form.register('description')} /><FieldError message={form.formState.errors.description?.message} /></label>
    <label className="grid gap-1 text-sm font-medium sm:col-span-2">Motivo<input aria-invalid={form.formState.errors.reason !== undefined} aria-label="Motivo" className="min-h-11 rounded-md border px-3" {...form.register('reason')} /><FieldError message={form.formState.errors.reason?.message} /></label>
    <Button className="sm:col-span-2" disabled={busy} type="submit">{busy ? 'Salvando…' : initial === undefined ? 'Criar registro' : 'Salvar alterações'}</Button>
  </form>
}

function MoveForm({ row, options, busy, move }: { row: CatalogRow; options: readonly StructuralCatalogLookup[]; busy: boolean; move: (parentId: string | null) => void }) {
  const [parentId, setParentId] = useState('')
  return <form aria-label={`Alterar vínculo de ${row.name}`} className="mt-3 grid gap-3 rounded-lg border p-3" onSubmit={(event) => { event.preventDefault(); move(parentId || null) }}><label className="grid gap-1 text-sm font-medium">Novo vínculo superior<select className="min-h-11 rounded-md border px-3" onChange={(event) => setParentId(event.target.value)} value={parentId}><option value="">Sem vínculo superior</option>{options.filter((item) => item.id !== row.id).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><Button disabled={busy} type="submit">Salvar vínculo</Button></form>
}

export function StructuralCatalogPage({ resource }: { resource: StructuralResource }) {
  const params = useParams(); const gateways = useCadastroGateways(); const { state: auth } = useAuth(); const { hasPermission } = useAuthorization(); const client = useQueryClient(); const definition = definitions[resource]
  const detailId = params.locationTypeId ?? params.locationId ?? params.costCenterId ?? params.sectorId
  const listKey = useTenantKey(`cadastros:${resource}:list`, { projection: 'admin' }); const detailKey = useTenantKey(`cadastros:${resource}:detail`, { id: detailId ?? '' })
  const [creating, setCreating] = useState(false); const [editing, setEditing] = useState<CatalogRow>(); const [moving, setMoving] = useState<CatalogRow>(); const [message, setMessage] = useState<string | null>(null)
  const canRead = hasPermission(definition.read)
  const list = useQuery({ queryKey: listKey, enabled: gateways !== null && canRead && detailId === undefined, queryFn: () => definition.list(gateways!.structuralCatalog) })
  const detail = useQuery({ queryKey: detailKey, enabled: gateways !== null && canRead && detailId !== undefined, queryFn: () => definition.detail(gateways!.structuralCatalog, detailId!) })
  const typeKey = useTenantKey('cadastros:location-types:lookup'); const parentKey = useTenantKey(`cadastros:${resource}:lookup`)
  const locationTypes = useQuery({ queryKey: typeKey, enabled: gateways !== null && resource === 'locations' && hasPermission('shared.location_types.lookup.all_tenant'), queryFn: () => gateways!.structuralCatalog.lookupLocationTypes(null, 100) })
  const parents = useQuery({ queryKey: parentKey, enabled: gateways !== null && definition.lookup !== undefined && definition.lookupPermission !== undefined && hasPermission(definition.lookupPermission), queryFn: () => definition.lookup!(gateways!.structuralCatalog) })
  const refresh = () => Promise.all([client.invalidateQueries({ queryKey: listKey }), client.invalidateQueries({ queryKey: detailKey })])
  const mutation = useMutation({ mutationFn: ({ form, row, parentId, lifecycle }: { form?: CommandForm; row?: CatalogRow; parentId?: string | null; lifecycle?: boolean }) => {
    if (gateways === null) throw new Error('Cadastro indisponível.')
    if (row !== undefined && lifecycle) return definition.lifecycle(gateways.structuralCatalog, row, row.status === 'active' ? 'inactivate' : 'reactivate')
    if (row !== undefined && parentId !== undefined && definition.moveCommand !== undefined) return definition.moveCommand(gateways.structuralCatalog, row, parentId)
    return row === undefined ? definition.createCommand(gateways.structuralCatalog, form!) : definition.updateCommand(gateways.structuralCatalog, row, form!)
  }, onMutate: () => setMessage(null), onSuccess: async () => { setMessage('Alteração concluída.'); setCreating(false); setEditing(undefined); setMoving(undefined); await refresh() }, onError: async (error) => { setMessage(safeError(error)); await refresh() } })
  if (gateways === null || auth.status !== 'ready') return <StatePanel title="Cadastro indisponível" description="A experiência não foi configurada com segurança." kind="error" />
  if (!canRead) return <StatePanel title="Sem permissão" description="Seu acesso atual não permite consultar este cadastro." kind="error" />
  const rows = detailId === undefined ? list.data : detail.data === undefined || detail.data === null ? [] : [detail.data]
  const loading = detailId === undefined ? list.isLoading : detail.isLoading; const failed = detailId === undefined ? list.isError : detail.isError
  return <section aria-label={definition.title}><CadastroPageHeader title={definition.title} description="Gestão autorizada do cadastro estrutural." />
    {detailId !== undefined && <Link className="mb-4 inline-flex min-h-11 items-center text-primary underline" to={canonicalTenantPath(auth.context.tenantRef, `cadastros/${definition.segment}`)}>Voltar à lista</Link>}{message && <p aria-live="polite">{message}</p>}
    {detailId === undefined && hasPermission(definition.create) && <Button onClick={() => { setCreating(true); setEditing(undefined); setMoving(undefined) }} type="button">Novo registro</Button>}
    {creating && <CatalogForm busy={mutation.isPending} definition={definition} locationTypes={locationTypes.data ?? []} parents={parents.data ?? []} submit={(form) => mutation.mutate({ form })} />}
    {editing && <CatalogForm busy={mutation.isPending} definition={definition} initial={editing} locationTypes={locationTypes.data ?? []} parents={parents.data ?? []} submit={(form) => mutation.mutate({ form, row: editing })} />}
    {moving && <MoveForm busy={mutation.isPending} move={(parentId) => mutation.mutate({ row: moving, parentId })} options={parents.data ?? []} row={moving} />}
    {loading ? <CadastroContentState kind="loading" /> : failed ? <CadastroContentState kind="error" onRetry={() => { void (detailId === undefined ? list.refetch() : detail.refetch()) }} /> : rows?.length === 0 ? <CadastroContentState kind="empty" /> : <ul className="mt-5 grid gap-3">{rows?.map((row) => <li className="rounded-lg border p-4" key={row.id}><div className="flex flex-wrap items-start justify-between gap-3"><div><strong>{row.name}</strong><p className="text-sm text-muted-foreground">{row.code ?? 'Sem código'} · {row.status === 'active' ? 'Ativo' : 'Inativo'}</p></div><div className="flex flex-wrap gap-2">{detailId === undefined && <Button asChild variant="secondary"><Link to={canonicalTenantPath(auth.context.tenantRef, `cadastros/${definition.segment}/${row.id}`)}>Abrir</Link></Button>}{hasPermission(definition.update) && <Button onClick={() => { setEditing(row); setMoving(undefined) }} type="button" variant="secondary">Editar</Button>}{definition.move !== undefined && hasPermission(definition.move) && <Button onClick={() => { setMoving(row); setEditing(undefined) }} type="button" variant="secondary">Alterar vínculo</Button>}{row.status === 'active' && hasPermission(definition.inactivate) && <ActionConfirmation action="Inativar" busy={mutation.isPending} confirm={() => mutation.mutate({ row, lifecycle: true })} message={`Inativar ${row.name}?`} />}{row.status === 'inactive' && hasPermission(definition.reactivate) && <ActionConfirmation action="Reativar" busy={mutation.isPending} confirm={() => mutation.mutate({ row, lifecycle: true })} message={`Reativar ${row.name}?`} />}</div></div></li>)}</ul>}
  </section>
}

function TeamForm({ initial, sectors, busy, submit }: { initial?: TeamListItem; sectors: readonly StructuralCatalogLookup[]; busy: boolean; submit: (form: CommandForm) => void }) {
  const form = useForm<CommandForm>({ resolver: zodResolver(commandFormSchema), defaultValues: { code: initial?.code ?? '', name: initial?.name ?? '', description: initial?.description ?? '', reason: '', locationTypeId: '', parentId: '', sectorId: initial?.sector_id ?? '' } })
  return <form aria-label={initial === undefined ? 'Criar Equipe' : `Editar ${initial.name}`} className="mt-3 grid gap-3 rounded-lg border p-4 sm:grid-cols-2" onSubmit={(event) => { void form.handleSubmit(submit)(event) }}><label className="grid gap-1 text-sm font-medium">Nome<input aria-invalid={form.formState.errors.name !== undefined} aria-label="Nome" className="min-h-11 rounded-md border px-3" {...form.register('name')} /><FieldError message={form.formState.errors.name?.message} /></label><label className="grid gap-1 text-sm font-medium">Código<input aria-invalid={form.formState.errors.code !== undefined} aria-label="Código" className="min-h-11 rounded-md border px-3" {...form.register('code')} /><FieldError message={form.formState.errors.code?.message} /></label><label className="grid gap-1 text-sm font-medium sm:col-span-2">Setor<select aria-invalid={form.formState.errors.sectorId !== undefined} aria-label="Setor" className="min-h-11 rounded-md border px-3" {...form.register('sectorId')}><option value="">Sem setor</option>{sectors.map((sector) => <option key={sector.id} value={sector.id}>{sector.name}</option>)}</select><FieldError message={form.formState.errors.sectorId?.message} /></label><label className="grid gap-1 text-sm font-medium sm:col-span-2">Descrição<textarea aria-invalid={form.formState.errors.description !== undefined} aria-label="Descrição" className="min-h-20 rounded-md border px-3 py-2" {...form.register('description')} /><FieldError message={form.formState.errors.description?.message} /></label><label className="grid gap-1 text-sm font-medium sm:col-span-2">Motivo<input aria-invalid={form.formState.errors.reason !== undefined} aria-label="Motivo" className="min-h-11 rounded-md border px-3" {...form.register('reason')} /><FieldError message={form.formState.errors.reason?.message} /></label><Button disabled={busy} type="submit">{busy ? 'Salvando…' : initial === undefined ? 'Criar equipe' : 'Salvar equipe'}</Button></form>
}

export function TeamsPage() {
  const { teamId } = useParams(); const gateways = useCadastroGateways(); const { state: auth } = useAuth(); const { hasPermission } = useAuthorization(); const client = useQueryClient()
  const listKey = useTenantKey('cadastros:teams:list', { projection: 'admin' }); const detailKey = useTenantKey('cadastros:teams:detail', { teamId: teamId ?? '' }); const sectorKey = useTenantKey('cadastros:sectors:lookup')
  const canRead = hasPermission('shared.teams.read.all_tenant') || hasPermission('shared.teams.read.team')
  const list = useQuery({ queryKey: listKey, enabled: gateways !== null && canRead && teamId === undefined, queryFn: () => gateways!.teams.listTeams() }); const detail = useQuery({ queryKey: detailKey, enabled: gateways !== null && canRead && teamId !== undefined, queryFn: () => gateways!.teams.getTeam(teamId!) })
  const sectors = useQuery({ queryKey: sectorKey, enabled: gateways !== null && hasPermission('shared.sectors.lookup.all_tenant'), queryFn: () => gateways!.structuralCatalog.lookupSectors(null, 100) })
  const [creating, setCreating] = useState(false); const [editing, setEditing] = useState<TeamListItem>(); const [message, setMessage] = useState<string | null>(null)
  const refresh = () => Promise.all([client.invalidateQueries({ queryKey: listKey }), client.invalidateQueries({ queryKey: detailKey })])
  const save = useMutation({ mutationFn: (form: CommandForm) => editing === undefined ? gateways!.teams.createTeam({ sectorId: form.sectorId || null, code: form.code || null, name: form.name, description: form.description || null, ...commandContext(form.reason, 'team-create') }) : gateways!.teams.updateTeam({ id: editing.id, expectedVersion: editing.version, sectorId: form.sectorId || null, code: form.code || null, name: form.name, description: form.description || null, ...commandContext(form.reason, 'team-update') }), onMutate: () => setMessage(null), onSuccess: async () => { setMessage(editing === undefined ? 'Equipe criada.' : 'Equipe atualizada.'); setCreating(false); setEditing(undefined); await refresh() }, onError: async (error) => { setMessage(safeError(error)); await refresh() } })
  const lifecycle = useMutation({ mutationFn: (team: TeamListItem) => team.status === 'active' ? gateways!.teams.inactivateTeam({ id: team.id, expectedVersion: team.version, ...commandContext('Inativação de equipe', 'team-inactivate') }) : gateways!.teams.reactivateTeam({ id: team.id, expectedVersion: team.version, ...commandContext('Reativação de equipe', 'team-reactivate') }), onMutate: () => setMessage(null), onSuccess: async () => { setMessage('Status da equipe atualizado.'); await refresh() }, onError: async (error) => { setMessage(safeError(error)); await refresh() } })
  if (gateways === null || auth.status !== 'ready') return <StatePanel title="Cadastro indisponível" description="Não foi possível carregar equipes com segurança." kind="error" />
  if (!canRead) return <StatePanel title="Sem permissão" description="Seu acesso atual não permite consultar equipes." kind="error" />
  const teams = teamId === undefined ? list.data : detail.data === undefined || detail.data === null ? [] : [detail.data]; const loading = teamId === undefined ? list.isLoading : detail.isLoading; const failed = teamId === undefined ? list.isError : detail.isError
  return <section aria-label="Equipes"><CadastroPageHeader title="Equipes" description="Gestão de equipes e seus vínculos ativos." />{teamId !== undefined && <Link className="mb-4 inline-flex min-h-11 items-center text-primary underline" to={canonicalTenantPath(auth.context.tenantRef, 'cadastros/equipes')}>Voltar à lista</Link>}{message && <p aria-live="polite">{message}</p>}{teamId === undefined && hasPermission('shared.teams.create.all_tenant') && <Button onClick={() => { setCreating(true); setEditing(undefined) }} type="button">Nova equipe</Button>}{creating && <TeamForm busy={save.isPending} sectors={sectors.data ?? []} submit={(form) => save.mutate(form)} />}{editing && <TeamForm busy={save.isPending} initial={editing} sectors={sectors.data ?? []} submit={(form) => save.mutate(form)} />}{loading ? <CadastroContentState kind="loading" /> : failed ? <CadastroContentState kind="error" onRetry={() => { void (teamId === undefined ? list.refetch() : detail.refetch()) }} /> : teams?.length === 0 ? <CadastroContentState kind="empty" /> : <ul className="mt-5 grid gap-3">{teams?.map((team) => <li className="rounded-lg border p-4" key={team.id}><strong>{team.name}</strong><p className="text-sm text-muted-foreground">{team.code ?? 'Sem código'} · {team.status === 'active' ? 'Ativa' : 'Inativa'}</p><div className="mt-3 flex flex-wrap gap-2">{teamId === undefined && <Button asChild variant="secondary"><Link to={canonicalTenantPath(auth.context.tenantRef, `cadastros/equipes/${team.id}`)}>Abrir equipe</Link></Button>}{teamId !== undefined && hasPermission('shared.team_memberships.read.all_tenant') && <Button asChild variant="secondary"><Link to={canonicalTenantPath(auth.context.tenantRef, `cadastros/equipes/${team.id}/membros`)}>Membros da Equipe</Link></Button>}{hasPermission('shared.teams.update.all_tenant') && <Button onClick={() => { setEditing(team); setCreating(false) }} type="button" variant="secondary">Editar</Button>}{team.status === 'active' && hasPermission('shared.teams.inactivate.all_tenant') && <ActionConfirmation action="Inativar" busy={lifecycle.isPending} confirm={() => lifecycle.mutate(team)} message={`Inativar a equipe ${team.name}?`} />}{team.status === 'inactive' && hasPermission('shared.teams.reactivate.all_tenant') && <ActionConfirmation action="Reativar" busy={lifecycle.isPending} confirm={() => lifecycle.mutate(team)} message={`Reativar a equipe ${team.name}?`} />}</div></li>)}</ul>}</section>
}

export function TeamRosterPage() {
  const { teamId } = useParams(); const gateways = useCadastroGateways(); const { state: auth } = useAuth(); const { hasPermission } = useAuthorization(); const client = useQueryClient(); const rosterKey = useTenantKey('cadastros:team-roster', { teamId: teamId ?? '' })
  const [search, setSearch] = useState(''); const [offset, setOffset] = useState(0); const [selected, setSelected] = useState<{ membership_id: string; display_name: string | null }>(); const [message, setMessage] = useState<string | null>(null)
  const candidatePrefix = useTenantKey('cadastros:team-candidates'); const candidateKey = useTenantKey('cadastros:team-candidates', { teamId: teamId ?? '', search, limit: 20, offset }); const teamListKey = useTenantKey('cadastros:teams:list', { projection: 'admin' }); const teamDetailKey = useTenantKey('cadastros:teams:detail', { teamId: teamId ?? '' })
  const canRead = hasPermission('shared.team_memberships.read.all_tenant'); const canAdd = hasPermission('shared.team_memberships.add.all_tenant')
  const roster = useQuery({ queryKey: rosterKey, enabled: gateways !== null && teamId !== undefined && canRead, queryFn: () => gateways!.teams.listTeamMembers({ teamId: teamId! }) }); const candidates = useQuery({ queryKey: candidateKey, enabled: gateways !== null && teamId !== undefined && canAdd, queryFn: () => gateways!.teams.lookupTeamMemberCandidates({ teamId: teamId!, searchText: search || null, limit: 20, offset }) })
  const refresh = () => Promise.all([client.invalidateQueries({ queryKey: rosterKey }), client.invalidateQueries({ queryKey: candidatePrefix }), client.invalidateQueries({ queryKey: teamListKey }), client.invalidateQueries({ queryKey: teamDetailKey })])
  const add = useMutation({ mutationFn: () => gateways!.teams.addTeamMember({ teamId: teamId!, membershipId: selected!.membership_id, ...commandContext('Inclusão de membro na equipe', 'team-member-add') }), onMutate: () => setMessage(null), onSuccess: async () => { setSelected(undefined); setMessage('Membro incluído.'); await refresh() }, onError: async (error) => { setMessage(safeError(error)); await refresh() } })
  const end = useMutation({ mutationFn: (member: TeamMembership) => gateways!.teams.endTeamMember({ id: member.id, expectedVersion: member.version, ...commandContext('Encerramento de vínculo na equipe', 'team-member-end') }), onMutate: () => setMessage(null), onSuccess: async () => { setMessage('Vínculo encerrado.'); await refresh() }, onError: async (error) => { setMessage(safeError(error)); await refresh() } })
  if (gateways === null || teamId === undefined || auth.status !== 'ready') return <StatePanel title="Equipe indisponível" description="A equipe solicitada não está disponível." kind="error" />
  if (!canRead) return <StatePanel title="Sem permissão" description="Seu acesso atual não permite consultar membros desta equipe." kind="error" />
  return <section aria-label="Membros da Equipe"><CadastroPageHeader title="Membros da Equipe" description="Vínculos de membros são encerrados, nunca excluídos." /><Link className="mb-4 inline-flex min-h-11 items-center text-primary underline" to={canonicalTenantPath(auth.context.tenantRef, `cadastros/equipes/${teamId}`)}>Voltar à equipe</Link>{message && <p aria-live="polite">{message}</p>}{canAdd && <div aria-label="Adicionar membro" className="mt-4 rounded-lg border p-4" role="region"><label className="grid gap-1 text-sm font-medium">Pesquisar candidato<input className="min-h-11 rounded-md border px-3" onChange={(event) => { setSearch(event.target.value); setOffset(0); setSelected(undefined) }} value={search} /></label>{candidates.isLoading ? <p aria-live="polite">Carregando candidatos…</p> : candidates.isError ? <div role="alert"><p>Não foi possível consultar candidatos.</p><Button onClick={() => { void candidates.refetch() }} type="button" variant="secondary">Tentar novamente</Button></div> : candidates.data?.length === 0 ? <p>Nenhum candidato disponível.</p> : <><ul className="mt-3 grid gap-2">{candidates.data?.map((candidate) => <li key={candidate.membership_id}><Button onClick={() => setSelected(candidate)} type="button" variant="secondary">{candidate.display_name ?? 'Usuário sem nome de exibição'}</Button></li>)}</ul><div className="mt-3 flex flex-wrap gap-2"><Button disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - 20))} type="button" variant="secondary">Página anterior</Button><Button disabled={(candidates.data?.length ?? 0) < 20} onClick={() => setOffset(offset + 20)} type="button" variant="secondary">Próxima página</Button></div></>}{selected && <div className="mt-3"><p>Candidato selecionado: {selected.display_name ?? 'Usuário sem nome de exibição'}</p><Button disabled={add.isPending} onClick={() => add.mutate()} type="button">{add.isPending ? 'Adicionando…' : 'Adicionar membro'}</Button></div>}</div>}{roster.isLoading ? <CadastroContentState kind="loading" /> : roster.isError ? <CadastroContentState kind="error" onRetry={() => { void roster.refetch() }} /> : roster.data?.length === 0 ? <CadastroContentState kind="empty" /> : <ul className="mt-5 grid gap-3">{roster.data?.map((member) => <li className="rounded-lg border p-4" key={member.id}><strong>{member.display_name ?? 'Usuário sem nome de exibição'}</strong><p className="text-sm text-muted-foreground">{member.status === 'active' ? 'Ativo' : 'Encerrado'}</p>{member.status === 'active' && hasPermission('shared.team_memberships.end.all_tenant') && <ActionConfirmation action="Encerrar vínculo" busy={end.isPending} confirm={() => end.mutate(member)} message={`Encerrar o vínculo de ${member.display_name ?? 'este membro'}?`} />}</li>)}</ul>}</section>
}
