# Arquitetura Técnica Oficial — CW ERP V2

| Campo | Valor |
| --- | --- |
| Status | **FROZEN BASELINE** |
| Branch de referência | **develop/v2** |
| Produto | CW ERP / CW Manutenção V2 |
| Escopo | Baseline técnica da V2, consolidada a partir das decisões aprovadas das Etapas 1–9 e dos fechamentos ratificados na Etapa 9B |
| Fonte funcional | PRODUCT_SPEC.md |
| Fontes de contexto | AGENTS.md, docs/INVENTARIO-V1.md e docs/GAP-ANALYSIS-V1-V2.md |
| Próxima etapa | Etapa 10 — plano técnico V1 → V2 |

Este documento é a fonte técnica oficial da arquitetura CW ERP V2. O PRODUCT_SPEC.md continua sendo a fonte oficial das regras funcionais, do escopo obrigatório, complementar e futuro. Em caso de conflito, a divergência deve ser registrada e resolvida formalmente; não se deve alterar silenciosamente nem a regra funcional nem esta baseline.

Esta baseline define invariantes, fronteiras e decisões arquiteturais. Ela não é plano de implementação, modelagem física completa, migration, código, escolha de hosting ou plano de migração de dados.

Após o congelamento, decisões classificadas como **CLOSED** somente podem mudar pelo processo da seção 44. Itens **DEFERIDO**, **IMPLEMENTATION-DEPENDENT**, **PROVIDER-DEPENDENT**, **ROLLOUT-DEPENDENT** ou **LEGAL/RETENTION-DEPENDENT** podem ser concretizados sem reabrir a arquitetura, desde que preservem todos os invariantes desta baseline.

> Nota documental: a ratificação da Etapa 9B delimita o e-mail operacional de eventos de domínio como futuro. Essa delimitação prevalece nesta baseline sobre formulações mais amplas do PRODUCT_SPEC.md para o MVP, sem alterar o documento funcional nesta execução.

## 1. Visão Executiva

A V2 é uma reconstrução incremental e segura do CW Manutenção como primeiro módulo da plataforma SaaS multiempresa CW ERP. Ela preserva regras e dados válidos da V1, mas não prolonga sua arquitetura de scripts globais, navegação híbrida, estado compartilhado implícito, SQL manual acumulativo ou autorização baseada em papéis e bypasses.

A arquitetura se organiza em cinco limites:

1. **Experiência cliente:** rotas, telas e componentes orientados a domínio, responsivos e acessíveis.
2. **Acesso a dados:** queries sem efeitos colaterais e commands explícitos para mutações.
3. **Autoridade:** tenant, entitlement, permissão, scope, estado e versão avaliados no servidor/banco.
4. **Persistência:** PostgreSQL com RLS, integridade tenant-aware, auditoria, histórico e outbox transacionais.
5. **Execução técnica:** Storage e workers operados com capacidades técnicas mínimas, payload não autoritativo e rastreabilidade.

Visão macro:

~~~text
Pessoa autenticada
        |
        v
Frontend por rotas e módulos
        |
        +---------------- Query boundary ----------------+
        |                                                |
        |                                PostgreSQL + RLS + projeção
        |
        +--------------- Command boundary ---------------+
                                                         |
                                     transação + locks + reautorização
                                                         |
                            domínio + auditoria + histórico + outbox
                                                         |
                                         commit único e observável
                                                         |
                           worker allowlisted / Storage quando necessário
~~~

Segurança, isolamento multiempresa e rastreabilidade precedem conveniência de implementação. O frontend melhora a experiência, mas não é autoridade. A V1 é evidência e condicionante de migração, não arquitetura normativa da V2.

## 2. Princípios Arquiteturais

Decisões **CLOSED**:

- segurança antes de fundação, fluxo, consistência e experiência;
- todo dado de cliente tem vínculo inequívoco com um Empreendimento;
- autorização combina principal, contexto, tenant, entitlement, Resource, Action e Scope;
- Perfil é baseline, não autorização final;
- defesa em profundidade em frontend, backend/commands, banco/RLS e Storage;
- queries e commands têm contratos e responsabilidades distintos;
- mutations críticas estabilizam fatos mutáveis antes da decisão final;
- efeitos persistentes relacionados a uma mudança de domínio são transacionais quando fazem parte da mesma decisão;
- auditoria, histórico, comentários, notificações e alertas são conceitos distintos;
- registros operacionais relevantes são cancelados, inativados, baixados ou arquivados; exclusão física é excepcional;
- componentes e mecanismos transversais são reutilizados sem criar plataforma genérica antecipada;
- a V2 inicial exige conexão; offline/PWA não integra o escopo;
- funcionalidades futuras não geram tabelas, telas, APIs ou infraestrutura prematuras;
- toda informação apresentada por Dashboard, Visão Geral, relatório, notificação ou URL de mídia permanece limitada ao acesso efetivo do usuário.

Princípio de autoridade:

~~~text
tenant authority != platform authority != technical authority
~~~

As três autoridades são separadas, explícitas, mínimas, auditáveis e não intercambiáveis.

## 3. Arquitetura Macro

Decisões **CLOSED**:

- a aplicação cliente é organizada por domínios e capacidades compartilhadas;
- o cliente acessa dados somente por uma camada delimitada de queries e commands;
- leitura comum usa RLS e projeções autorizadas;
- mutações simples ainda devem respeitar validação e RLS;
- mutações críticas são commands server-side ou de banco com contrato explícito;
- PostgreSQL é a fonte autoritativa dos dados operacionais;
- metadados de arquivos pertencem ao banco; bytes pertencem ao Storage;
- eventos assíncronos saem de outbox persistido, não de disparo best-effort no cliente;
- integrações técnicas não recebem autoridade a partir do payload;
- rotas e deep links são padrão arquitetural desde a fundação.

Mapa lógico:

~~~text
CW ERP
├── Núcleo
│   ├── identidade, sessão e contexto
│   ├── Empresa e Minha Conta
│   ├── notificações internas
│   ├── Visão Geral, Dashboard e Relatórios
│   └── autorização, auditoria e observabilidade
├── Compartilhado
│   ├── Ativos
│   ├── Fornecedores
│   ├── Cadastros
│   ├── mídia, comentários, histórico e checklist
│   └── componentes e contratos de UI
└── Manutenção
    ├── Solicitações
    ├── Ordens de Serviço
    ├── Planos e Programações
    └── Calendário derivado das fontes
~~~

O desenho físico de deploy é **PROVIDER-DEPENDENT**. Nenhuma topologia de hosting é fechada por esta baseline.

## 4. Stack Oficial

Decisões **CLOSED**:

- **Supabase Auth** para identidade e fluxos seguros de autenticação;
- **PostgreSQL/Supabase Database** como persistência autoritativa;
- **Row Level Security** como camada obrigatória de isolamento e autorização de leitura/escrita aplicável;
- **Supabase Storage** para objetos, com metadados e autorização contextual no banco;
- funções/RPCs e execução server-side para commands que não podem depender de escrita direta genérica;
- migrations versionadas e reproduzíveis como único caminho normal de evolução do esquema;
- aplicação web com rotas próprias, deep links e experiência responsiva;
- contratos tipados e validação nas fronteiras quando suportados pela implementação.

