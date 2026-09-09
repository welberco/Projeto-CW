# Rehearsal, Reconciliação, Cutover e Recovery V1 → V2 — Etapa 10D

| Campo | Valor |
| --- | --- |
| Projeto | CW ERP / CW Manutenção |
| Etapa | Fase A — Etapa 10D |
| Natureza | Runbook técnico conceitual e contratos operacionais |
| Origem | V1 preservada e snapshots futuros autorizados |
| Destino | CW ERP V2 conforme arquitetura congelada |
| Estado | Especificação para implementação, rehearsal e operação posteriores |
| Execução nesta etapa | Somente documentação; nenhuma migração, rehearsal, carga, acesso remoto, backup, restore, deploy ou cutover foi executado |

## 1. Objetivo

Definir um procedimento operacional repetível, idempotente, observável, auditável, reconciliável, interrompível e recuperável para a futura migração V1 → V2.

O fluxo controlado é:

```text
PREPARE
→ SNAPSHOT
→ MAP
→ LOAD BASE
→ RECONCILE BASE
→ REHEARSE
→ PRE-CUTOVER
→ FREEZE
→ DELTA CAPTURE
→ DELTA LOAD
→ FINAL RECONCILIATION
→ GO/NO-GO
→ CUTOVER
→ POST-CUTOVER VERIFY
→ STABILIZE
→ LEGACY RETENTION
```

Em qualquer ponto aplicável, o runbook deve permitir:

```text
ABORT | RECOVER | ROLL FORWARD | RETURN TO V1
```

O documento define contratos e evidências para execução futura. Ele não declara a V2 pronta para produção e não substitui implementação, teste, aprovação humana ou revalidação do estado remoto.

## 2. Escopo

Incluído:

- identidade, estado e imutabilidade de cada Migration Run;
- manifesto dos artefatos promovidos;
- contratos P0 a P15, checkpoints e evidence bundles;
- snapshots coordenados de Database, Auth e Storage;
- Consistency Envelope e source drift;
- aplicação das regras versionadas 10B/10C, registry e quarantine;
- carga base e delta idempotentes;
- reconciliação L1 Count, L2 Relationship, L3 Semantic e L4 Security/Access;
- rehearsals progressivos, medição e critérios objetivos;
- freeze de todos os writers, delta e cálculo final de `safe_next`;
- GO/NO-GO, waivers permitidos e separação de funções;
- cutover com single writer e ponto explícito de não retorno simples;
- recovery R0 a R4, Return to V1 e Roll Forward;
- verificação pós-cutover, observabilidade, estabilização e piloto Serena;
- retenção da V1 e insumos da Etapa 10E.

Fora do escopo e não executado nesta etapa:

- acesso a Supabase, PostgreSQL, Auth, Storage, GitHub/API, produção ou Edge Functions remotos;
- DDL, SQL, migrations, ETL, RPCs, RLS, policies, workers, buckets, fixtures ou usuários;
- download/cópia de objetos, captura real de snapshot, backup ou restore;
- deploy, ativação, cutover, alteração de Auth ou teste remoto;
- definição arbitrária de duração, tolerância percentual, volume, provider ou topologia física;
- dual-write, ETL bidirecional ou descarte físico de dados.

## 3. Fontes e precedência

Fontes aplicadas, nesta ordem:

1. `PRODUCT_SPEC.md` — autoridade funcional e de escopo;
2. `docs/ARQUITETURA-TECNICA-V2.md` — decisões técnicas `CLOSED`;
3. `docs/MIGRACAO-V1-V2-10A-ESTRATEGIA.md` — estratégia aprovada;
4. `docs/MIGRACAO-V1-V2-10B-MAPEAMENTO.md` — mappings aprovados;
5. `docs/MIGRACAO-V1-V2-10C-CRITICOS.md` — contratos críticos aprovados;
6. `docs/INVENTARIO-V1.md` — estado legado conhecido no repositório;
7. `docs/GAP-ANALYSIS-V1-V2.md` — apoio comparativo;
8. `AGENTS.md` — governança do trabalho.

Precedência operacional:

```text
PRODUCT_SPEC
> ARQUITETURA-TECNICA-V2
> 10A
> 10B
> 10C
> INVENTARIO-V1
> GAP
```

As decisões `CLOSED` não são reabertas. Os SQLs e o código V1 são evidência local, não prova do estado remoto. Toda conclusão dependente de ambiente, dados, provider ou configuração remota é `REVALIDATION_REQUIRED`.

## 4. Princípios

### 4.1 Definição de sucesso

```text
Migration success
!= processo terminou sem erro
!= LOAD concluído
!= counts globais iguais
```

Sucesso exige simultaneamente:

- integridade estrutural e referencial tenant-aware;
- identidade, membership e lifecycle reconciliados;
- autorização reconciliada sem expansão indevida;
- relações, semântica, códigos e counters reconciliados;
- Operational History, Migration Provenance e Audit técnico distintos e completos;
- Storage reconciliado entre metadado, objeto, parent, tenant, integridade e disponibilidade;
- testes de segurança, Auth e fluxos funcionais aprovados;
- backup e recovery demonstrados;
- gates técnicos, operacionais e de negócio formalmente aprovados.

`LOAD` nunca implica `ACTIVATE`.

### 4.2 Invariantes operacionais

1. O mesmo artefato validado é promovido; alteração de qualquer digest exige nova validação.
2. Um run finalizado ou abortado não é reescrito para aparentar outro resultado.
3. Toda transformação crítica produz registry/provenance e Audit técnico quando exigido.
4. Falha no Audit obrigatório impede confirmar a operação crítica correspondente.
5. Retry não duplica tenant, identity, membership, grant, Request, OS, evento, arquivo, associação ou código.
6. Nenhum registro recebe fallback genérico para enum, tenant, ator, scope, relação ou classificação desconhecida.
7. Nenhum ator humano é fabricado; `LEGACY_ACTOR`, `UNRESOLVED_ACTOR` e `TECHNICAL_ACTOR` preservam a realidade observável.
8. Códigos já emitidos não são renumerados nem reutilizados; gaps são aceitáveis.
9. Snapshot de Database não substitui snapshots de Auth e Storage.
10. Freeze de UI não prova freeze de todos os writers.
11. Delta deve observar inserts, updates e deletes relevantes; timestamp só é usado quando confiável.
12. Após ativação, há um único writer operacional por domínio, salvo estratégia formal futura de dual-write.
13. Restore de Database não resolve Auth, Storage nem efeitos externos.
14. Serena é tenant piloto em produção, não ambiente nem fork arquitetural.
15. NO-GO é um resultado válido e seguro do processo.

### 4.3 Classificação de criticidade e tolerância

| Classe | Regra de aceite |
| --- | --- |
| `CRITICAL` | Zero perda, inconsistência, exposição, expansão de privilégio, código reutilizável ou evidência crítica não verificada |
| `HIGH` | Toda exceção exige classificação, evidência e aprovação explícita; não há tolerância implícita |
| `NORMAL` | Quarantine não bloqueante pode ser aceita apenas fora do fluxo operacional e com owner/resolução |
| `LEGACY_NON_OPERATIONAL` | Pode permanecer `LEGACY_ONLY` conforme retenção e aprovação, sem capacidade operacional |

Não existe tolerância genérica como “99% migrado”. A tolerância é por regra, domínio, severidade e impacto, com evidência por registro ou categoria controlada.

## 5. Migration Run

### 5.1 Unidade operacional

Migration Run é a unidade imutavelmente identificável que agrupa artefato, fonte, regras, execução, evidência, decisão e resultado.

Campos conceituais mínimos:

| Grupo | Campos |
| --- | --- |
| Identidade | `migration_run_id`, `release_id`, `environment`, `wave`, `attempt`, `correlation_id` |
| Fonte | `source_snapshot_id`, `source_cutoff`, Consistency Envelope, source release/database identity |
| Regras | `mapping_rule_set_version`, schema/migration version, config schema/version |
| Artefatos | commit SHA, digests de migrations/ETL/workers/config, runtime/tool versions |
| Execução | `started_at`, `finished_at`, `technical_actor`, status e checkpoints |
| Controle | owners, reviewers, approvers, approvals, exceptions e waivers permitidos |
| Resultado | reconciliation result L1–L4, Auth, permissions, codes, history, Storage e final status |

Não se fecha schema físico nesta etapa.

### 5.2 Estados e transições

Estados candidatos:

```text
PLANNED
→ PREPARING
→ RUNNING
→ RECONCILING
→ READY_FOR_REVIEW
→ APPROVED
→ COMPLETED
```

Saídas alternativas controladas:

```text
PREPARING/RUNNING/RECONCILING
├→ FAILED
├→ QUARANTINED
└→ ABORTED

READY_FOR_REVIEW
├→ APPROVED
└→ REJECTED
```

`FAILED`, `QUARANTINED`, `REJECTED` e `ABORTED` preservam evidence bundle e não são apagados. `COMPLETED` só é permitido depois do checkpoint aplicável e da reconciliação prevista para o tipo de run.

### 5.3 Retry e checkpoints

- Retry usa novo `attempt`/run ou uma continuação explicitamente checkpointed pelo contrato implementado.
- Continuação só reutiliza resultados cuja identidade, digest, pós-condição e idempotência tenham sido provados.
- Um checkpoint não é inferido de logs; precisa de registro imutável e evidence bundle.
- Alteração de snapshot, rule set, schema, artefato ou resolução de quarantine cria nova identidade de tentativa apropriada.
- Resultado anterior permanece consultável para comparação e auditoria.

## 6. Artefatos

### 6.1 Migration Artifact Manifest

O conjunto executável futuro deve possuir um manifesto selado com:

- release ID e commit SHA;
- scripts de migration e seus digests;
- scripts ETL/mappers/loaders e seus digests;
- mapping rules e versão;
- schema/migration version;
- Functions/workers/handlers relevantes e versões;
- schema e versão de configuração;
- identidade da configuração pública autorizada, sem secrets;
- versões de runtime e ferramentas;
- checksums dos artefatos;
- identidade do source snapshot e do Consistency Envelope;
- matriz de compatibilidade entre aplicação, schema e ferramentas;
- data, technical owner e assinatura/aprovação do manifesto.

### 6.2 Promoção e imutabilidade

```text
LOCAL
→ TEST descartável/local/CI
→ STAGING compartilhado persistente
→ declaração de RC
→ PRODUCTION
```

- Migration pode ser ajustada em LOCAL/TEST descartável antes da publicação.
- Ao alcançar STAGING ou outro ambiente compartilhado persistente, torna-se imutável.
- RC é declaração sobre artefatos já validados em STAGING; não é rebuild.
- Rehearsal final e cutover usam os mesmos digests, regras, ordem, gates e runbook.
- Mudança de artefato após rehearsal invalida a aprovação afetada e exige novo run proporcional ao impacto.
- Configuração externa pode variar por ambiente, mas sua identidade, schema e valores públicos autorizados entram na evidência.

## 7. Ambientes

| Ambiente | Papel | Dados | Regra operacional |
| --- | --- | --- | --- |
| LOCAL | Desenvolvimento por PC | Sintéticos locais | Não prova promoção nem estado compartilhado |
| TEST | Descartável local/CI | Fixtures determinísticas | Reconstruído por migrations; exercita forward/retry |
| STAGING | Remoto persistente separado e prod-like | Sintéticos ou anonimizados aprovados | Fronteira de imutabilidade e validação da RC |
| PRODUCTION | Remoto persistente real | Dados reais autorizados | Recebe a mesma cadeia publicada após GO |
| Serena | Tenant piloto em PRODUCTION | Dados do tenant conforme escopo aprovado | Não é ambiente; usa mesmo release, schema, RLS e workers |

Produção nunca é usada como rehearsal. Dados reais não são copiados indiscriminadamente. Secrets e credenciais são específicos por ambiente, mínimos, válidos e não aparecem nos evidence bundles.

## 8. Fases

| Fase | Nome | Resultado necessário | Checkpoint principal |
| --- | --- | --- | --- |
| P0 | PREPARE | Prerrequisitos, owners, ferramentas, controles e artefatos prontos | CP0 |
| P1 | SNAPSHOT | Snapshots selados sob um Consistency Envelope | CP1 |
| P2 | MAP | Toda origem elegível recebe classificação reconciliável | Evidência do run |
| P3 | LOAD BASE | Base carregada idempotentemente, ainda não ativada | CP2 |
| P4 | RECONCILE BASE | L1–L4 e domínios críticos fechados para rehearsal | CP3 |
| P5 | REHEARSAL | Processo e recovery demonstrados em ambiente seguro | CP4 |
| P6 | PRE-CUTOVER | RC, pessoas, janela, backups e gates prontos | Pré-condição CP5 |
| P7 | FREEZE | Todos os writers relevantes parados/controlados | CP5 |
| P8 | DELTA CAPTURE | Mudanças desde o snapshot capturadas e seladas | Evidência CP6 |
| P9 | DELTA LOAD | Delta mapeado, carregado e reconciliado | CP6 |
| P10 | FINAL RECONCILIATION | Reconciliação final imutável e target saudável | CP6 |
| P11 | GO/NO-GO | Decisão formal, rastreável e completa | CP7 em GO |
| P12 | CUTOVER | V2 ativada como single writer | CP8 |
| P13 | POST-CUTOVER VERIFY | Smoke e segurança aprovados | CP9 |
| P14 | STABILIZATION | Operação aceita sob observação reforçada | CP10 |
| P15 | LEGACY RETENTION | V1 preservada no estado aprovado | Evidência de retenção |

