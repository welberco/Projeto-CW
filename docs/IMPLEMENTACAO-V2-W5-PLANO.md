# W5 — Ativos estruturais e primeira vertical de Storage

## 1. Estado e autoridade deste freeze

Este documento é o contrato arquitetural definitivo e o plano executável da
W5, baseado no checkpoint
`ff3e5d92d0f12030e1950b4732f0dbc5937a37ce`. Ele é plano, não implementação:
não cria schema, permission, RPC, policy, rota, worker ou componente.

As decisões deste documento especializam, sem enfraquecer, `PRODUCT_SPEC.md`,
`AGENTS.md`, `docs/ARQUITETURA-TECNICA-V2.md` e os contratos concluídos de
W1–W4. Se a implementação descobrir incompatibilidade real com esses contratos,
ela deve parar no gate da subwave e corrigir o plano por decisão explícita; não
pode improvisar uma arquitetura diferente.

Gates finais oficiais: `ASSET_READY` e `STORAGE_FOUNDATION_READY`. Ambos
permanecem `NO` neste freeze.

### Escopo

**IN:** tipos de Ativo, Ativos, allocator/código/aliases, hierarquia, status
cadastral, condição operacional, especificações versionadas, prontuário básico,
Local e Centro de Custo explícitos, lookup mínimo de Solicitante, fotos e
documentos de Ativo, metadata/lifecycle/quota/integridade Tier B, associação
Asset-file, MediaManager para Asset, mobile, estados de processamento/falha,
cleanup e observabilidade.

**OUT:** Supplier/W6, Requests, OS, Preventiva, QR, importação, garantia
avançada, inferência/herança de Local ou Centro de Custo, consumidores Storage
além de Asset, antimalware obrigatório, migração real V1, offline e hardening
transversal W14. W5 não cria placeholders, tabelas, endpoints ou UI para esses
itens.

## 2. Invariantes herdadas W1–W4

- **AUTH-01:** autorização é `Resource + Action + Scope` exato. Não há wildcard,
  `INHERIT`, hierarquia/conversão de scopes nem DENY de um scope subtraindo
  ALLOW de outro.
- **AUTH-02:** command crítico executa `begin → identificar fatos → adquirir
  locks em ordem canônica → reler fatos → reavaliar tenant + entitlement +
  permission + scope → validar domínio + estado + versão → mutar →
  Audit/History/Outbox → concluir idempotência → commit`.
- **RLS-01:** RLS não recursiva, helpers mínimos com `search_path = ''`, nomes
  qualificados, grants mínimos, FKs tenant-aware e payload não autoritativo.
- **TECH-01:** `service_role` é bypass-capable e somente autoridade técnica
  server-side; nunca é autorização de domínio.
- **STO-01:** reserve não garante autorização futura; finalize reautoriza.
- **AUD-01:** Audit é append-only e falha de Audit obrigatório aborta o command.
- Global Admin permanece fora dos endpoints e Perfis tenant.
- `tenantRef`, URL, cache, código, alias, key de Storage e payload são seletores,
  nunca autoridade.
- Commands expostos ao cliente usam idempotência W3 quando retry pode duplicar
  efeitos; eventos usam outbox W3, schema/version e payload allowlisted.

## 3. DEC-05 — Asset, Local, Centro de Custo e hierarquia

### 3.1 Modelo e relações

`asset_types` e `assets` são tenant-owned. Asset possui UUID técnico estável,
código humano, `asset_type_id`, `parent_asset_id` nullable, `location_id`
nullable e `cost_center_id` nullable. FKs entre entidades tenant-owned incluem
tenant nas duas pontas.

Local e Centro de Custo são relações explícitas, independentes e já entregues
pela W4. Create/update valida que a referência é do mesmo tenant e está ativa.
Inativação posterior do catálogo não reescreve o vínculo histórico. Não existe
`effective_location`, `effective_cost_center`, herança implícita, cascata ou
autorização por ancestralidade.

Alterar `parent_asset_id` modifica somente a linha alvo. Não reescreve
`parent_asset_id`, Local ou Centro de Custo dos descendentes; os descendentes
continuam ligados ao alvo e, por isso, toda a subárvore entra no cálculo de
profundidade da mudança.

### 3.2 Profundidade, ciclo e estados do parent

- root tem profundidade 1; o máximo é 32 nós da raiz ao nó, inclusive;
- profundidade 32 é aceita e 33 é rejeitada;
- self-parent, parent cross-tenant e ciclo direto ou indireto são rejeitados;
- um novo parent precisa estar `ACTIVE` no instante estabilizado da decisão;
- create com parent e move validam também que a maior profundidade da subárvore
  movida continuará menor ou igual a 32;
- parent `INACTIVE` ou `DECOMMISSIONED` não recebe child novo ou movido;
- inativar ou baixar um parent com child direto `ACTIVE` é proibido;
- child inativo pode permanecer historicamente sob parent baixado, mas não pode
  ser reativado sem antes ser movido para parent `ACTIVE` ou para root;
- não há DELETE físico normal de Asset.

### 3.3 Protocolo autoritativo de concorrência da hierarquia

Toda mutation que pode observar ou alterar hierarquia/lifecycle — create com
parent, move, inactivate, reactivate e decommission — deve adquirir primeiro um
lock transacional estável no namespace `asset_hierarchy` por tenant. A chave é
derivada internamente e deterministicamente; não vem do payload. Esse lock
serializa essas decisões no mesmo tenant e é o fence obrigatório contra duas
transações simultâneas `A.parent=B` e `B.parent=A`.

