# Plano de implementação da W3 — History, Audit operacional, Outbox e eventos

## 1. Estado, finalidade e gate

Este documento fecha o planejamento técnico da W3 sem implementar schema,
migration, runtime, worker ou domínio. A entrada oficial é o commit
`9400f6eb053ef2f321f5d2dac6310938259d4ed6`, na branch local
`feat/v2-w3-history-outbox`, com W0, W1 e W2 prontas e
`AUTHORIZATION_READY = YES`.

A W3 cria o kernel transacional e de rastreabilidade que as waves de domínio
usarão depois. Ela concretiza os design blockers `DD-04` e `DD-05` do roadmap,
preserva `AUTH-02` e `TECH-01` e termina somente quando o gate arquitetural
`AUDIT_READY` puder ser provado pela implementação W3A–W3E.

Estado após este planejamento:

```ini
W3_PLAN_COMPLETE = YES
W3A_READY = NO
W3B_READY = NO
W3C_READY = NO
W3D_READY = NO
W3E_READY = NO
W3_INFRASTRUCTURE_READY = NO
```

## 2. Fontes e precedência

Foram consideradas, nesta ordem:

1. `AGENTS.md` e `PRODUCT_SPEC.md`;
2. `docs/ARQUITETURA-TECNICA-V2.md`;
3. `docs/DEVELOPMENT-WORKFLOW.md`;
4. `docs/MIGRACAO-V1-V2-10C-CRITICOS.md`;
5. `docs/MIGRACAO-V1-V2-10E-PLANO-IMPLEMENTACAO.md`;
6. `docs/IMPLEMENTACAO-V2-W1.md`;
7. `docs/IMPLEMENTACAO-V2-W2-PLANO.md` e
   `docs/IMPLEMENTACAO-V2-W2.md`;
8. migrations, pgTAP, harness local, tipos gerados e boundaries frontend W0–W2.

As decisões `CLOSED` da arquitetura prevalecem. Este plano detalha decisões
marcadas anteriormente como `IMPLEMENTATION-DEPENDENT`; não altera a arquitetura
congelada. Não foi identificado conflito que exija change control.

## 3. Escopo e exclusões

### 3.1 Escopo oficial

A W3 deve entregar:

- evolução forward-only do Audit existente;
- History funcional reutilizável e semanticamente tipado;
- envelope imutável de evento e Transactional Outbox;
- idempotência de commands e handlers;
- claiming concorrente, lease, fencing, retry e dead-letter;
- contrato portátil de worker com registry allowlisted;
- correlação, causação, actor/source e observabilidade mínima;
- boundaries de segurança, RLS, grants, retenção e integração de commands;
- testes transacionais, adversariais, concorrentes e de regressão W1/W2.

### 3.2 Fora de escopo

Não pertencem à W3:

- módulos de Manutenção, Solicitações, OS, Ativos, Fornecedores, Cadastros,
  Relatórios, Calendário ou Preventivas;
- implementação completa de Notifications, preferências, caixa de entrada,
  delivery por canal ou UI;
- e-mail operacional, WhatsApp, SMS, push ou escolha de fornecedor;
- filas externas, Redis, Kafka, RabbitMQ, SQS, Celery ou Temporal;
- scheduler funcional, webhook ou integração real;
- worker cloud/produtivo e provider definitivo;
- Supabase Realtime ou `LISTEN/NOTIFY` como barramento durável;
- Global Admin, UI administrativa de outbox ou migração de History legado;
- particionamento, event sourcing e números finais de retenção.

## 4. Vocabulário oficial e invariantes

| Conceito | Pergunta respondida | Source of truth | Visibilidade |
| --- | --- | --- | --- |
| Audit | Quem/qual autoridade fez o quê, quando e sobre qual target? | `public.audit_events` | Fechado; projection futura com capability própria |
| History | Como um registro evoluiu funcionalmente? | `public.history_entries` planejada | Usuários autorizados ao aggregate via projection de domínio |
| Event | Qual fato imutável ocorreu? | Envelope persistido na outbox | Interno; não é endpoint de domínio |
| Outbox | O que precisa ser processado depois do commit? | `private.outbox_events` planejada | Somente boundary técnica |
| Notification | Quem deve ser avisado, como e quando? | Wave futura | Destinatário reautorizado |

Invariantes `W3-INV`:

1. Domain tables continuam source of truth; o produto não é event-sourced.
2. Audit, History, Event, Outbox, Comment, Notification e Alert não se substituem.
3. Mutation, Audit obrigatório, History aplicável e Outbox obrigatória persistem
   na mesma transação do command.
4. Falha de qualquer escrita obrigatória antes do commit causa rollback total.
5. Falha de consumer depois do commit nunca desfaz a mutation de domínio.
6. Audit, History e campos factuais de Event são append-only.
7. Estado de processamento da outbox é mutável somente por boundary técnica.
8. Tenant, actor, authority, handler e timestamp oficial não vêm do payload.
9. Toda relação tenant-owned possui tenant inequívoco e integridade no banco.
10. Delivery é at-least-once; handlers precisam ser idempotentes.
11. Correlation e causation são observabilidade, nunca authority.
12. Nenhum cliente acessa diretamente Audit, Outbox, Idempotency ou worker state.
13. History não amplia acesso ao aggregate ou a entidades relacionadas.
14. Payloads não carregam secrets nem PII desnecessária.
15. Evento desconhecido ou versão incompatível não é descartado nem executado.

## 5. Decisões arquiteturais

### ADR-W3-01 — Audit e History permanecem separados