São **IMPLEMENTATION-DEPENDENT**, porque a evidência local desta consolidação não registra uma escolha CLOSED específica: framework frontend, router, biblioteca de componentes, biblioteca de formulários, gerenciador de estado cliente, cliente de queries, ferramenta de build, runtime exato das funções e convenções físicas de monorepo/pacotes.

São **DEFERIDO** ou **PROVIDER-DEPENDENT**, conforme a seção 41: hosting, provider de workers, provider de observabilidade, bibliotecas de gráficos e PDF, feature flags e cache server-side.

Uma escolha de implementação não pode reintroduzir scripts globais, dependência de ordem de carregamento, HTML inseguro por concatenação, estado global como fonte autoritativa ou acesso a dados sem boundaries.

## 5. Organização do Frontend

Decisões **CLOSED**:

- organização primária por domínio/capacidade, com compartilhamento explícito;
- rotas para páginas e registros relevantes, com refresh, back/forward, nova aba e deep link;
- filtros relevantes e paginação representáveis na URL quando isso melhorar continuidade e compartilhamento;
- sessão, contexto de tenant e capacidades efetivas tratados como estados explícitos;
- dados remotos não são duplicados como fonte autoritativa em estado global;
- componentes transversais encapsulam comportamento recorrente;
- estados obrigatórios: carregando, vazio, vazio por filtro, erro, validação, sem permissão, inexistente, conexão indisponível, sucesso, falha de ação, upload e processamento;
- fluxos operacionais críticos são mobile-first; administração complexa pode ser responsiva sem ser mobile-first;
- teclado, foco, labels, diálogos, contraste, área de toque e significado não dependente apenas de cor integram o padrão básico de acessibilidade;
- renderização de conteúdo não confiável deve ser segura por padrão; HTML bruto exige sanitização e justificativa.

Estrutura lógica, sem impor nomes de diretório:

~~~text
app shell e rotas
├── módulos de domínio
│   ├── páginas
│   ├── componentes do domínio
│   ├── queries
│   ├── commands
│   └── contratos/validação
├── capacidades compartilhadas
│   ├── auth e contexto
│   ├── autorização de UX
│   ├── tabelas, filtros e estados
│   ├── mídia, histórico, comentários e checklist
│   └── erros, telemetria e acessibilidade
└── infraestrutura
    ├── cliente Supabase
    ├── cache de queries
    └── configuração por ambiente
~~~

Os nomes CWDataTable, CWFilters, CWStatusBadge, CWHistory, CWChecklist, CWCalendar, CWConfirmDialog, CWPermissionGuard, CWUserSelector, CWNotifications, CWMediaManager e CWReport são contratos conceituais; não obrigam uma biblioteca ou hierarquia física específica.

## 6. Arquitetura de Dados

Decisões **CLOSED**:

- identificadores internos estáveis não dependem de códigos humanos;
- códigos humanos sequenciais são únicos no tenant e seguem as regras funcionais de cada entidade;
- tabelas tenant-owned carregam o identificador do Empreendimento;
- relações entre entidades tenant-owned garantem coerência de tenant no banco;
- constraints, índices, chaves estrangeiras e checks expressam invariantes que o banco pode garantir;
- transições críticas não são updates livres de linha;
- autoria e timestamps sensíveis são atribuídos ou validados por fonte autoritativa;
- status histórico não é apagado para simplificar estado atual;
- exclusão física de dados operacionais é excepcional;
- schema, dados de referência e mudanças são reproduzidos por migrations.

Padrão obrigatório de relação tenant-owned:

~~~text
filho (tenant_id, parent_id)
          |
          v
pai   (tenant_id, id)
~~~

As referências devem usar chaves/constraints compostas equivalentes ou outro mecanismo de banco igualmente forte. RLS não substitui coerência referencial; filtro de frontend não substitui nenhum dos dois.

Projeções públicas ou resumidas devem ser deliberadas. Campos sensíveis não são retornados apenas porque a linha é visível. Views, funções e consultas devem respeitar a projeção necessária ao caso de uso.

Modelagem física de tabelas, nomes de colunas e distribuição entre schemas é **IMPLEMENTATION-DEPENDENT** e será detalhada na implementação/modelagem, sem alterar os invariantes.

## 7. Multiempresa / Tenant Model

Decisões **CLOSED**:

- cada cliente CW é um Empreendimento/tenant;
- unidades internas são Locais, Centros de Custo, Setores, Equipes ou estruturas correlatas, não tenants adicionais por conveniência;
- usuário comum pertence a um único tenant;
- o contexto de tenant não é aceito como autoridade apenas porque veio do cliente, URL, header ou payload;
- toda leitura, escrita, relação, arquivo, notificação, relatório, cache e evento técnico tenant-owned preserva tenant inequívoco;
- situação Ativo, Suspenso ou Inativo e entitlements influenciam o acesso conforme o caso de uso;
- Global Admin é autoridade de plataforma separada;
- workers usam autoridade técnica separada;
- operações cross-tenant não são padrão e não são simuladas por union de consultas comuns.

Para autoridade tenant, o tenant efetivo é derivado de identidade/sessão e vínculos autoritativos, então confrontado com o target. Slugs e IDs da rota são seletores, não prova de acesso.

## 8. Modelo de Autorização

### 8.1 Combinação exata

Decisão **CLOSED — AUTH-01**:

~~~text
Capability = Resource + Action + Scope
~~~

Perfil fornece o baseline. Override individual atua sobre a **mesma combinação exata** Resource + Action + Scope.

Para um usuário u, recurso r e ação a:

~~~text
BASE(u, r, a) =
  conjunto de scopes concedidos pelo Perfil baseline

OVERRIDE(u, r, a, s) =
  ALLOW, DENY ou ausência para a combinação exata (r, a, s)

EFFECTIVE_SCOPES(u, r, a) =
  { s em BASE(u, r, a) onde OVERRIDE(u, r, a, s) != DENY }
  união
  { s onde OVERRIDE(u, r, a, s) = ALLOW }
~~~

Consequências obrigatórias:

- DENY individual exato prevalece sobre ALLOW do baseline somente na mesma combinação;
- ALLOW individual exato adiciona a combinação;
- não existe subtração implícita entre scopes;
- DENY OWN não recorta ALL_TENANT;
- DENY TEAM não recorta ALL_TENANT;
- remover ALL_TENANT exige negar ou remover ALL_TENANT explicitamente;
- a existência de vários scopes efetivos é união de alcance, não hierarquia de negações.

Scopes conceituais iniciais:

- OWN: registros próprios segundo a definição do recurso;
- ASSIGNED: registros atribuídos ao usuário;
- TEAM: registros alcançados por Equipes do usuário;
- ALL_TENANT: todos os registros autorizáveis do tenant.

A definição de “próprio”, “atribuído” e “Equipe” é específica por recurso e precisa ser explícita na matriz técnica; não pode ser improvisada por tela.

### 8.2 Fórmula PERMIT

Para uma operação tenant-targeted sobre registro x:

~~~text
PERMIT(u, ctx, t, r, a, x) =
  AUTHENTICATED(u)
  and PRINCIPAL_ACTIVE(u)
  and CONTEXT_VALID(u, ctx)
  and TENANT_MATCH(ctx, t, x)
  and TENANT_OPERATION_ALLOWED(t)
  and ENTITLEMENT_ENABLED(t, r, a)
  and exists s in EFFECTIVE_SCOPES(u, r, a):
        SCOPE_REACHES(u, ctx, t, r, s, x)
