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
`reactivate`, boundary do helper privilegiado, ausência das tabelas de domínio,
rollout/replay, preservação de customizações, tenants existentes e novos,
AUTH-01 fail-closed e regressão dos catálogos W2/W4A/W4B. O inventário de
hardening W2E foi estendido somente para allowlistar o novo helper privado, e o
runner local passou a incluir a migration e o pgTAP W4C.1. A proteção histórica
contra antecipação das tabelas W4C permanece inalterada. A fixture histórica
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
`W4C_MAINTENANCE_CATALOGS_READY` e `CADASTRO_READY` permanecem `NO`; W4C.2 não
foi iniciada.
