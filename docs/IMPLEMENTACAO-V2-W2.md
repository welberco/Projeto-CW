# Implementação da W2 — Authorization

## Estado

Este documento registra a execução incremental da W2. O contrato aprovado
permanece em `docs/IMPLEMENTACAO-V2-W2-PLANO.md`.

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = YES
W2B_PROFILES_OVERRIDES_READY = NO
W2C_AUTHORIZATION_ENGINE_READY = NO
W2D_AUTHORIZATION_PROJECTION_READY = NO
W2E_AUTHORIZATION_HARDENING_READY = NO
AUTHORIZATION_READY = NO
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
- ausência das entidades W2B;
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

- **W2B:** `tenant_profiles`, baseline tenant, overrides, `profile_id` na
  membership, target profile do convite, provisioning/backfill e integridade
  tenant-aware correspondente.
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