~~~

Para commands, PERMIT é necessário, mas não suficiente: domain/state/version, invariantes, input e condições de concorrência também devem ser válidos.

~~~text
COMMAND_ALLOWED =
  PERMIT
  and INPUT_VALID
  and DOMAIN_STATE_VALID
  and EXPECTED_VERSION_VALID
  and INVARIANTS_HOLD
~~~

Autoridades de plataforma e técnica não são scopes extras de tenant:

- platform authority usa capabilities e commands de plataforma;
- technical authority usa capabilities fixas de handlers allowlisted;
- nenhuma delas nasce de Perfil tenant, override comum ou payload.

## 9. RLS e Segurança de Banco

Decisões **CLOSED**:

- RLS é obrigatória em toda tabela tenant-owned, com análise explícita por operação;
- policies genéricas permissivas não são atalho aceitável;
- SELECT, INSERT, UPDATE e DELETE/inativação são avaliados separadamente;
- policies e functions nunca confiam em tenant enviado pelo cliente sem vínculo autoritativo;
- relações cross-entity preservam tenant por constraint, além da RLS;
- funções SECURITY DEFINER são mínimas, justificadas e revisadas;
- service_role não é utilizada no frontend;
- grants seguem menor privilégio;
- testes de RLS cobrem isolamento entre tenants e casos positivos/negativos por capability e scope.

Decisão **CLOSED — RLS-01**:

O evaluator usado por RLS não pode depender circularmente das mesmas policies que está tentando decidir. Helpers privilegiados mínimos devem:

- usar search_path seguro e explícito;
- qualificar objetos;
- receber/derivar ator e tenant somente de fontes confiáveis;
- possuir grants mínimos;
- não manter PUBLIC EXECUTE indevido;
- evitar leitura recursiva de tabelas cuja policy depende do próprio helper;
- ser pequenos o suficiente para auditoria e testes exaustivos.

O desenho físico desses helpers é **IMPLEMENTATION-DEPENDENT**.

RLS é defesa e enforcement, mas commands críticos ainda precisam validar estado, versão e invariantes. Uma policy de UPDATE não autoriza alteração arbitrária de colunas ou transição.

## 10. Governança de Permissões

Decisões **CLOSED**:

- Perfis-base fornecem conjuntos baseline;
- overrides individuais são explícitos, exatos, auditáveis e não reescrevem o Perfil;
- concessão, revogação e negação passam por command administrativo dedicado;
- ninguém concede autoridade que não possui, salvo capability explícita e reservada de plataforma;
- permissões reservadas à CW não são delegáveis por administrador tenant;
- mudança de Perfil, override, Equipe, status de usuário ou entitlement é auditada;
- a matriz técnica precisa registrar recurso, ação, scope aplicável, definição de alcance e fronteira de enforcement;
- alterações concorrentes de governança usam versão/locking conforme o risco;
- sessões e caches não mantêm capabilities antigas após bloqueio ou troca relevante detectada.

A antiescalada considera a autoridade efetiva do concedente e o target tenant. A regra física para provar delegabilidade é **IMPLEMENTATION-DEPENDENT**, mas não pode se basear apenas no nome do Perfil.

Capabilities de UI são projeções da decisão de autorização para orientar a experiência. Elas não substituem RLS nem reautorização de command.

## 11. Backend, Queries e Commands

### 11.1 Query boundary

Decisões **CLOSED**:

- query é leitura sem efeito colateral de domínio;
- toda query recebe contexto suficiente para paginação, filtros, ordenação e projeção;
- RLS e autorização server-side limitam linhas; projeção limita campos;
- filtros e agregações são aplicados na fonte, não após carregar dados de múltiplos tenants;
- queries não reservam números, não avançam cursores, não marcam eventos como processados e não realizam writes ocultos;
- listagens são paginadas e têm ordenação determinística;
- detalhe por ID aplica anti-enumeration contextual;
- Dashboard, relatórios, notificações e busca usam a mesma fronteira de autorização.

### 11.2 Command boundary

Decisões **CLOSED**:

- command representa intenção de mudança, não patch arbitrário de tabela;
- commands críticos concentram transição, validação, autorização final, concorrência, idempotência e efeitos transacionais;
- input é validado por contrato;
- tenant, ator, autoria e autoridade não são aceitos do payload como fatos;
- cada command define pré-condições, estado resultante, erros estáveis e efeitos;
- updates condicionais/versionados evitam lost update;
- operações administrativas, Global Admin, Storage finalize e transições críticas de OS sempre usam commands dedicados.

Decisão **CLOSED — AUTH-02** para commands críticos:

~~~text
iniciar transação
→ identificar fatos relevantes
→ adquirir locks necessários em ordem canônica
→ reler estado autoritativo
→ reavaliar tenant + entitlement + permission + scope
→ validar domain/state/version
→ mutar
→ audit/history/outbox
→ commit
~~~

Não se congela que todas as tabelas de permissões devam ser bloqueadas em todo command. Devem ser estabilizados somente os fatos mutáveis relevantes à decisão, com locks ou técnicas equivalentes adequadas.

## 12. Concorrência e Idempotência

Decisões **CLOSED**:

- commands críticos declaram estratégia de concorrência;
- locks são adquiridos em ordem canônica para reduzir deadlocks;
- estado e autorização são relidos depois da estabilização necessária;
- versão esperada ou condição equivalente protege edições concorrentes;
- números sequenciais são alocados atomicamente por tenant e domínio;
- idempotency keys são exigidas onde retry pode duplicar efeitos;
- repetição com a mesma chave retorna o resultado compatível ou erro determinístico, sem repetir o efeito;
- outbox, jobs e finalize de Storage têm identidade/idempotência persistida;
- workers usam conditional write/fencing para impedir conclusão por executor obsoleto;
- criação de OS preventiva é protegida pela occurrence key.

Estratégias físicas de lock, colunas de versão e armazenamento de idempotency keys são **IMPLEMENTATION-DEPENDENT**.

## 13. Solicitações

Decisões **CLOSED**:

- Solicitação representa necessidade/ocorrência/pedido e é independente de OS;
- tipos oficiais: Manutenção Corretiva, Solicitação de Serviço, Agendamento de Serviço e Inspeção/Vistoria;
- Preventiva não é tipo de Solicitação;
- status oficiais: Registrada, Em análise, Programada, Em andamento, Concluída, Cancelada e Rejeitada;
- prioridades: Baixa, Normal, Alta e Urgente;
- prioridade só é alterada por capability adequada e a mudança é auditada;
- identificação anual sequencial é por tenant;
- uma Solicitação possui zero, uma ou várias OS;
- cancelar e rejeitar têm semânticas e motivos próprios;
- comentários são comunicação; histórico registra eventos; auditoria registra atos sensíveis;
- anexos usam o padrão compartilhado e autorização contextual;
- agendamento aprovado pode aparecer no Calendário e pode ou não gerar OS;
- conclusão de OS nunca conclui automaticamente Solicitação;
- após todas as OS vinculadas estarem concluídas, o sistema pode sugerir a conclusão a pessoa autorizada.

Transições e campos obrigatórios seguem PRODUCT_SPEC.md e são aplicados por commands quando críticos.

