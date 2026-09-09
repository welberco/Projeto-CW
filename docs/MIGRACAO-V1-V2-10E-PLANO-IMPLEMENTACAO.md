# Plano Técnico Consolidado e Ondas de Implementação V1 → V2 — Etapa 10E

| Campo | Valor |
| --- | --- |
| Projeto | CW ERP / CW Manutenção |
| Etapa | Fase A — Etapa 10E |
| Natureza | Implementation Roadmap documental consolidado |
| Branch de referência | `develop/v2` |
| HEAD de entrada | `5092f15` |
| Estado das fontes | Arquitetura `FROZEN`; 10A, 10B, 10C e 10D aprovadas |
| Execução nesta etapa | Somente documentação; nenhum código, DDL, migration, ETL, acesso remoto, rehearsal, deploy ou cutover |
| Estado produzido | `ARCHITECTURE_PLANNING_COMPLETE` após aprovação humana deste documento |

## 1. Objetivo

Converter a arquitetura congelada e os contratos aprovados de migração das Etapas 10A–10D em um roadmap ordenado, implementável, testável e verificável para a reconstrução da V2.

O plano define ondas, dependências, entregáveis, gates, testes, security reviews, revalidações remotas, prontidão de migração, blockers, checkpoints, esforço, risco e Definition of Done. Cada onda futura seguirá obrigatoriamente:

```text
ARCHITECT
→ MODEL
→ IMPLEMENT
→ TEST
→ SECURITY REVIEW
→ COMMIT
→ NEXT WAVE
```

Uma onda não avança porque o código compila ou a UI parece pronta. Ela avança somente quando seu gate principal possui evidência objetiva e nenhum blocker incompatível permanece aberto.

## 2. Estado de entrada

Pré-checagem executada antes da criação deste arquivo:

| Verificação | Resultado |
| --- | --- |
| Branch | `develop/v2` |
| HEAD | `5092f15 docs: definir rehearsal cutover e recovery da migracao` |
| Worktree | Limpa |
| Arquivo de saída antes da etapa | Inexistente, conforme esperado |

Estado documental de entrada:

- Arquitetura Técnica V2: `FROZEN BASELINE`;
- Etapas 10A, 10B, 10C e 10D: aprovadas e não reabertas;
- V1: preservada pela tag `v1-legacy` e pela branch `main` enquanto a V2 evolui em `develop/v2`;
- estado remoto: não consultado nesta etapa e integralmente `REVALIDATION_REQUIRED` quando dele depender uma decisão futura;
- implementação, migração, rehearsal e produção: ainda não iniciados por este documento.

Não foi encontrada contradição real entre as fontes que exigisse reabrir decisão `CLOSED`. As escolhas concretas de frontend exigidas para este roadmap são concretizações `IMPLEMENTATION-DEPENDENT`, não alterações dos invariantes congelados.

## 3. Fontes e precedência

Foram consideradas integralmente:

1. `PRODUCT_SPEC.md`;
2. `AGENTS.md`;
3. `docs/ARQUITETURA-TECNICA-V2.md`;
4. `docs/INVENTARIO-V1.md`;
5. `docs/GAP-ANALYSIS-V1-V2.md`;
6. `docs/MIGRACAO-V1-V2-10A-ESTRATEGIA.md`;
7. `docs/MIGRACAO-V1-V2-10B-MAPEAMENTO.md`;
8. `docs/MIGRACAO-V1-V2-10C-CRITICOS.md`;
9. `docs/MIGRACAO-V1-V2-10D-CUTOVER-RECOVERY.md`.

Precedência aplicada:

```text
PRODUCT_SPEC
> ARQUITETURA-TECNICA-V2
> 10A
> 10B
> 10C
> 10D
> INVENTARIO-V1
> GAP
```

`AGENTS.md` governa a forma de trabalho. Código V1 e SQLs legados são evidência, não norma V2 nem prova do remoto. Decisão `CLOSED` não pode ser reinterpretada por uma onda; conflito futuro vira `ARCHITECTURE_BLOCKER` e segue change control.

## 4. Princípios

1. Segurança e isolamento tenant são fundação, não hardening tardio.
2. Toda tabela tenant-owned recebe RLS, integridade tenant-aware e testes Tenant A/B desde a primeira ocorrência.
3. Perfil é baseline; autoridade efetiva usa `Resource + Action + Scope` e override individual exato.
4. UI guards (`CapabilityGate`, `Can` ou `ActionVisibility`) orientam UX; RLS, commands e backend decidem.
5. Tenant, ator, autoria e autoridade não são aceitos do payload como fatos.
6. Commands críticos reautorizam dentro da transação após estabilizar somente os fatos relevantes.
7. Audit, History, Comment, Notification e Alert permanecem mecanismos distintos.
8. Domain mutation, Audit/History aplicável e Outbox pertencem ao mesmo boundary transacional.
9. Storage usa `reserve → upload → finalize → AVAILABLE`; path e signed URL não são autoridade.
10. Relações tenant-owned usam constraint composta equivalente a `(tenant_id, parent_id) → (tenant_id, id)`.
11. UUID interno é gerado pelo banco; código humano é separado, tenant-aware e alocado atomicamente.
12. Request e OS permanecem independentes; concluir a última OS apenas pode sugerir encerramento.
13. Preventiva preserva `Plano → Programação → Ocorrência → OS Preventiva → Execução`.
14. Observabilidade começa nas primeiras ondas críticas e é consolidada no hardening.
15. Foundations são introduzidas na menor extensão necessária e imediatamente exercitadas por uma capacidade real.
16. Itens V2 Complementar ou Futuro não são promovidos para desbloquear conveniência técnica.
17. Migração usa registry, quarantine, provenance, idempotência e reconciliação; `LOAD != ACTIVATE`.
18. Mesmos artefatos/digests são promovidos de TEST para STAGING e PRODUCTION; RC não é rebuild.
19. Após cutover existe um único writer por `tenant + domínio`.
20. NO-GO, isolamento e Roll Forward são resultados operacionais legítimos; backup sem restore demonstrado não é gate.

## 5. Critérios de ordenação

A prioridade de cada onda é calculada por:

```text
DEPENDENCY
+ SECURITY FOUNDATION
+ DATA INTEGRITY
+ DOMAIN DEPENDENCY
+ MIGRATION REQUIREMENTS
+ TESTABILITY
+ OPERABILITY
```

Critérios práticos:

- nenhum domínio tenant-owned antecede identidade de tenant, membership e RLS aplicável;
- autorização antecede actions de domínio, mas seu catálogo cresce apenas quando uma vertical slice exige recursos reais;
- Audit/History/Outbox antecedem transitions críticas de Request e OS;
- cadastros estruturais antecedem Ativo, Fornecedor, Request, OS e Preventiva;
- Storage é introduzido com o primeiro consumidor real e endurecido antes do piloto;
- Request antecede OS vinculada, mas OS avulsa permanece suportada;
- Ativo e OS antecedem Preventiva; fontes operacionais antecedem Calendar, Overview, Dashboard e Reports;
- schema e domínios V2 estáveis antecedem migration tooling; tooling antecede rehearsals; R4 antecede cutover;
- revalidação remota acontece antes da onda que precisa fechar a decisão, não como tarefa genérica no final.

## 6. Estratégia horizontal × vertical

O roadmap evita tanto uma foundation horizontal gigantesca quanto slices que duplicam infraestrutura.

| Capacidade horizontal | Primeira introdução | Primeira prova vertical | Evolução posterior |
| --- | --- | --- | --- |
| App shell, router, typed boundaries e test harness | W0 | Rotas técnicas e estados de aplicação | Cada domínio adiciona somente sua rota/contrato |
| Migrations e PostgreSQL local compatível | W0 | Baseline reconstruível | W1 introduz o primeiro modelo tenant-owned |
| Auth, session e tenant context | W1 | Empresa/Minha Conta e troca de contexto | W2 aplica capability e RLS |
| Authorization/RLS | W2 | Tenant/User/Membership e casos A/B | Cada domínio acrescenta Resource/Action/Scope próprio |
| Commands e Audit crítico | W1 em forma mínima e reutilizável | Lifecycle/tenant administration | W2 usa em permissions; W3 consolida o kernel compartilhado |
| History/Outbox e Audit compartilhado | W3 | Mudanças administrativas críticas já auditadas | W7–W11 exercitam transitions e eventos operacionais |
| UI compartilhada | W0/W4 | Cadastros estruturais | Listas e formulários de domínio especializam contratos |
| Storage | W5 | Fotos/documentos de Ativo | W6–W10 reutilizam para Fornecedor, Request, OS e checklist |
| Comments | W7 | Request | W8/W9 reutilizam em OS |
| Worker/scheduler | W3/W10 | Outbox técnico e ocorrência preventiva | W11 notificações/alertas e W14 hardening |
| Observabilidade | W0/W3 | build, commands e workers correlacionados | W14 consolida SLI, health, release e incident response |
| Migration registry/quarantine | W15 | dry-run/mapping sem carga real | W16 rehearsals e W17 cutover |

Cada wave fecha uma capacidade verificável. Pastas, tabelas e componentes são meios, não resultados de onda.

## 7. Roadmap consolidado

O roadmap final possui 18 ondas, de `W0` a `W17`:

| Wave | Capacidade verificável | Gate principal |
| --- | --- | --- |
| W0 | Fundação de engenharia reproduzível | `FOUNDATION_READY` |
| W1 | Identidade, tenant e membership funcionais | `TENANT_READY` + `AUTH_READY` |
| W2 | Autorização efetiva e isolamento RLS A/B | `AUTHORIZATION_READY` |
| W3 | Commands, Audit, History e Outbox transacionais | `AUDIT_READY` |
| W4 | Cadastros estruturais e scope TEAM utilizáveis | `CADASTRO_READY` |
| W5 | Ativos e Storage foundation autorizados | `ASSET_READY` + `STORAGE_FOUNDATION_READY` |
| W6 | Fornecedores canônicos e documentos reutilizando Storage | `SUPPLIER_READY` |
| W7 | Requests completas, comentários e códigos anuais | `REQUEST_READY` |
| W8 | OS núcleo: criação, planejamento, atribuição e execução | `OS_CORE_READY` |
| W9 | OS completa: pausa, validação, checklist, evidências e relação Request × OS | `OS_READY` |
| W10 | Preventiva idempotente de Plano a Execução | `PREVENTIVE_READY` |
| W11 | Calendar, Notifications, Alerts e Overview autorizados | `OPERATIONAL_ATTENTION_READY` |
| W12 | Dashboard, Reports e PDF individual de OS autorizados | `REPORTING_READY` |
| W13 | Global Admin e operações de plataforma separadas | `PLATFORM_READY` |
| W14 | Hardening operacional, release e observabilidade | `OPERATIONS_READY` + `SCHEMA_READY` + `SECURITY_READY` |
| W15 | Tooling de migração 10A–10D implementado, sem migrar produção | `MIGRATION_TOOLING_READY` |
| W16 | R1–R4 e prontidão objetiva de cutover | `REHEARSAL_READY` + `CUTOVER_READY` |
| W17 | Cutover Serena, estabilização e prontidão do segundo tenant | `PILOT_READY` + `SECOND_TENANT_READY` |

## 8. Dependency Graph

```text
W0 Engineering Foundation
 |
 v
W1 Identity / Tenant / Membership
 |
 v
W2 Authorization / RLS -------------------------------+
 |                                                     |
 v                                                     |
W3 Commands / Audit / History / Outbox                 |
 |                                                     |
 v                                                     |
W4 Cadastros / Teams                                   |
 |                                                     |
 +------------------+------------------+               |
 |                  |                  |               |
 v                  v                  |               |
W5 Assets+Files --> W6 Suppliers ------+               |
 |                  |                                  |
 +------------------+                                  |
 |                                                     |
 v                                                     |
W7 Requests / Comments                                 |
 |                                                     |
 v                                                     |
W8 OS Core                                             |
 |                                                     |
 v                                                     |
W9 OS Completion / Validation / Checklist / Evidence   |
 |                                                     |
 v                                                     |
W10 Preventive                                         |
 |                                                     |
 +------------------------+                            |
 |                        |                            |
 v                        v                            |
W11 Calendar / Attention  W12 Dashboard / Reports <----+
 |                        |
 +------------+-----------+
              |
              v
W13 Platform Operations
              |
              v
W14 Operational / Release Hardening
              |
              v
W15 Migration Tooling
              |
              v
W16 R1 → R2 → R3 → R4 / Cutover Readiness
              |
              v
W17 Serena Cutover → Stabilization → Second Tenant Gate
```

Dependências transversais:

- W2–W17 dependem de testes A/B e integridade tenant-aware;
- W3–W17 dependem de correlação e Audit proporcional;
- W5–W17 dependem do protocolo Storage para qualquer arquivo;
- W10–W17 dependem de worker/scheduler allowlisted, idempotente e com fencing;
- W15–W17 dependem das revalidações remotas RV-01–RV-08;
- W17 depende de todos os gates bloqueantes, R4, restore e GO humano.

## 9. Critical Path

### 9.1 Caminho crítico do MVP operacional

```text
W0 → W1 → W2 → W3 → W4 → W5/W6 → W7 → W8 → W9
   → W10 → W11 → W12 → W14
```

W5 e W6 podem ter preparação interna parcialmente paralela após W4, mas W7 não fecha enquanto os contratos estruturais e seletores consumidos não estiverem estáveis. W13 não bloqueia a demonstração local do fluxo operacional, porém bloqueia operação de plataforma e piloto em produção.

### 9.2 Caminho crítico da migração V1

```text
W0 → W1 → W2 → W3 → W4 → W5–W12 → W14 → W15 → W16 → W17
```

W15 não começa com modelo V2 instável. W16 não começa sem tooling, ambientes, restore e evidências. W17 não começa sem R4 aprovado e revalidação final.

### 9.3 Caminho crítico do piloto Serena

```text
MVP operacional + W13 + W14 + W15 + W16 + GO humano → W17
```

### 9.4 Classificações

- `MVP_CRITICAL`: W0–W12 e W14.
- `MIGRATION_CRITICAL`: W0–W10 e W13–W17; W11–W12 participam quando suas fontes/configurações fazem parte do escopo migrado ou do smoke.
- `PILOT_CRITICAL`: W0–W17, exceto capacidades explicitamente não ativadas no escopo do piloto mediante decisão documentada; segurança estrutural nunca é excluída.
- `POST_PILOT`: parte final de W17, especialmente `SECOND_TENANT_READY`, expansão gradual e hardening baseado em evidência do piloto.

### 9.5 Primeiro MVP operacional

O escopo funcional obrigatório do primeiro MVP é o conjunto W0–W12: foundation, identidade/tenant, autorização/RLS, Audit/History/Outbox, cadastros essenciais, Ativos, Fornecedores, Requests, OS, Preventive, Calendar/Overview/Notifications/Alerts e Dashboard/Reports básicos. Segurança estrutural, A/B, Audit crítico, Storage authorization e integridade tenant-aware já fazem parte dessas waves e não aguardam hardening.

Para o MVP ser operacionalmente liberável, W14 também precisa fechar `SCHEMA_READY`, `SECURITY_READY` e `OPERATIONS_READY`. Para o piloto Serena com migração da V1, são ainda obrigatórios W13, W15, W16 e o estágio pré-ativação de W17. O estágio pós-CP9/CP10 e `SECOND_TENANT_READY` é pós-piloto. Assim:

| Camada | Conteúdo |
| --- | --- |
| MVP obrigatório | W0–W12, com todos os controles de segurança incorporados |
| Hardening necessário antes de produção | W13–W16; plataforma, release/observabilidade, migration tooling, restore e R4 |
| Pós-piloto | W17 estágio B: estabilização aceita, evidência multi-tenant e expansão gradual |

## 10. Macro Fases

| Fase futura | Ondas | Resultado |
| --- | --- | --- |
| FASE B — Foundation | W0 | Toolchain, app shell, router, test harness e migrations reproduzíveis |
| FASE C — Identity & Multitenancy | W1 | Auth/session/tenant/membership e configurações essenciais |
| FASE D — Authorization & Security | W2–W3 | RLS/capabilities, commands, Audit, History e Outbox |
| FASE E — Shared Domains | W4–W6 | Cadastros, Ativos, Fornecedores e Storage reutilizável |
| FASE F — Maintenance Core | W7–W9 | Requests e OS completas |
| FASE G — Preventive & Scheduling | W10 | Preventiva e scheduler idempotente |
| FASE H — Collaboration & Reporting | W11–W12 | Attention surfaces, Dashboard e Reports |
| FASE I — Platform & Operational Hardening | W13–W14 | Global Admin, release, observabilidade, segurança e operação |
| FASE J — Migration Tooling | W15 | Contratos 10A–10D executáveis em ambiente controlado |
| FASE K — Rehearsal | W16 | R1–R4 e `CUTOVER_READY` |
| FASE L — Serena Pilot | W17, estágio A | Cutover e piloto no mesmo produto/produção |
| FASE M — Stabilization & Expansion | W17, estágio B | CP10 e prontidão do segundo tenant |

## 11. Waves detalhadas

### W0 — Fundação de engenharia reproduzível

