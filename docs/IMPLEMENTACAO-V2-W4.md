# Implementação V2 — W4

## Estado

- Wave: **W4 — Cadastros estruturais e scope TEAM**.
- Subwaves concluídas: **W4A — Structural Catalog Foundation** e
  **W4B — Teams and TEAM Scope**.
- Próxima subwave: **W4C — Maintenance Catalogs**, com plano executivo
  congelado e implementação ainda não iniciada.
- Gate W4A: `W4A_STRUCTURAL_CATALOGS_READY = YES`.
- Gate W4B: `W4B_TEAM_SCOPE_READY = YES`.
- Gate W4C: `W4C_MAINTENANCE_CATALOGS_READY = NO`.
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

## W4B.2 — Team Domain and Scope Enforcement

Em 2026-09-17 a migration forward-only
`20260917001000_w4b_team_domain_scope.sql` materializou somente o domínio de
Equipes e tornou operacional o primeiro alcance `TEAM`. A migration W4B.1 e as
migrations anteriores permanecem imutáveis. Contratos TypeScript, gateway e UI
continuam reservados para W4B.3/W4D.

### Modelo físico e lifecycle

`public.teams` é tenant-owned, versionada, inativável e possui referência
opcional tenant-safe para `public.sectors`. Código, quando informado, é único
por tenant sem distinção de caixa. FKs compostas, checks de conteúdo/lifecycle
e índices tenant/status/name e tenant/sector/status fecham inconsistências e
mantêm consultas determinísticas.

`public.team_memberships` registra períodos de participação `active|ended` com
FKs compostas para Team e tenant membership. Um índice único parcial admite no
máximo um período ativo por tenant/Team/membership, sem impedir múltiplas Teams
simultâneas. Um período encerrado é imutável; retorno à mesma Team insere nova
linha. As duas tabelas proíbem hard delete e não possuem cascade.

Equipe com participação ativa não pode ser inativada. Setor com Equipe ativa
também não pode ser inativado; a proteção foi adicionada por trigger novo sobre
`sectors`, sem alterar W4A. Team ativa sempre exige Setor ativo quando houver
referência. Não existe encerramento, inativação ou movimentação implícita.

### Alcance TEAM e boundaries

`private.team_reaches(team_id)` deriva o ator exclusivamente de `auth.uid()` e
revalida `app_user`, tenant membership, tenant, Team e período de participação
ativos no banco. `private.can_access_team(team_id, action)` compõe esse fato de
domínio com `private.has_effective_permission` para a combinação exata
`teams.{read|lookup}.TEAM`; a capability independente `ALL_TENANT` é avaliada
como alternativa, sem hierarquia ou conversão entre scopes. Setor não participa
da decisão de alcance.

Os seis commands públicos são `create_team`, `update_team`,
`inactivate_team`, `reactivate_team`, `add_team_member` e `end_team_member`.
Todos derivam tenant/ator do contexto atual, exigem reason e idempotency key,
usam optimistic version quando há estado preexistente e retornam somente
`{ id, version, status, command_correlation_id }`. Nenhuma assinatura aceita
tenant, ator, Perfil, permission ou scope como autoridade.

Os seis read models são `list_teams`, `get_team`, `lookup_teams`,
`list_my_teams`, `list_team_members` e `list_teams_for_membership`. List/detail
compõem a união de capabilities exatas TEAM e ALL_TENANT; lookup retorna apenas
Teams ativas e `id, code, name`; my-teams é self-only sob lookup TEAM. Roster e
projeção por membership exigem exclusivamente
`team_memberships.read.all_tenant` e não expõem e-mail, grants ou overrides.

### RLS, locks e revisão de autorização

As duas tabelas usam ENABLE/FORCE RLS. `teams` concede ao papel authenticated
somente SELECT protegido pela policy de read; mutations são RPC-only.
`team_memberships` não concede acesso direto nem possui policy de cliente:
roster e mutations passam apenas pelas boundaries explícitas. Helpers privados
têm owner `postgres`, search path vazio e nenhum EXECUTE para PUBLIC, anon,
authenticated, service role ou worker.

Commands começam pelo lock autoritativo W2 do ator/tenant e pela identidade
idempotente W3. Depois estabilizam Setor, Team, tenant membership alvo e período
na ordem física aplicável, fazem uma reavaliação final do ator autorizado e só
então validam/mutam. O advisory lock tenant já estabelecido por W2 serializa
commands do mesmo tenant; optimistic versions e constraints permanecem como
defesas independentes.

Add/end atualizam na mesma transação a `version` da tenant membership alvo por
meio do mecanismo normal de versão W2. Assim projeções de autorização ficam
obsoletas por fato persistido, sem depender de JWT ou cache cliente.

### Efeitos, concorrência e validação

Cada command escreve atomicamente Audit, History e Outbox v1. Teams emitem
`cadastros.team.{created,updated,inactivated,reactivated}`; períodos emitem
`cadastros.team_membership.{added,ended}`. Payloads contêm apenas IDs
funcionais, versão, status, código e Setor quando aplicável, sem e-mail ou dump
de autorização. Replay idempotente não duplica domínio nem efeitos.

O pgTAP W4B.2 cobre schema, grants, RLS, boundaries, tenant isolation, alcance
TEAM positivo/negativo, independência read/lookup/roster, lifecycle, revisão de
autorização, replay e efeitos. O runner local multi-session cobre dez classes:
adds com mesma key e keys distintas, add/end, add/inactivate, optimistic update,
double end, mudança de alcance corrente, replay, unicidade dos efeitos e
unicidade do período ativo.

O gate W4B.2 somente pode ser marcado pronto após a execução efetiva de reset,
pgTAP, runner e regressões locais. `W4B_TEAM_SCOPE_READY` e `CADASTRO_READY`
permanecem `NO` até W4B.3 e W4D, respectivamente.

### Resultado final do gate W4B.2

Em validação local externa ao sandbox, `db:reset` aplicou integralmente as
migrations W0–W4B.2. O gate DB passou os lints dos schemas `public` e `private`,
18 arquivos pgTAP e 969/969 assertions, incluindo a regressão W1–W4B.1. O
smoke integrado também passou com os runners anteriores e o runner W4B.2
aprovou 10/10 casos de concorrência.

A estabilização revelou somente duas falhas de teste: a boundary histórica
W4A ainda proibia as duas tabelas oficialmente introduzidas pela W4B.2, e duas
fixtures W4B tentavam obter `membership_id` do retorno de
`bootstrap_initial_tenant`, cujo contrato contém apenas `tenant_id` e
`tenant_ref`. A boundary continuou protegendo a antecipação W4C e as fixtures
passaram a resolver `public.tenant_memberships.id` pela fonte autoritativa. As
correções não alteraram a migration W4B.2, o engine de autorização nem a
semântica TEAM.

Com `DB_RESET = PASS`, `DB_TESTS = PASS`, `DB_TEST_COUNT = 969/969`,
`W4B_CONCURRENCY = PASS (10/10)`, `REGRESSION_W1_W4B1 = PASS` e
`DB_SMOKE = PASS`, o gate `W4B_TEAM_DOMAIN_READY` está concluído. O gate
`W4B_TEAM_SCOPE_READY` permanece `NO` até a execução explícita da W4B.3.

## W4B.3 — Typed Boundary and Integrated Hardening

Em 2026-09-21 foi materializada a boundary TypeScript de Equipes sobre os
tipos gerados oficialmente pelo Supabase CLI local após a W4B.2. O arquivo
`database.types.ts` contém `public.teams`, `public.team_memberships` e as 12
RPCs aprovadas; ele não foi ajustado manualmente. A adaptação entre a
nulabilidade real das funções PostgreSQL e a limitação dos metadados gerados
permanece estreita e local ao gateway.

O boundary runtime cobre `Team`, `TeamMembership`, seus status, os seis inputs
de command e os seis read models. Schemas Zod strict validam somente formato e
projeção: UUID, conteúdo textual, versão, paginação, lifecycle projetado e o
resultado exato `{ id, version, status, command_correlation_id }`. O formato
legado com `correlation_id` é rejeitado. Lookup continua limitado a `id`,
`code` e `name`; roster não expõe e-mail, Perfil, permissions ou overrides.

O gateway autenticado expõe exatamente 12 operações: seis commands e seis
reads, todas por RPC. Inputs e outputs são parseados fail-closed. Erros de
authorization, conflito de versão/idempotência e estado inválido preservam o
código de domínio aplicável. O gateway não aceita tenant, ator ou scope como
authority, não avalia TEAM localmente, não usa `service_role`, não acessa
tabelas diretamente e não transforma falhas em sucesso ou ausência silenciosa.

Os unitários da W4B.3 cobrem 24 casos focados, incluindo as 12 operações do
gateway, contratos strict, nulabilidade aprovada, lifecycle projetado,
paginação, projeção mínima e rejeição de payload de authority. A regressão
completa passou 195/195; typecheck, lint e build passaram; E2E permaneceu 6/6.

Nenhum SQL, migration, pgTAP ou runner de concorrência foi alterado na W4B.3.
Por isso, uma nova execução DB não é necessária para este bloco tipado: a
evidência W4B.2 imediatamente anterior permanece autoritativa em 969/969, com
reset e smoke aprovados e concorrência 10/10, inclusive mudança de membership
durante decisão TEAM viva.