Depois do lock de hierarquia, o command adquire row locks dos Assets relevantes
em UUID ascendente: alvo, parent antigo, parent novo e dependentes necessários.
Então relê a cadeia e a subárvore por consulta recursiva protegida contra loop,
reavalia AUTH-02, versão, lifecycle, ciclo e profundidade, e só então escreve.
Locks de outros agregados seguem a ordem: tenant/namespace → Assets ordenados →
Local → Centro de Custo → efeitos W3.

Esse protocolo resolve obrigatoriamente:

| Race | Resultado obrigatório |
| --- | --- |
| move × move | uma decisão estabiliza primeiro; a segunda relê e não cria ciclo/lost update |
| move × create child | ambas usam o mesmo lock; create relê parent e profundidade finais |
| decommission parent × create child | somente uma vence; a outra falha por child ativo ou parent não `ACTIVE` |
| decommission parent × move child para parent | somente uma vence; move não liga a parent baixado |
| inactivate parent × reactivate child | somente uma vence; não resulta child ativo sob parent não ativo |

Um `SELECT` recursivo isolado, apenas row locks da cadeia observada ou check no
frontend não satisfazem este freeze. Testes multi-session PostgreSQL reais são
gate da W5B.

## 4. Código AT-00001, allocator e aliases

### 4.1 Allocator

O UUID é a identidade técnica; `AT-00001` é código visual imutável na W5. O
allocator é por tenant e domínio Asset, com uma linha autoritativa de próximo
número e lock `FOR UPDATE` (ou serialização equivalente).

`create_asset` deve, na mesma transação:

1. derivar ator/tenant e adquirir idempotência W3 antes de alocar;
2. em replay compatível, retornar exatamente o Asset já criado sem tocar no
   allocator;
3. adquirir lock do allocator do tenant;
4. reservar/incrementar o próximo número;
5. inserir Asset e seu identificador canônico no registry da seção 4.2;
6. gravar Audit/History/Outbox e concluir idempotência;
7. commit atômico.

Unique constraints são a última defesa. Dois creates concorrentes nunca recebem
o mesmo número; o mesmo command/key nunca consome outro número. Código não é
reutilizado, inclusive após inativação/baixa. Gaps são aceitáveis; compaction e
renumeração são proibidas.

### 4.2 Namespace único de identificadores

Código canônico, alias e legacy alias compartilham um registry tenant-aware com
unique sobre `(tenant_id, normalized_identifier)`. Cada entrada aponta para um
único `asset_id` e tem `kind = CANONICAL | ALIAS | LEGACY_ALIAS`. O código
canônico é registrado atomicamente na criação; alias só nasce por command
autorizado/versionado. Remover um alias o aposenta, mas não libera seu valor
para outro Asset.

Normalização é uma função server-side única, imutável e testada: trim nas
extremidades, colapso de whitespace interno para um espaço e comparação
case-insensitive em collation estável. Vazio é inválido. A mesma função é usada
para unique e lookup; frontend não define a forma canônica.

Lookup exato consulta o registry, não executa precedência “código primeiro” ou
fallback ambíguo. Colisão entre código canônico, alias ou legacy alias do mesmo
tenant falha, mesmo se os kinds diferirem. Tenant diferente pode reutilizar o
texto. Alias nunca substitui UUID, não autoriza acesso e não é chave de FK.

## 5. Status cadastral e condição operacional

As máquinas são independentes.

**Registration:** `ACTIVE`, `INACTIVE`, `DECOMMISSIONED` (label de produto
“Baixado”). **Operational:** `OPERATIONAL`, `PARTIAL`, `UNDER_MAINTENANCE`,
`OUT_OF_OPERATION`.

| Origem | Destino cadastral | Regras |
| --- | --- | --- |
| criação | `ACTIVE` | tipo/referências/spec válidos |
| `ACTIVE` | `INACTIVE` | reason; sem child `ACTIVE`; bloqueia novas relações operacionais/arquivos |
| `ACTIVE` | `DECOMMISSIONED` | reason; sem child `ACTIVE`; terminal |
| `INACTIVE` | `ACTIVE` | parent ausente ou `ACTIVE`; referências necessárias e specs continuam válidas na revisão vinculada |
| `INACTIVE` | `DECOMMISSIONED` | reason; sem child `ACTIVE`; terminal |
| `DECOMMISSIONED` | qualquer | proibido |

Asset `ACTIVE` aceita update, move e nova associação de arquivo conforme
capability. Asset `INACTIVE` admite somente correção administrativa allowlisted,
move necessário para reativação, reativação ou baixa; não recebe arquivo novo.
Asset `DECOMMISSIONED` não aceita update/move/status reverso, alteração de
condição, nova associação, reserve/finalize/retry ou remoção ordinária de
prontuário. Seus dados, arquivos já `AVAILABLE`, History e Audit permanecem
legíveis conforme permission e retenção.

Condição operacional pode mudar somente em Asset `ACTIVE` ou `INACTIVE`, por
update autorizado/versionado; após `DECOMMISSIONED` fica congelada no último
valor. Condição nunca altera status cadastral por inferência e sinalização
derivada futura não sobrescreve silenciosamente o valor persistido.

## 6. Especificações JSONB sem JSON arbitrário

### 6.1 Meta-schema W5

Cada Asset Type possui revisões imutáveis de definição. A revisão declara
`definition_schema_version = 1`, `asset_type_id`, número crescente e uma lista
ordenada de campos com chave técnica ASCII estável, label, tipo, `required` e
`nullable` explícitos.