| Campo | Definição |
| --- | --- |
| Wave ID | `W0` |
| Nome | Fundação de engenharia reproduzível |
| Objetivo | Entregar uma aplicação e um banco local reconstruíveis, com boundaries tipados, rotas profundas e harness de testes, sem regra de domínio prematura. |
| Dependências | Arquitetura congelada e aprovação da 10E. |
| Escopo | React, TypeScript strict, Vite, React Router Data Mode/`createBrowserRouter`, TanStack Query, React Hook Form, Zod, Supabase JS typed client, shadcn/ui, Radix, Tailwind/CSS variables, Vitest, React Testing Library, Playwright; configuração por ambiente; migrations locais; estrutura mínima `src/app`, `src/infrastructure`, `src/shared`, `src/test` e módulos somente quando houver conteúdo; error/correlation/release identity básicos. |
| Fora de escopo | Entidades tenant-owned, permissões de negócio, domínio operacional, Redux/Zustand, generic CRUD repository, deploy e migração de dados. |
| Database | Harness PostgreSQL/Supabase local compatível, cadeia de migrations vazia/baseline reconstruível, geração de `database.types.ts` quando houver schema. |
| Backend/Commands | Contratos de query/command e erro, sem commands de domínio. |
| Frontend | App shell técnico; rotas `/e/:tenantRef/*` e `/plataforma/*` como boundaries, tratando `tenantRef` como seletor opaco; estados de loading/error/not-found/no-permission; nenhuma page acessa Supabase diretamente. |
| Security | Secrets externos; CSP e supply-chain entram no backlog verificável; conteúdo não confiável renderizado com segurança; UI não assume autorização. |
| Storage | N/A; apenas boundary de configuração sem bucket ou protocolo. |
| Async | N/A; contrato de correlação preparado. |
| Observability | Release/build identity, erro seguro, correlation ID e logging local mínimo. |
| Migration impact | Estabelece migrations imutáveis após publicação, tipos e compatibilidade exigidos por todas as ondas; não toca V1. |
| Deliverables | Aplicação executável; router/deep links; boundary Supabase tipada; lint/type/build/test scripts; harness unit/component/E2E e DB local; convenções de diretório e imports. |
| Tests | Build, typecheck, lint, unit de configuração/erro, component smoke, deep-link/refresh/back/forward, Playwright smoke, reconstrução do DB local do zero. |
| Negative tests | Secret ausente; config inválida; rota desconhecida; erro seguro sem stack/dado sensível; page proibida de importar cliente Supabase direto por regra estática apropriada. |
| Entry criteria | 10E aprovada; branch correta; worktree limpa; decisões de package versions/licenças registradas. |
| Exit criteria | Todos os checks locais passam; app e DB reconstruíveis; rota profunda funciona; boundaries tipados e documentação mínima existem. |
| Blockers | `IB-01` incompatibilidade de toolchain; `DD-01` escolha de hosting não bloqueia local, mas precisa respeitar deep links futuramente. |
| Remote revalidation | N/A para fechar W0; nenhuma consulta remota. |
| Rollback/recovery relevance | Mudanças pequenas e reversíveis por commits coerentes; nenhuma migração publicada. |
| Definition of Done | `FOUNDATION_READY`, diff revisado, zero domínio prematuro, documentação e checks verdes. |

### W1 — Identidade, tenant e membership

| Campo | Definição |
| --- | --- |
| Wave ID | `W1` |
| Nome | Identidade, tenant e membership funcionais |
| Objetivo | Provar autenticação segura, tenant context e membership única para usuário comum, com Empresa/Minha Conta essenciais. |
| Dependências | `FOUNDATION_READY`. |
| Escopo | Auth identity, Application User, Tenant, Membership, lifecycle separado, session/context switching, tenant status, entitlements mínimos explícitos, dados gerais de Empresa e Minha Conta, convites administrativos sem cadastro público. |
| Fora de escopo | Permission catalog completo, Global Admin operacional, migração de usuários, billing/checkout e sessão transparente entre projetos não comprovada. |
| Database | UUID DB-generated; `tenant_id NOT NULL` onde aplicável; timestamps/version/lifecycle; relações compostas; migrations reproduzíveis; primeira tabela tenant-owned com RLS mínima deny-by-default; Audit append-only mínimo para mudanças críticas de identidade/tenant. |
| Backend/Commands | Commands mínimos de convite/status/configuração com autoria derivada, reautorização e Audit crítico; queries de sessão/contexto sem efeito colateral. |
| Frontend | Login/recovery/logout; seletor/contexto; rotas tenant; limpeza de cache/estado em logout, bloqueio e troca; Empresa/Minha Conta básicas. |
| Security | Authenticated + principal active + membership + tenant status/entitlement; rota/payload não decide tenant; nenhum cadastro público; cache keys incluem principal/contexto e tenant. |
| Storage | Logo permanece fora até W5; avatar somente se não exigir Storage antes da foundation. |
| Async | E-mails transacionais Auth somente conforme provider/fluxo aplicável; nenhum e-mail operacional de domínio. |
| Observability | Eventos seguros de login/context switch/lifecycle, sem tokens, senha, session ou PII desnecessária. |
| Migration impact | Cria alvos conceituais separados para Auth identity, app user e membership; não decide Path A/B da V1. |
| Deliverables | Auth/session; tenant resolver; membership única; lifecycle/status; Empresa/Minha Conta essenciais; migrations e tipos. |
| Tests | Unit de state machine; integração Auth local suportada; session/context; DB constraints; cache invalidation; rotas; mobile básico. |
| Negative tests | Usuário sem membership; tenant errado; membership dupla comum; principal bloqueado/inativo; tenant suspenso; JWT metadata adulterada; cache antigo após switch. |
| Entry criteria | W0; formato físico de `tenantRef` (`DEC-01`) fechado antes do modelo de resolução definitivo; modelo físico básico de identity/membership aprovado. |
| Exit criteria | `TENANT_READY` e `AUTH_READY`; primeiro teste Tenant A/B passa; usuário comum não acessa segundo tenant; lifecycle separado e toda mudança crítica usa o Audit mínimo que W3 consolidará sem duplicação. |
| Blockers | `DD-02` schema físico identity/membership; `BD-01` entitlements iniciais; `RRB-01` não bloqueia implementação local, mas bloqueia mapping migratório. |
| Remote revalidation | Não exigida para o target local; RV-03 será obrigatória antes do Auth mapper em W15. |
| Rollback/recovery relevance | Migrations forward; status não apaga identidade/histórico; recovery Auth documentado sem prometer sessão. |
| Definition of Done | Gates aprovados, RLS mínima e A/B reais no PostgreSQL/Supabase local, tipos e docs atualizados. |

### W2 — Autorização e RLS

| Campo | Definição |
| --- | --- |
| Wave ID | `W2` |
| Nome | Autorização efetiva e isolamento RLS |
| Objetivo | Entregar enforcement `Resource + Action + Scope`, antiescalada e RLS não recursiva, provados entre tenants. |
| Dependências | `AUTH_READY`, `TENANT_READY`. |
| Escopo | Profile baseline, exact override ALLOW/DENY, OWN/ASSIGNED/TEAM/ALL_TENANT, evaluator, capability projection de UI, grants mínimos, governance commands, platform identity model sem operações amplas. |
| Fora de escopo | Bypass por perfil; generic `FOR ALL`; catálogo de recursos futuros; endpoints tenant com `bypass=true`; impersonação. |
| Database | Tabelas de baseline/override; RLS por operação; helpers mínimos sem circularidade, `search_path` seguro, objetos qualificados, PUBLIC EXECUTE removido; composite integrity. |
| Backend/Commands | Commands de grant/revoke/deny com antiescalada, expected version, locks relevantes e target tenant derivado. |
| Frontend | `CapabilityGate`/`Can`/`ActionVisibility`; telas mostram explicação/estado, mas não autorizam; selectors respeitam use capability. |
| Security | Provar união de scopes; `DENY OWN` e `DENY TEAM` não subtraem `ALL_TENANT`; sensitive projections separadas; permission change reautoriza sob estado estabilizado. |
| Storage | Somente capabilities conceituais; enforcement de objeto chega em W5. |
| Async | Outbox ainda N/A; invalidação de capability/session/cache após mudança relevante. |
| Observability | Denials, alteração de capability e antiescalada correlacionados sem enumeração. |
| Migration impact | Cria catálogo target necessário para mapear permissões legadas em W15; default deny para mappings incertos. |
| Deliverables | Evaluator, policies, governance commands, UI projection, matrix técnica inicial e test suite A/B. |
| Tests | Unit de álgebra; DB integration; RLS SELECT/INSERT/UPDATE/DELETE/inativação; command/concurrency; capability UI. |
| Negative tests | Cross-tenant; actor/tenant adulterado; grant superior ao concedente; scope desconhecido; helper recursivo; PUBLIC EXECUTE; tenant admin usando platform command. |
| Entry criteria | `DEC-02` catálogo físico inicial e definições de scope dos recursos fundacionais aprovados. |
| Exit criteria | `AUTHORIZATION_READY`; nenhum acesso anon de domínio; todas as tenant-owned tables existentes cobertas; A/B e antiescalada aprovados. |
| Blockers | `DD-03` catálogo Resource/Action/Scope; `SB-01` evaluator RLS inseguro; `BD-02` delegabilidade reservada. |
| Remote revalidation | Não para fechar o target local; policies/grants V1 serão RV-01/RV-03 antes de W15. |
| Rollback/recovery relevance | Revogação/compensating command; migrations forward; não apagar grants/audit historicamente relevantes. |
| Definition of Done | Security review explícito, matriz e policies revisadas, testes positivos/negativos e documentação. |

### W3 — Commands, Audit, History e Outbox

| Campo | Definição |
| --- | --- |
| Wave ID | `W3` |
| Nome | Kernel transacional e rastreabilidade |
| Objetivo | Consolidar o Audit mínimo de W1 em commands críticos compartilhados, History operacional e Outbox transacional com idempotência e correlação, sem uma segunda infraestrutura concorrente. |
| Dependências | `AUTHORIZATION_READY`. |
| Escopo | Command contract, errors, expected version, canonical locks, idempotency namespace/fingerprint, Audit, History, Outbox, handler registry allowlisted, retry/backoff, lease/fencing e failure contract. |
| Fora de escopo | Eventos de domínio ainda inexistentes, provider final de worker e notificação ao usuário. |
| Database | Version bigint, idempotency store, append-only Audit/History, Outbox/jobs, constraints e índices; failure do Audit obrigatório aborta mutation. |
| Backend/Commands | Pipeline transacional completo e workers mínimos exercitados por mudança administrativa real de W1/W2. |
| Frontend | Tratamento de conflict/version/state/permission; correlation ID em erro seguro; History/Audit não misturados na UX. |
| Security | Technical authority separada; payload não escolhe handler/tenant/actor; service_role somente server-side se estritamente necessário; kill switch. |
| Storage | N/A, mas finalize futuro usa o mesmo command/audit/outbox contract. |
| Async | Principal: outbox persistida, handler allowlist, schema/version, idempotência, lease/fencing e resultado. |
| Observability | Correlação `request → command → transaction → outbox → worker`, métricas de retry/failure/backlog e redaction. |
| Migration impact | Audit técnico de migração reutilizará invariantes, mas registry/quarantine ficam em W15; History legado não vira Audit. |
| Deliverables | Command SDK/pattern, Audit, History, Outbox, worker test handler, error catalog e observabilidade básica. |
| Tests | Transaction atomicity, audit failure, idempotent replay, payload conflict, concurrency/lost update, worker retry/fencing, append-only. |
| Negative tests | Mesma key com payload diferente; handler não allowlisted; stale lease; update/delete de Audit por usuário comum; job com tenant adulterado; partial commit. |
| Entry criteria | W2 e modelo físico/retention inicial compatível com no-delete até decisão final. |
| Exit criteria | `AUDIT_READY`; mutation administrativa crítica prova Domain + Audit/History aplicável + Outbox em boundary coerente. |
| Blockers | `DD-04` schema de Audit/History/Outbox; `DD-05` idempotency/fingerprint; `PD-01` provider não bloqueia implementação local. |
| Remote revalidation | N/A para o kernel local; RV-01 antes de comparar writers/triggers legados. |
| Rollback/recovery relevance | Correções por evento compensatório; outbox replay idempotente; migrations roll-forward. |
| Definition of Done | Security review, testes transacionais/concorrência, documentação de lock order e observabilidade. |

### W4 — Cadastros estruturais e Equipes

| Campo | Definição |
| --- | --- |
| Wave ID | `W4` |
| Nome | Cadastros estruturais e scope TEAM |
| Objetivo | Entregar Locais, Centros de Custo, Setores, Equipes, Categorias/Subcategorias e motivos essenciais como fundação real dos domínios. |
| Dependências | `AUDIT_READY`. |
| Escopo | Hierarquia/status/inativação; memberships de Equipe; estrutura mínima de categorias; motivos de pausa/cancelamento/rejeição/devolução; tipos de documento; checklist model skeleton quando necessário; shared table/filter/form/status/selector patterns. |
| Fora de escopo | Transformar enums estáveis em tabelas, Tags/UOM avançadas, taxonomia extensa, importação XLSX/CSV. |
| Database | Tenant-aware parents, cycle protection quando hierárquico, codes/uniqueness apropriados, no physical delete normal, RLS por action. |
| Backend/Commands | Commands cadastrais e membership de Equipe com antiescalada e History/Audit apropriados. |
| Frontend | List/detail/form routes, `DataTable`, filtros em URL, StatusBadge, ConfirmDialog, UserSelector e estados completos; mobile responsivo. |
| Security | TEAM usa membership ativa e definição do recurso; narrow lookup/use separado de VIEW amplo. |
| Storage | N/A. |
| Async | Outbox somente para fatos relevantes, sem notificações prematuras. |
| Observability | Falhas de hierarchy/code/authorization e command metrics. |
| Migration impact | Define destinos para operações/lojas classificadas, CC, categorias e scopes; não classifica dados sem evidência. |
| Deliverables | Cadastros essenciais, selectors, UI patterns reutilizáveis, matrix TEAM e migrations. |
| Tests | Domain/unit, hierarchy/cycle, RLS A/B read/write/child, commands, component/accessibility e mobile. |
| Negative tests | Parent cross-tenant; usuário fora da Equipe; inativo selecionável; conceder TEAM sem authority; delete de registro referenciado. |
| Entry criteria | Catálogo mínimo e significados aprovados; ausência de tentativa de mapear `operacoes/lojas` por aproximação. |
| Exit criteria | `CADASTRO_READY`; selectors retornam apenas opções visíveis/utilizáveis; A/B e inativação aprovados. |
| Blockers | `BD-03` taxonomia mínima; `RRB-02` classificação V1 só bloqueia W15, não cadastros novos. |
| Remote revalidation | RV-02 obrigatória antes do mapper de cadastros em W15. |
| Rollback/recovery relevance | Inativação/compensação em vez de delete; migrations forward. |
| Definition of Done | Gates de domínio e segurança, testes e documentação de semântica/ownership. |

### W5 — Ativos e Storage foundation

| Campo | Definição |
| --- | --- |
| Wave ID | `W5` |
| Nome | Ativos estruturais e primeira vertical de Storage |
| Objetivo | Entregar Ativo como prontuário estrutural e provar o protocolo completo de arquivo autorizado. |
| Dependências | `CADASTRO_READY`, W3 e W2. |
| Escopo | Código `AT-00001`, aliases legados, hierarchy/cycle, cadastral/operational status, specs validadas, Local/CC, relation Supplier preparada, documents/photos, narrow lookup para Requester; `reserve/upload/finalize/AVAILABLE`. |
| Fora de escopo | QR Code, importação, alerta avançado de garantia, inferência automática de Local e bucket count arbitrário. |
| Database | Asset + relations + file metadata/association/lifecycle; composite FKs; atomic allocator; quota facts; checksum/integrity metadata conforme tier. |
| Backend/Commands | Asset commands; Storage reserve/finalize reautoriza actor, tenant, parent, state, action, quota, object identity, bucket/key, size, effective MIME e integrity. |
| Frontend | Asset routes/list/detail/hierarchy/prontuário; MediaManager inicial; upload mobile e estados de processing/failure. |
| Security | Path não autoriza; signed URL curta e não persistida; requester lookup narrow; parent access obrigatório; object A/B tests. |
| Storage | Principal: topology por classes aprovada, private-by-default, orphan cleanup idempotente e controlado. |
| Async | Processamento/cleanup técnico allowlisted quando necessário; objeto não fica AVAILABLE antes do finalize. |
| Observability | Reserve/finalize/access failures, quota, integrity, orphan e correlation sem signed URL. |
| Migration impact | Define destino de ativos, códigos EQP aliases e manifests/associations de arquivos; migração real somente W15–W17. |
| Deliverables | Asset completo, allocator, hierarchy, prontuário básico e Storage foundation reutilizável. |
| Tests | Hierarchy/cycle/concurrency; code allocation; RLS A/B; Storage reserve/finalize/access; MIME/size/quota; component/mobile. |
| Negative tests | Cross-tenant parent/file; duplicate code; forged tenant/path/parent; loss of permission between reserve/finalize; signed URL stale; unsupported MIME. |
| Entry criteria | `DEC-05` Local inheritance/depth; `DEC-06` bucket topology/classes; `DEC-07` integrity/checksum tier inicial. |
| Exit criteria | `ASSET_READY` e `STORAGE_FOUNDATION_READY`; zero cycle/cross-tenant; arquivo só fica AVAILABLE após reautorização. |
| Blockers | `DD-06`, `DD-07`, `SB-02` Storage authorization, `IB-02` provider local incompatível. |
| Remote revalidation | Target local basta; RV-04 obrigatória antes do Storage mapper W15 e R3. |
| Rollback/recovery relevance | Lifecycle impede associação parcial; código consumido não é reutilizado; bytes não são sobrescritos; roll-forward. |
| Definition of Done | Security review explícito de Storage, tests reais compatíveis e documentação do protocolo. |