A auditoria integrada preservou as 11 permissions, os baselines Manager 10,
Technician 2, Assistant 2 e Requester 1, sem generic `use` e sem
`teams.reactivate` nos baselines. AUTH-01, a independência TEAM/ALL_TENANT e a
ausência de hierarquia de scope permanecem inalteradas. Com os gates de app e
a evidência DB vigente aprovados, `W4B_TYPED_BOUNDARY_READY = YES` e
`W4B_TEAM_SCOPE_READY = YES`. `CADASTRO_READY` permanece `NO` até W4D.

## W4C — plano executivo congelado

Em 2026-09-21 foi congelado o plano executivo da W4C, sem iniciar migration,
SQL, TypeScript, teste funcional ou UI. As decisões abaixo detalham o recorte
já aprovado no plano W4: Categorias, Subcategorias, Motivos contextuais, Tipos
de Documento, esqueleto de Modelos de Checklist e aplicação opcional do
Template CW. Solicitações, OS, execução/snapshot de checklist, Storage e todos
os consumidores operacionais permanecem fora desta subwave.

### Modelo de Categoria e Subcategoria

Categoria e Subcategoria são entidades próprias, tenant-owned e específicas
do domínio Manutenção:

- `public.maintenance_categories` representa a classificação primária;
- `public.maintenance_subcategories` representa a classificação subordinada e
  possui FK composta `(tenant_id, category_id)` para Categoria;
- a profundidade funcional é exatamente dois níveis — Categoria →
  Subcategoria. Não há `parent_id`, árvore genérica ou sub-subcategoria;
- ambas possuem UUID interno, `tenant_id`, `code` opcional, `name`,
  `description`, status `active|inactive`, versão positiva, autoria e
  timestamps do banco;
- código de Categoria, quando presente, é único de forma normalizada no
  tenant; código de Subcategoria, quando presente, é único de forma
  normalizada dentro da Categoria;
- nome não é autoridade nem identificador. Listas usam ordenação determinística
  por nome normalizado e UUID; não há campo de ordenação manual sem requisito;
- não há hard delete nem cascade de lifecycle. Inativação preserva identidade e
  histórico.

Categoria ativa pode ser atualizada sem propagar alterações aos filhos.
Inativar Categoria com Subcategoria ativa ou Modelo de Checklist ativo falha
com dependência ativa. Inativar Subcategoria não inativa a Categoria nem
qualquer consumidor futuro. Reativar Subcategoria ou Modelo exige Categoria
ativa. Referências históricas permanecem legíveis; lookups retornam somente
ativos.

### Motivos contextuais

`public.maintenance_reasons` é tenant-owned e possui UUID, `tenant_id`,
`usage_context`, código obrigatório, nome, descrição, status, versão, autoria
e timestamps. `usage_context` é vocabulário técnico fechado e imutável:

- `CANCEL_REQUEST` — cancelamento futuro de Solicitação;
- `REJECT_REQUEST` — rejeição futura de Solicitação;
- `PAUSE_WORK_ORDER` — pausa futura de OS;
- `CANCEL_WORK_ORDER` — cancelamento futuro de OS;
- `RETURN_WORK_ORDER` — devolução futura de OS.

A unicidade é `(tenant_id, usage_context, normalized_code)`. O registro é
editável em código, nome e descrição, pode ser inativado/reativado e nunca muda
de contexto; correção de contexto exige inativar e criar outro. A W4C entrega
somente catálogo e validação do contexto. As state machines consumidoras,
obrigatoriedade de detalhe para “Outro” e referências operacionais pertencem às
waves de Solicitação/OS. Nenhum contexto conhecido é adiado; permanecem
adiados apenas seeds de `CANCEL_WORK_ORDER` e `RETURN_WORK_ORDER`, novos
contextos não aprovados e toda lógica consumidora.

### Tipos de Documento e Modelos de Checklist

O escopo congelado inclui os skeletons seguros já previstos:

- `public.document_types`: vocabulário tenant-owned com código opcional, nome,
  descrição, lifecycle e versão; não cria arquivo, metadata, bucket ou Storage;
- `public.checklist_templates`: cabeçalho tenant-owned ligado por FK composta a
  uma Categoria ativa, com código opcional, nome, descrição, lifecycle e
  versão;
- `public.checklist_template_items`: definição pertencente ao template, com
  posição positiva única, prompt, tipo de resposta fechado, obrigatoriedade e
  instruções opcionais. Não possui lifecycle independente nem boundary de
  autorização própria;
- a criação e a atualização da definição do Modelo persistem cabeçalho e itens
  atomicamente. Os tipos permitidos são `DONE_NOT_DONE`,
  `CONFORMING_NONCONFORMING`, `YES_NO`, `TEXT`, `NUMBER` e `OBSERVATION`;
- execução, respostas, evidências, associação a Ativo/Plano/OS e snapshot
  permanecem adiados.

### Template CW v1

O Template CW é implementado na W4C como opção explícita, nunca como seed
automático. `private.catalog_templates`,
`private.catalog_template_entries` e
`private.catalog_template_applications` guardam versão, entradas allowlisted e
ledger técnico. Não possuem acesso direto de cliente e nenhuma tabela
tenant-owned mantém FK ou dependência runtime com o template.

`apply_cw_catalog_template` aceita apenas chave/versão allowlisted, deriva
tenant e ator do contexto, exige `catalog_templates.apply.all_tenant`, usa o
mesmo lock tenant/catálogos das mutations manuais e exige Categorias,
Subcategorias e Motivos integralmente vazios. A aplicação cria cópias
tenant-owned em uma transação, registra History/Event por registro, Audit da
aplicação, idempotência e ledger único `(tenant_id, template_key)`. Não há
merge por label/código, aplicação parcial, reaplicação de versão futura ou
auto-sync. “Começar vazio” não grava estado artificial.

O Template CW v1 copia exatamente:

| Categoria | Subcategorias |
| --- | --- |
| Elétrica | Iluminação; Tomadas; Quadros elétricos; Circuitos; Iluminação de emergência |
| Hidráulica | Abastecimento; Vazamentos; Esgoto; Bombas; Reservatórios |
| Civil | Alvenaria; Pintura; Revestimentos; Impermeabilização; Cobertura |
| Climatização | Ar-condicionado; VRF; Ventilação; Exaustão |
| Segurança contra incêndio | Extintores; Hidrantes; Alarme; Iluminação de emergência |
| Elevadores | Elevadores; Plataformas; Transporte vertical |
| Portas e acessos | Portas; Fechaduras; Portões; Controle de acesso |
| CFTV e segurança eletrônica | Câmeras; Gravadores; Sensores |
| Jardinagem e áreas externas | Paisagismo; Irrigação; Áreas externas |
| Limpeza e conservação | Limpeza técnica; Conservação |
| Outros | classificação genérica residual |

Os motivos copiados são:

| Contexto | Motivos |
| --- | --- |
| `CANCEL_REQUEST` | Duplicidade; Solicitação indevida; Serviço não necessário; Impossibilidade de execução; Substituído por outra demanda; Outro |
| `REJECT_REQUEST` | Fora do escopo; Informação insuficiente; Solicitação improcedente; Duplicidade; Outro |
| `PAUSE_WORK_ORDER` | Aguardando material; Aguardando fornecedor; Aguardando acesso/liberação; Aguardando aprovação; Impedimento técnico; Outro |
| `CANCEL_WORK_ORDER` | nenhum seed aprovado |
| `RETURN_WORK_ORDER` | nenhum seed aprovado |

As entradas globais usam chaves ASCII e códigos determinísticos separados das
labels editáveis. Tipos de Documento e Modelos de Checklist começam vazios.

### Authorization e rollout

AUTH-01 permanece exato, sem wildcard, hierarchy, `manage`, `use`, OWN,
ASSIGNED ou TEAM. Todos os Resources W4C usam exclusivamente `ALL_TENANT` e o
entitlement `maintenance`; nenhum deles possui associação autoritativa com
Equipe. A policy pós-W4A para referências é normativa: a permission do Resource
mutado autoriza a mutation; Categoria e demais referências são relidas e
validadas server-side. `lookup` serve somente discovery e não é authority nem
pré-requisito da mutation.

O catálogo W4C contém exatamente 31 combinações:

| Module/Resource | Actions `ALL_TENANT` | Total |
| --- | --- | ---: |
| `maintenance.maintenance_categories` | read, lookup, create, update, inactivate, reactivate | 6 |
| `maintenance.maintenance_subcategories` | read, lookup, create, update, inactivate, reactivate | 6 |
| `maintenance.maintenance_reasons` | read, lookup, create, update, inactivate, reactivate | 6 |
| `maintenance.document_types` | read, lookup, create, update, inactivate, reactivate | 6 |
| `maintenance.checklist_templates` | read, lookup, create, update, inactivate, reactivate | 6 |
| `maintenance.catalog_templates` | apply | 1 |

Os baselines exatos são:

| Template | Grants W4C | Total |
| --- | --- | ---: |
| `manager` | read/lookup/create/update/inactivate de Categorias, Subcategorias e Motivos; read/lookup de Tipos de Documento e Modelos de Checklist; apply de Template CW | 20 |
| `technician` | lookup de Categorias, Subcategorias, Motivos, Tipos de Documento e Modelos de Checklist | 5 |
| `assistant` | lookup de Categorias, Subcategorias, Motivos, Tipos de Documento e Modelos de Checklist | 5 |
| `requester` | lookup de Categorias e Subcategorias | 2 |

`reactivate` permanece granular no catálogo e fora dos quatro baselines.
Mutations de Tipo de Documento/Modelo de Checklist também ficam fora dos
baselines; Custom Profiles podem recebê-las somente por delegação W2 válida.
Manager contém todas as combinações exatas delegadas aos demais templates, sem
exceção à antiescalada.

