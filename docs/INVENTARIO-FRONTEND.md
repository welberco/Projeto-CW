# Inventário do frontend

Este documento caracteriza o estado encontrado na Fase 2A. Nenhum dos arquivos de produção citados foi alterado.

## 1. Ordem de carregamento

O final de `index.html` carrega os scripts nesta ordem:

1. Supabase JS 2 (CDN);
2. SheetJS/XLSX 0.18.5 (CDN);
3. jsPDF 2.5.2 (CDN);
4. jsPDF AutoTable 3.8.4 (CDN);
5. `app.js?v=38`;
6. `multiempresa.js?v=5`;
7. `arquitetura-v2.js?v=2`.

Os scripts locais são clássicos, sem módulos. Consequentemente, compartilham o mesmo ambiente global e dependem estritamente dessa ordem. `app.js` cria o cliente e a base funcional; `multiempresa.js` consome e substitui partes dessa base; `arquitetura-v2.js` consome ambas as camadas, instala o roteador e faz a última substituição de alguns pontos de extensão.

## 2. Estado e variáveis globais compartilhadas

| Origem | Globais | Consumidores principais |
| --- | --- | --- |
| `app.js` | `SUPABASE_URL`, `SUPABASE_KEY`, `initialAuthLinkType`, `passwordSetupMode`, `db` | autenticação, todos os acessos ao Supabase, `multiempresa.js`, `arquitetura-v2.js` |
| `app.js` | `STATUS`, `PRIORITIES`, `CATEGORIES`, `RESPONSIBLES`, `DEMAND_TYPES`, `MAINTENANCE_TYPES`, `TYPE_STATUS` | formulários, filtros, relatórios e renderizadores v1/v2 |
| `app.js` | `demands`, `profile`, `session`, `signupMode`, `editingId`, `permissions`, `usersCache`, `reportCache`, `activeOrgId` | autenticação, permissões, contexto da empresa, solicitações e usuários |
| `app.js` | `PERMISSION_ALIASES`, `ROLE_LABELS`, `PERMISSION_LABELS` | camadas multiempresa e v2 ampliam/consultam os mapas |
| `multiempresa.js` | `enterpriseOptions`, `authRevision` | seleção de empresa e proteção contra respostas de autenticação fora de ordem |
| `arquitetura-v2.js` | `CWV2_PAGE_SIZE`, `CWV2_ROUTES`, `CWV2_MENU`, `CWV2_PERMISSION_LABELS`, `cwMain` | roteador, menu e renderizadores v2 |
| `arquitetura-v2.js` | `cwOperationOptions`, `cwGalleryItems`, `cwGalleryIndex` | usuários/operações e modal da galeria |

Embora declarações globais com `const`/`let` nem sempre sejam propriedades de `window`, elas continuam no ambiente léxico compartilhado dos scripts clássicos e são dependências entre arquivos.

## 3. Funções globais declaradas

### `app.js`

Utilitários e permissões: `el`, `slug`, `fmt`, `open`, `today`, `localDay`, `late`, `esc`, `badge`, `role`, `hasPermission`, `canCreateAny`, `canManage`, `isAdmin`, `canManageCompany`, `canEditOrganization`, `currentOrganizationId`, `isStore`, `canEditDemand`, `applyRoleVisibility`, `refreshDemandTypeOptions`, `configureDemandType`, `toast`.

Navegação e interface v1: `show`, `metrics`, `charts`, `table`, `lists`, `render`, `cancelEdit`, `openNewDemandChooser`, `chooseNewDemandType`.

Usuários, conta e empresa: `loadUsers`, `saveUserProfile`, `createManagedUser`, `sendPasswordReset`, `loadPermissionMatrix`, `savePermission`, `openUserEditor`, `saveManagedUser`, `openMyAccount`, `showAccountView`, `saveMyAccount`, `changeMyPassword`, `openPasswordSetup`, `openOrganization`, `saveOrganizationSettings`.