### W6 — Fornecedores canônicos

| Campo | Definição |
| --- | --- |
| Wave ID | `W6` |
| Nome | Fornecedores e documentos reutilizáveis |
| Objetivo | Substituir o conceito canônico de Prestador por Fornecedor sem fundir contato e usuário Auth. |
| Dependências | W4 e `STORAGE_FOUNDATION_READY`. |
| Escopo | PF/PJ, tipos múltiplos, contatos/finalidades, especialidades, documentos, status Ativo/Inativo/Bloqueado, History, relações com Ativo/OS/Plano conforme uso. |
| Fora de escopo | Portal externo, avaliação avançada, gestão documental avançada e merge automático por nome/documento. |
| Database | Supplier, contacts, types, specialties, documents, lifecycle e tenant-aware N:N; no physical delete normal. |
| Backend/Commands | Commands de create/update/block/inactivate/document; selector recusa Bloqueado em nova operação. |
| Frontend | List/detail/form; múltiplos contatos; documentos via MediaManager; status/historical relations. |
| Security | Supplier contact não recebe identidade; document access deriva do parent; sensitive fields projetados conforme capability. |
| Storage | Reuso integral do protocolo W5; tipos/finalidades de documento allowlisted. |
| Async | Outbox somente para fatos aprovados; alertas documentais avançados fora de escopo. |
| Observability | Commands, documentos e tentativas de selecionar Bloqueado. |
| Migration impact | Destino de `prestadores`, contatos embutidos, especialidades e documentos; casos ambíguos ficam review/quarantine. |
| Deliverables | Supplier completo e reuso comprovado de selectors, tables, forms, History e Storage. |
| Tests | PF/PJ, status, contacts, N:N, RLS A/B, document authorization, selectors, accessibility/mobile. |
| Negative tests | Contact virar login; cross-tenant relation/document; Bloqueado selecionável; merge fuzzy; delete de Supplier referenciado. |
| Entry criteria | Taxonomia mínima de tipos/especialidades e documento; Storage gate aprovado. |
| Exit criteria | `SUPPLIER_READY`; nenhum vínculo cross-tenant; documento e status respeitam domínio/segurança. |
| Blockers | `BD-04` taxonomia Supplier; dados legados ambíguos bloqueiam apenas mapping W15. |
| Remote revalidation | RV-02/RV-04 antes do mapper de Supplier em W15. |
| Rollback/recovery relevance | Inativar/bloquear; associações e arquivos preservados; migrations forward. |
| Definition of Done | Gate, testes negativos, security review de documentos e docs de migração impactada. |

### W7 — Requests e comentários

| Campo | Definição |
| --- | --- |
| Wave ID | `W7` |
| Nome | Requests completas e comunicação humana separada |
| Objetivo | Entregar a capacidade completa de Solicitação com código anual, atribuição, mídia, comentários e transitions oficiais. |
| Dependências | W2–W6. |
| Escopo | Tipos/status/prioridades oficiais; código `AAAA-NNN`; Local/CC/Equipe/Setor/responsável/Ativo opcional; assignment combinável; scheduling; comments create/edit/remove/moderate, mentions e reply de um nível; files; History/Audit/Outbox. |
| Fora de escopo | Preventiva como Request, Kanban, busca global, fechamento automático pela OS e thread model complexo. |
| Database | Request, assignments, comments, annual allocator, reasons, composite relations, version/lifecycle e RLS. |
| Backend/Commands | Create/classify/assign/schedule/transition/cancel/reject/comment commands; prioridade auditada; mentions reautorizadas. |
| Frontend | Table prioritária, filtros/paginação em URL, create/detail/edit, comments/files, mobile-first e deep links. |
| Security | Scope por action/record; asset narrow lookup; mention same tenant + active + can view parent; comments com XSS-safe rendering. |
| Storage | Attachments via W5; finalize reautoriza Request state/action. |
| Async | Outbox de assignment/comment/transition; notificação ao usuário é materializada em W11. |
| Observability | Transitions, allocator, comments/mentions e upload correlation. |
| Migration impact | Destino de `demandas`, status/tipos/prioridades, históricos e anexos; preventiva é reclassificada, nunca importada como Request. |
| Deliverables | Request vertical completa, comments shared capability e allocator anual. |
| Tests | Domain state matrix, command/idempotency/concurrency, RLS A/B read/write/child/file/comment, UI/E2E/mobile. |
| Negative tests | Preventive type; cross-tenant association/mention/file; unauthorized priority/status; stale version; XSS; code collision; automatic close. |
| Entry criteria | `DEC-08` comment edit window; Request scope definitions e transition matrix fechadas; cadastros essenciais ready. |
| Exit criteria | `REQUEST_READY`; schema, commands, RLS, permissions, UI, History/Audit, tests A/B, allocator e Storage aprovados. |
| Blockers | `BD-05` comment edit window; `DD-08` assignment combinations/transitions; `SB-03` mention/access leakage. |
| Remote revalidation | RV-02 antes do mapper Request em W15; nenhuma dependência remota para target local. |
| Rollback/recovery relevance | Cancel/reject/inactivate, não delete; replay idempotente; codes não reutilizados. |
| Definition of Done | Feature gate completo e security review explícito de command/RLS/files/comments. |

### W8 — Núcleo de Ordens de Serviço

| Campo | Definição |
| --- | --- |
| Wave ID | `W8` |
| Nome | OS: criação, planejamento, atribuição e execução |
| Objetivo | Entregar o núcleo formal de trabalho com origens, tipos, responsáveis, múltiplos executores e execução segura. |
| Dependências | `REQUEST_READY`, W4–W6 e W3. |
| Escopo | Códigos `OS-AAAA-NNN`; origens Manual/Request/Preventive; tipos oficiais; Draft/Open/Scheduled/In execution; responsável distinto de executores; Equipe/Fornecedor; Internal/Supplier/Mixed; schedule/start; service requested/executed; custos/materiais opcionais informativos. |
| Fora de escopo | Pause/return/validation final, checklist completion e scheduler preventivo. |
| Database | OS, executor N:N, assignments, schedule/execution facts, costs/materials mínimos, version, composite FKs e allocator. |
| Backend/Commands | Create/link/plan/assign/start/update allowed fields; locks canônicos, expected version e idempotência. |
| Frontend | List/create/detail/plan/start, selectors e mobile execution shell; conflito/perda de permission tratados. |
| Security | Actions de planner/responsible/executor separadas; no generic row patch; cost projection requer `VIEW_COST`. |
| Storage | Estrutura de evidência preparada, mas fluxo before/during/after completa em W9. |
| Async | Outbox de assignment/schedule/start; consumers de notificação em W11. |
| Observability | Transition latency/failure/conflict, allocator e assignments correlacionados. |
| Migration impact | Alvo de OS avulsas/vinculadas, executor legado e costs/materials; ambiguidades não recebem fallback. |
| Deliverables | OS core, allocator, assignments/executors, execução inicial e tests. |
| Tests | State/domain, Request link cardinality, concurrency/idempotency, allocator, RLS A/B, cost projection, E2E mobile. |
| Negative tests | Responsible=executor por inferência; cross-tenant parent; unauthorized start/assign/cost; invalid origin/type; duplicate code; generic status patch. |
| Entry criteria | Resource/Action/Scope OS core e estados/campos aprovados; UOM mínima decidida se materials a exigirem. |
| Exit criteria | `OS_CORE_READY`; criação manual e por Request, schedule, assignment e start passam segurança/integridade. |
| Blockers | `DD-09` catálogo de OS actions; `BD-06` UOM mínima; `DD-10` semântica de assignments. |
| Remote revalidation | RV-02 antes do mapper OS W15. |
| Rollback/recovery relevance | Commands compensatórios de planejamento; códigos consumidos; no destructive rollback. |
| Definition of Done | Core vertical testável, sem antecipar automações, com security review. |

### W9 — Conclusão, validação, checklist e evidências de OS

| Campo | Definição |
| --- | --- |
| Wave ID | `W9` |
| Nome | OS operacional completa |
| Objetivo | Fechar o ciclo de execução com pausa/retomada, checklist imutável, evidências, validação/devolução e matriz Request × OS. |
| Dependências | `OS_CORE_READY`, `STORAGE_FOUNDATION_READY`, `REQUEST_READY`. |
| Escopo | Paused/Awaiting validation/Completed/Cancelled; motivos; validation default required; self-validation default no conforme configuração; repeated returns; before/during/after evidence; checklist model/version/instance/responses/snapshot; Request × OS matrix completa; suggestion de encerramento. |
| Fora de escopo | Fechamento automático de Request, autovalidação irrestrita, custo obrigatório, edição de snapshot concluído. |
| Database | Pause intervals, validation events, checklist snapshots/responses, evidence classifications, immutable completion facts e relationships. |
| Backend/Commands | Pause/resume/submit/approve/return/cancel/complete; reread + lock + reauthorize + domain/version + Audit/History/Outbox. |
| Frontend | Jornada mobile de execução, checklist, fotos, serviço executado, envio/validação/devolução; bloqueios em Awaiting validation. |
| Security | Validator por capability/scope; executor não altera execução aguardando validação; self-validation policy; evidence access contextual. |
| Storage | Evidence before/during/after e checklist via reserve/finalize; retenção apropriada. |
| Async | Eventos persistidos para validação/devolução/sugestão; notification materialization W11. |
| Observability | Ciclos, pauses, validation SLA facts, conflicts, checklist/evidence failure. |
| Migration impact | Destino de aceite/recusa, histories, checklist parcial e OS status; eventos ausentes não são fabricados. |
| Deliverables | OS completa, checklist shared capability, evidence workflow e Request × OS decision/test matrix. |
| Tests | Todas as transitions; repeated return; immutable snapshot; validation configs; Request × OS cases; RLS/files; concurrency/idempotency; E2E mobile. |
| Negative tests | Return sem motivo; incomplete required checklist; self-validation forbidden; executor edit awaiting; cross-tenant evidence; last OS auto-closes Request; invalid cancel/close/reopen/unlink/transfer. |
| Entry criteria | Matriz Request × OS sem ambiguidade; checklist contract; validation settings; retention provisória segura. |
| Exit criteria | `OS_READY`; fluxo completo e matriz aprovados; nenhum blocker funcional/security aberto. |
| Blockers | `BD-07` ambiguidades Request × OS; `DD-11` snapshot/checklist; `SB-04` validation boundary. |
| Remote revalidation | RV-02 antes do mapper de estados/aceite/checklist em W15. |
| Rollback/recovery relevance | Devolução/cancelamento por commands; snapshot e eventos append-only; códigos/evidências preservados. |
| Definition of Done | Gate completo com testes negativos, security review e UX mobile verificada. |

### W10 — Manutenção preventiva

| Campo | Definição |
| --- | --- |
| Wave ID | `W10` |
| Nome | Plano, Programação, Ocorrência e OS Preventiva |
| Objetivo | Provar geração idempotente de exatamente uma OS por ocorrência e avanço seguro de cursor. |
| Dependências | `ASSET_READY`, `SUPPLIER_READY`, `OS_READY`, W4 e W3. |
| Escopo | Plano, Programação, occurrence key, periodicidades obrigatórias, responsible/team/supplier/checklist, generation, execution linkage, next execution, history básico, scheduler/worker. |
| Fora de escopo | Recorrências complexas complementares, motor genérico, Preventiva como Request. |
| Database | Identidades separadas; unique occurrence; schedule version; cursor condicionado; tenant-aware FKs; lifecycle. |
| Backend/Commands | Claim/validate/create-or-locate occurrence/create exactly one OS/history/audit/outbox/advance cursor; handler allowlisted e fenced. |
| Frontend | Plan/Schedule list/detail/form; generation/history; estado de erro/overdue; mobile consultivo. |
| Security | Scheduler relê origem/tenant; payload não autoriza; scopes de Plan/Schedule/OS; technical authority mínima. |
| Storage | Instruções/checklist/files reutilizam foundation quando aplicável. |
| Async | Principal: scheduler e worker idempotentes com retry/backoff/lease/fencing. |
| Observability | Duplicate signal, cursor mismatch, missed occurrence, retry, lag e release identity. |
| Migration impact | Destino separado de `planos_manutencao`, programming, occurrence e OS; cursor legado não cria ocorrências. |
| Deliverables | Preventive vertical completa e safe scheduler. |
| Tests | Time/domain unit; occurrence uniqueness; concurrent claims/retry; cursor; RLS A/B; worker failure; E2E Plan→OS. |
| Negative tests | Two OS same occurrence; cursor without OS; timezone/DST/month-end error; cross-tenant Plan/Asset; stale worker; Request preventive. |
| Entry criteria | `DEC-09` timezone/civil time/DST/month-end/catch-up/missed/reschedule/versioning fechada; provider decision suficiente para worker. |
| Exit criteria | `PREVENTIVE_READY`; exatamente uma OS por occurrence; cursor e retry provados. |
| Blockers | `DD-12` time semantics; `DD-13` occurrence identity; `PD-02` worker/scheduler provider; `SB-05` technical authority. |
| Remote revalidation | RV-02/RV-05 antes de migrar Planos e antes de R3. |
| Rollback/recovery relevance | Occurrence/código não são apagados; failed jobs retry/compensate; cursor nunca retrocede por convenience. |
| Definition of Done | Security review de worker, testes de concorrência/tempo e gate aprovado. |

### W11 — Atenção operacional

| Campo | Definição |
| --- | --- |
| Wave ID | `W11` |
| Nome | Calendar, Notifications, Alerts e Overview |
| Objetivo | Entregar superfícies acionáveis derivadas de fontes autorizadas, sem criar autoridade ou base operacional paralela. |
| Dependências | W7–W10, W3 e W2. |
| Escopo | Calendar day/week/month; OS scheduled, approved scheduling e Plan activities; internal Notification Center/read states; canonical alert condition key+generation; operational Overview cards; reprogramming na origem. |
| Fora de escopo | Drag-and-drop MVP, domínio e-mail, WhatsApp/push, alerta documental avançado, calendário como entity. |
| Database | Read models/views seguras quando justificadas; notifications; alert state/materialization escolhida; nenhuma fonte duplicada. |
| Backend/Commands | Queries/projections autorizadas; read notification commands; reprogram commands atualizam fonte; alert generation idempotente. |
| Frontend | Calendar, bell/center, actionable Overview, filters/links, states acessíveis e mobile. |
| Security | Notification/link reautoriza; conteúdo mínimo; aggregates/cards não vazam existence/count; source access governa. |
| Storage | N/A direto; links para arquivos reautorizam via parent. |
| Async | Outbox consumers criam/deduplicam notifications e alert transitions; condition key + generation. |
| Observability | Delivery/internal materialization, inaccessible source, dedup, scheduler e overdue calculations. |
| Migration impact | Calendário/Overview/alerts regenerados; notificações legadas somente por decisão e autorização atuais. |
| Deliverables | `CALENDAR_READY`, `NOTIFICATION_READY`, `ALERT_READY`, `OVERVIEW_READY`. |
| Tests | Projection/query, source update, dedup, read states, RLS A/B, cache interleaving, accessibility/mobile, E2E links. |
| Negative tests | Source invisible but notification reveals; aggregate leak; stale link; Calendar grants access; duplicate alerts; overdue before canonical deadline. |
| Entry criteria | `DEC-10` OS canonical deadline antes de `WORK_ORDER_OVERDUE`; `DEC-11` alert persistence; notification recipient rules. |
| Exit criteria | `OPERATIONAL_ATTENTION_READY`; todas as superfícies derivam de sources e reautorizam; no leakage. |
| Blockers | `BD-08` deadline; `DD-14` alert model; `SB-06` aggregate/notification leak. |
| Remote revalidation | Não para target; dados secundários entram em RV-02 antes de W15. |
| Rollback/recovery relevance | Rebuild de read models; notification/alert corrections são novos fatos; source permanece autoridade. |
| Definition of Done | Security review de projections/links, A/B interleaved e gates aprovados. |

### W12 — Dashboard e Relatórios