| Campo | Decisão |
| --- | --- |
| Contexto | W1/W2 já possuem Audit de segurança; domínios futuros precisam timeline funcional. |
| Alternativas | Uma tabela única; tabelas por domínio; Audit existente + History compartilhado. |
| Escolha | Manter `audit_events` como Audit oficial e criar History compartilhado separado. |
| Razão | Visibilidade, retenção, payload e perguntas de negócio são diferentes. |
| Consequência | Um command pode gravar Audit, History, ambos ou nenhum, conforme contrato explícito. |

### ADR-W3-02 — History híbrido

| Campo | Decisão |
| --- | --- |
| Contexto | Uma timeline reutilizável precisa consultar aggregates diferentes sem virar EAV. |
| Alternativas | History genérico; History por domínio; envelope compartilhado com payload semântico por domínio. |
| Escolha | Modelo híbrido: envelope físico compartilhado e contratos semânticos definidos pelo domínio. |
| Razão | Permite `CWHistory`, índices uniformes e retenção sem mover estado de domínio para JSON. |
| Consequência | Payload é pequeno e tipado por `history_type + history_version`; dumps integrais são proibidos. |

### ADR-W3-03 — Outbox é o persisted event record

| Campo | Decisão |
| --- | --- |
| Contexto | Um event store separado duplicaria fatos sem o produto ser event-sourced. |
| Alternativas | Event store + delivery; outbox como evento persistido; dois registros acoplados. |
| Escolha | `private.outbox_events` contém o fato imutável e o estado mutável de entrega na mesma row. |
| Razão | É o modelo mínimo que garante atomicidade e replay operacional. |
| Consequência | Campos factuais recebem proteção estrutural; rows processadas podem ser purgadas conforme retenção futura. |

### ADR-W3-04 — At-least-once e idempotência

| Campo | Decisão |
| --- | --- |
| Contexto | Crash entre efeito e acknowledgement impede garantia geral de exactly-once. |
| Alternativas | At-most-once; exactly-once declarado; at-least-once com handlers idempotentes. |
| Escolha | At-least-once + receipts/idempotency + conditional writes. |
| Razão | Não perde evento silenciosamente e explicita a duplicação possível. |
| Consequência | Todo handler declara uma estratégia de idempotência antes de entrar na allowlist. |

### ADR-W3-05 — Idempotência em duas camadas

| Campo | Decisão |
| --- | --- |
| Contexto | Retry de request e retry de worker são problemas diferentes. |
| Alternativas | Uma chave global; somente outbox; stores separados. |
| Escolha | `command_idempotency` para commands selecionados e `event_handler_receipts` para consumers. |
| Razão | Escopos, fingerprint, resultado e retenção diferem. |
| Consequência | Nem toda mutation exige key; emissão/event processing sempre possui identidade persistida. |

### ADR-W3-06 — Claim com SKIP LOCKED, lease e fencing token

| Campo | Decisão |
| --- | --- |
| Contexto | Vários workers precisam processar lotes sem bloqueio global e recuperar crashes. |
| Alternativas | Flag simples; advisory lock global; `FOR UPDATE SKIP LOCKED` com lease. |
| Escolha | Claim transacional por lote, `SKIP LOCKED`, lease expiráveis e token por claim. |
| Razão | Escala no PostgreSQL, evita espera entre workers e permite recuperação. |
| Consequência | Complete/fail exige o token atual; worker obsoleto não confirma trabalho. |

### ADR-W3-07 — Dead-letter na mesma outbox

| Campo | Decisão |
| --- | --- |
| Contexto | Tabela separada exigiria mover/copyar o fato imutável. |
| Alternativas | Tabela dead-letter; estado terminal na outbox. |
| Escolha | Estado `dead_letter` na mesma row. |
| Razão | Mantém identidade, payload, correlação e tentativas sem duplicação. |
| Consequência | Reprocessamento controlado muda somente metadata de processamento e é auditado. |

## 6. Audit oficial

`public.audit_events` continua sendo a única trilha oficial de segurança e
compliance. Não será criada uma segunda tabela de Audit.

Decisão `AUD-01`: toda ação classificada como obrigatoriamente auditável integra
a mesma transação do command; o evento é append-only, usa actor/authority/target
autoritativos, contém apenas metadata segura e sua falha impede o commit. Esta
decisão nomeia e concretiza as regras `CLOSED` da seção de Auditoria da
arquitetura, sem criar uma trilha concorrente.

### 6.1 Estado existente preservado

O modelo atual já possui `id`, `occurred_at`, `tenant_id`, `actor_user_id`,
`actor_kind`, `correlation_id`, `event_type`, `entity_type`, `entity_id` e
`metadata`; RLS está habilitada, clientes não têm acesso e triggers rejeitam
UPDATE, DELETE e TRUNCATE. Commands W1/W2 gravam Audit na mesma transação.

### 6.2 Evolução forward-only planejada

A W3A deve avaliar os dados existentes e acrescentar, sem reescrever eventos:

- `event_version`: versão positiva do contrato de Audit;
- `command_id`: execução que produziu o evento, quando aplicável;
- `causation_id`: causa imediata, quando aplicável;
- `authority_kind`: `tenant`, `technical` ou `platform`;
- `source`: origem controlada definida na seção 12;
- `actor_ref`: identidade técnica estável quando não existe usuário humano;
- expansão controlada de `actor_kind` para representar `system` sem fabricar
  um Application User;
- `reason`: razão validada e pesquisável, preservando razões antigas em metadata;
- metadata segura para contexto, before/after ou diff semântico e versões.

`event_type` permanece o identificador da operação auditada; não será duplicado
por uma coluna `operation`. `occurred_at` continua vindo do banco. A evolução
deve preservar os inserts W1/W2 durante a transição e migrar writers por etapas.

### 6.3 Contrato de escrita

