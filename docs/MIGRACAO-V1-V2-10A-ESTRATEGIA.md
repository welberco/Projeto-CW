# Estratégia e Inventário da Migração V1 → V2 — Etapa 10A

| Campo | Valor |
| --- | --- |
| Projeto | CW ERP / CW Manutenção |
| Etapa | Fase A — Etapa 10A |
| Natureza | Estratégia e inventário documental de alto nível |
| Origem | V1 preservada em `v1-legacy` e estado legado conhecido |
| Destino | Arquitetura Técnica Oficial CW ERP V2 |
| Status | Estratégia proposta; sem execução de migração |
| Restrição | Sem acesso remoto, SQL, migration, ETL, Storage, Auth ou produção |

## 1. Objetivo

Definir a estratégia controlada de migração dos dados e vínculos conhecidos da V1 para a V2, estabelecendo classificação, dependências, ordem lógica, tratamento de ambiguidades, proveniência, reconciliação, revalidações e critérios de bloqueio.

Este documento não executa nem especifica em nível implementável a migração. Ele prepara as Etapas 10B, 10C e 10D sem reabrir decisões `CLOSED` da arquitetura congelada.

O resultado esperado é que cada conjunto legado possa ser encaminhado, com evidência, para um destes tratamentos: migração direta, transformação, separação, consolidação, reclassificação, retenção apenas como legado, quarentena, eventual descarte sujeito a aprovação ou regeneração determinística.

## 2. Escopo

Incluído nesta etapa:

- inventário conceitual dos domínios e artefatos V1 já documentados;
- classificação preliminar de migração por domínio;
- dependências entre identidades, tenants, cadastros e registros operacionais;
- estratégias de Auth, tenant, permissões, códigos, Solicitações, OS, preventiva, histórico, auditoria e Storage;
- tratamento conceitual de autoria incompatível, dados cross-tenant, registros órfãos e ambiguidades;
- conceito de quarentena e requisitos de proveniência;
- ordem lógica em ondas, gates e condições de bloqueio;
- métricas de reconciliação;
- revalidações obrigatórias antes do cutover;
- entregáveis esperados das Etapas 10B, 10C e 10D.

Fora do escopo:

- acesso ou validação de qualquer ambiente remoto;
- decisão definitiva baseada em dados que não constam das fontes versionadas;
- criação de schema físico, migrations, SQL, scripts ETL, tabelas de staging, RPCs, policies, buckets, usuários ou fixtures;
- transformação, correção, exclusão ou movimentação de dados;
- deploy, cutover, rollback real ou alteração de produção;
- implementação de funcionalidade V2, inclusive itens complementares ou futuros.

## 3. Fontes e precedência

Foram utilizadas integralmente as seguintes fontes versionadas:

1. `PRODUCT_SPEC.md`: autoridade funcional, de escopo e de regras de negócio;
2. `docs/ARQUITETURA-TECNICA-V2.md`: autoridade técnica congelada para o destino V2;
3. `docs/INVENTARIO-V1.md`: autoridade para o estado legado conhecido no repositório;
4. `docs/GAP-ANALYSIS-V1-V2.md`: apoio de comparação e classificação preliminar;
5. `AGENTS.md`: regras de trabalho, segurança, escopo e governança do repositório.

Precedência aplicada:

- a arquitetura congelada prevalece sobre o GAP quando houver divergência técnica;
- o `PRODUCT_SPEC.md` permanece a fonte funcional oficial;
- o inventário descreve apenas evidências versionadas e não comprova o estado remoto;
- qualquer conflito entre regra funcional e decisão `CLOSED` deve seguir change control, nunca interpretação silenciosa;
- nenhuma ausência de evidência será preenchida por suposição.

Há uma delimitação já registrada na arquitetura: e-mail operacional de eventos de domínio é futuro no MVP, enquanto e-mails transacionais de Auth permanecem aplicáveis. Esta estratégia respeita esse fechamento.

## 4. Princípios da migração

O processo conceitual é:

```text
V1 existente
→ snapshot e inventário revalidado
→ classificação
→ mapeamento explícito
→ transformação validável
→ staging/modelo intermediário
→ carga em ordem de dependência
→ validação
→ reconciliação
→ cutover controlado
→ verificação
→ estabilização
```

Princípios obrigatórios:

1. Não assumir atualização in-place direta.
2. Não assumir correspondência 1:1 entre tabelas V1 e entidades V2.
3. Não assumir que todo dado legado é correto, completo, autorizado ou necessário.
4. Não corrigir silenciosamente valores, vínculos, autoria, tenant, códigos ou status.
5. Preservar o registro original e a evidência usada em toda decisão relevante.
6. Preservar códigos humanos já emitidos; não reutilizar nem renumerar histórico.
7. Separar identidade Auth, usuário de aplicação, membership tenant e autoridade de plataforma.
8. Aplicar menor privilégio a permissões sem correspondência inequívoca.
9. Tratar RLS como enforcement obrigatório, sem confundi-la com integridade referencial tenant-aware.
10. Provar coerência tenant, autorização, proveniência e reconciliação antes do cutover.
11. Não inventar ator humano para registros sem autoria.
12. Não promover estrutura técnica, cache ou dado derivável quando puder ser regenerado com segurança.
13. Não descartar nenhum dado nesta etapa; `DISCARD_CANDIDATE` exige decisão posterior documentada.
14. Não criar infraestrutura de itens classificados como V2 Complementar ou Futuro apenas para acomodar legado.
15. Cada onda deve possuir critérios de entrada, saída, reconciliação e recuperação antes de avançar.

## 5. Estado conhecido da V1

### 5.1 Fundação técnica

A V1 é uma SPA estática em HTML, CSS e JavaScript global, integrada diretamente ao Supabase Auth, PostgreSQL/PostgREST, RLS, RPCs, Storage e uma Edge Function administrativa. Há 18 arquivos SQL incrementais fora do formato convencional de migrations, sem cadeia remota comprovada.

O modelo conhecido parte de `organizacoes` como tenant e de `perfis` como extensão de `auth.users`. Registros de negócio carregam `organizacao_id`, mas as relações tenant-owned não possuem garantia composta uniforme de que pai e filho pertençam ao mesmo tenant.

### 5.2 Identidade e autorização

Há Auth, sessão, recuperação/troca de senha, perfis, aprovação, ativação/bloqueio, criação/edição administrativa e uma matriz legada por papel/empreendimento. A V1 mistura papéis e ações de gerações diferentes, contexto tenant e possíveis funções administrativas globais.

O estado versionado não comprova a correspondência exata entre identidades Auth, perfis, tenant atual, memberships e a futura identidade de plataforma. Também não comprova o estado remoto de grants, functions privilegiadas ou versão publicada da Edge Function `admin-users`.

### 5.3 Operação

- `demandas` concentra Solicitações legadas, códigos, tipos/naturezas, prioridade, responsável, status, prazo, agendamento, centro de custo, operação, anexos e histórico;
- `ordens_servico` admite criação manual ou vinculada, referências opcionais a solicitação, ativo, prestador e plano, além de custos, materiais, arquivos e histórico;
- `planos_manutencao` representa parcialmente preventiva, periodicidade, próxima execução e geração de OS;
- `ativos` possui código, dados técnicos, hierarquia opcional e arquivos;
- `prestadores` possui PF/PJ, contatos, especialidades, documentos e vínculos operacionais;
- `operacoes`, `usuario_operacoes`, `prioridades`, `naturezas_servico`, `tipos_servico` e `centros_custo` compõem cadastros auxiliares de semântica desigual;
- não há implementação completa conhecida de Locais, Setores, Equipes, Tags, Unidades, motivos estruturados ou modelos/snapshots completos de checklist.

