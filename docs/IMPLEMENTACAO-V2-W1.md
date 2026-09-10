# Implementação da W1 — Identity / Tenant / Membership

## Estado

Este documento registra a execução incremental da W1. O plano aprovado permanece
em `docs/IMPLEMENTACAO-V2-W1-PLANO.md`.

```text
W0_COMPLETE = YES
FOUNDATION_READY = YES
W1_PLANNING_COMPLETE = YES
W1A_IMPLEMENTATION_AUTHORED = YES
W1A_DATA_MODEL_READY = YES
W1B_AUTH_BOOTSTRAP_INVITATIONS_READY = NO
AUTH_READY = NO
TENANT_READY = NO
IDENTITY_TENANT_READY = NO
```

`W1A_DATA_MODEL_READY` está aprovado pelas migrations reproduzíveis, execução
real no Supabase local, tipos regenerados e testes DB/RLS aprovados. Os gates
de Auth, Tenant e Identity/Tenant continuam pendentes das etapas W1B–W1E.

## W1A — modelo físico, migrations e RLS base

### Escopo implementado

- `public.app_users` ligado 1:1 a `auth.users`;
- `public.tenants` com `tenant_ref` UUID v4 público separado;
- `public.tenant_memberships` com lifecycle histórico;
- `public.tenant_invitations` sem token reutilizável em plaintext;
- `public.tenant_entitlements` mínimo;
- `public.audit_events` append-only mínimo;
- helpers privados e não recursivos de principal/tenant;
- RLS base deny-by-default e grants mínimos;
- testes pgTAP de constraints, lifecycle, grants e isolamento Tenant A/B;
- harness local atualizado para validar migrations, schema e testes W1A.

Não foram implementados Auth UI, sessão frontend, bootstrap runner, integração de
convite com Auth, aceite, provider de contexto, cache lifecycle, E2E Auth, RBAC,
Global Admin, History, Outbox, workers ou idempotência.

### Migrations concretas

| Migration | Responsabilidade |
| --- | --- |
| `20260910000000_w1a_identity_tenant_core.sql` | schema privado; Application User; Tenant; lifecycles; trigger Auth 1:1; atualização/versionamento; RLS fechada |
| `20260910001000_w1a_membership_invitation_entitlement_audit.sql` | memberships, invitations, entitlements, Audit mínimo, constraints, índices, append-only e RLS fechada |
| `20260910002000_w1a_rls_helpers_and_policies.sql` | helpers `is_active_principal`/`can_access_tenant`, policies SELECT mínimas e grants exatos |

Cada tabela nasce com RLS habilitada e sem grants de cliente. A última migration
abre somente as leituras estritamente necessárias para `authenticated`.

### Modelo e lifecycles

| Entidade | Lifecycle/regras principais |
| --- | --- |
| `app_users` | `active`, `blocked`, `inactive`; status coerente com timestamps; mesmo UUID de `auth.users` |
| `tenants` | `active`, `suspended`, `inactive`; `tenant_ref` unique e não autoritativo; hard delete operacional ausente |
| `tenant_memberships` | `active`, `blocked`, `revoked`; `revoked` terminal; no máximo uma membership `active`/`blocked` por usuário |
| `tenant_invitations` | `pending`, `accepted`, `revoked`, `expired`; aceite exige usuário; pendência equivalente única |
| `tenant_entitlements` | PK `(tenant_id,module_key)`; chave normalizada; sem billing/planos/limites |
| `audit_events` | somente INSERT por operações controladas futuras; UPDATE, DELETE e TRUNCATE bloqueados estruturalmente |

Reentrada após revogação cria uma nova linha de membership. A linha revogada é
preservada; índices únicos parciais consideram apenas `active` e `blocked`.

### Helpers e RLS

Os únicos helpers RLS são:

- `private.is_active_principal()`;
- `private.can_access_tenant(target_tenant_id uuid)`.

Ambos derivam o ator de `auth.uid()`, usam `SECURITY DEFINER`, `search_path`
vazio, referências schema-qualified, grants explícitos e nenhum `PUBLIC EXECUTE`.
O argumento de tenant é apenas target confrontado com a membership persistida.

| Tabela | SELECT `authenticated` | INSERT/UPDATE/DELETE de cliente |
| --- | --- | --- |
| `app_users` | apenas a própria linha | negados |
| `tenants` | tenant ativo alcançado por principal e membership ativos | negados |
| `tenant_memberships` | somente linhas do próprio `auth.uid()` | negados |
| `tenant_invitations` | negado na W1A | negados |
| `tenant_entitlements` | somente tenant operacional autorizado | negados |
| `audit_events` | negado na W1A | negados; UPDATE/DELETE/TRUNCATE também protegidos por trigger |

### Testes adicionados

`supabase/tests/w1a_constraints.sql` cobre:

- tabelas e RLS habilitada;
- trigger Auth → Application User;
- `tenant_ref` único;
- status/lifecycles inválidos;
- FKs;
- membership operacional única para `active` e `blocked`;
- revogação, reentrada cross-tenant e reentrada no mesmo tenant sem apagar
  histórico;
