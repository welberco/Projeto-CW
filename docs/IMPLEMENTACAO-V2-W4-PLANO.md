# Plano de implementação V2 — W4: Cadastros estruturais e scope TEAM

## 1. Objetivo

Este documento congela o plano executável da W4 do CW ERP V2. A W4 MUST
entregar os cadastros estruturais necessários aos domínios posteriores e o
fato de associação a Equipes necessário à semântica de `TEAM`, reutilizando
integralmente as fundações W0–W3.

Nome oficial da wave: **Cadastros estruturais e scope TEAM**.

Gate final oficial: `CADASTRO_READY`.

A W4 MUST NOT implementar funcionalidades operacionais de Ativos,
Fornecedores, Solicitações, Ordens de Serviço, Preventiva, Notificações,
Financeiro, Compras ou qualquer domínio de W5+.

## 2. Fontes de verdade e precedência

As fontes aplicáveis, em ordem de precedência documental, são:

1. `PRODUCT_SPEC.md`, para regras funcionais e de produto;
2. `docs/ARQUITETURA-TECNICA-V2.md`, para contratos arquiteturais;
3. `docs/MIGRACAO-V1-V2-10A-*.md` a `10D`, na ordem definida pelo plano de
   migração;
4. `docs/INVENTARIO-V1.md` e `docs/GAP-ANALYSIS-V1-V2.md`, como evidência do
   legado e dos gaps;
5. `docs/MIGRACAO-V1-V2-10E-PLANO-IMPLEMENTACAO.md`, como roadmap oficial
   W0–W17 e delimitador da wave;
6. `docs/IMPLEMENTACAO-V2-W3-PLANO.md` e
   `docs/IMPLEMENTACAO-V2-W3.md`, para os contratos já entregues em W3;
7. `docs/DEVELOPMENT-WORKFLOW.md` e `AGENTS.md`, para o processo operacional.

Quando uma fonte de menor precedência detalhar a alocação temporal sem
contradizer uma fonte superior, esse detalhamento MUST ser seguido. Nenhum
rascunho ou arquivo não rastreado é fonte oficial.

### 2.1 Resultado da descoberta

O roadmap 10E define W4 como “Cadastros estruturais e scope TEAM” e também a
resume como “Cadastros estruturais e Equipes”. O escopo inclui:

- Locais hierárquicos e seus tipos configuráveis;
- Centros de Custo, independentes de Local;
- Setores;
- Equipes e seus membros;
- Categorias e Subcategorias de Manutenção;
- motivos de pausa, cancelamento, rejeição e devolução;
- tipos de documento;
- esqueleto mínimo de modelos de checklist;
- padrões compartilhados de tabela, filtros, formulário, status,
  confirmação e seleção;
- rotas reais, consultas, segurança, testes e experiência mínima necessários
  para operar esses cadastros.

Não há contradição material entre as fontes. A menção explícita a “devolução”
no roadmap complementa as configurações previstas no `PRODUCT_SPEC.md`. A
classificação de Tags, unidades de medida avançadas e importação como
posteriores delimita a wave sem negar sua existência no produto futuro.

## 3. Estado de entrada

A implementação da W4 somente MAY começar quando:

- a branch aprovada partir do checkpoint W3;
- `W3_INFRASTRUCTURE_READY = YES`;
- W3A, W3B, W3C, W3D e W3E continuarem aprovadas;
- o worktree estiver conhecido e sem alterações fora de escopo;
- as decisões resolvidas neste plano forem implementadas sem reabrir escopo.

Checkpoint de planejamento:

- branch: `feat/v2-w3-history-outbox`;
- commit W3: `f1bbe236110c963ebfcfc56a4ad7e5b8243dc922`;
- Supabase: exclusivamente LOCAL durante implementação e validação;
- migrations W1–W3 MUST NOT ser alteradas retroativamente.

Toda alteração de banco da W4 MUST ocorrer em migrations forward-only novas.

## 4. Escopo classificado

### 4.1 MUST HAVE W4

- modelo tenant-aware de Locais, Tipos de Local, Centros de Custo, Setores,
  Equipes e membros de Equipe;
- modelo tenant-aware de Categorias, Subcategorias, Motivos, Tipos de
  Documento e Modelos de Checklist mínimos;
- hierarquia segura, proteção contra ciclos, status e inativação;
- catálogo de permissões W4, autorização exata e anti-escalation;
- fato persistido de associação ativa a Equipe;
- semântica `TEAM` para o recurso Equipe e contrato para recursos futuros;
- commands explícitos, queries/projeções, RLS, grants mínimos e isolamento;
- Audit, History, Event/Outbox e command idempotency onde definidos;
- concorrência real, controle de versão e constraints;
- rotas reais, páginas de lista/detalhe/formulário e estados completos;
- padrões compartilhados `CWDataTable`, `CWFilters`, `CWStatusBadge`,
  `CWConfirmDialog` e `CWUserSelector`, apenas na extensão necessária à W4;
- pgTAP, testes multi-session, unitários, E2E e regressão W0–W3;
- documentação da implementação real.

### 4.2 SHOULD HAVE W4

- busca textual normalizada nos cadastros que tenham volume suficiente;
- filtros persistidos na URL;
- paginação por cursor quando a cardinalidade justificar;
- seletores compactos com código + nome;
- reativação explícita de cadastros inativos, respeitando dependências.

Um item `SHOULD` somente MAY ser omitido com justificativa registrada no
documento de implementação da W4 e sem comprometer `CADASTRO_READY`.

### 4.3 DEFERRED / fora de escopo

- Tags;
- unidades de medida avançadas e conversões;
- importação XLSX/CSV;
- taxonomia extensa não aprovada;
- classificação automática ou migração de dados ambíguos da V1;
- anexos, buckets, upload e signed URLs;
- execução e snapshot de checklist;
- uso operacional dos cadastros por Ativos, Solicitações ou OS;
- notificações funcionais e consumidores de evento de produto;
- scheduler, worker de produção, integrações, e-mail e webhooks;
- relatórios funcionais;
- Global Admin funcional ou bypass administrativo novo;
- exclusão física normal;
- qualquer UI ou fluxo de W5+.

### 4.4 Outputs da W4

- migrations forward-only reproduzíveis para os cadastros aprovados;
- Template CW opcional e aplicação tenant-safe/idempotente;
- catálogo exato de permissions W4 e matriz TEAM;
- commands e read models tipados;
- rotas/páginas administrativas e padrões compartilhados necessários;
- schemas Zod, query keys e contratos TypeScript;
- Audit, History e eventos v1 transacionais;
- suites pgTAP, multi-session, unitárias e E2E;
- documento de implementação atualizado e evidência do gate
  `CADASTRO_READY`.

## 5. Decisões congeladas

1. Todas as entidades da W4 são tenant-owned e MUST possuir `tenant_id NOT
   NULL`.
2. IDs internos MUST ser UUID. Código humano, quando existente, MUST NOT ser
   usado como autoridade.
3. Centro de Custo MUST permanecer independente de Local.
4. Setor é divisão organizacional; Equipe é grupo operacional. Equipe MAY
   referenciar um Setor, mas não se confunde com ele.
5. Um usuário MAY participar de múltiplas Equipes. Equipe MUST NOT conceder
   Perfil, Permissão ou Entitlement.
6. Categoria/Subcategoria são o vocabulário mínimo da Manutenção, não um
   catálogo universal genérico.
7. Motivos MUST possuir tipo fechado: `pause`, `cancellation`, `rejection` ou
   `return`.
8. Cadastros MUST ser inativados, não apagados, no fluxo normal.
9. Alterações de status MUST ocorrer por commands explícitos.
10. Escrita direta do cliente nas tabelas MUST ser negada.
11. W4 MUST reutilizar Audit, History, Event/Outbox, idempotency e demais
    contratos W3; nenhuma infraestrutura paralela MAY ser criada.
12. Eventos W4 são fatos de domínio, não Event Store e não Event Sourcing.
13. Selectors MUST expor somente projeção mínima e somente registros
    autorizados/utilizáveis.
14. Campos de payload, rota, cache, código humano ou `tenantRef` MUST NOT ser
    autoridade final.
15. Nenhum seed, nome, código ou taxonomia inicial MAY ser inventado sem a
    aprovação registrada neste plano.
16. O Template CW é opcional, versionado e controlado pela plataforma, mas é
    somente fonte de criação inicial. Após a aplicação, os registros são
    tenant-owned e não possuem FK nem dependência operacional do template.
17. Alterar o Template CW MUST NOT sincronizar, reescrever ou inativar registros
    de tenants existentes.