Solicitações, anexos e agendamentos: `loadHistory`, `loadAttachments`, `deleteAttachment`, `loadGallery`, `openMedia`, `loadHistoryInto`, `viewDemand`, `startEdit`, `loadData`, `decideAppointment`, `openAppointmentAction`, `confirmAppointmentAction`, `uploadDemandFiles`.

Autenticação e relatórios: `loadProfile`, `migrateLocalDemands`, `enterApp`, `openReports`, `selectedReportRows`, `reportSummary`, `reportStatusSummary`, `reportFilterDescription`, `buildReportPreview`, `reportExportRows`, `exportReportXlsx`, `logoDataUrl`, `exportReportPdf`.

### `multiempresa.js`

`companyBasePath`, `requestedCompanySlug`, `setCompanyAddress`, `approvalView`, `refreshEnterpriseOptions`, `managedRequest`. O arquivo também redefine `loadProfile`, `loadData`, `enterApp`, `loadUsers`, `openUserEditor`, `loadPermissionMatrix` e `savePermission`.

### `arquitetura-v2.js`

Navegação: `cwCan`, `cwRouteState`, `cwUrl`, `cwNavigate`, `cwSetRouteFilter`, `cwActiveNav`, `cwInstallNavigation`, `cwRenderRoute`, `cwGoPage`.

Renderização: `cwDate`, `cwPager`, `cwRenderSolicitacoes`, `cwRenderSolicitacao`, `cwEditSolicitacao`, `cwGenerateOs`, `cwRenderOrdens`, `cwShowOsForm`, `cwCreateOs`, `cwRenderOrdem`, `cwConcludeOs`, `cwAcceptOs`, `cwRenderAtivos`, `cwShowAssetForm`, `cwCreateAsset`, `cwRenderPrestadores`, `cwShowProviderForm`, `cwCreateProvider`, `cwRenderCadastros`, `cwAddRegister`.

Usuários e galeria: `cwManagedRoles`, `cwRoleOptions`, `cwOperationSelect`, `cwOpenUser`, `cwLoadGallery`, `cwBytes`, `cwOpenGallery`, `cwRenderGalleryModal`, `cwGalleryMove`. O arquivo redefine ainda `show`, `loadUsers`, `loadPermissionMatrix`, `savePermission`, `loadGallery` e `enterApp`.

## 4. Sobrescritas e referências preservadas

| Nome | Nasce em | Substituições posteriores | Referência preservada |
| --- | --- | --- | --- |
| `show` | `app.js`, renderizador v1 | `app.js` adiciona conta/relatórios/organização/usuários; `arquitetura-v2.js` converte nomes antigos em rotas | `showBase` guarda a primeira versão; `cwLegacyShow` guarda a versão composta de `app.js` |
| `loadUsers` | `app.js` | duas versões adicionais em `app.js`; outra em `multiempresa.js`; versão final em `arquitetura-v2.js` | `loadUsersBasic` guarda a primeira versão, mas não foi encontrado consumidor |
| `loadGallery` | `app.js` | wrapper em `app.js`; versão final em `arquitetura-v2.js` | `renderGallery` guarda a primeira versão e é usada pelo wrapper de `app.js` |
| `viewDemand` | `app.js` | wrapper posterior em `app.js` acrescenta campos por tipo e ações de agendamento | `viewDemandBase`, ainda chamada pelo wrapper |
| `startEdit` | `app.js` | wrapper posterior em `app.js` acrescenta os campos tipados | `startEditBase`, ainda chamada pelo wrapper |
| `loadProfile` | `app.js` | `multiempresa.js` aplica aprovação, permissões e organização | nenhuma referência da versão anterior |
| `loadData` | `app.js` | `multiempresa.js` inclui filtro obrigatório por `organizacao_id` | nenhuma referência da versão anterior |
| `enterApp` | `app.js` | `multiempresa.js` inclui aprovação e revisão assíncrona; `arquitetura-v2.js` chama o roteador após a base | `cwEnterAppBase` guarda a versão de `multiempresa.js` |
| `openUserEditor` | `app.js` | `multiempresa.js`; a interface v2 passa a usar `cwOpenUser` em vez de nova sobrescrita | nenhuma referência da versão anterior |
| `loadPermissionMatrix` | `app.js` | `multiempresa.js`; `arquitetura-v2.js` | nenhuma referência anterior |
| `savePermission` | `app.js` | `multiempresa.js`; `arquitetura-v2.js` | nenhuma referência anterior |
| `enterpriseSelect.onchange` | `multiempresa.js` | wrapper em `arquitetura-v2.js` renderiza novamente a rota | `cwEnterpriseChange` guarda e chama o handler anterior |