| Campo | Definição |
| --- | --- |
| Wave ID | `W12` |
| Nome | Analytics, Reports e PDF individual de OS |
| Objetivo | Entregar informação analítica e exportação sem ampliar linha, campo, custo ou tenant visível. |
| Dependências | W7–W11, authorization e branding/Empresa. |
| Escopo | Dashboard básico; Reports de Requests, OS, Preventive, Assets e Suppliers quando aplicável; filters/columns/preview; PDF/XLSX básicos; PDF individual de OS; branding e filtros aplicados. |
| Fora de escopo | Saved/recurring reports, dashboard avançado, e-mail, layout engine genérico e export avançado complementar. |
| Database | Queries/projections/agregações seguras; materialized view somente com evidência e RLS correta. |
| Backend/Commands | Report generation/export command quando necessário; source scopes e `VIEW_COST`; deterministic filters/pagination. |
| Frontend | Dashboard e Report UI; charts/table/filter/export accessible/responsive; PDF OS. |
| Security | Authorization antes de aggregate/export; export capability; sensitive projection; config compartilhada não concede dados. |
| Storage | Artefatos temporários, se usados, com lifecycle e acesso contextual; não persistir signed URLs. |
| Async | Geração assíncrona somente se volume comprovar; nenhuma recurring email. |
| Observability | Query/export duration, size, denial e correlation, sem conteúdo sensível. |
| Migration impact | Projeções e indicadores são `REGENERATE`; relatórios V1 servem apenas de evidência/branding. |
| Deliverables | `DASHBOARD_READY`, Reports básicos e PDF OS. |
| Tests | Formula/domain, projection/RLS A/B, cost/export permissions, PDF content/filter/branding, E2E, performance baseline. |
| Negative tests | Aggregate count cross-tenant; hidden cost in PDF/XLSX; export without capability; stale materialization; config leaks source. |
| Entry criteria | `DEC-12` bibliotecas chart/PDF e geração síncrona/assíncrona com evidência. |
| Exit criteria | `REPORTING_READY`; counts e exports fecham com sources autorizadas e testes A/B. |
| Blockers | `DD-15` libraries/report contract; `SB-07` aggregate/export leakage; performance evidence se async for proposto. |
| Remote revalidation | Volumes RV-02/RV-06 antes de decidir geração/índices finais e antes de R3. |
| Rollback/recovery relevance | Artefatos regeneráveis; exports não são fonte; cleanup controlado. |
| Definition of Done | Security review explícito, fórmula reconciliada e documentos verificados. |

### W13 — Global Admin e operações de plataforma

| Campo | Definição |
| --- | --- |
| Wave ID | `W13` |
| Nome | Autoridade de plataforma separada |
| Objetivo | Entregar administração global mínima com capabilities e commands dedicados, target explícito e Audit reforçado. |
| Dependências | W1–W3 e domínios/configurações que serão administrados. |
| Escopo | Platform identity/capabilities; tenant lifecycle, entitlements/limits e suporte operacional mínimo aprovados; explicit target/reason; `/plataforma/*`; no silent impersonation. |
| Fora de escopo | Billing/checkout, endpoint tenant com bypass, union cross-tenant default e impersonação silenciosa. |
| Database | Platform identities/capabilities separadas; target/reason/Audit; RLS/grants mínimos; tenant status/entitlements. |
| Backend/Commands | Commands de plataforma dedicados, narrow, reautorizados e auditados. |
| Frontend | Rotas/UI de plataforma separadas; target read-back e confirmação proporcional; sem reutilizar tenant guards como authority. |
| Security | Tenant admin não acessa plataforma; platform actor não recebe tenant Profile; reason/target/capability obrigatórios. |
| Storage | Ações platform de quota/retention não contornam file authorization sem command específico. |
| Async | Handlers técnicos separados; payload não escolhe target/capability. |
| Observability | Platform action, target, reason/correlation e anomaly monitoring com acesso restrito. |
| Migration impact | Lista de platform identities e initial entitlements dependem de decisão nominal futura; nunca derivados de papel admin. |
| Deliverables | `PLATFORM_READY`, commands/UI mínimas, Audit e security suite. |
| Tests | Platform/tenant separation, target/reason, antiescalation, RLS/grants, commands, audit failure e E2E. |
| Negative tests | Tenant admin platform command; missing target/reason; cross-tenant union; bypass flag; unauthorized entitlement; silent impersonation. |
| Entry criteria | Platform capability catalog e operations permitidas aprovados; identities reais não são necessárias para teste sintético. |
| Exit criteria | `PLATFORM_READY`; zero caminho genérico de bypass; security review independente. |
| Blockers | `BD-09` catálogo platform/entitlements; `SB-08` bypass/blast radius; identities reais são RV-03/W15. |
| Remote revalidation | RV-03 antes de mapear identities reais; target implementation local usa fixtures aprovadas. |
| Rollback/recovery relevance | Commands compensatórios e Audit; status/entitlement não apagam tenant; kill switch. |
| Definition of Done | Review explícito de segurança, least privilege, testes negativos e docs operacionais. |

### W14 — Hardening operacional e release

| Campo | Definição |
| --- | --- |
| Wave ID | `W14` |
| Nome | Operabilidade, observabilidade e cadeia de release |
| Objetivo | Consolidar segurança, performance, observabilidade, supply chain e promoção imutável de artefatos para tornar o produto candidato a migração/rehearsal. |
| Dependências | W0–W13 aplicáveis. |
| Escopo | Logs/metrics/health/readiness/redaction; release manifest; CI/CD; same-digest promotion; config schema; backup hooks; kill switches/read-only; CSP/security headers; dependency/licence review; capacity/performance; incident/runbooks; expand/backfill/contract. |
| Fora de escopo | Provider escolhido sem evidência, thresholds arbitrários, deploy produtivo, migration tooling e cutover. |
| Database | Reconstrução do zero/forward; checksums; immutable-after-STAGING; indexes/constraints; recovery/roll-forward; schema compatibility. |
| Backend/Commands | Health/readiness, rate/abuse control proporcional, safe errors, correlation e release identity em commands/workers. |
| Frontend | Error boundaries, offline-as-unavailable (sem offline sync), accessibility/mobile regression, release/config identity. |
| Security | Revisão transversal Auth/RLS/grants/functions/commands/Storage/XSS/CSRF/injection/enum/export/workers/secrets/supply chain. |
| Storage | Quota, lifecycle, orphan/cleanup, access, observability e recovery hardening. |
| Async | Backlog/dead-letter/retry/fencing/kill switch e health. |
| Observability | Principal; thresholds/SLIs baseados em testes/medidas; privacy e access review. |
| Migration impact | Release/migration compatibility, manifest e evidence são pré-requisitos do tooling/rehearsal. |
| Deliverables | `OPERATIONS_READY`, `SCHEMA_READY`, `SECURITY_READY`, release manifest e candidate artifact chain. |
| Tests | Full regression, security negative, performance/capacity, migration-from-zero/forward, smoke same artifact, backup/restore hooks, dependency scan. |
| Negative tests | Rebuild between envs; mutable STAGING migration; config/secret leak; missing release ID; health false-positive; worker/storage kill-switch failure. |
| Entry criteria | Providers/hosting/observability decisions necessárias fechadas; critérios de saúde medíveis definidos. |
| Exit criteria | Gates aprovados; nenhuma security debt estrutural deferida; artifact/digest e schema compatíveis e rastreáveis. |
| Blockers | `PD-03` hosting/observability; `DD-16` health gates; `SB-09` transversal security findings; `IB-03` capacity/supply chain. |
| Remote revalidation | RV-06 obrigatória para validar STAGING/hosting/config/release antes de W16; não acessada na 10E. |
| Rollback/recovery relevance | Roll-forward compatível, immutable artifacts, kill switches, backup/restore integration. |
| Definition of Done | Security review formal, release/recovery evidence e todas as regressões aplicáveis. |

### W15 — Tooling de migração

| Campo | Definição |
| --- | --- |
| Wave ID | `W15` |
| Nome | Contratos 10A–10D executáveis sem migração produtiva |
| Objetivo | Implementar tooling versionado e idempotente para snapshot, mapping, load, quarantine, provenance e reconciliação, sem executar cutover. |
| Dependências | `SCHEMA_READY`, `SECURITY_READY`, `DOMAIN_READY`, `OPERATIONS_READY`; RV-01–RV-05. |
| Escopo | Migration Run; artifact/snapshot manifests; Consistency Envelope; registry bidirecional; quarantine; rule sets; loaders; technical Audit; L1–L4; Auth/Storage/code/history mappers; evidence bundles; GO/NO-GO tooling; dry-run; delta adapters. |
| Fora de escopo | Produção, cutover, aprovação GO, descarte real, fallback silencioso, mutable published migration. |
| Database | Staging/registry/quarantine/run schemas físicos; loaders por dependency; migration chain separada de ETL; constraints target permanecem ativas. |
| Backend/Commands | Technical handlers allowlisted; map/load/reconcile/resolve/activate separados; idempotency por run/source/rule/operation. |
| Frontend | N/A ou console operacional mínimo protegido se comprovadamente necessário; não criar painel ornamental. |
| Security | Technical identity mínima; service_role isolada se necessária; registry não concede acesso; approvals/separation; secrets ausentes de manifests. |
| Storage | Manifest, copy, integrity tiers, association/finalize e quarantine; nenhuma signed URL persistida. |
| Async | Orchestration/checkpoints/retry/fencing e failure injection hooks. |
| Observability | Run/wave/attempt/correlation, metrics, audit e immutable evidence refs. |
| Migration impact | Principal; materializa 10A–10D, mas não executa migração produtiva. |
| Deliverables | Toolchain completo, fixtures/dry-run, rule catalogs, reports e runbook executável candidato. |
| Tests | From-zero/forward, dry-run, retry/idempotency, splits/merges, quarantine, Audit failure, L1–L4, Auth A/B paths, codes, history, Storage, delta coverage. |
| Negative tests | Unknown enum fallback; actor/tenant invented; privilege expansion; duplicate target; path authority; lost source row; mutable evidence; technical payload authority. |
| Entry criteria | Revalidações específicas concluídas; DEC-13–DEC-18 aplicáveis fechadas; blockers de design do tooling resolvidos. |
| Exit criteria | `MIGRATION_TOOLING_READY`; `failed` controlado em fixtures; toda source identity aparece na equação; recovery hooks testáveis. |
| Blockers | `RRB-01`–`RRB-05`, `MB-01` schemas/tooling, `MB-02` delta, `MB-03` tolerâncias, `MB-04` Auth Path A/B. |
| Remote revalidation | Obrigatória antes da implementação final dos adapters e rule-set freeze; usar apenas o projeto autorizado quando houver autorização futura. |
| Rollback/recovery relevance | Runs/evidence imutáveis, retry idempotente, target não ativo, recovery por novo attempt/roll-forward. |
| Definition of Done | Review Data/Security/Platform, test suite completa, docs/runbooks e gate aprovado. |

### W16 — Rehearsals e Cutover Readiness

| Campo | Definição |
| --- | --- |
| Wave ID | `W16` |
| Nome | R1–R4, recovery e prontidão de cutover |
| Objetivo | Demonstrar end-to-end tooling, reconciliação, recovery, freeze/delta e operação com os mesmos artefatos candidatos ao cutover. |
| Dependências | `MIGRATION_TOOLING_READY`, `OPERATIONS_READY`, ambientes autorizados, RV-06/RV-07. |
| Escopo | R1 Structural, R2 Representative Data, R3 Production-like Full, R4 Final Dress; CP0–CP4; failure injection; backup/restore; performance; writer map; freeze/delta dress; GO/NO-GO evidence preparation. |
| Fora de escopo | Rehearsal em produção, GO produtivo, ativar Serena e mudar artifacts após R4 sem repetir validação. |
| Database | Rebuild/forward/load/reconcile; prod-like volume; backup/restore; safe-next candidate; target não ativo. |
| Backend/Commands | Run phases P0–P15 aplicáveis, checkpoints e technical handlers. |
| Frontend | Smoke controlado e same-artifact validation em STAGING. |
| Security | L4 A/B interleaved, platform, Auth, Storage, worker/scheduler, sensitive projection, restore/recovery. |
| Storage | Full manifest/copy/verify/associate/availability em ambiente seguro e volume representativo. |
| Async | Failure injection, retry, backlog, fencing, external sinks e kill switches. |
| Observability | Painel de rehearsal/cutover, timings, thresholds e privacy aprovados. |
| Migration impact | Prova a migração; R4 usa RC congelada e contratos definitivos, mas não produção. |
| Deliverables | Reports R1–R4, CP0–CP4 bundles, restore proof, measured window/abort thresholds e proposta `CUTOVER_READY`. |
| Tests | Todas as suites W15 + smoke/E2E/performance/failure injection/recovery R0–R4 aplicável. |
| Negative tests | Incomplete delta; unknown writer; checksum mismatch; RLS failure; code collision; audit/registry failure; network interruption; unauthorized manual step. |
| Entry criteria | R1 tooling ready; STAGING separado/prod-like; snapshots autorizados/minimizados; owners e separation of duties. |
| Exit criteria | `REHEARSAL_READY` e depois `CUTOVER_READY`: R4 aprovado, critical failed=0, blocking quarantine=0, restore/recovery demonstrados. |
| Blockers | `CB-01` R4/restore, `MB-05` writer/delta coverage, `CB-02` artifact drift, `CB-03` health/capacity. |
| Remote revalidation | RV-06/RV-07 obrigatórias; nenhuma revalidação é presumida pela documentação. |
| Rollback/recovery relevance | Principal: R0–R4, Return to V1 conditions, Roll Forward, kill switch, single writer e evidence. |
| Definition of Done | CP4 aprovado por classes independentes; mesmos digests; todos os blockers bloqueantes resolvidos. |

### W17 — Serena, estabilização e segundo tenant

| Campo | Definição |
| --- | --- |
| Wave ID | `W17` |
| Nome | Cutover controlado, piloto Serena e expansão segura |
| Objetivo | Executar futuramente o cutover autorizado, estabilizar Serena em produção e provar prontidão para o segundo tenant sem código específico. |
| Dependências | `CUTOVER_READY`, RV-08, aprovação humana GO e todos os gates bloqueantes. |
| Escopo | P6–P15; CP5–CP10; freeze all writers; final delta/safe_next; GO/NO-GO; single writer; activation; smoke/security; monitoring; incident/recovery; legacy retention; interleaved A/B; `SECOND_TENANT_READY`. |
| Fora de escopo | Aprovação automática, produção sem GO, dual-write implícito, Serena-specific path/schema/RLS/worker, purge da V1, segundo tenant antes do gate. |
| Database | Final delta/reconciliation, allocator activation, same migrations; V1 frozen/read-only; no manual unversioned change. |
| Backend/Commands | Activation/runbook steps exatos, target read-back, kill switches, smoke e controlled platform operations. |
| Frontend | Same RC; routing/Auth/tenant/context/mobile smoke; no special Serena build. |
| Security | Final A/B, permission/Auth/Storage/platform tests; any cross-tenant issue stops rollout; waiver proibido para invariants críticas. |
| Storage | Final delta/bytes/integrity/availability; new V2 uploads enter Point of No Simple Return. |
| Async | Workers/scheduler/outbox activated allowlisted; backlog, effects and fencing monitored. |
| Observability | Cutover dashboards, thresholds, write attempts V1, incidents, tenant-safe metrics and support triage. |
| Migration impact | Executa a migração/piloto somente com autorização futura; evidence e retention permanecem imutáveis. |
| Deliverables | CP5–CP10, Migration Run Report, Serena acceptance, V1 retention state e Second Tenant report. |
| Tests | Final smoke, negative A/B, Auth, commands, codes, Storage, reports/aggregates, cache/multitab/context switch, workers/scheduler, recovery evidence. |
| Negative tests | Writer V1 after CP8; cross-tenant cache; second tenant code/quota collision; unauthorized GO; rebuild; unknown V2 write then simple rollback; missing source reauthorization. |
| Entry criteria | R4/CP4; final remote revalidation; backup/restore; delta; RLS A/B; Auth/permission/code/Storage reconciliation; observability; recovery; formal GO. |
| Exit criteria | Estágio A: `PILOT_READY` e CP8/CP9; estágio B: CP10 e `SECOND_TENANT_READY`, zero P0/P1 aberto e reconciliação contínua fechada. |
| Blockers | `CB-01`–`CB-06`, `BD-10` business acceptance/retention, qualquer gate `PENDING`/`FAILED`/`REVALIDATION_REQUIRED`. |
| Remote revalidation | RV-08 final em PRODUCTION, somente no projeto CW ERP correto e sob autorização explícita. |
| Rollback/recovery relevance | Principal; Point of No Simple Return; R1 antes de activation, R2 se zero writes provado, R3/R4 e Roll Forward após writes/effects. |
| Definition of Done | CP10 e gate de expansão aprovados; não implica purge, implementação de módulos futuros ou rollout irrestrito. |

## 12. Frontend Foundation

A foundation frontend é implementada em W0 e evolui incrementalmente. A estrutura alvo é:

```text
src/
├── app/              # bootstrap, router, providers, layout e config
├── modules/          # domínios com páginas e contratos próprios
├── features/         # capacidades reutilizadas por mais de um domínio
├── infrastructure/   # Supabase, query/command transport, telemetry
├── shared/           # UI, tipos e utilitários sem domínio
└── test/             # harness, fixtures e helpers
```

Diretórios só são criados quando recebem conteúdo real. Decisões de implementação desta 10E:

- React + TypeScript strict + Vite;
- React Router Data Mode com `createBrowserRouter`;
- TanStack Query para remote state e cache tenant-aware;
- React Hook Form + Zod para forms e validação de fronteira;
- Supabase JS com client tipado e `database.types.ts` gerado;
- shadcn/ui + Radix + Tailwind/CSS variables para primitives e tokens;
- Vitest + React Testing Library + Playwright;
- nenhum Redux/Zustand sem evidência posterior de estado cliente complexo que não caiba nos mecanismos existentes;
- nenhum generic CRUD repository;
- pages/components não importam cliente Supabase diretamente;
- queries, feature hooks, domain repositories específicos e commands possuem boundaries explícitos.

Rotas:

```text
/e/:tenantRef/*
/plataforma/*
```

`tenantRef` é seletor opaco até `DEC-01`; nunca é autoridade. Refresh, back, forward, deep-link e nova aba são gates desde W0. Filtros/paginação relevantes ficam na URL. Query keys incluem principal/contexto, tenant, resource/query, filtros e projeção sensível quando aplicável.

## 13. Database Foundation

W0 cria a disciplina; W1 introduz o primeiro schema tenant-owned; as ondas seguintes adicionam apenas os objetos exigidos pela capacidade.

Invariantes físicos obrigatórios:

- UUID interno gerado pelo banco;
- `tenant_id NOT NULL` em toda entidade tenant-owned;
- relações compostas tenant-aware ou mecanismo equivalente igualmente forte;
- códigos humanos separados de UUID, com namespace e allocator atômico;
- `version bigint` ou condição equivalente em updates concorrentes;
- timestamps e autoria atribuídos/validados por fonte autoritativa;
- lifecycle lógico e ausência de `DELETE` normal para registros históricos;
- constraints/checks/índices que expressem invariantes;
- RLS desde a primeira tabela tenant-owned;
- migrations ordenadas, versionadas, reproduzíveis e testadas do zero/forward;
- `database.types.ts` regenerado e validado quando o schema mudar;
- migration publicada em STAGING ou ambiente persistente compartilhado é imutável;
- mudança incompatível usa `EXPAND → BACKFILL → VALIDATE → SWITCH CONSUMERS → CONTRACT`;
- `CONTRACT` só ocorre com `old consumers = 0` e reconciliação aprovada;
- rollback SQL não é universal; recovery/roll-forward é obrigatório.

Cada migration futura registra identidade/checksum, compatibilidade de release, teste from-zero e forward, efeito sobre RLS/grants/functions e recovery esperado.

## 14. Identity / Tenant / Membership

W1 implementa conceitos separados:

```text
Auth Identity
!= Application User
!= Tenant Membership
!= Profile Baseline
!= Individual Override
!= Platform Identity
```

Condições mínimas para acesso tenant:

```text
authenticated
AND principal active
AND valid context
AND active membership
AND target tenant = context tenant
AND tenant operation allowed
AND entitlement enabled
```

Auth, Application User, Membership e Tenant possuem lifecycles independentes. Usuário comum operacional tem exatamente uma membership ativa. Não há cadastro público. Convite, bloqueio, inativação, recuperação e mudança de e-mail seguem fluxos autorizados e auditáveis. Empresa e Minha Conta não permitem que o próprio usuário altere unilateralmente tenant, perfil, equipes ou permissões.

Path A/Path B de Auth é decisão migratória em `DEC-04`: o target pode ser implementado em W1 sem prometer preservação de UUID, senha ou sessão V1. Nenhum password hash, token, session ou secret integra manifesto/evidence.

## 15. Authorization / RLS

W2 fecha o gate estrutural:

```text
PERMIT =
  authenticated
  AND principal active
  AND context valid
  AND tenant match
  AND tenant allowed
  AND entitlement
  AND effective Resource + Action + Scope reaches record
  AND domain/state rules for commands
```

Scopes iniciais:

- `OWN`;
- `ASSIGNED`;
- `TEAM`;
- `ALL_TENANT`.

Eles formam união de alcance, não hierarquia de negações. Override atua na combinação exata. A definição de OWN/ASSIGNED/TEAM é específica por recurso e deve ser fechada antes da wave que usa o recurso.

Toda tenant-owned table tem policies separadas por operação. É proibido usar acesso anon de domínio, `FOR ALL` genérico, tenant derivado de payload, helper recursivo inseguro, PUBLIC EXECUTE inadequado, normal DELETE ou service role no frontend. UI usa `CapabilityGate`, `Can` ou `ActionVisibility`; `CWPermissionGuard` não é nomenclatura oficial nem boundary de segurança.

## 16. Audit / History / Outbox

W3 cria mecanismos compartilhados, sem fundi-los:

| Mecanismo | Pergunta | Regra |
| --- | --- | --- |
| Audit | Quem/qual autoridade realizou ação sensível? | Append-only, acesso próprio, failure aborta command quando obrigatório |
| Operational History | O que aconteceu ao registro? | Append-only para usuários comuns; sem ampliar acesso à origem |
| Comment | O que uma pessoa comunicou? | Texto humano e actions próprias; não substitui motivo/execução |
| Notification | O que ocorreu que interessa ao destinatário? | Derivada de evento; conteúdo mínimo; link reautoriza |
| Alert | Qual condição exige atenção? | Condition key + generation; Active/Resolved |
| Outbox | Qual efeito assíncrono deve ser executado? | Persistida com domain mutation; handler allowlisted e idempotente |

Command crítico:

```text
begin transaction
→ identify relevant resources
→ canonical locks or equivalent stabilization
→ reread authoritative state
→ reevaluate authorization
→ validate input/domain/state/version/invariants
→ mutate
→ Audit + History + Outbox as applicable
→ commit
```

Idempotency namespace contém tenant, actor/context, command, key e payload fingerprint. Replay compatível retorna resultado estável; mesma key com payload distinto retorna conflito.

## 17. Shared Cadastros

W4 entrega somente cadastros necessários à V2 Obrigatória:

- Locais hierárquicos;
- Centros de Custo independentes de Local;
- Setores;
- Equipes e memberships;
- Categorias/Subcategorias;
- Motivos de pausa, cancelamento, rejeição e devolução;
- Tipos de Documento;
- estrutura mínima de Modelos de Checklist.

Global reference, tenant configuration, maintenance configuration e system enum permanecem classes distintas. Enum estável não vira tabela configurável por reflexo. Tags, importação e cadastro avançado de Unidades de Medida continuam complementares; um conjunto mínimo de UOM só entra se OS/materiais realmente o exigirem.

## 18. Assets

W5 trata Ativo como entidade estrutural e Equipamento como classificação/tipo. O gate inclui:

- código `AT-00001` por tenant e alias legado preservado;
- hierarchy com cycle protection e tenant integrity;
- status cadastral e condição operacional separados;
- Local, Centro de Custo, specs flexíveis validadas e Supplier N:N quando aplicável;
- prontuário com relações autorizadas;
- documentos/fotos pelo protocolo de Storage;
- lookup estreito para Requester sem conceder `Asset.VIEW` amplo.

Local inheritance e profundidade física são `DEC-05` e precisam fechar antes da implementação final da hierarquia. QR Code/importação permanecem complementares.

## 19. Suppliers

W6 estabelece Fornecedor como entidade canônica. “Prestador” permanece apenas nomenclatura/evidência legada. PF/PJ, tipos, contatos com finalidade, especialidades, documentos, status e History têm modelos distintos. Contato não é Auth user. Bloqueado não participa de novas seleções, mas permanece em relações históricas. Merge por nome, e-mail ou documento semelhante nunca é automático.

## 20. Requests

W7 entrega:

- tipos: Corrective Maintenance, Service Request, Service Scheduling e Inspection/Survey;
- statuses: Registered, Under analysis, Scheduled, In progress, Completed, Cancelled e Rejected;
- prioridades: Low, Normal, High e Urgent;
- código anual tenant-aware `2026-001` com allocator atômico;
- assignment a team, sector, individual ou combinações aprovadas;
- Local/CC/Ativo opcional, mídia, comentários, History/Audit/Outbox;
- tabela como interface prioritária, filtros/paginação em URL e jornada mobile.

Preventive não é Request. Prioridade só muda com capability apropriada e Audit. Request pode existir sem OS.

## 21. Work Orders

W8 e W9 dividem o domínio para evitar mega-wave:

```text
W8: identidade + criação + planejamento + atribuição + início
W9: pausa/retomada + checklist/evidência + validação/devolução + conclusão
```

Origens: Manual, Request, Preventive. Tipos: Corrective, Preventive, Inspection/Survey, Service. Statuses: Draft, Open, Scheduled, In execution, Paused, Awaiting validation, Completed, Cancelled.

Responsible não é Executor; múltiplos executores são suportados. Execution é Internal/Supplier/Mixed. Custos são opcionais/informativos e projeção exige capability. Checklist concluído preserva snapshot imutável. Evidências são classificadas before/during/after.

Validação é por permission, default required; self-validation default no conforme configuração. Devolução exige motivo, volta a In execution, pode repetir e é auditada.

## 22. Preventive

W10 preserva identidades distintas:

```text
Plan
→ Schedule
→ Occurrence
→ Preventive Work Order
→ Execution
```

Occurrence key canônica contém tenant + schedule + competência/instante planejado canônico + versão quando necessária. O command de geração cria/localiza uma occurrence, produz exatamente uma OS e só então avança o cursor em decisão transacional ou protocolo idempotente equivalente.

Timezone, civil time, DST, fim de mês, catch-up, missed occurrences, reschedule e schedule versioning devem fechar em `DEC-09`; nenhuma política é inventada pela implementação. Recorrências avançadas continuam complementares.

## 23. Calendar

Calendar é read model/view de fontes autorizadas. W11 agrega OS agendadas, agendamentos aprovados e atividades de Plan quando aplicável. Reprogramar executa command na entidade de origem e gera History/Audit aplicável. Sem drag-and-drop no MVP. Estar no calendário nunca amplia acesso.

## 24. Storage

W5 implementa e W14 endurece:

```text
reserve
→ upload restrito
→ inspect real object facts
→ finalize reauthorizes
→ metadata/association
→ AVAILABLE
```

Modelo:

```text
bytes
+ DB metadata
+ association
+ parent
+ tenant
+ uploader/actor
+ classification/lifecycle
+ provenance
```

Finalize valida ator/contexto, tenant, parent, state, action, quota, object identity, bucket/key, size, effective MIME e checksum/integrity quando exigido. Path não é autoridade; signed URL não é persistida como payload comum. A quantidade de buckets só é fechada em `DEC-06`, com base em classes/lifecycle/provider, nunca por número arbitrário.

## 25. Comments / Notifications / Alerts

Comments nascem em W7 e são reutilizados por OS. Actions: CREATE, EDIT, REMOVE e MODERATE, com OWN quando aplicável. Edit window permanece `DEC-08`. Mentions exigem mesmo tenant, usuário ativo e acesso ao parent. Replies são de um nível; não se congela `thread_root` físico sem necessidade.

Notifications e Alerts nascem em W11:

- Notification Center interno é MVP obrigatório;
- e-mails transacionais Auth permanecem aplicáveis;
- e-mail operacional de domínio, WhatsApp e push não integram o MVP;
- notification não concede acesso e seu link reautoriza;
- alerta usa condition key + generation e estados ACTIVE/RESOLVED;
- deduplicação evita eventos/condições repetitivos;
- `WORK_ORDER_OVERDUE` só entra após `DEC-10`.

## 26. Dashboard / Reports

W12 usa apenas sources e campos já autorizados. Dashboard responde “como está a operação”; Overview de W11 responde “o que precisa da minha atenção agora”. Relatórios seguem:

```text
source
→ permissions/scopes/projection
→ filters
→ columns/indicators
→ preview
→ PDF/XLSX
```

PDF individual de OS é obrigatório. Custos exigem `VIEW_COST`; export exige capability apropriada. Configuração compartilhada não concede dados. Agregações nunca revelam existência, count, valor, custo ou tenant além do alcance efetivo.

## 27. Global Admin

W13 implementa `PLAT-01`:

- Platform Identity é separada de Profile/Membership tenant;
- commands de plataforma são dedicados;
- target tenant é explícito;
- reason é exigido quando aplicável;
- operação é limitada e recebe Audit reforçado;
- não há endpoint tenant com `bypass=true`, profile temporário, union silenciosa ou impersonação silenciosa.

Service role permanece technical authority e nunca substitui platform authority funcional.

## 28. Observability / Hardening

Observabilidade incremental começa em W0/W3; W14 consolida:

- logs estruturados e redaction;
- correlation por request/command/transaction/outbox/worker;
- release/build/migration identity;
- metrics, health/readiness, dashboards e alertas técnicos;
- RLS/command/Storage/Auth/code/worker signals;
- privacy/access control dos próprios dados de observabilidade;
- capacity/performance baselines;
- CSP, dependency/supply-chain, secrets e error hardening;
- kill switches e modos read-only.

Thresholds concretos são medidos em W14/W16 e não inventados na 10E. Alertas técnicos não se confundem com Alerts funcionais do produto.

## 29. Migration Tooling

W15 implementa, sem executar produção:

- Migration Run e state machine;
- artifact/release/snapshot manifests;
- Consistency Envelope de Database/Auth/Storage;
- registry/provenance bidirecional;
- quarantine com reason codes e approvals;
- mapping rule sets versionados;
- loaders idempotentes por dependência;
- technical Audit;
- Auth Path A/B mappings;
- code inventory/collision/safe-next;
- History/actor mapping sem retrofabricar Audit;
- Storage manifest/copy/integrity/association;
- reconciliation L1 Count, L2 Relationship, L3 Semantic, L4 Security/Access;
- delta adapters e GO/NO-GO evidence.

Namespace de idempotência inclui ambiente, run/snapshot, source identity, rule version, operation e role de split/merge quando aplicável. `failed` não desaparece: chega a zero ou vira classe controlada e reconciliável.

## 30. Rehearsals

W16 executará futuramente:

| Rehearsal | Componentes que já devem existir | Saída obrigatória |
| --- | --- | --- |
| R1 Structural | W0, W14 e tooling estrutural W15 | Migrations/rebuild/retry, registry/quarantine/Audit e idempotência |
| R2 Representative Data | Rule sets, mappings, domains W1–W13 | L1–L3, exceptions e workflow de review/quarantine |
| R3 Production-like Full | W14, Auth/Storage/workers/observability e RV-01–RV-07 | Volume, L4, recovery, performance e full manifests |
| R4 Final Dress | RC congelada, owners, writer map, delta, communication e recovery | Mesmo runbook/digests do cutover, zero blocker, CP4 |

R4 não é dispensável. Cada rehearsal gera Migration Run e evidence próprios. Recovery é demonstrado com failure injection; descrição sem execução não aprova gate.

## 31. Cutover / Serena

Nenhum cutover antes de:

- R4/CP4 aprovado;
- final remote revalidation e source drift incorporados;
- backup identificado e restore demonstrado;
- freeze/delta strategy demonstrada para todos os writers;
- RLS A/B interleaved;
- Auth, membership, permission e platform reconciliation;
- codes/counters e `safe_next` final;
- Storage metadata/object/parent/tenant/integrity reconciliation;
- observability/health/capacity;
- recovery rehearsal e kill switches;
- GO/NO-GO completo e aprovação humana.

Serena é o primeiro tenant em PRODUCTION, usando a mesma release, schema, RLS, commands, workers e Storage protocol. Não existe “ambiente Serena” nem código especial. Após CP8, qualquer write/effect V2 cruza o Point of No Simple Return; retorno a V1 exige prova/reverse strategy, e Roll Forward tende a ser preferido.

Qualquer pilot allowlist/config só existe se aprovada como configuração genérica de rollout, versionada e auditável. Ela não concede capability, não contorna RLS e não contém branch Serena-specific.

## 32. Second Tenant

Antes do segundo tenant, W17 executa casos interleaved A/B sobre:

- sessão/context/cache/multitab/logout;
- domain rows/children/associations;
- reports/aggregates/Calendar/Overview/Notifications;
- Storage, signed access, reserve/finalize e quotas;
- workers/outbox/scheduler;
- codes/counters;
- Global Admin target explícito;
- OWN/ASSIGNED/TEAM/ALL_TENANT e sensitive projections.

`SECOND_TENANT_READY` exige zero cross-tenant read/write/effect, reconciliação separada e conjunta sem compensação cruzada, nenhum Serena-specific path e aprovação de Security, Operations, Data e Business.

## 33. Test Strategy

### 33.1 Camadas

| Camada | Finalidade | Gate típico |
| --- | --- | --- |
| Unit/domain | Regras puras, states, scope reach, códigos e tempo | Feature gate da wave |
| Component | Estados, forms, capability UX, accessibility e mobile behavior | Feature gate da wave |
| Contract | Queries, commands, erros, schemas, idempotência e projections | Feature/security gate |
| DB integration | Constraints, FKs compostas, triggers mínimos, transactions e concurrency | `SCHEMA_READY`/feature gate |
| RLS/security | Policies reais em PostgreSQL/Supabase compatível, grants e helpers | `AUTHORIZATION_READY`/`SECURITY_READY` |
| Worker/async | Outbox, allowlist, retry, lease/fencing e source reread | W3/W10/W11/W14 |
| Storage | Reserve/finalize/object access/quota/integrity | W5 e `SECURITY_READY` |
| E2E | Jornadas críticas, deep links, mobile e recovery UX | Feature/MVP/pilot gates |
| Migration | From-zero, forward, retry, mapping, load, reconciliation e delta | W15/W16 |
| Reconciliation | L1–L4 por tenant/domínio/run | `MIGRATION_TOOLING_READY` em diante |

