# Implementação da W2 — Authorization

## Estado

Este documento registra a execução incremental da W2. O contrato aprovado
permanece em `docs/IMPLEMENTACAO-V2-W2-PLANO.md`.

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = YES
W2B_PROFILES_OVERRIDES_READY = YES
W2C_AUTHORIZATION_ENGINE_READY = YES
W2D_AUTHORIZATION_PROJECTION_READY = YES
W2E_AUTHORIZATION_HARDENING_READY = YES
AUTHORIZATION_READY = YES
```

## W2A — modelo e catálogo estrutural

### Escopo implementado

A W2A implementa exclusivamente as migrations W2-01 e W2-02 previstas no
plano:

- enum público `authorization_scope` com `OWN`, `ASSIGNED`, `TEAM` e
  `ALL_TENANT` como valores exatos, sem hierarquia ou precedência;
- `public.permission_catalog`, uma linha por combinação válida de
  `module + resource + action + scope`;
- `private.authorization_catalog_state`, singleton de revisão monotônica do
  catálogo;
- templates privados e versionados `manager`, `technician`, `assistant` e
  `requester`;
- relação privada de grants dos templates para provisionamento futuro;
- seed determinístico das onze combinações administrativas mínimas de
  `core.users` e `core.profiles`;
- tipos TypeScript regenerados pelo Supabase CLI a partir do banco local;
- pgTAP W2A integrado ao smoke oficial.

Não foram criados perfis tenant, grants tenant, overrides, vínculo de perfil na
membership, evaluator, scope resolver, commands de governança, projeção/cache,
UI, resources funcionais de módulos, Global Admin ou RLS de domínios futuros.

### Migrations

| Migration | Responsabilidade |
| --- | --- |
| `20260914000000_w2a_authorization_catalog.sql` | Enum dos scopes, catálogo, revisão privada, templates, constraints, triggers de integridade, RLS fechada e grants mínimos |
| `20260914001000_w2a_platform_seed.sql` | IDs e códigos determinísticos, quatro templates e baseline administrativo mínimo do template Gestor |

As migrations W0/W1 não foram alteradas. A cadeia foi reconstruída do zero no
Supabase local descartável com `npm run db:reset`.

### Modelo físico e integridade

`permission_catalog` usa UUID declarado pela migration, `code` semântico,
`module_code`, `resource_code`, `action_code`, enum de scope,
`required_entitlement_key`, `tenant_delegable`, chaves de apresentação, status
e timestamps. Os códigos obedecem exatamente:

```text
<module>.<resource>.<action>.<scope>
```

Os segmentos usam lowercase/snake_case. Há unicidade independente de `code` e
da tupla `(module_code, resource_code, action_code, scope)`. ID, código e tupla
estrutural são imutáveis. O catálogo aceita lifecycle `active → deprecated`,
preserva o registro e rejeita hard delete. Labels e descriptions são metadados
e não participam de autorização.

`authorization_catalog_state` possui uma única linha e revisão `bigint > 0`.
Cada insert ou update de catálogo incrementa a revisão na mesma transação. A
revisão não pode permanecer igual, diminuir ou ser apagada. O seed inicial
produz revisão determinística `12`: revisão base `1` mais onze linhas válidas.
Esse mecanismo apenas sinaliza mudança estrutural; projection/cache continuam
deferidos para W2D.

Os templates são plataforma-owned e privados. Eles não entram na decisão
runtime. Sua relação com o catálogo representa somente o conteúdo a copiar no
provisionamento W2B; nenhuma permission foi concedida a usuário, membership ou
tenant na W2A.

### Catálogo e seed

O seed contém exatamente:

```text
core.users.read.all_tenant
core.users.invite.all_tenant
core.users.assign_profile.all_tenant
core.users.manage_overrides.all_tenant
core.users.change_status.all_tenant
core.profiles.read.all_tenant
core.profiles.create.all_tenant
core.profiles.update.all_tenant
core.profiles.activate.all_tenant
core.profiles.inactivate.all_tenant
core.profiles.change_permissions.all_tenant
```

As onze combinações são `active`, `tenant_delegable = true`, usam
`required_entitlement_key = null` e pertencem somente a `core`. O template
Gestor referencia as onze; Técnico, Auxiliar e Solicitante não recebem grant
funcional prematuro.

Deliberadamente não foram semeados `tenant_settings`, Ativos, Fornecedores,
Cadastros, Relatórios, Solicitações, OS, Preventiva, Calendário, comments,
anexos, scopes `OWN`/`ASSIGNED`/`TEAM` de domínio, wildcard `manage`, capability
de plataforma ou Global Admin. A existência desses namespaces no plano não
autoriza produto cartesiano ou grant antecipado.

### Segurança

`permission_catalog` nasce com RLS habilitada e sem policy. `PUBLIC`, `anon`,
`authenticated` e `service_role` não possuem privilégio direto no catálogo,
estado de revisão ou templates. O enum também não concede `USAGE` a
`PUBLIC`/roles cliente. Tenant comum e cliente anônimo não podem ler, criar,
alterar ou excluir permissions estruturais.

As três funções de trigger W2A são `SECURITY INVOKER`, possuem `search_path`
vazio, referências qualificadas, owner não cliente e nenhum `PUBLIC EXECUTE`.
Não foi necessário criar `SECURITY DEFINER`, helper de autorização, bypass ou
policy temporária.

`ALL_TENANT` permanece limitado conceitualmente ao tenant corrente; não existe
grant de tenant, evaluator ou target de domínio nesta etapa. Membership,
entitlement e Global Admin continuam conceitos separados.

### Types

`src/infrastructure/supabase/database.types.ts` foi regenerado pelo fluxo
oficial `npm run db:types`, sem edição manual. O diff adiciona somente
`permission_catalog` e o enum `authorization_scope`; tabelas privadas não são
projetadas no schema público tipado.

### Testes e evidências

`supabase/tests/w2a_authorization_catalog.sql` contém 58 asserts e comprova:

- tabelas e taxonomia exata dos quatro scopes;
- ausência de hierarquia/precedência estrutural;
- seed e UUIDs determinísticos;
- onze combinações válidas, sem produto cartesiano;
- unicidade de code e tupla estrutural;
- formato de código, entitlement e lifecycle;
- imutabilidade de identidade, deprecation e proibição de hard delete;
- revisão inicial, incremento por insert/update e monotonicidade;
- quatro templates e grants somente no template Gestor;
- presença das entidades W2B após a wave seguinte, sem alterar as invariantes do catálogo;
- RLS fechada, grants mínimos, owners e `search_path`;
- ausência de `SECURITY DEFINER`;
- negação direta para `PUBLIC`, `anon`, `authenticated` e `service_role`.

Evidências locais:

| Validação | Resultado |
| --- | --- |
| `npm run preflight:v2` antes da implementação | `WARN`: Docker ainda não estava acessível ao processo; demais checks passaram |
| `npm run db:start` | `PASS`: Supabase local iniciado |
| `npm run db:reset` | `PASS`: oito migrations W0/W1/W2A aplicadas do zero |
| `npm run db:types` | `PASS`: tipos regenerados contra o banco local |
| schema lint | `PASS`: nenhum erro no schema público |
| `npm run test:v2:db` | `PASS`: 6 arquivos e 218/218 asserts pgTAP; W2A 58/58; `DB_SMOKE_OK` |
| `npm run test:v2:unit` | `PASS`: 12 arquivos e 65/65 testes |
| `npm run test:v2:e2e` | `PASS`: 6/6 testes Chromium |
| `npm run typecheck` | `PASS` |
| `npm run lint` | `PASS` |
| `npm run build` | `PASS`: 246 módulos; aviso não bloqueante de chunk acima de 500 kB |
| `git diff --check` | `PASS` |
| `npm run verify:v2:full` antes do commit | Todos os gates `PASS`; resultado agregado `WARN` somente porque o worktree da missão ainda estava dirty antes do commit |

Durante o primeiro run da nova suíte, os 42 asserts anteriores ao erro passaram,
mas a introspecção tentou tratar o pseudo-grantee SQL `PUBLIC` como role em
`has_type_privilege`. O teste foi corrigido para consultar
`information_schema.usage_privileges`; nenhuma migration ou regra de produção
foi relaxada. A repetição passou integralmente.

O comando local de start também foi ajustado para não ecoar as credenciais
descartáveis emitidas pelo CLI. O harness agora captura essa saída e informa
somente que o Supabase local iniciou. Nenhum valor foi persistido ou
versionado.

### Itens deferidos

- **W2C:** evaluator, entitlement enforcement, resolvers, RLS funcional,
  governance commands, antiescalada e Audit dessas mutações.
- **W2D:** projection self, vetor de revisão, provider, cache e generation local.
- **W2E:** hardening consolidado, policies/grants finais e testes adversariais da
  W2 integrada.

### Gate W2A

O catálogo estrutural é reproduzível, determinístico, fechado para clientes e
testado em PostgreSQL/Supabase local real. O gate isolado está aprovado:

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = YES
W2B_PROFILES_OVERRIDES_READY = NO
W2C_AUTHORIZATION_ENGINE_READY = NO
W2D_AUTHORIZATION_PROJECTION_READY = NO
W2E_AUTHORIZATION_HARDENING_READY = NO
AUTHORIZATION_READY = NO
```

