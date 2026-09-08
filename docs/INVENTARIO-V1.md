# Inventário Técnico V1 — Consolidado

## 1. Objetivo e Escopo

Este documento registra o estado técnico encontrado na implementação V1 do CW Manutenção antes do desenvolvimento da nova V2 e antes do GAP Analysis. Ele consolida evidências presentes no repositório: frontend, scripts SQL, Edge Function, documentação e testes.

O documento descreve o que existe no código versionado; não confirma o estado efetivamente aplicado no projeto Supabase remoto. Não contém GAP Analysis, decisão de arquitetura V2 ou classificação de adequação à especificação funcional.

## 2. Stack Atual

- **Frontend:** HTML estático (`index.html`), CSS próprio (`styles.css`) e JavaScript global, sem módulos ES.
- **Backend/dados:** Supabase (Auth, PostgREST, PostgreSQL, RLS, Storage, RPCs e uma Edge Function).
- **Bibliotecas via CDN:** `@supabase/supabase-js@2`, SheetJS/XLSX, jsPDF e jsPDF-AutoTable.
- **Node/testes:** `npm test` executa checagem sintática dos três scripts principais e quatro testes `.mjs`; dependências de desenvolvimento são PGlite, JSDOM e TypeScript.
- **Edge Function:** `supabase/functions/admin-users/index.ts`, destinada às operações administrativas de usuários.
- **Não há framework, bundler, gerenciador de rotas, biblioteca de componentes nem processo de build** versionados. A aplicação pode ser servida como arquivos estáticos.

## 3. Estrutura do Repositório

```text
/
├── index.html                 # estrutura inicial, telas legadas e carregamento ordenado dos scripts/CDNs
├── styles.css                 # estilos globais e regras responsivas
├── app.js                     # autenticação, demandas legadas, mídia, histórico, relatórios e conta/organização
├── multiempresa.js            # contexto de empreendimento, usuários, aprovação e matriz de permissões
├── arquitetura-v2.js          # menu, hash routing e módulos incrementais de manutenção
├── supabase/
│   ├── *.sql                  # esquema base e alterações incrementais aplicáveis manualmente
│   └── functions/admin-users/ # Edge Function administrativa
├── tests/                     # testes Node/PGlite/JSDOM
├── README.md                  # instruções de execução/publicação, parcialmente históricas
├── AGENTS.md                  # regras de trabalho da reconstrução V2
└── PRODUCT_SPEC.md            # especificação funcional de referência da V2
```

Os SQLs não seguem o diretório/formato convencional de migrations do Supabase. Há 18 arquivos SQL no diretório `supabase`, incluindo o esquema inicial e alterações corretivas/aditivas.

## 4. Arquitetura Atual

A aplicação é uma SPA estática de JavaScript global. `app.js` cria o cliente Supabase, mantém o estado de sessão, perfil, permissões, empreendimento corrente, demandas e caches em variáveis globais. Também contém as telas e fluxos originalmente centrados em `demandas`.

`multiempresa.js` amplia o app com o seletor de empreendimento, aprovação de acesso, cadastro de empreendimento, gestão de usuários e matriz de permissões. `arquitetura-v2.js` acrescenta menu e renderização por hash, preservando e redirecionando partes das funções legadas. Os scripts dependem da ordem em `index.html`: primeiro `app.js`, depois `multiempresa.js` e, por fim, `arquitetura-v2.js`; todos compartilham o mesmo escopo global e sobrescrevem/extensões de funções existentes, como `show` e `loadGallery`.

O cliente consulta tabelas, Storage e RPCs diretamente pelo Supabase. A segurança pretendida está concentrada em RLS, funções SQL e triggers; a interface também oculta ações segundo permissões, mas isso é apenas controle de experiência.

## 5. Navegação e Rotas

### Navegação legado por views

O HTML inicial contém seções `.view` e botões `data-view` para dashboard, demandas, nova demanda, usuários e minha conta. A troca de tela é feita por funções JavaScript e classes CSS, sem carregamento de página.

### Hash routing incremental

`arquitetura-v2.js` introduz URLs `#/...`, tratamento de `hashchange`/`popstate`, parâmetros de filtro e paginação. As rotas declaradas são:

- `#/dashboard`
- `#/solicitacoes`, `#/solicitacoes/nova` e `#/solicitacoes/:id`
- `#/ordens-servico` e `#/ordens-servico/:id`
- `#/calendario`, `#/ativos`, `#/prestadores`, `#/usuarios`
- `#/relatorios`, `#/cadastros`, `#/empresa`, `#/conta` e `#/suporte`