### 5.4 Histórico, mídia e dados secundários

`historico_demandas` é preenchido por triggers e exibido na V1. `historico_ordens_servico` existe, mas seu fluxo ponta a ponta não está comprovado. Não há auditoria central com semântica V2. Comentários separados do histórico não foram encontrados.

Há metadados e objetos associados aos buckets conhecidos `cw-anexos`, `cw-logos` e `cw-arquivos`. A privacidade, policies vigentes, integridade metadado × objeto, ownership e total de objetos remotos não estão comprovados. `notificacoes` existe como estrutura parcial, sem fluxo operacional completo comprovado.

### 5.5 Incerteza fundamental

Todo o estado acima é o estado legado **conhecido pelo repositório**, não um snapshot autoritativo do ambiente em operação.

**REVALIDAÇÃO NECESSÁRIA ANTES DO CUTOVER:** schema, dados, volumes, Auth, Storage, RLS, grants, functions, triggers, sequences, buckets, Edge Functions e drift desde a data do inventário.

## 6. Classificação de migração

| Classe | Definição | Regra de uso |
| --- | --- | --- |
| `DIRECT_MAP` | Destino claro e transformação mínima | Somente após validar tenant, integridade, código e autoria |
| `TRANSFORM` | Destino claro, com mudança estrutural ou semântica | Exige regra explícita, teste e reconciliação |
| `SPLIT` | Uma entidade/linha V1 alimenta múltiplas entidades V2 | Exige cardinalidade e vínculo de proveniência por destino |
| `MERGE` | Múltiplos conceitos/fontes V1 alimentam uma entidade V2 | Exige regra de precedência e detecção de duplicidade |
| `RECLASSIFY` | O dado permanece, mas muda de categoria ou significado | Exige dicionário aprovado e confiança registrada |
| `LEGACY_ONLY` | Preservado para histórico/proveniência, sem função operacional V2 | Não concede capacidade nem participa do fluxo atual |
| `QUARANTINE` | Inconsistente, ambíguo, inseguro ou sem decisão suficiente | Não entra no modelo operacional até resolução explícita |
| `DISCARD_CANDIDATE` | Pode ser desnecessário no destino | Não implica exclusão; exige prova, retenção e aprovação |
| `REGENERATE` | Pode ser reconstruído deterministicamente | Não copiar se a geração for comprovada e reconciliável |

A classificação é por registro ou subconjunto quando um domínio contém casos distintos. Um domínio marcado `TRANSFORM` pode conter registros `QUARANTINE`, por exemplo.

Estados auxiliares para mapeamento futuro:

- `UNKNOWN`: não há evidência suficiente para propor destino;
- `REQUIRES_REVIEW`: há destinos plausíveis, mas a decisão exige revisão de negócio, segurança ou dados;
- `CONFIDENCE`: nível de confiança da regra, a ser formalizado em 10B;
- `BLOCKING`: indica se a pendência impede a onda ou o cutover.

## 7. Inventário e matriz por domínio

