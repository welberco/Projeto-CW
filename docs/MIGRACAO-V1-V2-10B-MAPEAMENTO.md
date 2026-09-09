# Mapeamento de Dados e Regras de Transformação V1 → V2 — Etapa 10B

| Campo | Valor |
| --- | --- |
| Projeto | CW ERP / CW Manutenção |
| Etapa | Fase A — Etapa 10B |
| Natureza | Especificação conceitual detalhada de mapeamento |
| Origem | V1 conhecida pelas evidências versionadas |
| Destino | CW ERP V2 conforme baseline arquitetural congelada |
| Estado | Especificação para desenho posterior de migrations/ETL |
| Execução | Nenhuma migração, acesso remoto ou alteração de dados foi realizada |

## 1. Objetivo e escopo

Este documento transforma a estratégia aprovada da Etapa 10A em regras verificáveis de mapeamento V1 → V2. Para cada domínio relevante, explicita fonte, semântica conhecida, destino conceitual, transformação, identidade, relações, tenant, autoria, null/default, validação, quarentena, proveniência e reconciliação.

A especificação usa as colunas e estruturas encontradas nos SQLs versionados apenas como evidência local. Como a V1 acumula scripts sucessivos e não possui histórico convencional de migrations, nenhuma definição local prova o schema ou os dados atualmente remotos.

Incluído:

- mapeamentos conceituais em nível de entidade, campo, enum, relação, código, ator, evento e objeto;
- regras determinísticas e condicionais que podem ser implementadas posteriormente sem reinterpretação silenciosa;
- requisitos objetivos de revisão, quarentena e revalidação;
- registry bidirecional de proveniência, taxonomia de quarentena e equações de reconciliação;
- dependências concretas entre `PREPARE`, `MAP`, `LOAD`, `RECONCILE` e `ACTIVATE`;
- blockers de desenho, dados e cutover relevantes à Etapa 10C.

Excluído:

- acesso a Supabase, PostgreSQL, Auth, Storage, Edge Functions, produção ou GitHub remotos;
- criação de DDL, SQL, migration, ETL, código, RPC, policy, bucket, usuário, fixture ou objeto;
- decisão física de schema, runtime ou provider;
- correção, exclusão, carga, ativação ou disparo de notificações;
- inferência de dados ausentes ou promoção de itens complementares/futuros.

## 2. Fontes e precedência

Fontes lidas e aplicadas:

1. `PRODUCT_SPEC.md` — autoridade funcional e de escopo;
2. `docs/ARQUITETURA-TECNICA-V2.md` — autoridade das decisões técnicas `CLOSED`;
3. `docs/MIGRACAO-V1-V2-10A-ESTRATEGIA.md` — estratégia de migração aprovada;
4. `docs/INVENTARIO-V1.md` — estado legado conhecido;
5. `docs/GAP-ANALYSIS-V1-V2.md` — apoio comparativo;
6. `AGENTS.md` — governança do repositório.

Evidências locais complementares foram consultadas nos SQLs versionados em `supabase/`, especialmente `schema.sql`, `attachments.sql`, `history.sql`, `permissions-users.sql`, `demand-types-codes.sql`, `reports.sql` e `arquitetura-v2.sql`. Elas servem para nomear campos e vocabulários possíveis, não para declarar o estado remoto.

Precedência: regra funcional → arquitetura `CLOSED` → estratégia 10A → inventário → GAP → evidência técnica acumulada. Ausência ou conflito de evidência resulta em `UNKNOWN`, `REQUIRES_REVIEW`, `REVALIDATION_REQUIRED` ou `QUARANTINE`, conforme o risco.

## 3. Convenções

### 3.1 Dispositions

| Disposition | Significado operacional futuro |
| --- | --- |
| `DETERMINISTIC` | Evidência atual permite transformação inequívoca, ainda sujeita a validação de integridade |
| `CONDITIONAL` | Regra objetiva depende de condição verificável no snapshot/registro |
| `REQUIRES_REVIEW` | Exige decisão humana de negócio, segurança ou dados antes da carga |
| `QUARANTINE` | Registro não entra operacionalmente até resolução explícita |
| `LEGACY_ONLY` | Preservado como história/proveniência, sem entidade operacional equivalente |
| `REGENERATE` | Não copiar; reconstruir após carregar fontes autoritativas |
| `DISCARD_CANDIDATE` | Potencialmente dispensável; descarte não está autorizado nesta etapa |

### 3.2 Confidence

| Confidence | Critério |
| --- | --- |
| `HIGH` | Fonte e semântica inequívocas nas evidências e compatíveis com a V2 |
| `MEDIUM` | Correspondência provável, condicionada a valores/vínculos verificáveis |
| `LOW` | Destino plausível, mas sem evidência suficiente para regra automática |
| `UNKNOWN` | Estado ou semântica não comprovados |

### 3.3 Termos e símbolos

- `REVALIDATION_REQUIRED`: depende obrigatoriamente do snapshot remoto futuro.
- `source row`: registro original imutavelmente identificado.
- `target`: entidade/campo conceitual V2; nomes físicos não estão fechados.
- `registry`: mapa bidirecional e versionado fonte ↔ destino.
- `tenant invariant`: pai, filho e vínculo devem pertencer ao mesmo tenant V2.
- `actor resolution`: resultado `mapped_actor`, `legacy_actor`, `unresolved_actor` ou `technical_actor`.
- `trimmed non-empty`: texto após remoção de espaços não é vazio.
- “preservar” não significa reutilizar PK bigint como PK V2.

### 3.4 Política de incerteza

Uma regra nunca promove `LOW`/`UNKNOWN` a carga operacional por conveniência. O pipeline futuro deve rejeitar valor fora do vocabulário esperado e registrar a linha, sem usar fallback genérico. Similaridade textual, e-mail, nome, path, tenant atual do ator e posição ordinal não constituem prova suficiente isoladamente.

## 4. Modelo canônico de mapping

Toda regra detalhada deve poder ser representada por:

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fonte identificada | coluna/relação/evento | significado evidenciado | entidade/campo/conceito | preserve/map/split/merge/normalize/reclassify | predicado verificável | política explícita | derivação autoritativa | resolução explícita | referência obrigatória | nível | classificação |

Requisitos por mapping:

- identificador e versão imutável da regra;
- predicado de elegibilidade separado da transformação;
- motivo estável para falha/quarentena;
- sem efeitos colaterais na fase de análise;
- saída determinística para a mesma fonte e versão;
- idempotência futura por `migration_run + source identity + rule version`;
- métricas de entrada, saída e exceção;
- capacidade de relacionar uma origem a vários destinos e vice-versa;
- nenhum registro fora da equação de reconciliação.

## 5. Identidade interna e registry

Entidades de domínio V2 recebem UUID interno gerado pelo banco. PKs bigint V1 permanecem como identidade de origem no registry e nunca são promovidas automaticamente a PK V2.

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tabelas tenant-owned | `id bigint` | PK técnica local | UUID interno V2 | generate + register | gerar uma vez por source identity; retry reutiliza mapping | PK nula é inválida | `source_tenant` obrigatório | N/A | mapping 1:1 obrigatório | HIGH | `DETERMINISTIC` |
| `organizacoes` | `id uuid` | PK/tenant legado | UUID interno de Empreendimento | preserve candidate ou generate + register | preservar somente se compatível/único; caso contrário mapear | nulo inválido | é o próprio tenant | N/A | obrigatório | MEDIUM | `CONDITIONAL` |
| `auth.users` | `id uuid` | identidade Auth | Auth identity V2 | preserve candidate | `REVALIDATION_REQUIRED`; preservar somente após compatibilidade e snapshot Auth | nulo inválido | membership separado | próprio principal | obrigatório | UNKNOWN | `CONDITIONAL` |
| qualquer fonte | código humano | referência visível | código legado + código V2 quando necessário | preserve, nunca usar como PK | detectar colisão por namespace/tenant | nulo segue regra do domínio | tenant do registro | N/A | obrigatório | HIGH | `CONDITIONAL` |
| relações N:1 ou 1:N | source IDs | vínculo legado | target UUIDs | resolve through registry | todos os lados precisam estar mapeados e tenant-coerentes | ausência não é inventada | igualdade obrigatória | N/A | mapping de relação | HIGH | `CONDITIONAL` |

O registry conceitual deve conter `source_system`, `source_entity`, `source_id`, `source_tenant`, `target_entity`, `target_id`, `migration_run_id`, `mapping_rule/version`, `status`, `disposition`, `confidence`, evidência, timestamps e resolução. Seu desenho físico fica deferido.

## 6. Tenants

### 6.1 Mapeamento de `organizacoes`

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `organizacoes` | `id` | identidade do cliente | Empreendimento UUID | preserve candidate/register | único e referenciado; compatibilidade remota exigida | nulo: quarantine | self | N/A | source ID obrigatório | MEDIUM | `CONDITIONAL` |
| `organizacoes` | `nome` | nome conhecido | nome/nome de exibição | trim preservando original | trimmed non-empty | nulo/vazio: review, sem inventar | self | N/A | valor original | HIGH | `CONDITIONAL` |
| `organizacoes` | `slug` | seletor de URL legado | slug/alias, se adotado | normalize somente por regra futura | não é identidade nem autoridade | nulo permitido | self | N/A | preservar original | LOW | `REQUIRES_REVIEW` |
| `organizacoes` | `cnpj` | documento cadastral opcional | documento fiscal | preservar formato original + normalização separada validada | não deduplicar tenant automaticamente por CNPJ | nulo = `NOT_CAPTURED` | self | N/A | obrigatório | MEDIUM | `CONDITIONAL` |
| `organizacoes` | `endereco` | endereço textual | dados cadastrais/endereço | preservar texto; split só com parser/revisão aprovada | sem geocodificação/inferência | nulo permitido | self | N/A | obrigatório | MEDIUM | `CONDITIONAL` |
| `organizacoes` | `telefone`, `email` | contatos do tenant | contatos do Empreendimento | normalização não destrutiva | validar formato; original preservado | nulo permitido | self | N/A | obrigatório | MEDIUM | `CONDITIONAL` |
| `organizacoes` | `logo_path` | referência ao logo | identidade visual + file metadata | resolve object after tenant | apenas se objeto e tenant conferirem | nulo = sem logo | self | uploader separado | path original | MEDIUM | `CONDITIONAL` |
| `organizacoes` | `criado_em` | criação conhecida | created timestamp/provenance | preserve instant if valid | timezone válido ou regra temporal | nulo: provenance + review | self | ator desconhecido permitido | obrigatório | MEDIUM | `CONDITIONAL` |
| `organizacoes` | status inexistente/indireto | situação comercial não comprovada | Ativo/Suspenso/Inativo | sem inferência | decisão cadastral explícita | não aplicar default como fato histórico | self | revisor | evidência | UNKNOWN | `REQUIRES_REVIEW` |

### 6.2 Validações de tenant

- ID duplicado ou organização inexistente referenciada: `QUARANTINE` com `TENANT_UNKNOWN`.
- possíveis organizações duplicadas por nome/CNPJ: sinalizar; nunca `MERGE` automático.
- tenant V1 sem destino aprovado: bloqueia carga de todos os filhos.
- registro tenant-owned sem `organizacao_id`: não herda tenant do ator, pai ou maioria sem regra e evidência; `QUARANTINE`.
- status, entitlements e código `EMP-*` V2 não são inferidos da atividade observada.

## 7. Auth e usuários

### 7.1 Separação conceitual