Solicitações e OS possuem rota individual por identificador. Ativos, prestadores, planos, cadastros e usuários não possuem rotas individuais de registro no frontend encontrado. Algumas rotas são telas reais, outras são reserva de estrutura: calendário e suporte exibem conteúdo estático; não há rota própria para planos.

O encaminhamento de telas legadas para hash é parcial. O refresh preserva o hash, mas a renderização depende de sessão, perfil aprovado/ativo, scripts globais e estado carregado em memória; não há roteador independente, carregamento de dados por rota generalizado ou fallback de servidor específico além de `_redirects`. O contexto multiempresa é refletido no caminho da página pelo slug (`/.../<slug>`) e o hash continua a identificar a tela; a troca de empreendimento atualiza o caminho e recarrega os dados do contexto.

## 6. Funcionalidades Implementadas

As classificações abaixo descrevem o estado da implementação encontrada: **implementado**, **parcial**, **somente estrutura** ou **legado**.

### 6.1 Autenticação

- **Implementado:** login/logout Supabase, recuperação/definição de senha, sessão, consulta de perfil e bloqueio de perfil inativo.
- **Parcial:** fluxo de aprovação do perfil após acesso; tratamento é dependente das políticas/funções remotas.
- **Legado:** cadastro/autenticação e partes de UX preservadas de versões anteriores no mesmo `app.js`.

### 6.2 Multiempresa

- **Implementado:** `organizacoes`, vínculo em `perfis`, seletor de empreendimento, slug de URL, criação de empreendimento por RPC e consultas filtradas por `organizacao_id` no frontend.
- **Parcial:** a experiência mistura papéis legados e novos; a segurança efetiva depende da versão e ordem de execução das políticas remotas.

### 6.3 Solicitações/Demandas

- **Implementado:** cadastro, edição, listagem, busca/filtros legados, tipos de demanda, prioridade, responsável, prazo, status, agendamento, galeria e histórico da tabela `demandas`.
- **Implementado incrementalmente:** lista paginada por banco, filtros por tipo/status/período, detalhe individual e geração de OS a partir da solicitação.
- **Legado:** nomenclatura, campos e status de `demandas` convivem com a nomenclatura de solicitação; há migração opcional de itens do `localStorage`.

### 6.4 Ordens de Serviço

- **Implementado:** tabela, geração por solicitação, criação avulsa, listagem, detalhe, associação opcional a ativo/prestador, conclusão e aceite/recusa por RPC.
- **Parcial:** há fluxo de planejamento/execução/aceite, custos, materiais, arquivos e histórico no SQL, mas a interface encontrada não entrega cobertura integral desses recursos. O cancelamento e demais transições previstas por permissões não estão todos expostos de forma consistente.

### 6.5 Preventiva e Planos

- **Parcial:** `planos_manutencao`, periodicidade e a RPC de geração de OS programadas existem no SQL; o frontend cadastra plano básico associado a ativo e prestador.
- **Somente estrutura:** não há calendário operacional de preventivas, programação detalhada, detalhe de plano, checklist de execução ou fluxo completo Plano → Programação → OS → Execução na interface.

### 6.6 Ativos

- **Implementado:** tabela, código, dados básicos de fabricante/modelo/série/aquisição/garantia, vínculo opcional com ativo-pai, arquivos e associação em OS/planos.
- **Parcial:** listagem e criação básica no frontend; não há edição, detalhe, hierarquia navegável, prontuário técnico ou gestão completa de arquivos na interface.

### 6.7 Prestadores

- **Implementado:** tabela de prestadores, pessoa física/jurídica, vínculo próprio/terceirizado, contatos, especialidades, documentos e associação em OS/planos.
- **Parcial:** listagem e criação básica no frontend; documentos, edição, inativação e consulta detalhada não estão completos na interface.

### 6.8 Usuários e Permissões

- **Implementado:** perfis vinculados a Auth, papéis, aprovação, ativação/bloqueio, criação/edição via Edge Function/RPC e matriz por papel/empreendimento.
- **Parcial:** o modelo usa ações por papel e verificações de interface/RLS, mas preserva ações e papéis de gerações distintas; escopos operacionais completos não são uniformes.

### 6.9 Cadastros

- **Implementado:** operações, prioridades, naturezas, tipos de serviço e centros de custo possuem tabelas/políticas e uma tela de cadastros básicos.
- **Parcial:** não foram encontrados os cadastros completos previstos para locais, setores, equipes, tags, unidades, motivos e modelos de checklist.