O rollout parte dos System Profile Templates v3 entregues pela W4B e publica
v4 com `rollout_key = 'w4c_maintenance_catalogs_v1'`. Ele reutiliza
`private.authorization_profile_rollouts`, é add-only, determinístico,
transacional e idempotente, seleciona apenas UUID/template_key oficiais,
preserva grants existentes e exact overrides, exclui Custom Profiles e
registra Audit técnico sem duplicação em replay. Não existe auto-sync.

### Commands planejados

São 21 RPCs mutáveis explícitas:

1. `create_maintenance_category`;
2. `update_maintenance_category`;
3. `inactivate_maintenance_category`;
4. `reactivate_maintenance_category`;
5. `create_maintenance_subcategory`;
6. `update_maintenance_subcategory`;
7. `inactivate_maintenance_subcategory`;
8. `reactivate_maintenance_subcategory`;
9. `create_maintenance_reason`;
10. `update_maintenance_reason`;
11. `inactivate_maintenance_reason`;
12. `reactivate_maintenance_reason`;
13. `create_document_type`;
14. `update_document_type`;
15. `inactivate_document_type`;
16. `reactivate_document_type`;
17. `create_checklist_template`;
18. `update_checklist_template_definition`;
19. `inactivate_checklist_template`;
20. `reactivate_checklist_template`;
21. `apply_cw_catalog_template`.

Create recebe campos funcionais, reason, correlation ID e idempotency key.
Update recebe ID, expected version, campos funcionais completos allowlisted,
reason, correlation e idempotency. Inactivate/reactivate recebem ID, expected
version e o mesmo contexto de command. Motivo recebe `usage_context` apenas no
create; update/status nunca o altera. Subcategoria relê e bloqueia Categoria.
Modelo relê Categoria e persiste toda a definição ordenada atomicamente sob a
permission `checklist_templates.update`.

Todos os commands seguem AUTH-02: lock autoritativo W2 do ator/tenant,
aquisição idempotente W3, lock compartilhado tenant/catálogos quando o Template
ou seus alvos participarem, pai antes do filho, alvo por UUID, releitura final,
permission exata, tenant/entitlement/estado/versão/domínio, mutation e
Audit/History/Outbox antes do commit. Tenant, ator, status, scope, grants e
autoria não entram no payload.

Os 20 commands de entidade retornam estritamente
`{ id, version, status, command_correlation_id }`. O resultado especializado
de aplicação preserva esses quatro campos — `id` identifica o ledger,
`version` é a versão efetiva e `status = applied` — e acrescenta somente
`template_key`, IDs e contagens allowlisted exigidos pelo contrato congelado.
`correlation_id` legado nunca substitui `command_correlation_id`.

### Read models planejados

São 16 RPCs de leitura:

- Categorias: `list_maintenance_categories`, `get_maintenance_category`,
  `lookup_maintenance_categories`;
- Subcategorias: `list_maintenance_subcategories`,
  `get_maintenance_subcategory`, `lookup_maintenance_subcategories`;
- Motivos: `list_maintenance_reasons`, `get_maintenance_reason`,
  `lookup_maintenance_reasons`;
- Tipos de Documento: `list_document_types`, `get_document_type`,
  `lookup_document_types`;
- Modelos de Checklist: `list_checklist_templates`,
  `get_checklist_template`, `lookup_checklist_templates`;
- Template CW: `get_cw_catalog_template_preview`.

Listagens administrativas filtram somente por texto, status e, conforme o
Resource, `category_id` ou `usage_context`, com limite/offset seguro,
ordenação normalizada e UUID como desempate. Detalhes usam UUID e
anti-enumeration. O detalhe de Modelo inclui os itens em posição ordenada; não
há RPC pública separada de item. Lookups retornam somente ativos e projeção
mínima `id`, `code`, `name`; Subcategoria aceita Categoria como filtro
tenant-safe, Motivo exige contexto quando usado por selector e Modelo pode
incluir `category_id` apenas para distinção/filtragem necessária. O preview do
Template exige capability `catalog_templates.apply`, retorna somente chave,
versão, conteúdo allowlisted e contagens, e não escreve ledger.

### RLS, lifecycle e efeitos

Todas as seis tabelas públicas nascem com ENABLE/FORCE RLS. SELECT
administrativo exige `read.all_tenant`; lookup e preview passam por RPCs de
projeção própria. `checklist_template_items` não recebe SELECT direto de
cliente: seus campos aparecem somente no detalhe autorizado do Modelo. INSERT,
UPDATE e DELETE diretos são negados; mutations ocorrem apenas por RPC.
`PUBLIC`, `anon`, `service_role` e `cw_worker` não recebem atalhos. Helpers e
tabelas privadas têm owner técnico, `search_path = ''`, nomes qualificados e
grants mínimos. Tenant e ator são derivados de `auth.uid()` e fatos atuais.

Guards exatos:

- Categoria não inativa com Subcategoria ou Modelo ativo;
- Subcategoria e Modelo não reativam sob Categoria inativa;
- Motivo não muda `usage_context`;
- Modelo inativo preserva integralmente seus itens;
- inativos saem de lookup, mas continuam legíveis por read autorizado;
- nenhuma transição produz cascade ou DELETE físico;
- Tipo de Documento não cria nem referencia Storage;
- referências futuras relerão tenant, contexto e status dentro do command
  consumidor.

Create/update/inactivate/reactivate emitem respectivamente eventos v1
`maintenance.category.*`, `maintenance.subcategory.*`,
`maintenance.reason.*`, `cadastros.document_type.*` e
`maintenance.checklist_template.*`. A aplicação emite
`cadastros.catalog_template.applied`, além dos eventos de criação das cópias.
Mutation, Audit, History, Outbox e idempotência são atômicos; payloads são
mínimos e não carregam descrição, instruções completas, authority ou PII.

### Concorrência e testes

O runner multi-session W4C provará 12 classes:

1. create concorrente com mesmo código e mesma key;
2. create com keys distintas contra a mesma unicidade de negócio;
3. dois updates com a mesma versão;
4. inactivate versus update do mesmo registro;
5. inactivate Categoria versus create Subcategoria;
6. inactivate Categoria versus reactivate Subcategoria;
7. inactivate Categoria versus create/reactivate Modelo;
8. update de definição do Modelo versus inactivate Categoria;
9. duas aplicações do Template com a mesma key;
10. duas aplicações com keys distintas;
11. aplicação do Template versus criação manual nos catálogos-alvo;
12. colisão concorrente de Subcategoria na Categoria e de Motivo no contexto.

Constraints tenant-aware, locks pai-antes-do-filho, lock comum de
tenant/catálogos, expected version e idempotência W3 definem o resultado. Não
há check-then-insert no cliente.

O pgTAP cobrirá schema, FKs, uniques/checks, lifecycle, grants, RLS,
anti-enumeration, tenant isolation, exact permissions/baselines/rollout,
Custom Profiles/overrides, cada command/read, idempotência, atomicidade,
eventos, Template opcional/vazio/replay/rollback/sem auto-sync, contexto de
Motivo e ausência de Storage/W5+. Unitários cobrirão schemas Zod strict,
normalização/fingerprint, tipos de resposta, projeções, query keys e gateway.
Gateway tests cobrirão 21 commands e 16 reads por RPC, argumentos, parse
fail-closed e erros. Typecheck, lint, build e E2E existente continuam gates;
W4C não cria UI/E2E novo. Reset local, todos os pgTAP W1–W4B, runners
anteriores, runner W4C e smoke integram a regressão final.

### Typed boundary e subdivisão executiva

Após as migrations e validação DB, `npm run db:types` será executado somente
contra Supabase LOCAL. `database.types.ts` nunca será editado manualmente. Os
arquivos previstos são `src/shared/maintenance/maintenance-catalogs.ts` e
testes, além de
`src/infrastructure/supabase/maintenance-catalog-gateway.ts` e testes. Eles
conterão status/tipos/contextos, inputs dos 21 commands, resultados strict,
projeções dos 16 reads, items de checklist, query keys tenant-aware e gateway
autenticado sem authority local ou acesso direto a tabelas.

A implementação será dividida em quatro blocos internos:

1. **W4C.1 — Authorization Contract and Rollout**: 31 permissions, baselines
   20/5/5/2, templates v3→v4 e rollout. Gate
   `W4C_AUTHORIZATION_CATALOG_READY`;
2. **W4C.2 — Maintenance Taxonomy and Template CW**: Categorias,
   Subcategorias, Motivos, Template v1, commands/reads, RLS, efeitos, pgTAP e
   concorrência aplicável. Gate `W4C_MAINTENANCE_TAXONOMY_READY`;
3. **W4C.3 — Supporting Catalog Skeletons**: Tipos de Documento e Modelos de
   Checklist/itens, boundaries DB e testes, sem Storage ou execução. Gate
   `W4C_SUPPORTING_CATALOGS_READY`;
4. **W4C.4 — Typed Boundary and Integrated Hardening**: tipos gerados,
   boundary/gateway, unitários e regressão W1–W4C.3. Gate oficial
   `W4C_MAINTENANCE_CATALOGS_READY`.

Cada bloco possui migration/testes/documentação próprios quando houver banco e
um commit isolado após seu gate. Migrations anteriores não são editadas. O
congelamento deste plano não inicia W4C.1, W4D ou qualquer domínio operacional.
`CADASTRO_READY` permanece `NO` até W4D.

## W4C.1 — Authorization Contract and Rollout