- `application_user` exige `actor_user_id` atual derivado pelo command.
- `technical` e `platform` exigem `actor_ref` controlado quando não há usuário.
- `tenant_id` é obrigatório para ação tenant-targeted e validado contra target.
- before/after contém somente campos relevantes, não snapshot indiscriminado.
- reason textual preserva o limite atual de 500 caracteres e política de PII.
- correção gera novo Audit/compensação; evento antigo nunca é atualizado.
- falha do Audit obrigatório aborta a transação.

## 7. History funcional

### 7.1 Modelo escolhido

`public.history_entries` será o envelope compartilhado. Ele não é tabela de
estado, Audit, comentário nem event store. Domínios futuros definem o
vocabulário permitido e a projection de leitura.

Campos conceituais mínimos:

| Campo | Regra |
| --- | --- |
| `id` | UUID gerado server-side |
| `tenant_id` | Obrigatório para History operacional |
| `aggregate_type` / `aggregate_id` | Identidade interna do registro |
| `aggregate_version` | Versão resultante quando o aggregate é versionado |
| `human_code` | Metadata opcional de UX; nunca FK/authority |
| `history_type` / `history_version` | Contrato semântico versionado |
| `occurred_at` | `timestamptz` atribuído pelo banco |
| `actor_kind` / `actor_user_id` / `actor_ref` | Humano, técnico ou sistema sem fabricar pessoa |
| `command_name` / `command_id` | Origem da mudança |
| `correlation_id` / `causation_id` | Observabilidade |
| `source` | Taxonomia controlada |
| `payload` | Fatos semânticos mínimos e seguros |

Para mudança de status, o payload esperado é `{from_status, to_status, reason_code?}`,
e não dump da row. Mudanças simples usam diff de campos allowlisted. Texto livre
continua em Comment ou em reason sujeito à política; não vira mensagem histórica
pré-renderizada como source of truth.

Esse contrato permite à UX futura renderizar, por exemplo, “João alterou a
prioridade de Normal para Alta” ou “status alterado para Em andamento” a partir
de fatos estruturados, com localization posterior e sem armazenar HTML.

### 7.2 Consulta futura

History será consultada por endpoint/RPC do domínio, com aggregate type e ID
validados, tenant derivado do principal e permission/scope reavaliados. Não há
SELECT genérico de `history_entries` para `authenticated`. A resposta será uma
projection paginada por keyset `(occurred_at, id)` e poderá produzir frases de
timeline no frontend sem expor payload interno.

### 7.3 Deduplicação e imutabilidade

Quando um command idempotente é repetido, o mesmo `command_id` retorna o
resultado anterior e não cria outra History. A relação lógica
`command_id + aggregate_type + aggregate_id + history_type` será única quando
o contrato do command declarar uma ocorrência única. Casos legitimamente
múltiplos devem fornecer ordinal/identidade semântica explícita.

## 8. Event model e nomenclatura

### 8.1 Envelope oficial

O evento persistido na outbox terá:

- `event_id` UUID imutável;
- `event_type` e `event_version` positivos;
- `occurred_at` atribuído pelo banco;
- `scope_kind`: `tenant` ou `platform`;
- `tenant_id`, obrigatório quando `scope_kind = tenant` e nulo quando platform;
- `aggregate_type`, `aggregate_id` e `aggregate_version` quando aplicáveis;
- `actor_kind`, `actor_user_id` e/ou `actor_ref` conforme a origem real;
- `source`, `command_id`, `correlation_id` e `causation_id`;
- `payload` factual e `metadata` técnica mínima, ambos objetos JSON;
- processing fields definidos na seção 10.

Não haverá `schema_version` duplicada: `event_version` versiona o contrato do
envelope específico. `event_id` e IDs internos são relações autoritativas;
códigos humanos são apenas metadata de UX.

### 8.2 Convenção de tipos

Formato oficial:

```text
<bounded_context>.<aggregate>.<past_tense_event>
```

Segmentos usam lowercase snake_case, sem nomes de tabela como contrato por
padrão. Exemplos conceituais:

- `authorization.profile.updated`;
- `tenant.user.invited`;
- `maintenance.request.created`;
- `maintenance.request.status_changed`;
- `platform.release.published`.

O terceiro segmento descreve um fato ocorrido, não uma ordem imperativa.

### 8.3 Versionamento e compatibilidade

- Mudança aditiva opcional, sem alterar semântica, pode manter a versão.
- Campo obrigatório novo, remoção, rename, mudança de tipo ou semântica exige
  incremento de `event_version`.
- Registry declara exatamente os pares `event_type + event_version` suportados.
- Consumers antigos processam somente versões explicitamente suportadas.
- Versão nova desconhecida vai para dead-letter; não há fallback genérico.
- Eventos persistidos nunca são migrados ou reescritos in-place.

## 9. Correlation, causation e command identity

`correlation_id` agrupa uma operação/processo maior e atravessa request,
command, transaction, Audit, History, Outbox e worker. Um UUID vindo do cliente
pode ser aceito apenas como sugestão de correlação após validação; o servidor
gera outro quando ausente/inválido. Ele nunca seleciona tenant, actor ou acesso.

`causation_id` aponta para a causa imediata. Commands raiz usam nulo; um handler
disparado por evento usa o `event_id` anterior. Eventos encadeados mantêm a
mesma correlação e mudam a causação.

`command_id` será adotado porque identifica uma execução lógica e liga Audit,
History, Outbox e Idempotency sem sobrecarregar correlation. Ele é gerado no
boundary confiável e permanece estável em replay idempotente. Não substitui
`idempotency_key`.

## 10. Transactional Outbox

### 10.1 Tabela e estados

`private.outbox_events` nasce dentro da transaction do command. Estados oficiais:

| Estado | Significado |
| --- | --- |
| `pending` | Elegível quando `next_attempt_at <= database_time` |
| `processing` | Possui claim/lease vigente |
| `processed` | Handler confirmou conclusão idempotente |
| `dead_letter` | Não retryable, poison, versão desconhecida ou limite esgotado |

Não haverá estado `failed`: falha retryable volta a `pending`, preserva erro
seguro e agenda nova tentativa; falha terminal vira `dead_letter`.

Processing fields mutáveis:

- `status`, `attempt_count`, `next_attempt_at`;
- `claimed_by`, `claimed_at`, `lease_expires_at`, `lease_token`;
- `processed_at`, `last_error_class`, `last_error_code`, `last_error_message`;
- `handler_name`, `handler_version` resolvidos pela allowlist, nunca pelo payload;
- `requeue_count` e timestamps técnicos quando aplicável.

Campos do envelope/event fact não podem ser atualizados. Trigger/constraint
de imutabilidade deve comparar OLD/NEW e aceitar somente processing fields.

### 10.2 Payload

Payload contém fatos necessários ao efeito, não snapshots gigantes. Quando o
consumer precisa do estado no momento do evento, o fato relevante deve estar
no payload; quando precisa da verdade atual para decidir, relê a origem. Os dois
casos podem coexistir: fato histórico no envelope, authority e preconditions na
releitura.

`payload + metadata` terá limite inicial combinado de 64 KiB. Exceder é erro de
contrato e exige redesenho, não truncamento. Chaves são allowlisted por schema
do evento. JSON não pode carregar authority arbitrária.

### 10.3 Atomicidade

```text
begin
→ estabilizar/reautorizar conforme AUTH-02
→ adquirir/validar idempotency record quando exigido
→ mutar domínio
→ gravar Audit obrigatório
→ gravar History aplicável
→ enqueue de cada Event obrigatório
→ concluir idempotency record com resultado seguro
→ commit
```

Insert de outbox posterior ao commit é proibido para eventos obrigatórios.

### 10.4 Consistência eventual e duplicação

O commit confirma domain/Audit/History/Outbox, mas não confirma que um consumer
já executou. A UI futura deve representar processamento pendente quando isso
for funcionalmente relevante e nunca presumir entrega instantânea.

Um command idempotente atribui identidade determinística por
`command_id + event_type + event_ordinal` dentro da execução lógica. Replay do
command não cria uma segunda outbox para o mesmo fato; eventos múltiplos
legítimos usam ordinais distintos definidos pelo contrato, nunca pelo browser.

## 11. Claiming, ordering e fencing

O worker chama uma boundary técnica que, em uma transação curta:

1. filtra `pending` vencidos e leases expirados elegíveis;
2. respeita kill switch do handler;
3. ordena por `next_attempt_at`, `occurred_at`, `event_id`;
4. usa `FOR UPDATE SKIP LOCKED` com batch limitado;
5. atribui `processing`, worker identity, lease e token imprevisível;
6. retorna somente o envelope necessário ao handler.

Global ordering não é prometido. Quando um domínio exigir ordem por aggregate,
`aggregate_version` permitirá ao handler rejeitar, aguardar ou aplicar
conditional write. Índice/constraint pode serializar tipos específicos no
futuro; não haverá lock global.

Complete/fail/release exigem `event_id + lease_token` atual. Lease antiga não
pode confirmar, falhar ou sobrescrever resultado. DB time é autoridade para
lease, scheduling, retry e `occurred_at`; relógio do browser/worker não é.

Ordem canônica para commands futuros:

1. tenant/advisory lock quando necessário;
2. idempotency namespace;
3. principal, membership, profile, entitlement e permission facts;
4. aggregate root;
5. children em ordem estável de tipo e ID;
6. appends de Audit, History e Outbox.

Worker: claim de outbox → handler control → releitura do aggregate → receipt/
conditional effect → acknowledgement com fencing.

## 12. Actor e source

Actor e authority são dimensões separadas:

| Actor | Representação | Regra |
| --- | --- | --- |
| Humano | `application_user` + `actor_user_id` | Derivado de `auth.uid()` e estado DB atual |
| Técnico | `technical` + `actor_ref` | Identidade fixa do processo/handler |
| Sistema | `system` + `actor_ref` | Regra interna sem pessoa humana |
| Plataforma | `platform` + identidade apropriada | Futuro W13; não é profile tenant |

Taxonomia `source` controlada:

```text
user_command | system | worker | scheduler | integration | platform | migration
```

Source vindo do cliente nunca é aceito como fato. `scheduler`, `integration`,
`platform` e `migration` ficam estruturalmente previstos, mas seus endpoints e
autoridades permanecem deferred às waves correspondentes.

## 13. Segurança e minimização de dados

Decisão `W3-DATA-01`: envelopes persistem somente dados necessários ao contrato
e sua rastreabilidade. Este identificador não substitui o `DATA-01` do roadmap,
que continua sendo o blocker de mapping tenant/cross-tenant/orphan de W15–W17.

É proibido persistir em Audit, History, Event, Outbox, receipts ou logs:

- senha, JWT, refresh/access token, raw invitation token ou credential;
- `service_role`, chave privada ou secret de provider;
- signed URL prolongada;
- conteúdo integral de anexos;
- PII não necessária ao fato ou dump indiscriminado de request/row;
- stack trace ou erro bruto de banco em campos públicos/operacionais.

`last_error` guarda classe, código estável e mensagem sanitizada limitada a 500
caracteres. Diagnóstico interno detalhado, quando necessário, permanece em
observabilidade restrita e correlacionada.

Cross-tenant é impedido por tenant explícito, FKs/constraints compostas quando
há parent tenant-owned, helpers que derivam tenant do command/origin e testes
Tenant A/B. `scope_kind = platform` não concede Global Admin nem permite evento
tenant sem tenant; apenas reserva envelope para fatos globais futuros escritos
por boundary distinta.