Tipos W5: `STRING`, `INTEGER`, `DECIMAL`, `BOOLEAN`, `DATE` ISO-8601 e `ENUM`
de string. Constraints suportadas são somente: `min_length`, `max_length` e
pattern allowlisted para string; `minimum`/`maximum` para número; opções únicas
e não vazias para enum. Constraints incompatíveis com o tipo são rejeitadas.
Objetos aninhados, arrays livres, scripts, expressões, dependências entre campos
e UI/form builder genérico ficam fora da W5.

`assets.specifications` é objeto JSONB fechado: unknown keys são sempre
rejeitadas; required ausente falha; `null` só é aceito com `nullable=true` e não
satisfaz required quando a definição exigir valor; tipos e constraints são
validados server-side no command. Zod/frontend melhora UX, mas não é autoridade.

### 6.2 Evolução segura

Asset referencia explicitamente a revisão imutável usada. Alterar a definição
do Asset Type cria nova revisão; nunca edita revisão já referenciada e não torna
Assets existentes retroativamente inválidos. Reads informam a revisão aplicada.

Update de campo não relacionado valida as specs contra a revisão já vinculada,
não contra a última. Alterar specifications para adotar uma revisão nova é
operação explícita com `expected_version`, payload integral validado e troca
atômica da referência. Alterar `asset_type_id` exige tipo alvo `ACTIVE`, revisão
corrente explícita e specifications integrais válidas; não há carry-over ou
mapeamento silencioso. Remoção/rename de campo em revisão futura não reescreve
snapshot antigo. Migração em massa e editor low-code estão fora da W5.

## 7. Matriz de autorização W5

Há **19 capabilities** W5, módulo `shared`, `tenant_delegable=true`,
`required_entitlement_key = null`, todas com scope `ALL_TENANT`. OWN, ASSIGNED e
TEAM não têm relação autoritativa em Asset W5 e não existem. `created_by` é
autoria, não OWN. Não há wildcard, `manage`, inferência por display name ou
autorização implícita pela URL.

| Resource | Action | Finalidade / consumer |
| --- | --- | --- |
| `asset_types` | `read` | list/detail administrativo, inclusive inativos e revisões |
| `asset_types` | `lookup` | projeção mínima de tipos ativos para forms/filtros |
| `asset_types` | `create` | criar tipo e primeira revisão de spec |
| `asset_types` | `update` | metadata e nova revisão explícita de spec |
| `asset_types` | `inactivate` | impedir novas seleções, preservar referências |
| `asset_types` | `reactivate` | reativar tipo por command |
| `assets` | `read` | list/detail/prontuário autorizado |
| `assets` | `lookup` | lookup mínimo ativo, inclusive Requester |
| `assets` | `create` | criar Asset e alocar código |
| `assets` | `update` | campos allowlisted, aliases, specs e condição; não move/não baixa |
| `assets` | `move` | alterar somente `parent_asset_id` sob protocolo hierárquico |
| `assets` | `inactivate` | `ACTIVE → INACTIVE` |
| `assets` | `reactivate` | `INACTIVE → ACTIVE` |
| `assets` | `decommission` | transição terminal para Baixado |
| `asset_files` | `read` | metadata pública e signed read contextual de `AVAILABLE` |
| `asset_files` | `reserve` | criar reservation e emitir capability exata |
| `asset_files` | `finalize` | confirmar upload com reautorização corrente |
| `asset_files` | `delete` | remoção lógica/controlada e enqueue de cleanup; não hard delete direto |
| `asset_files` | `retry` | solicitar novo processamento de `FAILED` elegível |

Códigos: `shared.<resource>.<action>.all_tenant`. `lookup` é projeção estreita,
não `read`; possuir lookup não autoriza mutation. `update` não absorve `move`,
status ou decommission. `delete` não entrega Storage delete ao usuário.

### 7.1 Baselines e rollout

| Template | Grants W5 |
| --- | --- |
| `manager` | as 19 combinações |
| `technician` | `asset_types.lookup`; `assets.read/lookup`; `asset_files.read/reserve/finalize/retry` |
| `assistant` | `asset_types.lookup`; `assets.read/lookup`; `asset_files.read` |
| `requester` | somente `assets.lookup` |

O rollout é add-only, determinístico, transacional, idempotente, por UUID e
`template_key` oficiais, nunca nome visível. Valida as versões vigentes no fim
da W4 antes de escrever; atualiza templates oficiais e instâncias derivadas,
preserva grants existentes e exact overrides, exclui Custom Profiles e usa
ledger/Audit W4. Manager possui todas as combinações delegáveis para preservar
antiescalada exata W2. Reexecução não duplica grant/Audit.

### 7.2 Requester lookup

`assets.lookup` do Requester retorna somente Assets `ACTIVE` do tenant atual,
paginados/limitados, com UUID, código, nome, status cadastral e condição
operacional. Não retorna descrição extensa, Local/CC detalhado, specs, parent
tree, prontuário, arquivos, bucket/key, MIME, tamanho, SHA-256, Audit, History ou
metadata técnica. Não equivale a `assets.read`; W5 não cria Request/OS.

### 7.3 Inventário obrigatório de commands e reads

Os nomes físicos podem seguir a convenção SQL/TypeScript existente, mas não
podem fundir boundaries. O contrato funcional mínimo é:

| Resource | Reads | Commands |
| --- | --- | --- |
| Asset Type | list/detail (`read`), selector (`lookup`) | create, update metadata/create revision, inactivate, reactivate |
| Asset | list/detail/prontuário (`read`), selector (`lookup`) | create, update fields/specs/aliases/condition, move, inactivate, reactivate, decommission |
| Asset File | list/metadata/signed read (`read`) | reserve, finalize, delete lógico, retry processing |

Cada command usa exatamente a action da matriz, `ALL_TENANT`, AUTH-02,
idempotency key, reason quando há lifecycle/remoção, correlation opcional e
`expected_version` para registro existente. Alias add/retire pertence a
`assets.update`, usa patch allowlisted e expected version; não existe endpoint
de alias que dispense essa permission. Reads `lookup` nunca retornam campos de
`read`, e signed read nunca é obtido por `assets.read` sozinho.

## 8. DEC-06 — topologia Storage e capability

Bucket privado único: `cw-private-files`. Classes W5: `asset_image` e
`asset_document`. Key: `v1/<object_uuid>`, opaca, imutável, sem tenant, Asset,
filename ou caminho de UI. Não há upsert, move/copy normal, bucket por tenant ou
consumer arbitrário.

Tenant, parent, classe, nome original, MIME declarado, lifecycle, quota e
autoridade ficam no banco. Bucket/key nunca autorizam. Signed upload é uma
capability temporária para bucket/key exatos, emitida somente após reserve
autorizado. O token pode continuar fisicamente aceito após perda de permission;
por isso não é autorização corrente nem pode produzir associação/`AVAILABLE`.

Capability, signed URL e token não são persistidos em domínio, Audit, History,
Outbox, idempotência, telemetria ou logs. Apenas fatos não secretos da emissão
podem ser guardados: reservation, object UUID, issued_at e um
`capability_not_after` conservador. `2h` é duração documentada pelo mecanismo
testado localmente, não prova de expiração efetiva exata nem autorização. A
configuração operacional deve usar no mínimo o máximo documentado pelo provider
mais safety skew; se não houver limite confiável, cleanup automático deve
falhar fechado em vez de presumir expiração.

## 9. DEC-07 — Tier B e modelo de dados Storage

Os fatos são distintos:

- `declared_mime`: declaração do cliente, não confiável;
- `storage_recorded_content_type`: metadata observada no Storage, não prova;
- `verified_mime`: resultado de sniff server-side dos bytes/magic bytes;
- `observed_size`: bytes reais observados;
- `sha256`: digest calculado server-side sobre os bytes lidos.

W5 permite PNG, JPEG e PDF conforme classe e configuração allowlisted. Upload
físico aceito, MIME declarado ou metadata do provider não tornam arquivo válido.
`AVAILABLE` exige Tier B completo.

Registros privados separam reservation, objeto/metadata técnica, job/fence e
contabilidade. A projeção/associação pública de Asset-file nunca expõe key,
token, URL persistida, SHA-256 ou metadata interna. Estados lógicos:

`RESERVED → PENDING_PROCESSING → PROCESSING → AVAILABLE | REJECTED | FAILED`

e finais de retenção `EXPIRED | DELETED`. `FAILED` é retryable quando a causa é
transiente; `REJECTED` é falha determinística de integridade/domínio e não
retorna a processamento sem novo reserve. `AVAILABLE`, `REJECTED`, `EXPIRED` e
`DELETED` não são promovidos novamente.

Estado físico separado: `EXPECTED | PRESENT | DELETE_PENDING | ABSENT |
DELETE_FAILED`. Assim, rejeitar/expirar logicamente não finge que bytes já foram
removidos. Toda linha possui versão/fence monotônico.

## 10. Protocolo normativo de Storage

| Transição | Who / authority | Preconditions autoritativas | Side effects / next state | Retry |
| --- | --- | --- | --- | --- |
| reserve → `RESERVED` | usuário, `asset_files.reserve` | ator/tenant/entitlement/contexto; Asset `ACTIVE`; classe; quota sob lock; idempotência | cria reservation/object UUID/key e hold de quota; Audit/History mínimo; emite capability fora da persistência | mesma key retorna mesma reservation e não duplica hold/token persistido |
| upload físico | cliente com capability | somente bucket/key exatos; `upsert=false` | bytes podem existir; nenhum estado/associação/autoridade DB nasce | provider pode responder retry; não cria segundo key |
| finalize → `PENDING_PROCESSING` | usuário, `asset_files.finalize` | row/fence; reservation vigente; reautoriza ator, tenant, permission, Asset ainda `ACTIVE`, classe, quota, bucket/key; objeto exato existe | registra fatos observáveis iniciais, cria associação pendente, Outbox de inspeção; nunca `AVAILABLE` | idempotency retorna resultado original; conflito de fingerprint falha |
| claim → `PROCESSING` | handler técnico allowlisted | job/schema/version/origem; estado `PENDING_PROCESSING` ou `FAILED` elegível; lease/fence | claim condicionado incrementa attempt/fence | lease expirado pode ser reclaim; executor antigo fica stale |
| inspect | worker técnico mínimo | DB decision/fence e bucket/key relidos | download/info exatos; calcula observed size, storage content type, sniff MIME e SHA-256 | efeito de leitura repetível; resultado só vale no commit fenced |
| technical commit → `AVAILABLE` | RPC DB autoritativa chamada pelo worker | mesmo fence/lease; objeto e Tier B válidos; associação/tenant/Asset ainda válidos e `ACTIVE`; entitlement e autorização corrente do ator original ainda válidos; quota final | persiste cinco fatos, converte hold em accounted bytes, association disponível, Audit/History/Outbox | conditional write; replay retorna resultado, stale falha |
| technical commit → `REJECTED` | mesma boundary | fence atual; MIME/size/integridade ou domínio definitivamente inválido | registra motivo seguro, marca physical delete pending, Audit/History/cleanup outbox | condicional/idempotente |
| erro transiente → `FAILED` | mesma boundary | fence atual e erro classificado retryable | registra categoria segura/attempt; preserva hold e objeto | `asset_files.retry` ou política interna cria novo job/fence; sem duplicar associação |
| delete request → `DELETED` lógico | usuário, `asset_files.delete` | capability corrente; Asset não `DECOMMISSIONED`; política de retenção permite; versão | indisponibiliza leitura, marca physical `DELETE_PENDING`, Audit/History/Outbox | replay idempotente; não chama Storage no request |
| expiry → `EXPIRED` lógico | cleanup técnico | reservation ainda `RESERVED`, expirada, fence atual e delete_not_before atingido | conditional decision, release somente conforme seção 12, physical `DELETE_PENDING` | retry por estado/fence |
| physical delete → `ABSENT` | worker técnico mínimo | decisão DB prévia, fence e key exata relida | remove objeto exato; confirma ausência; persiste resultado/reconciliation | objeto já ausente é sucesso; falha fica `DELETE_FAILED` |