Em 2026-09-21 foi implementado o contrato de autorização da W4C.1, sem
antecipar domínio, commands, read models, boundary TypeScript ou UI. A migration
`20260918000000_w4c_authorization_contract_rollout.sql` publica exatamente as
31 permissions congeladas no módulo `maintenance`, todas com entitlement
`maintenance`, delegáveis e restritas ao scope exato `ALL_TENANT`. Não foram
criados scopes TEAM, OWN ou ASSIGNED, ações genéricas `use`/`manage`, wildcard
ou permission adicional para preview. As cinco permissions `reactivate`
existem no catálogo e permanecem fora dos baselines oficiais.

Os System Profile Templates oficiais avançam de v3 para v4 com baselines W4C
exatos de 20 grants para Manager, 5 para Technician, 5 para Assistant e 2 para
Requester. Somente Manager recebe `catalog_templates.apply`; todo grant dos
perfis subordinados também existe como combinação exata no Manager, preservando
o contrato de antiescalada sem grants preventivos.

O rollout `w4c_maintenance_catalogs_v1` reutiliza o ledger compartilhado,
seleciona perfis oficiais exclusivamente por `template_key`, é determinístico,
add-only e idempotente, e preserva Custom Profiles, grants existentes, nomes de
exibição e exact overrides. Tenants existentes recebem somente os grants W4C
aprovados; novos tenants usam diretamente os templates v4 por meio do
provisionamento existente.

O pgTAP `w4c_authorization_contract_rollout.sql` cobre o catálogo 31/31, matriz
de baselines, ausência dos scopes e ações proibidos, delegação exata,
`reactivate`, boundary do helper privilegiado e boundary incremental do domínio,
rollout/replay, preservação de customizações, tenants existentes e novos,
AUTH-01 fail-closed e regressão dos catálogos W2/W4A/W4B. O inventário de
hardening W2E foi estendido somente para allowlistar o novo helper privado, e o
runner local passou a incluir a migration e o pgTAP W4C.1. A prova histórica
de ausência de domínio foi posteriormente evoluída pela W4C.2 para aceitar
somente suas tabelas/boundaries e continuar proibindo a antecipação da W4C.3.
A fixture histórica
W4B.1 agora exercita seu rollout na versão v3 dentro da própria transação e
restaura v4 antes de continuar, preservando tanto a prova original quanto o
estado corrente introduzido pela W4C.1.

Os gates sem Docker passaram com 195/195 testes unitários, typecheck, lint,
build e 6/6 cenários E2E. O reset externo aplicou todas as migrations com
sucesso. A primeira regressão DB externa executou 1.008 testes e revelou três
expectativas históricas incompletas: as allowlists cumulativas W2B/W2D ainda
terminavam na W4B.1, e a fixture W4C tentava reutilizar o bootstrap inicial
one-shot para um segundo tenant. As allowlists passaram a enumerar exatamente
os grants W4C.1, e a prova de novo tenant passou a usar o mecanismo real
`private.provision_tenant_authorization` sobre uma fixture de tenant, conforme
o padrão W2B. `SYSTEM_ALREADY_INITIALIZED` e o bootstrap de produção não foram
alterados. O reteste externo posterior passou com lint de schema `public` e
`private`, 19 arquivos pgTAP e 1.014 assertions, além dos runners de
concorrência e runtime existentes. Com a evidência DB aprovada,
`W4C_AUTHORIZATION_CATALOG_READY = YES`. Os gates
`W4C_MAINTENANCE_CATALOGS_READY` e `CADASTRO_READY` permanecem `NO`.

## W4C.2 — Maintenance Taxonomy and Template CW

Em 2026-09-22 foi implementado o recorte autorizado da W4C.2: Categorias e
Subcategorias de Manutenção, seus commands/read models e o Template CW v1 da
taxonomia. A migration
`20260918001000_w4c_maintenance_taxonomy_template.sql` cria
`public.maintenance_categories` e `public.maintenance_subcategories` como
entidades tenant-owned com lifecycle `active|inactive`, optimistic locking,
autoria e unicidade normalizada de código. A relação composta
`(tenant_id, category_id)` limita estruturalmente o domínio a dois níveis e
impede referência cross-tenant; não existe árvore genérica, `team_id`, cascade
de lifecycle ou hard delete.

Os nove commands explícitos cobrem create/update/inactivate/reactivate das
duas entidades e a aplicação do Template CW. Eles derivam tenant e ator do
contexto, usam a permission
exata do Resource mutado, lock autoritativo do ator, lock transacional comum da
taxonomia, idempotência W3, expected version e efeitos Audit/History/Outbox. A
Categoria não inativa com Subcategoria ativa, e Subcategoria não nasce nem
reativa sob Categoria inativa. A permission de lookup continua sendo apenas
discovery e não é pré-condição de mutation. O guard adicional contra Modelo de
Checklist ativo será acrescentado somente quando a W4C.3 criar esse domínio.

Os sete read models são `list_maintenance_categories`,
`get_maintenance_category`, `lookup_maintenance_categories`,
`list_maintenance_subcategories`, `get_maintenance_subcategory` e
`lookup_maintenance_subcategories`, além de `get_cw_catalog_template_preview`.
List/get exigem `read`, lookup exige
`lookup`, inativos permanecem administrativamente legíveis mas não aparecem
nos seletores, e o filtro por Categoria nunca amplia o tenant derivado.

O mecanismo privado usa `private.catalog_templates`,
`private.catalog_template_entries` e
`private.catalog_template_applications`, sem grant direto de cliente.
`get_cw_catalog_template_preview` reutiliza a capability exata
`maintenance.catalog_templates.apply.all_tenant` e expõe somente versão,
contagens e conteúdo allowlisted. `apply_cw_catalog_template` aceita somente o
Template `cw_maintenance_taxonomy` v1, exige os dois catálogos integralmente
vazios sob o mesmo lock das mutations manuais, cria cópias tenant-owned em uma
transação e registra ledger único, Audit da aplicação, History/Event por cópia
e Event da aplicação. Replay é estável; chaves diferentes não duplicam o
ledger; não há merge, auto-sync ou FK runtime dos registros tenant para o
template global.

O Template CW v1 contém exatamente as 11 Categorias e 39 Subcategorias já
congeladas, inclusive as duas ocorrências contextualmente válidas de
“Iluminação de emergência”. Motivos, Tipos de Documento, Modelos/Itens de
Checklist, boundary TypeScript, tipos gerados e UI permanecem ausentes deste
recorte. O runner `w4c-concurrency-test.mjs` cobre 12 casos aplicáveis à
taxonomia: replay e colisão de create, optimistic update, update/inactivate,
duas disputas pai-filho, unicidade contextual, duas formas de concorrência na
aplicação, aplicação versus criação manual de Categoria/Subcategoria e
rollback atômico. As duas classes congeladas que dependem de Modelo de
Checklist serão exercitadas quando esse domínio existir na W4C.3; não foi
fabricado um domínio antecipado para simulá-las.

O pgTAP `w4c_maintenance_taxonomy_template.sql`, o inventário cumulativo W2E,
o boundary histórico W4C.1 e o smoke local foram atualizados para o novo
contrato. A validação externa final, após reset local completo, aprovou lint de
schema `public` e `private`, 20 arquivos pgTAP com 1.091 assertions, as 75
assertions W4C.2 e os 12 casos de concorrência do Template CW. O smoke final
foi aprovado com as migrations W0-W3/W4A/W4B.1-W4B.2/W4C.1-W4C.2. Assim,
`W4C_TAXONOMY_TEMPLATE_READY = YES` e `W4C_AUTHORIZATION_CATALOG_READY = YES`.
`W4C_MAINTENANCE_CATALOGS_READY` e `CADASTRO_READY` permanecem `NO`.

## W4C.3 — Supporting Catalog Skeletons

Em 2026-09-23 foi implementado o domínio DB da W4C.3 na migration
`20260918002000_w4c_supporting_catalog_skeletons.sql`, sem antecipar a boundary
tipada da W4C.4. O recorte cria `public.maintenance_reasons`,
`public.document_types`, `public.checklist_templates` e
`public.checklist_template_items`. As quatro estruturas são tenant-owned,
possuem relações compostas tenant-safe, grants mínimos e ENABLE/FORCE RLS. Os
itens permanecem subordinados ao Modelo: não possuem Resource, permission,
RPC ou acesso direto independente.

Motivos aceitam exatamente `CANCEL_REQUEST`, `REJECT_REQUEST`,
`PAUSE_WORK_ORDER`, `CANCEL_WORK_ORDER` e `RETURN_WORK_ORDER`. O contexto é
obrigatório e imutável. Tipos de Documento armazenam apenas metadados de
classificação e não criam Storage. Modelos de Checklist exigem Categoria ativa
e possuem definição atômica e ordenada com os tipos `DONE_NOT_DONE`,
`CONFORMING_NONCONFORMING`, `YES_NO`, `TEXT`, `NUMBER` e `OBSERVATION`; não
existem execução, respostas, evidências ou snapshot de OS nesta wave.

Os 12 commands e nove read models congelados reutilizam exclusivamente as
permissions W4C.1 e o entitlement `maintenance`. Tenant e ator vêm do contexto
autenticado atual; não foram criados TEAM, OWN ou ASSIGNED. Commands retornam
somente `{id, version, status, command_correlation_id}` e reutilizam Audit,
History, Outbox, idempotência, optimistic locking e lifecycle existentes.
Inativos deixam lookup sem desaparecer de list/get administrativos. Não há
hard delete, cascade ou mutação direta de cliente. Categoria não inativa com
Modelo ativo e Modelo não reativa sob Categoria inativa.

### Clarificação arquitetural da W4C.3 — Opção 3

