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