18. Escolher início vazio MUST ser uma opção válida e não pode reduzir a
    segurança ou criar seeds implícitos.
19. O rollout de permissions W4 usa IDs e `template_key` oficiais W2, nunca o
    nome visível do Perfil.
20. Global Admin CW permanece fora da matriz tenant e segue `PLAT-01`.

## 6. Modelo de domínio

| Agregado/entidade | Responsabilidade | Invariantes principais |
| --- | --- | --- |
| Tipo de Local | Vocabulário tenant de tipos de Local | código/nome no tenant; inativo não pode ser escolhido |
| Local | Estrutura física hierárquica | pai no mesmo tenant; sem ciclos; tipo válido e ativo na criação |
| Centro de Custo | Estrutura contábil independente | código obrigatório e único no tenant; hierarquia opcional sem ciclos |
| Setor | Divisão organizacional | tenant correto; status explícito |
| Equipe | Grupo operacional | Setor opcional do mesmo tenant; não concede autorização por si só |
| Membro de Equipe | Período de associação entre membership e Equipe | membership ativa do mesmo tenant; uma associação ativa por par |
| Categoria | Classificação primária da Manutenção | código/nome tenant-aware; status explícito |
| Subcategoria | Classificação subordinada | categoria do mesmo tenant; não existe sem categoria |
| Motivo | Razão configurável por finalidade | contexto fechado/imutável; código único por tenant + contexto |
| Tipo de Documento | Vocabulário de documento | não representa arquivo, anexo ou storage |
| Modelo de Checklist | Definição reutilizável | itens ordenados; resposta em vocabulário aprovado; sem execução |
| Item de Modelo | Pergunta/instrução ordenada | posição única no modelo; tipo de resposta válido; obrigatório explícito |

### 6.1 Template CW opcional

Uma nova empresa MUST poder escolher:

- **Template CW:** aplicar explicitamente o template vigente aprovado; ou
- **Vazio:** iniciar sem taxonomia pré-carregada.

O Template CW v1 cria somente Categorias, Subcategorias e Motivos listados nas
seções 6.2 e 6.3. Tipos de Local, Tipos de Documento e Modelos de Checklist
começam vazios até cadastro tenant ou decisão futura aprovada. Isso evita seeds
não especificados e não impede que o tenant configure esses recursos.

`apply_cw_catalog_template` MUST:

1. derivar tenant e actor do contexto autoritativo;
2. exigir `shared.catalog_templates.apply.all_tenant`;
3. adquirir lock transacional comum a toda mutation dos catálogos-alvo;
4. aceitar somente `template_key`/versão allowlisted e idempotency key;
5. exigir que os catálogos-alvo ainda estejam vazios;
6. criar todos os registros tenant-owned na mesma transação;
7. criar History e Event de criação para cada registro e um Audit da aplicação;
8. concluir o resultado idempotente e a aplicação técnica na mesma transação;
9. falhar integralmente em colisão, estado não vazio ou efeito obrigatório;
10. retornar resultado estável com versão do template, IDs e contagens.

A aplicação MUST ser única por `(tenant_id, template_key)`, inclusive entre
versões futuras. Nova versão global vale para novos tenants; reaplicação ou
sincronização em tenant existente exige decisão futura explícita. Um tenant
que já iniciou cadastro manual MUST receber `TEMPLATE_TARGET_NOT_EMPTY`, sem
merge por nome/código e sem criação parcial.

O estado “vazio” não precisa criar registros artificiais. A ausência de uma
aplicação e a existência de nenhum registro são suficientes; o onboarding
apenas apresenta a escolha e, se selecionado o template, chama o command.

### 6.2 Taxonomia inicial do Template CW

As labels abaixo são dados iniciais editáveis do tenant após a cópia, não enums
imutáveis. Cada entrada global MUST possuir chave técnica ASCII estável,
separada da label traduzível. Códigos tenant copiados MUST ser determinísticos.

| Categoria | Subcategorias iniciais |
| --- | --- |
| Elétrica | Iluminação; Tomadas; Quadros elétricos; Circuitos; Iluminação de emergência |
| Hidráulica | Abastecimento; Vazamentos; Esgoto; Bombas; Reservatórios |
| Civil | Alvenaria; Pintura; Revestimentos; Impermeabilização; Cobertura |
| Climatização | Ar-condicionado; VRF; Ventilação; Exaustão |
| Segurança contra incêndio | Extintores; Hidrantes; Alarme; Iluminação de emergência |
| Elevadores | Elevadores; Plataformas; Transporte vertical |
| Portas e acessos | Portas; Fechaduras; Portões; Controle de acesso |
| CFTV e segurança eletrônica | Câmeras; Gravadores; Sensores |
| Jardinagem e áreas externas | Paisagismo; Irrigação; Áreas externas |
| Limpeza e conservação | Limpeza técnica; Conservação |
| Outros | classificação genérica residual |

“Iluminação de emergência” em Elétrica e Segurança contra incêndio é válida
porque a identidade da Subcategoria inclui a Categoria. “Outros” é fallback
tenant-editável, não wildcard de autorização nem autorização para ignorar
validação.

### 6.3 Motivos contextuais

Motivo MUST possuir `usage_context` controlado pela plataforma. A combinação
tenant + contexto + código identifica seu uso; label igual em contextos
diferentes não mistura semântica.

Contextos W4 iniciais:

- `CANCEL_REQUEST`;
- `REJECT_REQUEST`;
- `PAUSE_WORK_ORDER`;
- `CANCEL_WORK_ORDER`;
- `RETURN_WORK_ORDER`.

O contexto é enum/vocabulário técnico estável, não cadastro tenant. Novos
contextos exigem migration forward-only e contrato do domínio dono. W4 cria
somente infraestrutura/taxonomia; não implementa state machines de Request/OS.

Seeds do Template CW v1:

| Contexto | Motivos |
| --- | --- |
| `CANCEL_REQUEST` | Duplicidade; Solicitação indevida; Serviço não necessário; Impossibilidade de execução; Substituído por outra demanda; Outro |
| `REJECT_REQUEST` | Fora do escopo; Informação insuficiente; Solicitação improcedente; Duplicidade; Outro |
| `PAUSE_WORK_ORDER` | Aguardando material; Aguardando fornecedor; Aguardando acesso/liberação; Aguardando aprovação; Impedimento técnico; Outro |
| `CANCEL_WORK_ORDER` | nenhum seed até aprovação específica |
| `RETURN_WORK_ORDER` | nenhum seed até aprovação específica |

Uma referência futura MUST validar que o motivo está ativo, pertence ao mesmo
tenant e possui exatamente o contexto exigido pelo command. Payload não pode
alterar o contexto esperado. Selecionar “Outro” não define comportamento de
Request/OS nesta wave; eventual detalhe obrigatório pertence à wave dona.
`usage_context` é imutável após a criação; corrigir um contexto exige inativar
o motivo incorreto e criar outro no contexto certo, preservando History.

### 6.4 Dependências e inativação

- Inativar um Tipo de Local com Locais ativos MUST falhar.
- Inativar um Local ou Centro de Custo com filhos ativos MUST falhar; não há
  cascade silencioso.
- Inativar um Setor com Equipes ativas vinculadas MUST falhar.
- Inativar uma Equipe com membros ativos MUST falhar até que as associações
  sejam encerradas explicitamente.
- Inativar uma Categoria com Subcategorias ou Modelos ativos MUST falhar.
- Inativar um Modelo de Checklist MUST preservar integralmente sua definição.
- Registros inativos MUST permanecer legíveis quando necessários à evidência,
  mas MUST ser excluídos de lookup de novas relações.
- Domínios futuros MUST revalidar o status da referência dentro do command;
  um selector W4 não é prova de autorização ou validade posterior.

## 7. Modelo físico planejado

Os nomes abaixo são o contrato planejado. A implementação MUST confirmar a
convenção já usada no schema antes da primeira migration, sem alterar a
semântica.

Campos comuns das tabelas mutáveis: `id uuid`, `tenant_id uuid`, `status`,
`version bigint`, `created_at timestamptz`, `created_by uuid`, `updated_at
timestamptz`, `updated_by uuid`. Timestamps MUST vir do banco. `version` MUST
ser incrementada a cada mudança autoritativa.