Nenhum Supabase remoto, `db push`, `migration repair`, deploy, push, merge ou PR
faz parte desta execução.

## W2B — profiles, baseline, overrides e provisioning

### Objetivo e escopo

A W2B implementa exclusivamente as migrations W2-03 a W2-06 do plano
aprovado. O estado autoritativo agora representa:

```text
membership → tenant profile → baseline ALLOW
membership → override exato ALLOW/DENY
```

Não foi criado evaluator final, resolver de `OWN`/`ASSIGNED`/`TEAM`, alcance de
registro, antiescalada, command administrativo autenticado, projection/cache,
PermissionGuard, UI administrativa, Global Admin ou RLS de domínio. As novas
tabelas permanecem fechadas até os commands e o evaluator da W2C.

### Modelo físico

`public.tenant_profiles` contém identidade interna, tenant proprietário, nome
editável, origem imutável `template_key + template_version`, lifecycle
`active/inactive`, `version`, timestamps e autoria. Nome é somente label: não é
consultado por bootstrap, convite, assignment ou qualquer decisão de
autoridade. Há unicidade de nome normalizado entre perfis ativos, uma cópia de
cada template por tenant e chave composta `(tenant_id, id)`.

`public.tenant_profile_permissions` é a relação exata de baseline. Presença da
linha significa `ALLOW`; ausência significa deny implícito. Não há coluna
`effect`, baseline `DENY` ou `INHERIT`. A FK composta impede profile de outro
tenant e a FK de catálogo impede permission inexistente. Nova relação para
permission deprecated é rejeitada; relações históricas permanecem preservadas
para o evaluator W2C ignorar pelo estado atual do catálogo.

`public.tenant_permission_overrides` pertence à membership e aceita somente
`allow` ou `deny`. Ausência da linha significa herdar o baseline. A unicidade
`(membership_id, permission_id)` impede efeitos simultâneos conflitantes e a FK
composta `(tenant_id, membership_id)` impede associação cross-tenant. Remover a
linha retorna à herança.

`tenant_memberships` recebeu `profile_id`, `profile_assigned_at` e
`profile_assigned_by`. Membership `active` ou `blocked` exige profile ativo do
mesmo tenant; membership histórica `revoked` pré-W2 pode manter `null` e não
ganha autoridade. O profile permanece na revogação quando já conhecido.

`tenant_invitations` recebeu `target_profile_id`. Novo convite pending exige
profile ativo do mesmo tenant, o target torna-se imutável e o aceite o copia
atomicamente para a membership. Convite legado sem target falha fechado e deve
ser revogado/reemitido; nenhum profile é inferido por nome ou e-mail.

