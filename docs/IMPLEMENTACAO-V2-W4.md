# Implementação V2 — W4

## Estado

- Wave: **W4 — Cadastros estruturais e scope TEAM**.
- Subwave em implementação: **W4A — Structural Catalog Foundation**.
- Gate W4A: `W4A_STRUCTURAL_CATALOGS_READY`.
- Gate final: `CADASTRO_READY` (permanece `NO` até W4D).

## W4A — Structural Catalog Foundation

### Escopo implementado

- catálogo granular W2 para Tipos de Local, Locais, Centros de Custo e Setores;
- baseline v2 determinístico dos quatro System Profile Templates;
- rollout add-only e idempotente para Tenant Profile Instances oficiais, sem tocar
  Custom Profiles ou exact overrides;
- `public.location_types`, `public.locations`, `public.cost_centers` e
  `public.sectors`, todas tenant-owned, versionadas, inativáveis e protegidas por
  RLS;
- hierarquias tenant-safe de Local e Centro de Custo, com advisory lock por
  tenant/recurso, proibição de self-parent/ciclo e bloqueio de inativação com
  filhos ativos;
- command boundaries explícitas de create/update/move/inactivate/reactivate;
- read models explícitos de list/detail/lookup;
- integração transacional com command idempotency, Audit, History e
  Transactional Outbox W3;
- contratos TypeScript/Zod tenant-neutral e query keys particionadas por tenant e
  projeção;
- pgTAP e runner PostgreSQL multi-session específicos da W4A.

### Segurança e autoridade

O tenant e o actor são derivados de `auth.uid()` e de fatos persistidos. Nenhuma
boundary pública aceita `tenant_id`, actor, permission, scope ou status por
mass assignment. As mutations exigem uma permissão exata
`Resource + Action + ALL_TENANT`; nomes de perfis não participam da autorização.

As tabelas não concedem INSERT/UPDATE/DELETE a clientes. `authenticated` recebe
somente SELECT sujeito a RLS para leitura administrativa e EXECUTE nas boundaries
explícitas. `PUBLIC`, `anon` e `service_role` não recebem atalhos. Helpers
privados fixam `search_path` vazio e não são RPCs de cliente.

### Decisão arquitetural ratificada após auditoria W4A

Em 2026-09-16 foi ratificado, antes do gate W4A, que `location_types` permanece
Resource independente de `locations`. A matriz originalmente congelada no plano
W4 não continha uma linha para esse Resource; a decisão foi registrada após a
auditoria, sem tratar a existência da tabela separada como autorização
implícita para a escolha.

A separação permite administrar Locais sem conceder administração da taxonomia
de Tipos de Local e permite combinações exatas em Custom Profiles. O rollout
W4A continua limitado aos quatro templates oficiais, preserva Custom Profiles e
overrides e não usa nome de Perfil como autoridade. No escopo W4A, somente o
baseline `manager` recebe permissions de `location_types`. Grants futuros de
`lookup` dependerão de necessidade funcional real e de rollout
explícito/versionado da wave consumidora.

### Decisão pós-congelamento sobre `use`

`read` e `lookup` estão materialmente separados: list/detail administrativo
expõe campos de gestão e pode consultar ativos e inativos, enquanto lookup
retorna apenas `id`, `code` e `name` de registros ativos para selectors.

O plano originalmente congelado incluía `use` para `locations`, `cost_centers`
e `sectors`; a primeira implementação W4A também havia criado
`location_types.use`. A auditoria W4A demonstrou que nenhuma dessas quatro
permissions possuía consumidor real ou authority boundary própria. A análise
adversarial confirmou que a proteção correta é a permission da mutation
principal combinada à validação server-side da referência. A decisão posterior
ao congelamento removeu as quatro permissions antes do gate W4A, sem substituí-las
por outra action.

A política aprovada determina que a mutation seja autorizada pela permission do
Resource efetivamente alterado. Referências e FKs recebidas pelo command são
revalidadas server-side quanto a tenant, existência, estado, elegibilidade e
invariantes de domínio. `lookup` autoriza somente descoberta/projeção mínima:
não constitui authority para mutation nem pré-requisito para associação.
Conhecer ou adivinhar um UUID não concede autoridade. Permission semelhante a
`use` somente poderá ser criada futuramente diante de boundary concreta,
documentada, consumida e testada.

Create/update de Local continua exigindo `locations.create` ou
`locations.update` e valida que o Tipo existe, está ativo e pertence ao mesmo
tenant. Referências inexistentes, inativas ou cross-tenant falham fechado. O
Resource independente `location_types` permanece ratificado, agora sem `use`.

| Resource | Actions W4A | Total |
| --- | --- | ---: |
| `locations` | read, lookup, create, update, move, inactivate, reactivate | 7 |
| `location_types` | read, lookup, create, update, inactivate, reactivate | 6 |
| `cost_centers` | read, lookup, create, update, move, inactivate, reactivate | 7 |
| `sectors` | read, lookup, create, update, inactivate, reactivate | 6 |

O catálogo W4A contém 26 permissions. Os grants `use` foram removidos dos
baselines sem antecipar novos grants de `lookup`. O rollout permanece explícito,
versionado e restrito às instâncias oficiais; Custom Profiles não recebem
expansão silenciosa e exact overrides permanecem preservados.

### Idempotência e concorrência

Cada command reutiliza `private.command_idempotency`. O fingerprint SHA-256 inclui
somente intenção semântica; reason, correlation e metadata operacional não fazem
parte dele. Replay compatível retorna o resultado original sem duplicar domínio,
Audit, History ou Event. Reuso incompatível falha fechado.

Locais e Centros de Custo serializam mudanças hierárquicas por advisory lock
transacional tenant/recurso. Updates e transições exigem `expected_version`.
Constraints, FKs compostas e índices únicos são a última linha contra races.

### Eventos W4A

Eventos usam versão 1 e o namespace `cadastros.<aggregate>.<past_tense_event>`:
created, updated, moved quando aplicável, inactivated e reactivated. O payload é
allowlisted e informativo; jamais é fonte de autoridade.

### Deliberadamente adiado

- W4B: Equipes, memberships e semântica real de TEAM;
- W4C: Categorias, Subcategorias, Motivos e Template CW;
- W4D: rotas/páginas e hardening integrado;
- OWN e ASSIGNED para recursos futuros;
- Storage e todos os domínios W5+.

### Validação

O gate exige reset e migrations locais, schema lint, toda a suíte pgTAP,
concorrência PostgreSQL real, unit, E2E, typecheck, lint, build e regressão W0–W3.
Resultados só são registrados no relatório da execução após serem efetivamente
executados.