## 14. Idempotência de commands

`private.command_idempotency` será usada somente quando retry puder duplicar
efeito: criação por integração, scheduler, webhook, operações com side effects
ou command explicitamente classificado. Leituras e mutations naturalmente
condicionadas não recebem key por padrão.

Namespace único:

```text
tenant_scope + actor/source_scope + command_name + idempotency_key
```

O registro contém `command_id`, fingerprint SHA-256 de input semântico
canonicalizado, estado, resultado seguro versionado, timestamps e expiração
configurável. Correlation, timestamps e a própria key não entram no fingerprint.

Semântica:

- primeira execução cria o namespace dentro da transaction;
- concorrente com a mesma key aguarda/observa a linha única;
- mesma key + mesmo fingerprint retorna o resultado persistido sem novo efeito;
- mesma key + fingerprint diferente retorna conflito determinístico;
- falha/rollback antes do commit não deixa sucesso falso;
- key é opaca, limitada e nunca usada como authority;
- cleanup só remove records expirados fora de transação ativa.

## 15. Idempotência de handlers

`private.event_handler_receipts` terá unicidade
`consumer_name + event_id`. Ela registra handler/version, resultado seguro e
timestamps. O handler verifica/cria o receipt na mesma transaction do efeito
DB quando isso for possível.

Para efeitos externos, `event_id` é enviado como idempotency key quando o
provider suportar. Sem suporte externo, duplicação continua possível e deve ser
tratada pelo adapter; exactly-once não será declarado.

Retry do mesmo evento não cria History, Notification ou efeito duplicado. Se um
handler produzir novo command/event, o novo `command_id` referencia o event
original por `causation_id`.

## 16. Worker contract e TECH-01

Pipeline obrigatório:

```text
outbox persistida
→ claim condicionado e fenced
→ event_type/version em registry allowlisted no código
→ schema validado
→ tenant/origin relidos
→ capability técnica fixa do handler
→ efeito idempotente/conditional
→ receipt
→ acknowledgement fenced
→ telemetria sanitizada
```

O nome do handler não controla carregamento arbitrário de módulo. O registry é
allowlist compilada `event_type + version → handler + schema + capability`.
Configuração no banco pode desabilitar uma entrada conhecida, mas nunca criar
handler executável ausente do código.

Credencial preferida é role técnica dedicada com EXECUTE apenas nas boundaries
necessárias. Se o provider futuro obrigar `service_role`, a decisão deve ser
documentada e o grant continuará restrito a RPCs específicas; nunca haverá
grant amplo de tabela ou uso como autorização funcional.

O executor cloud permanece provider-dependent. W3 implementará apenas runner
local/testável e contrato portátil; nenhum daemon produtivo será criado.

A transaction do command termina antes do worker. Cada processamento é uma
nova transaction. Se o handler precisar escrever domínio, deve reler o target,
revalidar sua capability técnica fixa e usar expected version/conditional write;
o envelope não autoriza a escrita.

## 17. Retry, dead-letter e reprocessing

Classificação oficial:

| Classe | Ação |
| --- | --- |
| `retryable` | Incrementa tentativa, volta a `pending`, agenda backoff exponencial com jitter configurável |
| `non_retryable` | Vai diretamente a `dead_letter` |
| `poison_event` | Schema/payload inválido vai a `dead_letter` |
| `unsupported_event` | Tipo/versão não suportado vai a `dead_letter` |
| `attempts_exhausted` | Retryable que alcançou limite vai a `dead_letter` |

Não há retry infinito. Batch, lease, máximo de tentativas e curva de backoff são
configuração validada da implementação, não dados controlados pelo evento.

Reprocessing futuro:

- somente operador técnico autorizado, nunca tenant comum;
- exige reason, correlation e Audit;
- não altera payload, type, version, tenant, actor ou occurred_at;
- cria nova tentativa e novo lease, preservando contadores anteriores;
- pode ser bloqueado por kill switch;
- continua sujeito a receipt e idempotência.

## 18. Error e failure contracts

| Falha | Estado esperado | Recovery |
| --- | --- | --- |
| Domain mutation falha | Nada do command persiste | Corrigir input/estado e reenviar |
| Audit obrigatório falha | Domain/History/Outbox/Idempotency fazem rollback | Corrigir Audit; command não é confirmado |
| History obrigatória falha | Domain/Audit/Outbox fazem rollback | Corrigir contrato/schema |
| Outbox obrigatória falha | Domain/Audit/History fazem rollback | Corrigir enqueue/schema |
| Worker cai antes do claim | Evento continua `pending` | Outro worker pode reclamar |
| Worker cai após claim, antes do efeito | `processing` até lease expirar | Reclaim com novo fencing token |
| Efeito DB e receipt commitam, ack falha | Outbox pode ser reclamada | Receipt torna replay no-op e permite ack |
| Efeito externo ocorre, ack falha | Possível redelivery | Idempotency key externa/adapter deduplica; sem promessa exactly-once |
| Handler rejeita versão | `dead_letter` com código seguro | Deploy de handler compatível + requeue autorizado |
| Erro não retryable | `dead_letter` | Inspeção e reprocessamento explícito |
| Tentativas esgotam | `dead_letter` | Operação técnica futura |
| Evento duplicado | Mesmo receipt/conditional effect | No-op observável, sem novo efeito |

Erros públicos mantêm catálogo estável (`validation`, `conflict`,
`invalid_state`, `forbidden`, `unavailable`, `internal`) e correlation segura.
Erro interno, constraint, SQLSTATE ou existência cross-tenant não chega à UX.

## 19. Notification foundation

W3 termina no evento/outbox. Ela apenas define a boundary futura:

```text
event
→ regra de notification allowlisted
→ destinatários derivados de fatos atuais
→ notification record
→ delivery attempts por canal
```

`notification_preferences`, `notifications`, `notification_deliveries`, canais,
templates, read/unread, deep link, severidade, expiração e UI não serão criados
na W3. A wave futura deve prever deduplicação por
`source_event + recipient + notification_type`, conteúdo mínimo e reautorização
ao abrir o link. E-mail operacional, push, WhatsApp e SMS continuam deferred.

## 20. RLS e grants

### 20.1 Matriz planejada

| Objeto | PUBLIC | anon | authenticated | worker técnico | RLS/policy | Mutation boundary |
| --- | --- | --- | --- | --- | --- | --- |
| `public.audit_events` | none | none | none | sem tabela direta | Enabled, sem policy cliente | helper interno/command |
| `public.history_entries` | none | none | none | sem tabela direta | Enabled, sem policy cliente | `private.append_history` |
| `private.outbox_events` | none | none | none | sem tabela direta | Enabled, sem policy cliente | enqueue/claim/ack RPCs mínimas |
| `private.command_idempotency` | none | none | none | sem tabela direta | Enabled, sem policy cliente | helpers de command |
| `private.event_handler_receipts` | none | none | none | sem tabela direta | Enabled, sem policy cliente | handler boundary |
| `private.worker_handler_controls` | none | none | none | sem tabela direta | N/A tenant; schema/grants fechados | operação técnica controlada |

Default privileges continuam fechados conforme W2E. `service_role` não recebe
table grants. Queries de History serão RPCs/projections domain-specific futuras,
nunca policy SELECT genérica. Audit não será exposto por endpoint de History.

### 20.2 SECURITY DEFINER

Toda boundary privilegiada exige owner controlado, `search_path = ''`, objetos
qualificados, SQL estático, PUBLIC EXECUTE revogado e grant mínimo. Actor,
tenant, handler e source são derivados/revalidados. Helpers internos sem
necessidade de elevação permanecem SECURITY INVOKER.

## 21. Helpers e contracts planejados

| Nome conceitual | Schema/segurança | Caller | Authority source | Finalidade |
| --- | --- | --- | --- | --- |
| `append_audit` | `private`, invoker/owner-bound | command confiável | contexto já revalidado | Evoluir o writer existente sem duplicar Audit |
| `append_history` | `private`, invoker/owner-bound | domain command | command + aggregate relido | Inserir History semântico |
| `enqueue_event` | `private`, invoker/owner-bound | command confiável | command/target DB | Persistir envelope outbox |
| `acquire_command_idempotency` | `private` | command idempotente | namespace derivado | Criar/replay/conflito por fingerprint |
| `complete_command_idempotency` | `private` | mesmo command | command_id | Persistir resultado seguro |
| `claim_outbox_batch` | `public`, definer mínima | role técnica; fallback service role explícito | allowlist/config DB | Claim com SKIP LOCKED/lease |
| `complete_outbox_event` | `public`, definer mínima | role técnica; fallback service role explícito | event + lease token | Ack fenced/receipt |
| `fail_outbox_event` | `public`, definer mínima | role técnica; fallback service role explícito | event + lease token | Retry/dead-letter seguro |
| `requeue_dead_letter` | `private`; wrapper W13 se necessário | operador técnico futuro | capability + reason | Reprocessamento auditado |

Nomes físicos e assinaturas serão congelados na migration design de cada
subwave; a responsabilidade acima é CLOSED. As três RPCs públicas técnicas
revogam `PUBLIC`, `anon` e `authenticated`, não aceitam handler/tenant/actor como
authority e não concedem acesso de tabela. Não haverá god function nem RPC de
cliente para inventar Audit, History ou Event.

## 22. Tabelas físicas planejadas

| Tabela | Wave | Responsabilidade |
| --- | --- | --- |
| `public.audit_events` | W3A | Evolução forward-only do Audit oficial |
| `public.history_entries` | W3A | Timeline funcional compartilhada |
| `private.outbox_events` | W3B | Event fact imutável + processing state fenced |
| `private.command_idempotency` | W3C | Replay seguro de commands selecionados |
| `private.event_handler_receipts` | W3C | Deduplicação por consumer/event |
| `private.worker_handler_controls` | W3D | Disable/kill switch de handlers já allowlisted |

Não haverá tabela `domain_events` separada, notification, job genérico,
scheduler, migration registry ou provenance nesta wave.

## 23. Índices e constraints planejados

Somente índices orientados às queries/gates conhecidos:

- History: `(tenant_id, aggregate_type, aggregate_id, occurred_at desc, id desc)`
  e identidade idempotente/command quando aplicável;
- Audit: preservar índices tenant/time e target; avaliar `correlation_id` e
  `command_id` somente após query plan dos testes W3A;
- Outbox claim: índice parcial por `(next_attempt_at, occurred_at, event_id)`
  para `pending`, e índice de lease para `processing`;
- Outbox operability: `status + event_type + occurred_at` sem indexar JSON;
- Idempotency: unique do namespace completo e índice de `expires_at`;
- Receipts: unique `(consumer_name, event_id)`;
- Integridade: checks de scope/tenant, versions positivas, estados, JSON object,
  tamanhos, actor/source e imutabilidade dos facts.

Particionamento é DEFERRED até evidência de volume/performance. O estágio atual
é piloto Serena com evolução SaaS; PostgreSQL/Supabase é suficiente.

## 24. Observabilidade e operabilidade

Campos e logs permitirão obter, sem stack externa obrigatória:

- quantidade pending/processing/dead-letter;
- idade do pending mais antigo;
- retries por tipo/handler;
- latency de claim/processamento;
- failures por classe/código;
- lease expiradas/reclaims;
- resultado idempotente/replay;
- correlation, causation, command, event e release identity.