| Tabela `public` | Campos específicos | Constraints e índices mínimos |
| --- | --- | --- |
| `location_types` | `code`, `name`, `description` | unique normalizado `(tenant_id, code)`; índices tenant/status/nome |
| `locations` | `location_type_id`, `parent_id`, `code?`, `name`, `description` | FKs compostas tenant-aware; unique normalizado de código quando presente; índice pai; proteção de ciclo |
| `cost_centers` | `parent_id`, `code`, `name`, `description` | código requerido; unique `(tenant_id, normalized_code)`; FK pai composta; proteção de ciclo |
| `sectors` | `code?`, `name`, `description` | unique de código quando presente; índice tenant/status/nome |
| `teams` | `sector_id?`, `code?`, `name`, `description` | FK composta para Setor; unique de código quando presente; índice setor/status |
| `team_memberships` | `team_id`, `membership_id`, `joined_at`, `ended_at?` | FKs compostas; check temporal; unique parcial do par ativo; índices membership e team |
| `maintenance_categories` | `code?`, `name`, `description` | unique de código quando presente; índice tenant/status/nome |
| `maintenance_subcategories` | `category_id`, `code?`, `name`, `description` | FK composta; unique normalizado dentro da categoria; índice categoria/status |
| `maintenance_reasons` | `usage_context`, `code`, `name`, `description` | contexto allowlisted; unique por tenant/contexto/código |
| `document_types` | `code?`, `name`, `description` | unique de código quando presente; índice tenant/status/nome |
| `checklist_templates` | `category_id`, `code?`, `name`, `description` | FK composta; unique de código quando presente; índice categoria/status |
| `checklist_template_items` | `template_id`, `position`, `prompt`, `response_type`, `required`, `instructions?` | FK composta; `position > 0`; unique `(tenant_id, template_id, position)`; resposta allowlisted |

Estruturas privadas de suporte ao template, sem grants para API:

| Tabela `private` | Finalidade | Invariantes |
| --- | --- | --- |
| `catalog_templates` | identidade/versionamento de templates CW | chave/version estáveis; status controlado pela plataforma |
| `catalog_template_entries` | entradas allowlisted de categoria, subcategoria e motivo | `entry_kind` fechado; chave estável; pai/contexto coerentes; nenhuma SQL/função em dados |
| `catalog_template_applications` | ledger técnico da aplicação | unique `(tenant_id, template_key)`; resultado estável; sem autoridade runtime sobre registros copiados |

O command usa branches SQL fixas por `entry_kind`; MUST NOT usar dynamic SQL,
nome de tabela/função vindo do template ou payload arbitrário. As tabelas
tenant-owned não referenciam o template. O ledger preserva somente proveniência
técnica e resultado idempotente.

### 7.1 Regras físicas

- Cada FK entre entidades tenant-owned MUST incluir `tenant_id` e encontrar
  uma chave única correspondente no pai.
- Normalização de código MUST ser determinística e definida uma única vez;
  comparação não MAY depender do locale do cliente.
- Código opcional MUST ser tratado com unique parcial para valores não nulos.
- Nomes MAY se repetir quando o código e o contexto distinguirem o registro;
  o Template CW fornece códigos determinísticos, mas a label não é autoridade.
- Nenhuma tabela W4 MAY ter `ON DELETE CASCADE` que apague evidência funcional.
- FKs de autoria MAY preservar o UUID mesmo se a membership for inativada.
- Não há contador ou número sequencial humano obrigatório na W4. Qualquer
  numeração futura MUST usar alocador tenant-safe; `max(code)+1` é proibido.
- Alteração do schema público tipado MUST regenerar
  `src/infrastructure/supabase/database.types.ts` exclusivamente do Supabase
  LOCAL validado.

## 8. Authorization — Resource + Action + Scope

O catálogo MUST adicionar permissões determinísticas, forward-only, seguindo
o formato oficial existente. Os nomes finais MUST ser validados contra a
convenção do catálogo W2 antes da migration.

| Resource | Actions mínimas | Scopes permitidos na W4 |
| --- | --- | --- |
| locations | read, lookup, use, create, update, move, inactivate, reactivate | `ALL_TENANT` |
| cost_centers | read, lookup, use, create, update, move, inactivate, reactivate | `ALL_TENANT` |
| sectors | read, lookup, use, create, update, inactivate, reactivate | `ALL_TENANT` |
| teams | read, lookup, use, create, update, inactivate, reactivate | `TEAM`, `ALL_TENANT` para read/lookup/use; mutações `ALL_TENANT` |
| team_memberships | read, add, end | `ALL_TENANT`; projeção própria separada MAY existir sem expor roster |
| maintenance_categories | read, lookup, use, create, update, inactivate, reactivate | `ALL_TENANT` |
| maintenance_subcategories | read, lookup, use, create, update, inactivate, reactivate | `ALL_TENANT` |
| maintenance_reasons | read, lookup, use, create, update, inactivate, reactivate | `ALL_TENANT` |
| document_types | read, lookup, use, create, update, inactivate, reactivate | `ALL_TENANT` |
| checklist_templates | read, lookup, use, create, update, inactivate, reactivate | `ALL_TENANT` |
| catalog_templates | apply | `ALL_TENANT` |

`lookup` MUST ser uma capacidade estreita, distinta de `read`. Ela permite
somente a projeção mínima de registros ativos. `use` é a capacidade verificada
pelo command consumidor para aceitar a referência; lookup bem-sucedido não é
prova de `use`. Possuir `lookup` ou `use` MUST NOT conceder listagem
administrativa, detalhe completo ou mutação.

Baselines de Perfil e exact overrides MUST seguir W2. A W4 MUST NOT inventar
wildcards, hierarquia de scope, DENY subtrativo ou `INHERIT` persistido.
Combinações `maintenance.*` MUST exigir o entitlement `maintenance`; recursos
estruturais compartilhados seguem o tratamento `core/shared` aprovado, sem
inferir entitlement pelo frontend.

### 8.1 Matriz baseline aprovada

Os nomes abaixo descrevem templates, não condições runtime. O evaluator
continua decidindo exclusivamente por Resource + Action + Scope.

| Template W2 | Grants baseline W4 |
| --- | --- |
| `manager` | `read`, `lookup` e `use` de todos os cadastros tenant W4; `create`, `update` e `inactivate` de Tipos de Local, Locais, Centros de Custo, Setores, Equipes, Categorias, Subcategorias e Motivos; `move` de Local/CC; `team_memberships.read/add/end`; `catalog_templates.apply` |
| `technician` | `lookup/use.all_tenant` de Local, Setor, Centro de Custo, Categoria, Subcategoria, Motivo, Tipo de Documento e Modelo de Checklist; `teams.read/lookup/use.team` |
| `assistant` | mesma projeção operacional estreita de `technician`, sem qualquer mutation W4 |
| `requester` | `lookup/use.all_tenant` de Local, Setor, Categoria e Subcategoria; `teams.lookup/use.team`; nenhuma leitura administrativa |

O baseline `manager` não recebe DELETE físico. `reactivate` e administração de
Tipos de Documento/Modelos de Checklist permanecem combinações granulares no
catálogo, mas não entram nos quatro templates sem decisão/rollout posterior.
Técnico, Auxiliar e Solicitante não recebem `create`, `update`, `move`,
`inactivate`, `reactivate`, gestão de membership nem aplicação de template.

Tipos de Documento e Modelos de Checklist entram na W4 como skeletons seguros,
sem seeds e sem administração concedida por baseline. A wave consumidora MAY
aprovar rollout adicional. Até lá, fixtures técnicas podem provar boundaries e
RLS, mas a UI padrão MUST permanecer somente leitura para o Gestor. Isso não
autoriza relaxar antiescalada para conceder essas permissions.

Um “Supervisor de Manutenção” é um `tenant_profile` customizado, com
`template_key = null`, e MAY receber combinações exatas delegáveis por commands
W2. Nenhum código MUST testar `role == manager` ou nome equivalente.

### 8.2 Rollout seguro dos baselines W4

W2 já fornece identidades autoritativas:

- **System Profile Template:** linhas privadas com UUID estável e
  `template_key` `manager`, `technician`, `assistant` ou `requester`;
- **Tenant Profile Instance:** linha tenant-owned criada de template, com
  `template_key` e `template_version` imutáveis como proveniência;
- **Custom Profile:** linha tenant-owned com `template_key = null`.

Identidades W2 que a migration MUST conferir antes de escrever:

| Template key | UUID oficial | Nome inicial apenas para apresentação |
| --- | --- | --- |
| `manager` | `92000000-0000-4000-8000-000000000001` | Gestor |
| `technician` | `92000000-0000-4000-8000-000000000002` | Técnico |
| `assistant` | `92000000-0000-4000-8000-000000000003` | Auxiliar |
| `requester` | `92000000-0000-4000-8000-000000000004` | Solicitante |