### 6.10 Mídia

- **Implementado:** upload de imagens e vídeos de demandas, metadados em `anexos_demandas`, URLs assinadas, miniaturas, modal/lightbox, exclusão e histórico de anexos.
- **Parcial:** buckets e tabelas adicionais para logo, arquivos de ativo, prestador e OS existem; a interface é concentrada em anexos de demanda e logo, sem um gerenciador compartilhado completo.

### 6.11 Histórico

- **Implementado:** `historico_demandas` com trigger de alterações e triggers de anexos; leitura e exibição no detalhe de demanda.
- **Parcial:** `historico_ordens_servico` existe e é preenchido por RPCs de OS, mas a tela de OS encontrada não o exibe. Não há auditoria central completa de entidades/ações.

### 6.12 Relatórios

- **Implementado:** relatório das demandas com filtros, prévia e exportação XLSX/PDF no navegador, inclusive dados básicos e logo da organização.
- **Parcial/legado:** baseia-se em RPCs e estrutura de demandas; não há mecanismo compartilhado para todos os domínios nem relatório individual completo de OS.

### 6.13 Dashboard

- **Implementado (legado):** indicadores e listas baseados em demandas, status e prioridade.
- **Parcial:** não há dashboard operacional/analítico abrangendo OS, preventivas, ativos e demais indicadores.

### 6.14 Empresa / Minha Conta / Suporte

- **Implementado:** edição de dados básicos e logo da organização; atualização de nome/e-mail/loja e senha da conta.
- **Somente estrutura:** suporte é uma tela estática de ajuda/contato, sem chamados ou central operacional.

### 6.15 Notificações

- **Somente estrutura:** a tabela `notificacoes` e políticas de leitura/atualização existem em `arquitetura-v2.sql`.
- **Não encontrado no frontend:** central, sino, geração de eventos, listagem ou marcação de leitura.

## 7. Modelo de Dados Atual

O modelo parte de `organizacoes` como tenant e `perfis` como extensão de `auth.users`, com `organizacao_id` nos registros de negócio. O controle de papel/permissão usa `permissoes_perfis`; a versão incremental também inclui operações e associação usuário-operação.

`demandas` é a entidade original e foi ampliada para atuar como solicitação, com códigos, tipo/natureza, prioridade, responsável, situação, prazo, agendamento, centro de custo e operação. Seus anexos e histórico são tratados por `anexos_demandas` e `historico_demandas`.

`ordens_servico` possui `organizacao_id`, uma referência opcional e única a `solicitacao_id`, além de vínculos opcionais a ativo, prestador e plano. Existem tabelas dependentes para custos, materiais, arquivos e histórico. As funções permitem gerar OS de solicitação e concluir/aceitar OS; a solicitação permanece uma entidade separada, embora haja função de finalização opcional.

`ativos` possui referência opcional a ativo-pai e arquivos próprios; é relacionado a OS e planos. `prestadores` possui documentos e pode ser próprio ou terceirizado. `planos_manutencao` se vincula a ativo e prestador e armazena periodicidade/próxima execução. Cadastros auxiliares incluem `operacoes`, `usuario_operacoes`, `prioridades`, `naturezas_servico`, `tipos_servico` e `centros_custo`. `cw_sequencias` sustenta códigos por organização/entidade/período; `cw_migracoes` registra uma marca lógica no SQL, não migrations convencionais.

Há referências estrangeiras e RLS no SQL versionado, mas nem todas as FKs que ligam entidades tenant-owned impõem a mesma `organizacao_id` entre registro pai e filho. Essa coerência é relevante para o isolamento e deve ser verificada no ambiente remoto.

## 8. Supabase e Storage

- Há **18 SQLs incrementais** no repositório, executáveis manualmente e sem histórico convencional de migrations ordenadas pelo Supabase CLI.
- Os buckets citados são `cw-anexos`, `cw-logos` e `cw-arquivos`; os dois primeiros aparecem desde scripts anteriores, e `cw-arquivos` é incluído pela arquitetura incremental.
- `cw-anexos` guarda os objetos relacionados às demandas; `cw-logos` recebe identidade visual; `cw-arquivos` é previsto para arquivos de ativo, prestador e OS segundo o caminho/entidade validado pela função de Storage.
- A Edge Function `admin-users` realiza operações administrativas de usuários e depende de segredos/configuração da plataforma fora do repositório.
- As RPCs incluem, entre outras, criação/listagem de organização, gestão de perfil, dados de relatório, geração/conclusão/aceite de OS, sequência de código, criação de solicitação e geração de OS programadas.
- O SQL versionado habilita RLS em tabelas principais e define políticas para entidades e objetos Storage. Como os arquivos substituem/criam políticas ao longo do tempo, a política vigente depende da ordem e do êxito de execução no Supabase remoto.

