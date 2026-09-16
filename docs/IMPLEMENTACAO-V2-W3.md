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

## W3C — Idempotency e Handler Contract

### Estado e escopo

A W3C implementa idempotência de commands selecionados, evidência idempotente
de conclusão por consumer e o contrato TypeScript allowlisted para handlers.
Ela não executa a outbox: claim, lease, fencing, ack, retry, backoff,
dead-letter operacional, requeue, worker e controles de handler continuam
reservados à W3D.

### Command idempotency

`private.command_idempotency` possui namespace único por:

```text
tenant_id + actor_scope + source + command_name + idempotency_key_hash
```

`actor_scope` é derivado pelo helper interno a partir de `application_user` e
seu usuário autoritativo, ou da identidade técnica/sistema controlada. A chave
opaca é validada, transformada em SHA-256 e nunca persistida em texto; portanto
ela não fornece tenant, actor, source, command ou autorização.

O fingerprint do request também é SHA-256, mas tem finalidade separada: ele é
calculado sobre JSONB construído no command somente com sua intenção semântica.
JSONB fornece representação determinística de objetos, independente da ordem
textual das chaves. Correlation, timestamp, key e metadata irrelevante não
participam. Na integração real, entram `command_name`, `profile_name` e
`command_reason`.

`private.acquire_command_idempotency` tenta inserir a identidade sob unique
constraint. Duas transações com o mesmo namespace são serializadas pelo índice
único do PostgreSQL; a concorrente aguarda a decisão da primeira, sem
check-then-insert. Mesmo fingerprint sobre row concluída retorna `command_id` e
resultado original; fingerprint diferente falha com
`IDEMPOTENCY_FINGERPRINT_CONFLICT`. Estado intermediário inesperado falha
fechado.

`private.complete_command_idempotency` permite uma única transição
`in_progress → completed`, persiste resultado JSON seguro e versionado e usa o
timestamp do banco. Namespace, actor, fingerprint, command e resultado
concluído são protegidos contra reescrita. Como acquisition, mutation, Audit,
Event e completion vivem na mesma transaction, qualquer falha causa rollback
integral e não deixa sucesso falso.

### Integração real e compatibilidade

`public.create_tenant_profile(text, text, uuid)` permanece inalterada para
callers W2/W3B. A W3C adiciona a overload explícita e não ambígua:

```text
public.create_tenant_profile(text, text, uuid, text)
```

Os três primeiros argumentos preservam nome, reason e correlation nas posições
existentes; o quarto é a key obrigatória desta variante. A primeira execução
faz Domain mutation + Audit + Event/Outbox + resultado idempotente na mesma
transaction. Replay compatível devolve o mesmo profile ID/version e a
correlation original, sem novo efeito. History permanece N/A para criação de
Perfil.

Essa garantia é de replay transacional no PostgreSQL para o namespace
declarado. Não promete exactly-once distribuído, entrega única por provider nem
execução de consumer.

### Handler receipts e contrato portátil

`private.event_handler_receipts` registra evidência imutável de processamento
concluído e possui unicidade `consumer_name + event_id`. Tenant, event type e
event version são copiados da outbox pelo helper e protegidos por FK composta
para a origem persistida. Mesmo consumer/event retorna receipt e resultado
originais; tentativa de trocar handler/version falha fechada. O receipt não
altera `status` da outbox e não se confunde com command idempotency nem delivery
state.

Os contratos TypeScript tipam `DomainEvent`, `OutboxEnvelope`, `EventHandler`,
`HandlerResult`, `RetryClassification`, `TechnicalExecutionContext`,
`CommandIdempotencyResult` e a projection futura de History. O registry é uma
allowlist em memória por `event_type + event_version`, rejeita duplicidade,
evento/versão desconhecido, payload inválido e tenant divergente. O handler de
prova existe somente no teste unitário, não produz efeito de domínio e recebe a
capability fixa do contrato, nunca do payload. Não há registry operacional em
banco.