| Domínio V1 | Situação V1 | Destino conceitual V2 | Classe de migração | Risco | Dependências | Revalidação | Etapa detalhada |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `organizacoes` | Tenant conhecido, dados básicos e logo | Empreendimento/tenant | `DIRECT_MAP` + `TRANSFORM` | Alto: status e identidade podem divergir | snapshot, códigos, Auth | Sim: existência, volume, duplicidade e situação | 10B/10C |
| Unidades internas | Operações/lojas podem representar conceitos distintos | Local, Centro de Custo, Setor, outro ou legado | `RECLASSIFY` / `QUARANTINE` | Crítico: criar tenant ou vínculo estrutural errado | tenant, entrevistas/evidência | Sim: significado por tenant e uso real | 10B |
| Supabase Auth | UUIDs e e-mails remotos não inventariados nesta etapa | Identidade Auth | `DIRECT_MAP` ou `TRANSFORM` | Crítico: perda de acesso ou associação falsa | snapshot Auth, perfis | Sim: UUID, e-mail, providers, estado | 10B/10C |
| `perfis` como usuário de aplicação | Extensão de Auth, papel, status e organização opcional | Application user/profile | `SPLIT` + `TRANSFORM` | Crítico: identidade, tenant e plataforma misturados | Auth, tenant, memberships | Sim: nulos, duplicados, status e tenant | 10B |
| Vínculo usuário × organização | Predominantemente em `perfis.organizacao_id`; operações adicionais existem | Membership tenant único para usuário comum | `TRANSFORM` / `MERGE` | Crítico: membership ausente ou múltiplo | Auth, perfis, organizações | Sim: cardinalidade e conflitos | 10B/10C |
| Global Admin legado | Possivelmente misturado a papéis/identidade tenant | Platform identity/capabilities | `SPLIT` / `QUARANTINE` | Crítico: escalada de privilégio | Auth, evidência administrativa | Sim: lista nominal e autoridade aprovada | 10B |
| Perfis/papéis | Papéis legados de gerações distintas | Profile baseline | `RECLASSIFY` + `TRANSFORM` | Alto: semântica não equivalente | catálogo V2 de capabilities | Sim: nomes e uso efetivo | 10B |
| `permissoes_perfis` | Ações por papel/empreendimento, sem scopes uniformes | Resource + Action + Scope baseline/override | `SPLIT` + `RECLASSIFY` | Crítico: privilégio por aproximação | perfis, memberships, matriz V2 | Sim: cada permissão e grant efetivo | 10B |
| `usuario_operacoes` | Escopo operacional legado | Membership de Equipe/Local ou legado | `RECLASSIFY` / `QUARANTINE` | Alto: “operação” é ambígua | classificação de operações | Sim: finalidade e consultas atuais | 10B |
| `cw_sequencias` | Counters por organização/entidade/período | Allocator/counters V2 | `TRANSFORM` + `REGENERATE` | Crítico: colisão ou reutilização | códigos emitidos, tenant, ano | Sim: máximos, gaps, duplicados | 10B/10C |
| Códigos de Empreendimento | Identificador estável não comprovado | Código humano + UUID interno | `TRANSFORM` | Alto | tenant mapping | Sim: unicidade e formato | 10B |
| `demandas` | Solicitação legada ampliada, nomenclaturas e status mistos | Request/Solicitação V2 | `TRANSFORM` + `RECLASSIFY` | Crítico: semântica e relações | tenant, cadastros, usuários | Sim: tipos, status, autoria e vínculos | 10B/10C |
| Demandas de preventiva | Possível tipo legado incompatível | Plano/Programação/OS ou legado | `SPLIT` / `RECLASSIFY` / `QUARANTINE` | Crítico: preventiva não é Solicitação | evidência por registro | Sim: origem e execução real | 10B |
| Agendamentos em demandas | Campos temporais dentro de demanda | Solicitação tipo Agendamento e projeção de Calendário | `TRANSFORM` / `RECLASSIFY` | Alto: status específico e fornecedor/equipe | Request, cadastros | Sim: aprovação, datas, origem | 10B |
| `ordens_servico` | OS parcial com executor único e referências opcionais | OS V2 | `TRANSFORM` + `SPLIT` | Crítico: status, atores e transições | Requests, usuários, Ativos, Fornecedores | Sim: estado, origem, autoria e vínculos | 10B/10C |
| Executor/responsável de OS | Possível campo único ou papel sobreposto | Responsável + múltiplos executores | `SPLIT` / `QUARANTINE` | Crítico: atribuição histórica falsa | usuários, evidência de execução | Sim: semântica por campo/registro | 10B |
| Custos de OS | Tabelas/estruturas parciais | Custos estimados/reais V2 | `TRANSFORM` | Médio/alto: unidade, moeda e duplicidade | OS, tenant | Sim: valores e referências | 10B/10C |
| Materiais de OS | Estrutura parcial | Materiais usados/planejados | `TRANSFORM` / `QUARANTINE` | Alto: UOM e significado incompletos | OS, unidades mínimas | Sim: writer e uso real | 10B |
| Aceite/recusa de OS | Fluxo RPC parcial | Validação/aprovação/devolução motivada | `RECLASSIFY` + `TRANSFORM` | Crítico: ciclos e autoria podem faltar | OS, histórico, usuários | Sim: eventos e estados reais | 10B |
| `planos_manutencao` | Plano e programação parcialmente sobrepostos | Plano + Programação | `SPLIT` + `TRANSFORM` | Crítico: ocorrência e cursor não explícitos | Ativos, OS, códigos | Sim: periodicidade, próxima execução e geração | 10B/10C |
| OS preventiva gerada | Geração parcial sem occurrence key V2 comprovada | Ocorrência + OS Preventiva | `RECLASSIFY` + `TRANSFORM` | Crítico: duplicidade de ocorrência | Plano, Programação, OS | Sim: vínculo e competência canônica | 10B |
| Checklists parciais | Modelo/snapshot completo não comprovado | Modelo, instância, respostas e snapshot | `TRANSFORM` / `QUARANTINE` | Alto: evidência histórica incompleta | Plano, OS, categorias | Sim: estruturas e conteúdo remoto | 10B |
| `ativos` | Cadastro técnico, código `EQP-*`, pai opcional e JSON | Ativo estrutural V2 | `TRANSFORM` | Crítico: código, tenant, hierarquia e local | tenant, locais, CC | Sim: ciclos, duplicidade e relações | 10B/10C |
| Especificações de ativo | JSON flexível/textos | Características validadas quando consultáveis | `TRANSFORM` / `LEGACY_ONLY` | Médio: schema heterogêneo | tipo/categoria de Ativo | Sim: chaves e unidades usadas | 10B |
| `prestadores` | PF/PJ, contato, especialidades e documentos | Fornecedor canônico | `TRANSFORM` + `SPLIT` | Alto: contato e tipos múltiplos | tenant, categorias, arquivos | Sim: documentos, status e duplicidade | 10B/10C |
| Contatos de prestador | Possível contato único embutido | Contatos de Fornecedor | `SPLIT` | Alto: não virar usuário Auth | Fornecedor | Sim: finalidade e dados válidos | 10B |
| Especialidades textuais | Texto ou estrutura não canônica | Especialidades/taxonomia associada | `RECLASSIFY` / `QUARANTINE` | Alto: correspondência semântica | categorias | Sim: vocabulário por tenant | 10B |
| `operacoes`/lojas | Cadastro polivalente | `REQUIRES_REVIEW` | `RECLASSIFY` / `QUARANTINE` | Crítico | tenant, locais, setores, CC | Sim: obrigatório por registro/grupo | 10B |
| `centros_custo` | Cadastro básico | Centro de Custo independente de Local | `TRANSFORM` | Alto: códigos/status/hierarquia | tenant | Sim: unicidade e referências | 10B/10C |
| Localização textual | Campos em demandas/ativos/outros | Local hierárquico ou proveniência textual | `MERGE` + `RECLASSIFY` / `QUARANTINE` | Alto: homônimos e estrutura inexistente | catálogo de Locais | Sim: normalização aprovada | 10B |
| Setores | Não encontrados como cadastro completo | Setor V2 | `UNKNOWN` / `REQUIRES_REVIEW` | Alto: não inferir de operação/equipe | usuários e operação real | Sim: fontes possíveis | 10B |
| Equipes | Não encontradas como cadastro completo | Equipe V2 | `UNKNOWN` / `REQUIRES_REVIEW` | Crítico para scope TEAM | usuários, OS, setores | Sim: composição operacional | 10B |
| Prioridades | Cadastro legado, incluindo “Média” | Prioridades oficiais | `RECLASSIFY` | Médio: “Média” pode mapear a Normal após aprovação | Requests, OS | Sim: valores e uso | 10B |
| Naturezas/tipos de serviço | Vocabulários sobrepostos | Categorias/Subcategorias e tipos oficiais | `MERGE` + `RECLASSIFY` | Alto: significado por contexto | Requests, OS, Plano | Sim: dicionário e referências | 10B |
| Motivos em texto/status | Estrutura incompleta ou embutida | Motivos de pausa/cancelamento/rejeição/devolução | `RECLASSIFY` / `LEGACY_ONLY` | Alto: texto não deve virar catálogo automaticamente | Requests, OS, histórico | Sim: frequência e significado | 10B |
| `historico_demandas` | Trigger e UI conhecidos | Histórico operacional de Solicitação | `TRANSFORM` | Alto: ator, evento e antes/depois | Requests, usuários | Sim: semântica e completude | 10B/10C |
| `historico_ordens_servico` | Estrutura/escrita parcial | Histórico operacional de OS | `TRANSFORM` / `QUARANTINE` | Alto: cobertura não comprovada | OS, usuários | Sim: writer, eventos e lacunas | 10B |
| Auditoria legada | Sem mecanismo central completo | Auditoria V2 | `LEGACY_ONLY` + `REGENERATE` somente para fatos deriváveis | Crítico: não fabricar eventos históricos | todas as entidades | Sim: fontes técnicas existentes | 10B |
| Comentários | Recurso separado não encontrado | Comentários V2 | `UNKNOWN`; textos só após revisão | Alto: observação não é comentário | Requests, OS, usuários | Sim: campos candidatos e intenção | 10B |
| `notificacoes` | Tabela/policies parciais sem fluxo comprovado | Notificação interna V2 | `TRANSFORM` / `LEGACY_ONLY` / `DISCARD_CANDIDATE` | Alto: links e acesso podem estar obsoletos | usuários, entidades, permissões | Sim: linhas, writer e relevância | 10B |
| Anexos de demanda | Metadados e galeria funcional | Metadados compartilhados de arquivo/evidência | `TRANSFORM` | Crítico: metadado × objeto e autorização | Request, Storage, usuários | Sim: counts, MIME, tamanho e objeto | 10B/10C |
| Arquivos de OS | Estrutura parcial | Arquivos/evidências de OS | `TRANSFORM` / `QUARANTINE` | Alto | OS, Storage | Sim: linhas e objetos | 10B |
| Arquivos de Ativo | Estrutura parcial | Documentos/fotos de Ativo | `TRANSFORM` / `QUARANTINE` | Alto | Ativo, Storage | Sim: linhas e objetos | 10B |
| Documentos de prestador | Estrutura parcial | Documentos de Fornecedor | `TRANSFORM` / `QUARANTINE` | Alto | Fornecedor, tipos de documento | Sim: validade, objeto e ownership | 10B |
| Logos | Bucket e edição conhecidos | Identidade visual do Empreendimento | `DIRECT_MAP` + `TRANSFORM` | Médio/alto: tenant e objeto | tenant, Storage | Sim: objeto vigente e duplicados | 10B/10C |
| Objetos `cw-anexos` | Bucket legado privado esperado | Objetos Storage V2 | `TRANSFORM` | Crítico: órfãos e policies | metadados, tenant | Sim: inventário completo | 10B/10C |
| Objetos `cw-arquivos` | Modelo multi-entidade parcial | Objetos Storage V2 | `TRANSFORM` / `QUARANTINE` | Crítico: contexto pelo path é insuficiente | metadados, entidades | Sim: paths, hashes e owners | 10B/10C |
| Objetos `cw-logos` | Logos por organização | Objetos de branding | `TRANSFORM` | Alto | tenant mapping | Sim: paths e versão ativa | 10B/10C |
| Arquivos gerais/órfãos | Existência remota desconhecida | Quarentena técnica ou descarte aprovado | `QUARANTINE` / `DISCARD_CANDIDATE` | Alto: perda de evidência ou custo | snapshot Storage | Sim: obrigatório | 10B |
| `cw_migracoes` | Marca lógica, não cadeia convencional | Migration ledger V2 separado | `LEGACY_ONLY` | Médio: não comprova schema | SQLs versionados, remoto | Sim: conteúdo e confiabilidade | 10B |
| SQLs incrementais | 18 arquivos, ordem/execução remota não comprovada | Baseline e migrations V2 reproduzíveis | `LEGACY_ONLY` como evidência | Crítico: drift | schema remoto | Sim: obrigatório | 10B |
| Functions/RPCs | Helpers e commands de gerações distintas | Commands/queries V2 dedicados | `LEGACY_ONLY`; dados de efeito podem migrar | Crítico: SECURITY DEFINER/grants | schema remoto, permissões | Sim: definições, owners e grants | 10B |
| Triggers | Histórico e regras incrementais | Triggers mínimos/commands transacionais V2 | `LEGACY_ONLY` / `REQUIRES_REVIEW` | Alto: efeitos ocultos | functions, tabelas | Sim: definições e habilitação | 10B |
| Sequences PostgreSQL | Estado remoto desconhecido; counters híbridos | Alocação atômica V2 | `TRANSFORM` / `REGENERATE` | Crítico: colisões | códigos emitidos | Sim: valores atuais e dependências | 10B/10C |
| RLS/policies | Versionadas, estado remoto não comprovado | Policies V2 por operação | `LEGACY_ONLY`; não converter automaticamente | Crítico: vazamento | modelo de permissão V2 | Sim: obrigatório | 10B/10C |
| Grants | Broad grants são risco conhecido | Menor privilégio V2 | `LEGACY_ONLY`; reconstruir | Crítico | roles, functions, policies | Sim: obrigatório | 10B/10C |
| Edge Function `admin-users` | Código versionado; deploy/config remotos desconhecidos | Commands administrativos V2 | `LEGACY_ONLY` como referência | Crítico: credencial e versão | Auth, autorização | Sim: deploy, secrets sem expô-los e comportamento | 10B |
| Dados órfãos | Não quantificados | Reassociação comprovada, legado ou quarentena | `QUARANTINE` | Crítico | domínio pai, provenance | Sim: obrigatório | 10B |
| Relações cross-tenant | Possíveis pela ausência de FKs compostas | Relações tenant-aware V2 | `QUARANTINE` até classificação | Crítico | tenant mapping, evidência | Sim: obrigatório | 10B |
| Registros sem autoria | Casos conhecidos/possíveis | `unresolved_actor`, `technical_actor` comprovado ou provenance | `TRANSFORM` / `QUARANTINE` | Alto | Auth e evidência | Sim: obrigatório | 10B |
| Autoria incompatível | `record.tenant != actor.current_tenant` possível | `mapped_actor`, `legacy_actor`, provenance ou quarantine | `RECLASSIFY` / `QUARANTINE` | Crítico | histórico de memberships/contexto | Sim: obrigatório | 10B |
| Configurações da organização | Dados básicos/logo; preferências incompletas | Configurações do Empreendimento | `TRANSFORM`; defaults V2 aprovados quando ausentes | Alto: não inferir consentimento/política | tenant, produto | Sim: valores e origem | 10B |
| Caches/localStorage | Dados locais e migração opcional conhecidos | Nenhum destino operacional automático | `DISCARD_CANDIDATE` / `LEGACY_ONLY` | Médio: fonte não autoritativa | reconciliação com banco | Sim, se ainda houver uso no cutover | 10B |
| Calendário/dashboard/relatórios derivados | Projeções ou UI centradas em demandas | Projeções V2 autorizadas | `REGENERATE` | Médio: não migrar cache/indicador | domínios carregados | Sim: fórmulas e counts | 10C/10D |