```text
auth.users
→ Auth identity

perfis
→ application user/profile data

perfis.organizacao_id + evidências autorizadas
→ tenant membership

perfis.papel + permissoes_perfis
→ candidatos de profile baseline/capabilities

papel administrativo legado
↛ platform identity automática
```

### 7.2 Mapeamento

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `auth.users` | `id` | principal Auth | Auth identity | preservar se seguro | UUID único e tecnicamente compatível | nulo inválido | não define membership | self | identity mapping | UNKNOWN | `CONDITIONAL` |
| `auth.users` | e-mail/provider/estado | credencial e lifecycle | Auth identity | preservar pelos fluxos Auth | `REVALIDATION_REQUIRED`; validar provider, confirmação, duplicidade e mudanças | não fabricar e-mail | não define tenant | self | snapshot Auth | UNKNOWN | `CONDITIONAL` |
| `auth.users.raw_user_meta_data` | nome/papel/organização | metadata cliente/trigger | somente dado auxiliar | não usar como autoridade | pode apoiar revisão, nunca sobrepor tabelas autoritativas; qualquer uso operacional exige nova regra revisada | ausente permitido | não deriva tenant sozinho | N/A | preservar evidência mínima | LOW | `LEGACY_ONLY` |
| `perfis` | `id` | FK para Auth | application user identity mapping | resolve Auth mapping | perfil sem Auth: review/quarantine conforme uso | nulo inválido | membership separado | self | obrigatório | HIGH | `CONDITIONAL` |
| `perfis` | `nome` | nome do usuário | nome de exibição | trim não destrutivo | vazio não deriva do e-mail sem decisão | nulo = `NOT_CAPTURED` | membership | self | original | HIGH | `CONDITIONAL` |
| `perfis` | `email` | cópia do e-mail Auth | atributo de exibição/contato | comparar com Auth | Auth é fonte do login; divergência exige revisão | nulo não recebe valor silencioso | membership | self | ambos os valores | MEDIUM | `CONDITIONAL` |
| `perfis` | `loja` | afiliação textual legada | membership/Local/Setor/outro | nenhuma conversão automática | classificar com operações e evidência | nulo permitido | tenant do perfil validado | self | original | LOW | `REQUIRES_REVIEW` |
| `perfis` | `organizacao_id` | tenant corrente/legado | tenant membership | resolve tenant mapping | exatamente um tenant para usuário comum | nulo não recebe primeiro tenant | target tenant | self | obrigatório | MEDIUM | `CONDITIONAL` |
| `perfis` | `papel` | papel legado | profile baseline candidate | reclassify | dicionário + permissões efetivas + revisão | nulo/inválido: review | mesmo tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `perfis` | `ativo` | flag operacional | status de application user | map with approval state | `false` não distingue Bloqueado/Inativo | nulo legado não vira true | mesmo tenant | ator da mudança se conhecido | original | MEDIUM | `CONDITIONAL` |
| `perfis` | `aprovacao` | pendente/aprovado/rejeitado | estado de convite/aprovação e status | split/reclassify | combinar com Auth e `ativo`; não equiparar rejeitado a inativo automaticamente | nulo: review | mesmo tenant | `aprovado_por` | obrigatório | MEDIUM | `CONDITIONAL` |
| `perfis` | `aprovado_por`, `aprovado_em` | decisão administrativa | provenance/history de onboarding | preserve event candidate | ator e timestamp válidos; não fabricar se ausentes | nulos preservados | tenant coerente | actor resolution | obrigatório | MEDIUM | `CONDITIONAL` |
| `perfis` | `criado_em` | criação do perfil | created timestamp/provenance | preserve if valid | não confundir com criação Auth | nulo: review | tenant membership | technical/unknown | obrigatório | HIGH | `CONDITIONAL` |

Perfil sem Auth usado como autor de registros mantém `legacy_actor`/`unresolved_actor`; não se cria uma nova identidade humana apenas para satisfazer FK. Auth sem perfil exige decisão sobre acesso V2 e não recebe tenant por metadata ou “primeira organização”.

## 8. Global Admin

Papéis V1 `administrador` ou `gestor` não mapeiam deterministicamente para Global Admin.

Evidências mínimas para candidatura:

- identidade Auth nominalmente confirmada;
- autorização organizacional/CW documentada;
- necessidade real de operar múltiplos tenants;
- histórico e finalidade das ações administrativas;
- confirmação de que não se trata apenas de administrador do tenant;
- aprovação explícita por autoridade responsável;
- capabilities de plataforma mínimas e target auditável.

| Caso | Regra | Confidence | Disposition |
| --- | --- | --- | --- |
| administrador com um tenant e sem evidência de plataforma | candidato a administração tenant, não Global Admin | MEDIUM | `REQUIRES_REVIEW` |
| usuário com acesso aparente a vários tenants por bypass legado | não promover; investigar origem | LOW | `QUARANTINE` |
| identidade CW explicitamente aprovada e documentada | criar mapping de platform identity separado | HIGH após aprovação | `CONDITIONAL` |
| papel/metadata apenas contém “admin” | evidência insuficiente | LOW | `REQUIRES_REVIEW` |

## 9. Perfis e permissões

### 9.1 Regras gerais

- Perfil V2 fornece baseline; não é autorização absoluta.
- Override individual usa a combinação exata Resource + Action + Scope.
- Scopes efetivos são união; `DENY OWN` não remove `ALLOW ALL_TENANT`.
- Scope ausente na V1 nunca é escolhido por conveniência.
- Bypass de `administrador`/`gestor` em `tem_permissao_usuario` é evidência de comportamento legado, não grant migrável.
- `permitido=false` preserva evidência, mas não vira `DENY` individual automaticamente.

### 9.2 Dicionário preliminar de permissões

| Legacy permission | Significado conhecido | Resource V2 | Action V2 | Scope V2 | Confidence | Disposition | Evidência/revisão necessária |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `visualizar_todas`, `solicitacao_visualizar_todas` | ler demandas do tenant | Request | View | ALL_TENANT | MEDIUM | `CONDITIONAL` | confirmar policies/uso remoto e projeção |
| `visualizar_proprias`, `solicitacao_visualizar_proprias` | ler criadas pelo ator | Request | View | OWN | MEDIUM | `CONDITIONAL` | definir OWN do recurso como requester/creator |
| `cadastrar_demanda`, `solicitacao_criar` | criar demanda/solicitação | Request | Create | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | criação não herda scope de leitura automaticamente |
| `criar_corretiva` | criar tipo corretiva | Request | Create Corrective | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | confirmar action granular V2 |
| `criar_agendamento` | criar agendamento | Request | Create Scheduling | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | confirmar action/resource model V2 |
| `criar_preventiva` | criar demanda preventiva | nenhum grant Request equivalente | N/A | N/A | HIGH | `LEGACY_ONLY` | Preventiva não é Request; revisar autoridade em Planos/OS |
| `editar_todas`, `solicitacao_editar` | editar demandas amplamente | Request | Update | ALL_TENANT candidato | LOW | `REQUIRES_REVIEW` | `solicitacao_editar` não codifica scope |
| `editar_proprias`, `solicitacao_editar_proprias` | editar próprias demandas | Request | Update | OWN | MEDIUM | `CONDITIONAL` | definir campos e estados permitidos |
| `classificar_prioridade` | alterar prioridade | Request | Set priority | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | scope e delegabilidade não comprovados |
| `alterar_status`, `solicitacao_alterar_status` | mudar status | Request | Transition | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | mapear transições, não update genérico |
| `apagar_demanda`, `solicitacao_excluir` | apagar fisicamente | Request | nenhuma promoção automática | N/A | HIGH | `LEGACY_ONLY` | V2 prefere cancelar/arquivar; exclusão excepcional |
| `aprovar_agendamento` | decidir agendamento | Request/Scheduling | Approve/Reject scheduling | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | scope e estados válidos |
| `visualizar_historico`, `historico_visualizar` | ler histórico | Operational History | View | herda alcance do pai + capability própria | MEDIUM | `CONDITIONAL` | provar que acesso ao histórico não amplia pai |
| `excluir_midia`, `galeria_excluir` | remover arquivo | File/Media | Remove | alcance do pai `UNKNOWN` | LOW | `REQUIRES_REVIEW` | retenção, finalidade e parent scope |
| `galeria_visualizar` | ver mídia | File/Media | View | alcance do pai | MEDIUM | `CONDITIONAL` | parent access obrigatório |
| `gerenciar_usuarios`, `usuarios_gerenciar` | administrar usuários | Application User | Manage | ALL_TENANT candidato | LOW | `REQUIRES_REVIEW` | separar invite/update/block/team/profile e anti-escalada |
| `gerenciar_permissoes` | alterar matriz | Permission Governance | Manage | ALL_TENANT candidato | LOW | `REQUIRES_REVIEW` | ninguém concede o que não possui |
| `gerenciar_empreendimento` | editar organização | Tenant Settings | Update | ALL_TENANT | MEDIUM | `CONDITIONAL` | separar campos comerciais reservados à CW |
| `configuracoes_editar` | editar múltiplos cadastros | vários recursos | várias actions | ALL_TENANT candidato | LOW | `REQUIRES_REVIEW` | permissão ampla deve ser decomposta |
| `os_visualizar_todas` | ler todas as OS | Work Order | View | ALL_TENANT | MEDIUM | `CONDITIONAL` | projeção sensível separada |
| `os_visualizar_resumo` | resumo de OS ligada à própria demanda | Work Order | View summary | OWN/RELATED candidato | LOW | `REQUIRES_REVIEW` | scope RELATED não está CLOSED; definir alcance por recurso |
| `os_criar` | criar OS | Work Order | Create | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | origem e target scope |
| `os_editar` | update amplo de OS | Work Order | várias actions | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | decompor planejar, atribuir, executar e editar |
| `os_concluir` | concluir execução | Work Order | Finish execution/Submit validation | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | depende da configuração tenant e papel de executor |
| `os_cancelar` | cancelar OS | Work Order | Cancel | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | motivo e scope obrigatórios |
| `os_aceitar` | aceitar/recusar OS | Work Order | Validate/Return | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | fluxo V1 permitia requester; V2 exige capability |
| `ativos_visualizar` | ler ativos | Asset | View | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | scope não codificado |
| `ativos_editar` | criar/editar/inativar ativos | Asset | várias actions | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | decompor por action |
| `planos_editar` | gerir planos | Preventive Plan | várias actions | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | decompor create/update/schedule |
| `prestadores_visualizar` | ler prestadores | Supplier | View | `UNKNOWN` | MEDIUM | `REQUIRES_REVIEW` | scope não codificado |
| `prestadores_editar` | gerir prestadores | Supplier | várias actions | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | decompor create/update/block/document |
| `emitir_relatorios`, `relatorios_emitir` | gerar relatório | Report | Generate | alcance das fontes | MEDIUM | `CONDITIONAL` | nunca ampliar source scopes |
| `custos_visualizar` | ler custos | Work Order Cost | View | alcance da OS + projeção | MEDIUM | `CONDITIONAL` | capability sensível separada |
| `custos_editar` | editar custos | Work Order Cost | Update | `UNKNOWN` | LOW | `REQUIRES_REVIEW` | scope e estado da OS |

Cada linha resultante em 10C deve apontar para uma capability técnica V2 aprovada. Não encontrar correspondência significa não conceder.

## 10. Operações, Locais, Setores, Centros de Custo e Equipes

### 10.1 Matriz de evidências para `operacoes`