### Segurança, testes e garantias

As duas stores estão em `private`, com RLS habilitada, nenhuma policy e nenhum
grant para `PUBLIC`, `anon`, `authenticated` ou `service_role`. Todos os helpers
são `SECURITY INVOKER`, owner `postgres`, `search_path` vazio e sem EXECUTE para
essas roles. Resultados têm formato de objeto, versão positiva, limite de 64
KiB e rejeição recursiva de secrets, authority, handler e dumps.

`supabase/tests/w3c_idempotency_handler_contract.sql` cobre estrutura, grants,
namespace, SHA-256, canonicalização, execução, replay, conflito, rollback,
tenant A/B, receipts e ausência de W3D. O teste complementar
`scripts/w3c-concurrency-test.mjs` abre duas sessões reais no PostgreSQL local,
mantém a primeira transaction aberta para forçar contenção e exige exatamente
uma mutation, um record idempotente, um Audit e um Event, com History N/A e
resultado igual. Seus fixtures locais são removidos ao concluir.

Validação efetiva em Supabase estritamente local: reset completo com 19
migrations, schema lint sem findings, 652/652 asserts pgTAP em 13 arquivos (78
da W3C), teste concorrente PASS, 113/113 testes unitários em 18 arquivos e 6/6
E2E. Typecheck, lint, build e diff-check passaram. O resultado agregado de
`verify:v2:full` é `WARN` somente porque a implementação permanece
intencionalmente sem commit, conforme solicitado.

### Deferred e gate

- W3D: claim por `SKIP LOCKED`, lease/fencing, registry operacional controlado,
  runner, ack/fail, retry/backoff, dead-letter e requeue;
- W3E: hardening adversarial integrado, retenção/cleanup e gate final W3;
- provider/worker produtivo, canais externos e Notifications permanecem fora
  desta subwave.

```ini
W3A_AUDIT_HISTORY_READY = YES
W3B_EVENT_OUTBOX_READY = YES
W3C_IDEMPOTENCY_HANDLER_READY = YES
W3D_DELIVERY_RUNTIME_READY = NO
W3E_HISTORY_OUTBOX_HARDENING_READY = NO
W3_INFRASTRUCTURE_READY = NO
```

## W3D — Delivery Runtime

### Estado e garantia

A W3D implementa o runtime de entrega exclusivamente no PostgreSQL/Supabase
local e um runner Node testável. A garantia é **at-least-once delivery**. Não há
promessa de exactly-once distribuído: proteção contra duplicação combina Outbox
persistida, claim com lease/fencing, receipt W3C e transições condicionais.
Domain tables continuam source of truth e a Outbox não é Event Store.

### Estado técnico da Outbox

`private.outbox_events` preserva integralmente o fato W3B e acrescenta somente
estado operacional mutável:

- `claimed_by`, `claimed_at`, `lease_expires_at` e `lease_token`;
- `fencing_token` monotônico;
- `processed_at`, `last_failed_at` e `dead_lettered_at`;
- `last_error_class`, `last_error_code` e `last_error_message` sanitizada;
- `requeue_count`, preservando contadores entre ciclos de reprocessamento.

Os estados continuam `pending`, `processing`, `processed` e `dead_letter`.
Checks estruturais impedem lease parcial ou timestamp terminal incompatível. O
trigger de imutabilidade continua rejeitando qualquer mudança em identidade,
tipo, versão, tenant, aggregate, actor, source, command, correlation, causation,
payload ou metadata.

### Handler controls e segurança

`private.worker_handler_controls` associa apenas `event_type + event_version`
conhecido a consumer/handler/version compilados, kill switch e política limitada
de lease/retry. A entrada inicial permite somente
`authorization.profile.created@1`. A tabela não carrega módulo, SQL ou
capability executável; configuração em banco pode desabilitar contrato conhecido,
mas não criar código no runner.

