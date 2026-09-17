# Implementação V2 — W4

## Estado

- Wave: **W4 — Cadastros estruturais e scope TEAM**.
- Subwave concluída: **W4A — Structural Catalog Foundation**.
- Próxima subwave: **W4B — Teams and TEAM Scope**, com plano congelado e
  implementação ainda não iniciada.
- Gate W4A: `W4A_STRUCTURAL_CATALOGS_READY = YES`.
- Gate W4B: `W4B_TEAM_SCOPE_READY = NO`.
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

## W4B — plano congelado e execução incremental

Em 2026-09-17 foi aprovado o plano executável de Equipes e scope `TEAM`. Este
registro não cria schema, permission, migration, código ou teste executável e
não inicia W4B.1.

### Decisões ratificadas

- `TEAM` depende de principal, membership de tenant, tenant, Equipe e período
  de `team_membership` ativos e da combinação exata `Resource.Action.TEAM`;
- `ALL_TENANT` é independente; `DENY TEAM` não o subtrai e
  `ALLOW ALL_TENANT` não é convertido em `TEAM`;
- Setor nunca é proxy de `TEAM`;
- sem associação autoritativa Resource → Team definida pela wave dona,
  `TEAM = false`;
- uma membership pode participar simultaneamente de múltiplas Equipes;
- a unicidade impede somente repetição do mesmo vínculo ativo;
- período encerrado é imutável; retorno à Equipe cria nova linha;
- não há DELETE normal nem reativação de período encerrado;
- Equipe com membros ativos não pode ser inativada;
- Setor com Equipes ativas não pode ser inativado;
- não há cascade ou encerramento implícito;
- `team_memberships` é Resource próprio com `read`, `add` e `end`, sempre
  `ALL_TENANT`.

### Catálogo e baselines congelados

O catálogo W4B contém exatamente 11 permissions: oito para `teams` —
`read.team`, `read.all_tenant`, `lookup.team`, `lookup.all_tenant`,
`create.all_tenant`, `update.all_tenant`, `inactivate.all_tenant` e
`reactivate.all_tenant` — e três para `team_memberships` —
`read.all_tenant`, `add.all_tenant` e `end.all_tenant`.

A matriz histórica W4 incluía `teams.use`. Essa decisão foi superada pela
política pós-freeze aprovada na W4A. W4B não criará `teams.use`, generic
`manage`, OWN, ASSIGNED ou wildcard.

Baselines exatos:

- Manager: read/lookup/create/update/inactivate de Teams em ALL_TENANT e
  read/add/end de Team Memberships em ALL_TENANT — oito grants;
- Technician: read/lookup de Teams em TEAM — dois grants;
- Assistant: read/lookup de Teams em TEAM — dois grants;
- Requester: lookup de Teams em TEAM — um grant.

`teams.reactivate` permanece fora dos quatro baselines. O rollout aprovado usa
`w4b_team_scope_v1`, eleva os templates oficiais da versão 2 para 3, é add-only,
determinístico, idempotente e independente de display name. Custom Profiles e
exact overrides permanecem intocados.

### Modelo, boundaries e efeitos planejados

`teams` será tenant-owned, versionada, inativável e opcionalmente associada a
Setor por FK composta. `team_memberships` guardará períodos `active|ended` com
FKs compostas para Team e tenant membership, unique parcial do par ativo e
histórico integral.

Commands planejados: create/update/inactivate/reactivate Team e add/end Team
Membership. Read models: list/detail/lookup/my-teams, roster por Equipe e
Equipes por membership. Roster exige `team_memberships.read`; TEAM read/lookup
não revela membros.

Todas as mutations seguem AUTH-02, expected version quando aplicável,
idempotência W3 e resultado
`{ id, version, status, command_correlation_id }`. Add/end atualizam a revisão
persistida da membership alvo para invalidar caches derivados. RLS nasce
fail-closed; escritas diretas são negadas; helpers privilegiados são privados,
mínimos, com search path vazio e grants estritos.

Audit, History e Outbox serão atômicos. Os eventos v1 são
`cadastros.team.{created,updated,inactivated,reactivated}` e
`cadastros.team_membership.{added,ended}`, com payload mínimo e sem autoridade
ou PII desnecessária.

### Contrato futuro e execução