Logs são estruturados e redigidos; payload completo não é logado. Provider de
métricas/tracing é deferred. Operações futuras incluem listar dead-letter,
requeue, pausar handler e kill switch; UI não integra W3.

`LISTEN/NOTIFY` pode futuramente apenas acordar worker. Durabilidade e polling
continuam na outbox. Supabase Realtime pode otimizar UX futura, nunca substituir
event/outbox.

## 25. Retenção, cleanup e hard delete

- Audit: retenção longa/imutável; prazo legal continua
  `LEGAL/RETENTION-DEPENDENT`; nenhum hard delete normal.
- History: acompanha retenção do aggregate e necessidades de rastreabilidade;
  nenhum hard delete por usuário comum.
- Outbox `pending`, `processing` e `dead_letter`: nunca purgada automaticamente.
- Outbox `processed`: elegível a purge/archive por housekeeping autorizado após
  janela configurada e ausência de hold.
- Idempotency: pode expirar após janela do command; replay fora dela é nova
  operação e precisa ser seguro pelo contrato.
- Receipts: retenção deve cobrir a janela de redelivery e outbox relacionada.
- Correção de Audit/History/Event usa novo registro compensatório/correction.

Nenhuma duração numérica é inventada neste plano. Housekeeping será command/job
técnico allowlisted, idempotente, auditado e testado antes de ativação.

## 26. Integração com commands futuros

Padrão obrigatório, estendendo `AUTH-02`:

```text
intent + expected_version + optional idempotency_key
→ validate contract
→ begin transaction
→ canonical locks
→ reread actor/tenant/authorization/domain facts
→ validate state/version/invariants
→ mutate domain
→ append Audit when security/compliance relevant
→ append History when user-facing evolution exists
→ enqueue Events required after commit
→ complete idempotency result
→ commit
```

Cada command declara uma effect matrix: Audit required/N/A, History required/N/A,
Event list required/N/A e idempotency required/N/A, com justificativa. Não há
insert best-effort após commit.

Exemplo futuro, apenas contratual:

```text
Request.create
→ request row
→ History maintenance.request.created
→ Audit se a operação for auditável
→ Outbox maintenance.request.created
→ commit
```

Solicitação, OS e demais tabelas não são criadas pela W3.

Eventos futuros de Storage podem usar o mesmo outbox, mas permanecem na wave de
Storage. `STO-01` continua intacta: reserve não autoriza finalize; finalize relê
objeto, parent, tenant e contexto atual antes de confirmar metadata ou emitir
evento. Nenhuma URL assinada integra o envelope.

## 27. Contratos TypeScript planejados

Sem implementação nesta missão, W3C deverá tipar:

- `DomainEvent<TType, TVersion, TPayload>`;
- `OutboxEnvelope<TEvent>`;
- `EventHandler<TEvent>` e registry exhaustivo;
- `HandlerResult` discriminado (`processed`, `retryable_failure`,
  `terminal_failure`, `duplicate`);
- `RetryClassification`;
- `TechnicalExecutionContext` sem authority de tenant derivada do payload;
- `CommandIdempotencyResult<TResult>`;
- `HistoryEntryProjection<TPayload>` para uso futuro por domínio.

Não haverá `any`, lookup dinâmico de módulo ou payload não validado. Schemas
runtime e tipos devem compartilhar uma fonte explícita por evento/version.

## 28. Estratégia de testes

### 28.1 pgTAP/DB

- schema, constraints, FKs tenant-aware e índices essenciais;
- RLS/grants/default privileges e direct access negado;
- Audit/History/Event facts append-only;
- processing fields da outbox como única mutation permitida;
- mutation + Audit/History/Outbox atomic e rollback em falha injetada;
- command replay, fingerprint conflict e concorrência de key;
- claim concorrente com `SKIP LOCKED`, lotes disjuntos e reclaim após lease;
- stale fencing token negado;
- retry/dead-letter/requeue sem alterar payload;
- receipts impedindo efeito duplicado;
- Tenant A/B, tenant adulterado e eventos platform/tenant separados;
- functions SECURITY DEFINER, owner/search_path/grants;
- nenhum secret/raw token em payload ou Audit;
- regressão integral W1/W2.

### 28.2 Unit/contract

- parser e schema por `event_type + version`;
- registry allowlisted e unknown event fail-closed;
- classificação de retry e backoff determinístico com clock injetado;
- fingerprint canonical e conflito semântico;
- handler idempotency e conditional result;
- redaction, tamanho de envelope e safe errors;
- mapping de History semântico e contracts TypeScript.

### 28.3 Integration

- command administrativo W1/W2 escolhido escreve Audit + Outbox na mesma
  transaction, com History explicitamente N/A quando não funcional;
- runner local processa test handler, falha, retry e dead-letter;
- crash antes/depois de claim e efeito/ack;
- dois workers recebem lotes disjuntos;
- alteração do aggregate entre event e handler é protegida por fencing/version;
- duplicate delivery não duplica efeito;
- correlação atravessa command → Audit → Outbox → receipt.

E2E só será adicionado se houver jornada de usuário real da W3. Nenhum backdoor,
service role no browser ou domínio fake será criado para satisfazer E2E.

## 29. Subwaves W3A–W3E

### W3A — Audit e History model

**Objetivo:** evoluir `audit_events`, criar o envelope History e writers internos.

**Artifacts:** migration forward-only, pgTAP, tipos gerados, catálogo de actor/
source e matriz de effects para commands existentes.

**Fora:** Outbox, worker, notification e domínio.