Cada fase deve registrar Inputs, Actions, Outputs, Preconditions, Postconditions, Evidence, Metrics, Failure behavior, Recovery path, Owner/approval class e Next gate. Os contratos detalhados a seguir são normativos para o futuro runbook executável.

## 9. Prepare — P0

| Campo | Contrato |
| --- | --- |
| Inputs | Arquitetura congelada; 10A/10B/10C aprovadas; backlog de blockers; release candidate futura |
| Actions futuras | Confirmar implementação do target schema, migrations, registry, quarantine, Audit, tooling, mappings, RLS/FKs, Storage protocol, observabilidade, backups, kill switches, credentials e runbooks |
| Outputs | Readiness inventory, RACI, manifests candidatos, lista de writers, gates e blockers atualizados |
| Preconditions | Escopo/tenants/ondas definidos; owners nomeados; ambientes autorizados |
| Postconditions | Todos os pré-requisitos possuem evidência `READY`, ou permanecem blocker explícito; nada é presumido implementado por estar documentado |
| Evidence | Versões/digests, testes, aprovações, restore rehearsal, matriz de writers e source drift baseline |
| Metrics | Prerrequisitos total/ready/blocked; blockers por classe; cobertura de owners e gates |
| Failure behavior | Não iniciar snapshot/carga; preservar diagnóstico; classificar blocker |
| Recovery path | Corrigir por artefato versionado, executar testes e iniciar novo attempt/review |
| Owner/approval | Migration Lead executa; Security/Data/Platform/Operations revisam; approver de release aceita |
| Next gate | CP0 — source e target prerequisites validados |

Pré-requisitos obrigatórios, sem pressupor implementação atual:

- target schema implementado e validado futuramente;
- migrations publicadas conforme lifecycle;
- registry/provenance e quarantine implementados;
- Audit técnico append-only implementado e failure contract testado;
- migration tooling e mapping rules versionados;
- target RLS, grants, functions e FKs tenant-aware implementados/testados;
- Storage migration/finalize e integrity tiers implementados;
- backups e restore comprovados;
- observabilidade, correlation e dashboards disponíveis;
- kill switches e modo read-only testados;
- secrets/configs/credentials preparados com menor privilégio;
- recovery decision tree, comunicação e separação de funções aprovados.

## 10. Snapshot — P1

| Campo | Contrato |
| --- | --- |
| Inputs | CP0, source inventory, writer map, artifact manifest e regra de cutoff |
| Actions futuras | Capturar Database, Auth e Storage de forma autorizada/read-only; registrar boundaries; calcular counts/hashes; selar manifestos |
| Outputs | `source_snapshot_id`, manifests DB/Auth/Storage e Consistency Envelope |
| Preconditions | Captura testada; espaço/retention disponíveis; permissões read-only; source drift não crítico |
| Postconditions | Fontes identificadas, cutoffs relacionados e integridade de cada manifest verificada |
| Evidence | IDs, fingerprints, counts/hashes, timestamps, known writers, cutoffs, operator e digests |
| Metrics | Duração por fonte, registros/objetos/bytes, divergências, cobertura e lag entre boundaries |
| Failure behavior | Invalidar snapshot incompleto; não combinar partes de tentativas diferentes sem contrato explícito |
| Recovery path | Repetir captura em novo attempt e novo Consistency Envelope; manter evidência da falha |
| Owner/approval | Data/Platform executam; Security revisa minimização Auth; Migration Lead sela |
| Next gate | CP1 — snapshot e envelope selados |

### 10.1 Identidade do snapshot

O snapshot lógico consistente deve identificar:

- `snapshot_id` e `captured_at`;
- source database/project identity e schema fingerprint;
- application release da V1;
- data cutoff/transaction boundary;
- Auth snapshot identity e boundary administrativa;
- Storage manifest identity e object cutoff;
- counts/hashes por tenant/domínio;
- known writers e estado de cada um;
- base/delta boundary;
- ferramenta/versão, technical actor e correlação.

### 10.2 Snapshot de Database

Inventariar futuramente, sem escrever na origem:

- schemas, tables, views e materialized views;
- columns, enums/status values, constraints, FKs e indexes;
- triggers, functions/RPCs, owners, `SECURITY DEFINER` e `search_path`;
- grants, PUBLIC EXECUTE e RLS/policies por operação;
- sequences, counters e consumidores;
- counts, hashes, códigos, históricos, relações e dados relevantes;
- watermark/transaction identity utilizável para delta.

O dump, se usado, é apenas um componente. Ele não prova Auth, Storage nem o relacionamento temporal entre as fontes.

### 10.3 Snapshot de Auth

Capturar somente os dados autorizados necessários ao mapping da 10C:

- Auth UUID, e-mail original/normalizado, provider/identities e lifecycle;
- confirmação, disabled/banned e timestamps relevantes;
- referências de aplicação e identidade do snapshot;
- boundary de mudanças administrativas e writers Auth conhecidos.

Não exigir nem transportar password hashes, secrets, tokens ou sessões. Continuidade de senha/sessão só pode ser declarada se oficialmente suportada e ensaiada; caso contrário, o runbook prevê ativação/recuperação sem promessa de sessão transparente.

### 10.4 Snapshot de Storage

Criar manifest separado para:

- bucket e identidade/key do objeto;
- metadata row e parent source;
- tenant candidato e evidência;
- size, MIME declarado/efetivo, timestamps e checksum quando aplicável;
- classificação, uploader/actor e integrity tier;
- object cutoff e estado no lifecycle de migração.

Bytes podem ser copiados separadamente do manifest. O manifest precisa permanecer reconciliável com Database e com o cutoff de uploads.

## 11. Consistency Envelope

### 11.1 Definição

Consistency Envelope é o contrato que relaciona snapshots e boundaries de sistemas distintos que não oferecem necessariamente uma transação distribuída comum.

```text
Consistency Envelope
├── Database snapshot + transaction/data cutoff
├── Auth snapshot + administrative cutoff
├── Storage manifest + object cutoff
├── application release/config identity
├── writer states and known in-flight work
└── delta start/end rules per source
```

Campos conceituais:

- `consistency_envelope_id` e versão;
- IDs/digests de cada snapshot/manifest;
- horário de início/fim de captura com clock source;
- boundary observável de cada fonte;
- writers ativos, parados, desconhecidos ou em trânsito;
- relações pendentes entre DB metadata e Storage bytes;
- alterações Auth potencialmente posteriores ao DB mapping;
- regra de delta por domínio/fonte;
- gaps conhecidos, severidade, owner e resolução;
- condição de validade/expiração do envelope.

### 11.2 Critério de fechamento

O envelope fecha apenas quando:

1. cada fonte possui identidade e integridade próprias;
2. todo intervalo entre cutoffs é coberto por delta ou por freeze comprovado;
3. uploads reservados/em andamento e operações assíncronas foram classificados;
4. alterações Auth administrativas têm boundary/reconciliação próprias;
5. nenhuma relação DB ↔ Storage pode desaparecer entre janelas sem detecção;
6. clocks, timezones e timestamps usados têm confiabilidade documentada;
7. gaps restantes são blockers ou exceções formalmente permitidas.

Um Consistency Envelope inválido ou incompleto é NO-GO para o run correspondente.

## 12. Source Drift

Antes de cada rehearsal relevante e cutover, comparar o remoto autorizado com o inventário e o último snapshot aprovados. Toda verificação remota é futura e `REVALIDATION_REQUIRED`.

Detectar no mínimo:

- novas/removidas tables, columns, constraints, indexes e enum/status values;
- functions, triggers, owners, grants, RLS/policies e `SECURITY DEFINER`;
- Edge Functions, versões, writers, scheduled jobs e integrações;
- buckets, policies, object classes e paths;
- permission names, profiles, bypasses e platform candidates;
- namespaces de código, counters e sequences;
- novos casos órfãos, cross-tenant, duplicados ou semanticamente desconhecidos;
- release/config da aplicação V1 e alterações manuais.

Classificação:

| Drift | Ação |
| --- | --- |
| Crítico para schema, segurança, writer, Auth, código, Storage ou delta | NO-GO até análise, incorporação ao rule set e novo rehearsal proporcional |
| Material, mas fora do escopo operacional aprovado | Classificar, preservar evidência e decidir retenção/waiver se permitido |
| Não material e coberto por regra versionada existente | Registrar no run e demonstrar reconciliação |

Drift nunca é absorvido por fallback genérico.

## 13. Map — P2

| Campo | Contrato |
| --- | --- |
| Inputs | CP1, snapshots/manifests, rules 10B/10C, dicionários, registry e quarantine |
| Actions futuras | Avaliar elegibilidade; resolver tenant, identity, enums, relações, atores, códigos e classificação por rule version |
| Outputs | Mappings bidirecionais, dispositions, quarantine items e métricas por tenant/domínio |
| Preconditions | Rule set congelado; registry/quarantine/Audit disponíveis; nenhuma regra desconhecida com fallback |
| Postconditions | Cada source record elegível possui exatamente uma classe reconciliável e splits/merges têm registry explícito |
| Evidence | Source hash/ID, rule/version, confidence, disposition, reviewer/approver e target candidates |
| Metrics | Source/eligible/mapped/quarantined/legacy/approved discard/failed por tenant e domínio |
| Failure behavior | Não promover o registro; registrar reason code; interromper lote quando a falha comprometer invariant |
| Recovery path | Resolver quarantine ou corrigir rule set versionado; novo attempt preservando fonte original |
| Owner/approval | Data Migration executa; Domain/Data/Security revisam conforme classe |
| Next gate | Entrada autorizada em LOAD BASE; blockers críticos continuam impedindo o lote/onda |

Cada source record elegível recebe exatamente uma classificação operacional:

```text
MAPPED
QUARANTINED
LEGACY_ONLY
APPROVED_DISCARD
FAILED
```

`FAILED` é falha não absorvida; não equivale a quarantine. Splits e merges registram cardinalidade, role e todos os source/target IDs. O mapper não altera a fonte.

## 14. Quarantine

### 14.1 Workflow

```text
OPEN
→ TRIAGED
→ RESOLUTION_PROPOSED
→ APPROVED
→ RESOLVED
```

Saídas alternativas:

```text
OPEN → ACCEPTED_LEGACY_ONLY
OPEN/TRIAGED → BLOCKING
```

Os estados de 10A/10B (`UNDER_REVIEW`, `RESOLVED_MAP`, `RESOLVED_LEGACY_ONLY`, `APPROVED_DISCARD`, `BLOCKED`) devem ser mapeados sem perda para este workflow quando o schema físico for definido; não se reescreve o histórico de status.

### 14.2 Conteúdo obrigatório

Toda resolução registra:

- source system/snapshot/entity/ID/tenant e hash/referência imutável;
- migration run, wave e rule/version;
- reason code, categoria, severidade e impacto;
- evidence, análise e resolução proposta;
- reviewer e approver quando aplicável;
- target/disposition resultante;
- timestamps e correlation;
- efeito na reconciliação e no gate.

A source row não é corrigida silenciosamente. A decisão é acrescentada ao lado da evidência original. Quarantine `BLOCKING` não pode ser omitida por count global correto.

### 14.3 Critérios de resolução

- `RESOLVED/MAPPED`: target e regra inequívocos, invariants válidos e aprovação registrada.
- `ACCEPTED_LEGACY_ONLY`: retenção e acesso não operacional definidos.
- `APPROVED_DISCARD`: somente após decisão de retenção/legal/negócio; nunca por conveniência técnica.
- `BLOCKING`: impacto em segurança, identidade, código, dado/evidência crítica, recovery ou cutover.
- Reabertura cria evento de resolução adicional; não apaga a decisão anterior.

## 15. Load Base — P3