Finalize não aceita tenant/key/parent como autoridade do payload. A entrada
pública usa reservation ID opaco + expected version/idempotency; todos os fatos
são relidos. `PENDING_PROCESSING` é a única associação anterior a `AVAILABLE` e
serve para UI de processamento/falha; não permite download nem uso como
evidência válida.

## 11. Races e fencing Storage

Regra universal:

`DB decision → novo version/fence → conditional transition → operação física
exata → confirmação DB/reconciliation`.

- **Finalize × cleanup:** ambos lockam/condicionam a mesma reservation. Se
  finalize vence, cleanup não pode expirar; se cleanup vence, finalize falha.
- **Cleanup × capability ainda utilizável:** nenhum delete/release final ocorre
  antes de `capability_not_after + safety_skew`. Após a janela, delete exato e
  confirmação de ausência são idempotentes; reconciliation detecta upload
  tardio/orphan. Expiração DB sozinha nunca autoriza delete cego.
- **Processing × cleanup:** claim `PROCESSING` possui lease/fence. Cleanup não
  apaga durante lease válido; após reclaim/decisão condicional incrementa fence,
  e worker antigo não persiste resultado.
- **Parent muda durante inspeção:** technical commit relê Asset, association,
  tenant, lifecycle e autorização. Asset inativo/baixado, associação alterada ou
  fence diferente impede `AVAILABLE` e encaminha rejeição/cleanup conforme a
  causa.
- **Efeito físico e falha antes da persistência:** inspect é repetível; delete
  permanece `DELETE_PENDING/DELETE_FAILED` até confirmação. Retry relê estado e
  não presume resultado.
- **Evento duplicado/retry:** identity do job, unique e conditional transition
  produzem no máximo um efeito lógico. Attempts adicionais são observáveis.
- **Objeto já ausente:** delete é sucesso idempotente e confirma `ABSENT`.
- **Stale worker:** lease token/fence precisa coincidir no UPDATE final; zero
  rows updated é conflito stale, nunca sucesso/`AVAILABLE`.

## 12. Quota concorrente e reconciliation

Fonte autoritativa é uma conta por tenant, bloqueada na mesma transação de
reserve/finalize/commit/delete. Contadores distintos:

- `reserved_bytes`: holds de reservations ainda sem tamanho observado;
- `physical_pending_bytes`: bytes observados presentes ainda não `AVAILABLE`;
- `accounted_bytes`: bytes `AVAILABLE`/retidos faturáveis;
- `physical_observed_bytes`: medição reconciliada do Storage, usada para detectar
  drift e nunca aceita do cliente.

Reserve recebe tamanho máximo pretendido apenas para criar hold conservador;
declared size não é fato final. Sob row lock/fence, aceita somente se
`reserved + physical_pending + accounted + requested_hold <= tenant_limit` e o
limite por classe permitir. Finalize/inspeção substitui hold por observed bytes
atomicamente. Se observado exceder hold/limite/quota, o arquivo é rejeitado, mas
seus bytes permanecem em `physical_pending_bytes` até ausência física confirmada.
Reject/delete/expire só liberam uso físico após confirmação `ABSENT` e após a
janela da capability; AVAILABLE logicamente removido continua contabilizado se
a política exigir retenção física.

Duas reservas concorrentes serializam na conta tenant; check-then-act sem lock é
proibido. Reconciliation compara ledger DB com info/listagem técnica allowlisted,
registra drift e corrige somente por command técnico fenced/auditável; não cria
associação a orphan nem confia em filename/path. Tenant sem quota operacional
configurada recebe erro de configuração, não “ilimitado” implícito.

Os valores 1 MiB do bucket experimental, 10 MiB imagem, 25 MiB documento e
1 GiB tenant **não** são política comercial W5. Limites reais são configuração
server-side/plataforma e ficam fora do Perfil tenant; fixtures de teste podem
usar números próprios claramente não produtivos.

## 13. Autoridade técnica e isolamento tenant

O protocolo testado observou
`SERVICE_ROLE_STORAGE_API_AFTER_DB_DECISION` e exigiu `service_role` localmente.
O contrato é:

`RPC/DB autoritativa → decisão/fence → operação física mínima server-side →
confirmação técnica condicionada`.

`service_role` não decide permission, tenant, quota, parent ou estado; não recebe
autoridade do payload, não vai ao frontend, não é persistida e não aparece em
logs. O handler é allowlisted/versionado, possui capability técnica fixa, deriva
origem/tenant/bucket/key do banco, valida schema/version e executa somente a
operação física exata. Credencial futura mais estreita pode substituí-la após
prova equivalente; este freeze não afirma que `service_role` é a única opção
para sempre.

Como a key não contém tenant, isolamento é inteiramente DB/contextual:

- reserve/finalize derivam tenant do principal/contexto e conferem Asset;
- signed read exige `asset_files.read`, association `AVAILABLE` e tenant atual;
- association possui FKs tenant-aware;
- worker/cleanup/delete relêem tenant e objeto a partir da origem DB;
- payload de evento contém somente IDs/schema/version/correlation mínimos e não
  escolhe livremente tenant, bucket ou key;
- mismatch ou origem ausente falha fechado, sem fallback por path.

## 14. Associação Asset-file e lifecycle do parent

Upload físico não cria associação. Finalize válido cria exatamente uma
associação pendente tenant-aware entre reservation/file e Asset; unique e
idempotência impedem duplicação. A mesma linha muda para `AVAILABLE` somente no
technical commit Tier B. Associação pendente pode aparecer ao autor/leitores
autorizados com estado seguro, sem signed read.

Se Asset ficar `INACTIVE` após finalize e antes do commit, o commit não promove
`AVAILABLE`; registra resultado e cleanup. Asset inativo mantém arquivos já
`AVAILABLE` legíveis, mas não aceita reserve/finalize/retry novo. Asset
`DECOMMISSIONED` preserva arquivos já disponíveis e todo prontuário conforme
retenção, sem nova associação, retry, alteração de condição ou delete ordinário.
Condição operacional, isoladamente, não remove arquivo.

`asset_files.delete` é remoção controlada, não hard delete direto. Nenhum arquivo
do prontuário é fisicamente apagado por fluxo normal sem política explícita de
retenção, decisão DB, Audit e cleanup técnico. W5 não antecipa documentos de
Supplier, Request, OS ou outros parents.

## 15. Cleanup, orphans e observabilidade

São candidatos: reservation expirada, upload sem finalize, orphan detectado,
rejected, failed terminal, delete aprovado e objeto ausente/divergente. Cleanup
sempre usa decisão/fence DB, espera a janela potencial da capability, opera
bucket/key exatos, confirma e reconcilia. Nunca lista um prefixo e apaga em massa,
nunca deriva tenant do path e nunca apaga objeto `AVAILABLE`/`PROCESSING` com
fence diferente.

Orphan físico sem origem válida é colocado em quarentena lógica/telemetria e só
é removido por boundary técnica allowlisted após prova de ownership do bucket,
janela segura e decisão auditável. Failed processing preserva causa segura,
attempts e possibilidade de retry; rejeição de integridade não expõe bytes.

Métricas mínimas: reservations abertas/expiradas, bytes nos três contadores,
drift, jobs por estado/attempt, latência, rejeições por categoria, cleanup
pending/failed e stale-fence conflicts. Logs usam correlation IDs, nunca token,
signed URL, service role, SHA completo desnecessário, bytes ou payload pessoal.

## 16. Audit, History e Outbox

Conceitos permanecem separados:

- Audit: command/autoridade/target/fato técnico sensível, append-only;
- History: evento compreensível do prontuário do Asset;
- Outbox: trabalho assíncrono allowlisted/versionado;
- observabilidade: attempts, métricas e falhas técnicas sem virar History.

Devem ser rastreáveis: create/update/move/status do Asset; revisão de spec;
reservation; finalize; associação pendente; resultado de integridade;
`AVAILABLE`; rejection/failure/retry; decisão e confirmação de cleanup/delete.
Efeitos exigidos pelo command são atômicos com a mudança. Token, capability,
signed URL, key exposta, credencial/service role ou secret nunca entram em
Audit/History/Outbox/logs. AUD-01 permanece íntegro.

## 17. Reads, UI e MediaManager

Reads são paginados, ordenados, anti-enumeração e com projeção mínima. Signed
read é emitido sob autorização corrente para um único arquivo `AVAILABLE`, com
prazo curto, e nunca salvo em cache persistente. Query keys seguem UI-01 com
principal/contexto/tenant/resource/filtros/projeção.

W5E entrega:

- lista, filtros e detalhe/prontuário de Asset;
- create/edit/move/lifecycle conforme capabilities distintas;
- hierarquia, Local, Centro de Custo, status, condição e specifications;
- fotos/documentos com upload mobile, progresso, processing, failure, retry,
  preview/lightbox/download quando permitido;
- loading, vazio, erro, sem permissão, inexistente, offline/conexão indisponível,
  sucesso e falha;
- foco, teclado, labels, contraste, mensagens não baseadas só em cor e alvos
  touch adequados.

MediaManager é boundary reutilizável de contratos/estados/capabilities, sem
Perfil hardcoded e sem acesso direto a Storage. Asset é seu único consumidor
funcional na W5; não há fake CRUD nem UI de consumers futuros.

## 18. Subwaves e gates

### W5A — Contract / Authorization