## 5. Listeners globais e inicialização

- `app.js`: atribui `onclick` ao menu, botões de criação/edição/exclusão, modal, anexos, autenticação, recuperação e logout; atribui `onsubmit` ao formulário de demanda; registra `input`/`change` nos cinco filtros da lista.
- `multiempresa.js`: substitui handlers de autenticação; atribui handlers de aprovação, seletor e cadastro de empresa e formulários de usuário; registra `db.auth.onAuthStateChange`; inicia `db.auth.getSession().then(...)`.
- `arquitetura-v2.js`: substitui o clique do `nav`, dos botões `data-new` e do seletor de empresa; cria handlers dos formulários v2; registra exatamente um `window.addEventListener('hashchange', cwRenderRoute)` e um `popstate`.

## 6. Eventos inline

### Declarados em `index.html`

- `onclick`: fechar `demandTypeModal`, inclusive pelo fundo do modal; `sendPasswordReset`.
- `onsubmit`: `createManagedUser`, `saveManagedUser`, `saveMyAccount`, `changeMyPassword`.
- Não há `onchange` literal no HTML inicial.

### Gerados por `app.js`

- `onclick`: `saveUserProfile`, `sendPasswordReset`, `openUserEditor`, `viewDemand`, `deleteAttachment`, `openMedia`, `decideAppointment`, `openAppointmentAction`, `confirmAppointmentAction`, `chooseNewDemandType` e fechamento do modal.
- `onchange`: `savePermission`, `configureDemandType`, `buildReportPreview`.
- `onsubmit`: `saveOrganizationSettings`.

### Gerados por `multiempresa.js`

- `onclick`: `openUserEditor`.
- `onchange`: `savePermission`.

### Gerados por `arquitetura-v2.js`

- `onclick`: `cwGoPage`, `cwNavigate`, `cwEditSolicitacao`, `cwGenerateOs`, `cwShowOsForm`, `cwAcceptOs`, `cwShowAssetForm`, `cwShowProviderForm`, `cwOpenGallery`, `cwGalleryMove`.
- `onchange`: `cwSetRouteFilter` e `savePermission`.
- `onsubmit`: `cwCreateOs`, `cwConcludeOs`, `cwCreateAsset`, `cwCreateProvider`, `cwAddRegister`.

Esses eventos exigem que as funções citadas permaneçam alcançáveis globalmente.

## 7. Chamadas entre arquivos e dependências de ordem

- `multiempresa.js` usa de `app.js`: `db`, `el`, `esc`, `profile`, `session`, `permissions`, `demands`, `usersCache`, `reportCache`, `activeOrgId`, `ROLE_LABELS`, `PERMISSION_LABELS`, `isAdmin`, `canManage`, `canManageCompany`, `currentOrganizationId`, `applyRoleVisibility`, `render`, `toast`, `sendPasswordReset` e `openPasswordSetup`.
- `multiempresa.js` substitui funções que chamadas existentes de `app.js` resolvem pelo nome global no momento da execução.
- `arquitetura-v2.js` usa de `app.js`: estado de autenticação, mapas de demanda/permissão, renderizadores de relatório/empresa/conta, utilitários, dados de demandas, edição e galeria.
- `arquitetura-v2.js` usa de `multiempresa.js`: `managedRequest`, contexto de organização, a versão multiempresa de `enterApp` e o handler do seletor.
- `app.js` pressupõe que `window.supabase`, XLSX e jsPDF foram carregados antes. Os exportadores dependem das bibliotecas CDN apenas quando acionados.
- Inverter a ordem dos scripts locais causa referências ausentes ou captura da implementação errada.

