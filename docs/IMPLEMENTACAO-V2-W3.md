# Implementação da W3 — History, Audit operacional, Outbox e eventos

## W3A — Audit e Functional History foundation

### Estado e escopo

A W3A implementa somente a primeira subwave do plano aprovado em
`docs/IMPLEMENTACAO-V2-W3-PLANO.md`: evolução forward-only da trilha oficial de
Audit e o envelope compartilhado de History funcional. Ela não cria Outbox,
Event processing, idempotência, worker, retry, dead-letter, Notifications ou
qualquer entidade de domínio.

Entrada oficial: branch `feat/v2-w3-history-outbox`, commit
`c213a9ae51268e3a3412f539e78c61883a73b847`, W0–W2 prontas e
`W3_PLAN_COMPLETE = YES`.

### Separação Audit × History

`public.audit_events` continua sendo a única trilha de segurança/compliance. Ela
responde quem ou qual autoridade realizou uma operação, em qual contexto e sobre
qual target. A W3A não cria log concorrente e não transforma Audit em History,
Outbox ou event store.

`public.history_entries` é um envelope separado para fatos funcionais que
alimentarão timelines de domínio. Ele descreve como um aggregate evoluiu, não é
uma tabela de estado, não replica a row inteira e não amplia a autorização sobre
o aggregate. Domínios futuros definirão vocabulário, payload tipado e projection
de leitura próprios.

### Evolução de `audit_events`

A migration forward-only acrescenta:

- `event_version` positivo, com default 1;
- `command_id` e `causation_id` opcionais;
- `source` controlado;
- `actor_ref` para provenance não humana;
- `reason` validada e pesquisável;
- `authority_kind` gerada como `tenant`, `technical` ou `platform`;
- limites e defesa contra chaves evidentes de segredo em `metadata`;
- índices por correlation e command.

Linhas históricas não são reescritas e valores sem base documental não são
fabricados. Por isso `source` permanece nullable para eventos anteriores à W3A.
Novos inserts recebem source seguro no banco. Writers técnicos W1/W2 que ainda
não possuíam `actor_ref` recebem a provenance explícita
`technical:legacy-writer` (ou variante system/platform) apenas em novos eventos;
os registros já persistidos continuam intocados.

O trigger append-only existente continua rejeitando `UPDATE`, `DELETE` e
`TRUNCATE`. Inserts no formato W1/W2 continuam válidos. O helper W2C
`private.write_authorization_audit` mantém assinatura e metadata legadas, mas
passa a delegar a escrita ao boundary W3A e também persiste `reason` e
`command_id`.

### Modelo físico de History

`public.history_entries` contém:

| Grupo | Campos | Contrato |
| --- | --- | --- |
| Identidade | `id`, `tenant_id` | UUID interno e tenant obrigatório com FK restritiva |
| Aggregate | `aggregate_type`, `aggregate_id`, `aggregate_version`, `human_code` | ID interno é autoritativo; código humano é somente metadata de UX |
| Fato | `history_type`, `history_version`, `occurred_at`, `payload` | Evento semântico versionado e tempo atribuído pelo banco |
| Actor | `actor_kind`, `actor_user_id`, `actor_ref`, `source` | Humano, técnico, sistema e plataforma são representados sem fingir usuário |
| Rastreio | `command_name`, `command_id`, `correlation_id`, `causation_id` | Execução, processo maior e causa imediata são conceitos distintos |

`tenant_id` é obrigatório; History global/platform permanece deferred. A FK de
tenant impede referência a tenant inexistente. Como W3A deliberadamente não cria
aggregates de domínio, não existe FK genérica artificial para `aggregate_id`.
Cada command futuro deve validar e estabilizar o aggregate tenant-owned antes de
chamar o helper.

`history_type` segue
`<bounded_context>.<aggregate>.<past_tense_event>`, com três segmentos lowercase
snake_case. `command_name` é namespaced. `history_version` e
`aggregate_version`, quando presente, são positivas. Não existe catálogo
prematuro de eventos de Manutenção.

### Actor, source, correlation e causation

Actors `application_user` exigem `actor_user_id` e proíbem `actor_ref`. Actors
`technical`, `system` e `platform` exigem `actor_ref` e proíbem identidade humana
no novo helper. Para History humana, o helper também comprova vínculo histórico
entre actor e tenant; a reautorização de lifecycle e capability continua sendo
responsabilidade obrigatória do command conforme `AUTH-02`.

Sources aceitas são `user_command`, `system`, `worker`, `scheduler`,
`integration`, `platform` e `migration`. Source, correlation e causation são
provenance/observabilidade: nenhum deles concede permission, redefine tenant ou
substitui o actor autoritativo.

`command_id` identifica a execução lógica; `correlation_id` agrupa o processo;
`causation_id` opcional registra a causa imediata sem FK para a Outbox ainda
inexistente. O timestamp oficial usa `statement_timestamp()` no PostgreSQL e não
é parâmetro do helper.

### Payload e segurança de dados