A role `cw_worker` é `NOLOGIN` e não possui grant de tabela. Ela recebe EXECUTE
somente em quatro boundaries públicas específicas. O owner local `postgres`
pode assumir essa role para o runner; `PUBLIC`, `anon`, `authenticated` e
`service_role` não podem invocar as boundaries. Helpers privados continuam sem
EXECUTE para worker/cliente, com owner controlado, `search_path` vazio e SQL
estático. `supabase_admin` recebe EXECUTE específico apenas para migrations e
pgTAP locais, sem grant de tabela.

### Claim, lease e fencing

`public.claim_outbox_batch(worker_identity, batch_size)` valida worker e limita o
batch a 1–100. A transação curta:

1. terminaliza contrato desconhecido e tentativa já esgotada elegível;
2. filtra handler habilitado, `pending` vencido ou `processing` com lease expirada;
3. ordena por `next_attempt_at`, `occurred_at`, `event_id`;
4. usa `FOR UPDATE SKIP LOCKED`;
5. incrementa `attempt_count` e `fencing_token`;
6. grava worker, timestamps do banco e lease token UUID novo;
7. retorna somente envelope, estado de claim e identidade allowlisted necessária.

Lease válida não pode ser roubada. Após expiração, novo claim conserva o mesmo
evento, cria token novo e avança o fence. Ack/fail exigem simultaneamente event,
worker, lease token, fence, estado `processing` e lease válida; worker stale falha
com `OUTBOX_LEASE_STALE`.

### Registry, authoritative reread, receipt e ack

O runner `scripts/w3d-local-runner.mjs` reutiliza
`createHandlerRegistry` da W3C. A allowlist compilada valida tipo/versão e schema
Zod, confere consumer/handler/version retornados pelo controle e fornece
capability fixa `authorization.profile.read`. Payload não escolhe handler,
consumer, tenant, capability ou SQL.

Para o evento real integrado, `public.read_profile_created_origin` valida a
lease/fence e relê `public.tenant_profiles` usando tenant e aggregate do evento
persistido. O payload é validado como evidência, mas não autoriza nem substitui
essa releitura. O handler atual é uma projection/probe sem mutation de domínio.

`public.complete_outbox_event` relê controle autoritativo, reutiliza
`private.record_event_handler_receipt` e grava receipt + ack na mesma transação.
Receipt existente torna redelivery um no-op lógico e devolve o resultado
original. O ack muda apenas estado técnico e requer fence atual.

### Failure, retry e dead-letter

`public.fail_outbox_event` aceita somente classes controladas `retryable`,
`non_retryable`, `poison_event` e `unsupported_event`, código estável e mensagem
sanitizada de até 500 caracteres. Bearer, JWT cru, credenciais em query string
(incluindo signed URLs genéricas), assignments de token/key/signature/secret e
dumps reconhecíveis são substituídos integralmente por uma mensagem operacional
genérica; entrada vazia ou acima do limite é rejeitada. O texto sensível original,
payload e erro bruto não são persistidos nem enviados a serviço externo.

Para tentativa retryable dentro do limite:

```text
base = min(backoff_max_seconds,
           backoff_base_seconds * 2^(attempt_in_cycle - 1))
jitter_factor = 1 + jitter_percent/100 * (2*jitter_unit - 1)
delay = max(0, base * jitter_factor)
```

`jitter_unit` é determinístico por `event_id + fencing_token`, e o relógio do
banco define `next_attempt_at`. A configuração inicial usa lease 30 s, máximo 3
tentativas por ciclo, base 1 s, teto 60 s e jitter ±20%. Falha não retryable,
poison/unsupported ou retry esgotado entra em `dead_letter`; claim automático
cessa.

### Reprocessamento controlado

`private.requeue_dead_letter` é invoker, privado e sem grant ao worker. Exige
evento terminal, handler habilitado, actor técnico válido, reason e correlation.
A operação escreve Audit oficial `infrastructure.outbox.requeued`, incrementa
`requeue_count`, preserva tentativas anteriores e abre um novo ciclo limitado;
o fato original permanece byte-a-byte equivalente fora do estado técnico. Não
há UI administrativa, endpoint tenant ou bypass de receipt/fencing.