A decisão formal desta implementação preserva a imutabilidade semântica do
Template CW v1:

- `W4C3_REASON_DOMAIN = IMPLEMENTED`;
- `W4C3_REASON_SEEDS = DEFERRED`;
- `TEMPLATE_CW_V1_CHANGED = NO`.

O Template `cw_maintenance_taxonomy`, versão 1 e schema 1, continua contendo
exatamente 11 Categorias e 39 Subcategorias. Maintenance Reasons não integram
esse template e nenhum tenant recebe Reason automaticamente na W4C.3. Não há
auto-sync, merge, Template v2 ou mecanismo de upgrade v1→v2. Os seeds de
`CANCEL_WORK_ORDER` e `RETURN_WORK_ORDER` continuam deferidos como já previsto;
os demais contextos também ficam sem seed nesta wave para não alterar
retroativamente o contrato do Template v1. Uma futura estratégia de
seed/versionamento/upgrade exigirá decisão explícita separada.

O pgTAP `w4c_supporting_catalog_skeletons.sql` cobre estrutura, contracts,
grants, RLS, contexts, lifecycle, optimistic locking, autorização,
anti-enumeration, efeitos, idempotência, ausência de seeds e preservação exata
do Template v1. O runner `w4c3-concurrency-test.mjs` mantém sessões PostgreSQL
independentes, reaplica JWT/role em cada conexão e cobre 12 disputas reais de
replay, unicidade contextual, versões, lifecycle pai-filho e substituição
atômica da definição. O inventário cumulativo W2E, os boundaries históricos e
o smoke local foram evoluídos sem enfraquecer a proteção contra ondas futuras.
A validação externa final reconstruiu a cadeia completa com
`npm run db:reset` e aprovou `npm run test:v2:db`: lint dos schemas `public` e
`private`, 21 arquivos pgTAP com 1.172 assertions e todos os runners,
inclusive os 12 casos reais de `w4c3-concurrency-test.mjs`. Durante a
validação, o trigger compartilhado foi corrigido para acessar
`usage_context` somente no branch de `maintenance_reasons`; Document Type e
Checklist Template não acessam esse campo. As expectativas de teste foram
alinhadas ao contrato real de History (`history_type`) e aos quatro creates
legítimos do cenário — dois Motivos, um Tipo de Documento e um Modelo de
Checklist — sem relaxar Audit, History, Outbox ou idempotência.

Assim, `W4C_SUPPORTING_CATALOGS_READY = YES`. A W4C.4 ainda é necessária para
o gate integrado: `W4C_MAINTENANCE_CATALOGS_READY = NO` e `CADASTRO_READY = NO`.
`READY_FOR_W4C4 = YES`.

## W4C.4 — Typed Boundary and Integrated Hardening

Em 2026-09-23 foi concluída a boundary tipada integrada da W4C, sem alterar
migrations, sem alterar a semântica de autorização e sem antecipar W4D. O
contrato em `src/shared/maintenance-catalogs/maintenance-catalogs.ts` valida
estritamente os 21 commands, os 16 read models, os resultados de command e o
resultado imutável de aplicação do Template CW. Ele preserva os cinco contextos
de Motivo, os seis tipos de resposta de Checklist, UUIDs, versões positivas,
enums, paginação e a regra de posições únicas dos itens de Checklist. O
resultado legado `correlation_id` não é aceito; a boundary exige
`command_correlation_id`.

`src/infrastructure/supabase/maintenance-catalog-gateway.ts` expõe somente os
37 contratos aprovados e usa exclusivamente RPCs autenticadas. Tenant, ator,
papel e escopo não são aceitos como autoridade em payloads do cliente; não há
consulta direta a tabelas, `service_role` ou bypass de RLS. Respostas SQL são
validadas antes de cruzar a boundary, falhas de autorização/conflito/estado são
normalizadas para `AppError` e detalhes anti-enumeration permanecem `null`.
As query keys incluem explicitamente a identidade do tenant, resource,
projection e filtros, sem introduzir autoridade de tenant no command.

Os testes unitários de boundary e gateway cobrem o conjunto de commands e
leituras, o mapeamento RPC, ausência de acesso `from`, payloads inválidos,
projeções expandidas, erros de autorização/conflito, resultados malformados,
Template CW e isolamento de cache. `database.types.ts` foi preservado como
artefato gerado externamente por `SUPABASE_CLI_LOCAL`; nenhuma edição manual ou
regeneração foi realizada nesta wave. A evidência DB externa W4C.3 permanece a
autoridade para migrations, pgTAP, RLS, grants e concorrência; nenhum comando
Docker/Supabase local foi executado nesta etapa de boundary.

Assim, `W4C_MAINTENANCE_CATALOGS_READY = YES`, `CADASTRO_READY = NO` e
`READY_FOR_W4D = YES`.

## W4D — Plano executivo da experiência de Cadastros

### Estado e precedência

Planejamento iniciado em 2026-09-23 sobre o commit W4C.4
`0df257e508b0d536764542cb7b8be383bcc16d3f`, sem iniciar UI ou alterar
contratos. W4A, W4B e W4C estão fechadas. O plano W4 original, seções 20–21,
24 e 26, continua sendo a base; este detalhamento mantém suas rotas e critérios
e usa o domínio realmente entregue. `CADASTRO_READY = NO` até o gate integrado.

Decisões posteriores prevalecem sobre duas descrições históricas: `use`
genérico dos cadastros foi retirado por decisão W4A/W4B/W4C; `lookup` é
somente descoberta e não substitui `read` nem autoriza mutations. O Template
CW v1 efetivo contém 11 Categorias e 39 Subcategorias, sem seeds de Motivos,
conforme a Opção 3 da W4C.3. A proposta antiga de copiar Motivos no Template
não descreve o artefato fechado e não será recuperada pela UI.

O código atual usa React Router com rotas filhas de `e/:tenantRef`,
`TenantRouteBoundary` e `TenantAppShell`; só há `dashboard` e `minha-conta`
no tenant. O helper `canonicalTenantPath` hoje aceita apenas esses destinos e
precisará suportar caminhos tenant validados, sem tratar `tenantRef` como
autoridade. `PermissionGuard` usa a projeção W2 por permission code exato e
entitlement; a autorização final permanece nas RPCs/RLS. `tenantQueryKey`
já inclui principal, tenant, membership/revisões, perfil, revisão de catálogo,
revisão de autorização e geração. As factories W4A/B/C acrescentam resource,
projection e filtros, mas não substituem essa identidade de sessão. Há
`Button` e `StatePanel`; não existem ainda tabela, filtro, diálogo, seletor ou
formulário RHF de Cadastros na V2. Os E2E existentes cobrem somente fundação
pública/sem autenticação; testes autenticados exigirão fixture local própria.

### Arquitetura de informação e rotas reais

Um único item primário **Cadastros** no shell. A página inicial mostra grupos
e links somente quando há capacidade de leitura da página (`read.all_tenant`
ou, para Equipes, `read.team`):

- **Estrutura:** Tipos de Local, Locais, Centros de Custo, Setores;
- **Pessoas e Equipes:** Equipes, com roster como detalhe subordinado;
- **Manutenção:** Categorias/Subcategorias, Motivos, Tipos de Documento,
  Modelos de Checklist; Template CW aparece junto da taxonomia quando houver
  `maintenance.catalog_templates.apply.all_tenant` e entitlement.

Paths canônicos abaixo de `/e/:tenantRef` (todos registrados no router, não
trocas de painel na mesma URL):

| Recurso | Lista | Detalhe/edição | Relação ou ação |
| --- | --- | --- | --- |
| entrada | `cadastros` | — | cards de grupos autorizados |
| Tipos de Local | `cadastros/tipos-de-local` | `cadastros/tipos-de-local/:locationTypeId` | — |
| Locais | `cadastros/locais` | `cadastros/locais/:locationId` | filhos no detalhe |
| Centros de Custo | `cadastros/centros-de-custo` | `cadastros/centros-de-custo/:costCenterId` | filhos no detalhe |
| Setores | `cadastros/setores` | `cadastros/setores/:sectorId` | — |
| Equipes | `cadastros/equipes` | `cadastros/equipes/:teamId` | `cadastros/equipes/:teamId/membros` |
| Categorias/Subcategorias | `manutencao/categorias` | `manutencao/categorias/:categoryId` | `manutencao/categorias/:categoryId/subcategorias/:subcategoryId` |
| Motivos | `manutencao/motivos` | `manutencao/motivos/:reasonId` | filtro `contexto` na URL |
| Tipos de Documento | `cadastros/tipos-de-documento` | `cadastros/tipos-de-documento/:documentTypeId` | — |
| Modelos de Checklist | `manutencao/modelos-de-checklist` | `manutencao/modelos-de-checklist/:templateId` | editor de itens no detalhe |
| Template CW | `manutencao/categorias/template-cw` | — | preview e aplicação explícita |

Criação e edição usam formulários em diálogo na lista/detalhe; a página
subjacente conserva sua URL e o registro editado tem URL de detalhe. Deep link,
refresh e back/forward precisam preservar página e filtros (texto, status,
parent, contexto e paginação real) via query string validada. `cadastros`
mostra as opções permitidas; sem nenhuma, apresenta `NoPermissionPage`.
Detalhes com UUID inválido caem em estado inexistente seguro. URL desconhecida
permanece no `NotFoundPage` após validação do tenant. Sem session/contexto,
aplica-se `TenantRouteBoundary`; sem capability da página, estado sem
permissão, sem chamada de list/get/lookup. O redirect do índice tenant para
`dashboard` permanece. Não redirecionar automaticamente usuário sem permissão
para um recurso que não pode ler.