Todo recurso futuro que consumir TEAM deverá declarar associação autoritativa
com Team, cardinalidade, actions, lifecycle, locks/rereads, efeitos de estado,
concorrência, projeções e testes. O target deve pertencer ao tenant corrente e
ter associação vigente com ao menos uma Equipe ativa presente nas memberships
ativas do ator. `team_id` do cliente nunca é autoridade.

Blocos internos congelados:

1. W4B.1 — Authorization Contract and Rollout —
   `W4B_AUTHORIZATION_CATALOG_READY`;
2. W4B.2 — Team Domain and Scope Enforcement — `W4B_TEAM_DOMAIN_READY`;
3. W4B.3 — Typed Boundary and Integrated Hardening —
   `W4B_TEAM_SCOPE_READY`.

Nenhuma nova wave oficial foi criada. `CADASTRO_READY` continua `NO` até W4D.

## W4B.1 — Authorization Contract and Rollout

Em 2026-09-17 foi implementado somente o primeiro bloco interno da W4B. A
migration forward-only `20260917000000_w4b_authorization_contract_rollout.sql`
materializa as 11 permissions já congeladas, sem criar tabelas, RLS, commands,
read models ou helper de alcance TEAM do domínio futuro.

Os templates oficiais avançam de 2 para 3. A matriz originalmente implementada
continha exatamente oito grants para Manager, dois para Technician, dois para
Assistant e um para Requester. `teams.reactivate` existe no catálogo sem
baseline; `teams.use`, generic `manage`, OWN, ASSIGNED e wildcard permanecem
ausentes. A ratificação subsequente corrige somente o baseline Manager para dez.

### Ratificação pós-freeze da delegação W2

O baseline acima registra a decisão originalmente congelada de oito grants
Manager. A validação executável W4B.1 revelou que assignment e invitation do
Perfil Technician falhavam com `AUTHORIZATION_DELEGATION_DENIED`: W2 exige que
o concedente possua a mesma combinação exata delegada, enquanto Manager tinha
somente read/lookup ALL_TENANT e Technician/Assistant tinham read/lookup TEAM.

Como ratificação pós-freeze da W4B decorrente da validação executável do
contrato de delegação W2, foram adicionadas explicitamente ao baseline Manager
`shared.teams.read.team` e `shared.teams.lookup.team`. O baseline vigente passa
a exatamente dez grants W4B. AUTH-01 permanece inalterado: TEAM e ALL_TENANT
são capabilities exatas independentes, sem hierarquia, implicação, bypass de
Manager ou exceção para templates oficiais. O contrato W2 de delegação exata é
preservado.

O rollout `w4b_team_scope_v1` reutiliza
`private.authorization_profile_rollouts`, serializa por tenant, seleciona
somente instâncias com provenance oficial e copia somente os códigos W4B.1
explicitamente allowlisted. Ele é add-only e idempotente: não remove grants,
não altera overrides, não expande Custom Profiles e não usa display name como
autoridade. Cada aplicação inicial registra Audit técnico por Perfil oficial;
replay reutiliza o ledger sem duplicar grants ou Audit.

Os testes W2B, W2D, W2E e W4A foram mantidos fail-closed diante da extensão do
catálogo. A suíte dedicada W4B.1 valida catálogo e baselines exatos, versão dos
templates, security mode/owner/search path/grants do rollout, preservação de
Custom Profiles, renome de Perfil oficial, overrides exatos, replay e a
independência semântica entre TEAM e ALL_TENANT no evaluator W2 existente.

W4B.1 não simula associação com Equipe e não torna TEAM operacional. A criação
de `public.teams`, `public.team_memberships`, o alcance autoritativo, RLS e
boundaries permanece exclusivamente na W4B.2.

### Resultado do gate W4B.1

O reset local aplicou todas as migrations, incluindo W4B.1. Após a ratificação,
a suíte DB integrada passou 890/890, incluindo 36/36 assertions dedicadas à
W4B.1 e regressão W1–W4A. Unit passou 171/171; typecheck, lint e build passaram;
E2E passou 6/6.

O primeiro gate DB integrado expôs o blocker de delegação acima: 877 de 884
assertions passaram e sete assertions encadeadas do W2C falharam. Essa execução
é preservada como evidência que motivou a ratificação; os resultados finais
após a correção explícita do baseline estão registrados acima.