### Runner e validação

O runner executa uma passagem local (`npm run ops:w3d:run-once`), sem daemon,
deploy, provider, fila externa ou secret. O teste de runner usa operação real de
criação de Perfil e cobre sucesso, falha transitória seguida de sucesso,
esgotamento, dead-letter, poison event e inspeção direta do valor persistido por
`cw_worker -> fail_outbox_event`. Texto operacional é preservado, enquanto Bearer,
JWT cru, signed URL, access token, API key, signature, secret e password sintéticos
convergem para a mensagem genérica sem copiar o material original. Failure
injection é dependência local do teste e nunca vem de evento/payload.

Validação efetiva em Supabase estritamente local: reset completo com 20
migrations, schema lint público/privado sem findings, 729/729 asserts pgTAP em
14 arquivos (77 da W3D), concorrência multi-session W3C/W3D PASS e runner W3D
PASS. A suíte multi-session prova lotes disjuntos por `SKIP LOCKED`, proteção de
lease válida, reclaim expirado, fence novo, stale ack/fail negados e receipt
pré-existente como replay. Unit, E2E, typecheck, lint, build e full gate são
registrados no fechamento da subwave.

### Limitações e deferred

- W3E: hardening adversarial consolidado, inventários finais, retenção/cleanup e
  gate integrado definitivo da infraestrutura W3;
- deploy/daemon cloud, scheduler produtivo e observabilidade externa;
- providers, filas externas, e-mail/SMS/push/webhooks e Notifications completas;
- UI de operação/Global Admin e autorização W13 para wrapper público de requeue.

```ini
W3A_AUDIT_HISTORY_READY = YES
W3B_EVENT_OUTBOX_READY = YES
W3C_IDEMPOTENCY_HANDLER_READY = YES
W3D_DELIVERY_RUNTIME_READY = YES
W3E_HISTORY_OUTBOX_HARDENING_READY = NO
W3_INFRASTRUCTURE_READY = NO
```

## W3E — History/Outbox Hardening e gate integrado

### Escopo e resultado técnico

A W3E não acrescenta schema nem funcionalidade de produto. A revisão integrada
de W3A–W3D não encontrou gap de banco que justificasse alterar migrations já
congeladas; portanto, não existe migration W3E. O hardening acrescenta um gate
pgTAP consolidado, um runner adversarial local e amplia o teste do registry para
campos de payload que tentem escolher autoridade técnica.

O fluxo real validado permanece:

```text
command autorizado -> mutation + Audit + Event + idempotency result
persisted Event -> claim allowlisted -> authoritative reread
-> fixed capability -> receipt + ack
```

History continua separado de Audit e Event. Para a operação real
`create_tenant_profile`, History é deliberadamente N/A; o gate cria uma fixture
History separada apenas para provar append-only e ausência de falsificação.

### Hardening adversarial

`supabase/tests/w3e_history_outbox_hardening.sql` valida de forma efetiva:

- RLS e ausência de policies/grants diretos em Audit, History, Outbox,
  idempotency e receipts;
- nenhuma leitura/injeção cliente em Audit/History e nenhuma inspeção direta da
  infraestrutura privada;
- role `cw_worker` sem login, inheritance, bypass RLS ou privilégios
  administrativos, limitada às quatro boundaries W3D;
- `service_role` sem shortcut de delivery e sem grants de tabela W3;
- owner `postgres`, `SECURITY DEFINER` necessário e `search_path` vazio nas
  quatro boundaries públicas do worker;
- Audit e History append-only por update/delete adversarial;
- imutabilidade de todas as classes factuais do Event: identidade, type/version,
  tenant, aggregate, actor/source, command/correlation/causation,
  payload/metadata e timestamp;
- command idempotency real, replay estável sem duplicação e conflito semântico
  fail-closed;