**Gate `W3A_READY`:** Audit existente preservado/append-only; actor/authority/
source/correlation fechados; History separado, tenant-safe e sem acesso cliente;
atomicidade/rollback dos writers provada.

### W3B — Event model e Transactional Outbox

**Objetivo:** implementar envelope versionado, outbox e enqueue transacional.

**Artifacts:** migration outbox, imutabilidade factual, índices de claim, helper
enqueue e integração mínima com um command administrativo real W1/W2.

**Fora:** worker produtivo, notification, provider externo.

**Gate `W3B_READY`:** mutation + Audit/History aplicável + Outbox é atômica;
event versioning, tenant constraint, payload bounds e direct access negado.

### W3C — Idempotency e handler contract

**Objetivo:** implementar idempotência de commands/handlers, schemas e registry.

**Artifacts:** stores de idempotência/receipts, helpers, tipos TypeScript,
registry allowlisted e test handler sem efeito de domínio.

**Fora:** loop produtivo e canais externos.

**Gate `W3C_READY`:** replay compatível é estável, fingerprint conflict falha,
duplicate event é no-op e unknown type/version é terminal seguro.

### W3D — Processing, retry e dead-letter

**Objetivo:** provar claim concorrente, lease/fencing, retry/backoff, kill switch
e reprocessamento em runner local.

**Artifacts:** boundaries técnicas mínimas, worker handler controls, runner local
testável, métricas deriváveis e failure injection.

**Fora:** deploy cloud, scheduler real, UI admin e integração externa.

**Gate `W3D_READY`:** workers concorrentes não duplicam claims; crashes são
recuperáveis; stale lease não confirma; retry é limitado; dead-letter é
observável/reprocessável sem mutar fact.

### W3E — Hardening e gate integrado

**Objetivo:** atacar W3A–W3D e regressões W1/W2.

**Artifacts:** suíte adversarial consolidada, inventários RLS/grants/functions,
testes cross-tenant/atomicity/concurrency, documentação final e gates completos.

**Fora:** W4 ou qualquer domínio.

**Gate `W3E_READY`:** zero finding bloqueante, pgTAP/unit/integration/E2E
aplicáveis, typecheck/lint/build/diff/secret scan e reset completo aprovados.
Com W3A–W3E prontas: `W3_INFRASTRUCTURE_READY = YES` e `AUDIT_READY = YES`.

## 30. Dependências e migration order

```text
AUTHORIZATION_READY
        |
        v
W3A Audit + History
        |
        v
W3B Event + Outbox
        |
        v
W3C Idempotency + Handler Registry
        |
        v
W3D Claim + Retry + Dead-letter
        |
        v
W3E Adversarial Hardening
        |
        v
AUDIT_READY / W3_INFRASTRUCTURE_READY
```

Ordem conceitual das migrations futuras, sem arquivos criados agora:

1. evolução compatível de `audit_events` e `history_entries`;
2. `outbox_events`, envelope, immutability e enqueue;
3. `command_idempotency` e `event_handler_receipts`;
4. claiming/ack/fail/requeue e `worker_handler_controls`;
5. hardening forward-only de grants/default privileges/constraints, se findings
   reais exigirem.

Cada subwave regenera `database.types.ts` somente se alterar schema público/RPC
pública e nunca edita o arquivo manualmente.

## 31. Review de decisões

### 31.1 CLOSED nesta W3

- `audit_events` permanece o Audit oficial;
- History usa envelope compartilhado + payload semântico de domínio;
- Audit e History são separados em armazenamento e leitura;
- outbox é o persisted event record, sem event store separado;
- domain tables são source of truth; não há event sourcing;
- event naming e versioning definidos;
- command_id, correlation e causation têm papéis distintos;
- delivery at-least-once e handlers idempotentes;
- idempotency stores separados para commands e handlers;
- claim por `SKIP LOCKED` + lease + fencing;
- estados `pending/processing/processed/dead_letter`;
- dead-letter na mesma outbox;
- handler registry allowlisted em código;
- payload não é authority e possui limite;
- actor/source/timestamp vêm de boundary confiável/DB;
- RLS/grants deny-by-default e service role sem grants amplos;
- notification completa começa depois da W3;
- provider de worker não bloqueia implementação local/portável.

### 31.2 OPEN

Não há decisão arquitetural aberta necessária para iniciar W3A. Ajustes de
assinaturas físicas, nomes finais de constraints e valores de batch/backoff são
detalhes de implementação subordinados aos contratos fechados e devem ser
documentados em cada subwave.

### 31.3 DEFERRED

- provider/topologia cloud e credencial técnica final;
- números legais de retenção, archival e incident hold;
- provider de métricas/tracing;
- particionamento e materialização por volume real;
- `LISTEN/NOTIFY` como wake-up optimization;
- UI de operabilidade e identidade nominal de operador técnico;
- notifications/read-state/preferences/delivery/canais/templates;
- e-mail operacional, push, WhatsApp e SMS;
- integrações/webhooks e scheduler preventivo;
- platform events writers e Global Admin, para W13;
- History/provenance da migração V1, para W15.

### 31.4 BLOCKERS

Nenhum blocker de planejamento permanece. `DD-04` e `DD-05` ficam resolvidos
por este plano, sujeitos à implementação e aos testes W3A–W3E. Blockers de
dados/remoto/cutover W15–W17 não impedem o kernel local da W3.

## 32. Critérios finais do plano

`W3_PLAN_COMPLETE = YES` exige que toda implementação futura respeite este
documento e as fontes superiores. Nenhum subgate de implementação é promovido
por planejamento. W4 só pode começar depois de `AUDIT_READY` e
`W3_INFRASTRUCTURE_READY` reais.

Esta missão não criou migrations, tabelas, SQL, runtime, packages, domain
modules, Notifications, worker produtivo, deploy ou mudança remota.