## 14. Ordens de Serviço

Decisões **CLOSED**:

- OS é o registro formal do trabalho;
- origens: Manual, Solicitação ou Manutenção Preventiva;
- tipos: Corretiva, Preventiva, Inspeção/Vistoria e Serviço;
- status: Rascunho, Aberta, Programada, Em execução, Pausada, Aguardando validação, Concluída e Cancelada;
- OS pode existir sem Solicitação e se vincula a no máximo uma Solicitação;
- uma Solicitação pode se vincular a várias OS;
- responsável não é necessariamente Executor;
- uma OS pode ter múltiplos Executores;
- execução pode ser Interna, Fornecedor ou Mista;
- pausa exige motivo, autoria e intervalo; “Outro” exige justificativa;
- custo estimado e real são opcionais e não bloqueiam o fluxo;
- checklist obrigatório completo e serviço executado obrigatório conforme configuração são pré-condições de conclusão;
- quando validação está habilitada, o Executor envia para Aguardando validação;
- aprovação leva a Concluída;
- devolução exige motivo, retorna a Em execução, é auditada e pode ocorrer repetidamente;
- durante Aguardando validação, campos de execução ficam bloqueados ao Executor, salvo command explicitamente permitido;
- impedir autovalidação é política tenant configurável, com padrão recomendado “não permitir”;
- concluir OS não conclui Solicitação;
- transições críticas são commands, não updates genéricos.

Fluxo oficial resumido:

~~~text
Rascunho → Aberta → Programada → Em execução
                                  ├→ Pausada → Em execução
                                  ├→ Aguardando validação
                                  │       ├→ Concluída
                                  │       └→ devolução motivada → Em execução
                                  └→ Concluída, quando validação não for exigida

Estados autorizados também podem alcançar Cancelada conforme a regra funcional.
~~~

Toda transição registra histórico operacional; transições sensíveis também geram auditoria. Eventos destinados a usuários são produzidos via outbox quando aplicável.

## 15. Manutenção Preventiva

Decisões **CLOSED**:

~~~text
Plano → Programação → OS Preventiva → Execução
~~~

- Plano define o que ocorre periodicamente;
- Programação define quando;
- OS Preventiva materializa o trabalho;
- Execução registra o realizado;
- Plano se vincula a Ativo e pode definir responsável/Equipe, Fornecedor, checklist e instruções;
- próxima execução e histórico básico integram o MVP;
- Calendário é projeção temporal e não duplicação dessas entidades;
- recorrências e automações complexas são complementares, não justificam motor genérico prematuro;
- geração automática deve ser idempotente e rastreável.

O mecanismo físico de scheduler é **PROVIDER-DEPENDENT**. A semântica de ocorrência e a proteção contra duplicidade são CLOSED.

## 16. Ocorrência Preventiva

Decisão **CLOSED — PRE-01**:

A ocorrência preventiva é identidade lógica necessária:

~~~text
tenant
+ programação preventiva
+ competência ou instante planejado canônico
+ versão necessária à identidade
= occurrence key
~~~

A occurrence key deve:

- ser determinística para a mesma ocorrência;
- impedir duas OS para a mesma ocorrência;
- impedir avanço de cursor sem ocorrência/OS correspondente;
- sobreviver a retry de scheduler/worker;
- distinguir corretamente uma nova versão quando a regra de identidade exigir;
- vincular geração, OS criada e avanço do estado de programação na mesma decisão transacional ou em protocolo idempotente equivalente.

Fluxo:

~~~text
claim da ocorrência
→ validar Plano/Programação/tenant/estado
→ criar ou localizar occurrence key
→ criar exatamente uma OS
→ registrar histórico/auditoria/outbox aplicável
→ avançar cursor somente com correspondência comprovada
~~~

A implementação física da ocorrência, índice único, cursor e versão é **IMPLEMENTATION-DEPENDENT** e será definida na modelagem.

## 17. Ativos

Decisões **CLOSED**:

- Ativo é a entidade estrutural; Equipamento é classificação/tipo;
- identificador interno é estável e código humano é único por tenant;
- novo padrão conceitual de código é AT-00001; códigos legados são preservados na migração;
- Ativo possui estado cadastral Ativo, Inativo ou Baixado;
- condição operacional é Operacional, Operação parcial, Em manutenção ou Fora de operação;
- hierarquia pai/componentes preserva tenant e impede ciclos;
- cada componente mantém identidade, histórico e relações próprios;
- Local e Centro de Custo são conceitos independentes;
- prontuário técnico agrega relações autorizadas com Solicitações, OS, preventivas, inspeções, documentos, localização, componentes, garantia e Fornecedores;
- condição operacional pode receber atualização autorizada e sinalização derivada, sem confundir dado persistido com alerta;
- especificações flexíveis precisam de validação/estrutura suficiente quando forem consultáveis.

Regra de herança de Local na hierarquia e profundidade física máxima são **IMPLEMENTATION-DEPENDENT**. QR Code e importação são V2 Complementar. O QR, se implementado, aponta para rota segura e não concede acesso.

## 18. Fornecedores

Decisões **CLOSED**:

- Fornecedor é a entidade canônica; “Prestador” não permanece como entidade paralela final;
- suporta PF/PJ, múltiplos tipos, especialidades, múltiplos contatos e documentos;
- status: Ativo, Inativo e Bloqueado;
- Fornecedor Bloqueado não é selecionável para novas operações, mas permanece no histórico;
- pode se relacionar a OS, Ativos e Planos;
- contato de Fornecedor não é automaticamente usuário autenticado;
- eventual acesso externo exige vínculo explícito e arquitetura futura própria;
- documentos usam metadados no banco e objetos no Storage;
- avaliações avançadas e portal externo são futuros.

Dados V1 válidos serão objeto da Etapa 10; este documento não define ETL nem mapeamento automático.

## 19. Checklists

Decisões **CLOSED**:

- modelos reutilizáveis têm itens ordenados, tipo de resposta, obrigatoriedade, instruções e status;
- associações podem existir com categoria, Ativo, Plano ou OS conforme regra;
- respostas iniciais incluem feito/não feito, conforme/não conforme, sim/não, texto, número e observação;
- evidências podem ser exigidas por item conforme contrato;
- ao instanciar um checklist em OS, a versão aplicável é preservada;
- uma OS concluída mantém snapshot imutável do checklist usado e das respostas;
- editar o modelo não reescreve execuções históricas;
- checklist obrigatório incompleto impede conclusão;
- respostas, evidências e conclusão preservam tenant, autoria e rastreabilidade.

O formato físico do snapshot é **IMPLEMENTATION-DEPENDENT**.

## 20. Storage, Arquivos e Evidências

Decisões **CLOSED**:

~~~text
Storage object != database metadata
~~~

- Storage guarda bytes; banco guarda identidade, tenant, entidade pai, finalidade, nome, tamanho, tipo, integridade, autor, estado e rastreabilidade;
- bucket/key não são autorização suficiente;
- objetos tenant-owned não são públicos por padrão;
- acesso de leitura é contextual e URLs assinadas são curtas, específicas e não tratadas como payload persistente comum;
- upload usa protocolo reserve/finalize;
- associação à entidade só existe após finalize válido;
- exclusão é controlada, auditável e coerente com retenção/histórico;
- quota bloqueia novos uploads quando excedida sem bloquear a operação sem arquivo;
- varredura/validação adicional pode compor o pipeline conforme risco e provider.