| Campo | Contrato |
| --- | --- |
| Inputs | Mappings aprovados, target schema, artifact manifest, registry, quarantine e technical identity |
| Actions futuras | Carregar por dependência/onda; validar invariants; registrar provenance/Audit; persistir resultado idempotente |
| Outputs | Base target não ativada, load report, registry atualizado e exceptions classificadas |
| Preconditions | Parents/mappings da onda disponíveis; RLS/FKs/commands técnicos testados; rollback transacional/lote definido |
| Postconditions | Cada item do lote tem target idempotente ou disposition explícita; target satisfaz tenant/FK/domain invariants |
| Evidence | Counts, source/target IDs, operation/result, digests, transactions, Audit/correlation e error report |
| Metrics | Rows attempted/loaded/skipped idempotent/quarantined/failed, throughput, retries e duração |
| Failure behavior | Rollback do boundary seguro; impedir avanço do lote; preservar partial-state evidence |
| Recovery path | Retomar de checkpoint comprovado ou executar novo attempt; nunca truncar evidência para repetir |
| Owner/approval | Migration Operator executa; Data owner revisa; Security participa de ondas críticas |
| Next gate | CP2 — base carregada, ainda não operacional |

### 15.1 Ordem por dependências

Ordem derivada das 10A/10B/10C:

```text
registry/quarantine/Audit + catálogos globais controlados
→ tenants e configurações mínimas
→ Auth identity mappings e application users
→ memberships e platform identities aprovadas
→ profile baselines, exact overrides e Equipes
→ Locais, Centros de Custo, Setores, Categorias e motivos aprovados
→ Fornecedores/contatos e Ativos/hierarquia
→ Solicitações
→ Planos e Programações
→ OS avulsas/vinculadas e ocorrências preventivas
→ custos, materiais, checklist e dependentes
→ Operational History classificado
→ file metadata e Storage associations
→ dados secundários autorizados
→ projeções/caches regeneráveis
→ counters/allocators somente após delta final
```

Esta ordem não autoriza criar cadastros ausentes por aproximação. Pais são carregados antes de filhos; relações são materializadas somente quando ambos os lados e o tenant fecham.

### 15.2 Idempotência

Namespace conceitual mínimo:

```text
environment
+ migration_run/source snapshot
+ source system/entity/id
+ mapping rule version
+ target operation/role
```

Para split/merge, incluir cardinality role e conjunto canônico de sources. Para Storage, incluir object identity e association identity separadas. Para History, incluir source event identity e suppression rule. Para grants, incluir User/Profile + Tenant + Resource + Action + Scope + decision version.

Retry com a mesma identidade retorna o mesmo target/resultado compatível ou erro determinístico. Nunca cria duplicata.

### 15.3 Load, Provenance e Audit

Toda transformação crítica confirma em boundary coerente:

```text
domain/target mutation
+ Migration Provenance/registry
+ technical Audit obrigatório
```

Audit não é log. Log auxilia diagnóstico; Audit prova a ação, autoridade, target e resultado. Se Audit obrigatório falhar, a operação correspondente não pode ser confirmada como concluída.

## 16. Reconciliation — P4

| Campo | Contrato |
| --- | --- |
| Inputs | CP2, source manifests, registry, quarantine, target base e rule set |
| Actions futuras | Executar L1–L4 e reconciliações críticas por snapshot/tenant/domínio/lote |
| Outputs | Reconciliation report imutável, exceptions e decisão de prontidão para rehearsal |
| Preconditions | Load report completo; queries/checks versionados; target não ativado |
| Postconditions | Equações fecham; invariants e security passam; falhas críticas/quarantine blocking zeradas |
| Evidence | Queries/digests, resultados, tolerâncias aprovadas, reviewers, timestamps e correlation |
| Metrics | Divergências por nível/domínio/tenant; failed critical; quarantine por impacto |
| Failure behavior | Não avançar a rehearsal/aprovação; isolar domínio; preservar target para diagnóstico quando seguro |
| Recovery path | Corrigir rule/artefato versionado, reload idempotente e rerun completo das reconciliações afetadas |
| Owner/approval | Data valida L1–L3; Security valida L4; Domain owners aceitam semântica |
| Next gate | CP3 — base reconciliada |

### 16.1 L1 — Count

Por `snapshot + tenant + domínio/source entity + rule version`:

```text
eligible
= mapped
+ quarantined
+ legacy_only
+ approved_discard
+ failed
```

Relatar também `source`, `ineligible_out_of_scope` e `target`. Antes de GO, `failed` crítico é zero. Count global não pode compensar perda em um tenant com duplicidade em outro.

### 16.2 L2 — Relationship

Validar:

- parent/child e FKs tenant-aware;
- Request `1 → 0..N OS` e OS `→ 0..1 Request`;
- Asset hierarchy sem ciclo/cross-tenant;
- Supplier relations sem merge inferido;
- user/application user/membership/profile/team;
- history parent e actor classification;
- file metadata/object/parent;
- Plano → Programação → occurrence → OS Preventiva → Execução.

Detectar broken reference, cross-tenant FK, cardinalidade inesperada, orphan e duplicate relation.

### 16.3 L3 — Semantic

Comparar tipos, status, prioridades, datas/timezones, códigos, custos, UOM, responsabilidades, executores, checklists, semântica preventiva, eventos históricos, file classifications e defaults. FK válida não prova semântica correta.

### 16.4 L4 — Security/Access

Provar ao menos:

- Tenant A não lê nem escreve Tenant B;
- SELECT, INSERT, UPDATE e commands;
- children, associations, files e signed access;
- reports, aggregates, Calendar, Dashboard e Notifications;
- workers, scheduler e technical handlers;
- requester OWN, ASSIGNED, executor, TEAM e ALL_TENANT;
- sensitive projections;
- Global Admin commands com target explícito;
- ausência de authority derivada de payload/path/metadata.

Mocks e filtros de frontend não provam L4.

## 17. Auth, Permissions, Codes, History e Storage Reconciliation

### 17.1 Auth e memberships

Aplicar as métricas e equações da 10C e adicionar testes futuros de:

- login e tenant/context selection;
- activation/invitation quando aplicável;
- recovery de credencial;
- blocked e inactive user;
- wrong tenant e missing membership;
- platform identity aprovada/rejeitada;
- session invalidation quando suportada/aplicável;
- Path A/Path B e todas as referências Auth.

Não exigir preservação de sessão quando arquitetura/provider não suportar. Nesse caso, o procedimento de reautenticação/recuperação precisa estar aprovado e ensaiado.

Métricas mínimas:

```text
auth_source / auth_eligible
auth_uuid_preserved / auth_uuid_remapped
auth_unresolved / auth_quarantined / auth_legacy_only
profiles_source / application_users_created
profiles_without_auth / auth_without_profiles / profiles_quarantined
membership_candidates / memberships_created / memberships_inactive
memberships_unresolved / memberships_quarantined / multi_membership_conflicts
platform_candidates / platform_approved / platform_rejected / platform_unresolved
```

Invariantes:

```text
auth_eligible
= auth_uuid_preserved
+ auth_uuid_remapped
+ auth_quarantined
+ auth_legacy_only
+ approved_discard

membership_candidates
= memberships_created
+ memberships_inactive
+ memberships_unresolved
+ memberships_quarantined
```

### 17.2 Permissions

Para cada `user/profile + tenant + Resource + Action + Scope`:

```text
V2 planned/effective privilege <= V1 proven privilege
```

Expansão somente com aprovação explícita, motivo, reviewer, timestamp e Audit/provenance. Testar combinações exatas e a união de scopes. Confirmar novamente:

```text
DENY OWN não subtrai ALL_TENANT
DENY TEAM não subtrai ALL_TENANT
```

Baseline, override exato, sensitive projection, ALL_TENANT, platform capability e bypass legado não promovido são relatados separadamente.

Métricas mínimas:

```text
legacy_permission_rows / legacy_effective_bypass_cases
safe_mapped_exact / mapped_after_scope_review / mapped_after_action_review
individual_overrides_created
quarantined / legacy_only / unresolved
```

### 17.3 Codes e counters

Por `tenant + namespace + year quando aplicável`, reconciliar:

- source/emitted codes, raw formats e aliases;
- duplicate groups e resolutions;
- máximos emitidos parseáveis;
- stored counters/sequences;
- base e delta emitted;
- target allocations aprovadas;
- `safe_next` e allocator state.

Teste futuro obrigatório de concorrência:

```text
N alocações simultâneas
→ N códigos únicos
→ zero reutilização
```

Métricas mínimas:

```text
source_code_rows / source_non_null_codes / unique_source_codes
duplicate_groups / invalid_format
target_preserved_codes / target_aliases / quarantined_codes
max_emitted_numeric / stored_counter / delta_max
safe_next / allocator_initialized
```

### 17.4 Operational History, Migration Provenance e Audit

Provar separadamente:

- Operational History completo ou explicitamente classificado;
- Migration Provenance bidirecional V1 ↔ V2;
- Audit técnico append-only e failure contract;
- `UNRESOLVED_ACTOR`/`LEGACY_ACTOR` preservados;
- nenhum humano fictício;
- suppression rules contabilizadas por source identity e rule version;
- parent, tenant, event type e timestamp semanticamente coerentes.

Métricas mínimas por tenant/domínio:

```text
source_history_records / eligible_history_records
mapped_operational_history / legacy_only_events
unresolved_actor_events / technical_actor_events
quarantined_events / duplicates_intentionally_suppressed / failed_events
```

```text
eligible_history_records
= mapped_operational_history
+ legacy_only_events
+ quarantined_events
+ duplicates_intentionally_suppressed
+ failed_events
```

### 17.5 Storage

Reconciliar:

```text
DB metadata
↔ Storage object
↔ target parent
↔ tenant
↔ integrity tier
↔ association
↔ availability
```

Por tenant/classe/lote: objects, metadata, matched pairs, quarantined, legacy-only, failed, bytes expected/copied/verified e available. Arquivo crítico não chega a `AVAILABLE` sem integridade forte exigida, parent, tenant, provenance e autorização contextual.

Métricas mínimas:

```text
source_objects / source_metadata_rows / matched_pairs
objects_without_metadata / metadata_without_object
parent_unresolved / tenant_mismatch
mapped_associations / quarantined / legacy_only / approved_discard / failed
target_objects / integrity_basic_verified / integrity_strong_verified
bytes_expected / bytes_copied / bytes_verified / available
```

## 18. Rehearsals — P5

| Campo | Contrato |
| --- | --- |
| Inputs | CP3, artefatos selados, snapshot representativo autorizado, runbook e recovery plan |
| Actions futuras | Executar processo end-to-end, gates, falhas planejadas, reconciliação, smoke e recovery |
| Outputs | Migration Run report, tempos medidos, defects/blockers e recovery evidence |
| Preconditions | Ambiente seguro/prod-like apropriado; dados sintéticos ou anonimizados aprovados; sinks externos |
| Postconditions | Critérios do nível de rehearsal alcançados; defects classificados; nenhum efeito em produção |
| Evidence | Manifest/digests, phase reports, logs/correlation, reconciliations, security tests e recovery proof |
| Metrics | Durações, volumes, throughput, retries, delta estimate, outage/freeze estimate e falhas |
| Failure behavior | Parar no gate previsto, isolar ambiente, preservar evidência e classificar falha |
| Recovery path | Demonstrar recovery do nível; corrigir artefato/versionar; novo Migration Run |
| Owner/approval | Migration Lead coordena; Data/Security/Platform/Operations/Business revisam por gate |
| Next gate | CP4 apenas após final dress rehearsal aprovado |

### 18.1 Maturidade progressiva

| Rehearsal | Objetivo | Dados/ambiente | Critério de saída |
| --- | --- | --- | --- |
| R1 — Structural | Provar migrations, ordem, registry/quarantine/Audit e idempotência básica | TEST determinístico | Reconstrução e retry sem duplicidade; falhas estruturais conhecidas |
| R2 — Representative Data | Exercitar mappings e exceções representativas | TEST/STAGING com dados sintéticos/anonimizados aprovados | L1–L3 fecham; quarantine/review workflow funciona |
| R3 — Production-like Full | Executar volume, Storage, Auth flows, L4, observabilidade e recovery | STAGING prod-like | Processo completo e recovery demonstrados sob carga representativa |
| R4 — Final Dress | Reproduzir runbook, pessoas, gates, freeze/delta e comunicação operacional | STAGING com RC congelada | Mesmos artefatos do cutover, zero blocker e aprovação CP4 |

Cada rehearsal gera novo Migration Run e relatório. Um rehearsal bem-sucedido não substitui o seguinte quando o risco/escopo exige progressão.

### 18.2 Critérios objetivos de sucesso

- run termina no estado previsto;
- reconciliação L1–L4 e domínios críticos fecha;
- `critical failed = 0` e `blocking quarantine = 0`;
- Auth, permission, code, Storage e security tests passam;
- functional smoke e observability passam;
- recovery é demonstrado, não apenas descrito;
- durações e capacidade são medidas;
- delta e freeze são estimados por evidência;
- passos manuais, owners e second-person verification são conhecidos;
- todos os artefatos e evidence bundles são recuperáveis.

“Pareceu funcionar” não é critério de aprovação.

## 19. Performance

Nenhuma duração é definida por suposição. Rehearsals devem medir:

| Medida | Corte mínimo | Uso |
| --- | --- | --- |
| Snapshot | Database, Auth, Storage manifest e bytes quando aplicável | Dimensionar captura e staleness |
| Mapping | Tenant/domínio/rule class | Dimensionar revisão e compute |
| DB load | Onda, tabela/domínio e lote | Definir throughput e janela |
| Auth preparation | Path A/Path B, activation e reconciliation | Planejar acesso e suporte |
| Storage | Manifest, copy, verify e associate | Separar transferência de disponibilidade |
| Reconciliation | L1–L4 e domínios críticos | Dimensionar gates, não apenas load |
| Delta | Captura, map, load e reconcile | Definir freeze/outage reais |
| Verification | Smoke, negative security e observability | Estimar tempo até CP9 |
| Recovery | Classe R0–R4 ensaiada | Validar abort threshold e decisão |
| Total | Freeze, indisponibilidade e estabilização inicial | Aprovar janela operacional |

Registrar p50/pior caso observado quando houver amostra suficiente, volumes correspondentes, gargalos, capacidade, paralelismo seguro e margem aprovada. Valores de um ambiente só são extrapolados quando a equivalência de recursos e volume for demonstrada.

Os resultados determinam `maximum approved window`, `cutover decision deadline` e `abort threshold`. Esses valores são `CUTOVER_ONLY` e permanecem indefinidos até R4.

## 20. Pre-cutover — P6

| Campo | Contrato |
| --- | --- |
| Inputs | CP4, RC declarada, métricas R4, blocker register, communication/recovery plans |
| Actions futuras | Congelar artefatos; validar backups/restore, credentials, operators, approvals, monitoring, target/source health e drift |
| Outputs | Pre-cutover readiness report, janela aprovada, roster e decisão de entrada em freeze |
| Preconditions | Final dress rehearsal aprovado; mesmos digests do cutover; nenhuma mudança não validada |
| Postconditions | Todos os itens abaixo possuem evidência atual ou impedem P7 |
| Evidence | RC/digests, restore report, source drift report, access checks, owner roster, kill-switch tests e approvals |
| Metrics | Gates ready/blocked, credential expiry, capacity headroom, issue counts e janela calculada |
| Failure behavior | Não iniciar freeze; manter V1 ativa; registrar NO-GO preemptivo |
| Recovery path | Resolver dependência, repetir validação/rehearsal afetado e reagendar janela |
| Owner/approval | Migration Lead prepara; Platform/Security/Operations/Data revisam; Business aceita janela |
| Next gate | Autorização explícita para P7 |

Checklist obrigatório antes do freeze:

- rehearsal final aprovado;
- artefatos congelados e RC identificada;
- migrations, configs e checksums confirmados;
- backup identities registrados e restore ensaiado;
- operators, reviewers, approvers e substitutes definidos;
- communication triggers/owners/audiences prontos;
- monitoring e dashboards ativos;
- kill switches e modos read-only testados;
- credentials válidas durante toda a janela e protegidas;
- target health/capacity e source health aprovados;
- source drift revalidado;
- blockers críticos e quarantine blocking zerados;
- Recovery Decision Tree e autoridade de decisão aprovados.

## 21. Freeze — P7

| Campo | Contrato |
| --- | --- |
| Inputs | Aprovação P6, writer inventory, janela/thresholds, source health e comunicação de manutenção |
| Actions futuras | Parar/controlar todos os writers; drenar in-flight; estabelecer boundaries; provar read-only efetivo |
| Outputs | `freeze_start`, writer shutdown evidence, boundaries DB/Auth/Storage e delta cutoff candidate |
| Preconditions | Autoridade para bloquear writers; kill switches; forma segura de reativar V1; observers ativos |
| Postconditions | Nenhum writer desconhecido/ativo no escopo; operações in-flight classificadas; CP5 selável |
| Evidence | Estado por writer, última transação/objeto/admin action, testes negativos de escrita e timestamps |
| Metrics | Tempo de freeze, writers total/stopped/drained/unknown, operações in-flight e falhas de write esperadas |
| Failure behavior | Não capturar delta final como completo; abortar antes da ativação se boundary não for confiável |
| Recovery path | R1: reativar writers V1 controladamente, reconciliar janela e preservar evidência |
| Owner/approval | Operations executa; owners de cada writer confirmam; Migration Lead/second person verificam |
| Next gate | CP5 — source frozen |

### 21.1 Inventário de writers

O freeze deve abranger, conforme descoberta futura:

| Classe | Evidência de parada/controle |
| --- | --- |
| UI writes | Commands/requests mutantes recusados no servidor, não apenas tela de manutenção |
| Edge Functions/API | Rotas mutantes desabilitadas/allowlisted e chamadas in-flight drenadas |
| Scheduled jobs | Schedules pausados e leases/claims resolvidos |
| Workers/outbox | Consumers pausados, backlog e in-flight conhecidos |
| External integrations | Credenciais/webhooks/writers suspensos ou sink controlado |
| Storage uploads | Reserve/finalize/upload bloqueados; uploads em andamento classificados |
| Auth administration | Convites, bloqueios, recovery administrativo e alterações relevantes controlados |
| Manual SQL/admin | Change window e acessos privilegiados bloqueados/auditados |

Colocar a UI em manutenção não congela esses writers. Qualquer writer desconhecido relevante é `CUTOVER_BLOCKER`.

### 21.2 Freeze window

Registrar:

- `freeze_start` e clock source;
- writer shutdown/drain evidence;
- última boundary de Database;
- última boundary de Storage;
- última boundary administrativa de Auth quando aplicável;
- `delta_cutoff` e identity;
- `cutover_decision_deadline`;
- `maximum_approved_window`;
- `abort_threshold` e quem pode acioná-lo.

Valores concretos vêm das medições aprovadas; não são inventados neste documento.

## 22. Delta — P8/P9

### 22.1 Contrato P8 — Delta Capture

| Campo | Contrato |
| --- | --- |
| Inputs | CP5, Consistency Envelope base, source snapshot, boundaries e strategy por domínio |
| Actions futuras | Capturar inserts/updates/deletes/Auth/Storage ocorridos entre base e freeze; selar delta manifest |
| Outputs | Delta identity, manifests por fonte, coverage report e gaps/blockers |
| Preconditions | Writers parados/controlados; boundaries confiáveis; mecanismos de captura ensaiados |
| Postconditions | Todo writer/domínio está coberto ou explicitamente bloqueado; delta é imutável |
| Evidence | Watermarks/log positions/diffs/manifests, queries/version, counts/hashes e cutoff |
| Metrics | Inserts/updates/deletes/objects/Auth changes, coverage, gaps e capture duration |
| Failure behavior | Delta incompleto é NO-GO; não ativar V2 |
| Recovery path | R1: restaurar writers V1 ou repetir boundary/captura dentro da janela aprovada |
| Owner/approval | Data/Platform capturam; source owners e Security revisam cobertura |
| Next gate | Entrada P9 somente com delta selado |

### 22.2 Estratégia por domínio

Opções conceituais a avaliar, sem escolha prematura:

- timestamp/high-water mark;
- change log/CDC confiável;
- Audit/Operational History quando completo para o caso;
- explicit manifest diff;
- full recompare de tabelas pequenas;
- Storage object/metadata delta;
- Auth administrative delta.

Critérios de escolha:

1. detecta insert, update e delete relevantes;
2. boundary é consistente e repetível;
3. todos os writers usam ou são capturados pelo mecanismo;
4. clocks/timezones e coluna de atualização são confiáveis;
5. retry é idempotente;
6. gaps e operações in-flight são observáveis;
7. reconciliação independente pode provar completude.

Se uma tabela não possui timestamp confiável, timestamp não pode ser a única estratégia. Se updates/deletes não são observáveis, high-water mark por ID é insuficiente. A ausência de mecanismo confiável é `DESIGN_BLOCKER` e, na janela, `CUTOVER_BLOCKER`.

### 22.3 Deletes

Deletes V1 são classificados, nunca propagados automaticamente:

| Classe | Tratamento |
| --- | --- |
| Historical deletion | Preservar evidência e aplicar regra histórica aprovada |
| Logical removal | Mapear para Cancelado/Inativo/Baixado/Arquivado quando semântica comprovada |
| Legacy-only | Reter fora da operação V2 |
| Correction | Aplicar decisão versionada com provenance |
| Security deletion | Seguir decisão legal/security específica e auditada |
| Unknown | Quarantine; não apagar target |

### 22.4 Contrato P9 — Delta Load

| Campo | Contrato |
| --- | --- |
| Inputs | Delta selado, mesmas mapping rules/artefatos, target base e registry |
| Actions futuras | Classificar, carregar idempotentemente, atualizar relações, reconciliar Auth/Storage/codes |
| Outputs | Target atualizado até o cutoff, delta reconciliation e `safe_next` candidate final |
| Preconditions | Nenhum bypass das regras 10B/10C; target ainda não ativo; Audit disponível |
| Postconditions | Delta inteiro classificado; `failed critical=0`; relações/Storage/Auth reconciliados |
| Evidence | Registry, Audit, load report, source/target counts/hashes e exceptions |
| Metrics | Delta mapped/quarantined/legacy/failed, retries, duração e drift residual |
| Failure behavior | Não seguir a P10; manter V1 frozen até threshold ou executar R1 |
| Recovery path | Retry idempotente do lote ou R1 conforme janela/risco; nunca carga manual sem regra |
| Owner/approval | Migration Operator executa; Data/Security revisam por domínio |
| Next gate | P10 Final Reconciliation |

Sequência futura:

```text
freeze writers
→ establish boundaries
→ capture delta
→ classify with the same rules
→ load idempotently
→ reconcile delta
→ update safe_next
→ reconcile Storage/Auth
→ final reconciliation
```

### 22.5 Final safe next

Somente após o delta:

```text
safe_next
>
max(
  base emitted,
  base counters,
  delta emitted,
  approved target allocations
)
```

O cálculo é por tenant + namespace + ano quando aplicável. O allocator fica desativado até CP7/CP8 conforme a sequência aprovada. Gap é aceitável; reuse não.

## 23. Final Reconciliation — P10

| Campo | Contrato |
| --- | --- |
| Inputs | Base + delta carregados, source frozen, final manifests, registry/quarantine/Audit |
| Actions futuras | Reexecutar L1–L4, Auth, permissions, codes, History, Provenance, Audit, Storage, health e observability |
| Outputs | Final Reconciliation Report imutável e proposta de GO/NO-GO |
| Preconditions | P9 concluída; `safe_next` recalculado; nenhuma escrita source/target fora do protocolo |
| Postconditions | Todas as métricas fecham e gates recebem evidência atual; CP6 selável |
| Evidence | Resultados versionados, tolerâncias, security tests, health checks, approvals e hashes |
| Metrics | Divergências finais, quarantine por criticidade, errors, access failures e health |
| Failure behavior | NO-GO; não ativar; preservar frozen state até decisão R1/limite da janela |
| Recovery path | Corrigir via novo run/roll-forward pré-ativação ou restaurar writers V1 controladamente |
| Owner/approval | Data/Security/Platform validam; Migration Lead consolida; approvers independentes revisam |
| Next gate | CP6 e P11 GO/NO-GO |

O relatório final referencia exatamente o release, snapshot, delta, rules e digests usados. Relatório anterior não pode ser reutilizado após qualquer mudança material.

## 24. GO/NO-GO — P11

| Campo | Contrato |
| --- | --- |
| Inputs | CP6, Final Reconciliation, gate matrix, blockers, waivers permitidos e janela restante |
| Actions futuras | Revisar evidências por categoria; registrar decisões independentes; consolidar GO ou NO-GO |
| Outputs | Decisão formal com approvers, timestamp, motivo e evidence bundle |
| Preconditions | Todos os gates têm status/evidence/owner/reviewer; nenhum waiver proibido |
| Postconditions | GO somente com todos os gates obrigatórios aprovados; NO-GO preserva V1 como writer |
| Evidence | Matrix assinada, blockers/quarantine, approvals, remaining window e correlation |
| Metrics | Gates approved/rejected/pending, blockers, waivers e tempo restante |
| Failure behavior | Ausência de decisão, approver ou evidência equivale a NO-GO |
| Recovery path | NO-GO → R1, reativação V1 controlada, reconciliação da janela e novo run |
| Owner/approval | Migration Lead não aprova sozinho; Data, Security, Platform, Operations e Business aprovam sua classe |
| Next gate | CP7 somente em GO; caso contrário ABORTED/REJECTED com recovery |

Categorias obrigatórias:

```text
DATA
AUTH
SECURITY
CODES
STORAGE
APPLICATION
INFRASTRUCTURE
OBSERVABILITY
RECOVERY
BUSINESS/OPERATIONS
```

### 24.1 Waivers

Waiver é proibido para:

- exposição cross-tenant confirmada;
- expansão de privilégio não resolvida;
- perda de dado crítico;
- identidade Auth insegura;
- possibilidade de reutilização de código;
- perda de evidência crítica;
- restore/recovery não demonstrado.