**IN:** 19 permissions/códigos, baselines e rollout; state vocabularies; meta-
schema spec v1; contratos de commands/reads/erros/eventos; nomes de tabelas,
identificadores, fences e interface W5B–W5C–W5D. **OUT:** tabelas de domínio,
bucket, bytes e UI. **Migration esperada:** catálogo/rollout forward-only.
**Tests:** AUTH-01, contagem/códigos, baselines/delegação, Custom Profiles,
overrides e replay. **Gate:** `W5A_CONTRACT_READY` somente com as 19 combinações,
contratos compartilhados e ownership de migrations congelados.

### W5B — Asset Domain / Hierarchy

**IN:** tabelas Asset Type/revisões/Asset/identifier registry/allocator; commands
create/update type, create/update/move/lifecycle Asset; list/get/lookup; RLS,
idempotência, Audit/History/Outbox. **OUT:** Storage, associação e UI final.
**Migrations:** domínio Asset forward-only. **Tests:** tenant/RLS/permissions,
allocator, alias, specs, estado, hierarchy/depth e multi-session races.
**Gate:** `W5B_ASSET_DOMAIN_READY` somente com DEC-05 e matriz Asset aprovadas.

### W5C — Storage Foundation

**IN:** bucket/config, reservations, objeto/metadata/lifecycle/fence, quota,
private primitives, outbox/worker boundary, cleanup/reconciliation e autoridade
técnica. Nenhum endpoint autenticado pode usar primitive técnica diretamente.
**OUT:** FK/associação Asset e UI. **Migrations/config:** foundation forward-only;
não altera nem incorpora o spike. **Tests:** Storage/RLS/grants, quota e races
fundacionais. **Gate:** `W5C_STORAGE_FOUNDATION_READY` somente com DEC-06/07,
TECH-01, lifecycle e deletion protocol aprovados.

### W5D — Asset Files Vertical

**IN:** wrappers públicos Asset-aware de reserve/finalize/read/delete/retry,
association pendente, Tier B, signed read, parent lifecycle e efeitos W3.
**Migrations:** associação/FKs e integração forward-only. **Frontend:** gateway e
boundary de dados, sem consumer adicional. **Tests:** fluxo completo e matriz
Storage abaixo. **Gate:** `W5D_ASSET_FILES_READY` exige previamente W5B e W5C
aprovadas e integração sem payload authority.

### W5E — Asset Experience / Integrated Hardening

**IN:** telas/rotas/forms/prontuário/hierarquia, MediaManager Asset, mobile/a11y,
cache, estados, E2E, observabilidade e regressão W1–W4. **Migrations:** nenhuma
por conveniência de UI; qualquer fato faltante retorna à wave dona. **Gate:**
`W5E_INTEGRATED_READY`; só então avaliar `ASSET_READY` e
`STORAGE_FOUNDATION_READY`.

### Matriz executável por subwave

| Wave | Commands / reads | Auth, RLS e invariantes | Frontend | Acceptance/gate objetivo |
| --- | --- | --- | --- | --- |
| W5A | nenhum command/read de domínio; somente rollout privado | 19 códigos exatos, baselines, delegação, overrides e grants mínimos | tipos/contratos apenas, sem rota | migration replay-safe + testes de catálogo/rollout verdes = `W5A_CONTRACT_READY` |
| W5B | todos os commands/reads Asset Type e Asset da seção 7.3 | tenant FKs, forced RLS, AUTH-02, registry/allocator/spec snapshots, hierarchy lock/depth/state | gateway/contratos; nenhum CRUD final obrigatório | migration/reset e pgTAP + multi-session Asset verdes = `W5B_ASSET_DOMAIN_READY` |
| W5C | primitives privadas de reserve/finalize técnico, claim/commit/cleanup/reconcile; nenhum read público | nenhuma execução por authenticated; tenant facts DB, quota lock, fences, TECH-01 e grants mínimos | nenhum consumer/UI | provider local + pgTAP + multi-session da foundation verdes = `W5C_STORAGE_FOUNDATION_READY` |
| W5D | commands Asset File e read contextual da seção 7.3 | reauth, parent/association tenant-aware, Tier B, quota, lifecycle, stale fence e retenção | gateway/MediaManager data boundary de Asset | vertical PNG/JPEG/PDF e matriz Storage de integração verdes = `W5D_ASSET_FILES_READY` |
| W5E | somente gateways já aprovados; nenhuma authority de UI | nenhuma policy/command relaxada por UX; cache tenant-aware | rotas/telas/forms/prontuário/MediaManager/mobile/a11y | unit/E2E/adversarial/regressão W1–W4 verdes = `W5E_INTEGRATED_READY` |

As migrations esperadas são, respectivamente: autorização/rollout; domínio
Asset; foundation Storage; integração Asset-file; nenhuma migration de
conveniência na experiência. Mudança desse ownership bloqueia o gate e exige
ratificação documental.

### Ordem e paralelização

`W5A → (W5B || W5C) → W5D → W5E`.

W5B e W5C são paralelizáveis somente após W5A congelar IDs, classes, estados,
contracts, erros, schema/version de eventos e ownership de migrations. W5C não
possui FK para Asset nem endpoint público funcional; W5B não cria Storage. W5D
é o único ponto de integração e não inicia antes dos dois gates. Qualquer
contrato compartilhado descoberto depois de W5A bloqueia ambos até ratificação;
não é duplicado em paralelo.

Cada gate exige migration forward-only de sua wave, grants/RLS mínimos, revisão
de secrets, testes positivos/negativos/cross-tenant, concorrência real quando
aplicável, diff/documentação e zero regressão comprovada. Este freeze não
autoriza nenhuma subwave sem mandato específico.