O rollout esperado parte de `template_version = 1` e publica a versão 2. UUID,
key ou versão inesperados MUST abortar a migration; ela não corrige catálogo
desconhecido por aproximação.

A futura migration W4A MUST executar um rollout explícito, transacional e
idempotente com `rollout_key = 'w4_catalog_baseline_v1'`:

1. inserir permissions W4 com UUIDs/códigos determinísticos e incrementar a
   revisão do catálogo pelo mecanismo W2;
2. adicionar os grants da matriz às tabelas privadas de System Profile
   Template pelos UUIDs oficiais, elevando a versão dos quatro templates;
3. enumerar Tenant Profile Instances somente por `template_key` oficial e
   tenant, nunca por `name`/label;
4. inserir apenas os novos grants previstos para a chave oficial da instância,
   com `ON CONFLICT DO NOTHING` e FKs tenant-aware;
5. excluir integralmente Custom Profiles (`template_key IS NULL`) do rollout;
6. não remover, reclassificar nem substituir baseline grant já existente;
7. não ler, inserir, alterar ou remover `tenant_permission_overrides`;
8. registrar ledger privado único por rollout + tenant + profile, contagens e
   Audit técnico W3 na mesma transação;
9. manter `tenant_profiles.template_key/template_version` intactos, pois são
   proveniência de criação; a mutation do baseline incrementa `profile.version`
   pelos triggers W2;
10. falhar e reverter toda a transação de rollout se grant, version bump,
    ledger ou Audit obrigatório falhar.

O rollout é uma atualização de baseline de produto explicitamente aprovada
para instâncias dos quatro templates oficiais. Renomear “Gestor” não impede o
rollout; criar um Perfil chamado “Gestor” não o inclui. Perfil customizado não
é ampliado. Instância padrão pode conter grants tenant adicionais: eles são
preservados, pois o rollout é somente aditivo para permissions W4 novas.

Reexecução MUST encontrar o ledger/unique keys, produzir zero grants e zero
Audit duplicado e retornar o mesmo resumo. Processamento MUST ordenar tenants e
profiles por UUID e usar advisory/row locks canônicos. A migration não expõe
helper a `PUBLIC`, `anon`, `authenticated`, `service_role` ou `cw_worker`.

Templates atualizados valem integralmente para tenants criados depois da W4.
Não há sincronização genérica contínua: qualquer baseline futuro exige outro
rollout versionado e aprovado. O rollout W4 não é precedente para auto-sync.

### 8.3 Ratificação pós-auditoria W4A — `location_types`

Em 2026-09-16, antes do fechamento do gate W4A, foi ratificado que Tipos de
Local constituem o Resource de autorização independente `location_types`. Esta
é uma decisão local à W4: a matriz originalmente congelada na seção 8 listava
`locations`, mas omitia `location_types` como Resource, embora o plano já
tratasse Tipo de Local como cadastro, agregado e tabela próprios. A lacuna foi
identificada em auditoria e resolvida deliberadamente; este registro não
reescreve a matriz original como se a decisão já estivesse presente nela.

A boundary independente separa a gestão da taxonomia da gestão dos registros
físicos de Local e permite mínimo privilégio e Perfis customizados. Por exemplo,
um Supervisor Predial pode receber mutations de `locations` e somente lookup de
`location_types`, sem receber create, update ou inactivate da taxonomia. A
autorização continua sendo a combinação exata Resource + Action + Scope da W2;
nome visível de Perfil e role não participam da decisão.

O baseline W4A é deliberadamente limitado ao escopo atual: `manager` recebe a
administração necessária de `location_types`; `technician`, `assistant` e
`requester` não recebem permissions desse Resource. Isso não congela ausência
permanente de `lookup` para waves futuras: qualquer grant adicional dependerá
de necessidade funcional real e de rollout explícito e versionado da wave
consumidora. Custom Profiles permanecem fora de expansão silenciosa e exact
overrides são preservados.

A mesma auditoria confirmou que `read` e `lookup` são boundaries distintas na
implementação W4A:

- `read` autoriza list/detail administrativo, inclusive registros ativos e
  inativos e campos de gestão como descrição, status, versão e timestamps;
- `lookup` autoriza somente selector/autocomplete de registros ativos, com
  projeção mínima `id`, `code` e `name`.

### 8.4 Decisão pós-congelamento — remoção de `use` na W4A

A matriz e os baselines originalmente congelados nas seções 8 e 8.1 incluíam
`use` para `locations`, `cost_centers` e `sectors`. A primeira implementação
W4A também havia acrescentado `location_types.use` ao novo Resource ratificado.
Antes do gate W4A, uma auditoria semântica e adversarial demonstrou que nenhuma
das quatro permissions possuía consumidor em RLS, commands, gateway ou projeção
de autorização, nem representava authority boundary própria. Essas partes da
matriz original ficam, portanto, explicitamente substituídas por esta decisão;
o registro histórico acima não deve ser interpretado como política vigente da
W4A.

A política aprovada para referências é:

- a mutation é autorizada pela permission correspondente ao Resource
  efetivamente alterado;
- referências e FKs recebidas pelo command são revalidadas server-side quanto
  a tenant, existência, estado, elegibilidade e invariantes de domínio;
- `lookup` autoriza somente descoberta e projeção mínima, não constitui
  authority para mutation nem pré-requisito para associação;
- conhecer ou adivinhar um UUID não concede autoridade;
- possuir `lookup` sem a permission da mutation principal não autoriza a
  mutation; possuir a permission da mutation principal não exige genericamente
  `use` sobre cada FK;
- permission semelhante a `use` só poderá ser criada em wave futura quando
  houver authority boundary concreta, documentada, consumida e testada.

Create/update de Local continua exigindo `locations.create` ou
`locations.update` e revalidando server-side que o Tipo informado existe, está
ativo e pertence ao mesmo tenant. UUID inexistente, inativo ou cross-tenant
falha fechado. O Resource independente `location_types` permanece ratificado,
agora sem `use`.

| Resource W4A | Actions vigentes | Total |
| --- | --- | ---: |
| `locations` | read, lookup, create, update, move, inactivate, reactivate | 7 |
| `location_types` | read, lookup, create, update, inactivate, reactivate | 6 |
| `cost_centers` | read, lookup, create, update, move, inactivate, reactivate | 7 |
| `sectors` | read, lookup, create, update, inactivate, reactivate | 6 |

O catálogo W4A passa a conter 26 permissions. Foram removidas
`shared.locations.use.all_tenant`,
`shared.location_types.use.all_tenant`,
`shared.cost_centers.use.all_tenant` e
`shared.sectors.use.all_tenant`, juntamente com seus grants de baseline. Nenhuma
permission substituta foi criada. Os demais grants permanecem inalterados:
waves funcionais futuras poderão acrescentar `lookup` somente por rollout
explícito e versionado, sem expansão silenciosa de Custom Profiles e sem alterar
exact overrides.

### 8.5 Global Admin CW

Global Admin não é System Profile Template nem Tenant Profile Instance. W4
MUST NOT inserir Perfil “global”, grant tenant, bypass RLS ou membership
silenciosa. Operação futura de plataforma dentro de tenant continua sujeita a
`PLAT-01`: identidade/capability de plataforma, tenant alvo explícito, boundary
allowlisted, motivo e Audit. Global Admin nunca é “super Gestor tenant”.

### 8.6 AUTH-02 nos commands críticos

Todos os commands mutáveis W4 MUST executar:

`begin → resolve principal/tenant → lock em ordem canônica → reread dos fatos
autoritativos → reavaliar entitlement + permission + scope → validar estado +
versão + domínio → mutar → Audit + History + Event/Outbox → concluir
idempotency → commit`.

São críticos: toda criação, mudança hierárquica, atualização, inativação,
reativação, adição e encerramento de membro. Nenhuma autorização MAY ser
calculada somente antes da transação.

## 9. Semântica OWN / ASSIGNED / TEAM / ALL_TENANT

### 9.1 Cadastros administrativos

- `OWN`: não aplicável. `created_by` é autoria, não propriedade.
- `ASSIGNED`: não aplicável; os cadastros não têm responsável operacional.
- `TEAM`: não aplicável a Locais, Centros de Custo, Setores, taxonomias,
  Motivos, Tipos de Documento ou Modelos de Checklist.
- `ALL_TENANT`: alcança os registros do tenant corrente e nunca de outro.

### 9.2 Equipes

Para o recurso Equipe, `TEAM` significa exatamente: a membership autenticada
está ativa no tenant corrente, existe uma associação ativa entre essa
membership e a Equipe e a Equipe está ativa. Isso permite somente as actions
explicitamente concedidas com scope `TEAM`.