### 20.1 Reserve

Reserve valida capacidade inicial, cria identidade de upload e limita tenant, entidade pai, finalidade, tamanho/tipo declarados, bucket/key e validade. Reserve não garante autorização até o fim.

### 20.2 Finalize

Decisão **CLOSED — STO-01**:

Finalize reautoriza obrigatoriamente:

- ator/contexto;
- tenant;
- entidade pai;
- estado;
- action;
- quota;
- bucket/key;
- identidade exata do objeto;
- tamanho;
- tipo efetivo permitido;
- integridade necessária.

Perda de autorização entre reserve e finalize pode impedir a associação. Objeto órfão não se torna evidência válida; limpeza posterior deve ser idempotente e operar por autoridade técnica limitada.

~~~text
reserve autorizado
→ upload ao destino restrito
→ inspeção dos fatos reais do objeto
→ finalize com reautorização completa
→ metadata associada
→ audit/history/outbox aplicável
~~~

Quantidade final de buckets é **PROVIDER-DEPENDENT**.

## 21. Auditoria

Decisões **CLOSED**:

- auditoria é rastreabilidade técnica/administrativa, não feed de usuário;
- registra tenant quando aplicável, ator, autoridade, contexto, target, entidade, registro, ação, timestamp, correlação e antes/depois ou diff seguro quando relevante;
- mudanças de Perfil, permissão, override, Equipe, usuário, convite, bloqueio, inativação, entitlement, configuração, Global Admin e operações destrutivas excepcionais são auditadas;
- commands críticos escrevem auditoria na mesma transação da mudança;
- eventos de auditoria são append-only para atores comuns;
- falha ao registrar auditoria obrigatória aborta o command;
- payloads evitam secrets, tokens, conteúdo excessivo e dados pessoais desnecessários;
- leitura da auditoria possui capability própria e não é concedida por acesso ao registro operacional.

Retenção exata e requisitos legais são **LEGAL/RETENTION-DEPENDENT**.

## 22. Histórico Operacional

Decisões **CLOSED**:

- histórico descreve o que aconteceu ao registro para pessoas autorizadas;
- inclui evento, ator, data/hora, motivo e relações relevantes;
- antes/depois é incluído quando útil e seguro;
- é append-only para usuários comuns;
- transições críticas escrevem histórico na mesma transação;
- histórico não substitui auditoria;
- histórico não recebe texto humano livre como substituto de comentário;
- o histórico de uma entidade relacionada não amplia acesso à entidade de origem;
- snapshots concluídos não são reescritos por alterações em cadastros/modelos.

## 23. Comentários

Decisões **CLOSED**:

- comentário é comunicação humana;
- MVP inclui comentários em Solicitações e OS;
- comentário possui tenant, entidade pai, autor, timestamp, texto e estado necessário;
- criar, visualizar, editar quando permitido e excluir/inativar são actions próprias;
- comentário não altera estado por si só;
- menção ou novo comentário pode produzir notificação, sem transformar comentário em notificação;
- comentário não substitui motivo estruturado, serviço executado, resposta de checklist, histórico ou auditoria;
- renderização é segura contra XSS;
- alteração ou remoção autorizada preserva rastreabilidade quando aplicável.

## 24. Notificações

Decisões **CLOSED**:

- central interna de notificações é obrigatória no MVP;
- notificação é evento relevante para um destinatário, não condição operacional;
- possui destinatário, título/mensagem segura, tipo, severidade, entidade/link, timestamp e estado Lida/Não lida;
- ações incluem marcar uma, várias ou todas como lidas;
- geração decorre de evento persistido/outbox quando vinculada a command;
- destinatários são calculados a partir de fatos autoritativos;
- conteúdo não revela registro ou campo sem acesso;
- abertura do link reautoriza o acesso atual;
- revogação de acesso pode tornar a notificação inacessível/neutralizada sem reabrir o registro;
- agrupamento e deduplicação evitam repetição indevida.

Fechamento da Etapa 9B:

- e-mails transacionais de Auth são obrigatórios quando aplicáveis;
- e-mail operacional de eventos de domínio é futuro, não requisito do MVP;
- WhatsApp e push são futuros.

## 25. Alertas Funcionais

Decisões **CLOSED**:

- alerta é condição que exige atenção, não mensagem entregue;
- exemplos: OS atrasada, preventiva próxima/atrasada, Ativo fora de operação, documento crítico, falha operacional relevante e armazenamento no limite;
- severidade nunca é comunicada apenas por cor;
- alertas respeitam tenant, permission, scope e projeção;
- Visão Geral pode exibir alertas acionáveis sem duplicar a entidade de origem;
- notificações podem anunciar mudança de alerta, mas os dois conceitos permanecem separados;
- deduplicação impede duplicatas contínuas da mesma condição.

Persistência calculada, materializada ou híbrida é **IMPLEMENTATION-DEPENDENT**. Alertas documentais avançados são V2 Complementar.

## 26. Processamento Assíncrono

Decisões **CLOSED**:

- eventos assíncronos originados por mutation usam outbox persistido na mesma transação;
- cada job possui tipo/version, identidade, tenant quando aplicável, referência à origem, tentativas, estado e idempotência;
- handlers são allowlisted e versionados;
- worker relê a origem e não confia no payload como autoridade;
- retries têm backoff e não duplicam efeitos;
- falhas persistentes ficam observáveis e recuperáveis;
- processamento concorrente usa claim, lease/fencing ou conditional write equivalente;
- resultado e telemetria são persistidos na medida necessária;
- dados sensíveis no payload são minimizados.

Pipeline oficial:

~~~text
commit de domínio + outbox
→ claim condicionado
→ handler allowlisted
→ releitura da origem
→ tenant e schema/version confirmados
→ capability técnica fixa
→ efeito idempotente
→ conditional write/fencing
→ resultado e telemetria
~~~

Provider e topologia de worker são **PROVIDER-DEPENDENT**.

## 27. Global Admin

Decisão **CLOSED — PLAT-01**:

Global Admin é função de plataforma, não Perfil comum de tenant. Usa commands de plataforma dedicados.

É proibido:

- endpoint comum com bypass flag;
- Perfil tenant temporário;
- impersonação silenciosa;
- union cross-tenant por padrão;
- bypass genérico para facilitar desenvolvimento.

Ações tenant-targeted exigem:

- platform capability;
- target tenant explícito;
- motivo quando aplicável;
- command limitado ao caso de uso;
- reautorização;
- auditoria com ator, contexto, autoridade e target.

Impersonação, se algum dia necessária, exige decisão explícita futura; não está implícita nesta baseline. A UI de plataforma e a UI tenant não compartilham autorização por conveniência.

## 28. Service Role e Autoridade Técnica

Decisão **CLOSED — TECH-01**:

service_role é credencial privilegiada capaz de bypass de RLS. Seu uso é somente server-side e técnico. Nunca é enviada ao navegador, incluída em bundle, persistida em cliente, registrada em log ou utilizada como substituto de um command autorizado.

Worker autorizado segue:

~~~text
outbox/job persistido
→ handler allowlisted
→ releitura da origem
→ tenant confirmado
→ schema/version validado
→ capability técnica fixa
→ conditional write/fencing
→ idempotência
→ resultado/telemetria
~~~