## 19. Matriz obrigatória de testes Asset

W5B/W5E devem cobrir, sem criar os testes neste freeze:

- tenant isolation, forged tenant/UUID, permissions exatas e RLS por operação;
- allocator concurrent create, unique e replay idempotente sem novo número;
- alias normalization/collision; código × alias × legacy alias sem ambiguidade;
- self-cycle, ciclo indireto e `A↔B` multi-session;
- move × move, move × create child e parent lifecycle races;
- depth 32 aceita, 33 negada e move de subárvore validado;
- registration transitions e terminal decommission;
- condição operacional independente/congelada após baixa;
- spec tipos/required/null/unknown/constraints e server-side rejection;
- nova revisão não invalida Asset existente; adoção/type change explícitos;
- stale `expected_version` e idempotency fingerprint conflict;
- Requester recebe somente projeção mínima;
- Audit/History/Outbox atômicos, append-only e sem segredo.

## 20. Matriz obrigatória de testes Storage

W5C/W5D/W5E devem cobrir:

- bucket privado/public denial, forged key e cross-tenant em reserve, finalize,
  read, association, processing e cleanup;
- permission loss após capability, capability física possivelmente aceita e
  finalize/technical commit reautorizados;
- capability/token/URL/service role ausentes de persistência e logs;
- no-upsert e objeto exato;
- MIME spoof aceito fisicamente mas rejeitado por Tier B;
- sniff PNG/JPEG/PDF, storage content type separado, SHA e observed size;
- AVAILABLE somente após cinco fatos e fence corrente;
- quota de duas reservas/uploads concorrentes, observed > declared/hold e
  reconciliation/drift;
- finalize × cleanup e processing × cleanup multi-session;
- parent mudando/inativando/baixando durante inspeção;
- stale worker, lease expiry, duplicate event e retry idempotente;
- falha após efeito físico, objeto ausente e technical delete idempotente;
- reservation expirada, uploaded orphan, failed/rejected processing e janela da
  capability;
- associação pendente versus disponível e retenção em parent inativo/baixado;
- signed read contextual e nenhum acesso por path/key.

Mocks não provam RLS, provider Storage, concorrência ou autoridade técnica.

## 21. Evidência: PROVEN, DECIDED e DEFERRED

### PROVEN BY LOCAL SPIKE

Bucket privado compartilhado; public denial; key/objeto exatos; no-upsert;
emissão autorizada/negada; forged/cross-tenant denial do harness; upload sem
sessão; token pós-perda de permission aceito fisicamente; finalize revogado
negado; signed read; info/tamanho; MIME declarado versus registrado; spoof
fisicamente aceito e rejeitável por bytes; sniff PNG/JPEG/PDF; SHA-256;
delete técnico e ausência idempotente; race limitada cleanup/finalize do spike;
ausência de capability nos locais inspecionados; teardown/repetibilidade.

Observações: `signed_upload_ttl_documented=2h`,
`technical_authority_observed=SERVICE_ROLE_STORAGE_API_AFTER_DB_DECISION`,
`service_role_required=YES` no protocolo local,
`token_after_permission_loss=ACCEPTED` e
`spoof_storage_behavior=ACCEPTED_PHYSICALLY_VERIFICATION_REJECTED`.

### ARCHITECTURAL DECISION

DEC-05 deste documento; bucket/key/classes W5; lifecycle/fences; association
pendente somente após finalize; Tier B antes de AVAILABLE; quota/cleanup
transacionais; protocols DB-first; matriz de 19 permissions; service-role
boundary técnica substituível por credencial mais estreita provada.

### DEFERRED / NOT PROVEN

Comportamento remoto, expiração efetiva exatamente em 2h, revogação física de
capability, escala/throughput, números comerciais, provider/worker final,
credencial futura mais estreita, antimalware, retenção legal, migração V1 e
consumers W6+. Evidência local não vira garantia remota.

## 22. Decisões finais e Definition of Done

### DEC-05 — FINAL

Asset é estrutural; Equipment é Asset Type; Local e Centro de Custo são
independentes; UUID/código/registry/allocator são inequívocos; hierarquia usa
lock tenant estável, rows canônicas, cycle/depth 32 e lifecycle revalidado;
specifications usam revisão imutável sem invalidade retroativa.

### DEC-06 — FINAL

Bucket `cw-private-files`; key `v1/<object_uuid>`; duas classes Asset; private/no
upsert; capability exata não é autorização corrente; finalize reautoriza;
isolamento vem do DB, nunca do path; lifecycle e cleanup são fenced.

### DEC-07 — FINAL

Tier B separa declared MIME, provider content type, verified MIME, observed size
e SHA-256; AVAILABLE só após inspeção real e technical commit condicionado.

`ASSET_READY=YES` exige W5A, W5B, W5D e W5E, matriz Asset verde, UX completa e
zero regressão W1–W4. `STORAGE_FOUNDATION_READY=YES` exige W5C, W5D e W5E,
matriz Storage verde, quota/reconciliation/cleanup/observabilidade e testes do
provider alvo. Nenhum gate local implica produção, deploy ou migração V1.

Checklist final de scope: Supplier W6, Requests, OS, Preventiva, QR, import,
garantia avançada, consumers arbitrários, antimalware obrigatório, migração
real e W14 permanecem ausentes. `W6_PLUS_SCOPE_LEAK = NO`.