PGlite pode acelerar testes locais, mas não é gate oficial de RLS, commands críticos ou concorrência. Esses casos usam PostgreSQL/Supabase local compatível.

### 33.2 Tenant A/B obrigatório

Desde W1 e para cada nova entidade tenant-owned:

| Caso | Prova positiva | Prova negativa |
| --- | --- | --- |
| Read | Tenant A lê registro A autorizado | A não lê existência/campos de B |
| Write | A escreve A dentro da capability/state | A não cria/altera B nem troca tenant por payload |
| Child | Filho A referencia pai A | Filho A não referencia pai B |
| Association | Relação entre entidades A válida | Associação A↔B falha por integridade e RLS |
| Command | Ator A executa command permitido | Scope/state/version/tenant inválidos falham atomicamente |
| File | A reserva/finaliza/acessa arquivo A | A não usa path/key/URL de B |
| Aggregate | Count/value de A correto | B não influencia count, gráfico, Overview ou Report de A |
| Cache/context | Troca A→B limpa estado | Dado A não pisca/reaparece em B/multitab |
| Async | Worker processa source A | Payload não muda tenant/handler/authority |

W17 repete esses casos de forma interleaved e em ordens distintas. Testes negativos essenciais nunca são adiados para o final.

### 33.3 Regras de teste por wave

- Correção de bug relevante inclui teste de regressão quando viável.
- Teste não é removido/enfraquecido para tornar pipeline verde.
- Fixture explicita tenant, actor, capability, scope e lifecycle.
- Mock não prova RLS, Storage, provider Auth nem configuração remota.
- Toda falha produz diagnóstico seguro e correlation; secrets/PII não entram em snapshots.
- Wave registra suites executadas, resultado, ambiente e testes não executados.
- Security review verifica o teste e o enforcement, não apenas cobertura percentual.

## 34. Release Strategy

Lifecycle oficial:

```text
feature branch curta
→ PR para develop/v2
→ CI
→ merge aprovado
→ build/release identity
→ TEST
→ promover os mesmos artifacts/digests
→ STAGING
→ validar
→ declarar RC
→ aprovação humana
→ PRODUCTION
→ smoke
→ pilot/rollout
```

Até go-live, `develop/v2` integra a V2, `main` preserva a V1 e `v1-legacy` permanece imutável. Após go-live, eventual transição trunk-based em `main` exige decisão explícita e não é executada por este plano.

Release Manifest liga:

- commit SHA e release ID;
- frontend digest;
- Functions/workers e seus digests;
- migrations/checksums;
- schema/version de configuração e identidade pública autorizada;
- compatibility range app/schema/tooling;
- telemetry identity;
- artifact manifest da migração quando aplicável.

Não se reconstrói entre STAGING e PRODUCTION. Uma alteração após R4 invalida as aprovações afetadas e exige novo rehearsal proporcional. Commits futuros são pequenos, coerentes, com uma responsabilidade principal e sem refactor aleatório.

## 35. Remote Revalidation

Nenhum remoto foi acessado nesta 10E. Quando houver autorização futura, o único projeto CW ERP correto é:

```text
qtxkasllovxjzukmxuav
```

É proibido tocar o projeto CW Obras:

```text
ymolipuxeybwlrfnxpng
```

Revalidation é sempre específica, read-only quando o objetivo for inventário, associada a evidence e concluída antes da wave que depende dela. “Revalidar o remoto” sem lista, boundary e gate não fecha blocker.

Pontos consolidados:

- RV-01: schema, constraints, indexes, views, migrations/drift, functions/RPCs, triggers, sequences, grants, RLS/policies, Edge Functions e release;
- RV-02: dados, volumes, enums, códigos, relações, órfãos, cross-tenant, autoria e qualidade por tenant/domínio;
- RV-03: Auth UUIDs, providers, lifecycle, profiles, memberships, permissions, platform candidates e bypasses;
- RV-04: buckets, settings, policies, objects, metadata, parent, tenant, MIME, size, checksum e órfãos;
- RV-05: writers, integrations, scheduled jobs, timestamps, deletes e mecanismos de delta;
- RV-06: TEST/STAGING/hosting/config/release identity, health, capacity e observability;
- RV-07: snapshot prod-like autorizado, source drift e equivalência para R3/R4;
- RV-08: revalidation final pré-cutover de Database/Auth/Storage/config/writers/delta/backup/restore/RC.

## 36. Migration Readiness

| Estado | Critérios objetivos | Produzido após |
| --- | --- | --- |
| `SCHEMA_READY` | Schema MVP reconstruível; migrations from-zero/forward; constraints/FKs/índices/RLS/grants/functions; checksums e compatibility; nenhuma migration publicada reescrita | W14 |
| `SECURITY_READY` | Auth/tenant/membership, capability algebra, RLS A/B, commands, Audit, Storage, platform e security regression aprovados | W14 |
| `DOMAIN_READY` | Cadastros, Assets, Suppliers, Requests, OS, Preventive, Calendar/Attention e Reports obrigatórios com feature gates aprovados | W12, condicionado a W14 |
| `MIGRATION_TOOLING_READY` | Run/registry/quarantine/rules/loaders/Audit/L1–L4/Auth/codes/History/Storage/delta implementados e testados sem produção | W15 |
| `REHEARSAL_READY` | Ambientes, artifact manifest, owners, snapshots autorizados, backups, restore, tooling e observability prontos para R1–R4 | Entrada/execução W16 |
| `CUTOVER_READY` | R4/CP4 aprovado; critical failed=0; blocking quarantine=0; restore/recovery, window, writer/delta e same digests provados | Saída W16 |
| `PILOT_READY` | RV-08, pre-cutover gates, business window/support e GO humano; ainda antes de CP8 | W17 antes da ativação |
| `SECOND_TENANT_READY` | CP10 Serena, A/B interleaved, cache/reports/Storage/workers/codes/platform/quotas e reconciliação multi-tenant aprovados | Saída W17 |

Estados não são inferidos por conclusão de commit. Se uma evidência expira, drift muda ou checkpoint é reaberto, o estado dependente volta a pendente até nova aprovação.

## 37. Gate Catalog

| Gate | O que prova | Evidência mínima | Owner class | Blocking |
| --- | --- | --- | --- | --- |
| `FOUNDATION_READY` | App/DB/test harness reproduzíveis e boundaries corretos | build/type/lint/tests, route smoke, DB rebuild | Architecture | Sim |
| `TENANT_READY` | Tenant/context/membership íntegros | constraints, session/context e A/B | Security/Data | Sim |
| `AUTH_READY` | Auth/lifecycle/convite/recovery seguros | Auth contracts/tests e cache invalidation | Security/Platform | Sim |
| `AUTHORIZATION_READY` | Resource/Action/Scope, override e RLS corretos | matrix, policy/grant review, A/B, antiescalada | Security | Sim |
| `AUDIT_READY` | Commands e rastreabilidade transacionais | atomicity, audit-failure, idempotency, outbox tests | Security/Architecture | Sim |
| `CADASTRO_READY` | Cadastros estruturais e TEAM utilizáveis | domain/RLS/hierarchy/selector tests | Domain/Data | Sim |
| `STORAGE_FOUNDATION_READY` | Reserve/finalize/access seguros | object A/B, MIME/size/quota/integrity tests | Security/Platform | Sim |
| `ASSET_READY` | Ativo estrutural completo | code/hierarchy/domain/file tests | Domain/Security | Sim |
| `SUPPLIER_READY` | Fornecedor canônico completo | status/contact/document/RLS tests | Domain/Security | Sim |
| `REQUEST_READY` | Request end-to-end segura | schema/commands/RLS/UI/History/files/comments/code tests | Domain/Security | Sim |
| `OS_CORE_READY` | OS criada/planejada/atribuída/iniciada | state/command/concurrency/code/RLS tests | Domain/Security | Sim |
| `OS_READY` | Ciclo completo de OS e Request×OS | validation/checklist/evidence/matrix tests | Domain/Security | Sim |
| `PREVENTIVE_READY` | Uma OS por occurrence e cursor seguro | time/concurrency/worker/RLS tests | Domain/Platform/Security | Sim |
| `CALENDAR_READY` | Calendar é view segura da origem | source-link/reprogram/RLS tests | Domain/Security | Sim |
| `NOTIFICATION_READY` | Entrega interna sem source leak | recipient/link/dedup/RLS tests | Domain/Security | Sim |
| `ALERT_READY` | Condições idempotentes e autorizadas | key/generation/state/projection tests | Domain/Security | Sim |
| `OVERVIEW_READY` | Atenção operacional sem aggregate leak | filters/source/aggregate A/B | Domain/Security | Sim |
| `REPORTING_READY` | Dashboard/Reports/PDF não ampliam acesso | formula/projection/export/cost/PDF tests | Domain/Security | Sim |
| `PLATFORM_READY` | Global Admin separado e mínimo | target/reason/capability/Audit/negative tests | Security/Platform | Sim para piloto |
| `OPERATIONS_READY` | Produto observável, recuperável e promovível | release/health/capacity/kill-switch/security evidence | Operations/Security | Sim |
| `SCHEMA_READY` | Cadeia de schema íntegra e compatível | from-zero/forward/checksums/constraints | Data/Architecture | Sim |
| `SECURITY_READY` | Security review transversal fechado | threat/control review e full negative suite | Security | Sim |
| `MIGRATION_TOOLING_READY` | Contratos 10A–10D executáveis | tooling tests, fixtures, reports, audit | Data/Security/Platform | Sim |
| `REHEARSAL_READY` | Pré-condições de rehearsal completas | manifests, env, owners, backup/restore, tooling | Operations/Data | Sim |
| `CUTOVER_READY` | R4 e recovery aprovados | CP4 bundle e zero blocker | Operations/Security/Data/Business | Sim |
| `PILOT_READY` | GO humano e pre-cutover completos | CP4 + RV-08 + gate matrix + approval | Business/Operations/Security | Sim |
| `SECOND_TENANT_READY` | Expansão não cria vazamento/coupling Serena | CP10, interleaved A/B e reconciliation | Security/Operations/Data/Business | Sim |

Feature gate aprovado exige que todos os subgates aplicáveis estejam aprovados; `N/A` requer justificativa e owner.

## 38. Blockers

### 38.1 Taxonomia

| Classe | Uso |
| --- | --- |
| `ARCHITECTURE_BLOCKER` | Contradição real com decisão `CLOSED`; exige change control |
| `DESIGN_BLOCKER` | Contrato físico/semântico ainda necessário antes de modelar/implementar |
| `IMPLEMENTATION_BLOCKER` | Limitação concreta de toolchain/provider/código descoberta durante execução |
| `SECURITY_BLOCKER` | Controle ou teste crítico falha ou não pode ser provado |
| `DATA_BLOCKER` | Registro/volume/qualidade/semântica impede mapping ou ativação |
| `REMOTE_REVALIDATION_BLOCKER` | Evidência remota obrigatória ainda não foi obtida/selada |
| `MIGRATION_BLOCKER` | Tooling, idempotência, provenance, reconciliação ou delta insuficientes |
| `CUTOVER_BLOCKER` | Condição impede GO/ativação/expansão |
| `BUSINESS_DECISION` | Escolha exige autoridade Domain/Business/Operations/Platform, não preferência técnica |

Não há `ARCHITECTURE_BLOCKER` ativo identificado nesta 10E. Se surgir, a wave para; o roadmap não altera silenciosamente a arquitetura congelada.

### 38.2 Registro consolidado