O payload do job não é autoridade. A capability técnica é fixa por handler/processo e limitada ao efeito necessário. Quando o provider permitir, devem ser usadas credenciais/processos adicionais separados por classe de responsabilidade, reduzindo blast radius.

Toda operação técnica preserva correlação e target. Bypass de RLS não significa bypass de invariantes.

## 29. UI e Capabilities

Decisões **CLOSED**:

- a UI pode esconder, desabilitar ou explicar ações com base em capabilities efetivas;
- CWPermissionGuard ou equivalente é mecanismo de UX, não segurança;
- menu depende de contexto, entitlement e capabilities, mas sua ocultação não autoriza nem protege dados;
- carregamento de rota revalida sessão/contexto e lida com sem permissão/inexistente;
- seletores retornam apenas opções que o usuário pode consultar e usar no command;
- ação habilitada ainda pode falhar se autorização, estado ou versão mudar;
- a UI trata conflito, perda de permissão e sessão expirada sem afirmar sucesso;
- campos sensíveis podem ter capabilities/projeções distintas da visibilidade da linha;
- status e severidades têm texto/ícone/semântica, nunca só cor.

Os componentes compartilhados devem receber contratos de capability e estado; não devem codificar Perfil como autorização.

## 30. Cache e Sessão

Decisão **CLOSED — UI-01**:

Query keys incluem as dimensões relevantes:

~~~text
principal/context
+ tenant
+ resource/query
+ filters
+ sensitive projection, quando aplicável
~~~

Logout, bloqueio detectado e troca de contexto:

- impedem novas queries do contexto antigo;
- cancelam requests inflight quando possível;
- invalidam ou removem cache sensível;
- limpam estado visual e seleções;
- descartam URLs assinadas e capabilities derivadas antigas;
- não exibem dados anteriores durante a transição.

Não se persiste indiscriminadamente payload tenant-owned nem signed URLs em localStorage. Persistência cliente exige classificação, necessidade, prazo, isolamento e limpeza explícitos. Tokens seguem o mecanismo seguro da stack e não são copiados para caches de aplicação.

Cache server-side é **DEFERIDO**. A estratégia/biblioteca cliente é **IMPLEMENTATION-DEPENDENT**, mas as chaves e regras de invalidação são invariantes.

## 31. Contrato de Erros

Decisões **CLOSED**:

- erros têm código estável, categoria, mensagem segura, correlation ID quando disponível e detalhes de campo somente quando apropriado;
- categorias mínimas: validação, não autenticado, não autorizado, inexistente, conflito/versão, estado inválido, limite/quota, indisponibilidade, rate limit e erro interno;
- mensagens ao usuário não incluem stack, SQL, policy, nomes internos sensíveis, tokens ou dados de outro tenant;
- logs contêm contexto técnico mínimo necessário e correlação, não a mensagem sensível exibida/recebida de forma indiscriminada;
- commands não retornam sucesso antes do commit;
- falhas assíncronas não são mascaradas como sucesso final.

Anti-enumeration é contextual:

- em fronteira pública ou quando distinguir existência revelaria recurso sem acesso, a resposta não confirma se o registro existe;
- dentro de contexto já autorizado, UX pode distinguir inexistente de sem permissão quando essa distinção não ampliar informação;
- login, convite, recuperação, IDs de registros, Storage e Global Admin recebem análise específica;
- códigos internos podem diferenciar causas nos logs sem expô-las ao cliente.

Mapeamento exato para HTTP/PostgREST/UI é **IMPLEMENTATION-DEPENDENT**.

## 32. Observabilidade

Decisões **CLOSED**:

- logs estruturados, métricas e correlação cobrem queries críticas, commands, jobs, Storage e releases;
- correlation ID atravessa request, transação, outbox e worker quando aplicável;
- registrar tenant técnico/target apenas de modo necessário e protegido;
- nunca registrar secrets, tokens, service_role, signed URLs completas, senhas, conteúdo integral de anexos ou dados pessoais sem necessidade;
- payloads de formulário, comentários, descrições e before/after não são despejados indiscriminadamente;
- acesso aos dados de observabilidade é restrito e auditável conforme sensibilidade;
- falhas de autorização são observáveis sem criar canal de enumeração;
- métricas de negócio respeitam isolamento e não viram exportação cross-tenant implícita;
- release/build identity integra eventos técnicos;
- alertas técnicos não se confundem com alertas funcionais do produto.

Provider de observabilidade e tracing distribuído são **PROVIDER-DEPENDENT/DEFERIDO**. Retenção é **LEGAL/RETENTION-DEPENDENT**.

## 33. Testes

Decisões **CLOSED**:

Prioridade de cobertura:

1. isolamento multiempresa;
2. autorização Resource + Action + Scope, baseline/override e antiescalada;
3. RLS por operação e helpers sem circularidade;
4. coerência de FKs compostas;
5. transitions de Solicitação e OS;
6. concorrência, versão e idempotência;
7. occurrence preventiva;
8. reserve/finalize e Storage;
9. auditoria/histórico/outbox transacionais;
10. Global Admin e technical authority;
11. regressões e fluxos principais;
12. mobile, acessibilidade e estados de UI.

Camadas:

- testes unitários para regras puras e alcance de scopes;
- testes de contrato para queries, commands e erros;
- testes de integração contra PostgreSQL/Supabase compatível;
- testes diretos de RLS/API/RPC/Storage com ao menos dois tenants e atores de capacidades distintas;
- testes de concorrência e retry;
- testes end-to-end dos fluxos críticos;
- testes de migration forward e reconstrução de ambiente descartável;
- smoke tests do mesmo artefato por ambiente.

Mocks não provam RLS nem configuração real de Storage. Não se enfraquece teste para obter pipeline verde.

## 34. Ambientes

Decisões **CLOSED**:

~~~text
LOCAL
→ TEST descartável/local/CI
→ STAGING compartilhado persistente
→ PRODUCTION
~~~

- configurações e secrets são externos ao código e específicos por ambiente;
- dados reais de produção não são copiados indiscriminadamente;
- TEST pode ser reconstruído;
- STAGING é compartilhado persistente e integra a fronteira de imutabilidade de migration;
- PRODUCTION recebe a mesma cadeia publicada;
- acesso administrativo e credenciais respeitam menor privilégio por ambiente;
- telemetria identifica ambiente e release;
- gates de promoção não são substituídos por execução local.

Hosting é **PROVIDER-DEPENDENT**.

## 35. CI/CD e Releases

Decisões **CLOSED**:

- build produz artefatos identificáveis e imutáveis;
- cada release referencia commit, build e digests;
- o mesmo artefato/digest é promovido entre ambientes;
- configurações externas podem variar; código compilado não é reconstruído por ambiente;
- migrations publicadas acompanham a identidade da release;
- promoção exige checks automatizados e gates humanos onde definidos;
- rollback/roll-forward preserva compatibilidade de schema e artefato;
- nenhum deploy faz push ou alteração remota implícita a partir de execução local não aprovada.

Sequência oficial:

~~~text
build/release
→ TEST
→ promoção dos mesmos artefatos/digests
→ STAGING
→ validação
→ declaração de RC
→ aprovação humana
→ PRODUCTION
~~~

Decisão **CLOSED — RC**: RC é uma declaração sobre os artefatos já validados em STAGING. RC não é rebuild.