| Evidência futura | Destino possível | Regra de decisão | Sem evidência |
| --- | --- | --- | --- |
| endereço físico, hierarquia espacial e uso em `demandas.local`/`ativos.local` | Local | revisão confirma unidade física dentro do tenant | `REQUIRES_REVIEW` |
| código contábil, apropriação de custos e uso financeiro | Centro de Custo | código/finalidade confirmados | `REQUIRES_REVIEW` |
| divisão organizacional estável, sem função de execução | Setor | responsabilidade organizacional comprovada | `REQUIRES_REVIEW` |
| grupo operacional de usuários usado em atribuição | Equipe | membros e função operacional comprovados | `REQUIRES_REVIEW` |
| mistura de significados conforme registro/tenant | destinos distintos | classificar por subconjunto/registro | `QUARANTINE` até decisão |
| apenas seletor legado sem valor V2 | provenance | retenção aprovada | `LEGACY_ONLY` |
| registro inconsistente/sem tenant | nenhum operacional | preservar payload | `QUARANTINE` |

### 10.2 Mapeamentos

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `operacoes` | `id`, `nome`, `codigo`, `endereco`, `ativo` | unidade polivalente | Local/CC/Setor/Equipe/outro | reclassify | somente após matriz de evidência | nulo não recebe categoria | `organizacao_id` validado | N/A | obrigatório | LOW | `REQUIRES_REVIEW` |
| `usuario_operacoes` | `usuario_id`, `operacao_id`, `principal` | afiliação do usuário | membership de Equipe/Setor/Local ou legacy | resolve after operation classification | ambos os mappings e mesmo tenant | `principal=false` não é ausência | tenant da operação = usuário | N/A | obrigatório | LOW | `REQUIRES_REVIEW` |
| `centros_custo` | `id` | identidade local | Centro de Custo UUID | generate/register | tenant e unicidade válidos | nulo inválido | `organizacao_id` | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `centros_custo` | `nome`, `codigo`, `ativo` | cadastro básico | nome, código e status | trim/preserve/reclassify | não mesclar por nome; código duplicado revisado | código nulo permitido | mesmo tenant | N/A | valores originais | MEDIUM | `CONDITIONAL` |
| `demandas` | `operacao_id`, `local`, `centro_custo_id` | referências/texto potencialmente sobrepostos | Request.local/setor/equipe/CC | resolve/reclassify | cada dimensão tratada separadamente | nulo = não capturado | invariants de todos os pais | N/A | obrigatório | LOW | `REQUIRES_REVIEW` |
| `ativos` | `operacao_id`, `local` | operação e localização textual | Asset.local e/ou legacy location | resolve/reclassify | nunca reconstruir Local por nome isolado | nulo permitido | mesmo tenant | N/A | obrigatório | LOW | `REQUIRES_REVIEW` |

Setores e Equipes V2 sem fonte comprovada não são gerados automaticamente. Seeds ou cadastros novos pertencem à construção V2, não à migração de fatos legados.

## 11. Códigos e sequências

### 11.1 Namespaces conhecidos

| Domínio | Fontes de código/counter V1 | Regra V2 | Mapping |
| --- | --- | --- | --- |
| Request | `demandas.codigo`, `codigo_solicitacao`, `sequencias_demandas`, `cw_sequencias(SOL)` | anual por tenant | preservar ambos como legado; escolher código humano operacional somente por regra/revisão |
| OS | `ordens_servico.codigo`, `cw_sequencias(OS)` | `OS-AAAA-NNN` por tenant | preservar emitido; validar formato/ano/tenant |
| Ativo | `ativos.codigo`, `cw_sequencias(EQP)` | `AT-NNNNN` único por tenant | preservar `EQP-*`; novo padrão não renumera histórico |
| Empreendimento | `organizacoes.id`, possível slug; código estável não comprovado | `EMP-*` conceitual | gerar futuramente sem substituir source ID |

### 11.2 Regra de reconciliação de contador

Para cada `tenant + namespace + período aplicável`:

```text
emitted_set = todos os códigos preserváveis do snapshot e delta
parsed_max = maior ordinal parseável sem colisão
stored_counter = valor revalidado da fonte aplicável
next_safe > max(parsed_max, stored_counter, ordinais emitidos durante convivência)
```

Gaps permanecem. Código não parseável continua histórico e não é reformatado. `sequencias_demandas` é anual global na definição local, enquanto `cw_sequencias` inclui tenant; essa divergência exige `REVALIDATION_REQUIRED` e análise de colisões.

| Condição | Disposition |
| --- | --- |
| código único no tenant/namespace e formato reconhecido | `CONDITIONAL` preserve |
| código nulo em entidade cujo histórico admite ausência | preservar null + gerar código V2 somente conforme política de ativação, sem fingir código histórico |
| mesmo código em tenants distintos quando namespace é por tenant | permitido após confirmar regra e tenant |
| mesmo código duplicado no mesmo tenant/namespace | `QUARANTINE` `CODE_COLLISION` |
| counter abaixo do maior emitido | não reescrever registro; calcular próximo seguro e registrar divergência |
| counter acima do maior emitido | preservar gap; próximo nunca retrocede |

## 12. Requests

### 12.1 Campos de `demandas`

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `demandas` | `id` | PK bigint | Request UUID | generate/register | linha elegível como Request | nulo inválido | mapping por `organizacao_id` | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `demandas` | `codigo`, `codigo_solicitacao` | códigos de gerações distintas | human code + aliases legados | select/preserve | regra de precedência definida após snapshot; ambos preservados | ambos nulos: review | mesmo tenant | N/A | ambos no registry | LOW | `REQUIRES_REVIEW` |
| `demandas` | `organizacao_id` | tenant | Request tenant | resolve registry | target tenant obrigatório | nulo: quarantine | self | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `demandas` | `titulo` | título/tipo textual em UIs antigas | título V2 | trim preservando original | trimmed non-empty | nulo/vazio: quarantine | Request tenant | creator | original | HIGH | `CONDITIONAL` |
| `demandas` | `categoria` | categoria textual, às vezes constante “Manutenção” | Category relation ou legacy category text | resolve taxonomy | match exato aprovado no tenant; não criar categoria silenciosamente | nulo: review | mesmo tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `demandas` | `natureza`, `tipo_servico` | classificações incrementais/textuais | Request type e Category/Subcategory candidates | merge/reclassify | dicionário versionado e sem conflito | nulo permitido | mesmo tenant | N/A | todos os valores | LOW | `REQUIRES_REVIEW` |
| `demandas` | `tipo_demanda` | corretiva/agendamento/preventiva | Request type ou domínio preventiva | reclassify/split | matriz 12.2 | nulo/fora do enum: quarantine | mesmo tenant | N/A | obrigatório | MEDIUM | `CONDITIONAL` |
| `demandas` | `prioridade` | A definir/Baixa/Média/Alta/Urgente | prioridade oficial | reclassify | matriz 12.3 | `A definir`/null não vira Normal | mesmo tenant | histórico pode resolver ator | original | MEDIUM | `CONDITIONAL` |
| `demandas` | `status` | status acumulado | Request status + scheduling decision/history | reclassify/split | matriz 12.4 e evidência temporal | nulo/fora: quarantine | mesmo tenant | evento separado | original | LOW | `CONDITIONAL` |
| `demandas` | `responsavel` | nome/texto, não FK | responsável individual candidato | resolve identity only with strong evidence | match único aprovado; nome isolado não basta | nulo = não atribuído | mesmo tenant | target user | valor original | LOW | `REQUIRES_REVIEW` |
| `demandas` | `criado_por` | criador/solicitante usado em policies | requester e/ou creator | resolve actor; split only if semantics confirmed | Auth mapping e tenant/contexto válidos | nulo: unresolved, não inventar | cross-tenant policy | actor resolution | obrigatório | MEDIUM | `CONDITIONAL` |
| `demandas` | `local`, `operacao_id` | texto e referência polivalente | Local relation + legacy text | resolve/reclassify | catálogo aprovado e mesmo tenant | nulo permitido | invariants | N/A | original | LOW | `REQUIRES_REVIEW` |
| `demandas` | `centro_custo_id` | FK simples | Centro de Custo relation | registry resolve | pai existe e mesmo tenant | nulo permitido | obrigatório se presente | N/A | source FK | HIGH | `CONDITIONAL` |
| `demandas` | `observacoes` | descrição do problema/serviço | descrição detalhada | preserve | não converter em comentário | nulo permitido conforme tipo/regra histórica | mesmo tenant | creator | original | HIGH | `CONDITIONAL` |
| `demandas` | `observacoes_adicionais` | texto usado também em cancelamento/reagendamento | motivo/evento/provenance | classify per status/event | só vira motivo quando função/estado comprova | nulo preservado | mesmo tenant | actor if event known | original | LOW | `REQUIRES_REVIEW` |
| `demandas` | `prazo` | date de prazo | deadline civil date | preserve date | calendário/fuso do tenant não altera date | nulo permitido | mesmo tenant | setter unknown | original | HIGH | `CONDITIONAL` |
| `demandas` | `agendamento_em` | instante previsto | scheduling start/desired datetime | preserve instant after timezone validation | somente para agendamento/planejamento coerente | nulo condicionado ao tipo | mesmo tenant | requester/planner | original | MEDIUM | `CONDITIONAL` |
| `demandas` | `empresa_prestador` | prestador/responsável textual | Supplier relation ou legacy text | resolve only with strong evidence | nome isolado não faz merge | nulo permitido | supplier same tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `demandas` | `proxima_acao` | texto operacional livre | provenance/history candidate | preserve as legacy context | não vira status/action estruturada automaticamente; uso operacional futuro exige revisão separada | nulo permitido | mesmo tenant | unknown | original | LOW | `LEGACY_ONLY` |
| `demandas` | `finalizada_por_os` | flag incremental | history/provenance de sugestão/decisão | preserve evidence only | não concluir Request automaticamente | false não prova ausência histórica | mesmo tenant | actor unknown | obrigatório | MEDIUM | `LEGACY_ONLY` |
| `demandas` | `criado_em`, `atualizado_em`, `concluido_em` | timestamps operacionais | created/updated/completed + provenance | preserve after temporal checks | status/date consistency matrix | nulo conforme campo; não inventar | mesmo tenant | actor resolution separate | original | HIGH | `CONDITIONAL` |

Ativo não aparece como FK na definição local conhecida de `demandas`; qualquer vínculo remoto adicional é `REVALIDATION_REQUIRED`. Setor e Equipe não possuem campos V1 comprovados e não podem ser derivados de responsável/operação.

### 12.2 Matriz de tipo/natureza

| Tipo/natureza V1 | Tipo Request V2 | Regra | Confidence | Disposition |
| --- | --- | --- | --- | --- |
| `tipo_demanda='corretiva'` | Corrective Maintenance | tenant válido e conteúdo representa ocorrência corretiva | MEDIUM | `CONDITIONAL` |
| `tipo_demanda='agendamento'` | Service Scheduling | dados/fluxo de agendamento coerentes | MEDIUM | `CONDITIONAL` |
| `tipo_demanda='preventiva'` | nenhum Request | classificar em Plano/Programação/OS/legacy; manter em quarentena enquanto a revisão não resolver | HIGH quanto à não permanência como Request | `REQUIRES_REVIEW` |
| `natureza='Preventiva'` ou texto semelhante | nenhum mapping pelo texto isolado | analisar origem/plano/OS | LOW | `REQUIRES_REVIEW` |
| `natureza`/`tipo_servico` indica serviço genérico | Service Request | exige dicionário e evidência do registro | LOW | `REQUIRES_REVIEW` |
| valor indica inspeção/vistoria | Inspection/Survey | exige vocabulário aprovado e contexto | LOW | `REQUIRES_REVIEW` |
| tipo nulo/desconhecido/conflitante | UNKNOWN | preservar e impedir carga operacional | UNKNOWN | `QUARANTINE` |