### Lifecycle, integridade e concorrência estrutural

Profiles não sofrem hard delete. A inativação preserva o registro e é bloqueada
enquanto houver membership operacional atribuída. Profile inativo não pode ser
atribuído nem usado como target de novo convite.

As relações tenant-specific usam FKs compostas, não dependem de RLS para
coerência. IDs válidos de outro tenant são rejeitados para baseline,
membership, override e convite. Unicidade relacional impede duplicatas sob
concorrência.

`tenant_profiles.version` avança em mudança do agregado do profile, inclusive
nome, lifecycle e cada adição/remoção de baseline. `tenant_memberships.version`
continua usando o mecanismo W1 e avança em assignment e em cada
adição/alteração/remoção de override. Cada override também possui versão própria.
`authorization_catalog_state.catalog_revision` continua exclusivamente sob a
W2A. Os checks `expected_version` dos commands pertencem à W2C; a W2B entrega o
estado persistido, triggers e unicidade necessários sem antecipar commands
parciais.

### Provisioning e backfill

`private.provision_tenant_authorization` é `SECURITY INVOKER`, sem grant a
roles de API, serializa por tenant e copia uma única vez os quatro templates
privados para profiles tenant-owned. Somente grants do template no momento da
criação são copiados. Retry não renomeia, reativa, restaura baseline removido,
altera versões ou emite Audit duplicado. Permission futura não é retroativa.

O bootstrap W1 foi substituído por nova definição forward-only, sem editar a
migration W1: cria o tenant suspenso, provisiona os quatro profiles, atribui
Gestor ao criador e somente então ativa o tenant. O backfill atribui Gestor
apenas à membership registrada no marcador autoritativo do primeiro bootstrap.
Se existir outra membership operacional sem inferência documental segura, a
migration aborta com `W2B_BACKFILL_REQUIRES_EXPLICIT_PROFILE_ASSIGNMENT` em vez
de conceder autoridade silenciosamente.

Os templates privados continuam separados e não participam do runtime. Gestor
recebe as onze permissions administrativas W2A; Técnico, Auxiliar e Solicitante
permanecem com baseline vazio até as waves donas dos módulos funcionais.

### Audit e segurança

Provisioning efetivo escreve `authorization.tenant_provisioned` no
`audit_events` append-only existente, com tenant, correlation, contagens e
proveniência segura. Execução sistêmica usa ator `technical`; bootstrap usa o
usuário real. Retry sem alteração não gera evento. Audit detalhado de rename,
lifecycle, baseline, assignment e overrides será transacional nos commands W2C;
essas mutações não foram expostas diretamente a clientes na W2B.

As três tabelas públicas novas têm RLS habilitada, zero policies e nenhum
privilégio para `PUBLIC`, `anon`, `authenticated` ou `service_role`. Todas as
funções privadas W2B fixam `search_path` vazio e não possuem `PUBLIC EXECUTE`.
Nenhuma nova função `SECURITY DEFINER` foi criada; apenas as boundaries W1 de
bootstrap, criação de convite e aceite foram substituídas preservando seu modelo
de grants. `authenticated` continua sem mutation administrativa antes da W2C.

### Migrations

| Migration | Responsabilidade |
| --- | --- |
| `20260914002000_w2b_tenant_profiles.sql` | Profiles tenant-owned, baseline ALLOW, índices, triggers de identidade/versão e RLS fechada |
| `20260914003000_w2b_membership_authorization.sql` | Vínculo membership-profile, target do convite, overrides, FKs compostas e revisão da membership |
| `20260914004000_w2b_provisioning_backfill.sql` | Provisioning privado idempotente, integração forward-only com bootstrap/convites e backfill fail-closed |
| `20260914005000_w2b_integrity_finalization.sql` | Profile obrigatório operacional, lifecycle, validação das constraints e proteção de targets |

As migrations W0, W1 e W2A não foram alteradas. A cadeia completa de doze
migrations foi aplicada do zero no Supabase local descartável.

### Types, testes e evidências

`src/infrastructure/supabase/database.types.ts` foi regenerado exclusivamente
por `npm run db:types`. O diff reflete as três tabelas W2B, os novos campos de
membership/invitation, suas relações e a nova assinatura profile-aware do
command de convite. Tabelas e command privados não são projetados no schema
público tipado.

`supabase/tests/w2b_profiles_overrides_provisioning.sql` contém 77 asserts. A
suíte prova modelo físico, lifecycle, nome sem autoridade, hard delete,
baseline por presença, override ALLOW/DENY/herança, versões, profile obrigatório,
profile inativo, targets de convite, aceite atômico, fail-closed legado,
idempotência, preservação de customização, não retroatividade, Tenant A/B, FKs
compostas, RLS, grants, owners e `search_path`.

Os fixtures W1 foram adaptados somente para provisionar profiles e fornecer o
novo vínculo obrigatório. A semântica W1 de bootstrap, convite, contexto,
membership operacional única e lifecycles foi preservada. O teste W2A foi
atualizado apenas para reconhecer que as tabelas formalmente deferidas agora
existem.

| Validação | Resultado |
| --- | --- |
| `npm run preflight:v2` inicial | `WARN`: Docker não estava visível no sandbox; branch, HEAD, worktree, arquivos e toolchain passaram |
| `npm run db:start` | `PASS`: Supabase local iniciado sem expor credenciais |
| `npm run db:reset` | `PASS`: doze migrations W0/W1/W2A/W2B aplicadas do zero |
| `npm run db:types` | `PASS`: tipos regenerados pelo CLI local |
| schema lint | `PASS`: nenhum erro no schema público |
| `npm run test:v2:db` | `PASS`: 7 arquivos, W2B 77/77 e total 295/295; `DB_SMOKE_OK` |
| `npm run test:v2:unit` | `PASS`: 12 arquivos e 65/65 testes |
| `npm run test:v2:e2e` | `PASS`: 6/6 Chromium |
| `npm run typecheck` | `PASS` |
| `npm run lint` | `PASS` |
| `npm run build` | `PASS`: 246 módulos; aviso preexistente de chunk acima de 500 kB |