O mecanismo de CI/CD e o hosting são **PROVIDER-DEPENDENT**.

## 36. Migrations

Decisões **CLOSED**:

- migrations são versionadas, ordenadas, revisáveis e reproduzíveis;
- produção não recebe alteração manual sem migration correspondente;
- schema atual deve ser reconstruível em ambiente descartável;
- migration destrutiva exige análise de dependências, preservação, compatibilidade e estratégia de rollback/roll-forward;
- não se presume banco vazio;
- código e schema são compatíveis durante a promoção;
- migrations publicadas não são reescritas; correções usam nova migration;
- dados de referência estruturais e grants/policies fazem parte da cadeia controlada quando aplicável.

Fronteira oficial de imutabilidade, ratificada na Etapa 9B:

~~~text
LOCAL
→ migration ainda pode ser ajustada antes da publicação

TEST descartável/local/CI
→ migration pode ser exercitada e reconstruída

STAGING ou qualquer ambiente compartilhado persistente
→ migration torna-se imutável

PRODUCTION
→ recebe a mesma cadeia publicada
~~~

Regra: migration publicada/promovida em qualquer ambiente compartilhado persistente torna-se imutável. TEST não congela automaticamente uma migration quando é descartável/local/CI.

## 37. Serena Pilot

Decisões **CLOSED**:

- Serena é pilot de validação/rollout, não fork arquitetural;
- regras, tabelas, rotas e código não são hardcoded para Serena Mall;
- diferenças legítimas usam configurações tenant, entitlements e cadastros autorizados;
- pilot não recebe bypass de RLS, service_role no cliente, flags escondidas de Global Admin ou migração manual irreproduzível;
- evidências do pilot alimentam validação e Etapa 10, sem promover comportamento local a regra geral;
- release identity e migrations do pilot seguem a mesma cadeia oficial;
- dados, acessos e observabilidade do pilot respeitam privacidade.

Thresholds, duração, coorte, critérios quantitativos de expansão e ordem final do rollout são **ROLLOUT-DEPENDENT**. Serena não autoriza investigação remota nesta fase.

## 38. Segurança Transversal

Decisões **CLOSED**:

- autenticação não implica autorização;
- tenant isolation é aplicada em todas as fronteiras;
- entrada é validada e saída é codificada/sanitizada conforme contexto;
- secrets nunca entram no repositório, bundle cliente ou logs;
- dependências são avaliadas por manutenção, licença, segurança, acessibilidade, tamanho e compatibilidade;
- CSP e proteções web equivalentes devem ser avaliadas na implementação;
- URLs assinadas são capacidades temporárias, não identificadores permanentes;
- upload valida fatos declarados e efetivos;
- commands sensíveis têm rate limit/abuse controls proporcionais;
- sessão bloqueada/inativa perde capacidade operacional;
- alterações de e-mail, senha, convite e recuperação usam os fluxos seguros do Auth;
- enumeração de usuários, tenants e registros é mitigada conforme contexto;
- relatórios/exportações aplicam autorização antes da geração e não ampliam projeções;
- exclusão física é excepcional, explícita e auditada;
- dependências e supply chain integram CI;
- service_role e Global Admin têm blast radius reduzido.

Revisão de segurança deve tratar ao menos: Auth, sessão, RLS, grants, functions privilegiadas, commands, FKs tenant-aware, Storage, XSS, CSRF quando aplicável, injeção, SSRF em integrações, enumeração, exports, workers, observabilidade e secrets.

## 39. Fluxos Oficiais

### 39.1 Query autorizada

~~~text
rota/ação de leitura
→ sessão e contexto atual
→ query key tenant-aware
→ parâmetros validados
→ query com projeção e paginação
→ RLS/evaluator
→ resultado autorizado
→ cache somente no contexto correspondente
~~~

### 39.2 Command crítico

~~~text
intenção do usuário + versão/idempotency key
→ contrato validado
→ transação
→ fatos relevantes + locks em ordem canônica
→ releitura autoritativa
→ tenant + entitlement + permission + scope
→ domínio + estado + versão + invariantes
→ mutation
→ auditoria + histórico + outbox
→ commit
→ resposta com release/correlation quando aplicável
~~~

### 39.3 Solicitação para OS

~~~text
Solicitação autorizada
→ command criar OS vinculada
→ coerência de tenant e estado
→ OS com 0..1 Solicitação
→ histórico/auditoria/outbox

Conclusão da OS
→ Solicitação permanece independente
→ sugestão de conclusão somente se regra e autorização permitirem
~~~

### 39.4 Validação de OS

~~~text
Em execução
→ Executor envia para validação
→ Aguardando validação
    ├→ validador autorizado aprova → Concluída
    └→ validador autorizado devolve com motivo → Em execução
~~~

### 39.5 Preventiva

~~~text
Plano
→ Programação
→ occurrence key
→ exatamente uma OS Preventiva
→ Execução
→ histórico de Plano e Ativo
~~~

### 39.6 Arquivo

~~~text
reserve
→ upload restrito
→ finalize reautoriza fatos atuais e objeto real
→ metadata vinculada
→ acesso posterior sempre contextual
~~~

### 39.7 Release

~~~text
build identificado
→ TEST
→ mesmo digest em STAGING
→ validação
→ declaração RC
→ aprovação humana
→ mesmo digest em PRODUCTION
~~~

## 40. Invariantes Globais

1. Nenhum dado, objeto, cache ou evento de tenant pode vazar para outro tenant.
2. UI, menu, filtro e rota nunca são autoridade de segurança.
3. Perfil é baseline; autorização efetiva usa combinação exata Resource + Action + Scope.
4. Override individual atua somente sobre a mesma combinação exata.
5. Scopes efetivos formam união de alcance; não existe recorte implícito entre scopes.
6. Toda relação tenant-owned preserva o tenant nas duas pontas por integridade de banco.
7. Tenant do payload não é autoridade.
8. Platform authority, tenant authority e technical authority são distintas.
9. Global Admin usa command dedicado, target explícito e auditoria.
10. service_role é somente server-side e não dispensa invariantes.
11. Command crítico reautoriza sob estado estabilizado.
12. Audit/history/outbox exigidos pela mutation são gravados atomicamente com ela.
13. Payload de job não é autoridade.
14. Query não possui efeito colateral de domínio.
15. Solicitação e OS são independentes; Solicitação tem 0..N OS e OS tem 0..1 Solicitação.
16. Concluir OS não conclui Solicitação automaticamente.
17. Preventiva não é tipo de Solicitação.
18. Plano, Programação, ocorrência, OS Preventiva e Execução mantêm identidades próprias.
19. Uma occurrence key não pode gerar duas OS.
20. Cursor preventivo não avança sem ocorrência/OS correspondente.
21. Ativo é estrutural; Equipamento é classificação/tipo.
22. Contato de Fornecedor não é usuário da plataforma.
23. Checklist concluído preserva snapshot.
24. Storage guarda bytes; banco guarda metadados e vínculo.
25. Reserve não garante autorização no finalize.
26. Comentário, histórico, auditoria, notificação e alerta não são sinônimos.
27. Dashboard, Visão Geral, relatórios, busca e notificações nunca ampliam acesso.
28. Registros operacionais históricos não são fisicamente excluídos por usuários comuns.
29. Cache inclui principal/contexto, tenant, query, filtros e projeção sensível aplicável.
30. Logout, bloqueio e troca de contexto removem estado sensível antigo.
31. Anti-enumeration é aplicada conforme o risco contextual.
32. Observabilidade não captura secrets ou payloads pessoais indiscriminadamente.
33. Migration torna-se imutável ao alcançar ambiente compartilhado persistente.
34. O mesmo artefato/digest é promovido; RC ocorre após validação em STAGING e não é rebuild.
35. A V2 inicial exige internet; offline/PWA não é implementado.