## 9. Permissões e Segurança

### Proteções existentes

- Auth Supabase e perfil vinculado ao usuário autenticado.
- Vínculo de registros a `organizacao_id` e funções como `cw_org_atual`, `cw_acesso_org`, `cw_admin`, `tem_permissao_usuario`, `pode_visualizar_demanda`, `cw_editar_demanda` e `cw_pode_ver_os`.
- RLS e políticas para demandas/solicitações, entidades incrementais e Storage; no SQL mais recente há políticas restritivas adicionais para buckets CW.
- Upload de demanda com limite de tamanho no frontend, caminhos por demanda e URLs assinadas para visualização.
- Escape em boa parte da renderização de dados textuais por `esc` e verificações de permissão na interface.

### Riscos confirmados

- `cw_proximo_codigo` atualiza/insere a sequência com base no parâmetro de organização sem uma verificação explícita de autorização dentro da função. A RPC é chamada diretamente pelo frontend para ativos; sua segurança depende de grants e do estado efetivamente aplicado.
- As FKs de entidades tenant-owned não garantem, por si, que as duas pontas pertençam ao mesmo empreendimento (por exemplo, associações de OS, plano, ativo e prestador). RLS reduz visibilidade, mas não substitui uma regra de coerência de tenant na escrita.
- Políticas `FOR ALL` combinam leitura/escrita/exclusão para várias entidades. Para algumas delas, o `using` de leitura utiliza uma permissão mais ampla do que o `with check` de escrita; o efeito preciso precisa ser validado por operação e política remota vigente.
- A política de `cw-arquivos` no SQL incremental trata seletamente caminhos por tipo de entidade, mas usa permissões genéricas de galeria/configuração e não foi acompanhada por uma interface completa nem por testes de isolamento de objeto.
- A política de atualização de OS permite atualização ampla da linha a quem tenha `os_editar`; o modelo não restringe colunas/transições por função de executor, planejador ou validador.
- A autoria/criação de OS não exige explicitamente `criado_por = auth.uid()` na política de insert encontrada; a interface preenche o campo, mas a regra de banco é mais ampla.
- `notificacoes` permite seleção por tenant e destinatário, mas não há política de inserção nem mecanismo de geração de eventos versionado; a proteção contra vazamento via conteúdo/notificação não está demonstrada end-to-end.
- A coexistência de ações e papéis legados com ações incrementais aumenta o risco de regra não coberta, especialmente onde o frontend consulta nomes de permissão diferentes dos SQLs mais recentes.
- Foi identificado uso de inserção de HTML com interpolação em pontos da interface. Embora parte dos valores seja escapada, o padrão de `innerHTML` e handlers inline torna a superfície de XSS dependente de disciplina manual e não há uma estratégia central de sanitização.
- Não há auditoria central completa com antes/depois, ator, tenant, entidade e contexto para todas as ações administrativas e operacionais.

### Riscos dependentes do estado remoto

- Não é possível afirmar, pelo repositório, qual dos SQLs foi executado por último, se houve erros parciais, nem quais políticas foram removidas ou permaneceram ativas.
- Não é possível confirmar RLS habilitada, triggers, funções, grants, buckets privados ou política efetiva de `storage.objects` no projeto remoto.
- A segurança da Edge Function depende das variáveis, chaves, deploy e versão publicados.
- Dados remotos existentes podem conter vínculos, papéis e registros criados sob versões anteriores das regras.

## 10. Frontend e Componentes

Não há componentes encapsulados, sistema de design, tipagem de interface ou separação por módulos de domínio. A reutilização é feita por funções globais e convenções visuais.

Os padrões encontrados incluem painéis, cabeçalhos, botões primário/secundário/link, tabelas, cards, badges de status/prioridade, formulários em grade, modais e toasts. As tabelas de solicitações e OS possuem wrappers responsivos; solicitações usam filtros por selects/datas e paginação por query/range no banco. As telas legadas possuem busca/filtros e lista de demandas em memória.