### Falhas encontradas e correções

O primeiro smoke ocorreu com o runtime local parado; o Supabase descartável foi
iniciado e o reset passou. Na primeira regressão após o schema novo, fixtures W1
ainda criavam memberships/convites sem profile e três asserts W2A ainda
esperavam ausência das tabelas W2B. Os fixtures foram ajustados ao contrato
novo, sem mudar semântica W1. Um segundo ciclo revelou o nome físico
`default_name` nos templates privados; o provisioning foi corrigido e a suíte
W1/W2A voltou a 218/218. A suíte W2B foi então adicionada e passou integralmente.

### Itens deferidos e gate W2B

- **W2C:** evaluator exato, entitlement enforcement, resolvers de scope,
  commands autenticados, antiescalada, optimistic concurrency por
  `expected_version`, Audit detalhado e enforcement funcional.
- **W2D:** projection self, vetor de revisão, provider, cache e generation local.
- **W2E:** policies/grants finais, hardening consolidado e matriz adversarial da
  autorização integrada.

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = YES
W2B_PROFILES_OVERRIDES_READY = YES
W2C_AUTHORIZATION_ENGINE_READY = NO
W2D_AUTHORIZATION_PROJECTION_READY = NO
W2E_AUTHORIZATION_HARDENING_READY = NO
AUTHORIZATION_READY = NO
```

Nenhum Supabase remoto, `db push`, `migration repair`, deploy, push, merge ou PR
faz parte da W2B.

## W2C — authorization engine, commands e antiescalada

### Escopo e decisão autoritativa

A W2C implementa exclusivamente W2-07 e W2-08 do plano aprovado. O evaluator
privado `private.resolve_effective_scopes(resource_code, action_code)` deriva o
principal de `auth.uid()` e reconsulta `app_users`, tenant, membership, profile,
catálogo, baseline, override e entitlement atuais. A decisão usa combinações
exatas:

```text
ALLOW exato = override ALLOW
           ou (sem override e baseline presente)
DENY exato  = override DENY
           ou ausência de ALLOW
PERMIT      = combinação efetiva + entitlement habilitado + alcance do alvo
```

Scopes são um conjunto sem hierarquia. Um `DENY` substitui somente a combinação
exata; `ALL_TENANT` significa todo o tenant corrente e nunca cross-tenant. O
evaluator separa capacidade efetiva de alcance de registro. Como W2C não cria
Solicitação, OS, Ativo, owner, assignment ou equipe, não existe resolver de
domínio artificial: os comandos administrativos usam apenas as combinações
`core.*.*.all_tenant` existentes e validam o tenant real do alvo. `OWN`,
`ASSIGNED` e `TEAM` permanecem fail-closed para recursos até a wave dona de
cada entidade publicar seus fatos e resolver dedicado.

`required_entitlement_key` é aplicado tanto ao evaluator quanto aos conjuntos
prospectivos usados pela antiescalada. Permission com entitlement ausente ou
desabilitado não é efetiva por baseline nem por override.

### Commands e concorrência

Foram publicados onze entrypoints `SECURITY DEFINER`, executáveis somente por
`authenticated`:

- criar, renomear, ativar e inativar profile;
- adicionar ou remover uma permission exata do baseline;
- atribuir profile à membership;
- criar/alterar e remover override individual;
- bloquear, reativar ou revogar membership operacional;
- convidar usuário e revogar/expirar convite por boundaries autenticadas.

Os comandos não recebem ator, tenant, profile corrente, scopes ou fatos de
autorização do cliente. Eles derivam o contexto atual, serializam mutações por
tenant com advisory lock, bloqueiam estado autoritativo, revalidam lifecycle e
permission e só então alteram dados. Targets usam IDs opacos, sempre são
restringidos ao tenant corrente e falhas de existência/tenant retornam erro não
enumerativo. Mutações pontuais exigem `expected_version`; overrides validam as
versões da membership e da própria exceção.

Convites reutilizam as primitivas W1/W2B restritas a `service_role` depois da
autorização autenticada. O token plaintext é devolvido uma única vez pelo
resultado do command; somente SHA-256 é persistido e nenhum Audit recebe o
token, e-mail plaintext ou segredo.

### Antiescalada e último administrador

Além da permission administrativa do command, toda transição que muda uma
combinação de não efetiva para efetiva exige simultaneamente que o ator possua
a mesma combinação exata e que `tenant_delegable = true`. O cálculo compara
conjuntos antes/depois em assignment de profile, considera remoção de `DENY`,
valida baseline, overrides e profile de convite, e não usa nome, ranking ou
papel especial. Assim, autoescalada, escalada indireta e grants não delegáveis
falham fechados.

Após toda mutação capaz de reduzir autoridade, a transação exige pelo menos uma
membership ativa com o conjunto administrativo `core.users` + `core.profiles`
completo e efetivo. A falha `LAST_AUTHORIZATION_ADMIN_REQUIRED` desfaz alteração
e Audit na mesma transação.

### Segurança, RLS e Audit

Helpers do evaluator e da antiescalada ficam em `private`, sem `EXECUTE` para
`PUBLIC`, `anon`, `authenticated` ou `service_role`. Todos fixam `search_path`
vazio, usam referências qualificadas e têm owner não cliente. As boundaries
públicas concedem somente `EXECUTE` a `authenticated`; tabelas continuam sem
grants de mutation. Nenhuma policy permissiva, bypass, wildcard, Global Admin,
`service_role` frontend ou autorização baseada em JWT mutável foi criado.

Cada command efetivo escreve no `audit_events` append-only na mesma transação,
com ator derivado, tenant, correlation, reason, alvo e versões anterior/nova.
Falha de versão, autorização, antiescalada ou último administrador não deixa
mutação nem evento parcial.

### Migrations, types e testes

| Migration | Responsabilidade |
| --- | --- |
| `20260914006000_w2c_authorization_evaluator.sql` | AUTH-01, entitlement, helpers de conjuntos prospectivos, delegação exata e detecção do administrador efetivo |
| `20260914007000_w2c_authorization_commands.sql` | AUTH-02, commands autenticados, locks, expected versions, antiescalada, último administrador e Audit |

`src/infrastructure/supabase/database.types.ts` foi regenerado pelo Supabase CLI
local. O diff tipado da W2C contém somente as novas funções públicas; helpers
privados não são projetados.

`supabase/tests/w2c_authorization_engine.sql` contém 57 asserts sobre AUTH-01,
entitlements, lifecycle atual contra JWT stale, scopes exatos, grants, owners,
`search_path`, commands, versions, Tenant A/B, autoescalada, escalada indireta,
permission não delegável, último administrador, Audit e segurança do token.

| Validação | Resultado |
| --- | --- |
| `npm run preflight:v2` inicial | `WARN`: Docker não estava visível no sandbox; branch, HEAD, worktree, arquivos e toolchain passaram |
| `npm run db:start` | `PASS`: Supabase local descartável iniciado sem expor credenciais |
| `npm run db:reset` | `PASS`: quatorze migrations W0/W1/W2A/W2B/W2C aplicadas do zero |
| `npm run db:types` | `PASS`: tipos regenerados pelo CLI local após o reset final |
| schema lint | `PASS`: nenhum erro no schema público |
| `npm run test:v2:db` | `PASS`: 8 arquivos, W2C 57/57 e total 352/352; `DB_SMOKE_OK` |
| `npm run test:v2:unit` | `PASS`: 12 arquivos e 65/65 testes |
| `npm run test:v2:e2e` | `PASS`: 6/6 Chromium |
| `npm run typecheck` | `PASS` |
| `npm run lint` | `PASS` |
| `npm run build` | `PASS`: 246 módulos; aviso preexistente de chunk acima de 500 kB |
| `git diff --check` | `PASS` |
| `npm run verify:v2:full` pré-commit | Gates DB, unit, E2E, typecheck, lint, build e diff-check em `PASS`; agregado `WARN` somente pelo worktree da missão ainda dirty |

Durante a construção da suíte, o role autenticado não podia ler fixtures
temporárias sem grant explícito; as referências foram isoladas numa tabela
temporária com `SELECT` mínimo. A instalação pgTAP local não oferecia o matcher
`like(text,text,...)`, substituído por uma asserção regex equivalente. Uma
fixture de convite expirado tentou inicialmente violar o check histórico
`expires_at > created_at`; ela passou a representar corretamente um convite
criado no passado. Por fim, a assinatura de criação de override foi ajustada
para que ausência de versão anterior seja opcional também nos tipos gerados,
sem afrouxar a versão obrigatória em updates. Nenhuma correção relaxou regra de
produção, RLS, grant ou antiescalada.

### Gate W2C e itens deferidos

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = YES
W2B_PROFILES_OVERRIDES_READY = YES
W2C_AUTHORIZATION_ENGINE_READY = YES
W2D_AUTHORIZATION_PROJECTION_READY = NO
W2E_AUTHORIZATION_HARDENING_READY = NO
AUTHORIZATION_READY = NO
```