### 12.3 Matriz de prioridade

| Prioridade V1 | Prioridade V2 | Regra | Confidence | Disposition |
| --- | --- | --- | --- | --- |
| `Baixa` | Low/Baixa | igualdade do valor controlado | HIGH | `DETERMINISTIC` |
| `Alta` | High/Alta | igualdade do valor controlado | HIGH | `DETERMINISTIC` |
| `Urgente` | Urgent/Urgente | igualdade do valor controlado | HIGH | `DETERMINISTIC` |
| `Média` | Normal | decisão funcional preliminar do GAP; confirmar dicionário | MEDIUM | `CONDITIONAL` |
| `A definir`, null | UNKNOWN/NOT_CAPTURED | não aplicar Normal como default histórico | HIGH | `REQUIRES_REVIEW` ou manter ausência permitida em staging |
| outro | UNKNOWN | nenhuma aproximação textual | UNKNOWN | `QUARANTINE` |

### 12.4 Matriz de status Request

| Status V1 | Status Request V2 | Regra objetiva adicional | Confidence | Disposition |
| --- | --- | --- | --- | --- |
| `Registrado` | Registered | tipo elegível como Request | HIGH | `CONDITIONAL` |
| `Em análise` | Under analysis | tipo elegível e sem evidência conflitante | HIGH | `CONDITIONAL` |
| `Programado` | Scheduled | programação válida ou evento que a comprove | MEDIUM | `CONDITIONAL` |
| `Em andamento` | In progress | registro Request, não simples execução de OS/preventiva | MEDIUM | `CONDITIONAL` |
| `Aguardando aprovação` | Under analysis + scheduling decision pending | somente agendamento; preservar subestado/evento | MEDIUM | `CONDITIONAL` |
| `Aprovado` | Scheduled + approval history | somente agendamento com decisão e data coerentes | MEDIUM | `CONDITIONAL` |
| `Reprovado` | Rejected + rejection history | decisão de agendamento/rejeição comprovada; motivo ausente gera item de revisão sem default | MEDIUM | `CONDITIONAL` |
| `Agendado` | Scheduled | data/semântica de agendamento coerentes | MEDIUM | `CONDITIONAL` |
| `Em execução` | In progress | confirmar que o Request representa acompanhamento, não preventiva indevida | LOW | `REQUIRES_REVIEW` |
| `Concluído` | Completed | `concluido_em` ou evidência histórica coerente; ausência gera revisão | MEDIUM | `CONDITIONAL` |
| `Cancelado` | Cancelled | preservar motivo quando comprovado; ausência gera item de revisão e não é preenchida | MEDIUM | `CONDITIONAL` |
| `A Fazer` | Registered candidato | valor de schema anterior; confirmar que não escapou da normalização | LOW | `REQUIRES_REVIEW` |
| `Em Andamento` | In progress candidato | confirmar geração do schema e semântica | LOW | `REQUIRES_REVIEW` |
| `Aguardando Terceiros` | Under analysis ou outro estado | sem equivalência direta | LOW | `REQUIRES_REVIEW` |
| `Aguardando Aprovação` | decisão pendente | distinguir agendamento de outro fluxo | LOW | `REQUIRES_REVIEW` |
| `Concluída` | Completed candidato | validar geração, tipo e datas | LOW | `REQUIRES_REVIEW` |
| `Cancelada` | Cancelled candidato | validar geração e motivo | LOW | `REQUIRES_REVIEW` |
| null/outro | UNKNOWN | preservar valor original | UNKNOWN | `QUARANTINE` |

## 13. Agendamentos

Agendamento é um tipo de Request e uma fonte do Calendário; Calendário não é entidade operacional duplicada.

| Fonte/conceito | Destino V2 | Regra | Null/Default | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- |
| `tipo_demanda='agendamento'` | Request type Service Scheduling | demais invariants válidos | tipo nulo não inferido por data | MEDIUM | `CONDITIONAL` |
| `agendamento_em` | data/hora solicitada/programada | preservar instante; semântica desejada vs aprovada exige histórico/status | nulo em status que exige agenda: quarantine/review | MEDIUM | `CONDITIONAL` |
| `empresa_prestador` | Supplier ou responsável textual | resolver somente por mapping inequívoco | nulo preservado | LOW | `REQUIRES_REVIEW` |
| `Aguardando aprovação` | decisão pendente | vira estado/evento de aprovação, não novo Request | não fabricar evento | MEDIUM | `CONDITIONAL` |
| `Aprovado` | aprovação histórica + Scheduled | ator/data podem vir do histórico; se ausentes, provenance incompleta | sem ator = unresolved | MEDIUM | `CONDITIONAL` |
| `Reprovado` | rejeição histórica + Rejected | preservar motivo quando comprovado | sem motivo = review | MEDIUM | `CONDITIONAL` |
| mudança de `agendamento_em` com retorno a aprovação | reagendamento/evento | detectar por histórico, não apenas valor final | histórico ausente = provenance apenas | LOW | `REQUIRES_REVIEW` |
| `observacoes_adicionais` em cancelamento | motivo de cancelamento candidato | somente se função/status comprovar finalidade | nulo não recebe texto | LOW | `CONDITIONAL` |

O estado final não permite reconstruir todos os eventos intermediários. Sem histórico suficiente, preservar apenas o estado atual e a provenance; não sintetizar aprovação/reagendamento.

## 14. Ordens de Serviço