| ID | Classe | Description | Source | Affected wave | Blocking condition | Resolution owner/class | Resolution gate |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `DD-01` | DESIGN_BLOCKER | Hosting deve preservar deep links e same-artifact promotion | Arquitetura §41 | W0/W14 | Provider não suporta rota/config/release invariants | Platform/Architecture | `OPERATIONS_READY` |
| `DD-02` | DESIGN_BLOCKER | Schema físico Identity/User/Membership/lifecycle | 10C §5–9 | W1 | Conceitos colapsados ou membership comum não única | Architecture/Security/Data | `TENANT_READY` |
| `DD-03` | DESIGN_BLOCKER | Catálogo físico Resource/Action/Scope e alcance por recurso | 10B §9; 10C §11 | W2 e cada feature | Action/scope desconhecido ou amplo | Security/Domain | `AUTHORIZATION_READY`/feature gate |
| `DD-04` | DESIGN_BLOCKER | Schema/retention inicial de Audit/History/Outbox | Arquitetura §21–26 | W3 | Audit não append-only/transactional ou conceitos misturados | Security/Architecture | `AUDIT_READY` |
| `DD-05` | DESIGN_BLOCKER | Namespace/fingerprint de idempotência e lock order | Arquitetura §11–12 | W3+ | Replay duplica efeito ou deadlock/lost update não controlado | Architecture/Security | `AUDIT_READY` |
| `DD-06` | DESIGN_BLOCKER | Topologia/classes físicas de bucket/key | Arquitetura §20; 10C §22 | W5 | Implementação depende de path/quantidade arbitrária | Platform/Security | `STORAGE_FOUNDATION_READY` |
| `DD-07` | DESIGN_BLOCKER | Integrity/checksum tiers por classe de arquivo | 10C §25 | W5/W15 | Evidence fica AVAILABLE sem integridade adequada | Security/Data/Platform | Storage gate |
| `DD-08` | DESIGN_BLOCKER | Assignment combinations de Request | Pedido 10E §32 | W7 | Modelo permite combinações incoerentes ou não cobre regra | Domain | `REQUEST_READY` |
| `DD-09` | DESIGN_BLOCKER | Decomposição de OS actions/scopes | 10B §14 | W8/W9 | `os_editar` vira patch amplo | Domain/Security | `OS_CORE_READY` |
| `DD-10` | DESIGN_BLOCKER | Semântica de responsável, executores e Equipe | PRODUCT_SPEC §5 | W8 | Responsável confundido com executor | Domain | `OS_CORE_READY` |
| `DD-11` | DESIGN_BLOCKER | Formato/versionamento de checklist snapshot | Arquitetura §19 | W9 | Modelo editável reescreve execução histórica | Domain/Data | `OS_READY` |
| `DD-12` | DESIGN_BLOCKER | Time semantics preventiva | Pedido 10E §37 | W10 | Timezone/DST/month-end/catch-up indefinidos | Domain/Architecture | `PREVENTIVE_READY` |
| `DD-13` | DESIGN_BLOCKER | Occurrence identity/cursor físico | PRE-01; 10B §16 | W10 | Possibilidade de duplicate OS/cursor órfão | Domain/Data/Platform | `PREVENTIVE_READY` |
| `DD-14` | DESIGN_BLOCKER | Persistência/materialização de Alerts | Arquitetura §25 | W11 | Dedup/state/source authorization não demonstrados | Architecture/Domain | `ALERT_READY` |
| `DD-15` | DESIGN_BLOCKER | Libraries/contracts chart/PDF e geração async | Arquitetura §41 | W12 | Export/projection/performance inseguros | Architecture/Security | `REPORTING_READY` |
| `DD-16` | DESIGN_BLOCKER | SLI/health/readiness e release gates concretos | 10D §34–35 | W14 | Health falso ou thresholds arbitrários | Operations/Platform | `OPERATIONS_READY` |
| `IB-01` | IMPLEMENTATION_BLOCKER | Toolchain incompatível com strict/build/test/local DB | W0 definition | W0 | Não há build/test/rebuild reproduzível | Architecture | `FOUNDATION_READY` |
| `IB-02` | IMPLEMENTATION_BLOCKER | Storage/Auth local não reproduz comportamento necessário | Arquitetura §33 | W1/W5 | Mocks seriam usados como prova oficial | Platform | Feature security gate |
| `IB-03` | IMPLEMENTATION_BLOCKER | Capacity ou supply-chain incompatíveis | Arquitetura §38 | W14 | Dependência insegura/sem licença ou capacidade insuficiente | Platform/Security | `OPERATIONS_READY` |
| `SB-01` | SECURITY_BLOCKER | Evaluator RLS circular, permissivo ou com grants inseguros | RLS-01 | W2 | Policy/helper não prova least privilege | Security | `AUTHORIZATION_READY` |
| `SB-02` | SECURITY_BLOCKER | Storage usa path/payload como autoridade | STO-01 | W5+ | Cross-tenant object access/finalize possível | Security/Platform | Storage/Security gate |
| `SB-03` | SECURITY_BLOCKER | Mention/comment/source pode vazar acesso | Arquitetura §23 | W7 | Usuário sem parent access recebe conteúdo/existência | Security | `REQUEST_READY` |
| `SB-04` | SECURITY_BLOCKER | Boundary de validação/autovalidação da OS | PRODUCT_SPEC §5.5 | W9 | Executor valida sem capability/policy | Security/Domain | `OS_READY` |
| `SB-05` | SECURITY_BLOCKER | Worker/scheduler recebe authority do payload | TECH-01 | W10+ | Handler/tenant não relidos/allowlisted | Security/Platform | `PREVENTIVE_READY` |
| `SB-06` | SECURITY_BLOCKER | Notification/Calendar/Overview revelam source/aggregate | Arquitetura §24–25 | W11 | Existence/count/link leak | Security | Attention gates |
| `SB-07` | SECURITY_BLOCKER | Dashboard/Report/export amplia linha/campo/custo | PRODUCT_SPEC §12–13 | W12 | Aggregate/export leak | Security | `REPORTING_READY` |
| `SB-08` | SECURITY_BLOCKER | Platform authority vira bypass tenant | PLAT-01 | W13 | Endpoint genérico/union/impersonation | Security/Platform | `PLATFORM_READY` |
| `SB-09` | SECURITY_BLOCKER | Findings transversais críticos abertos | Arquitetura §38 | W14+ | Auth/RLS/Storage/secrets/supply-chain falham | Security | `SECURITY_READY` |
| `RRB-01` | REMOTE_REVALIDATION_BLOCKER | Schema/RLS/grants/functions/triggers/sequences/Edge drift desconhecido | 10A §21 | W15 | Rule/tooling final seria baseado só no repo | Data/Platform/Security | RV-01 |
| `RRB-02` | REMOTE_REVALIDATION_BLOCKER | Dados/volumes/vocabulários/relations reais desconhecidos | 10B §33 | W15 | Mappings/tolerâncias não podem congelar | Data/Domain | RV-02 |
| `RRB-03` | REMOTE_REVALIDATION_BLOCKER | Auth/membership/permissions/platform reais desconhecidos | 10C §34 | W15/W16 | Path A/B e privilege mapping indefinidos | Security/Platform/Data | RV-03 |
| `RRB-04` | REMOTE_REVALIDATION_BLOCKER | Storage manifest/policies/objects reais desconhecidos | 10C §34.6 | W15/W16 | Copy/integrity/reconciliation indefinidos | Platform/Data/Security | RV-04 |
| `RRB-05` | REMOTE_REVALIDATION_BLOCKER | Writers/delta/source drift desconhecidos | 10D §11–12/21–22 | W15/W16 | Consistency Envelope incompleto | Platform/Data/Operations | RV-05/RV-07 |
| `DATA-01` | DATA_BLOCKER | Tenant/cross-tenant/orphan mapping | 10A §23 | W15–W17 | Registro crítico sem tenant/destino seguro | Data/Security/Domain | Quarantine + L2/L4 |
| `DATA-02` | DATA_BLOCKER | Identity/membership/platform candidate ambíguo | 10C §32 | W15–W17 | Acesso ou autoria crítica sem resolução | Security/Platform/Data | Auth/GO gate |
| `DATA-03` | DATA_BLOCKER | Codes/counters/status/type/occurrence collision | 10B §26/29 | W15–W17 | Reuse ou semântica operacional incorreta | Data/Domain | Code/Semantic gate |
| `DATA-04` | DATA_BLOCKER | Arquivo/evidência crítico ausente ou inconsistente | 10C §24–25 | W15–W17 | Evidence loss/integrity não resolvida | Data/Security/Business | Storage gate |
| `MB-01` | MIGRATION_BLOCKER | Schemas/contratos de Run, registry, quarantine, evidence e Audit técnico | 10D §50.1 | W15 | Tooling não rastreia source↔target/decision | Data/Architecture/Security | `MIGRATION_TOOLING_READY` |
| `MB-02` | MIGRATION_BLOCKER | Delta por writer/domínio/deletes não cobre janela | 10D §22 | W15/W16 | Insert/update/delete pode se perder | Data/Platform | CP4/CP6 |
| `MB-03` | MIGRATION_BLOCKER | Criticidade/tolerância e equações não aprovadas | 10D §4.3/16 | W15/W16 | Count pode esconder perda/leak | Data/Domain/Business | Reconciliation gate |
| `MB-04` | MIGRATION_BLOCKER | Auth Path A/B e Legacy/Unresolved Actor físicos | 10C §6/14 | W15 | Reference mapping/autoria não implementáveis | Security/Data/Platform | Auth tooling gate |
| `MB-05` | MIGRATION_BLOCKER | Failure injection/recovery não reproduzíveis | 10D §27/43 | W16 | Rehearsal não prova recovery | Operations/Data/Security | CP4 |
| `CB-01` | CUTOVER_BLOCKER | R4, backup/restore ou recovery não aprovados | 10D §18/39 | W17 | Ausência de CP4/recovery proof | Operations/Data/Security | `CUTOVER_READY` |
| `CB-02` | CUTOVER_BLOCKER | Artifact/RC/config digest difere do rehearsal | 10D §6 | W17 | Cadeia não é a validada | Platform/Operations | GO |
| `CB-03` | CUTOVER_BLOCKER | Health/capacity/observability/kill switch falha | 10D §34 | W17 | Incidente não seria detectável/isolável | Operations/Platform/Security | GO |
| `CB-04` | CUTOVER_BLOCKER | Critical failed ou blocking quarantine > 0 | 10D §18/24 | W17 | Dado crítico sem resolução | Data/Security/Business | GO |
| `CB-05` | CUTOVER_BLOCKER | RLS/Auth/permission/code/Storage/delta final falha | 10D §48–50 | W17 | Invariante crítica não provada | Security/Data/Platform | GO |
| `CB-06` | CUTOVER_BLOCKER | Passo crítico sem owner/reviewer/approval | 10D §44–45 | W17 | Separation of duties incompleta | Operations/Business | GO |
| `BD-01` | BUSINESS_DECISION | Entitlements iniciais e tenant status de ativação | 10C §9 | W1/W13/W15 | Default deny impede ativação sem decisão | Platform/Business | Tenant/Platform/Migration gate |
| `BD-02` | BUSINESS_DECISION | Delegabilidade e capabilities reservadas CW | Arquitetura §10 | W2 | Antiescalada não classificável | Security/Platform | `AUTHORIZATION_READY` |
| `BD-03` | BUSINESS_DECISION | Taxonomia mínima de Cadastros | PRODUCT_SPEC §3/11 | W4 | Domínios não têm referências aprovadas | Domain/Business | `CADASTRO_READY` |
| `BD-04` | BUSINESS_DECISION | Tipos/especialidades/documentos de Supplier | PRODUCT_SPEC §9 | W6 | Catalogs seriam inventados | Domain/Business | `SUPPLIER_READY` |
| `BD-05` | BUSINESS_DECISION | Janela concreta de edição de comentário | Arquitetura §23 | W7 | EDIT rule incompleta | Domain/Business/Security | `REQUEST_READY` |
| `BD-06` | BUSINESS_DECISION | UOM mínima para materiais | GAP §15 | W8 | Materiais estruturados sem unidade segura | Domain | `OS_CORE_READY` |
| `BD-07` | BUSINESS_DECISION | Casos ambíguos da matriz Request × OS | Pedido 10E §35 | W9 | Feature não pode inventar automação | Domain/Business | `OS_READY` |
| `BD-08` | BUSINESS_DECISION | Deadline canônico de OS | Pedido 10E §68 | W11 | `WORK_ORDER_OVERDUE` não pode ser calculado | Domain/Business | `ALERT_READY` |
| `BD-09` | BUSINESS_DECISION | Platform identities/operations/limits iniciais | 10C §12 | W13/W15 | Global Admin/entitlement não ativáveis | Platform/Business/Security | `PLATFORM_READY` |
| `BD-10` | BUSINESS_DECISION | Retention/legal, waivers permitidos e rollout Serena | 10D §38/53 | W15–W17 | Evidence/purge/pilot acceptance indefinidos | Business/Operations/Security/Data | GO/CP10 |

## 39. Deferred Decisions

Decisões deferidas permanecem abertas somente até o deadline da próxima seção. Elas não permitem default permissivo. A ausência de decisão resulta em redução segura de escopo, review/quarantine ou bloqueio da wave.

Grupos consolidados:

- routing: formato final de `tenantRef`;
- schema: detalhes físicos de entidades, registry, quarantine, staging, Audit e actors legados;
- Auth: Path A/B, password/session/MFA/invitation provider-specific;
- authorization: catálogo físico Resource/Action/Scope, alcance por recurso, baselines, overrides e sensitive projections;
- domínio: Request assignment, Request×OS, OS deadline, comment window, Asset Local inheritance, UOM e taxonomias;
- preventiva: timezone/civil time/DST/catch-up/missed/reschedule/version/occurrence;
- Storage: bucket classes/topology, key strategy, checksum/integrity e retention;
- async/platform: worker/scheduler provider, technical credentials e handler topology;
- information: alert materialization, chart/PDF libraries, report generation mode;
- operations: hosting, observability provider, health thresholds, feature/config allowlist;
- migration: manifest/tool runtime, delta/deletes, tolerâncias, safe-next/allocator, reverse delta;
- cutover: window, maximum duration, abort thresholds, staffing, Serena thresholds/cohort/order;
- legal/business: retention, initial entitlements, platform identities, discard/waivers.

Cache server-side, materialized views, partitioning, tracing distribuído e advanced feature flags continuam deferidos até evidência de necessidade; não bloqueiam as waves atuais se não forem usados.

## 40. Decision Deadlines

| Decision | Current State | Must Be Closed Before | Why | Owner Class |
| --- | --- | --- | --- | --- |
| `DEC-01` formato `tenantRef` | DEFERRED | W1 exit | Resolver tenant route sem transformar selector em authority e estabilizar links | Architecture/Security |
| `DEC-02` catálogo físico Resource/Action/Scope e scopes fundacionais | IMPLEMENTATION-DEPENDENT | W2 entry | Policies/commands não podem usar action/scope genéricos | Security/Domain |
| `DEC-03` schemas físicos por wave | IMPLEMENTATION-DEPENDENT | MODEL de cada wave | Migrations/constraints/types exigem contrato revisado | Architecture/Data |
| `DEC-04` Auth Path A/B e continuidade suportada | REVALIDATION_REQUIRED | W15 Auth mapper; no máximo antes de W16 R3 | Referências, convite/recovery e acesso dependem do provider real | Security/Platform/Data |
| `DEC-05` Asset Local inheritance e profundidade | IMPLEMENTATION-DEPENDENT | W5 MODEL | Hierarquia não pode propagar localização por suposição | Domain/Architecture |
| `DEC-06` bucket classes/topology e target key | PROVIDER-DEPENDENT | W5 MODEL | Storage implementation precisa de classes/lifecycle sem usar path como authority | Platform/Security |
| `DEC-07` checksum/integrity tier por arquivo | PROVIDER/RISK-DEPENDENT | W5 exit; refinado antes de W15 | AVAILABLE e migração de evidência exigem política objetiva | Security/Data/Platform |
| `DEC-08` comment edit window | DEFERRED | W7 MODEL | Action EDIT precisa de regra temporal e auditável | Domain/Business/Security |
| `DEC-09` preventive time/occurrence semantics | DEFERRED | W10 MODEL | Evitar duplicate occurrence e cursor incorreto | Domain/Architecture/Platform |
| `DEC-10` deadline canônico de OS | DEFERRED | `WORK_ORDER_OVERDUE` em W11 | Alerta não pode inventar data-limite | Domain/Business |
| `DEC-11` Alert calculated/materialized/hybrid | IMPLEMENTATION-DEPENDENT | W11 MODEL | Dedup, ACTIVE/RESOLVED e query security dependem da escolha | Architecture/Domain |
| `DEC-12` chart/PDF libraries e sync/async | IMPLEMENTATION-DEPENDENT | W12 IMPLEMENT | Segurança, licença, acessibilidade, tamanho e volume | Architecture/Security |
| `DEC-13` Legacy/Unresolved Actor físico e UX | DESIGN REQUIRED | W15 history mapper; contrato base antes de W3 migration hooks | Não fabricar ator e preservar FKs/projections | Data/Security/Domain |
| `DEC-14` Migration Run/registry/quarantine/evidence/staging/tool runtime | DESIGN REQUIRED | W15 MODEL | Tooling e provenance precisam de identities imutáveis | Data/Architecture/Security |
| `DEC-15` delta/deletes por writer/domínio | REVALIDATION_REQUIRED | W15 exit; antes de W16 R3 | Freeze/cutover exige insert/update/delete coverage | Data/Platform/Operations |
| `DEC-16` criticidade/tolerância por domínio | BUSINESS/DATA DECISION | W15 reconciliation freeze | Não existe tolerância percentual genérica | Data/Domain/Business/Security |
| `DEC-17` window/maximum duration/abort threshold/staffing | CUTOVER_ONLY | W16 R4 exit | Valores vêm de medição e governam NO-GO/R1 | Operations/Business |
| `DEC-18` reverse delta/Return to V1 strategy | DESIGN/OPERATIONS REQUIRED | W16 R4 exit | Após writes, retorno não é simples rollback | Operations/Data/Security/Business |
| `DEC-19` hosting/workers/observability providers | PROVIDER-DEPENDENT | W10 worker e W14 release/hardening | Topologia precisa preservar invariants e operability | Platform/Architecture |
| `DEC-20` retention/legal/incident hold/purge eligibility | LEGAL/RETENTION-DEPENDENT | W15 evidence schema; final antes de W17 P15 | Evidence/quarantine/V1 não podem ser apagados implicitamente | Business/Security/Data |
| `DEC-21` initial entitlements e platform identities | BUSINESS/PLATFORM DECISION | W13 exit e W15 mapping | Ativação/default deny e Global Admin exigem aprovação explícita | Platform/Business/Security |
| `DEC-22` matriz Request × OS ambígua | DOMAIN DECISION | W9 MODEL | Cancel/close/reopen/unlink/transfer não podem ser automatizados sem regra | Domain/Business |

## 41. Definition of Done

### 41.1 DoD geral de wave

Conforme aplicável, uma wave só termina quando:

1. objetivo e fora de escopo continuam respeitados;
2. requisito e decisões `CLOSED` foram rastreados;
3. modelo e migrations são versionados, reproduzíveis e tipados;
4. implementação não espalha acesso direto a Supabase nem generic CRUD/patch crítico;
5. queries, commands, errors e projections possuem contratos;
6. unit/component/contract/DB/E2E aplicáveis passam;
7. testes negativos, Tenant A/B, RLS e concorrência aplicáveis passam;
8. Security review explícito fecha findings ou mantém blocker;
9. observabilidade, correlation, redaction e release identity existem no novo fluxo;
10. mobile, accessibility e estados de UI foram verificados quando aplicável;
11. impacto migratório, registry/quarantine/reconciliation future requirements foram registrados;
12. rollback/recovery/roll-forward relevance foi exercitada ou documentada na proporção do risco;
13. documentação e `database.types.ts` estão atualizados;
14. nenhum decision deadline vencido nem blocker incompatível permanece;
15. diff foi revisado e o Git termina limpo após commit coerente.

### 41.2 DoD de migration/rehearsal/cutover

Além do geral:

- Migration Run e artifact/source identities fecham;
- cada source elegível aparece em mapping/quarantine/legacy/approved-discard/failed;
- `failed critical = 0` e blocking quarantine = 0 no gate aplicável;
- L1–L4 fecham por tenant/domínio/run;
- Auth, permission, codes, History/Provenance/Audit e Storage reconciliam;
- backup correto e restore demonstrado;
- evidence bundles e approvals são imutáveis e acessíveis;
- same artifact/digest é usado;
- single writer e recovery path são provados;
- GO permanece humano e separado da execução técnica.

## 42. Security Gates

Security review explícito é obrigatório antes de fechar W1–W3, W5, W7–W11, W13–W17. W4, W6 e W12 também exigem review do domínio/projection correspondente.

| Gate de segurança | Waves | Perguntas bloqueantes |
| --- | --- | --- |
| Auth/Tenant | W1 | Tenant deriva de fonte autoritativa? Lifecycle e cache invalidation funcionam? |
| Authorization/RLS | W2 | Álgebra exata, antiescalada, grants/helpers e A/B estão corretos? |
| Commands/Audit/Async | W3 | Reautorização transacional, idempotência, audit failure e handler allowlist estão provados? |
| Domain relationship | W4–W10 | Toda FK/child/association é tenant-aware e toda action é específica? |
| Storage | W5–W10 | Reserve/finalize reautoriza objeto/parent/tenant/fatos reais? |
| Projection/Information | W11–W12 | Link, notification, calendar, aggregate, report e export preservam source access? |
| Platform | W13 | Capability/target/reason/Audit substituem qualquer bypass? |
| Transversal | W14 | Auth/RLS/commands/Storage/XSS/injection/exports/workers/secrets/supply chain fecham? |
| Migration | W15–W16 | Technical authority, default deny, provenance, L4, delta e recovery estão provados? |
| Cutover/Pilot | W17 | Final A/B, same digest, health/kill switch, GO e incident response estão aprovados? |

Falha confirmada de cross-tenant, privilege escalation, unauthorized platform action ou critical evidence exposure interrompe a wave/rollout, isola o escopo, preserva evidence e exige correção versionada + novo gate.

## 43. Roadmap Table