`TEAM` MUST NOT:

- conceder automaticamente acesso ao roster completo;
- conceder gestão da Equipe;
- conceder Perfil, Permission ou Entitlement;
- alcançar Equipes do mesmo Setor sem associação ativa;
- sobreviver ao encerramento da membership ou da associação;
- ser derivado de `team_id` enviado pelo cliente.

Para recursos operacionais futuros, a W4 entrega apenas o fato confiável de
membership. A definição de “recurso alcançado pela Equipe” MUST ser feita na
wave que introduzir a FK/atribuição real desse recurso. Não haverá evaluator
genérico baseado em payload.

Assim, a semântica de `TEAM` fica definida para Equipe e para o fato de
membership; `OWN` e `ASSIGNED` continuam deliberadamente adiados por recurso
até surgirem fatos reais de domínio.

## 10. State machines

### 10.1 Cadastros

| Estado | Transição | Command/action | Scope | Pré-condições | Efeitos | Audit | History | Event |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inexistente | `ACTIVE` | create | `ALL_TENANT` | código/relações válidos | cria versão 1 | YES | YES | YES |
| `ACTIVE` | `ACTIVE` | update/move | `ALL_TENANT` | expected version; dependências válidas | incrementa versão | YES | YES | YES |
| `ACTIVE` | `INACTIVE` | inactivate | `ALL_TENANT` | sem dependente ativo bloqueante | incrementa versão; exclui de lookup | YES | YES | YES |
| `INACTIVE` | `ACTIVE` | reactivate | `ALL_TENANT` | pais/tipo/relações ativos | incrementa versão | YES | YES | YES |

Atualização arbitrária de `status` é proibida. Comando repetido com a mesma
identidade idempotente retorna o resultado original. Comando com nova chave
contra estado já atingido MUST falhar com erro de estado, salvo quando o
contrato declarar noop seguro; a W4 adotará falha explícita como padrão.

### 10.2 Membro de Equipe

| Estado | Transição | Command/action | Scope | Pré-condições | Efeitos | Audit | History | Event |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inexistente | `ACTIVE` | add | `ALL_TENANT` | Equipe e membership ativas no mesmo tenant | cria período | YES | YES | YES |
| `ACTIVE` | `ENDED` | end | `ALL_TENANT` | associação ativa e expected version | fixa `ended_at` | YES | YES | YES |

Uma associação encerrada é imutável. Nova participação posterior cria novo
período. Não existe reativação da mesma linha nem DELETE normal.

### 10.3 Aplicação do Template CW

| Estado | Transição | Command/action | Scope | Pré-condições | Efeitos | Audit | History | Event |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| não aplicado + catálogos-alvo vazios | aplicado | apply catalog template | `ALL_TENANT` | template/version allowlisted; tenant autorizado | cria cópias tenant-owned e ledger | YES | por registro | por registro + aplicação |

Aplicado, parcialmente preenchido ou já populado com outra origem não volta a
“não aplicado”. Reaplicação compatível retorna o resultado estável; versão/key
incompatível ou catálogos não vazios falham sem efeito.

## 11. Command boundaries

Os commands oficiais planejados são:

- Tipo de Local: `create`, `update`, `inactivate`, `reactivate`;
- Local: `create`, `update`, `move`, `inactivate`, `reactivate`;
- Centro de Custo: `create`, `update`, `move`, `inactivate`, `reactivate`;
- Setor e Equipe: `create`, `update`, `inactivate`, `reactivate`;
- Membro de Equipe: `add`, `end`;
- Categoria, Subcategoria, Motivo e Tipo de Documento: `create`, `update`,
  `inactivate`, `reactivate`;
- Modelo de Checklist: `create`, `update_definition`, `inactivate`,
  `reactivate`. A definição e seus itens MUST ser persistidos atomicamente.
- Template CW: `apply_cw_catalog_template`, sem command de sync/update tenant.

Cada RPC MUST ter nome explícito. RPCs como `update_entity(jsonb)` ou um patch
genérico são proibidas.

### 11.1 Contrato comum

| Parte | Regra normativa |
| --- | --- |
| Input | campos semânticos allowlisted, `idempotency_key`, `expected_version` nas mutações existentes e correlação opcional |
| Rereads | principal, tenant/membership, entitlement, permission, registro atual, pais/tipos/dependências e referências |
| Locks | alvo e dependências em ordem canônica; locks de hierarquia conforme seção 16 |
| Authorization | Resource + Action + Scope exato, recalculado na transação |
| Validation | tenant, estado, versão, unicidade, referência ativa, ciclo e limites |
| Mutation | somente colunas allowlisted; timestamp e autoria do banco |
| Audit | obrigatório para todo command mutável |
| History | obrigatório para todo command mutável |
| Event | obrigatório conforme matriz da seção 14 |
| Idempotency | obrigatório para toda boundary mutável exposta ao cliente |
| Result | ID, versão, status e campos estáveis mínimos; sem dump de linha |
| Errors | códigos estáveis: unauthorized, not_found, stale_version, conflict, invalid_state, dependency_active, cycle, idempotency_conflict |

### 11.2 Anti-mass-assignment

Inputs MUST NOT aceitar `tenant_id`, `created_by`, `updated_by`, `status`
genérico, `version` de destino, grants, owner, actor, handler, capability ou
campos de infraestrutura. IDs de relações são sugestões que MUST ser
revalidadas autoritativamente no tenant.

## 12. Read models e queries

Cada recurso MUST possuir queries separadas de commands:

- listagem paginada, com projeção administrativa;
- detalhe por UUID;
- lookup mínimo de registros ativos;
- árvore/filhos diretos para Local e Centro de Custo;
- roster de Equipe somente com permissão administrativa;
- “minhas equipes” com projeção mínima, sem revelar outros membros;
- definição de Modelo de Checklist com itens ordenados.

Contratos públicos MUST listar campos; `SELECT *` é proibido. Listagens MUST
usar ordenação determinística com desempate por UUID. Filtros MUST ser
allowlisted e parametrizados: texto, status, tipo, pai, categoria, Setor e
Equipe conforme o recurso.

Paginação por cursor SHOULD ser usada em listagens potencialmente grandes;
offset MAY ser usado apenas com justificativa e ordenação estável. Busca MUST
ter limite e não MAY permitir SQL arbitrário.

Projeções `lookup` MUST conter no máximo `id`, `code` quando houver, `name` e
dados estritamente necessários à distinção visual. Dados de autoria,
descrições internas e roster MUST ser omitidos.

## 13. RLS, grants e boundaries

Todas as tabelas W4 MUST nascer com RLS habilitada e comportamento fail-closed.

| Operação | Política planejada |
| --- | --- |
| SELECT administrativo | `authenticated`, tenant atual, entitlement e permission `read` com scope exato |
| SELECT de Equipe com TEAM | somente Equipes ativas às quais a membership ativa pertence |
| lookup | boundary/projeção própria com action `lookup`; não amplia SELECT administrativo |
| INSERT | negado diretamente; somente command explícito |
| UPDATE | negado diretamente; somente command explícito com versão |
| DELETE | negado para fluxo normal |
| template apply | somente RPC explícita, permission exata e tenant derivado do contexto |

`anon`, `PUBLIC` e `service_role` MUST NOT receber grants diretos amplos.
`cw_worker` MUST NOT receber acesso W4, pois não há consumidor W4 nesta wave.
Tabelas privadas de template, application ledger e rollout de authorization
MUST permanecer sem acesso direto dessas roles. Global Admin não recebe policy
tenant nem bypass por esta wave.

Helpers privilegiados MUST:

- ter necessidade documentada;
- possuir owner técnico aprovado;
- usar `SECURITY DEFINER` somente quando indispensável;
- fixar `search_path` seguro/vazio;
- qualificar todas as referências;
- revogar `PUBLIC EXECUTE` e conceder somente às roles necessárias;
- não aceitar autoridade final em parâmetros;
- não usar dynamic SQL.

Policies MUST usar evaluator W2 não recursivo. Queries de catálogo e lookup
MUST ser testadas por comportamento real e catálogo PostgreSQL, não apenas por
busca textual.

## 14. Audit, History e Event Model

Audit e History permanecem conceitos separados:

- Audit registra evidência técnica/administrativa, actor, source, command,
  reason e correlação;
- History registra a linha do tempo funcional autorizada do cadastro;
- Event registra um fato persistido relevante para consumidores futuros.

Nenhum deles é mecanismo de autorização. Payloads MUST NOT conter autoridade,
token, segredo, signed URL, dump de linha ou PII desnecessária.