### 14.1 Campos principais

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ordens_servico` | `id` | PK bigint | Work Order UUID | generate/register | source identity única | nulo inválido | `organizacao_id` mapping | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `ordens_servico` | `codigo` | código humano | OS human code | preserve | único no tenant; colisão quarantine | nulo exige política futura sem fabricar legado | mesmo tenant | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `ordens_servico` | `organizacao_id` | tenant | Work Order tenant | resolve | obrigatório | nulo: quarantine | self | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `ordens_servico` | `solicitacao_id` | Request opcional | Request relation | registry resolve | pai existe e mesmo tenant | nulo = OS manual/sem Request possível | igualdade tenant | N/A | source FK | HIGH | `CONDITIONAL` |
| `ordens_servico` | `plano_manutencao_id` | origem/plano opcional | Preventive Plan/Schedule/Occurrence relation | resolve/split | matriz preventiva | nulo permitido | mesmo tenant | N/A | obrigatório | MEDIUM | `CONDITIONAL` |
| `ordens_servico` | `ativo_id` | ativo opcional | Asset relation | registry resolve | pai existe e mesmo tenant | nulo permitido | mesmo tenant | N/A | source FK | HIGH | `CONDITIONAL` |
| `ordens_servico` | `prestador_id` | prestador opcional | Supplier relation | registry resolve | pai existe, não implica executor Auth | nulo permitido | mesmo tenant | N/A | source FK | HIGH | `CONDITIONAL` |
| `ordens_servico` | `executor_id` | executor único | executor membership | resolve actor | identidade/membership no tenant e evidência de execução | nulo = sem executor capturado | mesmo tenant | mapped actor | source FK | MEDIUM | `CONDITIONAL` |
| `ordens_servico` | `executor_id` | possível responsável implícito | responsible relation | não copiar automaticamente | somente evidência inequívoca separada | nulo permanece | mesmo tenant | mapped actor | evidência | LOW | `REQUIRES_REVIEW` |
| `ordens_servico` | `centro_custo_id` | CC opcional | Cost Center relation | registry resolve | pai e tenant válidos | nulo permitido | mesmo tenant | N/A | source FK | HIGH | `CONDITIONAL` |
| `ordens_servico` | `titulo` | título | title | trim/preserve | non-empty | vazio: quarantine | mesmo tenant | creator | original | HIGH | `CONDITIONAL` |
| `ordens_servico` | `natureza` | tipo/natureza textual | Work Order type/category candidates | reclassify | matriz de tipo + dicionário | nulo: review | mesmo tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `ordens_servico` | `prioridade` | prioridade textual | priority | matriz Request quando valores equivalentes | `A definir` não vira Normal | nulo/unknown: review | mesmo tenant | setter unknown | original | MEDIUM | `CONDITIONAL` |
| `ordens_servico` | `local` | localização textual | Local relation + legacy text | resolve only by approved catalog | nome isolado não basta | nulo permitido | mesmo tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `ordens_servico` | `descricao` | serviço solicitado | requested service/description | preserve | não confundir com executado | nulo permitido conforme regra | mesmo tenant | creator | original | HIGH | `CONDITIONAL` |
| `ordens_servico` | `descricao_execucao` | serviço executado | executed service | preserve | concluída exige conforme configuração/evidência | nulo pode gerar invalid state | mesmo tenant | executor candidate | original | HIGH | `CONDITIONAL` |
| `ordens_servico` | `observacoes_executor` | observação de execução | execution notes | preserve | não vira comentário | nulo permitido | mesmo tenant | executor candidate | original | HIGH | `CONDITIONAL` |
| `ordens_servico` | `status` | estado corrente | Work Order status | reclassify | matriz 14.3 | null/outro: quarantine | mesmo tenant | history resolves | original | MEDIUM | `CONDITIONAL` |
| `ordens_servico` | `inicio_previsto`, `fim_previsto` | janela programada | scheduled start/end | preserve instants | ordem temporal válida | nulos permitidos conforme status | mesmo tenant | planner unknown | original | HIGH | `CONDITIONAL` |
| `ordens_servico` | `inicio_real`, `fim_real`, `concluido_em` | execução/conclusão | actual start/end/completed | preserve with consistency checks | não preencher um a partir do outro sem regra | nulos conforme status | mesmo tenant | actor history | original | HIGH | `CONDITIONAL` |
| `ordens_servico` | `aceite_status` | pendente/aceito/recusado/dispensado | validation state/history | split/reclassify | matriz 14.4 | nulo/default legado não prova decisão | mesmo tenant | `aceite_por` | obrigatório | MEDIUM | `CONDITIONAL` |
| `ordens_servico` | `aceite_por`, `aceite_em`, `aceite_observacao`, `avaliacao` | decisão/feedback | validator, validation event, reason, optional legacy feedback | resolve/preserve | ator válido; recusa exige motivo; avaliação não amplia domínio | ausências preservadas | mesmo tenant | actor resolution | obrigatório | MEDIUM | `CONDITIONAL` |
| `ordens_servico` | `criado_por`, `criado_em`, `atualizado_em` | autoria/timestamps | creator/provenance | resolve/preserve | ator pode ser técnico/legado; temporal consistency | não inventar | cross-tenant policy | actor resolution | obrigatório | HIGH | `CONDITIONAL` |

Não há campo V1 comprovado de responsável separado nem tabela de múltiplos executores. A V2 poderá ter ambos, mas a migração não os fabrica.

### 14.2 Matriz de tipo/origem

| Evidência V1 | Origem V2 | Tipo V2 | Regra | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- |
| `solicitacao_id` válido, sem plano | Request | tipo derivado por dicionário próprio/Request apenas quando coerente | vínculo e tenant válidos | MEDIUM | `CONDITIONAL` |
| `plano_manutencao_id` válido, sem Request conflitante | Preventive Maintenance | Preventive | plano, agenda e tenant coerentes | MEDIUM | `CONDITIONAL` |
| ambos IDs nulos | Manual | Corrective/Inspection/Service `UNKNOWN` | origem manual é inferível; tipo não | MEDIUM/HIGH | `CONDITIONAL` + `REQUIRES_REVIEW` |
| `natureza='Preventiva'` sem plano | `UNKNOWN` | Preventive candidato | texto isolado é insuficiente | LOW | `REQUIRES_REVIEW` |
| Request e Plano presentes | conflito potencial | `UNKNOWN` | revisar intenção; não escolher por precedência | LOW | `QUARANTINE` |
| natureza Corretiva aprovada em dicionário | origem conforme vínculos | Corrective | valor controlado + contexto coerente | MEDIUM | `CONDITIONAL` |
| natureza Inspeção/Vistoria aprovada | origem conforme vínculos | Inspection/Survey | dicionário explícito | MEDIUM | `CONDITIONAL` |
| natureza Serviço aprovada | origem conforme vínculos | Service | dicionário explícito | MEDIUM | `CONDITIONAL` |

### 14.3 Matriz de status OS

| Status V1 | Status OS V2 | Regra adicional | Confidence | Disposition |
| --- | --- | --- | --- | --- |
| `Aberta` | Open | sem evidência de programação/execução conflitante | HIGH | `CONDITIONAL` |
| `Planejada` | Scheduled | datas programadas ou história coerente | MEDIUM | `CONDITIONAL` |
| `Aguardando execução` | Scheduled | programação válida; preservar label legado | MEDIUM | `CONDITIONAL` |
| `Em execução` | In execution | início real ou história coerente; ausência gera item de revisão | MEDIUM | `CONDITIONAL` |
| `Pausada` | Paused | motivo/intervalo de pausa não estão estruturados na fonte conhecida | LOW | `QUARANTINE` ou revisão por política de carga |
| `Concluída` + validação dispensada/aceita coerente | Completed | datas/serviço executado conforme regras aplicáveis | MEDIUM | `CONDITIONAL` |
| `Concluída` + `aceite_status='pendente'` quando validação requerida | Awaiting validation candidato | configuração tenant histórica e semântica precisam ser comprovadas | LOW | `REQUIRES_REVIEW` |
| `Cancelada` | Cancelled | motivo obrigatório não está estruturado; preservar lacuna e manter fora da carga até decisão | LOW | `REQUIRES_REVIEW` |
| null/outro | UNKNOWN | nenhuma aproximação textual | UNKNOWN | `QUARANTINE` |

### 14.4 Validação/aceite

| `aceite_status` V1 | Tratamento V2 | Regra | Disposition |
| --- | --- | --- | --- |
| `aceito` | validation approval event + Completed candidato | `aceite_por/em` coerentes; V2 capability não é herdada | `CONDITIONAL` |
| `recusado` | return event + In execution candidato | motivo obrigatório; sem motivo, quarantine; preservar ciclos somente se histórico existir | `CONDITIONAL` |
| `dispensado` | validation-not-required provenance | comprovar regra/configuração ou tratar como legado | `REQUIRES_REVIEW` |
| `pendente` em OS não concluída | ausência de decisão | não criar Awaiting validation automaticamente | `LEGACY_ONLY` quanto ao default |
| `pendente` em OS concluída | estado inconsistente ou validação pendente | depende da configuração histórica | `REQUIRES_REVIEW` |

### 14.5 Custos e materiais

| Source V1 | Destino V2 | Regra | Null/Default | Tenant | Disposition |
| --- | --- | --- | --- | --- | --- |
| `ordens_servico_custos.custo_mao_obra` | labor cost | numeric válido; zero legado pode ser valor real ou default | não converter zero em null | mesmo da OS | `CONDITIONAL` |
| `custo_materiais`, `outros_custos` | material/other costs | mesma regra | preservar zero | mesmo da OS | `CONDITIONAL` |
| `observacoes` | cost notes | preservar texto | nulo permitido | mesmo da OS | `CONDITIONAL` |
| `atualizado_por/em` | cost provenance/history candidate | resolve ator e tempo | não inventar | mesmo da OS | `CONDITIONAL` |
| `ordem_servico_materiais.descricao` | material description | non-empty | vazio: quarantine | mesmo da OS | `CONDITIONAL` |
| `quantidade`, `unidade`, `valor_unitario` | quantity/UOM/unit cost | quantidade positiva/coerente; UOM desconhecida gera revisão | unidade nula não recebe default | mesmo da OS | `CONDITIONAL` |

## 15. Request × OS

| Relação/caso V1 | Destino V2 | Regra | Falha |
| --- | --- | --- | --- |
| OS com `solicitacao_id` válido | Work Order → 0..1 Request | resolver ambos no registry e confirmar tenant | `BROKEN_REFERENCE`/`TENANT_MISMATCH` → `QUARANTINE` |
| várias OS apontam para a mesma demanda | Request → 0..N Work Orders | preservar todas; isso é válido na V2 | código/vínculo duplicado é analisado separadamente |
| OS sem `solicitacao_id` | OS manual/sem Request | não criar Request artificial | nenhuma falha |
| demanda sem OS | Request com 0 OS | preservar | nenhuma falha |
| `finalizada_por_os=true` | provenance/history | não aplicar conclusão automática | revisar status/evento |
| OS concluída e Request aberta | entidades independentes | preservar ambos os estados | nenhuma correção automática |

O vínculo não é inferido por código, título, datas, Ativo ou texto. Apenas FK/relação comprovada ou decisão de revisão explicitamente registrada pode criá-lo.

## 16. Preventiva

### 16.1 Mapeamento dos conceitos

| Source V1 | Campo/Conceito | Destino V2 | Regra | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- |
| `planos_manutencao.id` | identidade do registro | Preventive Plan UUID | gerar/register se plano válido | HIGH | `CONDITIONAL` |
| `nome`, `descricao` | definição do trabalho | Plan title/instructions candidate | preservar sem inventar instruções | HIGH | `CONDITIONAL` |
| `ativo_id` | ativo obrigatório | Plan → Asset | mapping existe, mesmo tenant | HIGH | `CONDITIONAL`; falha `QUARANTINE` |
| `periodicidade_dias` | intervalo em dias | schedule recurrence interval | >0; não converter para mensal/anual por aproximação | HIGH | `DETERMINISTIC` quanto ao intervalo |
| `proxima_execucao` | cursor/data seguinte | Schedule next planned civil date | preservar como estado observado; não prova histórico | MEDIUM | `CONDITIONAL` |
| `antecedencia_dias` | lead time | generation lead time candidate | >=0; não é periodicidade | HIGH | `CONDITIONAL` |
| `prestador_id` | prestador planejado | Plan/Schedule Supplier | mapping válido, mesmo tenant | HIGH | `CONDITIONAL` |
| `executor_id` | executor planejado | assigned executor candidate | identity e membership válidos | MEDIUM | `CONDITIONAL` |
| responsável/equipe ausentes | sem dado legado (`NOT_CAPTURED`) | nenhum preenchimento | não usar executor como responsável automaticamente | HIGH | `REQUIRES_REVIEW` |
| `ativo` | status do plano | Plan active/inactive | map boolean, sem inferir arquivamento | HIGH | `CONDITIONAL` |
| OS com `plano_manutencao_id` | materialização | Preventive Occurrence + Work Order relation | data planejada e tenant coerentes | MEDIUM | `CONDITIONAL` |
| `inicio_previsto::date` | competência usada na deduplicação V1 | canonical planned competence candidate | timezone/civil date e schedule devem ser confirmados | LOW | `REQUIRES_REVIEW` |
| demanda `tipo_demanda='preventiva'` | entidade indevida no modelo V2 | Plan/Schedule/OS/legacy | classificação por registro; nunca Request; quarantine até resolução | LOW | `REQUIRES_REVIEW` |
| checklist legado não comprovado | evidência parcial | legacy evidence | não sintetizar model/version/snapshot | UNKNOWN | `LEGACY_ONLY` |

### 16.2 Occurrence identity

Candidate key conceitual:

```text
target_tenant
+ target_schedule
+ canonical planned competence/instant
+ identity version quando comprovadamente necessária
```

Regras:

- uma OS não cria occurrence key sem vínculo e competência verificáveis;
- duas OS candidatas à mesma key são `OCCURRENCE_COLLISION` e entram em quarentena;
- `proxima_execucao` não retrocria ocorrências ausentes;
- o cursor não é avançado pela migração de histórico sem correspondência;
- timezone e semântica civil da competência são `REQUIRES_REVIEW`;
- geração futura é idempotente, mas o mecanismo físico pertence à 10C.

## 17. Ativos

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ativos` | `id` | PK bigint | Asset UUID | generate/register | source unique | nulo inválido | `organizacao_id` | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `ativos` | `codigo` | código `EQP-*`/outro | legacy human code + V2 code policy | preserve | único no tenant; não renumerar | nulo: política futura | mesmo tenant | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `ativos` | `nome` | nome | Asset name | trim/preserve | non-empty | vazio: quarantine | mesmo tenant | creator | original | HIGH | `CONDITIONAL` |
| `ativos` | `categoria` | texto | Asset type/category candidate | resolve taxonomy | dicionário aprovado | nulo permitido | mesmo tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `ativos` | `ativo` | flag cadastral | Active/Inactive | map boolean | `false` não significa Baixado | nulo não vira true | mesmo tenant | actor unknown | original | HIGH | `CONDITIONAL` |
| `ativos` | condição operacional (campo ausente) | não capturada | UNKNOWN | nenhuma default histórica | não assumir Operacional | N/A | mesmo tenant | N/A | ausência registrada | HIGH | `REQUIRES_REVIEW` |
| `ativos` | `ativo_pai_id` | hierarquia opcional | parent Asset | registry resolve | pai existe, mesmo tenant, sem ciclos | nulo = raiz | invariants obrigatórios | N/A | source FK | HIGH | `CONDITIONAL` |
| `ativos` | `operacao_id`, `local` | localização polivalente/textual | Local relation + legacy location | resolve/reclassify | catálogo aprovado; nunca por nome isolado | nulo permitido | mesmo tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `ativos` | `fabricante`, `modelo`, `numero_serie` | dados técnicos | technical attributes | trim/preserve | não criar Supplier automaticamente do fabricante | nulo permitido | mesmo tenant | N/A | original | HIGH | `CONDITIONAL` |
| `ativos` | `data_aquisicao`, `valor_aquisicao`, `garantia_ate` | aquisição/garantia | corresponding attributes | preserve/validate | datas e numeric válidos | nulo permitido | mesmo tenant | N/A | original | HIGH | `CONDITIONAL` |
| `ativos` | `especificacoes` | JSON flexível | structured specs ou legacy payload | map keys only via approved dictionary | JSON válido; chaves desconhecidas ficam somente na provenance, sem campo operacional inventado | `{}` pode ser default sem conteúdo | mesmo tenant | N/A | payload/hash | MEDIUM | `CONDITIONAL` |
| `ativos` | `criado_por`, timestamps | autoria/tempo | creator/provenance | resolve/preserve | actor/time policies | não inventar | cross-tenant policy | actor resolution | obrigatório | HIGH | `CONDITIONAL` |

Hierarquia inválida (`parent` ausente, self-parent, cross-tenant ou ciclo) recebe `ASSET_PARENT_INVALID` e `QUARANTINE`. Não reconstruir pai por código, nome ou localização.

## 18. Fornecedores