| Wave | Capability | Dependencies | Classification | Main Gate | Remote Revalidation | Migration Impact |
| --- | --- | --- | --- | --- | --- | --- |
| W0 | Engineering foundation | 10E approval | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | FOUNDATION_READY | — | Migrations/types/test/release substrate |
| W1 | Identity/Tenant/Membership | W0 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | TENANT_READY, AUTH_READY | RV-03 only before mapping | Target identity model |
| W2 | Authorization/RLS | W1 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | AUTHORIZATION_READY | RV-01/RV-03 before legacy mapping | Target capability/default-deny model |
| W3 | Commands/Audit/History/Outbox | W2 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | AUDIT_READY | RV-01 before writer/history mapping | Technical Audit and transactional substrate |
| W4 | Cadastros/Teams | W3 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | CADASTRO_READY | RV-02 before W15 | Mapping targets for structural data |
| W5 | Assets/Storage foundation | W4 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | ASSET_READY, STORAGE_FOUNDATION_READY | RV-04 before W15/R3 | Asset codes/files target |
| W6 | Suppliers | W4/W5 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | SUPPLIER_READY | RV-02/RV-04 before W15 | Prestador→Supplier/documents target |
| W7 | Requests/Comments | W4–W6 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | REQUEST_READY | RV-02 before W15 | Demanda mapping/codes/history/files |
| W8 | OS Core | W7 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | OS_CORE_READY | RV-02 before W15 | OS core/assignments/costs target |
| W9 | OS Completion/Validation | W8 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | OS_READY | RV-02 before W15 | Status/aceite/checklist/evidence mapping |
| W10 | Preventive | W9 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | PREVENTIVE_READY | RV-02/RV-05 before W15/R3 | Plan/Schedule/Occurrence target |
| W11 | Operational Attention | W7–W10 | MVP_CRITICAL, PILOT_CRITICAL | OPERATIONAL_ATTENTION_READY | RV-02 before secondary-data mapping | Regenerate views; conditional notifications |
| W12 | Dashboard/Reports | W11 | MVP_CRITICAL, PILOT_CRITICAL | REPORTING_READY | RV-02/RV-06 for volume | REGENERATE projections/reports |
| W13 | Platform Operations | W1–W3/domains | MIGRATION_CRITICAL, PILOT_CRITICAL | PLATFORM_READY | RV-03 before identity mapping | Platform identities/entitlements |
| W14 | Operational/Release Hardening | W0–W13 | MVP_CRITICAL, MIGRATION_CRITICAL, PILOT_CRITICAL | OPERATIONS_READY, SCHEMA_READY, SECURITY_READY | RV-06 before W16 | Artifact/schema/evidence compatibility |
| W15 | Migration Tooling | W14 + RV-01–05 | MIGRATION_CRITICAL, PILOT_CRITICAL | MIGRATION_TOOLING_READY | RV-01–RV-05 | Implements 10A–10D contracts; no cutover |
| W16 | Rehearsals/Readiness | W15 + RV-06/07 | MIGRATION_CRITICAL, PILOT_CRITICAL | REHEARSAL_READY, CUTOVER_READY | RV-06/RV-07 | R1–R4, recovery, final dress |
| W17 | Serena/Expansion | W16 + RV-08 + human GO | MIGRATION_CRITICAL, PILOT_CRITICAL, POST_PILOT | PILOT_READY, SECOND_TENANT_READY | RV-08 | Production cutover, stabilization, expansion |

## 44. Execution Matrix

Legenda: `●` principal, `○` secundário, `—` não aplicável.

| Wave | DB | Backend | Frontend | Security | Storage | Async | Tests | Migration |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| W0 | ○ | ○ | ● | ○ | — | — | ● | ○ |
| W1 | ● | ● | ● | ● | — | ○ | ● | ○ |
| W2 | ● | ● | ○ | ● | ○ | ○ | ● | ● |
| W3 | ● | ● | ○ | ● | — | ● | ● | ● |
| W4 | ● | ● | ● | ● | — | ○ | ● | ● |
| W5 | ● | ● | ● | ● | ● | ○ | ● | ● |
| W6 | ● | ● | ● | ● | ● | ○ | ● | ● |
| W7 | ● | ● | ● | ● | ● | ● | ● | ● |
| W8 | ● | ● | ● | ● | ○ | ● | ● | ● |
| W9 | ● | ● | ● | ● | ● | ● | ● | ● |
| W10 | ● | ● | ● | ● | ○ | ● | ● | ● |
| W11 | ○ | ● | ● | ● | ○ | ● | ● | ○ |
| W12 | ○ | ● | ● | ● | ○ | ○ | ● | ○ |
| W13 | ● | ● | ● | ● | ○ | ○ | ● | ● |
| W14 | ● | ● | ● | ● | ● | ● | ● | ● |
| W15 | ● | ● | ○ | ● | ● | ● | ● | ● |
| W16 | ● | ● | ○ | ● | ● | ● | ● | ● |
| W17 | ● | ● | ● | ● | ● | ● | ● | ● |

## 45. Revalidation Table

| Revalidation | Required Before | Environment | Evidence | Blocking |
| --- | --- | --- | --- | --- |
| RV-01 schema/security/technical drift | W15 MODEL e novo freeze de rule set | PRODUCTION source, read-only autorizado | Schema fingerprint; tables/columns/constraints/indexes/views; RLS/grants/functions/triggers/sequences/Edge/release inventory | Sim para W15 final |
| RV-02 data/volume/quality/domain vocabularies | W15 mapping rules; volume decisions de W12/W16 | PRODUCTION source, read-only autorizado | Counts/distributions por tenant; codes; orphans; cross-tenant; enums; relations; authorship; plans/OS/history | Sim |
| RV-03 Auth/membership/permissions/platform | W15 Auth/permission mapper e W16 R3 | PRODUCTION Auth/app, read-only autorizado | UUID/provider/lifecycle/profile/membership/permission/bypass/platform candidate manifest | Sim |
| RV-04 Storage | W15 Storage tooling e W16 R3 | PRODUCTION Storage/DB metadata, read-only autorizado | Buckets/settings/policies/objects/metadata/parents/tenant/size/MIME/checksum/orphan manifest | Sim |
| RV-05 writers/delta | W15 delta design exit e W16 R3 | Source application/platform | Writer inventory; in-flight; timestamps/log/CDC/full-compare capability; inserts/updates/deletes coverage | Sim |
| RV-06 hosting/STAGING/config/release/health | W16 R3/R4 | TEST/STAGING | Environment identity, RC/digests, config schema, health/capacity/observability and deep-link evidence | Sim |
| RV-07 pre-dress source drift/snapshot equivalence | W16 R4 | Authorized source + STAGING | Fresh drift report, Consistency Envelope candidate, volume/resource equivalence and updated blockers | Sim |
| RV-08 final pre-cutover | W17 P7/CP5 | PRODUCTION source/target | Final schema/data/Auth/Storage/RLS/grants/functions/triggers/sequences/Edge/buckets/config/release/writers/backup/restore/delta evidence | Sim; NO-GO if incomplete |

Cada evidence registra alvo, environment, project ID, timestamp, tool/query/version, actor autorizado, boundary, hash/fingerprint e reviewer. O projeto proibido nunca aparece como target válido.

## 46. Effort / Risk

| Wave | Effort | Risk | Drivers |
| --- | --- | --- | --- |
| W0 | M | MEDIUM | Toolchain, boundaries, local DB and test reproducibility |
| W1 | L | HIGH | Auth lifecycle, tenant context, membership and cache |
| W2 | XL | CRITICAL | RLS, exact scopes, antiescalation and grants |
| W3 | L | HIGH | Transactions, idempotency, Audit and async fencing |
| W4 | L | HIGH | Hierarchies, TEAM scope and shared domain references |
| W5 | XL | CRITICAL | Asset hierarchy/codes plus Storage authorization |
| W6 | L | HIGH | Canonical replacement, documents and multi-relations |
| W7 | XL | CRITICAL | Full Request vertical, transitions, codes, files/comments |
| W8 | XL | CRITICAL | OS assignments, execution, concurrency and code allocation |
| W9 | XL | CRITICAL | Validation, snapshot, evidence and Request×OS matrix |
| W10 | XL | CRITICAL | Time semantics, occurrence idempotency and scheduler |
| W11 | L | HIGH | Derived access, notification/link/aggregate leakage |
| W12 | L | HIGH | Aggregations, sensitive projections, exports and PDF |
| W13 | L | CRITICAL | Platform authority and cross-tenant blast radius |
| W14 | XL | CRITICAL | Cross-cutting security, release, capacity and recovery |
| W15 | XL | CRITICAL | Multi-system identity, data, Storage and reconciliation |
| W16 | XL | CRITICAL | Prod-like rehearsal, delta, restore and failure injection |
| W17 | XL | CRITICAL | Production cutover, single writer, pilot and expansion |

`XL` não significa uma única PR ou commit. A wave é dividida em substeps coerentes dentro do mesmo gate, com checkpoints revisáveis e sem declarar a capacidade pronta antes da integração vertical.

## 47. Codex Governance

Codex pode futuramente, dentro da wave autorizada:

- analisar requisitos/fontes e produzir plano pequeno;
- criar feature branch curta quando solicitado;
- modelar e implementar código/migrations locais;
- gerar tipos e documentação;
- executar testes locais/CI autorizados;
- revisar diff/PR;
- preparar artifact/release/migration manifests;
- executar dry-runs e operações locais seguras;
- produzir evidence e relatórios sem secrets.

Codex não pode autonomamente:

- aprovar produção, GO, waiver, platform identity ou descarte;
- acessar/usar secrets sem autorização;
- executar migration/carga/cutover em produção;
- alterar branch protection, fazer merge/push não solicitado ou modificar `main`;
- criar bypass, relaxar RLS, usar service role no frontend ou assumir tenant/ator;
- apagar dados reais, V1, evidence, run, quarantine ou histórico;
- escolher decisão Business/Legal/Operations sem autoridade/evidência;
- reconstruir artifact entre STAGING e PRODUCTION.

Toda execução futura começa confirmando branch/worktree, requirement section, dependencies, Supabase/RLS/permissions/history/files/tests/reuse impacts e termina com testes, diff, riscos e Git status reais.

## 48. Implementation Start Point

A primeira wave após aprovação humana da 10E é exatamente:

```text
W0 — Fundação de engenharia reproduzível
```

Primeiro objetivo: tornar o novo target local executável e verificável sem introduzir domínio ou segurança fictícia.

Primeiros artefatos:

- workspace React/Vite/TypeScript strict;
- router Data Mode e app shell;
- boundaries de config, errors, Supabase/query/command e telemetry;
- tokens/primitives mínimos shadcn/Radix/Tailwind;
- test harness Vitest/RTL/Playwright e PostgreSQL/Supabase local compatível;
- migration runner/baseline e geração futura de tipos;
- scripts de build/type/lint/test;
- documentação curta das conventions.

Primeiros testes:

- build/typecheck/lint;
- configuration validation e safe errors;
- deep-link/refresh/back/forward/not-found;
- loading/error/no-permission state shell;
- component smoke/accessibility básica;
- Playwright smoke;
- database reconstruction from zero;
- boundary rule que impeça page de importar Supabase diretamente.

Primeiro gate: `FOUNDATION_READY`.

## 49. First Implementation Checkpoint

Ao terminar W0, a evidência objetiva será:

1. projeto React/Vite/TS strict inicia e produz build reproduzível;
2. router suporta `/e/:tenantRef/*` e `/plataforma/*` como boundaries opacos, deep links e history do navegador;
3. Query/Form/Zod/Supabase typed boundaries existem sem páginas acessando infraestrutura diretamente;
4. estados fundamentais e primitives acessíveis renderizam em desktop/mobile;
5. Vitest/RTL/Playwright e DB local são executáveis por comandos documentados;
6. migrations reconstroem o ambiente descartável do zero;
7. config inválida falha de forma segura e nenhum secret entra no bundle/log;
8. release/correlation identity básicas aparecem no diagnóstico local;
9. não existem tabelas, screens, permissions ou abstrações de domínio prematuras;
10. diff é revisável, documentação está atualizada e Git termina limpo após commit.

Esse checkpoint não declara `TENANT_READY`, `AUTH_READY`, `MVP_READY` nem qualquer readiness de migração.

## 50. Adversarial Review

| Risco procurado | Resultado/correção no roadmap |
| --- | --- |
| UI antes da segurança | W1–W3 antecedem domínios; cada UI depende de command/RLS aplicáveis |
| RLS deixada para hardening | RLS começa na primeira tenant-owned table e é gate de cada wave |
| `tenant_id` sem composite integrity | W1+ exigem parent/child tenant-aware por banco |
| UI guard como segurança | `CapabilityGate/Can` é apenas UX; RLS/commands são autoridade |
| JWT stale como autoridade | Auth metadata não decide tenant/profile/capability; cache é limpo no switch/block |
| Profile confundido com Membership | Conceitos separados em W1/W2 e migration registry |
| Global Admin confundido com tenant admin | W13 usa Platform Identity/commands separados |
| service role como autoridade funcional | Technical authority limitada, allowlisted e server-side |
| Storage path como autorização | W5 exige metadata/parent/tenant/finalize e object facts |
| Request fechada pela última OS | W9 testa explicitamente que há apenas sugestão |
| Preventive misturada a Request | W7 rejeita tipo; W10 possui modelo separado |
| Duplicate preventive occurrence | Unique occurrence + concurrent claim/retry tests em W10 |
| Audit adiada | W3 precede transitions críticas |
| Audit/History/Comment misturados | W3/W7 mantêm contracts e access distintos |
| Notification revela source | W11 usa conteúdo mínimo e reautorização no link |
| Reports ampliam acesso | W12 exige source scope, sensitive projection e A/B aggregate/export |
| Dashboard aggregate leak | W11/W12 testam count/value/cost cross-tenant |
| Calendar como autoridade | W11 é read model; reprogram command atua na origem |
| Serena-specific code | W17 proíbe build/schema/path/RLS/worker específicos |
| A/B apenas no final | Começa W1 e repete em cada entidade; W17 faz interleaved |
| Migration tooling cedo demais | W15 depende de schema/security/domain/operations ready |
| Cutover antes de rehearsal | W17 depende de W16 R4/CP4/CUTOVER_READY |
| Migration mutable após STAGING | W14/W16 selam checksums/digests e exigem nova migration |
| Rebuild entre STAGING e PROD | Release lifecycle promove os mesmos digests |
| Observability só no fim | W0/W3 iniciam; W14 consolida |
| Backup sem restore | Restore demonstrado é waiver-prohibited gate em W16/W17 |
| Rollback universal assumido | R0–R4, Point of No Simple Return e Roll Forward explícitos |
| Decision após a wave dependente | §40 fixa deadline anterior ao MODEL/IMPLEMENT/gate |
| Mega-wave impossível | OS está dividida; foundations são exercitadas; XL usa substeps/checkpoints |
| Micro-waves sem capacidade | Arquivos/tabelas isolados não são waves; cada gate prova capacidade vertical |
| Dados V1 corrigidos por fallback | W15 usa rule/review/quarantine, sem inferir tenant/ator/status |
| Código reutilizado no recovery | Safe-next só fecha após delta; todo código emitido fica consumido |
| Projeções migradas como autoridade | Calendar/Dashboard/Reports/Alerts são regenerados de fontes |
| Segundo tenant antes do isolamento real | W17 exige CP10 + interleaved A/B + approvals |

Nenhuma ocorrência adversarial conhecida permaneceu sem tratamento no roadmap. Itens sem evidência foram mantidos como decision deadline, blocker ou `REVALIDATION_REQUIRED`.

## 51. State of Readiness

Ao final documental desta 10E, após validação local e aprovação humana, pode-se declarar somente:

```text
ARCHITECTURE_PLANNING_COMPLETE
```

Estado por classe:

| Classe | Estado após 10E |
| --- | --- |
| Arquitetura e regras de ordenação | Planejadas/consolidadas |
| Waves, dependencies, gates e critical path | Definidos |
| Frontend/DB/domain implementation | Não iniciada nesta etapa |
| Remote state | `REVALIDATION_REQUIRED` |
| `SCHEMA_READY` | Não |
| `SECURITY_READY` | Não |
| `DOMAIN_READY` | Não |
| `MIGRATION_TOOLING_READY` | Não |
| `REHEARSAL_READY` | Não |
| `CUTOVER_READY` | Não |
| `PILOT_READY` | Não |
| `SECOND_TENANT_READY` | Não |
| `IMPLEMENTATION_COMPLETE` | Não |
| `MIGRATION_READY` | Não |
| `PRODUCTION_READY` | Não |

## 52. Conclusion

O plano consolida a V2 em 18 ondas ordenadas por dependência, segurança, integridade, domínio, migração, testabilidade e operação. O critical path começa por uma foundation pequena e reproduzível, prova tenant/RLS/Audit antes dos domínios, entrega verticais completas, endurece release/observabilidade, implementa tooling de migração somente quando o target está estável e exige R1–R4 antes do piloto.

W0 é o único ponto de início autorizado após aprovação humana deste documento. W17 só pode operar com R4, restore, delta, reconciliação, security gates e GO humano. Serena permanece tenant piloto do mesmo produto; a expansão para um segundo tenant depende de evidência interleaved A/B e CP10.

Este documento não implementou código, schema, migration, ETL, testes, infraestrutura ou produção. Nenhum remoto foi acessado. A conclusão correta da Fase A é `ARCHITECTURE_PLANNING_COMPLETE`; todos os demais estados de prontidão continuam pendentes até as waves correspondentes.