Mídia usa galeria de cards, preview, URL assinada e modal próprio. Formulários e confirmações dependem de HTML inserido dinamicamente, `confirm`/`prompt` em alguns fluxos e handlers inline. Estados de carregamento, vazio e erro aparecem em várias telas, mas são implementados localmente e não de forma uniforme; não há padrão compartilhado para sem permissão, inexistente, conexão indisponível, sucesso e falha.

## 11. Responsividade e Acessibilidade

O CSS possui media queries, barra lateral recolhível e layouts adaptáveis; tabelas são envolvidas em contêiner de overflow e formulários usam grade. Demandas e anexos possuem interação viável em telas menores, mas vários fluxos novos permanecem densos, usam tabela ou dependem de ações pequenas.

O HTML inclui alguns rótulos, `required`, `role="status"` pontual e `aria-label` na matriz de permissões. Entretanto, não há evidência de auditoria sistemática de acessibilidade, gerenciamento consistente de foco em modais, suporte de teclado completo, semântica uniforme para ações dinâmicas, mensagens de erro anunciadas ou contraste/área de toque verificados. A navegação e os fluxos de OS/preventiva não foram estruturados especificamente para operação móvel completa.

## 12. Testes

Os testes versionados são:

- `tests/interface.test.mjs`: verificações da interface/base legada.
- `tests/interface-v2.test.mjs`: verificações da camada incremental de interface/rotas.
- `tests/admin-users.test.mjs`: contrato/comportamento da Edge Function administrativa.
- `tests/multiempresa.test.mjs`: cenário SQL com PGlite para partes do isolamento e permissões multiempresa.

O conjunto usa Node, PGlite e JSDOM; `npm test` também roda `node --check` em `app.js`, `multiempresa.js` e `arquitetura-v2.js`. As lacunas principais são testes contra um Supabase real com RLS/Storage, matriz completa de permissões e escopos, coerência cross-tenant de FKs, transições completas de OS, Edge Function publicada, fluxos de mídia por bucket e acessibilidade/responsividade.

## 13. Dívida Técnica

### Crítica

- Estado remoto do Supabase não reproduzível a partir de migrations convencionais e sem ordem única comprovada dos SQLs.
- Riscos de isolamento cross-tenant em relações por FK e necessidade de validação das políticas RLS efetivas.
- Regras de autorização de operações críticas distribuídas entre frontend, políticas, triggers e funções com versões sucessivas.

### Alta

- Scripts globais extensos, acoplados e dependentes de ordem; sobrescrita de funções e estado compartilhado dificultam manutenção e teste.
- Modelo de permissões/papéis e nomes de ações coexistindo entre legado e incremental.
- Política ampla de atualização de OS, ausência de restrição de autoria na inserção e cobertura insuficiente de transições.
- Superfície de XSS pela construção manual e ampla de HTML/handlers inline.
- Ausência de auditoria central e de cobertura operacional integral para histórico/notificações.

### Média

- Módulos parcialmente implementados, rotas que exibem somente estrutura e diferença entre tabelas SQL e interface entregue.
- Componentes de tabela, filtro, mídia, modal, confirmação e estados UX duplicados ou ad hoc.
- Falta de tipagem, lint, build e divisão por módulo; erros e estados de conexão inconsistentes.
- Documentação de execução/publicação parcialmente histórica e sem inventário de versão aplicada no remoto.

### Baixa

- Marcas de versão por query string nos scripts e estilos/HTML inline dispersos.
- Textos, rótulos e nomenclaturas de demanda/solicitação/empresa/organização coexistindo na interface.
- Dependência de bibliotecas CDN sem lockfile ou estratégia de empacotamento.

## 14. Reutilização Técnica

Classificação do material encontrado, sem decidir seu destino na V2:

| Item | Classe | Fundamentação observada |
| --- | --- | --- |
| Integração básica Supabase/Auth e ciclo de sessão | B | Há lógica funcional, mas está global e deve ser adaptada a uma estrutura mais delimitada. |
| Isolamento por organização e helpers SQL (`cw_acesso_org`, funções de visualização) | C | As regras e intenção são úteis; a implementação requer revisão de segurança e consolidação. |
| Dados de solicitações/demandas e histórico de demanda | C | Contêm regras/dados úteis, porém a modelagem e a interface são legadas/incrementais. |
| Fluxo de geração, conclusão e aceite de OS | C | A lógica SQL e o relacionamento são úteis, mas a cobertura de status, escopo e histórico é parcial. |
| Ativos, prestadores e planos | C | Tabelas e regras básicas úteis; UX e domínio completo precisam ser refeitos/adaptados. |
| Tabelas, filtros, paginação e badges | B | Há padrões visuais e lógica reaproveitáveis, mas não são componentes encapsulados. |
| Galeria privada de anexos de demanda | B | Upload, URLs assinadas e preview são base aproveitável; falta padronização multi-entidade. |
| Relatório de demandas PDF/XLSX | C | Exportação no navegador é útil, mas é específica de demandas e não é mecanismo compartilhado. |
| Gestão de usuários e matriz de permissões | C | Há fluxo e Edge Function, mas papéis/ações legados e riscos de autorização exigem revisão. |
| Dashboard de demandas | D | Implementação é específica e limitada ao legado. |
| Calendário, suporte e notificações de interface | D | Calendário/suporte são estrutura; notificações não possuem interface operacional. |
| CSS visual básico e layout responsivo | B | Tokens/padrões visuais podem inspirar reaproveitamento, mas não há design system. |
| `_redirects` e publicação estática | E | Valor de reutilização depende do ambiente de hosting ainda não comprovado. |

## 15. Padrões que Valem Preservar

- Separação já iniciada entre solicitação (`demandas`) e OS, com referência opcional de OS à solicitação e criação de OS avulsa.
- Vínculo explícito de registros de negócio ao empreendimento e intenção de aplicar RLS no banco.
- Códigos sequenciais por entidade/organização, históricos por demanda e geração de URLs assinadas para mídia privada.
- Uso de funções de banco para operações que precisam concentrar regra de negócio, como geração/conclusão/aceite de OS.
- Paginação no banco nas listas incrementais, filtros representados na URL e manutenção do contexto de empreendimento pelo slug.
- Exportações que incluem filtros aplicados e dados básicos da organização.
- Testes de interface e de parte do isolamento multiempresa já presentes no repositório.

## 16. Padrões que Não Devem Ser Carregados

- Acoplamento entre scripts globais, dependência implícita de ordem e sobrescrita de funções.
- Crescimento incremental por SQLs manuais sem mecanismo inequívoco de migration, ordem e estado aplicado.
- Uso de filtros/ocultação no frontend como complemento potencialmente confundido com autorização.
- Mistura de nomenclaturas, papéis, ações e regras legadas com as incrementais.
- HTML construído amplamente por concatenação/`innerHTML` com handlers inline.
- Componentes e estados de UX implementados repetidamente por tela em vez de padrões compartilhados.
- Relações tenant-owned sem garantia explícita de coerência entre organizações e políticas `FOR ALL` sem análise por ação.
- Interface que anuncia módulos reservados como se fossem rota funcional completa.

## 17. Incertezas

O repositório não comprova:

- o estado real do Supabase remoto, seus dados e a versão de cada SQL aplicada;
- a ordem completa, os resultados e eventuais falhas de execução dos SQLs;
- as políticas RLS e de `storage.objects` vigentes, inclusive políticas antigas restantes;
- triggers, funções, grants, extensões e configurações efetivamente ativas;
- privacidade/configuração final dos buckets e existência dos objetos legados;
- volume, qualidade, vínculos e necessidade de preservação dos dados legados;
- versão publicada, variáveis e segredos da Edge Function `admin-users`;
- configuração de hosting correspondente a `_redirects` e comportamento final de refresh em produção.

## 18. Mapa Final da V1

```text
CW Manutenção V1
├── Frontend
│   ├── HTML/CSS/JavaScript estático
│   ├── app.js: autenticação, demandas, mídia, histórico, relatórios
│   ├── multiempresa.js: empreendimento, usuários e permissões
│   └── arquitetura-v2.js: hash routing e módulos incrementais
├── Supabase
│   ├── Auth + perfis + organizações
│   ├── demandas/solicitações, OS, ativos, prestadores e planos
│   ├── RLS, RPCs, triggers e políticas incrementais
│   └── Edge Function admin-users
├── Storage
│   ├── cw-anexos
│   ├── cw-logos
│   └── cw-arquivos
└── Testes
    ├── interface.test.mjs
    ├── interface-v2.test.mjs
    ├── admin-users.test.mjs
    └── multiempresa.test.mjs (PGlite/JSDOM/Node)
```

## 19. Uso no GAP Analysis

Este inventário deve ser confrontado com `PRODUCT_SPEC.md`, que é a fonte funcional oficial da V2. O confronto futuro poderá classificar cada elemento inventariado como **Manter**, **Adaptar**, **Refatorar**, **Substituir**, **Remover** ou **Criar novo**.

Essa classificação não é feita neste documento.
