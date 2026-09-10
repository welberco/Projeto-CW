# Implementação da W1 — Identity / Tenant / Membership

## Estado

Este documento registra a execução incremental da W1. O plano aprovado permanece
em `docs/IMPLEMENTACAO-V2-W1-PLANO.md`.

```text
W0_COMPLETE = YES
FOUNDATION_READY = YES
W1_PLANNING_COMPLETE = YES
W1A_IMPLEMENTATION_AUTHORED = YES
W1A_DATA_MODEL_READY = NO
AUTH_READY = NO
TENANT_READY = NO
IDENTITY_TENANT_READY = NO
```

`W1A_DATA_MODEL_READY` permanece `NO` até que reset, geração de tipos e testes
DB/RLS sejam executados no Supabase local real.

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

### Validação nesta execução

| Validação | Resultado |
| --- | --- |
| aplicação auxiliar das migrations em PGlite | `PASS`: 6 tabelas, trigger Auth → Application User, UUID v4 inválido rejeitado (`23514`) e Audit UPDATE rejeitado (`55000`); não substitui Supabase/RLS real |
| `node --check scripts/supabase-local.mjs` | `PASS` |
| lint isolado do harness | `PASS` |
| Docker | `BLOCKED`: executável indisponível nesta sessão Codex |
| `npm run db:reset` | `BLOCKED` após execução: Docker indisponível |
| `npm run db:types` | `BLOCKED` após execução: Docker indisponível; arquivo gerado não foi editado manualmente |
| `npm run test:v2:db` | `BLOCKED` após execução: Docker indisponível |
| `npm run test:v2:unit` | `PASS`: 5 arquivos, 15 testes |
| `npm run typecheck` | `PASS` |
| `npm run lint` | `PASS` |
| `npm run build` | `PASS`: 188 módulos transformados |
| `npm run test:v2:all` | não executado; depende do banco local e inclui E2E fora do fechamento W1A |

Comandos manuais exatos para PowerShell com Docker acessível:

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

### Pendência para fechar o gate

Em uma sessão com Docker, executar a sequência manual, revisar o
`database.types.ts` gerado exclusivamente pelo CLI e confirmar os testes pgTAP
reais. Até essa evidência existir, W1A não está pronta para promover os gates de
implementação e W1B não deve começar.