## 8. Dependências

Grafo conceitual de dados:

```text
Snapshot V1 + dicionários + decisões aprovadas
        |
        v
Tenant mapping ────────────────┐
        |                      |
        v                      v
Auth identity mapping    Catálogos estruturais
        |                (Locais, CC, Setores, Categorias)
        v                      |
Application users              |
        |                      |
        v                      |
Memberships ─→ Perfis/permissões/Equipes
        |                      |
        ├──────────────────────┤
        v                      v
     Ativos               Fornecedores
        ├──────────────┬───────┘
        v              v
   Solicitações       Planos
        |              |
        v              v
       OS ←──── Programações/ocorrências
        |
        v
Checklist / custos / materiais / comentários
        |
        v
Histórico / auditoria legada / provenance
        |
        v
Metadados de arquivo → objetos Storage
        |
        v
Notificações e projeções regeneráveis
        |
        v
Reconciliação de códigos/counters e cutover
```

Auditoria da própria migração, ledger de proveniência, quarentena e métricas de reconciliação atravessam todas as ondas. Eles devem existir conceitualmente desde o início e não podem ser adicionados somente após a carga operacional.

Dependências críticas:

- nenhum registro tenant-owned entra na V2 sem `tenant mapping` resolvido;
- nenhum ator humano é mapeado sem identidade Auth/application user comprovada;
- permissões dependem de identities, memberships, profile baseline e dicionário V2;
- scopes `TEAM` dependem de Equipes e memberships confiáveis;
- Requests, OS, Planos e Ativos dependem de cadastros classificados, sem criar catálogo por aproximação;
- OS dependem de Requests apenas quando o vínculo legado for comprovado; OS avulsa permanece válida;
- preventiva depende de Plano, Programação, ocorrência e OS identificáveis separadamente;
- históricos dependem do ID mapeado da entidade e de tratamento de ator;
- metadados de arquivo dependem da entidade pai; bytes só são considerados migrados após correspondência e verificação;
- counters finais dependem da totalidade dos códigos preservados e emitidos durante eventual convivência.

## 9. Estratégia de identidade e Auth

O modelo de migração deve separar quatro conceitos:

```text
Supabase Auth identity
≠ application user/profile
≠ tenant membership
≠ platform identity/capability
```

Estratégia:

1. Produzir snapshot revalidado de identidades Auth sem alterar Auth.
2. Comparar Auth UUID, e-mail normalizado, provider, estado e perfil de aplicação.
3. Preservar o UUID Auth quando tecnicamente seguro, único e compatível.
4. Quando a preservação não for segura ou possível, criar em 10B um mapeamento explícito `source_auth_id → target_identity_id`, com motivo e evidência; não usar e-mail sozinho como prova suficiente em caso ambíguo.
5. Separar atributos do usuário de aplicação de metadata JWT/Auth que não seja autoritativa.
6. Derivar membership somente de vínculo validado; usuário comum deve resultar em um único tenant.
7. Isolar candidatos a Global Admin para revisão nominal e aprovação; nenhum papel legado os promove automaticamente.
8. Representar ausência de autoria como `unresolved_actor`, `legacy_actor` ou `technical_actor` apenas quando houver evidência técnica; nunca criar usuário humano fictício.
9. Preservar status histórico e vínculos de registros mesmo quando o usuário estiver Bloqueado/Inativo.
10. Planejar teste de login, convite, recuperação, bloqueio, inativação e invalidade de sessão antes do cutover, sem executá-lo nesta etapa.

Blockers de identidade incluem UUID duplicado/incompatível, perfil sem Auth quando necessário, usuário comum com múltiplos tenants não resolvidos, Global Admin não classificado e registros críticos cuja autoria seja condição legal/operacional e permaneça sem tratamento aprovado.

## 10. Estratégia de tenant

`organizacoes` é a origem conceitual do Empreendimento, mas o mapeamento definitivo depende do snapshot remoto.

Regras:

- cada tenant V1 deve possuir exatamente um destino V2 ou uma decisão explícita de não entrada no cutover;
- unidades internas não podem virar tenants apenas por existirem como operação/loja;
- o mapa deve distinguir `source_tenant_id`, `target_tenant_id`, código humano, nome, status, evidência e decisão;
- registros sem tenant, com tenant inexistente ou com relações a tenants distintos entram em quarentena;
- a correção de tenant só pode ocorrer por evidência verificável, nunca pelo tenant atual do ator ou pelo valor mais frequente;
- relações carregadas na V2 devem satisfazer coerência tenant-aware no banco;
- contexto de URL, slug, payload ou metadata legada não constitui autoridade;
- status Ativo/Suspenso/Inativo e entitlements devem ser revalidados, sem inferir configuração comercial inexistente;
- Serena permanece pilot configurável, não fork de dados ou arquitetura.

## 11. Estratégia de permissões

A matriz V1 não será convertida automaticamente. A unidade de análise de 10B será:

```text
legacy permission
→ source role/profile
→ observed meaning
→ V2 resource
→ V2 action
→ V2 scope
→ baseline or exact individual override
→ confidence
→ requires_review
→ evidence
```

Regras:

- correspondência exata e bem evidenciada pode produzir candidato de baseline/override;
- nomes semelhantes não bastam para equivalência;
- bypass legado de gestor/admin não vira capability implícita;
- `DENY` e `ALLOW` V2 atuam sobre a combinação exata Resource + Action + Scope;
- scopes não são hierarquia de negação; o mapeamento deve respeitar a união definida em `AUTH-01`;
- permissão sem correspondência confiável recebe `REQUIRES_REVIEW` e, enquanto incerta, menor privilégio;
- permissões de plataforma não podem nascer de Perfil tenant;
- a carga de permissões só avança após profiles, memberships, equipes e catálogo técnico V2 estarem estabilizados;
- a reconciliação compara grants legados classificados, grants V2 resultantes, casos revisados e casos deliberadamente não migrados.

## 12. Estratégia de códigos humanos

Cada registro deve distinguir:

| Conceito | Tratamento |
| --- | --- |
| UUID interno V2 | Identidade técnica estável, independente do código humano |
| ID legado | Preservado no migration ledger/provenance |
| Código humano legado | Preservado exatamente como emitido |
| Código humano V2 | Segue regra V2; não substitui silenciosamente o legado |
| Tenant | Dimensão obrigatória de unicidade e correspondência |
| Ano/contador | Dimensão aplicável a Solicitação e OS; validada por domínio |

Regras:

- não reutilizar, reordenar ou renumerar códigos históricos;
- códigos `EQP-*` permanecem rastreáveis mesmo com o padrão V2 `AT-*`;
- detectar duplicidade por tenant e também colisões que resultariam do formato de destino;
- reservar o próximo contador V2 acima de todos os códigos válidos/importados e de qualquer código emitido durante convivência, conforme regra detalhada futura;
- gaps não são corrigidos;
- códigos inválidos, duplicados ou sem tenant são quarantined até decisão;
- o mapa V1 → V2 será um registro explícito, não inferência pelo texto do código.

## 13. Estratégia de Solicitações e OS

### 13.1 Solicitações/demandas

Cada demanda será classificada por tipo, status, significado, vínculos e evidência. O destino padrão somente existe quando o registro representa uma Solicitação segundo a V2.

- mapear tipos oficiais sem transformar Preventiva em Solicitação;
- diferenciar Manutenção Corretiva, Solicitação de Serviço, Agendamento e Inspeção/Vistoria;
- status com mudança de nome ou significado exigem dicionário em 10B;
- prioridade “Média” é candidata a “Normal”, mas exige aprovação do mapeamento;
- campos textuais de local/categoria não criam automaticamente cadastros canônicos;
- cancelamento e rejeição permanecem semanticamente distintos;
- código e vínculo a zero ou várias OS devem ser preservados;
- conclusão de OS nunca gera conclusão automática de Solicitação durante migração.

### 13.2 Ordens de Serviço

- preservar OS avulsa e vínculo opcional a no máximo uma Solicitação;
- validar a cardinalidade legada e não copiar constraint que impeça várias OS por Solicitação;
- reclassificar origem e tipo com evidência;
- mapear estados sem fabricar transições que não ocorreram;
- separar responsável e executores somente quando os campos/eventos permitirem; caso contrário, `REQUIRES_REVIEW` ou quarentena;
- múltiplos executores V2 não autorizam duplicar automaticamente o executor único legado;
- aceite/recusa legado deve ser analisado como candidato a validação/devolução, preservando evento e motivo existentes;
- custos e materiais exigem unidade, moeda, autoria e vínculo confiáveis;
- nenhum histórico ausente será reconstruído como se fosse evento observado.

Casos em que a relação Request/OS cruza tenant, aponta para pai inexistente, viola cardinalidade ou possui origem contraditória bloqueiam a carga daquele registro e podem bloquear o cutover conforme criticidade/volume.

## 14. Estratégia de preventiva

A V2 exige identidades distintas:

```text
Plano → Programação → ocorrência → OS Preventiva → Execução
```

A V1 não comprova essa separação completa. Portanto:

- `planos_manutencao` é candidato a `SPLIT` entre Plano e Programação;
- próxima execução/cursor não prova por si só uma ocorrência histórica;
- OS vinculada a plano pode ser candidata a OS Preventiva, mas precisa de tenant, plano, data/competência e origem coerentes;
- a occurrence key histórica deve ser desenhada em 10B sem inventar versão ou competência;
- duplicidades possíveis de ocorrência entram em quarentena;
- o cursor V2 não pode avançar sem ocorrência/OS correspondente comprovada;
- execuções históricas preservam o que existe; eventos ausentes não são sintetizados;
- recorrências complexas não entram como requisito de migração do MVP.

## 15. Estratégia histórica, auditoria e comentários