## 8. Fluxo completo da navegação

1. `app.js` declara o primeiro `show`, responsável por ativar seções v1.
2. `showBase = show` preserva essa primeira implementação.
3. Ainda em `app.js`, `show` é substituída: delega telas comuns a `showBase` e trata conta, relatórios, organização e usuários.
4. Depois de `multiempresa.js`, `arquitetura-v2.js` captura essa versão composta em `cwLegacyShow`.
5. A versão final de `show` traduz nomes antigos pelo mapa e chama `cwNavigate`; nomes sem mapeamento são enviados a `cwLegacyShow`.
6. `cwNavigate` monta `#/rota?consulta` por `cwUrl`. Se o hash mudar, atribui `location.hash`; se já for idêntico, chama `cwRenderRoute` diretamente.
7. A alteração do hash dispara o único listener `hashchange`, que chama `cwRenderRoute`.
8. `cwRenderRoute` bloqueia renderização sem perfil aprovado/ativo, resolve rota/lista/detalhe, ativa a seção e o menu e chama o renderizador correspondente.
9. `dashboard` usa `cwLegacyShow('dashboard')`; `solicitacoes/nova` usa `cwLegacyShow('nova')`. As demais rotas seguem o mapa abaixo.

Fluxo resumido: `show` final → mapa de compatibilidade → `cwNavigate` → alteração do hash → `hashchange` → `cwRenderRoute`. Dentro do caminho legado: `cwRenderRoute` → `cwLegacyShow` → `show` composto de `app.js` → `showBase` quando aplicável.

## 9. Mapa de compatibilidade e renderizadores

| Nome antigo/rota | Destino | Renderizador atual | Dependência v1 |
| --- | --- | --- | --- |
| `dashboard` | `dashboard` | `cwLegacyShow('dashboard')` | sim: métricas, gráficos e seções v1 |
| `demandas` | `solicitacoes` | `cwRenderSolicitacoes` | usa estado/utilitários de `app.js`, mas markup principal é v2 |
| `nova` | `solicitacoes/nova` | `cwLegacyShow('nova')` | sim: formulário e submissão v1 |
| `detalhes` | sem rota direta; fallback legado | `cwLegacyShow('detalhes')` | sim; ainda alcançado por fluxos legados |
| `usuarios` | `usuarios` | `loadUsers` final de `arquitetura-v2.js` | usa autenticação, cache e `managedRequest` anteriores |
| `minhaConta` | `conta` | `openMyAccount` | sim |
| `relatorios` | `relatorios` | `openReports` | sim |
| `organizacao` | `empresa` | `openOrganization` | sim |
| — | `solicitacoes/:id` | `cwRenderSolicitacao` | usa `demands`, `canEditDemand`, `startEdit` e galeria |
| — | `ordens-servico` e `ordens-servico/:id` | `cwRenderOrdens`/`cwRenderOrdem` | não usa tela v1 |
| — | `calendario` | seção estática criada pela v2 | não |
| — | `ativos` | `cwRenderAtivos` | não |
| — | `prestadores` | `cwRenderPrestadores` | não |
| — | `cadastros` | `cwRenderCadastros` | não |
| — | `suporte` | seção estática criada pela v2 | não |

O menu ativo de detalhes é normalizado por `cwActiveNav`: qualquer `solicitacoes/...` ativa `solicitacoes`, e qualquer `ordens-servico/...` ativa `ordens-servico`. Filtros são mantidos em `URLSearchParams`; `cwSetRouteFilter` remove `pagina` antes de navegar.