### Capabilities de UX

Usar `useAuthorization` e projeção atual para comparar códigos exatos, nunca
nome de Perfil. Páginas administrativas exigem `*.read.all_tenant`; ações
create/update/move/inactivate/reactivate/add/end/apply exigem seu código
exato. Manutenção também exige entitlement `maintenance`. Equipes são exceção:
list/detail podem ser lidos por `shared.teams.read.team` ou
`shared.teams.read.all_tenant`, como alternativas independentes; `my-teams`
é projeção self. Roster exige `shared.team_memberships.read.all_tenant`, e
  add/end suas permissions próprias. A ação add fica no detalhe da Team mesmo
  sem permissão de roster; nesse caso somente o seletor capability-bound fica
  disponível, sem listar vínculos. End precisa de roster autorizado para
  selecionar a associação existente. Acesso apenas a `lookup` nunca abre tela
administrativa. Selectors utilizam as respectivas RPCs de lookup quando o
usuário possui a capability; caso contrário, preservam o valor atual no
detalhe autorizado e não consultam a coleção inteira. `reactivate` só aparece
com grant explícito; nenhum dos quatro baselines o recebe automaticamente.
Manager não ganha update de Tipos de Documento/Modelos de Checklist por nome
de Perfil; Custom Profiles com grants exatos podem exercer essas ações.

### Experiência por recurso

- **Estrutura:** list/get administrativo com busca, status e offset/limit
  suportados pelas RPCs; Local e Centro de Custo mostram filhos diretos, pai e
  mudança de pai via command `move`, sem árvore arbitrária no cliente. Local
  seleciona Tipo ativo; Centro de Custo permanece independente de Local.
  Confirmar inativação, preservar inativos em list/get, removê-los de lookup.
  Explicar bloqueio por Local/filho ativo e por Team ativa ao inativar Setor.
- **Equipes:** list/detail, Setor opcional, lifecycle e roster paginado.
  Mostrar ao próprio usuário `listMyTeams` quando a projeção TEAM estiver
  disponível; múltiplas Teams aparecem separadamente. Roster só para quem
  possui `team_memberships.read`. Add cria novo período; end pede confirmação
  e versão atual; período `ended` é imutável. Inativação de Team com membro
  ativo explica a necessidade de encerrar vínculos primeiro. Alteração de
  membership requer atualização de autorização e cache derivado. A seleção
  de novo membro usa somente a projection capability-bound definida abaixo;
  o command `add_team_member` revalida a elegibilidade no momento do write.
- **Taxonomia:** Categoria e Subcategoria na mesma área, com Subcategorias
  filtradas pelo `categoryId` real. Profundidade exatamente dois; não há árvore
  genérica. Bloqueio de inativação de Categoria com Subcategoria ou Modelo
  ativo e de reativação de filho sob Categoria inativa deve indicar o próximo
  passo sem cascade.
- **Template CW:** entrada contextual em Categorias; preview autorizado de
  `cw_maintenance_taxonomy` v1, 11/39, antes de confirmação. `Começar vazio`
  apenas fecha a escolha, sem command. A UI pode mostrar elegibilidade
  informativa após consultar listas, mas o command é a decisão final:
  `MAINTENANCE_TAXONOMY_NOT_EMPTY` e aplicação prévia são tratados como
  indisponibilidade, sem merge. Aplicação espera resposta transacional,
  invalida Categoria/Subcategoria/preview relevante e esclarece que as cópias
  são editáveis e não recebem sincronização ou upgrade. Motivos continuam
  vazios até cadastro explícito; nenhuma seed é prometida.
- **Motivos:** uma lista com filtro de contexto na query string e nomes
  legíveis para os cinco valores fechados. O contexto é escolha obrigatória
  na criação e somente leitura no detalhe/edição. Inativos ficam em list/get,
  não em lookup. Não consumir Motivos em Request/OS nesta wave.
- **Tipos de Documento:** list/get/lookup e lifecycle apenas para grants
  específicos; administrar classificação textual, sem upload, arquivo ou
  Storage. O baseline Manager é leitura/lookup.
- **Modelos de Checklist:** list/get/lookup, Categoria ativa, status e editor
  da definição completa. Itens são linhas ordenadas com `position` 1..10000,
  `prompt`, `response_type` fechado, `required` e `instructions` anulável.
  Adicionar/remover/reordenar por controles simples de subir/descer; no save,
  enviar um array completo de 1..200 itens com posições únicas via
  `updateChecklistTemplateDefinition` e `expectedVersion`. Não emitir writes
  parciais de item. Conflito exige refetch e revisão antes de novo save.
  Sem execução, resposta, evidência, OS ou snapshot nesta wave.

### Formulários, queries, erros e acessibilidade

RHF com resolver Zod somente para estado de formulário; derivar os campos de
inputs das boundaries W4A/B/C, sem criar outra regra de domínio. Converter
campo opcional de UI para `null` quando o command exige nullable; não omitir
`reason`, correlation ID, idempotency key ou `expectedVersion` onde exigidos.
Defaults vêm de get autorizado; update usa a versão carregada e não altera
status por patch. Criar idempotency key por intenção/submissão e mantê-la em
retry da mesma intenção; nova intenção recebe nova key. Em erro, preservar
valores e não reportar sucesso. Cancelar descarta alterações; proteção de
formulário sujo só se testes de navegação demonstrarem perda relevante.

Compor `tenantQueryKey(projection, authorizationGeneration, resource,...)`
com segmento W4A/B/C de resource/projection/id/filtros normalizados; uma
única composição em hooks evita omitir principal/revisões. Incluir
`categoryId`, `usageContext`, `teamId` no seletor de candidatos, status, busca,
offset e limite quando aplicáveis.
Não usar nome exibido ou `tenantRef` como identidade. Após sucesso confirmado,
invalidar listas, detalhe e lookups afetados; mudanças pai/filho invalidam
ambas as famílias; Team add/end invalida roster, candidatos do seletor,
my-teams e projeção de autorização; Template apply invalida taxonomia. Logout,
revogação, mudança de
contexto e sessão são tratados pelos providers existentes com cancelamento e
limpeza de cache. Não persistir roster ou payload tenant-owned em storage do
navegador. Invalidation deve usar prefixes compostos verificados por testes.

Usar `AppError.code`/categoria e códigos de domínio conhecidos, sem exibir
SQL, stack ou detalhes de outro tenant. Cobrir: `AUTHORIZATION_DENIED`,
`*_VERSION_CONFLICT`, duplicidade/SQLSTATE `23505`, pai indisponível ou
inativo, `ACTIVE_*_DEPENDENCY`/`ACTIVE_*_CHILDREN`,
`TEAM_STATE_OR_VERSION_CONFLICT`, `MAINTENANCE_TAXONOMY_NOT_EMPTY`,
`CW_CATALOG_TEMPLATE_ALREADY_APPLIED`, estado inválido, resposta malformada e
falha de rede. Recarregar detalhe após conflito sem sobrescrever edição local
silenciosamente. Gate de implementação deve verificar se os gateways atuais
preservam código seguro suficiente para esses casos; se não, corrigir somente
normalização de erro da boundary existente, com teste focal, sem alterar SQL.

Padrões reutilizáveis mínimos: lista paginada responsiva, filtros com labels,
status em texto, ações acessíveis, estado vazio e vazio por filtro, `StatePanel`
para indisponibilidade/sem permissão, botão de retry, confirmação com foco
controlado para inativar/encerrar/aplicar, `aria-live` para resultado, loading
e disabled durante mutation. Dialog fecha/restaura foco; teclado opera tudo;
alvos de toque e layout funcionam em celular. Não criar design system geral.

### Subwaves executáveis e testes

| Bloco | Entrega e arquivos prováveis | Dependência / gate de saída |
| --- | --- | --- |
| W4D.1 — Shell, rotas e primitives | `src/app/router`, `layout`, `pages/cadastros`, `shared/ui`, hooks de query; IA, guards, estados, lista/filtros/dialog/form patterns | W4C fechado; rotas reais, deep link, refresh, denied e query identity testados; `W4D_ROUTE_SHELL_READY` |
| W4D.2 — Estrutura e Equipes | páginas/hook/componentes de Tipos, Locais, CC, Setores, Teams e roster; uma migration forward-only para `lookup_team_member_candidates`, tipos gerados, boundary Zod/gateway/query key e seletor | W4D.1; migration, pgTAP de segurança e regressão W4B aprovados antes do seletor; CRUD autorizado, move, lifecycle, add/end e invalidação testados; `W4D_STRUCTURAL_TEAM_UX_READY` |
| W4D.3 — Manutenção | páginas/hook/componentes de taxonomia, Template CW, Motivos, Tipos de Documento e Modelos/itens; gateway W4C existente | W4D.1; 11/39 preview/apply, contexto, definição atômica e grants de leitura/mutation testados; `W4D_MAINTENANCE_UX_READY` |
| W4D.4 — Hardening integrado | testes de rota, componentes e E2E, docs W4 e revisão de segurança; somente correções focadas dentro da W4 | W4D.2/.3; regressão e gate final `CADASTRO_READY` |