### 14.1 Matriz de efeitos

| Classe de command | Audit | History | Event |
| --- | --- | --- | --- |
| create | YES | YES | YES |
| update de dado funcional | YES | YES | YES |
| move hierárquico | YES | YES | YES |
| inactivate/reactivate | YES | YES | YES |
| add/end Team member | YES | YES | YES |
| apply Template CW | YES único da aplicação | YES por registro criado | YES por registro criado e fato de aplicação |

Todos os efeitos obrigatórios MUST integrar a mesma transação do command e do
resultado idempotente. Falha de qualquer efeito obrigatório MUST causar
rollback integral.

### 14.2 Eventos v1

O formato MUST ser `<bounded_context>.<aggregate>.<past_tense_event>`, em
lowercase snake_case. A implementação MUST registrar ao menos:

- `cadastros.location_type.{created,updated,inactivated,reactivated}`;
- `cadastros.location.{created,updated,moved,inactivated,reactivated}`;
- `cadastros.cost_center.{created,updated,moved,inactivated,reactivated}`;
- `cadastros.sector.{created,updated,inactivated,reactivated}`;
- `cadastros.team.{created,updated,inactivated,reactivated}`;
- `cadastros.team_membership.{added,ended}`;
- `maintenance.category.{created,updated,inactivated,reactivated}`;
- `maintenance.subcategory.{created,updated,inactivated,reactivated}`;
- `maintenance.reason.{created,updated,inactivated,reactivated}`;
- `cadastros.document_type.{created,updated,inactivated,reactivated}`;
- `maintenance.checklist_template.{created,updated,inactivated,reactivated}`;
- `cadastros.catalog_template.applied`.

As chaves entre chaves representam a expansão em eventos concretos separados;
o caractere `{}` não integra nenhum `event_type` persistido.

Cada evento usa `event_version = 1`, aggregate type/ID coerentes e envelope W3.
Payload allowlisted MAY conter ID de pai/tipo/categoria, versão resultante,
status e nomes de campos alterados. Descrição, instruções de checklist e
snapshot completo MUST ser relidos na origem autoritativa quando necessários.

Não haverá handler funcional W4, publicação externa ou novo worker.

## 15. Command idempotency

Toda mutation RPC exposta ao cliente MUST exigir idempotency key e usar
`private.command_idempotency` de W3.

Namespace: tenant + actor/source + command + hash da key, sem key crua.

Fingerprint SHA-256 MUST ser produzido de representação canônica dos inputs
semânticos:

- create: tipo de entidade + campos funcionais normalizados + IDs de relação;
- update: ID + expected version + patch funcional allowlisted normalizado;
- move: ID + expected version + novo pai;
- status: ID + expected version + estado de destino + razão funcional quando
  exigida;
- add member: Team ID + target membership ID;
- end member: associação ID + expected version;
- checklist: cabeçalho + itens na ordem explícita, com campos normalizados.
- apply template: chave e versão allowlisted do Template CW; a versão efetiva
  também é protegida pela unicidade tenant + template.

Correlation, causation, timestamps de transporte, metadata técnica, ordem de
chaves JSON e a própria idempotency key são não semânticos e MUST NOT integrar
o fingerprint.

Replay compatível MUST retornar ID, versão e estado originais sem duplicar
mutation, Audit, History ou Event. Mesmo namespace com fingerprint diferente
MUST falhar fechado. Concorrência MUST ser resolvida pela constraint/locking W3,
nunca por check-then-insert no aplicativo.

## 16. Hierarquias e ciclos

Local e Centro de Custo são hierarquias separadas. Cada uma MUST:

- validar pai no mesmo tenant;
- impedir auto-parent e ciclos de qualquer profundidade;
- não impor profundidade de negócio arbitrária; queries MUST possuir limites
  técnicos seguros sem aceitar ciclo ou truncar validação autoritativa;
- preservar filhos ao renomear o pai;
- impedir inativação com filho ativo;
- não propagar autorização por ancestralidade;
- não usar caminho textual como autoridade.

Mutations de hierarquia MUST adquirir um lock transacional estável por tenant
e tipo de hierarquia antes dos row locks, serializando moves concorrentes no
mesmo tenant. Depois MUST reler a cadeia autoritativa e validar o ciclo. A chave
do lock MUST ser derivada por função determinística interna e não por SQL
dinâmico. Locks de tabelas diferentes MUST seguir ordem canônica documentada.

## 17. Concorrência

Races obrigatoriamente tratadas:

| Race | Controle |
| --- | --- |
| creates com mesmo código | unique tenant-aware + idempotency |
| updates simultâneos | `expected_version`, row lock e incremento atômico |
| moves simultâneos | lock de hierarquia por tenant + reread + cycle check |
| inactivate versus child/create | locks de pai antes do filho + reread |
| add member duplicado | unique parcial da associação ativa + idempotency |
| end member concorrente | row lock + expected version |
| inactivate Team versus add member | lock Team antes da associação |
| inactivate Category versus Subcategory/Template | lock parent antes do child |
| command idempotente duplicado | boundary W3 sob transação real |
| duas aplicações do Template CW | lock tenant/catalog + ledger unique + command idempotency |
| apply template versus criação manual | mesmo lock tenant/catalog; apenas um observa alvo vazio |

Ordem geral: tenant/contexto lógico, agregado pai por tipo e UUID ordenado,
agregado alvo e dependentes por UUID. Testes multi-session MUST demonstrar o
comportamento em PostgreSQL LOCAL real.

## 18. Delete e preservação

- DELETE físico por cliente é proibido em todas as tabelas W4.
- Cadastros usam `ACTIVE/INACTIVE`.
- Team memberships usam `ACTIVE/ENDED` e linha encerrada imutável.
- Audit, History, Event/Outbox e idempotency seguem retenção W3; W4 não cria
  cleanup.
- FKs MUST restringir exclusões capazes de remover evidência.
- Dados importados da V1 só poderão ser classificados por plano W15; W4 MUST
  NOT apagar ou reinterpretar legado.
- Ledger de aplicação do Template CW não autoriza nem bloqueia edição dos
  registros copiados e não pode ser apagado pelo cliente.

## 19. Storage

`STORAGE = DEFERRED`.

W4 não requer anexo nem upload. Tipo de Documento é somente vocabulário; não
cria objeto, bucket, metadata de arquivo ou signed URL. STO-01 será aplicado na
wave que introduzir anexos reais.

## 20. Rotas e UI

W4 inclui UI administrativa mínima e responsiva. Rotas reais planejadas:

- `/e/:tenantRef/cadastros`;
- `/e/:tenantRef/cadastros/locais` e `.../locais/:locationId`;
- `/e/:tenantRef/cadastros/centros-de-custo` e detalhe;
- `/e/:tenantRef/cadastros/setores` e detalhe;
- `/e/:tenantRef/cadastros/equipes` e `.../equipes/:teamId`;
- `/e/:tenantRef/cadastros/equipes/:teamId/membros`;
- `/e/:tenantRef/manutencao/categorias` e detalhe;
- `/e/:tenantRef/manutencao/motivos` e detalhe;
- `/e/:tenantRef/cadastros/tipos-de-documento` e detalhe;
- `/e/:tenantRef/manutencao/modelos-de-checklist` e detalhe.

O primeiro acesso administrativo aos catálogos MUST oferecer a escolha
explícita “Aplicar Template CW” ou “Começar vazio”. Começar vazio não chama o
command. Aplicar exige confirmação, exibe a versão/conteúdo previsto e trata
`already_applied`, `target_not_empty`, `permission_denied` e falha atômica. A
UI não pode executar aplicação automaticamente ao carregar uma rota.

Criação/edição MAY usar subrotas `novo` e `editar` ou formulários roteados
equivalentes, desde que cada estado navegável importante tenha URL própria,
refresh seguro, deep link e back/forward corretos.

Cada página MUST tratar: loading, vazio, erro, sem permissão, inexistente,
conexão indisponível, sucesso e falha. Ações de inativação MUST usar confirmação
e explicar dependências bloqueantes. Formulários MUST usar RHF + Zod, labels,
erros acessíveis, foco e navegação por teclado. Mobile MUST ser funcional.

Optimistic update MAY ser usado somente em mudanças reversíveis e sem esconder
falha de autorização/versão. Criações, moves, inativação e membros SHOULD
aguardar confirmação autoritativa.

## 21. Cache e UI-01

Query keys MUST incluir:

`principal/context + tenant + resource + query + normalized filters +
sensitive projection`.