## 41. Decisões Deferidas

As decisões abaixo não estão fechadas nesta baseline:

| Tema | Classificação | Limite obrigatório |
| --- | --- | --- |
| Hosting | PROVIDER-DEPENDENT | preservar release identity, secrets por ambiente, deep links e promoção do mesmo artefato |
| Provider/topologia de worker | PROVIDER-DEPENDENT | outbox, handlers allowlisted, releitura, capability fixa, fencing e idempotência |
| Provider de observabilidade | PROVIDER-DEPENDENT | correlação, privacidade, acesso restrito e release identity |
| Quantidade final de buckets | PROVIDER-DEPENDENT | objetos privados, autorização contextual e reserve/finalize |
| Framework de feature flag | DEFERIDO | não usar flag como bypass de autorização |
| Biblioteca específica de gráficos | IMPLEMENTATION-DEPENDENT | indicadores nunca ampliam acesso |
| Biblioteca específica de PDF | IMPLEMENTATION-DEPENDENT | PDF respeita projeção, filtros, branding e autorização |
| Cache server-side | DEFERIDO | eventual cache deve ser tenant-aware e invalidável |
| Materialized views | DEFERIDO | não podem contornar RLS ou produzir dados obsoletos inseguros |
| Particionamento | DEFERIDO | somente por evidência de volume/performance |
| Tracing distribuído | DEFERIDO | privacidade e correlação permanecem obrigatórias |
| Retenções legais exatas | LEGAL/RETENTION-DEPENDENT | preservar rastreabilidade até decisão formal |
| Thresholds Serena | ROLLOUT-DEPENDENT | não hardcode e não transformar pilot em fork |
| E-mail operacional de domínio | DEFERIDO/FUTURO | não é requisito do MVP |
| WhatsApp | DEFERIDO/FUTURO | não implementar infraestrutura antecipada |
| Push | DEFERIDO/FUTURO | não implementar infraestrutura antecipada |
| Offline/PWA | DEFERIDO/FUTURO | V2 inicial exige conexão |

Também são **IMPLEMENTATION-DEPENDENT** os detalhes físicos expressamente indicados ao longo deste documento: framework/router frontend, nomes de schemas/tabelas, helpers RLS, locks, colunas de versão, idempotency store, formato de snapshot, persistência de alertas e mapeamento técnico de erros.

Concretizar uma decisão deferida exige evidência e documentação técnica, mas não reabre uma decisão CLOSED se todos os invariantes forem preservados.

## 42. Riscos Herdados da V1

Estes riscos são condicionantes arquiteturais, não plano de migração:

- SQLs manuais incrementais sem cadeia convencional de migrations nem estado remoto comprovado;
- policies, grants, triggers, buckets e Edge Function remotos possivelmente divergentes do repositório;
- FKs tenant-owned que podem não garantir coerência de Empreendimento;
- autorização distribuída entre frontend, papéis/bypasses, RPCs e policies de gerações distintas;
- update amplo de OS e autoria/transições não integralmente garantidas no banco;
- scripts globais acoplados, ordem implícita e sobrescrita de funções;
- navegação híbrida e estado global como fonte principal;
- uso amplo de innerHTML/handlers inline com superfície de XSS;
- anexos/Storage sem prova end-to-end de isolamento e autorização por objeto;
- auditoria central ausente e histórico parcial;
- notificações com estrutura parcial, sem fluxo seguro completo;
- nomenclaturas, tipos e status V1 incompatíveis com a V2;
- dados “operação/loja”, localização, categorias e especialidades com semântica ambígua;
- códigos potencialmente duplicados, inclusive Ativos;
- componentes, estados de UI, mobile e acessibilidade ad hoc;
- relatórios e Dashboard centrados em demandas;
- dados remotos, volume, qualidade e dependências ainda não verificados.

Nenhum item acima autoriza descarte, correção remota, ETL ou migration nesta fase.

## 43. Regras para Etapa 10

A Etapa 10 deve produzir o plano técnico V1 → V2 sem reabrir esta arquitetura. Deve:

1. partir de PRODUCT_SPEC.md e desta baseline;
2. confirmar o estado real do Supabase remoto antes de planejar transformação definitiva;
3. inventariar schema, RLS, grants, functions, triggers, Storage, Auth, Edge Functions, dados, volume e qualidade;
4. mapear cada dado V1 para preservar, transformar, classificar manualmente, reter como legado ou remover após validação;
5. preservar códigos e referências legadas necessárias à rastreabilidade;
6. tratar operações/lojas e outras semânticas ambíguas sem mapeamento automático;
7. definir ondas pequenas, dependências, critérios de entrada/saída, rollback/roll-forward e reconciliação;
8. construir primeiro fundação de tenant, Auth, autorização, migrations, auditoria, rotas e cadastros estruturais;
9. provar RLS, FKs compostas, Storage e antiescalada antes de migrar fluxos operacionais;
10. planejar compatibilidade entre código e schema durante transição;
11. manter V1 preservada pela tag v1-legacy e não alterar main sem decisão explícita;
12. separar dados/regras aproveitáveis da arquitetura V1 que deve ser substituída;
13. incluir Serena como pilot configurável, com thresholds definidos no rollout;
14. não selecionar itens FUTURE como dependência do MVP;
15. não executar ETL, migration destrutiva, push, deploy ou investigação remota sem autorização da etapa correspondente.

Esta seção define guardrails; não é o plano da Etapa 10.

## 44. Change Control da Arquitetura

Após este congelamento, qualquer mudança em decisão **CLOSED** deve:

1. identificar a decisão atual;
2. justificar o problema;
3. avaliar impacto funcional, segurança, dados, tenant, permissões, operações, rollout e compatibilidade;
4. propor a alteração e alternativas;
5. registrar nova decisão com status, data, responsável e consequência;
6. atualizar este documento e referências afetadas.

Codex, outros agentes e desenvolvedores não devem reinterpretar silenciosamente uma decisão CLOSED.

Decisões **IMPLEMENTATION-DEPENDENT**, **PROVIDER-DEPENDENT**, **ROLLOUT-DEPENDENT** e **LEGAL/RETENTION-DEPENDENT** podem ser concretizadas sem reabrir a arquitetura, desde que:

- não contradigam PRODUCT_SPEC.md;
- respeitem todos os invariantes CLOSED;
- registrem a escolha, evidência e consequência no artefato técnico adequado;
- não promovam item V2 Complementar ou Futuro ao MVP sem decisão de produto;
- não reduzam segurança, isolamento, rastreabilidade ou identidade de release.

Se uma nova solicitação contradizer PRODUCT_SPEC.md ou esta baseline, a divergência deve ser explícita e resolvida documentalmente antes da implementação. Ausência de detalhe não autoriza preferência pessoal nem repetição automática da V1.