Permanecem deferidos para W2D projection self, vetor de revisão, cache,
generation e provider/guards de UX. W2E permanece responsável pelo hardening
consolidado, policies/grants finais e matriz adversarial integrada. Recursos e
RLS funcionais pertencem às waves dos módulos donos dos dados. Nenhum Supabase
remoto, `db push`, `migration repair`, deploy, push, merge ou PR integra W2C.

## W2D — projection, revision vector, provider, cache e UX

### Escopo e projection self

A W2D implementa exclusivamente W2-09 e W2-10 do plano aprovado. A RPC
`public.resolve_my_authorization()` não aceita argumento de alvo: deriva o
principal de `auth.uid()` e reconsulta os fatos atuais de usuário, tenant,
membership, profile, catálogo, baseline, overrides e entitlements. Quando o
contexto inteiro está disponível, devolve somente a projection self necessária
à UX:

- IDs opacos do principal, tenant, membership e profile correntes;
- `tenant_ref`, nome de apresentação do profile e versões autoritativas;
- permissions efetivas como códigos completos, exatos, únicos e ordenados;
- entitlements habilitados como lista separada, única e ordenada;
- revisão canônica `m<membership>:p<profile>:c<catalog>`.

Estados indisponíveis são explícitos e fail-closed. Fora de `ready`, a RPC não
projeta tenant, membership, profile, versões nem capabilities. Token de convite,
e-mail, Audit, detalhes de override, ator da mutação e dados de terceiros não
integram o contrato. Não há projection por usuário arbitrário.

### Revision vector, generation e cache

O vetor autoritativo é formado por `membership.version`, `profile.version` e
`authorization_catalog_state.catalog_revision`. Ele muda quando override,
profile/baseline ou catálogo muda, sem fanout artificial. Entitlements também
participam da chave semântica da projection e são sempre reconsultados.

O `AuthorizationProvider`, aninhado depois do `SessionProvider` e usando o mesmo
`QueryClient`, mantém uma `authorizationGeneration` apenas em memória. A
generation começa em `1` após a primeira projection válida e incrementa quando
principal/contexto, vetor, conjunto efetivo, entitlement ou sinal explícito
invalida o estado. Antes de publicar a nova projection, queries são canceladas
e o cache sensível é removido. Estados `loading`, `refreshing`,
`unauthenticated`, erro, mismatch ou lifecycle indisponível não expõem
capabilities anteriores.