| Source V1 | Campo/Conceito V1 | Semântica V1 | Destino conceitual V2 | Transformação | Regra | Null/Default | Tenant | Actor | Provenance | Confidence | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `prestadores` | `id` | PK bigint | Supplier UUID | generate/register | source unique | nulo inválido | `organizacao_id` | N/A | obrigatório | HIGH | `CONDITIONAL` |
| `prestadores` | `tipo_pessoa` | fisica/juridica | PF/PJ | controlled map | valor pertencente ao enum conhecido; valor inválido não é elegível | nulo/outro: quarantine | mesmo tenant | N/A | original | HIGH | `DETERMINISTIC` |
| `prestadores` | `tipo_vinculo` | próprio/terceirizado | Supplier type/relation ou legacy attribute | reclassify | não equivale diretamente aos tipos funcionais V2 | nulo/unknown: review | mesmo tenant | N/A | original | LOW | `REQUIRES_REVIEW` |
| `prestadores` | `nome` | nome | legal/display name candidate | preserve | non-empty | vazio: quarantine | mesmo tenant | creator | original | HIGH | `CONDITIONAL` |
| `prestadores` | `cpf_cnpj` | documento opcional | tax identifier | normalize non-destructively | documento igual é evidência, não merge automático | nulo permitido | mesmo tenant | N/A | original + normalized | MEDIUM | `CONDITIONAL` |
| `prestadores` | `email`, `telefone` | contato único embutido | Supplier Contact row(s) | split | criar contatos somente para valores não vazios; finalidade UNKNOWN | nulo = sem contato | mesmo tenant | N/A | source field | MEDIUM | `CONDITIONAL` |
| `prestadores` | `especialidades[]` | lista textual | Supplier-specialty relations ou legacy values | split/reclassify | cada item por dicionário aprovado | vazio = nenhuma capturada | mesmo tenant | N/A | array original | LOW | `REQUIRES_REVIEW` |
| `prestadores` | `observacoes` | nota | Supplier notes | preserve | não converter em comentário | nulo permitido | mesmo tenant | creator/unknown | original | HIGH | `CONDITIONAL` |
| `prestadores` | `usuario_tecnico_id` | vínculo com perfil | explicit application-user relation candidate | resolve | não converte contato em Auth nem implica executor | nulo permitido | mesmo tenant | mapped actor | source FK | LOW | `REQUIRES_REVIEW` |
| `prestadores` | `ativo` | status | Active/Inactive | map boolean | `false` não significa Blocked | nulo não vira true | mesmo tenant | actor unknown | original | HIGH | `CONDITIONAL` |
| `prestadores` | `criado_por`, timestamps | autoria/tempo | creator/provenance | resolve/preserve | políticas gerais | não inventar | cross-tenant policy | actor resolution | obrigatório | HIGH | `CONDITIONAL` |

Merge de Fornecedores nunca ocorre apenas por nome parecido ou documento igual. Esses sinais criam candidato de revisão com todas as relações preservadas. Documentos e contatos não se tornam usuários da plataforma.

Relações Asset ↔ Supplier não possuem tabela explícita comprovada na fonte local; `prestador_id` em OS/Planos não autoriza inferir relação direta permanente com Ativo.

## 19. Checklists

| Conceito legado | Destino V2 | Regra | Disposition |
| --- | --- | --- | --- |
| definição de checklist comprovada | Checklist Model + version | somente se itens, ordem, tipos e obrigatoriedade forem identificáveis | `CONDITIONAL` |
| respostas comprovadas por execução | Checklist instance/responses | vincular a OS e modelo/versão comprovados | `CONDITIONAL` |
| arquivo/foto possivelmente de item | evidence candidate | exige vínculo explícito ao item/resposta | `REQUIRES_REVIEW` |
| texto livre de execução | executed service/legacy evidence | não converter em respostas | `LEGACY_ONLY` |
| estrutura incompleta | legacy payload | preservar, não sintetizar snapshot | `LEGACY_ONLY` |
| OS concluída sem checklist legado | nenhum checklist histórico fabricado | ausência registrada | `DETERMINISTIC` quanto a não criar |

A V2 exige snapshot imutável, mas essa exigência não autoriza retrocriar um snapshot que nunca existiu.

## 20. Histórico

### 20.1 `historico_demandas`

| Campo V1 | Destino | Regra | Disposition |
| --- | --- | --- | --- |
| `id` | source event identity | registry próprio | `CONDITIONAL` |
| `demanda_id` | parent Request | parent mapeado e tenant derivado do pai | `CONDITIONAL`; pai ausente `QUARANTINE` |
| `usuario_id`, `usuario_nome` | actor + display snapshot | resolver UUID; preservar nome histórico | `CONDITIONAL` |
| `alteracoes` JSON | Operational History event(s) ou legacy payload | parsear apenas chaves conhecidas; campos desconhecidos permanecem na provenance; evitar duplicar o mesmo update | `CONDITIONAL` |
| `criado_em` | event time | consistência temporal; timezone policy | `CONDITIONAL` |

### 20.2 `historico_ordens_servico`

| Campo V1 | Destino | Regra | Disposition |
| --- | --- | --- | --- |
| `ordem_servico_id`, `organizacao_id` | parent OS/tenant | ambos mapeados e coerentes | `CONDITIONAL`; divergência `QUARANTINE` |
| `usuario_id` | actor | actor resolution | `CONDITIONAL` |
| `acao` | operational event type candidate | dicionário exato; unknown permanece legacy | `REQUIRES_REVIEW` |
| `detalhes` | safe event payload/provenance | converter apenas campos conhecidos; preservar o restante somente na provenance | `CONDITIONAL` |
| `criado_em` | event time | temporal checks | `CONDITIONAL` |

Triggers são evidência de writer e semântica, não eventos a migrar. Logs/eventos duplicados por trigger e RPC devem ser deduplicados somente com identidade/regra objetiva; similaridade de texto/tempo não basta.

## 21. Auditoria

Não se retrofabrica Audit V2. Dados V1 podem resultar em:

- histórico operacional legado convertido com confiança;
- histórico `LEGACY_ONLY` com payload preservado;
- provenance do mapping e da transformação;
- auditoria técnica da execução futura da migração.

A auditoria técnica futura deve registrar `technical_actor`, identidade de migration/release, `migration_run_id`, source snapshot, regra/versão, target, resultado, correlation ID e timestamps. Ela começa com a execução da migração; não finge existir antes.

Policies, grants, functions e triggers legados são evidências de postura e risco. Não são convertidos em eventos de auditoria por usuário.

## 22. Comentários

Não há tabela separada de comentários comprovada. Portanto:

| Fonte candidata | Tratamento | Disposition |
| --- | --- | --- |
| `demandas.observacoes` | descrição da Request | `CONDITIONAL`, não comentário |
| `observacoes_adicionais` | motivo/evento/provenance conforme contexto | `REQUIRES_REVIEW` |
| `observacoes_executor` | nota de execução | `CONDITIONAL`, não comentário |
| `aceite_observacao` | motivo/nota de validação | `CONDITIONAL`, não comentário |
| histórico JSON/texto | Operational History | não converter em comentário |
| texto livre cuja intenção é ambígua | preservar como legacy/provenance | `REQUIRES_REVIEW` |

Ausência de comentário V1 não cria comentário V2 vazio nem mensagem atribuída a um ator.

## 23. Notificações

| Source V1 | Campo/conceito | Destino V2 | Regra | Disposition |
| --- | --- | --- | --- | --- |
| `notificacoes.id` | identity | notification candidate | source unique e ainda relevante | `CONDITIONAL` |
| `organizacao_id`, `usuario_id` | tenant/destinatário | authorized recipient | ambos mapeados; broadcast nulo requer revisão | `REQUIRES_REVIEW` |
| `titulo`, `mensagem` | conteúdo | safe notification content | não pode revelar entidade/campo sem acesso atual | `CONDITIONAL` |
| `referencia_tipo`, `referencia_id` | link polimórfico | target entity/link | tipo allowlisted e mapping existente | `CONDITIONAL`; falha `LEGACY_ONLY` |
| `lida_em`, `criado_em` | estado/tempo | read state/timestamps | preservar se válida | `CONDITIONAL` |
| notificação antiga/transitória | valor histórico | legacy record ou descarte futuro | exige decisão de retenção/relevância; enquanto aberta não é carregada como notificação V2 | `REQUIRES_REVIEW` |

Não recriar notificações como novas, não disparar e-mail/push e não copiar link que contorne reautorização. `usuario_id is null` não é automaticamente broadcast V2 autorizado.

## 24. Storage

### 24.1 Metadados conhecidos

| Source V1 | Parent | Campos principais | Destino | Disposition |
| --- | --- | --- | --- | --- |
| `anexos_demandas` | Request (`demanda_id`) | `storage_path`, nome, tipo, tamanho, descrição, creator, nome, data | file metadata + Request association | `CONDITIONAL` |
| `ordem_servico_arquivos` | OS | `etapa`, nome, path, MIME, tamanho, creator, data | file/evidence metadata + OS association | `CONDITIONAL` |
| `ativo_arquivos` | Asset | nome, path, MIME, tamanho, creator, data | file metadata + Asset association | `CONDITIONAL` |
| `prestador_documentos` | Supplier | nome, path, MIME, tamanho, creator, data | Supplier document metadata | `CONDITIONAL` |
| `organizacoes.logo_path` | Tenant | path | branding file metadata | `CONDITIONAL` |

### 24.2 Mapping canônico de objeto

```text
source bucket
+ source key
+ metadata source entity/id
+ mapped parent entity/id
+ target tenant
+ uploader actor resolution
+ declared size/MIME
+ observed size/MIME/checksum quando obtível
→ target object identity + target metadata + association status
```

Bucket V1 não determina bucket V2. `storage_path` não é autorização nem identidade suficiente.

### 24.3 Classificação de exceções

| Caso | Reason code | Disposition |
| --- | --- | --- |
| objeto sem metadata | `STORAGE_METADATA_MISSING` | `QUARANTINE` ou `DISCARD_CANDIDATE` após retenção |
| metadata sem objeto | `STORAGE_OBJECT_MISSING` | `QUARANTINE` |
| parent inexistente/não mapeado | `STORAGE_PARENT_UNRESOLVED` | `QUARANTINE` |
| tenant do metadata diverge do parent/path | `TENANT_MISMATCH` | `QUARANTINE` |
| path não segue formato esperado | `STORAGE_PATH_INVALID` | `REQUIRES_REVIEW`; não reatribuir pelo path |
| conteúdo duplicado | `STORAGE_DUPLICATE_CONTENT` | preservar associações; deduplicação física é decisão futura |
| MIME não permitido ou divergente | `STORAGE_MIME_UNSUPPORTED` | `QUARANTINE` |
| uploader ausente | `ACTOR_UNRESOLVED` | metadata pode migrar com ator unresolved conforme política; não inventar |
| checksum indisponível | `INTEGRITY_UNVERIFIED` | `REQUIRES_REVIEW` conforme criticidade |

Associação só fica completa após verificação equivalente ao `finalize`: objeto real, parent, tenant, action técnica, tamanho, MIME e integridade. Signed URLs não são migradas.

## 25. Null e default

### 25.1 Estados semânticos

| Estado | Significado |
| --- | --- |
| `UNKNOWN` | valor existe/é necessário, mas não é conhecido ou classificável |
| `NOT_APPLICABLE` | campo não se aplica ao caso |
| `NOT_CAPTURED` | V1 não coletava ou não registrou o valor |
| `LEGACY_NULL` | null original preservado sem interpretação adicional |
| `DEFAULT_V2` | default aplicado somente a novo comportamento V2 ou por regra aprovada, nunca como fato histórico implícito |

### 25.2 Política