Para caso permitido, o waiver deve conter escopo preciso, owner, risco, evidência, compensating control, approver, validade/prazo e critério de resolução. Waiver nunca transforma falha conhecida em sucesso técnico.

### 24.2 NO-GO

NO-GO é uma saída normal e segura. Ao ocorrer:

1. não ativar V2 nem allocator;
2. preservar todos os manifests, relatórios, logs, approvals e motivo;
3. encerrar o run como `REJECTED` ou `ABORTED` conforme o momento;
4. executar R1 para restaurar writers V1 controladamente;
5. reconciliar alterações ocorridas durante a janela e in-flight work;
6. comunicar conforme trigger aprovado;
7. corrigir por artefato/regra versionados;
8. planejar novo Migration Run, sem reescrever a tentativa anterior.

## 25. Cutover — P12

| Campo | Contrato |
| --- | --- |
| Inputs | CP7/GO, source frozen, target reconciliado, RC/digests, operators e kill switches |
| Actions futuras | Colocar V1 no estado de retenção; ativar V2, allocator e serviços na ordem; validar Auth/routing; iniciar smoke/observação |
| Outputs | V2 ativa como single writer, activation evidence e estado V1 registrado |
| Preconditions | Todos os gates GO; janela válida; nenhuma alteração pós-reconciliação; approvals presentes |
| Postconditions | CP8 registrado; writes V2 controlados; V1 não escreve no mesmo domínio |
| Evidence | Activation commands/actions, before/after health, config/release identity, actor, timestamps e routing checks |
| Metrics | Activation duration, errors, write attempts V1/V2, Auth/routing health e service readiness |
| Failure behavior | Acionar kill switch; classificar R2/R3; não alternar writers informalmente |
| Recovery path | R2 controlled return quando sem writes significativos; R3 roll-forward/recovery quando V2 writes existem |
| Owner/approval | Operations executa; second person verifica; Migration Lead coordena; incident authority decide recovery |
| Next gate | CP8 e P13 |

Sequência conceitual explícita:

1. confirmar freeze e boundaries;
2. confirmar delta fechado e identificado;
3. confirmar Final Reconciliation e `safe_next`;
4. registrar GO/CP7;
5. colocar V1 em `FROZEN`/`READ_ONLY_REFERENCE` conforme plano;
6. ativar release V2 e configuração autorizada;
7. ativar allocator/counters reconciliados;
8. ativar workers/schedulers necessários e allowlisted;
9. validar Auth/lifecycle/memberships;
10. validar routing/config/entitlements;
11. executar smoke e negative security tests controlados;
12. iniciar observação reforçada e suporte de cutover.

Qualquer refinamento futuro deve preservar dependências, evidence e single writer.

## 26. Single Writer

Baseline:

```text
antes de CP8: V1 é o writer operacional; V2 target permanece não ativo
após CP8: V2 é o único writer operacional dos domínios ativados; V1 fica frozen/read-only
```

Não é permitido que V1 e V2 escrevam simultaneamente no mesmo domínio sem uma estratégia formal de dual-write, que não é definida nem autorizada nesta etapa.

O enforcement futuro deve abranger UI, API/Edge Functions, Database, Storage, Auth administration aplicável, workers, scheduler, integrações e acessos manuais. Monitorar tentativas de escrita no sistema que deveria estar read-only.

Ativação por tenant/onda, se adotada em rollout posterior, ainda exige exatamente um writer por `tenant + domínio` e matriz explícita de ownership. Nunca se usa roteamento ambíguo ou eventual consistency como prova de exclusividade.

## 27. Recovery Model

Rollback não é um comando único. Recovery é decisão de sistema distribuído que considera Database, Auth, Storage, códigos, History/Audit/Provenance, workers e efeitos externos.

| Classe | Source state | Target state | Ação permitida | Reconciliação | Writer strategy | Auth | Codes | Storage | External effects | Aprovação |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R0 — abort before source freeze | V1 ativa | Target parcial/não ativo | Abortar run; isolar/limpar apenas por procedimento recuperável futuro | Registrar partial target e run; nenhuma delta final | V1 continua writer | Nenhuma troca presumida; reverter preparações seguras | Allocator V2 inativo | Objetos target ficam unavailable/quarantined | Sinks de rehearsal; classificar qualquer efeito | Migration Lead + owner técnico |
| R1 — abort during freeze before activation | V1 frozen | Base/delta parcial ou reconciliado, não ativo | Não ativar; restaurar writers V1 controladamente | Reconciliar in-flight/janela e novo boundary | V1 volta a único writer após verificação | Reabrir administração/fluxos conforme boundary | Nenhum código V2 operacional emitido; preservar reservations | Classificar uploads in-flight/copied | Comunicar atraso/NO-GO; reconciliar chamadas | Operations + Data + Security conforme causa |
| R2 — failure after activation, before meaningful V2 writes | V1 frozen/read-only | V2 ativa, sem writes significativos comprovados | Kill switch; avaliar controlled return | Provar ausência de writes/side effects em todos os sistemas | Só então V1 pode voltar a writer | Verificar login/session/activation changes | Provar ausência de códigos emitidos; gaps/reservas preservados | Provar ausência de novos AVAILABLE/uploads ou tratá-los | Provar/compensar side effects | Incident authority + Security + Data + Business |
| R3 — failure after V2 writes exist | V1 frozen/read-only | V2 contém fatos novos | Preferir roll-forward; return exige reverse delta/manual recovery aprovado | Inventariar V2-only writes e efeitos por domínio | V2 read-only/isolation durante decisão; nunca dual writer implícito | Reconciliar identities, status, recovery e sessions | Todos os códigos V2 ficam consumidos mesmo se operação for revertida | Preservar novos uploads e associations; versionar movimentos | Reconciliar/compensar quando possível; no exactly-once presumido | Incident command + approvers técnicos e negócio |
| R4 — incident in stabilization | V1 retida | V2 operacional com volume de writes | Isolar tenant/domínio, read-only/kill switch; roll-forward ou recovery dirigido | Reconciliar desde CP8 e determinar blast radius | V2 continua controlada ou read-only; V1 não é ligada por reflexo | Tratar compromissos/lifecycle/session invalidation | Não reutilizar qualquer código emitido | Hold de evidência, orphan/partial/checksum workflow | Incident response e comunicação externa aplicável | Security Incident/Data Incident authority + direção responsável |

Cada classe recebe playbook implementável futuro com comandos/ações exatos, preconditions, expected output, evidence, second-person verification e abort conditions.

## 28. Return to V1

### 28.1 Point of No Simple Return

O ponto de não retorno simples é o primeiro momento em que V2 aceita qualquer escrita operacional ou efeito externo significativo após CP8.

```text
V2 operational write accepted
OR Auth lifecycle changed exclusively in V2
OR V2 code emitted/reserved as operational
OR V2 file accepted/associated
OR external side effect emitted
→ POINT OF NO SIMPLE RETURN crossed
```

Antes desse ponto, R2 pode permitir retorno controlado, desde que a ausência de writes e efeitos seja positivamente comprovada em Database, Auth, Storage, workers e integrações. “Não vimos erro” não é prova.

Depois desse ponto, ligar V1 não é rollback. É uma migração de retorno que precisa tratar:

- V2-only domain writes e relações;
- novos estados Auth, convites, recoveries e sessions;
- códigos e counters consumidos;
- novos arquivos, metadados e associações;
- History, Audit, Provenance e notifications;
- outbox/jobs e efeitos externos.

### 28.2 Condições para retorno

Return to V1 só é autorizado quando:

1. a classe R2 ou R3 foi determinada com evidência;
2. o sistema V2 está isolado/read-only de modo confiável;
3. reverse delta, forward correction ou manual controlled recovery foi aprovado;
4. não haverá writers simultâneos;
5. Auth, codes, Storage e efeitos externos possuem tratamento explícito;
6. reconciliação de retorno fecha por tenant/domínio;
7. Security, Data, Operations e Business aprovam;
8. evidence bundle permanece íntegro.

Não se presume ETL bidirecional. Se o reverse delta não foi desenhado e ensaiado, a opção segura pode ser V2 read-only temporária + roll-forward.

## 29. Roll Forward

Preferir Roll Forward quando:

- schema migration já foi publicada;
- V2 recebeu writes operacionais;
- efeitos externos foram emitidos;
- reverse migration é destrutiva/insegura;
- Auth divergiu;
- códigos/arquivos novos existem;
- a falha pode ser isolada e corrigida mantendo provenance.

Correção forward deve:

- ser versionada e revisar compatibilidade;
- usar novo release/migration/rule digest;
- preservar Migration Provenance e Audit;
- possuir idempotency key e recovery path;
- reconciliar o conjunto afetado e depois o sistema completo necessário;
- passar security/functional regression proporcional;
- gerar novo checkpoint/evidence, sem alterar o run anterior;
- exigir novo gate antes de reabrir writes suspensos.

Hotfix não autoriza “corrigir em produção e continuar” após incidente de segurança/dado crítico. Primeiro isola-se, preserva-se evidência e volta-se ao gate apropriado.

## 30. Database, Auth, Storage e Code Recovery

### 30.1 Database

Restore de Database é somente uma parte. O plano deve registrar backup identity, schema/application compatibility, point-in-time/boundary, dependências, duração ensaiada e reconciliação pós-restore.

Um restore não pode:

- apagar tentativas/evidence bundles;
- reintroduzir RLS/grants inseguros;
- retroceder counters permitindo reuse;
- ser declarado sucesso antes de reconciliar Auth/Storage/externals;
- sobrescrever estado válido sem plano de preservação.

### 30.2 Auth

Recovery deve tratar:

- identities novas/remapeadas e seus references;
- invitations/activation;
- password recovery em andamento;
- session invalidation quando aplicável;
- blocked/inactive users e provider state;
- mudanças de e-mail/MFA/provider;
- comunicação e suporte ao usuário.

Não se promete retorno transparente de sessão. Credenciais, hashes, tokens e sessions não entram no evidence bundle.

### 30.3 Storage

Classificar e reconciliar:

- objetos copiados mas não disponíveis;
- objetos `AVAILABLE` antes do incidente;
- novos uploads V2;
- target objects órfãos;
- cópias parciais;
- checksum mismatch;
- metadata/association sem objeto ou vice-versa.

Nunca sobrescrever bytes existentes para “corrigir rapidamente”. Usar nova object identity/version e provenance. Exclusão/garbage collection só ocorre depois da retenção e reconciliação aprovadas.

### 30.4 Codes

Código emitido ou reservado operacionalmente pela V2 durante o período ativo nunca é reutilizado, mesmo que o registro seja revertido ou o sistema retorne à V1. O recovery:

- preserva o conjunto consumido;
- avança counters para além de V1 + V2;
- registra gaps e aliases;
- reconcilia por tenant/namespace/year;
- testa concorrência antes de reabrir allocator.

Gap é custo aceitável de segurança; reuse não é.

## 31. External Effects

Efeitos potencialmente não reversíveis:

- e-mail transacional ou mensagem;
- webhook/integration call;
- notificação externa;
- documento enviado/exportado;
- ação de provider;
- job que chama sistema terceiro.

Rehearsals usam sink, sandbox ou allowlist. O runbook não presume exactly-once:

```text
at-least-once
+ idempotency
+ reconciliation
+ compensation quando suportada
```

Cada efeito deve registrar idempotency identity, target protegido/minimizado, attempt, result, provider reference, correlation e reconciliation status. Recovery classifica `not emitted`, `emitted unknown`, `accepted`, `failed`, `duplicate suppressed` ou `compensated`. Não se apaga a evidência do envio para parecer que o efeito não ocorreu.

## 32. Post-cutover Verify — P13

| Campo | Contrato |
| --- | --- |
| Inputs | CP8, identities controladas, smoke plan, negative security plan e dashboards |
| Actions futuras | Executar smoke funcional e segurança negativa; observar health e writes |
| Outputs | Verification report, incident classification ou CP9 |
| Preconditions | V2 ativa; V1 read-only; test identities/dados isolados e aprovados |
| Postconditions | Fluxos críticos e isolamento passam; nenhuma evidência de corrupção/exposição |
| Evidence | Test cases/results, actor/tenant, correlation IDs, screenshots/log references seguros e timestamps |
| Metrics | Success/failure/latency, 4xx/5xx, denials, code/storage/job outcomes |
| Failure behavior | Isolar/kill switch; classificar R2/R3; interromper expansão |
| Recovery path | Recovery Decision Tree; roll-forward preferido após writes; novo gate |
| Owner/approval | QA/Operations executam; Security valida negativos; Domain owners aceitam smoke |
| Next gate | CP9 — smoke/security passed |

Smoke controlado mínimo:

- login, recovery/activation aplicável e tenant selection/context;
- Visão Geral/Dashboard autorizados;
- Request create/view/transition aplicável;
- OS create/view/program/start/pause/resume/validation aplicável;
- Asset, Supplier, Plan e Calendar;
- reports e sensitive projections;
- file access, signed access e upload reserve/finalize;
- permission behavior e command de Global Admin controlado;
- codes/counters;
- internal notifications;
- workers, outbox e scheduler.

Os testes usam identities e registros controlados. Nenhum teste deve depender de acesso real de cliente não autorizado.

## 33. Security Verification

### 33.1 Casos negativos obrigatórios

| Ator/caso | Tentativa | Resultado obrigatório |
| --- | --- | --- |
| Tenant A | Ler/alterar Tenant B | Negado sem vazamento de existência/campo inadequado |
| Requester | Ação administrativa | Negada por capability/scope |
| Executor sem capability | Validar/administrar OS | Negada |
| Blocked user | Login/operação/sessão antiga | Bloqueado conforme lifecycle |
| User without membership | Selecionar/acessar tenant | Negado |
| Tenant admin | Platform command | Negado |
| Platform context | Union silenciosa de tenants | Negada; target explícito exigido |
| Sem parent authorization | Acessar file/signed URL | Negado |
| Payload adulterado | Trocar tenant/actor/authority | Ignorado/negado; autoridade relida |
| Worker/handler incorreto | Executar job fora da allowlist | Negado e observado |

Cobrir SELECT, INSERT, UPDATE, commands, children, files, reports, aggregates, Calendar, Dashboard, workers, scheduler e Notifications. Testes interleaved A/B impedem que cache ou contexto residual mascare vazamento.

### 33.2 Tratamento de falha

Qualquer cross-tenant read/write confirmado, privilege escalation, platform action não autorizada ou exposição crítica:

1. interrompe expansão e smoke subsequente;
2. aciona kill switch/isolation;
3. preserva evidence e correlation;
4. classifica incidente e blast radius;
5. invoca Recovery Decision Tree;
6. exige correção versionada, reconciliação e novo security gate.

## 34. Observability

### 34.1 Painel de cutover

Monitorar por environment/release/tenant protegido e correlation:

- Auth failures, activation/recovery e anomalous login;
- 403/permission denials e desvios de baseline;
- unexpected 5xx, Database errors e RLS denials;
- cross-tenant security signals;
- command failures/conflicts/idempotency replays;
- worker failures, stale lease/fencing e outbox backlog;
- scheduler failures/duplicate occurrence signals;
- Storage upload/finalize/access/checksum failures;
- code allocation errors/collisions;
- latency, saturation e capacity;
- quarantine growth e reconciliation drift;
- attempts de write na V1 read-only;
- external effects pending/unknown.

### 34.2 Contrato

- correlation ID atravessa request, command/transaction, outbox e worker;
- release/build/migration run identity integra eventos;
- logs nunca contêm secrets, tokens, service_role, signed URLs completas, passwords, conteúdo integral de anexos ou PII desnecessária;
- observabilidade tem acesso restrito e auditável;
- métricas agregadas não criam union cross-tenant insegura;
- alertas técnicos não se confundem com alertas funcionais;
- dashboard indisponível ou não validado é `CUTOVER_BLOCKER`.

Thresholds/SLIs concretos são definidos por evidência de rehearsal e baseline operacional, não por números arbitrários aqui.

## 35. Stabilization — P14

| Campo | Contrato |
| --- | --- |
| Inputs | CP9, V2 ativa, monitoring, support triage, reconciliation baselines e legacy retention state |
| Actions futuras | Observar, reconciliar continuamente, classificar incidentes/support, corrigir forward e controlar expansão |
| Outputs | Stabilization report, acceptance ou incident/recovery action |
| Preconditions | Smoke/security aprovados; support/incident roster ativo; backups operacionais válidos |
| Postconditions | Critérios de saída atendidos e CP10 aprovado; expansão somente após gate |
| Evidence | Dashboards, reconciliation snapshots, incident/issues, backup evidence e business acceptance |
| Metrics | P0/P1 incidents, Auth/storage/code/job health, support volume, drift e reconciliation |
| Failure behavior | Interromper expansão; isolar tenant/domínio; classificar R4 |
| Recovery path | Roll-forward/recovery controlado; novo gate de estabilização |
| Owner/approval | Operations lidera; Security/Data/Domain/Support revisam; Business aceita |
| Next gate | CP10 — stabilization accepted |

Não se inventa duração. A estabilização só encerra quando:

- zero incidente P0/P1 aberto;
- reconciliação continua fechada;
- sinais de segurança estão dentro da baseline aprovada;
- Auth e memberships estão estáveis;
- workers, outbox e scheduler estão estáveis;
- Storage e files estão estáveis;
- codes/counters estão estáveis e sem reuse;
- backups continuam válidos e restauráveis conforme plano;
- support issues estão classificados, com blockers resolvidos;
- business acceptance está registrada.

Encerrar estabilização não autoriza apagar V1 nem evidências.

## 36. Serena Pilot

Serena é tenant piloto em produção. Não recebe ambiente, schema, RLS, migration, worker ou código próprios.

Invariantes:

- mesmo release, digests e schema de produção;
- mesmas RLS/FKs, commands, Storage protocol e technical handlers;
- mesmos gates de segurança, Auth, codes e recovery;
- nenhum bypass, `service_role` no cliente, SQL manual irreproduzível ou lógica Serena-specific;
- diferença somente por feature/config/tenant allowlist prevista na arquitetura e auditável;
- dados e observabilidade respeitam privacidade e tenant isolation;
- thresholds, coorte e duração são `ROLLOUT_DEPENDENT`.

O pilot exige Migration Run/evidence por onda e critérios de entrada/saída aprovados. Falha Serena interrompe expansão; não cria fork para “fazer o piloto funcionar”. Após estabilização e CP10 do escopo piloto, a expansão continua gradualmente com os mesmos artefatos ou com nova release validada.

## 37. Second Tenant

Antes de ativar o segundo tenant, executar testes interleaved A/B que alternem sessão, contexto e ordem das operações para:

- tabelas e queries de domínio;
- children e associations;
- reports, aggregates, Dashboard e Visão Geral;
- Calendar e Notifications;
- Storage metadata, object access, signed access e upload;
- cache, multitab, logout e context switch;
- workers, outbox e scheduler;
- codes/counters/quotas;
- Global Admin e platform commands;
- permissions OWN, ASSIGNED, TEAM e ALL_TENANT;
- sensitive projections e erros anti-enumeration.

Critérios de saída:

1. zero cross-tenant read/write/side effect;
2. cache/query keys incluem principal/context + tenant + resource/query + filters/projection;
3. workers e scheduler releem tenant/source e não confiam no payload;
4. allocators permanecem independentes por namespace/tenant/year aplicável;
5. platform commands exigem target explícito;
6. nenhum código/configuration path Serena-specific;
7. reconciliação de ambos os tenants fecha separadamente e em conjunto sem compensação cruzada;
8. expansão recebe aprovação de Security, Operations, Data e Business.

Falha bloqueia o segundo tenant e invoca incident/recovery conforme o momento; Serena não é usada como justificativa para waiver de isolamento.

## 38. Legacy Retention — P15

| Campo | Contrato |
| --- | --- |
| Inputs | CP10, retention/legal/business decisions, final evidence bundles e recovery posture |
| Actions futuras | Manter V1 no estado aprovado; controlar acesso; verificar backups/evidence; revisar elegibilidade futura |
| Outputs | Legacy state record, access/retention controls e review schedule definido por autoridade competente |
| Preconditions | Stabilization aceita; recovery dependencies conhecidas; nenhuma purge implícita |
| Postconditions | V1 preservada, acessível apenas conforme necessidade e sem writer operacional indevido |
| Evidence | Estado, release/snapshot, backup identities, access list, approvals, legal/retention basis e checks |
| Metrics | Acessos, storage/cost quando aplicável, integrity checks, incidents e dependencies abertas |
| Failure behavior | Suspender mudança de estado/purge; preservar V1 e investigar |
| Recovery path | Restaurar controle/acesso mínimo; renovar backup/evidence sem reativar writer por reflexo |
| Owner/approval | Platform/Operations custodiam; Security/Legal/Data/Business aprovam mudanças materiais |
| Next gate | Review de retenção futuro, fora desta etapa |

Estados permitidos:

```text
ACTIVE
→ FROZEN
→ READ_ONLY_REFERENCE
→ ARCHIVED
→ ELIGIBLE_FOR_RETENTION_REVIEW
```

- `ACTIVE` é o estado operacional anterior ao cutover.
- `FROZEN` bloqueia writers durante a janela.
- `READ_ONLY_REFERENCE` permite consulta controlada sem operação concorrente.
- `ARCHIVED` preserva dados/evidência sem serviço operacional normal.
- `ELIGIBLE_FOR_RETENTION_REVIEW` apenas autoriza avaliação; não significa purge.

Não há prazo arbitrário nem purge nesta etapa. Retenção depende de negócio, auditoria, legal, recovery, incident hold e evidence. Mudança de estado é auditada e nunca apaga o Migration Run.

## 39. Backups e Restore

### 39.1 Evidence mínima

Para cada backup relevante:

| Campo | Requisito |
| --- | --- |
| Identity | ID imutável, ambiente, release/schema e source/target boundary |
| Timestamp | Início/fim e clock source |
| Scope | Database, Auth/config autorizada, Storage/manifests e dependências cobertas |
| Retention | Política, localização protegida, acesso e hold |
| Integrity | Checksums/fingerprints e verificação de legibilidade |
| Restore test | Run, ambiente isolado, procedimento/versão e resultado |
| Restore duration | Medida real com volume e recursos correspondentes |
| Owner | Custodian, executor, reviewer e approver |
| Dependencies | Auth, Storage, externals, secrets/config e application compatibility |

“Backup existe” não é gate suficiente. Restore deve ser executado em ambiente seguro, reconciliado e ensaiado até o nível exigido pela classe de recovery.

### 39.2 Critérios de restore rehearsal

- backup correto é localizável pela identity, sem ambiguidade;
- ambiente isolado é reconstruído com release/schema compatíveis;
- integridade do conteúdo é verificada;
- L1–L3 e security checks proporcionais passam;
- Auth/Storage/externals não são declarados restaurados por consequência do DB;
- duração e passos manuais são medidos;
- credenciais/secrets permanecem protegidos;
- falha e nova tentativa preservam evidência;
- resultado alimenta R0–R4 e a janela de cutover.

Restore não demonstrado é waiver-prohibited e `CUTOVER_BLOCKER`.

## 40. Checkpoints

Checkpoints são registros imutáveis, não nomes informais em log.

| Checkpoint | Estado provado | Evidência mínima | Aprovação |
| --- | --- | --- | --- |
| CP0 — source validated | Prerrequisitos, source/target, writers e governance validados | Readiness, drift baseline, owners, tooling/tests | Migration Lead + owners técnicos |
| CP1 — snapshot sealed | Database/Auth/Storage sob Consistency Envelope válido | Snapshot/manifests, boundaries, counts/hashes | Data + Platform + Security |
| CP2 — base loaded | Base idempotente carregada e não ativa | Load report, registry, Audit, exceptions | Data/Migration Operator review |
| CP3 — base reconciled | L1–L4 base e domínios críticos aprovados | Reconciliation reports e security results | Data + Security + Domain |
| CP4 — rehearsal approved | Final dress rehearsal e recovery aprovados | Run report, durations, failures/recovery, digests | Todas as classes de gate aplicáveis |
| CP5 — source frozen | Todos os writers controlados e boundaries finais estabelecidos | Writer evidence e negative write checks | Operations + second person |
| CP6 — delta reconciled | Delta completo, `safe_next` e final reconciliation fechados | Delta manifests/load/reconciliation | Data + Security + Platform |
| CP7 — GO approved | GO formal sem blocker/waiver proibido | GO/NO-GO Matrix e approvals | Approvers independentes |
| CP8 — V2 activated | V2 ativa, V1 não writer, release/config corretos | Activation/routing/service evidence | Operations + Migration Lead |
| CP9 — smoke/security passed | Funcional e segurança negativos aprovados | Test results, correlations e incident status | QA/Domain + Security |
| CP10 — stabilization accepted | Operação estável e business acceptance | Monitoring/reconciliation/support/backup reports | Operations + Business + Security/Data |

Reabrir um checkpoint exige evento explícito e avaliação do impacto nos checkpoints posteriores. Eles não são editados para esconder regressão.

## 41. Evidence Bundles

### 41.1 Conteúdo comum

Cada checkpoint registra ou referencia de forma imutável:

- `migration_run_id`, wave, attempt e correlation;
- release ID, commit SHA, manifest e artifact digests;
- source snapshot e Consistency Envelope;
- phase inputs/outputs e timestamps;
- counts, hashes e reconciliation reports;
- security/Auth/permission/code/Storage test results aplicáveis;
- approvals, reviewer, owner e separação de funções;
- logs/correlation e observability snapshot;
- exceptions, failures, waivers permitidos e quarantine;
- recovery actions e estado source/target;
- config identity sem secrets;
- referências de backup/restore quando aplicável.