As categorias permanecem separadas:

| Categoria | Destino |
| --- | --- |
| Histórico operacional | Eventos compreensíveis sobre o registro |
| Auditoria | Rastreabilidade técnica/administrativa e da própria migração |
| Comentário | Comunicação humana intencional |
| Proveniência | Relação entre fonte V1, decisão e destino V2 |

Estratégia:

- migrar `historico_demandas` e `historico_ordens_servico` apenas após mapear a entidade pai;
- preservar payload/descrição original quando a semântica não puder ser convertida com segurança;
- não transformar observação, motivo ou texto livre em comentário sem evidência de intenção comunicacional;
- não fabricar auditoria V2 retroativa; fatos técnicos legados podem ser retidos como provenance/legacy audit com origem identificada;
- registrar a própria migração com correlação, lote/onda, regra aplicada, resultado e identidade técnica responsável;
- aplicar `legacy_actor`, `unresolved_actor`, `mapped_actor` ou `technical_actor` conforme evidência;
- manter eventos históricos append-only no destino e não reescrevê-los com nomes atuais de catálogos.

## 16. Estratégia de Storage

O princípio de destino é:

```text
Storage object != database metadata
```

Estratégia conceitual:

1. Inventariar separadamente metadados e objetos dos buckets.
2. Relacionar cada objeto a tenant, entidade pai, finalidade e registro de metadado.
3. Calcular hash/checksum quando aplicável na etapa autorizada e comparar tamanho/MIME.
4. Carregar primeiro a entidade pai, depois metadados em estado de migração e, por fim, o objeto.
5. Considerar a associação concluída somente após validação equivalente ao `finalize` V2.
6. Colocar objetos sem metadado, metadados sem objeto, paths ambíguos, tenant divergente ou entidade ausente em quarentena.
7. Preservar nome original, tipo, tamanho, autor conhecido, timestamps, legenda/finalidade e path legado em provenance.
8. Não confiar no path do bucket como autorização ou prova de tenant.
9. Não persistir signed URLs como dado migrado.
10. Reconciliar logos separadamente dos anexos/evidências operacionais.

A quantidade final de buckets é `PROVIDER-DEPENDENT` e não é decidida nesta etapa.

## 17. Cross-tenant e autoria

Para todo caso em que:

```text
record.tenant != actor.current_tenant
```

é proibido concluir automaticamente que houve vazamento, corrupção, autoria falsa ou tenant errado. O caso deve ser classificado por evidência histórica, membership à época, função técnica, atuação de plataforma e cadeia do evento.

Destinos conceituais:

| Destino | Uso |
| --- | --- |
| `mapped_actor` | Identidade V2 comprovadamente correspondente |
| `legacy_actor` | Ator conhecido apenas no contexto legado |
| `unresolved_actor` | Ausência ou ambiguidade não solucionada |
| `technical_actor` | Ação comprovadamente produzida por função/processo técnico |
| `provenance` | Preservação do valor original e da análise |
| `quarantine` | Relação insegura ou não classificável para carga operacional |

Evidências possíveis para 10B: timestamps de membership, histórico de alterações, identidade Auth, logs autorizados, origem da função/trigger, tenant do pai e filhos, e decisão administrativa documentada. O tenant atual do ator não deve reescrever sozinho o passado.

## 18. Modelo conceitual de quarentena

A quarentena preserva o registro original e impede promoção silenciosa ao modelo operacional.

Campos conceituais mínimos:

- `source_system` e ambiente/snapshot;
- `source_table` ou tipo de objeto;
- `source_id` e chave composta original quando houver;
- `source_tenant` e tenant candidato, sem sobrescrever o original;
- payload relevante ou referência imutável ao payload capturado;
- hash do payload/evidência quando aplicável;
- motivo e categoria da quarentena;
- severidade e impacto (`record`, `wave`, `cutover`);
- regra/versão que detectou o caso;
- status de resolução;
- evidências e notas de revisão;
- responsável/autoridade da decisão;
- resolução futura e timestamp;
- referência V2 quando resolvida;
- correlação com lote/onda e reconciliação.

Categorias iniciais: tenant ausente/divergente, relação órfã, identidade ambígua, autoria incompatível, código duplicado, status/tipo desconhecido, semântica de operação/loja, arquivo inconsistente, permissão insegura, ocorrência preventiva duplicada e violação de integridade.

Status conceituais: `OPEN`, `UNDER_REVIEW`, `RESOLVED_MAP`, `RESOLVED_LEGACY_ONLY`, `APPROVED_DISCARD`, `BLOCKED`. A implementação física será decidida posteriormente.

## 19. Proveniência e migration ledger

Todo dado migrado relevante deve permitir o caminho:

```text
V2 entity
← mapping/decision
← migration run + rule version
← V1 snapshot + source record
```

Requisitos conceituais:

- registro por fonte e destino, admitindo 1:N e N:1;
- tipo de entidade, tenant, source ID, target ID e código humano;
- classe de migração aplicada;
- versão da regra de transformação;
- confiança, evidência e revisão quando aplicável;
- lote/onda, timestamps, resultado e correlation ID;
- checksum/hash do payload relevante quando aplicável;
- referências a quarentena e resolução;
- idempotência da carga e capacidade de provar que retry não duplicou destino;
- distinção entre registro migrado, regenerado, retido como legado e descarte aprovado.

Preferência conceitual: registry/ledger externo às tabelas operacionais, evitando espalhar colunas `legacy_*` por todo o modelo. Exceções só serão adotadas em 10B/10C quando uma consulta operacional ou requisito de retenção justificar.

## 20. Ordem lógica da migração

A ordem abaixo é propositalmente condicionada por gates; não é uma sequência cega de tabelas.

### Onda 0 — Governança e snapshot

- congelar escopo e janela do snapshot;
- revalidar remoto, drift e volumes;
- versionar dicionários, regras, ledger e critérios de quarentena;
- definir recuperação, ensaio e critérios de go/no-go.

**Gate:** snapshot autoritativo, repetível e reconciliável; nenhum acesso remoto ocorre na 10A.

### Onda 1 — Catálogos globais e fundação de tenant

- dados estruturais CW necessários;
- Empreendimentos, códigos/status aprovados e configurações mínimas;
- ledger e quarentena disponíveis para todas as ondas seguintes.

**Gate:** todos os tenants do escopo mapeados ou explicitamente bloqueados/excluídos do cutover aprovado.

### Onda 2 — Identidades, usuários e memberships

- Auth mappings;
- application users/profiles;
- memberships tenant;
- platform identities separadas.

**Gate:** usuário comum com no máximo um tenant, Global Admin classificado e ausência de identidade fictícia.

### Onda 3 — Perfis, permissões, scopes e Equipes

- profile baselines;
- exact overrides;
- Equipes e memberships necessários ao scope TEAM;
- casos incertos sem privilégio por aproximação.

**Gate:** matriz revisada, antiescalada e isolamento testáveis; mapping inseguro bloqueia ativação.

### Onda 4 — Cadastros estruturais

- Locais, Centros de Custo, Setores, Categorias/Subcategorias e motivos necessários;
- classificação de operações/lojas;
- seeds mínimos aprovados, sem taxonomia inventada.

**Gate:** referências críticas possuem destino ou quarentena conhecida.

### Onda 5 — Recursos compartilhados

- Fornecedores, contatos e especialidades;
- Ativos, hierarquia, localização e condição/status;
- metadados documentais ainda sem promover objeto inconsistente.