## 10. Candidatos a código obsoleto

| Candidato | Classificação | Justificativa |
| --- | --- | --- |
| Primeiras versões sobrescritas de `loadUsers` em `app.js` | PRECISA DE TESTE | Não são a implementação final, mas uma delas é preservada em `loadUsersBasic`; é necessário provar que essa referência não tem consumidor dinâmico/inline. |
| `loadUsersBasic` | PRECISA DE TESTE | Não foi encontrada chamada nos quatro arquivos, porém é global e pode ser usada externamente; confirmar no navegador antes de remover. |
| Versões de `loadProfile`, `loadData`, `enterApp`, `openUserEditor`, `loadPermissionMatrix` e `savePermission` substituídas sem referência | PRECISA DE TESTE | A análise estática indica substituição antes da interação, mas a inicialização e callbacks globais precisam ser caracterizados antes da remoção. |
| `renderGallery` e o wrapper intermediário de `loadGallery` | PRECISA DE TESTE | O wrapper é substituído pela v2; a referência preservada deixa de aparecer no fluxo final, mas galeria e exclusão de anexos são sensíveis. |
| `showBase` | COMPATIBILIDADE TEMPORÁRIA | Continua sendo chamada por `cwLegacyShow` para dashboard, nova solicitação e fallback de telas antigas. |
| `cwLegacyShow` | COMPATIBILIDADE TEMPORÁRIA | É a ponte explícita da v2 para renderizadores v1 ainda ativos. |
| `viewDemandBase` e `startEditBase` | AINDA UTILIZADO | Os wrappers finais de `viewDemand` e `startEdit` chamam diretamente essas referências. |
| `cwEnterAppBase` | AINDA UTILIZADO | A versão final de `enterApp` delega à implementação multiempresa antes de renderizar a rota. |
| `cwEnterpriseChange` | AINDA UTILIZADO | O handler final do seletor chama o handler preservado antes de renderizar novamente. |
| Handlers de navegação atribuídos em `app.js` | COMPATIBILIDADE TEMPORÁRIA | `cwInstallNavigation` substitui o menu, mas os handlers participam da interface antes da v2 e devem ser removidos junto da consolidação. |
| Seções v1 `dashboard`, `nova`, `minhaConta`, `relatorios`, `organizacao` e `detalhes` | AINDA UTILIZADO | Todas continuam acessíveis direta ou indiretamente pela camada v2. |
| `CATEGORIES` e `RESPONSIBLES` | NÃO DETERMINADO | O uso atual aparenta ser residual, mas os valores podem alimentar formulários ou integrações construídas dinamicamente; requer busca e validação específicas. |
| Listener `popstate` | AINDA UTILIZADO | A URL por empresa usa History API; voltar/avançar precisa solicitar nova renderização. |
| Eventos inline | COMPATIBILIDADE TEMPORÁRIA | Continuam sendo gerados e executados; só podem ser removidos com delegação de eventos equivalente e testes. |

Nenhum candidato foi removido ou marcado como `REMOVÍVEL AGORA` nesta fase: os pontos mais prováveis ainda exigem teste adicional ou têm dependência explícita.

## 11. Riscos para a Fase 2B

- Capturar a versão errada de `show` ou `enterApp` altera autenticação e navegação.
- Remover um nome global quebra eventos inline somente no momento da interação.
- Consolidar `loadData` sem preservar o filtro de `organizacao_id` compromete o isolamento multiempresa.
- Duplicar `hashchange` causa renderizações e consultas repetidas.
- Transformar o redirecionamento de rota desconhecida pode criar ciclo de hash.
- Migrar dashboard ou nova solicitação exige reproduzir integralmente os efeitos de `cwLegacyShow`, inclusive menu, título e formulários.

## Resultado da Fase 2B

### Estrutura anterior e estrutura consolidada