### 41.2 Privacidade e integridade

- não incluir secrets, tokens, password hashes, sessions, service role, signed URLs completas ou PII desnecessária;
- usar hashes, IDs técnicos e referências protegidas quando conteúdo integral não for necessário;
- controlar acesso por sensibilidade e auditar leitura administrativa;
- assinar/calcular digest do bundle e registrar versão;
- não sobrescrever bundle anterior; correções são adendas versionadas;
- manter ligação bidirecional com Migration Run e checkpoint.

## 42. Migration Run Report

Template conceitual obrigatório:

```text
1. Run identity
   - migration_run_id / wave / attempt / correlation
2. Environment
3. Source
   - release / Database / Auth / Storage
4. Target
   - release / schema / config / health
5. Artifact manifest and digests
6. Snapshot and Consistency Envelope
7. Start/end and measured durations
8. Phase results P0–P15 applicable to the run
9. Checkpoints and evidence bundles
10. Metrics and reconciliation L1–L4
11. Auth / memberships / platform identities
12. Permissions and privilege comparison
13. Codes / counters / safe_next
14. Operational History / Provenance / Audit
15. Storage / bytes / integrity / availability
16. Quarantine / exceptions / waivers
17. Failures and failure injections
18. Security and functional verification
19. Recovery actions / source-target state
20. Approvals and separation of duties
21. Final status and rationale
22. Evidence references
```

O relatório distingue fatos observados, inferências aprovadas, pendências e `REVALIDATION_REQUIRED`. `COMPLETED` nunca é usado para um run que apenas carregou dados sem reconciliação/gate exigidos.

## 43. Failure Injection

Testes intencionais de rehearsal devem provar failure behavior, idempotência e recovery; não são executados nesta etapa.

| Falha injetada | Resultado a provar | Evidência |
| --- | --- | --- |
| Interrupção de DB load | Boundary seguro, retry sem duplicidade e target consistente | Transaction/load/registry report |
| Duplicate retry | Mesmo target/resultado ou erro determinístico | Idempotency record e counts |
| Worker crash | Lease/fencing impede conclusão obsoleta; retry seguro | Job attempts e conditional write |
| Storage copy interruption | Objeto fica `COPIED_UNVERIFIED`/quarantine, nunca `AVAILABLE` | Manifest/lifecycle e bytes |
| Checksum mismatch | Bloqueio/quarantine sem overwrite | Source/target checksum e reason code |
| Auth mapping failure | Identity não ativada; referências não ficam parcialmente falsas | Auth registry/reconciliation |
| Code collision | Quarantine e allocator inativo | Collision register e gate |
| Counter stale | `safe_next` usa emitidos/delta, não counter inferior | Code reconciliation |
| RLS failure | L4 falha, activation/expansion bloqueada | A/B result e kill switch |
| Cross-tenant attempt | Negação, observability e nenhuma alteração | Correlation e before/after |
| Network interruption | Retry/backoff sem duplicar efeitos | Attempts/idempotency/metrics |
| Audit failure | Operação crítica não confirma/commita | Audit failure contract |
| Registry failure | Target não fica órfão de provenance | Transaction/compensation evidence |
| Delta inconsistency | NO-GO e R1, sem cutover | Delta coverage/gate decision |

R4 Final Dress inclui as injeções críticas possíveis sem comprometer o ambiente; demais cenários podem ser demonstrados em R1–R3. Injeção nunca usa produção.

## 44. Manual Steps

### 44.1 Regra

Minimizar passos manuais. Todo passo futuro deve preencher:

| Campo | Conteúdo obrigatório |
| --- | --- |
| Step ID/version | Identidade imutável e fase/checkpoint |
| Owner/executor | Pessoa/função autorizada |
| Reviewer | Second person para passo crítico |
| Action | Comando/ação exatos, sem “corrigir se necessário” |
| Target/environment | Alvo inequívoco e validado |
| Preconditions | Estado requerido e gate anterior |
| Expected output | Resultado observável e critérios de sucesso/falha |
| Evidence | Saída protegida, correlation, timestamp e referência |
| Abort condition | Quando parar sem avançar |
| Recovery | Ação segura correspondente e owner |
| Approval | Classe necessária antes/depois |

### 44.2 Controle

- comandos são revisados e ensaiados no ambiente apropriado;
- nenhum passo contém secret inline ou alvo construído ambiguamente;
- executor lê de volta environment/release/target antes de confirmar;
- passos críticos exigem second-person verification;
- saída inesperada interrompe a sequência;
- ação improvisada em produção cria NO-GO/incidente, não uma exceção informal;
- todas as ações são correlacionadas ao Migration Run.

## 45. Separation of Duties

| Decisão/operação | Executor | Reviewer | Approver |
| --- | --- | --- | --- |
| Captura/snapshot | Data/Platform Operator | Data owner | Migration Lead |
| Mapping comum | Migration/Data Operator | Domain owner | Conforme rule class |
| Quarantine de negócio | Analyst | Domain/Data reviewer | Business owner quando material |
| Permission/Global Admin | Security/Platform operator | Security reviewer distinto | Platform authority competente |
| Artefato/release | Build/Release operator | Engineering reviewer | Release approver |
| Backup/restore | Operations operator | Data/Platform reviewer | Operations authority |
| Freeze/activation | Operations operator | Second person | Migration/Operations approver |
| GO/NO-GO | Migration Lead consolida | Cada owner de gate | Grupo de approvers; não uma única pessoa |
| Recovery R2–R4 | Incident operator | Security/Data/Operations | Incident authority + Business conforme impacto |

Quem executa tecnicamente não decide sozinho exceção de segurança, privilégio, Global Admin, quarantine material, GO, produção ou retorno pós-write. Ausência de papel distinto onde exigido é `CUTOVER_BLOCKER`.

## 46. Communication

O plano define categorias, triggers, owner e audience; textos são preparados fora deste documento.

| Categoria | Trigger | Owner | Audience |
| --- | --- | --- | --- |
| Maintenance start | P7 autorizado e freeze iniciado | Operations/Communication owner | Usuários/stakeholders do escopo |
| Delay | Janela/etapa ultrapassa threshold sem risco imediato | Migration Lead | Stakeholders operacionais e approvers |
| NO-GO | P11 rejeita ou R1 é acionado | Migration Lead/Operations | Stakeholders, suporte e liderança aplicável |
| Activation | CP8 registrado | Operations/Product owner | Usuários/stakeholders do tenant/onda |
| Incident | Segurança/dado/indisponibilidade material | Incident Commander | Security, Operations, liderança, afetados conforme política |
| Recovery | Return/Roll Forward aprovado e iniciado/concluído | Incident Commander | Mesmo público do incidente, ajustado ao impacto |
| Stabilization complete | CP10 aprovado | Operations/Business owner | Stakeholders do rollout |

Comunicação não substitui evidence/gate. Conteúdo não expõe tenant, incidente, PII ou detalhes de segurança além do autorizado.

## 47. Incident Handling

### 47.1 Security incident

Qualquer evidência confirmada de cross-tenant read/write, privilege escalation, unauthorized platform action ou critical evidence exposure deve:

1. parar expansão e a sequência afetada;
2. ativar kill switch/isolation/read-only;
3. preservar logs, snapshots, correlation e evidence;
4. classificar blast radius, tenants, domínios e período;
5. invalidar o gate/checkpoint afetado;
6. invocar Recovery Decision Tree e classe R2–R4;
7. executar correção versionada e reconciliação completa do impacto;
8. exigir novo security gate antes de continuar.

É proibido corrigir silenciosamente em produção e prosseguir com a aprovação antiga.

### 47.2 Data incident

Para missing critical records, broken relationships, wrong tenant, wrong code, wrong actor ou missing evidence file:

- parar/isolar o fluxo e writer afetados;
- preservar estado source/target e evidence;
- classificar criticidade, registros, tenants, dependências e janela;
- não executar bulk correction sem rule/version/provenance;
- avaliar Auth, codes, Storage, History/Audit e externals correlatos;
- aplicar Roll Forward ou recovery aprovado;
- reexecutar L1–L4 e gates afetados.

### 47.3 Operação degradada

Falha operacional sem corrupção/segurança pode permitir isolamento de componente e Roll Forward, desde que single writer, integridade e segurança permaneçam provados. A decisão e o modo degradado têm owner, limite, observabilidade e exit criteria.

## 48. GO/NO-GO Matrix

`Resultado` permanece `PENDING/REVALIDATION_REQUIRED` até futura execução; este documento não concede GO.

| Gate | Categoria | Critério | Evidência | Owner | Blocking | Waiver | Resultado |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Snapshot consistency | DATA | Database/Auth/Storage ligados por Consistency Envelope sem gap | CP1 bundle, manifests, boundaries | Data/Platform | Sim | Não para gap crítico | PENDING |
| Source drift | DATA/INFRA | Drift crítico zerado ou incorporado e revalidado | Drift report/version | Platform/Data | Sim | Não para security/writer drift | REVALIDATION_REQUIRED |
| Tenant reconciliation | DATA/SECURITY | Cada registro/tenant fecha sem cross-tenant indevido | L1–L4 por tenant | Data/Security | Sim | Não | PENDING |
| Auth | AUTH | Path A/B, lifecycle, login/activation/recovery aprovados | Auth manifest/tests | Identity owner | Sim | Não se inseguro | PENDING |
| Membership | AUTH/SECURITY | Usuário comum ativo com exatamente um tenant; ausências classificadas | Membership report/tests | Identity/Security | Sim | Não para acesso ativo ambíguo | PENDING |
| Permissions | SECURITY | `V2 privilege <= V1 proven`, exact combinations e default deny | Privilege comparison/A-B | Security | Sim | Não para expansion | PENDING |
| Global Admin | SECURITY | Lista nominal, capabilities mínimas, target/Audit | Platform approval/tests | Platform Security | Sim | Não | PENDING |
| Codes | CODES | Emitidos/aliases/duplicates/counters/delta reconciliados | Code report | Data/Domain | Sim | Não para reuse | PENDING |
| Relationships | DATA | FKs/cardinalities/parents/children fecham por tenant | L2 report | Data/Domain | Sim | Não para critical | PENDING |
| History | DATA/GOV | Eventos classificados; actors/suppressions contabilizados | History report | Data/Domain | Sim para crítico | Limitado fora da operação | PENDING |
| Provenance | GOVERNANCE | Registry bidirecional completo e consultável | Registry tests/report | Migration Lead | Sim | Não para crítico | PENDING |
| Audit | SECURITY/GOV | Append-only e failure contract aprovados | Audit tests/events | Security | Sim | Não | PENDING |
| Storage | STORAGE/DATA | Metadata↔object↔parent↔tenant↔integrity↔availability fecha | Storage/bytes report | Storage/Data | Sim | Não para evidência crítica | PENDING |
| RLS A/B | SECURITY | Todos os casos positivos/negativos e interleaved passam | Security suite | Security | Sim | Não | PENDING |
| Functional smoke | APPLICATION | Fluxos MVP controlados passam no mesmo release | Smoke report | QA/Domain | Sim | Limitado conforme criticidade | PENDING |
| Backup | RECOVERY | Backup correto, íntegro, protegido e retido | Backup identity/report | Operations | Sim | Não sem recovery coverage | PENDING |
| Restore | RECOVERY | Restore ensaiado, medido e reconciliado | Restore rehearsal | Operations/Data | Sim | Não | PENDING |
| Observability | OBSERVABILITY | Dashboards, alerts, correlation e privacy validados | Monitoring tests | Operations/Security | Sim | Não | PENDING |
| Workers | INFRA/APPLICATION | Allowlist, reread, idempotency, lease/fencing e health passam | Worker tests/metrics | Platform | Sim se requerido | Limitado somente se serviço fora do escopo | PENDING |
| Scheduler | INFRA/APPLICATION | Occurrence uniqueness, cursor e retry aprovados | Scheduler/concurrency tests | Platform/Domain | Sim se ativo | Não para duplicate OS risk | PENDING |
| Delta | DATA | Cobertura de todos os writers/inserts/updates/deletes e cutoffs | Delta manifest/report | Data/Platform | Sim | Não | PENDING |
| safe_next | CODES | Valor final maior que base/counters/delta/target allocations | Final code report | Data/Domain | Sim | Não | PENDING |
| Recovery rehearsal | RECOVERY | Classes aplicáveis, kill switch e decision tree demonstrados | R3/R4 evidence | Operations/Security | Sim | Não | PENDING |
| Quarantine | DATA/GOV | Blocking=0; demais itens com owner/evidence/disposition | Quarantine report | Data/Business/Security | Sim quando blocking | Conforme classe, nunca proibidos | PENDING |
| Target health/capacity | INFRA | Saúde e capacidade compatíveis com métricas R4 | Health/capacity report | Platform/Operations | Sim | Limitado e explícito | PENDING |
| Business operations | BUSINESS | Janela, suporte, owners e acceptance prontos | Roster/approval | Business/Operations | Sim | Limitado | PENDING |