- `NULL` não vira string vazia, zero, `false`, “Normal”, “Operacional”, “Ativo”, primeiro tenant ou usuário técnico por conveniência.
- Defaults declarados nos SQLs V1 podem representar apenas criação técnica, não intenção do usuário; devem ser analisados.
- Campo V2 obrigatório sem fonte: derivar somente por regra `DETERMINISTIC`; caso contrário `REQUIRES_REVIEW` ou `QUARANTINE`.
- Um default V2 pode permitir ativação de configuração futura, mas deve ficar marcado como `DEFAULT_V2` e não substituir provenance.
- Null em FK opcional permanece ausência; não criar entidade artificial.

## 26. Datas e timezone

| Campo/conceito | Tratamento | Validação/ambiguidade |
| --- | --- | --- |
| `criado_em`, `atualizado_em` timestamptz | preservar instante | `updated >= created`; exceções registradas |
| `agendamento_em` | preservar instante e interpretar no fuso do tenant somente para exibição/regra aprovada | não assumir timezone de input além do tipo efetivo remoto |
| `inicio_previsto`, `fim_previsto` | preservar instantes | início ≤ fim |
| `inicio_real`, `fim_real`, `concluido_em` | preservar instantes distintos | consistência com status; não copiar um para preencher outro |
| `prazo` date | preservar data civil | fuso não deve deslocar date |
| `data_aquisicao`, `garantia_ate` | preservar datas civis | garantia anterior à aquisição sinalizada |
| `proxima_execucao` date | preservar cursor civil observado | não prova occurrence histórica |
| competência preventiva | derivar apenas de schedule + regra temporal aprovada | timezone/civil time `REQUIRES_REVIEW` |
| data sem timezone efetivo | preservar raw/parsed value | não declarar UTC; `TIMEZONE_AMBIGUOUS` |
| evento anterior ao parent | não corrigir | `TEMPORAL_INCONSISTENCY` para revisão/quarentena |

### 26.1 Estados impossíveis ou inconsistentes

| Caso detectado | Tratamento | Reason code | Disposition |
| --- | --- | --- | --- |
| Request/OS Completed sem `completed_at`/`concluido_em` e sem evento equivalente | preservar status e ausência; não criar timestamp | `INVALID_STATE` | `REQUIRES_REVIEW` |
| Request/OS Cancelled sem motivo/evidência quando exigidos | preservar lacuna; não gerar motivo genérico | `INVALID_STATE` | `REQUIRES_REVIEW` |
| OS vinculada a Request de outro tenant | não carregar o vínculo nem escolher um tenant | `TENANT_MISMATCH` | `QUARANTINE` |
| OS Preventiva sem Plano/Schedule comprovável | não fabricar Plano ou ocorrência | `BROKEN_REFERENCE` | `REQUIRES_REVIEW` |
| Asset com parent de outro tenant, inexistente ou cíclico | não carregar a relação hierárquica como válida | `ASSET_PARENT_INVALID` | `QUARANTINE` |
| histórico anterior à criação do parent | preservar timestamps originais e bloquear conversão automática | `TEMPORAL_INCONSISTENCY` | `REQUIRES_REVIEW` |
| responsável textual sem identidade inequívoca | manter valor em provenance; não criar usuário | `ACTOR_UNRESOLVED` | `REQUIRES_REVIEW` |
| autor inexistente/nulo | usar `unresolved_actor`; avaliar se o domínio pode carregar | `ACTOR_UNRESOLVED` | `CONDITIONAL` |
| código duplicado no mesmo tenant/namespace | não renumerar nem escolher vencedor | `CODE_COLLISION` | `QUARANTINE` |
| `updated_at < created_at`, fim antes do início ou aprovação antes da criação | preservar valores e impedir normalização automática | `TEMPORAL_INCONSISTENCY` | `REQUIRES_REVIEW` |
| OS concluída com `aceite_status='recusado'` e sem evento posterior coerente | não escolher status por precedência de colunas | `INVALID_STATE` | `QUARANTINE` |
| occurrence key candidata compartilhada por mais de uma OS | não deduplicar por escolha arbitrária | `OCCURRENCE_COLLISION` | `QUARANTINE` |

## 27. Autoria e cross-tenant

### 27.1 Actor resolution

| Resultado | Regra |
| --- | --- |
| `mapped_actor` | source Auth/user corresponde inequivocamente a target identity e atuação é plausível |
| `legacy_actor` | pessoa/identidade histórica preservável, mas sem identidade operacional V2 |
| `unresolved_actor` | nulo, inexistente ou ambíguo; nunca substituído por humano fictício |
| `technical_actor` | trigger, function, scheduler ou migração comprovadamente produziu o efeito |

### 27.2 Regra cross-tenant

Quando `record.tenant != actor.current_tenant`, o futuro mapper deve avaliar tenant do ator à época, memberships, origem técnica/plataforma, parent, timestamp e evidências. O tenant atual do ator não reescreve o passado.

| Caso | Disposition |
| --- | --- |
| membership histórica comprova atuação no tenant do registro | `CONDITIONAL`, preservar evidence |
| ação técnica comprovada | `technical_actor`, `CONDITIONAL` |
| identidade de plataforma aprovada e target auditável | platform provenance, `CONDITIONAL` |
| apenas tenant atual diverge, sem histórico | `REQUIRES_REVIEW` |
| ator/tenant incompatível e relação influencia segurança | `QUARANTINE` |
| `criado_por` nulo | `unresolved_actor`; carga depende do domínio, sem inventar |

## 28. Provenance registry

Requisitos mínimos:

- `migration_run_id` e identidade do snapshot;
- `source_system`, `source_entity`, `source_id`, `source_tenant`;
- `target_entity`, `target_id` e target tenant;
- `mapping_rule` e versão;
- `disposition`, `confidence`, status e resolução;
- timestamps de descoberta, mapping, load e resolução;
- evidência/referência e checksum do payload quando aplicável;
- actor técnico da execução;
- reason code de falha/quarentena;
- cardinalidade/role para mappings `SPLIT` e `MERGE`;
- códigos humanos de origem/destino;
- lote/onda, correlation ID e resultado idempotente.

Consultas devem responder V1 → V2 e V2 → V1. O registry não concede autorização e não substitui tabelas de negócio. Dados pessoais e payloads integrais devem ser minimizados; evidência pode ser referenciada em vez de duplicada.

## 29. Quarantine

### 29.1 Registro conceitual

Cada item contém: source system/entity/id/tenant, snapshot/run, raw ou referência ao payload relevante, hash quando aplicável, reason code, categoria, severidade, status, evidência, resolução, `resolved_by`, `resolved_at`, target reference, regra/versão e impacto em registro/onda/cutover.

Status: `OPEN`, `UNDER_REVIEW`, `RESOLVED_MAP`, `RESOLVED_LEGACY_ONLY`, `APPROVED_DISCARD`, `BLOCKED`.

### 29.2 Taxonomia preliminar

| Reason code | Categoria | Severidade padrão |
| --- | --- | --- |
| `TENANT_UNKNOWN` | tenant | Critical |
| `TENANT_MISMATCH` | tenant/relação | Critical |
| `AUTH_MAPPING_UNRESOLVED` | identidade | Critical quando acesso/ator obrigatório |
| `ACTOR_UNRESOLVED` | autoria | High, ajustável por domínio |
| `PLATFORM_AUTHORITY_UNRESOLVED` | Global Admin | Critical |
| `PERMISSION_AMBIGUOUS` | autorização | Critical |
| `SCOPE_UNKNOWN` | autorização | Critical para ativação |
| `TARGET_UNKNOWN` | classificação | High |
| `AMBIGUOUS_CLASSIFICATION` | domínio | High |
| `CODE_COLLISION` | códigos | Critical |
| `COUNTER_INCONSISTENT` | códigos | High |
| `BROKEN_REFERENCE` | relação | Critical/High |
| `CARDINALITY_VIOLATION` | relação | Critical |
| `INVALID_STATE` | status | High/Critical |
| `TEMPORAL_INCONSISTENCY` | datas | High |
| `TIMEZONE_AMBIGUOUS` | datas | High para ocorrência |
| `REQUEST_TYPE_UNKNOWN` | Request | High |
| `OS_ACTOR_ROLE_AMBIGUOUS` | OS | High |
| `OCCURRENCE_COLLISION` | preventiva | Critical |
| `ASSET_PARENT_INVALID` | Ativo | High/Critical |
| `CHECKLIST_INCOMPLETE_LEGACY` | checklist | Medium/High |
| `STORAGE_ORPHAN` | Storage | High |
| `STORAGE_METADATA_MISSING` | Storage | High |
| `STORAGE_OBJECT_MISSING` | Storage | Critical conforme evidência |
| `STORAGE_PARENT_UNRESOLVED` | Storage | Critical |
| `STORAGE_PATH_INVALID` | Storage | High |
| `STORAGE_MIME_UNSUPPORTED` | Storage | High |
| `INTEGRITY_UNVERIFIED` | Storage | High |

Resolução exige evidência, ator autorizado e rastreabilidade. Alterar o payload original é proibido; a resolução cria uma decisão ao lado dele.

## 30. Relações

| Relação V1 | Relação V2 | Tenant invariant | Cardinalidade V1 conhecida | Cardinalidade V2 | Regra | Falha |
| --- | --- | --- | --- | --- | --- | --- |
| `organizacoes → perfis` | Tenant → Membership/Application User | IDs mapeados; usuário comum em um tenant | 1:N, org opcional | 1:N; membership única por usuário comum | map após Auth/tenant | null/múltipla → review/quarantine |
| `demandas.criado_por → auth.users` | Request → requester/creator | actor autorizado ou legado; record tenant preservado | 0..1 | conforme campos conceituais | split somente se semântica confirmada | unresolved actor |
| `demandas.responsavel` texto | Request → responsible | mesmo tenant | texto 0..1 | 0..1 | match forte/aprovado | review; não fuzzy match |
| Request → Asset | não comprovada localmente | mesmo tenant | UNKNOWN | 0..1 | revalidar schema remoto | `REVALIDATION_REQUIRED` |
| `demandas → ordens_servico` | Request → Work Orders | mesmo tenant | 1:N pela FK em OS | 1:0..N | registry resolve | broken/cross-tenant quarantine |
| `ordens_servico.executor_id` | OS → Executors | mesmo tenant/membership | 0..1 | 0..N | map executor conhecido | unresolved/review |
| executor legado → responsável | OS → Responsible | mesmo tenant | não comprovada | 0..1 | apenas evidência explícita | `OS_ACTOR_ROLE_AMBIGUOUS` |
| `ordens_servico.ativo_id` | OS → Asset | mesmo tenant | 0..1 | 0..1 | registry resolve | broken/cross-tenant quarantine |
| `ordens_servico.prestador_id` | OS → Supplier | mesmo tenant | 0..1 | 0..1 ou modelo futuro aprovado | registry resolve | broken/cross-tenant quarantine |
| `ordens_servico.plano_manutencao_id` | OS → Plan/Schedule/Occurrence | mesmo tenant | 0..1 | relações separadas | split após occurrence mapping | collision/broken reference |
| `planos_manutencao.ativo_id` | Plan → Asset | mesmo tenant | 1 | 1 | registry resolve | quarantine |
| `ativos.ativo_pai_id` | Asset → Parent | mesmo tenant e acíclico | 0..1 | 0..1 | graph validation | `ASSET_PARENT_INVALID` |
| Asset ↔ Supplier | relação direta não comprovada | mesmo tenant | UNKNOWN | N:M conforme V2 | não inferir de OS/Plano | revalidation/review |
| Entity → metadata file | Parent → Files | mesmo tenant | 1:N | 1:N | parent mapping before association | orphan quarantine |
| metadata → Storage object | File metadata → Object | mesmo tenant/contexto | 1:0..1 esperado | 1:1 association | verify object facts | missing/orphan quarantine |
| Entity → history | Parent → Operational History | tenant do pai | 1:N | 1:N | parent mapping and actor resolution | orphan/duplicate review |
| `usuario_operacoes` | User → Team/Setor/Local/CC | mesmo tenant | N:M | depende da classificação | operation mapping first | ambiguous classification |