As chaves MUST distinguir list, detail, lookup, tree, roster e my-teams.
Mudança de principal, membership, entitlement ou tenant MUST cancelar requests,
invalidar/limpar caches sensíveis e impedir renderização de dados anteriores.

Após mutation confirmada, a aplicação MUST invalidar exatamente as listas,
detalhes, árvores e lookups afetados. Nenhum dado sensível ou roster MAY ser
persistido indiscriminadamente em `localStorage`. Filtros de UI MAY permanecer
na URL, mas MUST NOT incluir segredo nem servir de autorização.

## 22. Threat model

| Threat | Control | Test obrigatório |
| --- | --- | --- |
| tenant spoofing | tenant autoritativo W1; FKs compostas; input sem tenant | RPC com ID de outro tenant falha e não deixa efeito |
| actor spoofing | actor de `auth.uid()`/contexto W1 | payload com actor falso não altera envelope |
| privilege escalation | W2 exact permission; membership não concede Perfil | membro de Team sem action administrativa não muta cadastro |
| IDOR | tenant + permission + scope + reread | IDs A/B em detail, update e lookup |
| cross-tenant leakage | RLS/projeções e cache tenant-aware | SELECT/list/detail/lookup A/B |
| stale authorization | reavaliação dentro da transação | revogação concorrente antes da mutation |
| stale version | expected version + row lock | duas atualizações simultâneas, uma falha |
| payload authority | inputs allowlisted e rereads | payload com tenant/role/team/capability ignorado/rejeitado |
| mass assignment | RPCs explícitas | campos técnicos extras não persistem |
| confused deputy | relação e actor revalidados | ID válido de outro contexto não amplia ação |
| command replay | idempotency W3 | replay estável e conflito de fingerprint |
| duplicate creation | unique + idempotency | duas sessões com mesmo código/key |
| status tampering | sem update direto; state commands | update direto/status arbitrário negado |
| hierarchy cycle | lock + recursive validation | self-cycle, deep cycle e race de moves |
| code enumeration | projeção e permission estreita | usuário sem lookup/read não enumera |
| roster leakage | resource/action separado | TEAM read não revela roster |
| unsafe SECURITY DEFINER | owner/search_path/grants fixos | catálogos PostgreSQL e shadowing |
| broad grants | deny by default | privilege matrix anon/auth/service_role/cw_worker |
| service_role shortcut | sem grants diretos W4 | catálogo confirma ausência |
| unauthorized attachment | Storage ausente | nenhuma tabela/bucket/URL introduzida |
| sensitive cache leakage | keys por contexto e clear | tenant switch e logout E2E |
| malicious search/filter | parâmetros allowlisted | entradas adversariais não viram SQL |
| event data leakage | payload mínimo e schema | assertions do payload/outbox |
| role/display-name authorization | template UUID/key só no rollout; evaluator W2 em runtime | renomear Gestor e criar custom “Gestor” não muda grants |
| baseline rollout escalation | allowlist por template key oficial; custom profiles excluídos; add-only | matriz antes/depois, custom intacto, grants extras preservados |
| override loss | rollout não toca overrides | ALLOW/DENY preexistentes byte-a-byte iguais após rollout |
| Global Admin bypass | PLAT-01; nenhuma membership/policy/grant W4 implícito | catálogo e RLS confirmam ausência de acesso tenant |
| template auto-sync | aplicação única; sem FK operacional; sem scheduler | alterar versão global não muda tenant aplicado |
| duplicate template apply | ledger unique + lock + W3 idempotency | duas sessões e keys distintas produzem uma aplicação |
| cross-context reason | contexto técnico no registro + validação do command consumidor | PAUSE_WORK_ORDER rejeitado como CANCEL_REQUEST |

## 23. Estratégia de testes

### 23.1 pgTAP

MUST cobrir:

- existência, colunas, tipos, defaults, FKs compostas, checks e índices;
- tenant obrigatório, código/posição únicos e checks temporais;
- RLS habilitada, policies, grants reais e ausência de acesso direto de escrita;
- funções, owners, `proconfig`, `search_path`, EXECUTE e ausência de PUBLIC;
- cada state transition e cada command;
- lookup versus read, TEAM versus ALL_TENANT e roster;
- isolamento tenant em SELECT/INSERT/UPDATE/DELETE/EXECUTE;
- self-cycle, ciclo profundo, pai cross-tenant e dependentes ativos;
- stale version, estado incompatível e inputs extras/maliciosos;
- idempotency: primeiro uso, replay, conflito e efeitos únicos;
- atomicidade: falha em Audit, History ou Event reverte tudo;
- payload de evento allowlisted, versão e aggregate coerentes;
- append-only/preservação de History e Audit por regressão;
- Template CW opcional, cópia tenant-owned, alvo vazio, aplicação única,
  rollback, replay e ausência de auto-sync;
- catálogo de motivos rejeita contexto inexistente e uso cross-context;
- matriz baseline por UUID/template key, sem role check/display name;
- rollout add-only/idempotente: templates e instâncias oficiais recebem apenas
  grants aprovados; Custom Profiles e overrides permanecem idênticos;
- Global Admin não recebe Perfil/grant/bypass tenant;
- ausência de Storage, worker, domínio W5+ ou grants adicionais.

### 23.2 Multi-session PostgreSQL LOCAL

MUST usar sessões independentes para:

1. create com mesmo código;
2. command com mesma idempotency key;
3. update com mesma versão;
4. moves hierárquicos capazes de formar ciclo;
5. create child versus inactivate parent;
6. add member duplicado;
7. add member versus inactivate Team;
8. end member concorrente.
9. duas aplicações simultâneas do Template CW com keys iguais e distintas;
10. aplicação do template versus criação manual no mesmo catálogo.

O relatório MUST registrar número de sessões, ordenação observada e estado
final, sem substituir esses testes por mocks.

### 23.3 Unitários

- schemas Zod de inputs e filtros;
- normalização/canonicalização e fingerprints;
- materialização determinística do Template CW e matriz de rollout;
- reducers/helpers puros de formulários e hierarquia;
- query-key factories e invalidation;
- rendering/permission states dos componentes compartilhados.

### 23.4 E2E

- happy path de cadastro estrutural e taxonomia;
- denial de usuário sem permission;
- Team member vê somente projeção autorizada;
- gestão de membros e reflexo imediato de `TEAM`;
- conflito de versão e dependência ativa;
- tenant switch sem cache leakage;
- deep link + refresh + back/forward;
- mobile do fluxo crítico;
- inativação remove item do lookup, preservando detalhe histórico.
- escolha Template CW versus vazio e replay seguro da aplicação.

### 23.5 Regressão

Reset LOCAL, todas as migrations, schema lint, todos os pgTAP, testes W0–W3,
runner W3, unit, E2E, typecheck, lint, build e full gate MUST passar. Nenhuma
assertion anterior MAY ser removida ou enfraquecida.

## 24. Subwaves executáveis

### W4A — Structural Catalog Foundation

**Objective:** entregar contrato de taxonomia aprovado, catálogo de permissões
W4, rollout baseline aprovado e Locais/Tipos, Centros de Custo e Setores no
banco, com commands, queries e testes.

**Entry gate:** W3 ready; decisões BD-03 e W4-BLK-01 congeladas por este plano;
worktree limpo; Supabase LOCAL.

**Files expected:** migrations W4A, pgTAP W4A, tipos gerados quando aplicável,
schemas/domain helpers estritamente necessários e documentação W4.

**DB changes:** permissions forward-only; System Templates v2; rollout ledger;
tabelas estruturais; RLS; RPCs explícitas; índices/constraints.

**App changes:** contratos TypeScript/Zod e acesso de dados, sem páginas finais.

**Tests:** schema, hierarchy, matriz/rollout de permissions, idempotency,
atomicity, tenant e multi-session.

**Exit gate:** `W4A_STRUCTURAL_CATALOGS_READY = YES`.

**Deferred:** Teams, taxonomia de Manutenção e UI integrada.

### W4B — Teams and TEAM Scope

**Objective:** entregar Equipes, membership periods e semântica real de `TEAM`
para Equipe.

**Entry gate:** W4A ready.

**Files expected:** migration W4B, testes pgTAP/multi-session, contratos de
Equipe e documentação.

**DB changes:** Teams, memberships, policies/helpers mínimos, commands e
queries.

**App changes:** data contracts e queries de Team/my-teams; sem domínio W5+.

**Tests:** anti-escalation, roster, active membership, concurrency e tenant.

**Exit gate:** `W4B_TEAM_SCOPE_READY = YES`.

**Deferred:** alcance TEAM de recursos que ainda não existem.

### W4C — Maintenance Catalogs