Antes da Fase 2B, `app.js` declarava `show`, preservava-a em `showBase` e depois sobrescrevia `show`. A arquitetura v2 capturava essa segunda versão em `cwLegacyShow` e sobrescrevia `show` novamente. A resolução, o menu, os filtros e a renderização estavam distribuídos entre várias funções.

Depois da consolidação:

1. `app.js` declara `showLegacyBase`, responsável apenas pelas seções básicas da interface antiga;
2. `showLegacyView` explicita a seleção dos renderizadores legados;
3. `show` é declarado uma única vez e delega a `cwNavigateLegacy` quando a arquitetura v2 está disponível;
4. `CWRouter` centraliza estado, URL, resolução, navegação, filtros, paginação, menu ativo, renderização e instalação;
5. `CW_LEGACY_ROUTE_ALIASES` documenta a tradução dos nomes antigos;
6. `cwNavigate`, `cwSetRouteFilter` e `cwGoPage` apenas delegam ao controlador.

`showBase` e `cwLegacyShow` foram removidos. Não há nova sobrescrita de `show`.

### Registro declarativo

`CW_SCOPES` registra `core`, `shared` e `module`. `CW_MODULES` registra somente `manutencao` como módulo funcional. `CW_ROUTES` descreve as rotas estáticas, enquanto `CW_DYNAMIC_ROUTES` resolve `solicitacoes/:id` e `ordens-servico/:id`, aceitando apenas inteiros positivos.

| Escopo | Rotas |
| --- | --- |
| `core` | `dashboard`, `empresa`, `conta`, `suporte` |
| `shared` | `ativos`, `prestadores`, `cadastros`, `relatorios`, `usuarios` |
| `module/manutencao` | `solicitacoes`, `solicitacoes/nova`, `solicitacoes/:id`, `ordens-servico`, `ordens-servico/:id`, `calendario` |

Financeiro, Compras, Orçamento e Diário de Obras permanecem apenas como previsão documental. Nenhuma estrutura funcional desses módulos foi criada.

### Compatibilidade e telas legadas

As URLs públicas permanecem inalteradas. A rota técnica `#prestadores` continua válida; não existe `#fornecedores`. O termo visível passou a ser **Fornecedores**, mas tabela, consultas, permissões, funções e relacionamentos continuam usando `prestadores`. Um marcador oculto mantém compatibilidade com a caracterização anterior sem exibir o nome antigo.

Continuam legados e explicitamente registrados:

- Dashboard → `showLegacyView('dashboard')`;
- Nova solicitação → `showLegacyView('nova')`;
- Minha Conta → `openMyAccount()`;
- Relatórios → `openReports()`;
- Empresa → `openOrganization()`;
- Grupos e Usuários → `loadUsers()`.

`cwNavigateLegacy` preserva os aliases `dashboard`, `demandas`, `nova`, `usuarios`, `minhaConta`, `relatorios` e `organizacao`. Nomes fora do mapa são delegados explicitamente a `showLegacyView`.

### Listeners e riscos restantes

`CWRouter.install()` é idempotente e instala um listener `hashchange`, um `popstate` e um handler delegado no menu. Chamadas repetidas não duplicam esses listeners nem o handler do menu.

Riscos e candidatos para a Fase 2C:

- versões sobrescritas de `loadUsers` e `loadUsersBasic`: **PRECISA DE TESTE**;
- wrappers intermediários de galeria: **PRECISA DE TESTE**;
- `cwEnterAppBase` e `cwEnterpriseChange`: **AINDA UTILIZADO**;
- renderizadores legados listados acima: **AINDA UTILIZADO**;
- eventos inline: **COMPATIBILIDADE TEMPORÁRIA**;
- nomes técnicos `prestadores`: **COMPATIBILIDADE TEMPORÁRIA**;
- handlers antigos substituídos durante o carregamento: **PRECISA DE TESTE**.

A migração técnica de `prestadores` para `fornecedores` exige fase própria, incluindo banco, RLS, relacionamentos e compatibilidade de URLs. Ela não deve ser misturada à remoção de código obsoleto.