Unit/component tests: matriz de capability exata por recurso, estados
loading/empty/error/denied, validação/nullability, submissão e retry,
optimistic conflicts, códigos de lifecycle, filtros URL, query keys e
invalidation. O seletor de Team testa boundary Zod para os três campos,
`teamId`/busca/paginação na query key, páginas sucessivas, nome nulo ou
duplicado, ausência de autorização e candidate stale rejeitado no add.
Route tests: cada path, UUID/tenantRef inválido, deep link,
refresh/back/forward, mudança de contexto e isolamento de menu. E2E
autenticado local: create/update/inactivate de Local e Categoria; Team
add/end e efeito em my-teams/roster; Template preview/apply e escolha vazia;
Checklist definição atômica; conflito de versão e dependência ativa; usuário
sem read; logout/troca de contexto sem dados antigos; viewport mobile e
teclado nos fluxos críticos. Testes DB existentes seguem responsáveis por
RLS, tenant, Audit/History/Outbox, idempotência e concorrência real; não
duplicá-los em mock UI. A única migration W4D precisa de pgTAP próprio:
elegível autorizado; tenant membership, app_user ou Team inativos; outro
tenant; par ativo excluído; par `ended` elegível; Team alheia/inativa
rejeitada; `add.all_tenant` obrigatório e `read.all_tenant` isolado
insuficiente; paginação e desempate determinísticos; limite máximo; busca
server-side; nomes iguais sem confusão de IDs; SELECT direto de dados alheios
continua negado; TEAM reach e RLS intactos; regressão W4B. Na W4D.4 executar
reset e smoke DB local externo
quando disponível, pgTAP/runners, unit, E2E, typecheck, lint, build e
`git diff --check` sem enfraquecer regressões.

`CADASTRO_READY = YES` exige todos os blocos, navegação real e gestão utilizável
dos recursos W4A/B/C segundo grants, add/end de membros, Template CW opcional,
erro/lifecycle/conflito tratados, cache e contexto isolados, ausência de reads
diretos/service role/autoridade de frontend, nenhuma execução/Storage/W5,
testes e auditoria integrada aprovados, documentação refletindo código real.
Existência de páginas isoladas não basta. W4D ainda não foi implementada.

### Exceção congelada: seleção de membro de Equipe

`add_team_member(team_id, membership_id,...)` requer UUID da tenant
membership alvo. O único roster W4B, `list_team_members`, consulta pessoas
que já tiveram vínculo com a Equipe; `list_teams_for_membership` exige que o
UUID já seja conhecido. As policies W1 de `tenant_memberships` e `app_users`
permitem SELECT comum somente do próprio ator. Não há RPC ou gateway de
lookup/lista de memberships do tenant para formar o seletor de novo membro.
Um campo de UUID digitado manualmente não é experiência administrativa
utilizável e não cria o primeiro vínculo de modo descobrível. A W4D não pode
resolver isso por SELECT direto, relaxamento de RLS, service role no cliente,
uso indevido do roster ou diretório genérico de usuários.

Decisão aprovada para W4D.2: **uma** migration forward-only mínima acrescenta
`public.lookup_team_member_candidates(target_team_id uuid, search_text text
default null, result_limit integer default 20, result_offset integer default
0)`. O nome segue `lookup_teams` e `lookup_*` da W4A/C; é descoberta mínima
para o seletor do `add_team_member`, não página administrativa nem consulta de
roster. Uma boundary Zod, gateway e query key correspondentes seguem na mesma
subwave, depois da migration local e regeneração de `database.types.ts`; nada
disso é implementado neste planejamento.

A RPC usa `private.assert_w4b_all_tenant_access('team_memberships','add')`,
que deriva o ator de `auth.uid()`, exige app_user, tenant e tenant membership
ativos e consulta a permissão exata efetiva, inclusive Perfil ativo e
overrides. A permissão é **`shared.team_memberships.add.all_tenant`**,
catalogada na W4B com `required_entitlement_key = null`; não há entitlement
adicional aplicável. `shared.team_memberships.read.all_tenant` sozinho não
concede acesso. Isso reutiliza a mesma capability específica do command, sem
criar implicação `read`/`lookup`/`add`, hierarquia, permissão nova ou mudança de
AUTH-01/AUTH-02. A Team alvo deve existir no tenant derivado e estar `active`,
como exige `add_team_member`; Team alheia ou inativa retorna
`TEAM_UNAVAILABLE`. Contexto sem autorização falha fechado com
`AUTHORIZATION_DENIED` conforme helper W4B. O parâmetro `target_team_id` é
alvo, nunca autoridade de tenant. A RPC não aceita `tenant_id` nem
`actor_user_id`.

Projeção exata: `membership_id uuid`, `user_id uuid`, `display_name text`
nullable. Os três campos existem em `tenant_memberships.id`,
`tenant_memberships.user_id` e `app_users.display_name`. `membership_id` é o
argumento do command; `user_id` diferencia pessoas com nomes iguais ou nulos;
o seletor apresenta o nome, quando houver, e um identificador inequívoco.
Não expõe e-mail, perfil, revision, overrides, entitlement, sessão, histórico
ou estado administrativo. Somente memberships do tenant derivado com
`membership.status = 'active'` e `app_user.status = 'active'` são elegíveis.
Excluir por `NOT EXISTS` apenas o par `(tenant_id, team_id, membership_id)`
com Team membership `status = 'active'`; um vínculo `ended` não exclui o
candidato e o retorno continua criando novo período. Não inferir identidade
ou elegibilidade por `display_name`.

Busca server-side opcional e parametrizada somente por `display_name` como
substring literal case-insensitive; `%` e `_` do usuário não viram curingas.
Entrada é aparada e limitada a 160 caracteres; vazio equivale a ausência de
filtro. Nomes nulos aparecem sem filtro e não correspondem a texto de busca.
Paginação segue o padrão list/roster W4 de `result_limit/result_offset`:
default 20, limite inclusivo 1..100, offset não negativo; entrada inválida
recebe `INVALID_QUERY_INPUT`. Ordem determinística por `display_name`
case-insensitive com nulos ao fim, depois `user_id`, depois `membership_id`.
O seletor pede a página seguinte com `offset + quantidade retornada` quando
recebe uma página cheia; uma página vazia encerra a navegação. A UI não baixa
o tenant inteiro para filtrar localmente. Resultado é sugestão de momento:
`add_team_member` segue como autoridade final e pode rejeitar candidato que
mudou entre lookup e command, com refetch e mensagem de conflito.

A função será `security definer` com `search_path = ''`, referências
qualificadas, grants mínimos de EXECUTE apenas a `authenticated`, owner e
revoke conforme convenção W4B. Nenhum helper privilegiado novo é necessário.
RLS e grants das tabelas permanecem; SELECT direto de outros usuários e
memberships continua negado. A migration não altera Team, lifecycle,
permissões, engine, TEAM reach ou efeitos de membership mutation. Nenhuma
outra migration W4D fica planejada.

Com essa exceção e os gates acima, `W4D_PLAN_FROZEN = YES`,
`READY_FOR_W4D_IMPLEMENTATION = YES` e `CADASTRO_READY = NO` até a entrega
integrada. `MIGRATIONS_PLANNED = YES` (exatamente uma, em W4D.2), sem
implementação funcional nesta execução.

### W4D.1 — Shell, rotas e padrões de UI implementados

O router registra a raiz `cadastros` e os 21 paths de recurso/detalhe/relação
congelados acima sob o `TenantRouteBoundary` existente. O índice tenant ainda
redireciona para `dashboard`; paths desconhecidos preservam `NotFoundPage`.
`canonicalTenantPath` somente constrói destinos estáticos registrados, após
validar `tenantRef` como referência de navegação. IDs de detalhe inválidos
entram no estado seguro de rota inexistente.

O shell ganhou um único link primário **Cadastros**, ativo tanto nos paths
`cadastros/*` quanto nos paths cadastrais `manutencao/*`. A raiz apresenta
somente grupos e links que a projeção de autorização atual permite por código
exato; Equipes aceita independentemente `read.team` ou `read.all_tenant`, sem
calcular TEAM no cliente. Manutenção também exige entitlement. `lookup`,
create e reactivate isolados não abrem página administrativa. Sem capability,
o índice e as rotas mostram `NoPermissionPage`. A checagem de UI não substitui
o servidor.

As rotas de recurso são shells explícitos de **funcionalidade em preparação**:
nenhum registro, ação CRUD, preview, seletor, query ou RPC é simulado. Padrões
mínimos compartilhados incluem header semântico e estados distintos de
loading/empty/error com retry; `StatePanel` aceita subtítulo h2 para uso após
o h1 da página. Forms, filtros, dialogs e mutations de domínio aguardam as
subwaves correspondentes. Não houve migration, alteração de tipos de banco,
gateway, permissão, AUTH-01, AUTH-02 ou RLS.

Evidência local: testes de rota com contexto e projeção simulados cobrem os 21
deep links de recurso, índice, permissão exata, entitlement, navegação ativa,
back, UUID inválido e path desconhecido; E2E sem sessão cobre deep link de
Cadastros e refresh fail-closed. O harness browser atual não possui fixture
autenticada, portanto E2E autenticado da experiência completa permanece para
W4D.4. `npm run test:v2:unit`, `typecheck`, `lint`, `build` e `test:v2:e2e`
passaram. `W4D_SHELL_ROUTES_READY = YES`;
`W4D_STRUCTURAL_TEAMS_EXPERIENCE_READY = NO`;
`W4D_MAINTENANCE_EXPERIENCE_READY = NO`;
`W4D_INTEGRATED_HARDENING_READY = NO`; `CADASTRO_READY = NO`;
`READY_FOR_W4D2 = YES`.

### W4D.2.1 — Candidate lookup de Team Membership implementado