- convite pendente equivalente único e hash normalizado;
- chave/duplicidade de entitlement;
- Audit sem UPDATE/DELETE.

`supabase/tests/w1a_rls.sql` cobre:

- policies e grants mínimos;
- ausência de `PUBLIC EXECUTE`/acesso `anon` aos helpers;
- User A/Tenant A e User B/Tenant B;
- isolamento de Application User, Tenant, Membership e Entitlement;
- `tenant_ref`, `tenant_id` e `user_id` forjados;
- escrita direta negada;
- Invitation/Audit fechados;
- bloqueio, revogação, suspensão e inativação refletidos no acesso.

### Validação real no Supabase local

| Validação | Resultado |
| --- | --- |
| aplicação auxiliar das migrations em PGlite | `PASS`: 6 tabelas, trigger Auth → Application User, UUID v4 inválido rejeitado (`23514`) e Audit UPDATE rejeitado (`55000`); não substitui Supabase/RLS real |
| `node --check scripts/supabase-local.mjs` | `PASS` |
| lint isolado do harness | `PASS` |
| `npm run db:reset` | `PASS`: migrations W0/W1A aplicadas do zero |
| `npm run db:types` | `PASS`: `database.types.ts` regenerado pelo Supabase CLI contra o banco local, sem edição manual |
| `npm run test:v2:db` | `PASS`: smoke do schema e pgTAP aprovados |
| pgTAP | `PASS`: 2 arquivos, 60/60 testes (`w1a_constraints.sql` e `w1a_rls.sql`) |
| `npm run test:v2:unit` | `PASS`: 5 arquivos, 15 testes |
| `npm run typecheck` | `PASS` |
| `npm run lint` | `PASS` |
| `npm run build` | `PASS`: 188 módulos transformados |
| E2E Chromium | `PASS`: 4/4 testes |
| `npm run test:v2:all` | `PASS` |

O smoke inicialmente reportou, de forma incorreta, a ausência de
`public.app_users`: o dump atual do Supabase CLI emite `CREATE TABLE IF NOT
EXISTS`, enquanto o harness reconhecia somente `CREATE TABLE`. A correção em
`scripts/supabase-local.mjs` tornou somente `IF NOT EXISTS` opcional na regex;
nenhum schema, migration, RLS ou teste de banco foi alterado.

Os comandos executados no PowerShell com Docker/Supabase local acessíveis foram:

```powershell
npm run db:reset
npm run db:types
npm run test:v2:db
npm run test:v2:unit
npm run typecheck
npm run lint
npm run build
npm run test:v2:all
git diff --check
```

### Security review W1A

- nenhuma credencial, JWT, project ref remoto ou connection string adicionada;
- nenhuma chamada remota, `--linked`, `db push`, deploy ou service role no
  browser;
- nenhuma policy usa `tenant_ref`, tenant/user de payload ou claim mutável como
  autoridade;
- helpers RLS não são recursivos e têm grants mínimos;
- nenhuma escrita de cliente em lifecycle, membership, invitation, entitlement
  ou Audit;
- nenhum hard delete operacional foi exposto;
- e-mail não foi duplicado em `app_users`; invitation persiste somente hash;
- nenhum elemento de W1B/W2/W3 foi antecipado além do Audit mínimo aprovado.

### Fechamento do gate W1A

As migrations são reproduzíveis; o schema real e os tipos regenerados confirmam
as seis tabelas W1A; e os testes cobrem constraints, lifecycle histórico,
isolamento Tenant A/B, negação a `tenant_ref`/IDs forjados, memberships
blocked/revoked, tenant suspended/inactive, Audit append-only, helpers, grants
mínimos e RLS deny-by-default. A revisão de segurança não identificou secrets,
URLs remotas, credenciais, service role no frontend ou antecipação de W1B.

`W1A_DATA_MODEL_READY = YES`. O fechamento isolado da W1A não promove
`AUTH_READY`, `TENANT_READY` ou `IDENTITY_TENANT_READY`, que permanecem `NO`.

## W1B — Auth, bootstrap e convites controlados

### Objetivo e decisões

A W1B adiciona autenticação por Supabase Auth, bootstrap inicial one-shot,
commands controlados para invitations e aceite pelo destinatário autenticado.
Não cria signup público, role temporária, Global Admin, CompanySwitcher,
permissões W2 nem contexto tenant completo da W1C.

Supabase Auth permanece autoridade para credencial, sessão, e-mail confirmado e
`auth.uid()`. `app_users` permanece a identidade/lifecycle da aplicação. A
projeção frontend falha fechada para profile ausente, principal blocked/inactive,
membership ausente/blocked/revoked, tenant indisponível e entitlement desabilitado.

### Bootstrap

`private.platform_bootstrap_state` é o marcador autoritativo mínimo. O command
`public.bootstrap_initial_tenant`:

- é `SECURITY DEFINER`, transacional e serializado por advisory transaction lock;
- exige Auth/Application User ativo e plataforma ainda vazia;
- cria tenant inicialmente não operacional, membership, entitlement
  `maintenance = enabled`, Audit e marcador de conclusão;