**Gate:** códigos únicos, hierarquias sem ciclo, relações tenant-aware e pais resolvidos.

### Onda 6 — Solicitações

- demandas classificadas como Requests;
- agendamentos como subtipo funcional aplicável;
- vínculos de cadastros, autoria, códigos e histórico básico.

**Gate:** tipos/status/códigos reconciliados e Preventiva removida do conjunto de Solicitações por classificação, não descarte.

### Onda 7 — OS e dependentes operacionais

- OS avulsas e vinculadas;
- responsáveis/executores classificados;
- custos, materiais, pausas e validações existentes;
- checklists históricos somente quando comprovados.

**Gate:** cardinalidade Request × OS, tenant, transições e códigos reconciliados.

### Onda 8 — Preventiva

- Planos;
- Programações;
- ocorrências históricas classificáveis;
- OS Preventivas e execuções.

**Gate:** occurrence keys sem duplicidade e cursores coerentes com OS/ocorrência.

### Onda 9 — Histórico, auditoria legada e comentários classificados

- históricos operacionais completos após pais;
- fatos técnicos legados/provenance;
- comentários apenas com evidência.

**Gate:** counts por pai/evento, atores tratados e ausência de evento fabricado.

### Onda 10 — Arquivos e Storage

- metadados por entidade;
- objetos e logos;
- validação de integridade e associação contextual.

**Gate:** metadado × objeto × entidade × tenant reconciliados; órfãos críticos resolvidos ou bloqueados.

### Onda 11 — Dados secundários e regeneráveis

- notificações históricas somente se ainda válidas e autorizáveis;
- projeções, calendários, dashboard, relatórios, alertas e indicadores regenerados;
- nenhuma cache ou signed URL legada promovida.

**Gate:** projeções batem com fontes autoritativas e não ampliam acesso.

### Onda 12 — Counters, reconciliação final e cutover

- revalidar delta final;
- reconciliar todos os códigos e ajustar próximo valor sem reutilização;
- executar relatório de exceções, blockers e go/no-go;
- ensaiar recuperação e realizar verificação pós-cutover conforme plano aprovado.

## 21. Revalidações necessárias antes do cutover

Todos os itens desta seção têm o marcador:

**REVALIDAÇÃO NECESSÁRIA ANTES DO CUTOVER**

### 21.1 Estado e drift

- commit/tag e versão efetivamente publicados;
- schema completo, extensões e drift em relação aos SQLs versionados;
- tabelas, colunas, constraints, índices, views e materialized views;
- migrations/marcas aplicadas e alterações manuais;
- functions/RPCs, owners, `SECURITY DEFINER`, `search_path` e grants;
- triggers existentes, habilitação e efeitos;
- sequences/counters e consumidores;
- RLS habilitada e policies efetivas por operação;
- Edge Functions publicadas, versão e configuração, sem expor secrets.

### 21.2 Volumes e qualidade

- counts totais e por tenant de organizações, perfis, usuários, Requests, OS, Planos, Ativos, Fornecedores e dependentes;
- distribuição por status, tipo, prioridade, ano e origem;
- tenants inexistentes/inativos, IDs nulos e chaves duplicadas;
- FKs órfãs, relações cross-tenant e autoria incompatível;
- registros sem `user_id`/autoria;
- códigos humanos duplicados, inválidos ou conflitantes;
- novos campos/tabelas/registros criados após o inventário;
- deletes/updates ocorridos durante eventual janela de convivência.

### 21.3 Auth e autorização

- contagem e providers de Auth;
- Auth sem perfil e perfil sem Auth;
- e-mails duplicados/alterados e UUIDs incompatíveis;
- usuários por tenant, status e possível membership múltiplo;
- Global Admin e capacidades administrativas efetivas;
- permissões legadas, broad grants e regras/bypasses vigentes;
- operações/lojas usadas como escopo real.

### 21.4 Storage

- buckets, privacidade, limites e policies efetivas;
- contagem por bucket, tenant lógico, entidade e prefixo;
- metadados sem objeto e objetos sem metadado;
- tamanho, MIME, checksum quando aplicável e integridade física;
- paths duplicados, versões de logo, objetos cross-tenant e objetos órfãos;
- uploads ocorridos após o snapshot inicial.

### 21.5 Domínios

- vocabulários reais de tipos, status, prioridades, naturezas, categorias e especialidades;
- significado por tenant de operação/loja/local/centro de custo/setor/equipe;
- cardinalidade Request × OS e OS avulsas;
- executor versus responsável e autoria de transições;
- Planos, próximas execuções, OS geradas e possíveis duplicidades de ocorrência;
- writers e cobertura de históricos, notificações, anexos, custos, materiais e checklists;
- configurações tenant de validação, autovalidação e motivos, se existirem.

## 22. Reconciliação

A reconciliação deve produzir métricas antes/depois por snapshot, onda, tenant e domínio.

### 22.1 Métricas mínimas

- counts de origem, elegíveis, migrados, regenerados, legacy-only, quarantined, unresolved e discard-approved;
- counts por tabela/domínio, tenant, status, tipo, prioridade, ano e origem;
- IDs de origem mapeados e destinos únicos;
- cardinalidade de mappings 1:1, 1:N e N:1;
- códigos preservados, códigos duplicados e próximo contador calculado;
- Auth mappings, application users, memberships e identities sem correspondência;
- perfis, capabilities/scopes propostos, revisados e não concedidos;
- Requests, OS avulsas/vinculadas e cardinalidade por Request;
- Planos, Programações, ocorrências e OS Preventivas;
- pais/filhos, relações quebradas, órfãos e cross-tenant;
- históricos por entidade e eventos sem ator resolvido;
- anexos esperados × metadados migrados × objetos migrados;
- bytes/tamanho total e checksums quando aplicáveis;
- notificações preservadas, neutralizadas, legacy-only ou descartáveis;
- projeções regeneradas comparadas às fontes.

### 22.2 Invariantes de reconciliação

Para cada domínio:

```text
origem no snapshot
= migrado
+ legacy-only
+ quarantined/unresolved
+ descarte formalmente aprovado
+ exclusões/deltas documentados da janela
```

Não se considera reconciliado um count total correto com distribuição por tenant incorreta. Soma global não mascara vazamento, duplicidade ou perda em um Empreendimento.

### 22.3 Evidências

Cada relatório deve registrar snapshot, query/versão da regra, timestamp, tenant, resultado, tolerância permitida e responsável pela revisão. Divergências precisam ser explicadas por registro ou categoria controlada.

## 23. Critérios de bloqueio

O cutover deve ser bloqueado se ocorrer qualquer condição crítica sem exceção formal aprovada:

1. tenant mapping incompleto para registros do escopo;
2. usuário comum com múltiplos tenants ou identidade crítica sem correspondência;
3. Global Admin misturado a Perfil tenant sem resolução;
4. permission mapping inseguro, broad grant ou antiescalada não comprovada;
5. falha em RLS, tenant isolation, FKs tenant-aware ou autorização de Storage;
6. relação cross-tenant crítica sem classificação e evidência;
7. códigos duplicados/conflitantes sem resolução ou counter capaz de reutilizar código;
8. relação Request/OS inconsistente, tenant divergente ou cardinalidade inválida;
9. ocorrência preventiva duplicada ou cursor sem correspondência comprovada;
10. objeto Storage importante ausente, corrompido, sem pai ou sem tenant resolvido;
11. counts críticos divergentes além da tolerância formal;
12. registro operacional perdido sem classificação em ledger/quarentena;
13. migrations/cargas não reproduzíveis e idempotentes;
14. audit/provenance obrigatório ausente;
15. schema drift não incorporado ao plano;
16. snapshot/delta incapaz de impedir perda de alterações na janela;
17. rollback/roll-forward ou recuperação não ensaiados;
18. smoke tests e testes de segurança obrigatórios não aprovados;
19. evidência obrigatória ausente para decisões de descarte, merge, split ou correção;
20. blocker aberto classificado como impacto de cutover.

## 24. Riscos

| Risco | Impacto | Mitigação estratégica |
| --- | --- | --- |
| Estado remoto diferente do repositório | Plano incompleto ou carga incorreta | snapshot e schema diff obrigatórios em 10B |
| Ausência de migrations históricas formais | Impossibilidade de reproduzir origem | tratar SQLs como evidência, reconstruir baseline controlada |
| FKs sem tenant composto | Associação cross-tenant | detectar, quarentenar e exigir integridade V2 |
| Autoria ausente/incompatível | Atribuição falsa ou perda de rastreabilidade | atores conceituais e evidência; nunca inventar humano |
| Operação/loja ambígua | Estrutura organizacional errada | classificação manual por tenant/uso |
| Permissões por papel e bypass | Escalada de privilégio | matriz explícita, menor privilégio e revisão |
| Global Admin misturado | Bypass transversal | separar identidade/capability de plataforma |
| Código duplicado ou counter híbrido | Colisão e perda de referência | preservar legado, ledger e reconciliação final |
| Status/tipos incompatíveis | Semântica operacional falsa | dicionário versionado e quarentena |
| Executor único legado | Confusão entre responsabilidade e execução | split somente com evidência |
| Preventiva sobreposta | Duplicidade de OS/ocorrência | separar conceitos e validar occurrence key |
| Histórico e auditoria sobrepostos | Evento fabricado ou rastreabilidade incompleta | manter categorias e origem distintas |
| Storage por path | Vazamento ou associação incorreta | inventário metadado × objeto e autorização contextual |
| Objetos órfãos/inexistentes | Perda de evidência | quarentena e blocker por criticidade |
| Migração longa com escrita concorrente | Snapshot obsoleto | estratégia de delta/janela em 10C/10D |
| Regeneração incorreta de projeções | Indicadores divergentes | reconciliar com fontes autoritativas |
| Descarte prematuro | Perda irreversível | nenhuma exclusão nesta etapa; aprovação e retenção |

## 25. Entregáveis da Etapa 10B

A 10B deverá transformar esta estratégia em especificação detalhada, ainda antes da carga real:

- inventário remoto versionado de schema, dados, Auth, Storage, RLS, grants, functions, triggers, sequences e Edge Functions;
- snapshot/manifesto de origem e detecção de drift;
- dicionário de dados V1 e modelo conceitual/físico V2 aplicável;
- tabela detalhada de mapeamento campo a campo e entidade a entidade;
- catálogo de regras `DIRECT_MAP` a `REGENERATE` por subconjunto/registro;
- dicionários de tipos, status, prioridades, categorias, motivos e especialidades;
- mapa de tenants, identities, memberships, profiles e permissões com confidence/review;
- desenho físico do migration ledger, provenance e quarentena;
- estratégia de IDs/códigos/counters e tratamento de duplicidades;
- mapa Request/OS e separação de preventiva;
- inventário metadado × objeto do Storage;
- queries/métricas de reconciliação especificadas;
- registro de decisões deferidas e blockers abertos.

## 26. Entregáveis da Etapa 10C

A 10C deverá preparar e provar a execução técnica em ambiente autorizado e descartável/controlado:

- migrations V2 versionadas e reproduzíveis, separadas do ETL;
- modelo/staging intermediário e cargas idempotentes;
- scripts ETL versionados com dry-run, regras e relatórios de exceção;
- implementação do ledger, provenance e quarentena;
- cargas por ondas e dependências;
- validações de integridade, tenant, códigos, Auth mapping e Storage;
- testes de migration forward, retry, concorrência e idempotência;
- testes de RLS, FKs compostas, antiescalada, commands e Storage com ao menos dois tenants;
- reconciliação automatizada por domínio/tenant;
- procedimento de delta e compatibilidade durante convivência;
- plano e ensaio de rollback/roll-forward/recuperação;
- evidências de execução em TEST e, quando aprovado, STAGING.

## 27. Entregáveis da Etapa 10D

A 10D deverá consolidar prontidão, cutover e estabilização:

- runbook operacional de cutover com responsáveis e tempos;
- snapshot/delta final e janela de mudança;
- checklist go/no-go baseado nos blockers deste documento;
- reconciliação final V1 × V2 por tenant e domínio;
- ajuste final de counters/códigos sem reutilização;
- verificação de Auth, memberships, permissões, RLS, Storage e fluxos críticos;
- smoke tests e testes de segurança pós-carga;
- execução/validação do pilot Serena sem fork arquitetural;
- plano de rollback/roll-forward acionável e critérios de acionamento;
- monitoramento, observabilidade e período de estabilização;
- relatório de exceções, quarentena remanescente e decisões aceitas;
- aprovação humana formal do cutover e encerramento.

## 28. Decisões deferidas

Permanecem deliberadamente abertas para 10B/10C ou para as classificações da arquitetura:

- modelagem física e nomes de tabelas do ledger, staging e quarentena;
- ferramenta/runtime de ETL e formato do manifesto de snapshot;
- estratégia exata de snapshot, delta, dual-write ou janela de indisponibilidade;
- preservação direta de cada Auth UUID após inspeção remota;
- mapeamento final de operações/lojas, localização textual, naturezas e especialidades;
- dicionário final de tipos/status/prioridades;
- regra física de occurrence key histórica;
- tratamento de OS com executor/responsável ambíguo;
- tolerâncias quantitativas de reconciliação;
- retenção legal e prazo de dados `LEGACY_ONLY`/quarentena;
- quantidade final de buckets e mecanismo de cópia/verificação de objetos;
- mecanismo físico de counters e idempotency keys;
- thresholds e coorte do pilot Serena;
- provider de workers, observabilidade e hosting;
- aprovação de qualquer `DISCARD_CANDIDATE`.

Essas decisões não autorizam reabrir invariantes `CLOSED`, reduzir segurança ou promover funcionalidade futura.

## 29. Conclusão

A V1 contém dados e relações que merecem preservação, mas sua estrutura não pode ser promovida diretamente à V2. O caminho recomendado é uma migração por ondas, mediada por mapeamento explícito, modelo intermediário, quarentena, provenance e reconciliação por tenant.

Os maiores condicionantes são o estado remoto ainda não revalidado, identidade/membership, relações cross-tenant, permissões legadas, códigos/counters, separação Request/OS/Preventiva, autoria e integridade do Storage. Todos dependem de evidência antes da transformação definitiva.

A Etapa 10B deve começar pelo snapshot remoto e pelo mapeamento detalhado. A 10C deve construir e ensaiar migrations/ETL idempotentes em ambiente controlado. A 10D deve operar o go/no-go, cutover, verificação e estabilização. Nenhuma dessas ações foi executada na 10A.