O payload de History é um objeto JSONB semântico e pequeno. Dumps automáticos de
`OLD`/`NEW`, HTML pré-renderizado e JSON de rows completas não fazem parte da
infraestrutura. O limite é 64 KiB sobre a representação serializada; valores
acima falham sem truncamento.

Como defesa em profundidade, Audit metadata e History payload rejeitam,
recursivamente e sem pretensão de detector universal, chaves evidentes para
senha, JWT, access/refresh token, token bruto de convite, service role,
credenciais e signed URL. A regra principal permanece DATA-01: commands devem
usar allowlists semânticas, IDs quando suficientes e não persistir PII ou secrets
desnecessários.

### Boundaries, atomicidade e imutabilidade

`private.append_audit(...)` e `private.append_history(...)` são helpers mínimos
`SECURITY INVOKER`, sem SQL dinâmico, com `search_path` vazio, owner `postgres` e
sem `EXECUTE` para `PUBLIC`, `anon`, `authenticated` ou `service_role`. Eles não
fazem commit autônomo nem efeito externo: participam da transação do caller.

Assim, falha de Audit/History obrigatório aborta a mesma statement/transaction
do command. A suite W3A demonstra rollback com uma mutation transacional mínima,
sem criar domain command fake. A tabela History possui triggers que rejeitam
`UPDATE`, `DELETE` e `TRUNCATE`, inclusive por paths privilegiados; correção
futura deverá ser uma nova entrada semântica.

### RLS, grants, owners e índices

History tem RLS habilitada e nenhuma policy. Não há leitura genérica porque os
resolvers de permission/scope pertencem aos domínios futuros. `PUBLIC`, `anon`,
`authenticated` e `service_role` não recebem qualquer privilégio de tabela.
Audit mantém a postura fechada validada na W2E. O hardening de default privileges
não é reaberto.

Os índices mínimos são:

- timeline por `(tenant_id, aggregate_type, aggregate_id, occurred_at desc,
  id desc)`;
- rastreio por `(command_id, occurred_at desc)`;
- Audit por `(correlation_id, occurred_at desc)`;
- Audit parcial por `(command_id, occurred_at desc)`.

Não há GIN indiscriminado, particionamento, materialized view ou event store.

### Testes e regressões

`supabase/tests/w3a_audit_history.sql` cobre estrutura, FK/constraints, RLS,
policies, grants, owners, search path, helpers, actors humano/técnico, taxonomia
de source, nomenclatura/versionamento, timestamp de banco, payload abaixo/acima
do limite, chaves proibidas, append-only, compatibilidade do writer W2C,
cross-tenant/actor/source spoofing, acesso direto e rollback quando Audit ou
History obrigatório falha.

O harness local inclui a migration, `history_entries` e o pgTAP W3A no reset,
schema lint e smoke oficiais. Os tipos públicos são regenerados exclusivamente
pelo Supabase CLI após reset. As suites W1/W2 permanecem parte do mesmo gate e
validam bootstrap, invitations, identity/tenant, catálogo, profiles, overrides,
evaluator, commands, projection e hardening.

Os números finais de asserts, regressões e gates são preenchidos pelo relatório
da missão somente após execução efetiva; este documento não presume `PASS`.

### Deferred e gate

- W3B: envelope Event e Transactional Outbox, enqueue e imutabilidade factual;
- W3C: command idempotency, handler receipts e worker contract/registry;
- W3D: claiming, lease/fencing, retry, processing e dead-letter;
- W3E: hardening integrado e gate final da infraestrutura W3.

Também permanecem fora desta wave Notifications completas, canais externos,
worker produtivo, scheduler, Global Admin e todos os módulos de domínio.

O gate promovido somente após todas as validações obrigatórias é:

```ini
W3_PLAN_COMPLETE = YES
W3A_AUDIT_HISTORY_READY = YES
W3B_EVENT_OUTBOX_READY = NO
W3C_IDEMPOTENCY_READY = NO
W3D_PROCESSING_READY = NO
W3E_HARDENING_READY = NO
W3_INFRASTRUCTURE_READY = NO
```

## W3B — Event Model e Transactional Outbox

### Estado e escopo

A W3B implementa somente o evento interno persistido e a garantia de
Transactional Outbox. O registro de `private.outbox_events` é simultaneamente o
fato Event e a unidade durável que será processada futuramente; não existe Event
Store paralelo e as tabelas de domínio continuam sendo a source of truth.

Permanecem fora desta subwave idempotência de command/handler, registry
operacional, claim, lease, fencing, retry, dead-letter runtime, requeue, worker,
scheduler, filas externas, webhooks e Notifications.

### Envelope físico

`private.outbox_events` contém:

- identidade e contrato: `event_id`, `event_type`, `event_version` e
  `occurred_at` atribuído pelo banco;
- escopo tenant-only: `scope_kind = tenant` e `tenant_id` obrigatório com FK
  restritiva; eventos de plataforma permanecem deferred;