GO exige todos os gates bloqueantes `APPROVED`, sem `PENDING`, `FAILED` ou `REVALIDATION_REQUIRED` remanescente. Um `N/A` futuro exige justificativa e approver; não é usado para evitar teste aplicável.

## 49. Recovery Decision Tree

```text
Failure detected
|
+-- V2 activated?
|   |
|   +-- NO
|   |   |
|   |   +-- Source frozen?
|   |       +-- NO  → R0: abort run; V1 remains writer
|   |       +-- YES → R1: preserve evidence; restore V1 writers;
|   |                 reconcile window; plan a new run
|   |
|   +-- YES
|       |
|       +-- V2 accepted any write or external effect?
|           |
|           +-- NO / positively proven
|           |   → R2: activate kill switch; verify DB/Auth/Storage/jobs;
|           |     evaluate controlled return; re-gate
|           |
|           +-- YES or UNKNOWN
|               |
|               +-- Security exposure or data corruption?
|               |   → isolate tenant/domain → read-only/kill switch
|               |     → preserve evidence → classify R3/R4
|               |     → prefer roll-forward or controlled recovery
|               |
|               +-- Operational failure only, integrity/security proven?
|                   → degrade/isolate component
|                     → keep a single writer
|                     → roll-forward preferred
|                     → reconcile and re-gate
|
+-- At any branch: can all source/target/Auth/Storage/codes/external
    states be proven and reconciled?
    +-- NO  → remain isolated/read-only; escalate decision authority
    +-- YES → execute only the approved recovery path
```

`UNKNOWN` após ativação é tratado conservadoramente como possível write/effect até prova contrária. Nem todo ramo permite Return to V1.

## 50. Blockers

### 50.1 DESIGN_BLOCKERS

| Blocker | Evidência para resolver | Bloqueia |
| --- | --- | --- |
| Schema/contratos físicos de Migration Run, registry, quarantine e evidence bundle | Modelo aprovado, invariants, consultas bidirecionais e retention | Tooling/LOAD |
| Technical Audit e failure contract | Append-only, transactional behavior e tests | Operações críticas |
| Auth Path A/B e modelo Legacy/Unresolved Actor | Provider capability, mapping/references e UX/security contract | Identity/History load |
| Matriz Resource + Action + Scope e baselines | Catálogo técnico, definitions OWN/ASSIGNED/TEAM e enforcement | Permission load |
| Entitlements iniciais e platform identity governance | Config/aprovação de plataforma | ACTIVATE |
| Mapping rules/taxonomies/timezone/occurrence identity | Dicionários versionados e domain approval | MAP/Preventive load |
| Delta por domínio/writer, inclusive deletes | Mecanismo que prova insert/update/delete coverage | Final reconciliation |
| Safe-next/allocator e namespace/ano | Algoritmo, atomicidade, coexistência e concurrency tests | Allocator/cutover |
| Storage copy/finalize/integrity tiers/key identity | Lifecycle, idempotência, checksum policy e authorization | File load/availability |
| Backup/restore/recovery playbooks R0–R4 | Procedimentos implementados e rehearsed | GO |
| Observability/kill switches/provider choices | Dashboards, privacy, access e tests | Rehearsal/cutover |
| Tolerâncias/criticidade por domínio | Owner, rule e approval | Reconciliation/GO |

### 50.2 DATA_BLOCKERS

Todos exigem revalidação remota futura:

- schema/data/Auth/Storage/releases reais ainda não inventariados no run;
- tenant mappings e registros sem tenant/cross-tenant;
- Auth sem profile, profile sem Auth, UUID/e-mail/provider/lifecycle incompatíveis;
- membership zero/múltipla e usuários ativos ambíguos;
- candidatos a Global Admin sem decisão nominal;
- legacy permission actions/scopes/bypasses sem mapeamento seguro;
- `operacoes`/lojas/localização/categorias/taxonomias ambíguas;
- códigos duplicados, aliases conflitantes, counters/sequences remotos;
- Request/OS/Plan/Asset/Supplier parents, cardinalidades e status/tipos incompatíveis;
- executor versus responsável e autoria nula/cross-tenant;
- occurrence preventiva duplicada/timezone/cursor incoerente;
- History writers/events/duplicates reais não classificados;
- Storage objects/metadata/parents/tenant/MIME/checksums/retention;
- uploads, Auth changes e writes posteriores ao snapshot base.

### 50.3 CUTOVER_BLOCKERS

- Consistency Envelope ou delta incapaz de cobrir todos os writers;
- source drift crítico não incorporado;
- `critical failed > 0` ou blocking quarantine aberta;
- falha de tenant isolation, RLS A/B, FK tenant-aware ou antiescalada;
- identity/membership/platform authority insegura;
- privilege expansion não aprovada;
- código/counter/allocator com possibilidade de reuse;
- relação/dado/evidência crítica perdida ou semanticamente incorreta;
- Audit/Provenance obrigatórios ausentes;
- Storage crítico não reconciliado/disponível com integridade;
- backup/restore/recovery/kill switch não demonstrados;
- artefato diferente do rehearsal ou digest desconhecido;
- target health/observability/workers/scheduler não aprovados;
- passo manual crítico sem owner/evidence/second-person verification;
- qualquer gate bloqueante sem aprovação ou ainda `REVALIDATION_REQUIRED`.

## 51. Readiness

O estado ao final documental da 10D é:

| Classificação | Itens |
| --- | --- |
| `READY_FOR_IMPLEMENTATION` | State machine/manifest conceituais do Migration Run; contratos P0–P15; checkpoints/evidence; quatro níveis de reconciliação; rehearsal progression; single-writer baseline; gate/recovery/report templates |
| `REQUIRES_DESIGN` | Schemas físicos, runtimes/tooling, Auth Path A/B implementation, permission matrix, delta mechanisms, allocator, Storage protocol, Audit/provenance persistence, observability e recovery commands |
| `REQUIRES_REMOTE_REVALIDATION` | Schema/data/Auth/Storage/RLS/grants/functions/triggers/Edge Functions/writers/codes/volumes/quality e release remotos |
| `REQUIRES_BUSINESS_DECISION` | Tenant/record classifications ambíguas, initial entitlements, platform identities, taxonomies, permitted waivers, criticidade/tolerâncias, retention/legal e business acceptance |
| `CUTOVER_ONLY` | Janela/thresholds, source freeze boundaries, delta final, `safe_next` final, GO approvals, activation, CP8–CP10 e communication timestamps |

A 10D está pronta como contrato documental para orientar implementação e rehearsal. Isso não significa que os componentes listados estejam implementados ou que a V2 esteja pronta para produção.

## 52. Inputs 10E

A Etapa 10E deve receber:

1. estratégia 10A;
2. mappings/regras 10B;
3. componentes críticos 10C;
4. este runbook 10D;
5. `DESIGN_BLOCKERS`, `DATA_BLOCKERS` e `CUTOVER_BLOCKERS` consolidados;
6. dependências e ordem de pais/filhos/ondas;
7. gates, checkpoints, evidence bundles e owners;
8. critérios de aceite L1–L4 e domínios críticos;
9. ondas de implementação e critérios de entrada/saída;
10. registry/quarantine/Audit/observability/recovery requirements;
11. rehearsal progression e failure injection suite;
12. snapshot/Consistency Envelope/freeze/delta contracts;
13. artefato/release lifecycle e imutabilidade;
14. itens `READY_FOR_IMPLEMENTATION`, `REQUIRES_DESIGN`, `REQUIRES_REMOTE_REVALIDATION`, `REQUIRES_BUSINESS_DECISION` e `CUTOVER_ONLY`;
15. itens deferidos e fora de escopo;
16. cutover prerequisites e matriz GO/NO-GO.

10E deverá transformar esse conjunto em plano técnico consolidado, executável por fases pequenas, sem reabrir decisões `CLOSED`, antecipar FUTURE ou tratar documentação como implementação pronta.

## 53. Decisions Deferred

Permanecem deliberadamente abertas, sem reduzir invariantes:

- schemas físicos de Migration Run, registry, quarantine, evidence, Audit e staging;
- runtime/tooling de snapshot, ETL, orchestration e manifests;
- mecanismos exatos de snapshot/delta por domínio e source;
- estratégia/provider-specific para Auth UUID/password/session/MFA/invitation;
- representação física e UX de Legacy/Unresolved Actor;
- matriz final Resource/Action/Scope, baselines, overrides e sensitive projections;
- platform identity list e initial entitlements;
- dicionários finais de enums/taxonomias/status e classificação de operações/lojas;
- occurrence key/timezone e cursor preventivo físicos;
- política de códigos ausentes/aliases e allocator/counter físico;
- quantity/classes de buckets, target key, checksum e integrity tier por arquivo;
- provider/topologia de workers, observability, hosting e feature/config allowlist;
- tolerâncias por domínio, severity e owner;
- janela, maximum duration, abort thresholds e staffing;
- estratégia exata de reverse delta/Return to V1 depois de writes;
- thresholds, coorte, duração e ordem do rollout Serena;
- retention legal, incident hold e elegibilidade de purge;
- approval final de qualquer `APPROVED_DISCARD` ou waiver permitido.

Ausência de decisão não autoriza fallback, privilégio, delete, dual-write, associação, ator, default ou ativação.

## 54. Conclusion

### 54.1 Resultado da revisão adversarial

| Risco procurado | Tratamento neste runbook |
| --- | --- |
| “Backup existe” sem restore test | Backup só aprova com restore ensaiado, medido e reconciliado |
| LOAD tratado como sucesso | LOAD termina em CP2; ativação exige CP3–CP7 |
| Count tratado como reconciliação suficiente | L1 é acompanhado por L2 Relationship, L3 Semantic e L4 Security |
| Snapshot DB tratado como Auth/Storage | Consistency Envelope exige três fontes e boundaries próprios |
| Freeze de UI tratado como todos os writers | Inventário inclui APIs, workers, scheduler, Storage, Auth e admin/manual |
| Timestamp usado sem confiabilidade | Estratégia é por domínio; sem timestamp confiável usa outro mecanismo/blocker |
| Delete propagado automaticamente | Todo delete é classificado; unknown vai a quarantine |
| `safe_next` calculado antes do delta | Valor final só existe após P9/CP6 |
| Dual-write V1/V2 implícito | Baseline single writer explícita |
| Rollback como simples DB restore | Recovery R0–R4 cobre Auth, Storage, codes e external effects |
| Return to V1 pós-write sem reverse strategy | Point of No Simple Return e condições de retorno explícitos |
| Código reutilizado após recovery | Todo código V2 emitido/reservado permanece consumido |
| Efeito externo considerado reversível | at-least-once + idempotency + reconciliation/compensation |
| Serena tratada como STAGING | Serena é tenant piloto em PRODUCTION |
| Artefato diferente no rehearsal/cutover | Manifest/digests iguais; mudança exige nova validação |
| Waiver para cross-tenant | Explicitamente proibido |
| NO-GO tratado como exceção impossível | Saída normal de P11 com R1 e novo run |
| Ação manual sem owner/evidence | Template exige owner, expected output, evidence e second person |
| Recovery que apaga evidência | Runs/checkpoints/bundles são imutáveis; correções são adendas |
| Migração fabrica ator | Classes Legacy/Unresolved/Technical preservam ausência/origem |
| Arquivo crítico disponível sem integridade | `AVAILABLE` exige parent, tenant, integrity, provenance e authorization |
| V2 ativa antes da reconciliação final | CP6/CP7 precedem CP8 obrigatoriamente |

Nenhuma ocorrência conflitante foi mantida. Os pontos que dependem de implementação, provider, negócio ou remoto estão classificados como blockers, decisões deferidas ou `REVALIDATION_REQUIRED`.

### 54.2 Fechamento

O runbook estabelece uma cadeia auditável de Migration Runs, artefatos imutáveis, snapshots relacionados por Consistency Envelope, mapping sem fallback, carga idempotente, reconciliação L1–L4, rehearsals progressivos, freeze completo, delta final, GO/NO-GO, single writer, cutover, verificação, estabilização e retenção da V1.

O ponto de não retorno simples ocorre quando a V2 aceita a primeira escrita ou efeito exclusivo. A partir daí, recovery exige reconciliação distribuída e Roll Forward tende a ser mais seguro; Return to V1 não é assumido possível. Recovery R0–R4, checkpoints CP0–CP10, evidence bundles, failure injection e separação de funções impedem que velocidade substitua prova.

Esta Etapa 10D é somente documentação. Nenhuma migração real, rehearsal, acesso remoto, backup, restore, deploy ou cutover foi realizado, e nenhuma declaração de prontidão para produção é feita.