As chaves tenant-owned agora incluem principal, tenant, membership e versão,
profile e versão, revisão do catálogo, revisão canônica e generation local.
Essa composição impede reutilização acidental entre usuário, tenant, perfil,
versão ou ciclo de invalidação. Nenhuma permission, entitlement ou projection é
persistida em `localStorage`, `sessionStorage`, cookie, URL ou JWT.

### Revalidação, multitab e integração de UX

A projection é reconsultada após resolução Auth/context, mudança de principal
ou tenant, comando administrativo por `invalidateAuthorization`, foco,
retorno de visibilidade, retorno online e a cada 30 segundos enquanto a aba
está visível, online e autenticada. Há um único timer, removido no cleanup. Cada
request captura sua geração/contexto; resposta antiga é descartada se uma troca
ocorrer durante o voo.

O canal `cw-authorization` transmite apenas protocolo, tipo de invalidação e
nonce. Ele nunca transporta permissions, entitlements ou projection. Mensagens
com campos extras ou protocolo inválido são ignoradas; a aba receptora limpa o
estado e reconsulta a RPC. Logout explícito sinaliza `signed-out`, e o evento
Auth autoritativo conclui a saída. Não foi adicionado Realtime nem novo canal
persistente.

`useAuthorization` oferece checks exatos e independentes de permission e
entitlement. `PermissionGuard` serve somente à visibilidade de UX; commands e
RLS continuam sendo autoridade. Login, raiz e deep links tenant só liberam
redirect, shell e conteúdo depois que sessão, contexto, rota e authorization
projection estão simultaneamente válidos. Carregamento e indisponibilidade usam
estados genéricos, sem enumerar internals.

### Segurança, migration e types

| Migration | Responsabilidade |
| --- | --- |
| `20260914008000_w2d_authorization_projection.sql` | Projection self, capabilities exatas, entitlements separados e revision vector canônico |

A RPC é `STABLE SECURITY DEFINER` porque as tabelas autoritativas permanecem
fechadas aos clientes. Ela fixa `search_path` vazio, qualifica objetos, possui
owner não cliente, revoga `PUBLIC`, `anon` e `service_role` e concede apenas
`EXECUTE` a `authenticated`. Nenhum grant direto de tabela, policy permissiva,
bypass, wildcard, Global Admin ou `service_role` no frontend foi introduzido.

`src/infrastructure/supabase/database.types.ts` foi regenerado pelo Supabase CLI
local, sem edição manual. O diff gerado adiciona somente a assinatura pública de
`resolve_my_authorization`; as estruturas privadas continuam ausentes dos tipos
do browser.

### Testes e evidências

`supabase/tests/w2d_authorization_projection.sql` possui 27 asserts sobre
assinatura e grants, owner e `search_path`, estados fail-closed, isolamento self,
onze permissions exatas, entitlement separado, vetor canônico e invalidação por
profile, override, catálogo, entitlement e bloqueio da membership. O harness
oficial agora executa nove arquivos pgTAP.

Os testes frontend cobrem parsing estrito, rejeição de projection parcial,
wildcards e ordenação inválida; chave semântica; query keys; provider e
generation; cancelamento/limpeza antes da troca; race A→B; invalidação de
commands; protocolo multitab sem payload; foco, intervalo, hidden e cleanup;
logout; entitlement; guard fail-closed; login, rota e deep link aguardando a
projection.

| Validação | Resultado |
| --- | --- |
| `npm run preflight:v2` inicial | `WARN`: Docker não estava visível no sandbox; branch, HEAD, worktree limpo, arquivos e toolchain passaram |
| `npm run db:start` | `PASS`: Supabase local descartável iniciado sem expor credenciais |
| `npm run db:reset` | `PASS`: quinze migrations W0/W1/W2A/W2B/W2C/W2D aplicadas do zero |
| `npm run db:types` | `PASS`: tipos regenerados pelo CLI local |
| schema lint | `PASS`: nenhum erro no schema público |
| `npm run test:v2:db` | `PASS`: 9 arquivos, W2D 27/27 e total 379/379; `DB_SMOKE_OK` |
| `npm run test:v2:unit` | `PASS`: 17 arquivos e 105/105 testes |
| `npm run test:v2:e2e` | `PASS`: 6/6 Chromium |
| `npm run typecheck` | `PASS` |
| `npm run lint` | `PASS` |
| `npm run build` | `PASS`: 252 módulos; aviso preexistente de chunk acima de 500 kB |
| `git diff --check` | `PASS` |
| `npm run verify:v2:full` pré-commit | DB, unit, E2E, typecheck, lint, build e diff-check em `PASS`; agregado `WARN` somente pelo worktree da missão ainda dirty |

No primeiro pgTAP, uma expressão esperada tentou ler o catálogo sob
`authenticated`; o valor esperado passou a ser materializado antes da troca de
role, sem conceder acesso de produto. No frontend, o primeiro teste multitab
mostrou que um `signed-out` remoto removia capabilities mas expunha `loading`
até o evento Auth; o provider passou a expor `unauthenticated` imediatamente.
Também foram corrigidos grants explícitos das fixtures temporárias e a
introspecção dos nomes de saída da RPC. Nenhuma correção relaxou RLS, grants ou
fail-closed.