- payload com `tenant_id`, `handler` ou `capability` incapaz de conferir
  autoridade;
- limites de batch 1–100 e mensagem de erro 1–500;
- ausência de boundary implícita de purge/cleanup.

O registry TypeScript também rejeita payloads extras sintéticos chamados
`tenant_id`, `actor_id`, `role`, `permission`, `scope`, `capability`, `handler`,
`consumer`, `function`, `sql`, `worker_id`, `lease_id`, `fencing_token`,
`service_role` e `authorization`. Handler, consumer e capability continuam
allowlisted/compilados; não há dynamic import, `eval` ou SQL escolhido pelo
evento.

### Concorrência, fencing e falhas

Os runners multi-session existentes continuam sendo parte obrigatória do gate.
W3C usa duas conexões PostgreSQL reais concorrentes e prova uma única mutation,
idempotency row, Audit e Event. W3D usa sessões distintas para provar claims
disjuntos por `FOR UPDATE SKIP LOCKED`, lease válida sem steal, reclaim após
expiração, incremento do fence e rejeição de ack/fail stale. Receipt replay não
repete efeito lógico.

O runner integrado mantém retry exponencial com jitter limitado, máximo de
tentativas, poison/unsupported terminal, dead-letter não claimável e requeue
explícito/auditado. O fato Event original permanece imutável. A garantia é
**at-least-once delivery** com idempotência/receipt dentro das fronteiras
implementadas; não é exactly-once distribuído.

`scripts/w3e-adversarial-test.mjs` percorre a boundary real
`cw_worker -> fail_outbox_event -> last_error_message` e lê o valor persistido.
Texto operacional seguro é preservado. Bearer, JWT cru, signed URL genérica,
`access_token`, `refresh_token`, `api_key`, `apikey`, `signature`, `sig`,
`secret`, `password` e conteúdo semelhante a dump usam somente valores
sintéticos e convergem para a mensagem genérica. Entrada acima de 500 caracteres
falha sem alterar o estado; overwrite direto pela role worker é negado.

### Retenção e cleanup

A decisão congelada foi preservada sem inventar prazos:

- Audit é evidência append-only de longa duração e não possui purge normal;
- History acompanha a rastreabilidade do aggregate e não possui hard delete
  normal;
- Outbox `pending`, `processing` ou `dead_letter` não é removida
  automaticamente;
- Outbox `processed` somente poderá receber housekeeping futuro, explícito,
  configurado e compatível com holds/evidência;
- janelas de retenção de command idempotency e receipts continuam decisão
  operacional futura e não podem quebrar replay, correlação ou reprocessamento.

Assim, a responsabilidade W3E de retenção fica resolvida pela comprovação de que
nenhum cleanup inseguro existe e pela documentação dos limites, não por uma
política numérica arbitrária.

### Validação local

O reset local aplica 20 migrations históricas inalteradas. Schema lint público e
privado passa sem findings. A suíte contém 774/774 asserts pgTAP em 15 arquivos,
incluindo 45 W3E, além de concorrência W3C/W3D, runner W3D e adversarial W3E.
Unit possui 132/132 testes, E2E 6/6, typecheck, lint e build passam. O full gate
permanece autorizado a reportar `WARN` exclusivamente pelo worktree W3E ainda
sem commit; falha funcional ou de segurança continua bloqueante.

Continuam fora do escopo: worker/deploy/scheduler de produção, observabilidade
externa, providers, filas, webhooks, Notifications, UI administrativa, prazos de
retenção operacionais e qualquer funcionalidade W4.

```ini
W3A_AUDIT_HISTORY_READY = YES
W3B_EVENT_OUTBOX_READY = YES
W3C_IDEMPOTENCY_HANDLER_READY = YES
W3D_DELIVERY_RUNTIME_READY = YES
W3E_HISTORY_OUTBOX_HARDENING_READY = YES
W3_INFRASTRUCTURE_READY = YES
```