- torna o tenant `active` somente depois do conjunto consistente;
- retorna `SYSTEM_ALREADY_INITIALIZED` em repetição;
- possui `EXECUTE` somente para `service_role`, nunca para browser/cliente.

O runner `scripts/w1b-local-bootstrap.mjs` aceita somente URL loopback, recebe
e-mail, senha, nome do tenant e credencial técnica por ambiente do processo,
não imprime segredo e não persiste senha. Se a criação Auth funcionar e o
command DB falhar, a identidade permanece sem contexto para retry/reparo
controlado, conforme o plano W1.

### Invitations e modelo de token

E-mail é normalizado somente por `trim + lowercase` e persistido como SHA-256.
O command de criação gera token aleatório de 256 bits, persiste somente seu
SHA-256 e retorna o token bruto uma única vez ao serviço chamador. Audit nunca
recebe token, senha, JWT ou e-mail completo.

Criação, revogação e expiração são commands `service_role` sem grants para
`anon`/`authenticated`; a autorização interativa de quem pode convidar fica para
W2. O aceite é o único command concedido a `authenticated`: recebe somente token
e correlação, deriva usuário/e-mail confirmado de `auth.uid()`/`auth.users`,
adquire locks, relê invitation/tenant/membership, impede reuso, identidade
incorreta, expiração, revogação, tenant suspended/inactive e membership
active/blocked conflitante, e grava membership + invitation accepted + Audit na
mesma transação. Membership revoked permanece histórica e permite reentrada.

O link usa `/convite#token=...`, mantendo o token fora da requisição HTTP e de
referrers. A aplicação não copia sessão, token, tenant ou autorização para
storage próprio; usa a persistência oficial da SDK.

### Commands, grants e RLS

| Command | Grant |
| --- | --- |
| `bootstrap_initial_tenant` | `service_role` |
| `create_tenant_invitation` | `service_role` |
| `revoke_tenant_invitation` | `service_role` |
| `expire_tenant_invitation` | `service_role` |
| `accept_tenant_invitation` | `authenticated` |

Todos revogam `PUBLIC EXECUTE`, usam `search_path` vazio, nomes qualificados e
contratos estreitos. Nenhuma policy RLS W1A foi ampliada e nenhuma escrita
direta de cliente foi concedida.

### Frontend, rotas e testes

- `AuthGateway` delimita sessão, login, logout, projeção e aceite;
- `/login` oferece login seguro sem cadastro público;
- `/convite` exige sessão e token válido no fragmento;
- estados de loading, erro seguro, blocked/inactive/no-access e sessão válida
  são explícitos;
- testes unitários cobrem normalização, projeção fail-closed, erros seguros,
  ausência de signup e token no fragmento;
- pgTAP W1B cobre bootstrap, grants, tokens/hashes, identity binding, reuso,
  revoke/expire, conflicts de membership, tenant lifecycle e Audit;
- E2E local cobre renderização de login/sem sessão e invitation inválida segura.

### Validação e limitações nesta sessão

| Validação | Resultado |
| --- | --- |
| migrations em PostgreSQL embarcado auxiliar | `PASS` sintático/estrutural; não substitui Supabase/RLS real |
| `npm run test:v2:unit` | `PASS`: 8 arquivos, 35 testes |
| `npm run typecheck` | `PASS` |
| `npm run lint` | `PASS` |
| `node --check scripts/w1b-local-bootstrap.mjs` | `PASS` |
| `npm run build` | `PASS`: 239 módulos transformados; aviso não bloqueante de chunk acima de 500 kB |
| E2E Chromium | `PASS`: 6/6 testes locais controlados |
| Docker/Supabase local | `BLOCKED`: executável Docker indisponível nesta sessão Codex |
| `npm run db:reset` | `BLOCKED` por Docker indisponível |
| `npm run db:types` | `BLOCKED` por Docker indisponível; arquivo gerado não foi editado |
| `npm run test:v2:db` / pgTAP real | `BLOCKED` por Docker indisponível |
| `npm run test:v2:all` | `BLOCKED`: inclui o gate DB indisponível; unit e E2E foram executados separadamente |

A busca adversarial confirmou que as ocorrências de `service_role` estão
restritas à rejeição de configuração pública, ao runner local e aos grants ops;
não há chave concreta, senha hardcoded, `is_admin`, bypass, token bruto
persistido/logado ou tenant/user de payload no command de aceite.

Até a validação manual real, o adapter RPC usa um cast estreito e documentado;
`database.types.ts` deve ser regenerado pelo CLI e o cast removido depois que a
migration W1B estiver aplicada. W1C (resolver/context/cache), W1D, W1E e W2 não
foram iniciadas.

```text
W1A_DATA_MODEL_READY = YES
W1B_AUTH_BOOTSTRAP_INVITATIONS_READY = NO
AUTH_READY = NO
TENANT_READY = NO
IDENTITY_TENANT_READY = NO
```

O gate W1B permanece `NO` até `db:reset`, `db:types`, pgTAP/DB e a suíte completa
passarem no Supabase local real, seguidos de revisão dos tipos gerados.