### Gate W2D e itens deferidos

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = YES
W2B_PROFILES_OVERRIDES_READY = YES
W2C_AUTHORIZATION_ENGINE_READY = YES
W2D_AUTHORIZATION_PROJECTION_READY = YES
W2E_AUTHORIZATION_HARDENING_READY = NO
AUTHORIZATION_READY = NO
```

W2E permanece responsável pelo hardening consolidado, revisão final de
policies/grants e matriz adversarial integrada. Resources, facts, RLS e
resolvers de `OWN`, `ASSIGNED` e `TEAM` pertencem às waves dos módulos donos
dos dados. Não foram criados módulos de Manutenção, Ativos, Fornecedores,
Cadastros, Relatórios ou Calendário. Nenhum Supabase remoto, `db push`,
`migration repair`, deploy, push, merge ou PR integra W2D.

## W2E — hardening e security gate final

### Objetivo e método

A W2E executou revisão adversarial integrada de W2A–W2D sem iniciar W3 nem
adicionar domínio. O ciclo incluiu leitura das fontes normativas, inventário de
todas as migrations e suites W1/W2, reconstrução local, introspecção do catálogo
PostgreSQL, ataques com dois tenants e IDs válidos conhecidos, revisão estática
do frontend e SQL, correções mínimas, regressão dedicada e gates completos.

### Threat model e attack matrix

| Atacante/cenário | Ataque executado ou controle verificado | Resultado final |
| --- | --- | --- |
| Usuário authenticated malicioso | REST/table mutation, RPCs manipuladas e combinação inexistente | Negado por grants/RLS/commands; ausência é deny |
| Tenant A conhecendo UUIDs de B | tenantRef, profile, membership, entitlement e commands de B | Falha genérica, sem enumeração ou efeito em B |
| JWT ainda válido após lifecycle | app user, membership e tenant alterados no banco | Evaluator, command e projection falham imediatamente |
| Authority/profile/entitlement alterados | baseline, override, profile version e entitlement | Estado atual do banco prevalece; cache é invalidado por revisão/generation |
| Administrador parcial/self-escalation | ADD ALLOW, REMOVE DENY, profile e invitation mais privilegiados | Delegação exata e comparação antes/depois negam elevação |
| Payload/browser adulterado | actor, tenant, wildcard, scope implícito e IDs target cross-tenant | Actor deriva de `auth.uid()`; tenant deriva da membership atual |
| Aba/cache antigo | R1 atrasada após invalidação/R2, principal A→B | R1 é descartada; cache e capabilities A não reaparecem |
| BroadcastChannel malicioso | protocolo/tipo/campos extras/admin/tenant/actor/permissions e nonce repetido | Payload rejeitado; mensagem válida é só trigger de reconsulta; replay ignorado |
| Concorrência entre administradores | versões stale, mesmo profile/override e lock comum por tenant | Sem silent overwrite; command relê e reautoriza sob lock transacional |
| Acesso técnico indevido | direct tables e self resolver com `service_role` | Removido; apenas quatro RPCs W1 técnicas documentadas permanecem |
| anon/PUBLIC | tabelas, helpers e RPCs W1/W2 | Nenhuma superfície de autorização executável ou legível |
| Combinação futura/desconhecida | wildcard, prefixo, substring e scope não catalogado | Fail-closed, sem hierarquia ou expansão |

Os atacantes mínimos A–O da missão estão cobertos pela matriz acima e pelas
suites W1E, W2A, W2B, W2C, W2D e W2E executadas em conjunto.

### Findings e correções

| ID | Severidade | Finding/impacto | Causa | Correção |
| --- | --- | --- | --- | --- |
| W2E-01 | Alta | `service_role` conservava grants diretos nas seis tabelas W1, permitindo contornar commands W2C e o boundary de Audit se a credencial técnica fosse usada fora das RPCs | Defaults do ambiente Supabase e revogações W1 não incluíam `service_role` | Migration forward-only revoga todo acesso direto; as quatro RPCs técnicas W1 permanecem |
| W2E-02 | Média | Objetos futuros criados pelo owner das migrations em `public` herdariam grants amplos para roles de API | Default privileges iniciais do Supabase | Defaults de tables, sequences e functions em `public`/`private` foram fechados para o owner `postgres`; grants futuros passam a ser explícitos |
| W2E-03 | Baixa | Um `signed-out` sintaticamente válido e replay de nonce podiam alterar estado de UX sem fato Auth novo ou provocar revalidações repetidas | Tipo do canal era tratado como estado, e nonces não eram deduplicados | Todo sinal virou apenas invalidação/reconsulta; evento Auth continua autoritativo; nonces remotos têm deduplicação limitada |
| W2E-04 | Baixa | O self resolver de tenant permanecia executável por `service_role` sem necessidade | Grant default residual na function W1C | `EXECUTE` revogado de `service_role`; `authenticated` permanece o único cliente |

Não foram encontrados bypasses de produção adicionais em evaluator, commands,
projection, RLS, audit, convite ou route boundary. A tentativa de alterar defaults
da role interna `supabase_admin` foi rejeitada pelo próprio runtime e não foi
contornada. Objetos versionados V2 pertencem a `postgres`; criação manual fora
da cadeia de migrations continua proibida pelo workflow.

### AUTH-01, antiescalada e concorrência

O evaluator resolve apenas `resource_code + action_code + scope` exatos.
`ALLOW` forma união; `DENY OWN`, `DENY ASSIGNED` e `DENY TEAM` substituem apenas
a combinação correspondente e não removem `ALL_TENANT`. Não existe wildcard,
prefix matching, substring, profile-name authority ou scope hierarchy. O seed
continua contendo somente onze combinações `core.users/core.profiles` em
`ALL_TENANT`.

As transitions elevativas são avaliadas semanticamente: ADD ALLOW, REMOVE DENY,
profile change, unblock e invitation exigem delegabilidade e authority exata.
Transitions redutivas preservam o guard de último administrador. Todos os onze
commands authenticated entram por `lock_authorization_actor`, serializam pelo
tenant, relêem app user, membership, tenant, profile e permission/entitlement,
validam versões esperadas e escrevem Audit na mesma transação. Não foi encontrado
lock order divergente nem TOCTOU aberto.

### RLS, grants e functions

As dez tabelas públicas W1/W2 têm RLS. Somente `app_users`, `tenants`,
`tenant_memberships` e `tenant_entitlements` possuem policy SELECT estreita;
as seis tabelas sensíveis restantes permanecem sem policies. As quatro tabelas
privadas não são acessíveis por roles cliente. `PUBLIC` e `anon` não possuem
table grants; `authenticated` possui apenas os quatro SELECTs necessários e
nenhuma mutation; `service_role` não possui acesso direto a tabela W1/W2.

O inventário final contém 46 functions W1/W2: 30 `SECURITY DEFINER` e 16
`SECURITY INVOKER`. Todas pertencem a `postgres`, fixam `search_path` vazio,
usam nomes qualificados, não usam SQL dinâmico e não têm `PUBLIC EXECUTE`.
Helpers privados não são client-callable, salvo os dois helpers RLS W1
explicitamente necessários para `authenticated`. As RPCs W2C authenticated não
aceitam `actor_user_id` ou `operator_user_id`; actor é sempre `auth.uid()`.

### Cross-tenant, lifecycle, entitlement e acesso direto

Com Tenant A e B reais no PostgreSQL local, o usuário A viu somente seu próprio
app user, tenant, membership e entitlement. `tenantRef` B retornou o mesmo estado
indisponível seguro; profile B conhecido e profile inexistente produziram
`AUTHORIZATION_OPERATION_UNAVAILABLE`. INSERT/UPDATE/DELETE diretos de catálogo,
profiles, baselines, overrides, memberships, invitations, entitlements e Audit
foram negados conforme os grants e suites integradas. `ALL_TENANT` permaneceu
limitado ao tenant autoritativo.

Sem renovar o JWT, bloqueio do app user/membership e suspensão do tenant
invalidaram projection e commands. Entitlement desabilitado suprimiu baseline e
override ALLOW do recurso condicionado, mas não criou bloqueio artificial para
permissions `core` sem entitlement. Permission deprecated não aceitou novo
baseline, deixou de resolver e preservou a linha histórica existente.

### Projection, cache, multitab e routing

`resolve_my_authorization()` continua sem argumentos, self-only, com lifecycle
fail-closed, permission codes exatos, entitlements separados e dados mínimos.
Nenhuma mutation usa a projection como authority. Query keys distinguem
principal, tenant, membership, profile, vetor de revisão e generation. Testes
provam A→B, logout, revision switch e que resposta R1 atrasada não repopula o
estado depois de R2.

O canal multitab não transporta authority e agora nem seu tipo altera estado
diretamente: qualquer mensagem válida provoca apenas limpeza e reconsulta.
Payloads malformados ou com campos extras são rejeitados, nonce repetido é
ignorado, ausência de `BroadcastChannel` degrada sem crash, e listeners/timers
são limpos em StrictMode/mount/unmount. Focus, visibility, online/offline e
polling mantêm um único intervalo e retry limitado.

Não há projection ou query cache persistido em `localStorage`, `sessionStorage`,
IndexedDB, cookie ou persister. As ocorrências de `localStorage` fora de `src`
pertencem ao legado V1 e não são authority W2. Deep links, tenantRef inválido/de
outro tenant, refresh, back após logout, rota desconhecida e `/plataforma/*`
continuam fail-closed. Global Admin não foi implementado.

### Convites, Audit e non-enumeration

Convite mantém token raw retornado uma vez, somente hash SHA-256 persistido,
expiration/revoke/accepted lifecycle e profile ativo do mesmo tenant. Token
inválido, expirado, revogado ou usado retorna resposta pública uniforme. Token,
JWT, senha e secret não aparecem no Audit. Audit permanece append-only; actor,
tenant, target, reason, correlation e versões são escritos na mesma transação da
mutation, e falha não deixa evento falso de sucesso.

### Migration, tipos e testes

| Artefato | Finalidade |
| --- | --- |
| `20260914009000_w2e_authorization_hardening.sql` | Revogar superfícies diretas de `service_role`, fechar self resolver e default privileges do owner das migrations |
| `w2e_authorization_hardening.sql` | 56 ataques/asserts integrados de RLS, grants, functions, cross-tenant, stale JWT, entitlement, AUTH-01, depreciação e Audit |
| `authorization-signal.ts` e testes | Canal somente-invalidação, rejeição de payload e replay, fallback seguro |
| `authorization-context.tsx` e testes | Sinal multitab nunca vira estado autoritativo; proteção contra resposta stale |
| `supabase-local.mjs` | Migration e pgTAP W2E integrados ao reset/smoke oficial |

Não houve alteração estrutural de schema público ou assinatura RPC; por isso
`database.types.ts` permaneceu byte a byte igual e não recebeu edição manual.

Evidência intermediária após as correções:

| Validação | Resultado |
| --- | --- |
| Reset completo | `PASS`: dezesseis migrations W0–W2E |
| Schema lint | `PASS` |
| pgTAP W2E | `PASS`: 56/56 |
| pgTAP total | `PASS`: 10 arquivos, 435/435; `DB_SMOKE_OK` |
| Unit focado | `PASS`: 15/15 |
| Unit total | `PASS`: 17 arquivos, 108/108 |

Os resultados finais de E2E, typecheck, lint, build, diff-check, secret scan,
`verify:v2:full` pré e pós-commit são registrados no relatório da missão e
somente permitem o gate abaixo quando todos estiverem verdes.

### Riscos residuais, deferred e gate final

O único risco técnico conhecido não bloqueante permanece o warning preexistente
do bundle acima de 500 kB. Os defaults internos de `supabase_admin` são
gerenciados pela plataforma; como objetos V2 só podem nascer de migrations
versionadas do owner `postgres`, não há vulnerabilidade W2 aberta. Permanecem
deferidos para as waves donas dos domínios os facts/resolvers e RLS reais de
`OWN`, `ASSIGNED` e `TEAM`. Nenhum fact, tabela ou permission fake foi criado.

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = YES
W2B_PROFILES_OVERRIDES_READY = YES
W2C_AUTHORIZATION_ENGINE_READY = YES
W2D_AUTHORIZATION_PROJECTION_READY = YES
W2E_AUTHORIZATION_HARDENING_READY = YES
AUTHORIZATION_READY = YES
```

W3 não foi iniciada. Não houve acesso remoto, `db push`, `migration repair`,
deploy, push, merge ou PR na W2E.