## 31. Reconciliação

### 31.1 Equação comum

Para cada `snapshot + tenant + source entity + rule version`:

```text
source_count
= eligible_count
+ ineligible_out_of_scope_count

eligible_count
= migrated_count
+ quarantined_count
+ legacy_only_count
+ approved_discard_count
+ failed_count
```

`failed_count` deve chegar a zero ou ser convertido em quarentena/resolução antes do encerramento. `DISCARD_CANDIDATE` não integra `approved_discard_count` sem aprovação formal.

### 31.2 Invariantes por domínio

| Domínio | Reconciliação específica |
| --- | --- |
| Tenants | cada source tenant tem um target ou decisão bloqueante explícita; counts por status |
| Auth/users | Auth sem perfil, perfil sem Auth, mapping 1:1, memberships por usuário, statuses |
| Permissions | linhas por papel/ação/tenant; grants mapeados, revisados e deliberadamente não concedidos |
| Cadastros | counts por tenant/tipo; operações distribuídas entre destinos + legacy/quarantine |
| Codes | conjunto de códigos emitidos preservado; duplicidades explicadas; next safe comprovado |
| Requests | counts por tenant/tipo/status/prioridade; preventivas retiradas por classificação explícita |
| OS | counts por tenant/origem/tipo/status; avulsas/vinculadas; atores e dependentes |
| Request × OS | número de vínculos, OS por Request, broken/cross-tenant; nenhuma Request artificial |
| Preventiva | Planos, Schedules, occurrences, OS preventivas; occurrence key única |
| Assets | counts/status, códigos, raízes/filhos; zero ciclos/cross-tenant ativos |
| Suppliers | counts PF/PJ/status; contatos/especialidades; merges somente aprovados |
| Checklist | modelos/versões/instâncias/respostas/evidências ou legacy-only explícito |
| History | eventos por parent, tipo e actor resolution; órfãos/duplicidades |
| Notifications | preservadas/legacy/discard candidate; destinatários/targets válidos |
| Storage | metadata expected × object found × migrated × associated; bytes/checksums por tenant |

Counts globais nunca mascaram divergência entre tenants. Cada exceção precisa de source identity e reason code.

## 32. Ordem de transformação

### 32.1 Fases

| Fase | Objetivo | Não faz |
| --- | --- | --- |
| `PREPARE` | snapshot, manifesto, regras, registry, quarantine, ambientes e gates | não classifica por fallback |
| `MAP` | resolve source → target IDs, enums, atores, relações e dispositions | não ativa dados |
| `LOAD` | materializa em ordem de dependência e de forma idempotente | não ignora falhas |
| `RECONCILE` | prova counts, invariants, relações, códigos e objetos | não corrige silenciosamente |
| `ACTIVATE` | torna dados disponíveis após autorização/go-no-go | não ocorre com blockers críticos |

### 32.2 Dependências concretas

```text
PREPARE snapshot/manifest + rule versions
→ PREPARE registry/quarantine/reconciliation contracts

MAP tenant
→ MAP Auth identity
→ MAP application user + membership
→ MAP profile baseline/capabilities + teams

MAP structural catalogs
→ MAP Assets + Suppliers
→ MAP Requests + Plans/Schedules
→ MAP Work Orders + occurrences
→ MAP dependent costs/materials/checklists
→ MAP history/actors
→ MAP file metadata
→ MAP Storage objects

LOAD segue a mesma ordem de pais antes de filhos
→ RECONCILE a cada onda
→ ACTIVATE somente após gates de segurança e domínio
```

Mappings obrigatórios prévios:

- tenant antes de qualquer linha tenant-owned;
- Auth antes de actor resolution;
- tenant + Auth antes de membership;
- membership/Profile/Equipe antes de capability/scope;
- catálogo antes de relações categóricas;
- Asset/Supplier/Request/Plan antes de OS;
- Request antes da FK de OS vinculada;
- Schedule antes da occurrence;
- parent entity antes de history/file association;
- metadata/parent antes do finalize do objeto;
- todos os códigos emitidos/deltas antes do próximo counter;
- fontes operacionais antes de projeções `REGENERATE`.

## 33. Revalidações necessárias

Tudo abaixo é `REVALIDATION_REQUIRED` antes da 10C fechar regras de carga ou antes do cutover, conforme indicado:

- schema remoto completo e drift em relação aos 18 SQLs;
- ordem/êxito dos scripts, constraints e índices efetivos;
- dados/volumes por tabela, tenant, enum, ano e status;
- Auth identities, providers, estados, e-mails e perfis correspondentes;
- memberships reais, perfis com tenant nulo e usuários potencialmente multi-tenant;
- candidatos a Global Admin e autoridades aprovadas;
- conteúdo completo de `permissoes_perfis`, grants/bypasses e scopes observáveis;
- RLS/policies vigentes por operação;
- functions/RPCs, `SECURITY DEFINER`, owners, search paths e grants;
- triggers ativos e writers reais de histórico/notificação;
- `operacoes`, `usuario_operacoes`, `loja`, localização e CC em uso;
- todos os valores distintos de tipo, natureza, prioridade e status;
- códigos emitidos, duplicados, counters e sequences por namespace;
- Requests/OS, cardinalidade, relações órfãs/cross-tenant e autoria;
- Planos, OS preventivas, datas/competências e possíveis duplicates;
- Assets, pais, ciclos, códigos, categorias e localizações;
- Suppliers, documentos, duplicidades candidatas, contatos e especialidades;
- checklists ou estruturas adicionais não documentadas;
- comentários/notificações e sua relevância/retenção;
- buckets, policies, objetos, sizes, MIME, checksum, metadata e órfãos;
- Edge Function publicada, versão e comportamento, sem registrar secrets;
- timezone efetivo por tenant e semântica de datas civis;
- alterações/deltas posteriores ao snapshot inicial.

## 34. Blockers para 10C

### 34.1 `DESIGN_BLOCKER`

- formato físico e invariantes do registry/quarantine ainda não aprovados;
- matriz técnica V2 de Resource + Action + Scope indisponível;
- dicionários de enums/taxonomias sem versão/owner;
- política de identidade Auth e actor placeholders não definida;
- estratégia de código/counter e aliases não aprovada;
- regra de occurrence key/timezone preventiva não definida;
- protocolo de Storage migration/finalize e integridade não definido;
- equações/tolerâncias de reconciliação e critérios de falha não aprovados;
- estratégia de snapshot/delta/idempotência/rollback não especificada.

### 34.2 `DATA_BLOCKER`

- tenant mapping não resolvido;
- Auth/perfil/membership incompatível ou Global Admin ambíguo;
- permissão/scope sem correspondência segura;
- operação/loja usada em relação crítica sem classificação;
- código duplicado no mesmo namespace/tenant;
- Request/OS/Plano/Asset/Supplier com parent quebrado ou cross-tenant;
- executor versus responsável necessário e não resolvido;
- status/tipo obrigatório desconhecido;
- occurrence preventiva duplicada;
- arquivo crítico ausente, corrompido ou sem parent/tenant;
- campo V2 obrigatório sem regra determinística ou decisão humana.

### 34.3 `CUTOVER_BLOCKER`

- falha de RLS, FK tenant-aware, antiescalada ou Storage authorization;
- counts/reconciliação críticos divergentes;
- `failed_count > 0` fora de quarentena controlada;
- código/counter pode reutilizar número;
- snapshot/delta perde escrita da janela;
- migrations/ETL não são reproduzíveis e idempotentes;
- Auth/membership/capabilities não passam smoke/security tests;
- rollback/roll-forward/recuperação não ensaiados;
- quarentena `BLOCKED` de impacto cutover aberta;
- provenance/auditoria técnica obrigatória ausente.

Nem todo `DATA_BLOCKER` precisa ser resolvido na 10B, pois muitos dependem do snapshot remoto. A 10C, porém, não pode implementar fallback silencioso para contorná-los.

## 35. Decisões deferidas

- schema físico, storage engine e retenção do registry/quarantine;
- runtime/ferramenta de ETL, formato do manifesto e estratégia de staging;
- preservar ou remapear cada UUID Auth após inspeção remota;
- dicionário final de papéis/capabilities/scopes e overrides;
- destino de cada operação/loja e membership correspondente;
- precedência entre `codigo` e `codigo_solicitacao` como código operacional;
- política para entidades históricas sem código;
- dicionários finais de status/tipos/naturezas/categorias/especialidades/UOM;
- regra para OS `Pausada` sem pausa estruturada e `Cancelada` sem motivo;
- configuração histórica de validação e interpretação de `aceite_status`;
- responsável de Request/OS quando apenas texto/executor existe;
- forma física de Plan/Schedule/Occurrence e competência/timezone;
- política de campos JSON de Ativo;
- retenção de notificações, legacy-only e discard candidates;
- quantidade/buckets de destino, checksums e deduplicação física;
- tolerâncias de reconciliação, janela de delta e thresholds Serena;
- providers de worker/observabilidade/hosting e retenções legais.

Nenhuma decisão deferida permite contrariar arquitetura `CLOSED`, inventar dados ou reduzir isolamento/rastreabilidade.

## 36. Conclusão

### 36.1 Resultado da revisão adversarial

O documento foi revisado contra os riscos mandatórios. Não permanece regra que, por si só:

- invente informação, tenant, ator humano, status, relação, motivo ou timestamp;
- amplie privilégio por nome aproximado ou bypass legado;
- renumere código, compacte gap ou resolva colisão silenciosamente;
- converta histórica indiscriminadamente em Audit ou comentário;
- associe Storage sem parent, tenant e objeto verificados;
- transforme `NULL` em default de negócio arbitrário;
- mantenha preventiva como Request;
- trate executor como responsável sem evidência;
- derive Global Admin de administrador tenant;
- deixe registro elegível fora da equação de reconciliação.

Mappings condicionais declaram o predicado verificável e o tratamento da falha. Casos ainda dependentes de snapshot ou decisão estão marcados como `REVALIDATION_REQUIRED`, `REQUIRES_REVIEW` ou `QUARANTINE`, sem fallback permissivo.

O mapeamento detalhado confirma que poucos valores isolados são completamente determinísticos; a maior parte das entidades é migrável por regras condicionais após resolver tenant, identidade, relações e vocabulários. As principais revisões concentram-se em operações/lojas, scopes de permissões, códigos de Request, tipos/status legados, executor versus responsável, validação de OS, preventiva, taxonomias e Storage.

Registros cross-tenant, relações quebradas, collisions de códigos/ocorrências, identidade crítica não resolvida e objetos sem parent/tenant são candidatos claros a quarentena. Históricos não viram automaticamente auditoria ou comentários; preventiva não permanece como Request; administrador tenant não vira Global Admin; nulls não recebem defaults arbitrários.

A Etapa 10C poderá desenhar migrations e ETL somente depois de materializar as decisões e revalidações classificadas como blockers de design/dados. Nenhuma transformação, carga, acesso remoto ou alteração de sistema foi executada nesta etapa.