**Objective:** entregar Categorias/Subcategorias, Motivos contextuais, Tipos de
Documento, esqueleto de Modelos de Checklist e aplicação opcional do Template
CW.

**Entry gate:** W4A ready e Template CW v1 preservado conforme este plano.

**Files expected:** migration W4C, pgTAP, contratos Zod/TypeScript e docs.

**DB changes:** tabelas, constraints, RLS, commands e queries desses catálogos;
template privado e application ledger.

**App changes:** boundaries de dados; nenhuma execução de checklist/storage.

**Tests:** relações, contexto de motivo, resposta allowlisted, Template CW,
rollout/replay, status, idempotency, atomicity e tenant.

**Exit gate:** `W4C_MAINTENANCE_CATALOGS_READY = YES`.

**Deferred:** snapshots, execução, anexos e módulos operacionais.

### W4D — Cadastro Experience and Integrated Hardening

**Objective:** entregar rotas/páginas/padrões compartilhados e provar o gate
integrado da W4.

**Entry gate:** W4B e W4C ready.

**Files expected:** router/pages/components/hooks/tests E2E, ajustes de docs e
somente migrations forward-only para problemas reais encontrados.

**DB changes:** nenhuma esperada; hardening somente por migration nova.

**App changes:** listas, detalhes, forms, filters, selectors, status,
confirmations e cache/UI-01.

**Tests:** E2E, adversarial, access matrix, tenant switch, deep link, mobile e
regressão completa.

**Exit gate:** `CADASTRO_READY = YES`.

**Deferred:** todo W5+.

## 25. DAG e paralelização

```text
W3_INFRASTRUCTURE_READY
          |
          v
W4A_STRUCTURAL_CATALOGS_READY
       /                 \
      v                   v
W4B_TEAM_SCOPE_READY   W4C_MAINTENANCE_CATALOGS_READY
       \                 /
        v               v
 W4D_CADASTRO_EXPERIENCE_AND_HARDENING
                 |
                 v
          CADASTRO_READY
```

W4B e W4C MAY ser implementadas em paralelo somente depois de W4A, em
worktrees/branches coordenados, porque compartilham catálogo de permissões,
padrões de migration e tipos. W4D MUST aguardar ambas. Migrations paralelas
MUST receber ordenação inequívoca antes da integração e não podem editar umas
às outras.

## 26. Definition of Done — `CADASTRO_READY`

`CADASTRO_READY = YES` somente quando:

- W4A, W4B, W4C e W4D estiverem aprovadas;
- Template CW opcional, taxonomia/contextos aprovados e rollout de baselines
  estiverem implementados exatamente como definidos;
- schema, constraints, índices e migrations forward-only passarem reset LOCAL;
- RLS, authorization, grants, scopes e tenant isolation passarem;
- commands, queries e state machines passarem;
- semântica TEAM e anti-escalation passarem;
- Audit, History, Event/Outbox e idempotency passarem atomicidade e replay;
- testes concorrentes reais passarem;
- UI/rotas/cache e E2E passarem, inclusive refresh e troca de tenant;
- schema lint, pgTAP, unit, E2E, typecheck, lint, build e full gate passarem;
- revisão adversarial de segurança não encontrar bloqueador conhecido;
- nenhuma regressão W0–W3 existir;
- documentação representar a implementação real;
- não houver funcionalidade W5+ antecipada.

`CADASTRO_READY` significa apenas que os cadastros estruturais da W4 e a base
de Equipes estão prontos para consumo controlado pelas waves seguintes. Não
significa produção pronta, migração V1 concluída, Ativos, Solicitações, OS,
worker produtivo ou SaaS completo.

## 27. Riscos, decisões resolvidas e decisões adiadas

### 27.1 `BD-03` — RESOLVED

A taxonomia inicial aprovada é o Template CW opcional das seções 6.1–6.3.
Categorias, Subcategorias e Motivos listados são copiados como registros
tenant-owned. Tipos de Local, Tipos de Documento e Modelos de Checklist não
recebem seeds não especificados e começam vazios.

Os response types iniciais de Modelo de Checklist vêm do `PRODUCT_SPEC.md`:

- `DONE_NOT_DONE` — feito/não feito;
- `CONFORMING_NONCONFORMING` — conforme/não conforme;
- `YES_NO` — sim/não;
- `TEXT` — texto;
- `NUMBER` — número;
- `OBSERVATION` — observação.

Esses response types são vocabulário técnico estável, não registros
tenant-customizable. A W4 não cria execução nem snapshot de checklist.

### 27.2 Migração V1 — não bloqueia W4

`operacoes` e `usuario_operacoes` possuem semântica ambígua. A W4 cria o alvo
novo, mas a classificação/migração pertence à W15 e permanece bloqueada por
`RRB-02`. Nenhum fuzzy match ou mapeamento implícito é permitido.

### 27.3 `W4-BLK-01` — RESOLVED

A matriz baseline está congelada na seção 8.1. O rollout está congelado na
seção 8.2 e reutiliza os UUIDs/keys oficiais W2. É add-only, versionado,
idempotente, tenant-safe e auditado; preserva todos os overrides e grants
preexistentes; não inclui Custom Profiles e não usa display name.

Essa resolução é uma exceção explícita e limitada à regra W2 de que permission
futura não é retroativa por padrão. Ela autoriza somente os grants W4 desta
matriz para Tenant Profile Instances provenientes dos quatro templates
oficiais. Não cria mecanismo de auto-sync genérico.

### 27.4 Blockers atuais

`ARCHITECTURAL_BLOCKERS = NONE`.

`BUSINESS_BLOCKERS = NONE`.

Isso autoriza congelar o plano, não iniciar automaticamente W4A nem declarar
`CADASTRO_READY`.

### 27.5 Decisões deliberadamente adiadas

- semântica OWN/ASSIGNED dos recursos operacionais futuros;
- alcance TEAM de Ativo, Solicitação, OS ou outro recurso ainda inexistente;
- Tags e unidades de medida avançadas;
- importação em massa;
- execução/snapshot de checklist;
- anexos/Storage;
- retenção específica além dos contratos W3;
- consumidores funcionais dos eventos W4;
- política de profundidade máxima de hierarquia; sem limite arbitrário na W4,
  mantendo proteção contra ciclos e limites técnicos de consulta;
- migração e reconciliação de dados V1.

### 27.6 Riscos controlados

- **Taxonomia futura divergente:** registros copiados são tenant-owned e não
  sofrem auto-sync.
- **Rollout de privilégio:** somente template_key oficial recebe grants exatos;
  Custom Profile e overrides ficam intactos.
- **Escalada via Team:** membership é fato de scope, nunca Permission.
- **Ciclos/races:** lock transacional de hierarquia + reread + constraint/teste.
- **Catálogo inativo ainda referenciado:** sem hard delete; novos commands
  revalidam status.
- **Cache cross-tenant:** keys por contexto e limpeza obrigatória.
- **Overengineering:** tabelas específicas e commands explícitos; nenhuma
  engine genérica de catálogo.

## 28. Checklist adversarial do plano

Antes de implementar cada subwave, confirmar:

- [ ] toda tabela tenant-owned possui `tenant_id NOT NULL` e FKs compostas;
- [ ] nenhuma authority vem de payload, URL, cache ou código humano;
- [ ] nenhum scope é ambíguo ou hierárquico;
- [ ] toda transição usa command explícito;
- [ ] todo command mutável possui Audit e History;
- [ ] todo evento tem type/version/aggregate e payload allowlisted;
- [ ] toda race possui lock, constraint, versão ou combinação explícita;
- [ ] RLS/grants são efetivos e não dependem da UI;
- [ ] não há `service_role` shortcut, dynamic SQL ou PUBLIC EXECUTE;
- [ ] Storage continua ausente;
- [ ] todas as rotas mantêm tenant context e deep link;
- [ ] DAG não contém dependência circular;
- [ ] nenhuma funcionalidade W5+ foi antecipada;
- [ ] Template CW continua opcional, tenant-owned após cópia e sem auto-sync;
- [ ] rollout usa UUID/template_key W2 e não display name;
- [ ] Custom Profiles e overrides continuam intactos;
- [ ] Global Admin continua sujeito a PLAT-01, sem Perfil tenant implícito;
- [ ] motivos são validados pelo contexto exato;
- [ ] aplicação duplicada/concorrente do template permanece idempotente;
- [ ] todos os requisitos oficiais da W4 estão ligados a uma subwave e teste.

Este documento é plano, não implementação. Ele não autoriza migration, RPC,
RLS, permission catalog, evento, componente ou rota antes do gate de entrada
da subwave correspondente.