A única migration forward-only W4D, `20260919000000_w4d_team_member_candidate_lookup.sql`,
acrescenta `public.lookup_team_member_candidates` com a assinatura congelada.
A função reaproveita `private.assert_w4b_all_tenant_access('team_memberships',
'add')`: ator e tenant vêm de `auth.uid()` e dos fatos ativos do banco, com a
capability exata `shared.team_memberships.add.all_tenant`. Teams não exigem
entitlement adicional no catálogo W4B. A Team alvo deve estar ativa no mesmo
tenant; o retorno contém somente `membership_id`, `user_id` e `display_name`
nullable de memberships e app_users ativos, excluindo apenas par ativo na
Team. Um par `ended` pode reaparecer.

Busca por display name usa substring literal case-insensitive, incluindo `%`
e `_` como caracteres normais. Busca nula/vazia não filtra; nome nulo aparece
apenas sem filtro. O limite padrão é 20, máximo 100, offset não negativo; a
ordem é nome case-insensitive com nulos ao final, `user_id`, `membership_id`.
A RPC é read-only, `SECURITY DEFINER` com `search_path` vazio, referências
qualificadas e EXECUTE somente para `authenticated`. Grants/RLS de tabelas,
permissões, engine, TEAM reach, `add_team_member` e revision bump não mudaram.
O lookup é sugestão no momento da leitura; o command W4B e sua unicidade de
par ativo continuam validando e serializando a mutation concorrente. Por isso
o runner W4B não precisou de caso ou lock adicional nesta etapa.

`supabase/tests/w4d_team_member_candidate_lookup.sql` foi incluído no smoke
local após W4C.3, mantendo os testes W4B e runners existentes. O arquivo usa
`no_plan()`, `finish()` e rollback, com fixtures de dois tenants e cobertura
de capability, elegibilidade, RLS, busca, paginação, TEAM e ausência de
Audit/History/Outbox/idempotência. Em PowerShell normal, `npm run db:reset`
e `npm run test:v2:db` passaram com 22 arquivos e 1221 assertions, incluindo
o smoke e os runners locais; `npm run db:types` regenerou
`database.types.ts` a partir desse banco. Docker não foi executado no sandbox.
Gateway e UI aguardam etapa posterior. Assim,
`W4D_TEAM_MEMBER_CANDIDATE_READ_MODEL_IMPLEMENTED = YES`,
`W4D_TEAM_MEMBER_CANDIDATE_READ_MODEL_VALIDATED = YES`,
`W4D_STRUCTURAL_TEAMS_EXPERIENCE_READY = NO` e `CADASTRO_READY = NO`.

### W4D.2.2 — experiência de Estrutura e Equipes implementada

As rotas congeladas de Tipos de Local, Locais, Centros de Custo, Setores,
Equipes e roster agora consomem exclusivamente os gateways W4A/W4B e a
projection mínima de candidatos W4D.2.1. A autorização de cada leitura e ação
é consultada somente pela projection de sessão; mutations usam commands com
correlation/idempotency, versionamento e invalidação tenant-scoped. Os
placeholders de Manutenção permanecem para W4D.3. Esta entrega não altera o
modelo de banco, permissões, RLS ou `database.types.ts`.

O hardening final acrescentou páginas reais de lista e detalhe, formulários
RHF/Zod, seletores alimentados pelos lookups W4A, `move` para Locais e Centros
de Custo, setor opcional de Equipe, confirmações acessíveis de lifecycle e
reread após sucesso ou conflito. As query keys incluem principal, tenant,
membership, versões e geração de autorização; add/end invalidam roster,
candidatos e projeções de Team. O helper de rota canônica passou a aceitar
somente os paths dinâmicos congelados quando seus parâmetros são UUIDs.

A suíte de componentes autenticados cobre os recursos estruturais, Equipes,
roster, capabilities exatas, optimistic locking, estados, invalidação e o uso
de `membership_id` no command. O total passou da base de 271 para 296 testes.
Não há E2E autenticado no harness atual; os sete E2E não autenticados foram
preservados.

`W4D_STRUCTURAL_TEAMS_EXPERIENCE_IMPLEMENTED = YES`;
`W4D_STRUCTURAL_TEAMS_EXPERIENCE_READY = YES`;
`W4D_MAINTENANCE_EXPERIENCE_READY = NO`;
`W4D_INTEGRATED_HARDENING_READY = NO`; `CADASTRO_READY = NO`.

### W4D.3 — experiência dos Cadastros de Manutenção implementada

As rotas congeladas de Categorias e Subcategorias de Manutenção, Motivos,
Tipos de Documento e Modelos de Checklist agora consomem exclusivamente o
gateway W4C. Listas, detalhes, criação, edição e lifecycle respeitam cada
capability exata e independente da projection de sessão. As mutations enviam
correlation/idempotency, versão esperada e invalidam somente as projeções
tenant-scoped relacionadas. Não há acesso direto a tabelas, nova migration,
alteração de RLS, autorização, tipos gerados ou contrato de backend.

A taxonomia continua com profundidade exata de dois níveis: Subcategoria é
gerida dentro da Categoria, sem árvore recursiva. Motivos apresentam rótulos
humanos para os cinco contextos congelados e enviam os enums W4C ao servidor.
Tipos de Documento permanecem apenas metadados, sem upload ou Storage.
Modelos de Checklist editam sua definição e itens de forma atômica, incluindo
ordem, pergunta, instruções, tipo de resposta e obrigatoriedade; não existe
lifecycle individual de item no contrato W4C e nenhuma execução de checklist
foi antecipada.

O Template CW permanece opcional e imutável. A tela mostra o preview e exige
capability `maintenance.catalog_templates.apply.all_tenant` e confirmação
explícita antes do command. A regra empty-only e a criação de cópias do tenant
continuam autoritativas no servidor; não foram introduzidos merge, autosync,
upgrade ou edição do template privado.

Os testes de componentes autenticados cobrem rotas reais, capabilities
independentes, filtros server-side, formulários, optimistic locking, estados
seguros, invalidação, definição atômica do checklist e aplicação/rejeição do
Template CW. A auditoria final acrescentou cobertura específica de conflito
stale em Subcategoria, provando version forwarding e refetch do detalhe filho;
o hardening de acessibilidade passou a expor erros Zod associados aos controles,
e a prova de versionamento/refetch foi explicitada para Motivos e Tipos de
Documento. O total local passou da base de 296 para 324 testes. O hardening
integrado e o gate final permanecem reservados para W4D.4.

`W4D_MAINTENANCE_EXPERIENCE_IMPLEMENTED = YES`;
`W4D_STRUCTURAL_TEAMS_EXPERIENCE_READY = YES`;
`W4D_MAINTENANCE_EXPERIENCE_READY = YES`;
`W4D_INTEGRATED_HARDENING_READY = NO`; `CADASTRO_READY = NO`.

### W4D.4 — hardening integrado e gate final concluídos

A auditoria integrada confirmou que todas as rotas obrigatórias de Cadastros
resolvem experiências reais W4A/W4B/W4C; o fallback defensivo de rota passou a
falhar como não encontrado, sem placeholder residual. Tenant e principal das
query keys continuam derivados da projection autoritativa, enquanto
`tenantRef` é usado somente na navegação canônica. Não há leitura ou mutation
direta de tabela, autorização local, persistência tenant-owned paralela nem
efeitos W3 fabricados pelo frontend.

O hardening alinhou os formulários estruturais e de Equipes ao padrão
acessível da Manutenção: erros Zod possuem `role=alert`, controles inválidos
expõem `aria-invalid` e nomes acessíveis permanecem estáveis. Mensagens antigas
são limpas no início de novas mutations. O roster ganhou retorno explícito à
Equipe e mutations de membership agora invalidam todas as páginas e filtros de
candidatos pelo prefixo tenant-scoped, além de roster e projeções de Team.

A matriz integrada cobre shell, rotas/deep links, estados seguros, recursos
estruturais, Teams/roster/candidatos, `membership_id`, catálogos de Manutenção,
capabilities exatas, optimistic locking, stale handling, isolamento de cache,
invalidação filter-safe, acessibilidade e regressões W1/W2/W3. A base passou de
324 para 325 testes. A auditoria offline de dependências de produção não
encontrou vulnerabilidades conhecidas. O aviso de bundle acima de 500 kB
permanece residual e não bloqueante, sem dependência nova ou regressão material
identificada.

A validação final de banco foi executada externamente em PowerShell normal. O
Docker local, o reset completo, os 22 arquivos pgTAP com 1.221 assertions, o
smoke DB, os runners de concorrência e o runner adversarial passaram. O
`preflight:v2` registrou somente `WARN_EXPECTED_DIRTY_WORKTREE`, esperado para
os quatro arquivos deste fechamento; não houve falha bloqueante nos demais
checks. Essa evidência externa complementa os gates não-DB executados nesta
sessão e encerra a W4 sem alteração de migration, tipos gerados, RPC,
autorização, RLS ou escopo W5.

`W4D_INTEGRATED_HARDENING_IMPLEMENTED = YES`;
`W4D_INTEGRATED_HARDENING_READY = YES`;
`DB_RESET = PASS`; `DB_TEST = PASS`;
`PGTAP_FILES = 22`; `PGTAP_TESTS = 1221`;
`DB_SMOKE = PASS`; `CONCURRENCY = PASS`;
`ADVERSARIAL = PASS`;
`PREFLIGHT = WARN_EXPECTED_DIRTY_WORKTREE`;
`PREFLIGHT_BLOCKING_FAILURE = NO`;
`PENDING_EXTERNAL_DB_VALIDATION = NO`; `CADASTRO_READY = YES`;
`W4_COMPLETE = YES`.