- aggregate opcional e coerente: type/id juntos e version positiva quando
  informada;
- provenance: actor humano/técnico/sistema, source controlada, command,
  correlation e causation;
- `payload` factual e `metadata` técnica, ambos objetos JSON e limitados a 64
  KiB combinados;
- estado técnico mínimo e inerte: `status`, `attempt_count` e
  `next_attempt_at`. Nenhuma transition boundary ou execução existe na W3B.

O tipo segue `<bounded_context>.<aggregate>.<past_tense_event>` em lowercase
snake_case e `event_version` é positiva. O helper não aceita timestamp, scope,
status ou handler como parâmetros: esses fatos são fixados no banco ou ficam
fora desta wave.

### Segurança e minimização

A tabela está no schema `private`, com RLS habilitada, nenhuma policy e nenhum
grant para `PUBLIC`, `anon`, `authenticated` ou `service_role`. Os helpers W3B
são `SECURITY INVOKER`, owner `postgres`, `search_path` vazio, SQL estático e
sem EXECUTE para roles cliente ou service role.

`private.enqueue_event(...)` é somente um boundary interno para commands
confiáveis. O tenant fica fora do payload e actors humanos precisam possuir
vínculo autoritativo com o tenant. Actors técnicos/sistema exigem `actor_ref` e
não podem fingir `Application User`. Platform actor permanece deferred.

Payload e metadata rejeitam recursivamente chaves evidentes de secrets e chaves
que tentem redefinir envelope, tenant, actor, authority, source, handler,
capability ou destino privilegiado. Dumps explícitos de row também são
rejeitados. A defesa estrutural não substitui a allowlist semântica obrigatória
de cada evento/version definida pelo command/contrato consumidor futuro.

### Imutabilidade e estado técnico

O trigger `private.protect_outbox_event` compara a representação integral da
row e permite alteração somente dos três campos técnicos mínimos. Event ID,
type/version, timestamp, tenant, aggregate, actor, source, command, correlation,
causation, payload e metadata são imutáveis. DELETE e TRUNCATE são rejeitados.

Os índices criados são o índice parcial de ordenação de pendentes por
`(next_attempt_at, occurred_at, event_id)` e o índice mínimo de operabilidade por
`(status, event_type, occurred_at)`. Sua existência não implementa claim nem
qualquer comportamento W3D.

### Integração transacional mínima

`public.create_tenant_profile` é o command administrativo real escolhido para a
prova W3B, sem mudar assinatura, grants ou regras de autorização. Sua matriz de
effects é:

| Efeito | Contrato |
| --- | --- |
| Domain mutation | criação tenant-bound do Perfil |
| Audit | obrigatório: `authorization.profile_created` |
| History | N/A: não há timeline funcional de domínio nesta operação |
| Event/Outbox | obrigatório: `authorization.profile.created` |
| Idempotency | N/A nesta subwave; W3C |

O command gera um `command_id` no boundary confiável e o compartilha entre
Audit e Event. Mutation, Audit e enqueue executam na mesma função/transação
PostgreSQL; não existe dual-write application-side nem publicação pós-commit.
Falha de qualquer escrita obrigatória propaga erro e reverte todas as anteriores.

### Testes e regressões

`supabase/tests/w3b_event_outbox.sql` verifica schema, constraints, FK, índices,
RLS, policies, grants, owner/search path, absence de SECURITY DEFINER novo,
tenant/actor/source, naming/version, correlation/causation, JSON, limite combinado,
chaves proibidas, imutabilidade factual, acesso negado e ausência das estruturas
W3C/W3D.

A integração real comprova Domain + Audit + Outbox no mesmo command, History
explicitamente N/A, rollback da Domain/Audit quando o Event obrigatório falha e
ausência de Audit/Event quando a mutation falha. As suítes W1/W2/W3A continuam
no mesmo smoke para regressão integral.

Validação efetiva em Supabase local: reset completo com 18 migrations, schema
lint sem findings, 574/574 asserts pgTAP em 12 arquivos (72 da W3B), 108/108
testes unitários em 17 arquivos e 6/6 E2E. Typecheck, lint, build e todos os
subgates de `verify:v2:full` passaram. O resultado agregado do full gate é
`WARN` somente porque o worktree da implementação permanece intencionalmente
dirty e sem commit.

### Deferred e gate

- W3C: `command_idempotency`, `event_handler_receipts`, schemas/registry de
  consumers e contratos TypeScript;
- W3D: campos e boundaries de claim/lease/fencing, handler resolution,
  processing, retry, dead-letter e requeue;
- W3E: hardening adversarial integrado e gate final da infraestrutura W3.

```ini
W3A_AUDIT_HISTORY_READY = YES
W3B_EVENT_OUTBOX_READY = YES
W3C_IDEMPOTENCY_HANDLER_READY = NO
W3D_DELIVERY_RUNTIME_READY = NO
W3E_HISTORY_OUTBOX_HARDENING_READY = NO
W3_INFRASTRUCTURE_READY = NO
```
