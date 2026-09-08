# GAP Analysis V1 × V2

> Documento oficial de consolidação. Baseado no `PRODUCT_SPEC.md`, no inventário técnico da V1 e nas etapas aprovadas do GAP Analysis. A V1 é evidência de dados, regras e referências históricas; não é a base arquitetural a ser simplesmente expandida.

## Status do GAP Analysis

| Etapa | Situação |
| --- | --- |
| Etapa 1 — Fundação | APROVADA |
| Etapa 2 — Manutenção | APROVADA |
| Etapa 3 — Recursos Compartilhados | APROVADA |
| Etapa 4 — Experiência e Informação | APROVADA |
| Etapa 5 — Consolidação Final | APROVADA |

**Status para próxima fase: PRONTO PARA ARQUITETURA TÉCNICA V2.**

## 1. Resumo Executivo

A V1 é uma aplicação estática HTML/CSS/JavaScript integrada ao Supabase, com módulos legados e incrementais coexistindo. Ela contém dados, fluxos e padrões úteis — especialmente a separação inicial entre Solicitação e OS, o vínculo por organização, anexos privados, históricos de demanda, paginação incremental e exportação — mas sua estrutura técnica não atende à fundação necessária para a V2.

A V2 preservará regras de negócio e dados aproveitáveis, mas substituirá a navegação híbrida, o acoplamento de scripts globais, o estado global como fonte principal, a autorização baseada em papel/bypass e as políticas ou relações sem coerência tenant explícita. Segurança, isolamento multiempresa, autorização no backend/banco e rastreabilidade têm precedência sobre reaproveitamento de interface.

As prioridades consolidadas são:

- **P0:** fundação de tenant, autenticação, autorização por recurso/ação/escopo, auditoria, rotas como padrão arquitetural, coerência tenant, RLS/Storage e cadastros estruturais necessários ao núcleo.
- **P1:** fluxos completos do MVP de Solicitações, OS, Planos, Calendário, Ativos, Fornecedores, mídia, checklist, notificações, Visão Geral, Dashboard básico e Relatórios/PDF de OS.
- **P2:** capacidades complementares, como busca global, relatórios e dashboards avançados, QR Code, importações e gestão documental/alertas avançados.
- **FUTURE:** cobrança, checkout, portal externo de fornecedor, WhatsApp/push, offline e demais itens explicitamente fora da V2 atual.

## 2. Estrutura Consolidada do Produto

```text
CW ERP
├── Núcleo
│   ├── Visão Geral
│   ├── Dashboard
│   ├── Empresa
│   ├── Minha Conta
│   ├── Notificações
│   └── Suporte
├── Recursos Compartilhados
│   ├── Ativos e Equipamentos
│   ├── Fornecedores
│   ├── Cadastros
│   ├── Relatórios
│   └── Usuários e Permissões
└── Módulos
    └── Manutenção
        ├── Solicitações
        ├── Ordens de Serviço
        ├── Planos de Manutenção
        └── Calendário
```

Histórico, comentários, auditoria, mídia, alertas, autorização e estados de interface são recursos transversais: não pertencem a um item isolado de menu. Calendário é uma visualização de entidades de origem, não uma entidade operacional. Visão Geral é operacional e acionável; Dashboard é analítico; Relatórios são análise filtrável e exportável.

## 3. Fundação e Multiempresa

**[CONFIRMADO V1]** `organizacoes` vincula registros ao tenant e há RLS, helpers e contexto por slug, mas a V1 tem SQL incremental sem migrations convencionais, políticas remotas não comprovadas e FKs que não asseguram coerência entre tenants.

**[REQUISITO V2 / DECISÃO APROVADA]** Cada cliente CW é um Empreendimento (tenant). Usuário comum pertence a um tenant; Administrador Global CW é função de plataforma. Unidades internas não devem criar tenants automaticamente: devem usar Locais, Centros de Custo, Setores e Equipes.

**[CONSOLIDAÇÃO]** **REFATORAR**, P0. O tenant deve existir inequivocamente em UI, backend, banco, RLS e Storage. Toda relação tenant-owned deve impedir associação entre empreendimentos distintos. Global Admin requer exceção explícita, mínima e auditada.

**[INCERTEZA]** O repositório não confirma o estado de RLS, grants, triggers, buckets, Edge Function nem a ordem efetivamente aplicada no Supabase remoto.

## 4. Autenticação

**[CONFIRMADO V1]** Há Supabase Auth, login/logout, sessão, recuperação/troca de senha, perfil vinculado e Edge Function administrativa para usuários. O fluxo atual convive com regras e papéis legados.

**[REQUISITO V2]** Não há cadastro público. Convites são administrativos; usuário tem status Ativo, Bloqueado ou Inativo; troca de e-mail e redefinição de senha devem respeitar autorização e rastreabilidade. Global Admin não é perfil do tenant.

**[CONSOLIDAÇÃO]** Adaptar a integração básica de Auth e ciclo de sessão; **REFATORAR** gestão de identidade/status e fluxos administrativos, P0. Bloqueio e inativação não apagam histórico.

## 5. Autorização e Permissões

**[CONFIRMADO V1]** `permissoes_perfis`, `hasPermission()`, RPCs e RLS coexistem com ações/papéis de gerações diferentes e bypass para gestor/administrador. A interface não é uma fronteira de segurança suficiente.

**[REQUISITO V2 / DECISÃO APROVADA]** Autorização efetiva é `Usuário + Tenant + Recurso + Ação + Escopo`, com Perfil como baseline e override individual quando aplicável. Escopos: Próprios, Atribuídos, Equipe e Todos do tenant.

**[CONSOLIDAÇÃO]** **SUBSTITUIR** o modelo de papel como autorização absoluta e **CRIAR NOVO** enforcement coerente no backend/banco, RLS e UI, P0. Gestor autorizado só pode conceder autoridade que também possui; permissões reservadas à CW não são delegáveis. `CWPermissionGuard` ou equivalente melhora UX, mas nunca autoriza sozinho.

## 6. Rotas

**[CONFIRMADO V1]** Há navegação por views legadas e hash routing incremental. Algumas listas e registros têm rota, mas há páginas sem deep link individual e refresh depende do comportamento de hosting/roteamento.

**[REQUISITO V2]** Páginas e registros relevantes têm URL própria, deep link, refresh, back/forward, nova aba e filtros relevantes em URL; autenticação e permissão permanecem aplicadas.

**[CONSOLIDAÇÃO]** **SUBSTITUIR** o modelo híbrido, P0. “Rotas próprias P0” significa definir cedo o padrão arquitetural e assegurar deep link, refresh, histórico do navegador e autorização. Não significa implementar antecipadamente todas as rotas: cada rota funcional é construída junto do respectivo domínio.

Mapa mínimo conceitual:

```text
/visao-geral                 /solicitacoes              /solicitacoes/novo
/solicitacoes/:id            /ordens-servico            /ordens-servico/novo
/ordens-servico/:id          /planos                    /planos/:id
/calendario                  /ativos                    /ativos/novo       /ativos/:id
/fornecedores                /fornecedores/novo         /fornecedores/:id
/usuarios                    /usuarios/novo             /usuarios/:id
/cadastros                   /relatorios                /empresa
/minha-conta                 /suporte
```

## 7. Solicitações

**[CONFIRMADO V1]** `demandas` foi ampliada em direção a Solicitação, com código, status, prioridade, anexos, histórico, filtros e criação de OS. Persistem nomenclatura, tipos e transições legados.

**[REQUISITO V2]** Tipos oficiais: Manutenção Corretiva, Solicitação de Serviço, Agendamento de Serviço e Inspeção/Vistoria. Status: Registrada, Em análise, Programada, Em andamento, Concluída, Cancelada e Rejeitada. Prioridades: Baixa, Normal, Alta e Urgente. Preventiva não é tipo de Solicitação.

**[CONSOLIDAÇÃO]** **REFATORAR**, P1. Preservar dados, código sequencial por tenant e relação com OS; adaptar filtros e mídia; criar categoria/subcategoria, Local, Centro de Custo, Setor/Equipe, Ativo, comentários, motivos e scopes. **REMOVER** Preventiva como tipo de Solicitação.

## 8. Ordens de Serviço

**[CONFIRMADO V1]** Há OS manual, vinculada à solicitação ou plano, com arquivos, materiais/custos, histórico e RPCs de geração/conclusão/aceite. Status, update amplo, autoria e papéis de executor/validador são incompletos.

**[REQUISITO V2]** Origem Manual, Solicitação ou Preventiva; tipos Corretiva, Preventiva, Inspeção/Vistoria e Serviço; status Rascunho, Aberta, Programada, Em execução, Pausada, Aguardando validação, Concluída e Cancelada. Responsável é distinto de Executor; há múltiplos executores, equipe, fornecedor, checklist, evidências, pausa/retomada, validação, materiais, custos e PDF.

**[CONSOLIDAÇÃO]** **REFATORAR**, P1, sobre uma fundação P0 de autorização, auditoria e coerência tenant. Transições críticas devem ser aplicadas fora da UI; validação deve ser por permissão, com devolução motivada e opção tenant-level para exigir validação e impedir autovalidação.

## 9. Relação Solicitação × OS

**[CONFIRMADO V1]** A OS possui referência opcional e única à solicitação; OS avulsa já existe. Há fluxo opcional de encerramento associado.

**[DECISÃO APROVADA]** Solicitação `1 → 0..N OS`; OS `→ 0..1 Solicitação`. Concluir OS não conclui automaticamente a Solicitação. Quando a última OS aberta for concluída, o sistema pode sugerir conclusão ao usuário autorizado.

**[CONSOLIDAÇÃO]** **MANTER** a independência e a cardinalidade conceitual; **REFATORAR** integridade, auditoria e permissões, P1.

## 10. Planos de Manutenção

**[CONFIRMADO V1]** `planos_manutencao` relaciona Ativo, periodicidade, próxima execução, prestador e executor; existe geração parcial de OS programada.

**[REQUISITO V2]** Plano, Programação, OS Preventiva e Execução são conceitos separados. O básico inclui Ativo, periodicidade, responsável/equipe, checklist, programação, próxima execução, geração de OS e histórico.

**[CONSOLIDAÇÃO]** **REFATORAR**, P1. Preservar a intenção de periodicidade e vínculo com Ativo; separar os conceitos e tratar automações/recorrências complexas como P2. Scheduler físico permanece decisão de arquitetura.

## 11. Calendário

**[CONFIRMADO V1]** Há estrutura/tela incremental, sem calendário operacional completo.

**[REQUISITO V2]** Visão temporal de OS programadas, Agendamentos aprovados e atividades de Plano, com dia/semana/mês, filtros, links à origem, reprogramação autorizada e auditoria.

**[CONSOLIDAÇÃO]** **CRIAR NOVO**, P1. Não criar base operacional duplicada; alterações atualizam a entidade de origem.

## 12. Ativos

**[CONFIRMADO V1]** `ativos` contém código `EQP-0001`, nome, categoria textual, local textual/operação, fabricante, modelo, serial, aquisição, garantia, valor, JSON de especificações, ativo-pai, flag ativo, autoria, timestamps e arquivos. Há criação/listagem básica, sem prontuário completo ou navegação hierárquica.

**[REQUISITO V2]** Ativo é estrutural; Equipamento é classificação/tipo. Código humano conceitual `AT-00001`, UUID interno e preservação de códigos legados. O Ativo tem hierarquia, Local, Centro de Custo, estado cadastral (Ativo/Inativo/Baixado), condição operacional (Operacional/Operação parcial/Em manutenção/Fora de operação), especificações por tipo e prontuário técnico.

**[CONSOLIDAÇÃO]** **REFATORAR**, P1. Preservar dados técnicos úteis e relações existentes; substituir a identificação ambígua por conceito de código único por tenant, sem reinício anual que gere colisão visível. `ativo_pai_id` é base conceitual aproveitável, mas exige coerência tenant, prevenção de ciclos, profundidade/navegação e regra de herança de Local a definir na arquitetura. Condição operacional deverá ser conceitualmente mista: editável por autorização e passível de sinalização derivada de OS, sem definir mecanismo final agora.

Especificações JSON são **ADAPTAR**: preservam flexibilidade, mas precisam de conceito estruturado de características por tipo para consulta, validação e unidade quando necessário. O prontuário técnico e os vínculos completos a Solicitações, OS, Planos, documentos e Fornecedores são P1.

## 13. Fornecedores

**[CONFIRMADO V1]** `prestadores` suporta PF/PJ, tipo próprio/terceirizado, documento, um contato, especialidades textuais, status ativo e documentos; pode vincular OS e Planos.

**[REQUISITO V2]** Fornecedor é a entidade canônica para serviços, materiais, assistência, locação, fabricação, consultoria e relações comerciais. Suporta PF/PJ, dados comerciais, múltiplos contatos, múltiplos tipos, especialidades associáveis à taxonomia, documentos e status Ativo/Inativo/Bloqueado.

**[CONSOLIDAÇÃO]** **SUBSTITUIR** Prestador como entidade canônica por Fornecedor, P1. Preservar dados válidos com transformação. Contato não é usuário autenticado; eventual usuário externo é vínculo explícito e opcional. Bloqueado permanece no histórico e não pode ser escolhido em novas operações.

## 14. Usuários

**[CONFIRMADO V1]** Há listagem, criação/edição administrativa, ativação/bloqueio e matriz por papel via Edge Function/RPC, com limitações de escopo, papéis e rastreabilidade.

**[REQUISITO V2]** Cadastro somente administrativo por convite; status Ativo/Bloqueado/Inativo; tenant único para usuário comum; dados de perfil, setor, equipes, permissões e escopos; Global Admin separado.

**[CONSOLIDAÇÃO]** **REFATORAR**, P0. Convite, edição, bloqueio, inativação, troca de e-mail e senha devem ser ações explicitamente autorizadas e auditadas. Exclusão física é excepcional quando houver histórico.

## 15. Cadastros

**[CONFIRMADO V1]** Existem operações/lojas, prioridades, naturezas, tipos de serviço e centros de custo, em diferentes graus de estrutura e UI. Não há cadastros completos para Locais, Setores, Equipes, Tags, Unidades, motivos, tipos de documento ou modelos de checklist.

**[REQUISITO V2]** Gerais: Locais, Centros de Custo, Setores, Equipes, Tags e Unidades de Medida. Manutenção: Categorias/Subcategorias, Motivos de Pausa/Cancelamento/Rejeição, Tipos de Documento e Modelos de Checklist.

**[CONSOLIDAÇÃO]**

- **CRIAR NOVO** Locais hierárquicos, Setores e Equipes; Setores são fundação estrutural P0 com início simples, sem criar complexidade de autorização sem necessidade. Equipes são P0 porque suportam atribuição, escopo Equipe e autorização operacional.
- **ADAPTAR** Centros de Custo, independente de Local, com código, nome, status e hierarquia opcional.
- **REFATORAR** tipos/naturezas em Categorias/Subcategorias reutilizáveis, P0 estrutural. Isto significa estrutura, administração e seeds mínimos aprovados — não uma taxonomia extensa antecipada.
- **CRIAR NOVO** motivos estruturados, tipos de documento e modelos de checklist, P1.
- **CRIAR NOVO** Tags, P2, como classificação transversal controlada e nunca substituto de campos estruturados.
- Unidades de Medida permanecem **P2**; um conjunto mínimo pode ser antecipado a P1 se materiais de OS ou especificações estruturadas do MVP o exigirem. Isso não promove o cadastro avançado inteiro a P1.

Operações/lojas exigem classificação manual por significado: podem representar Local, Centro de Custo, unidade, vínculo organizacional ou outro conceito. Não há mapeamento automático aprovado.

## 16. Mídia

**[CONFIRMADO V1]** `cw-anexos` e anexos de demanda oferecem upload múltiplo de imagem/vídeo, metadados, URL assinada, preview/lightbox e exclusão; `cw-arquivos`, `ativo_arquivos`, `prestador_documentos` e arquivos de OS existem parcialmente. Logos usam bucket próprio.

**[REQUISITO V2]** Padrão compartilhado para Solicitação, OS, Ativo, Fornecedor, Plano e Empresa, com metadados, autoria, MIME, tamanho, legenda, preview, download, exclusão controlada, contexto/evidência, histórico, permissão e uso móvel.

**[CONSOLIDAÇÃO]** **ADAPTAR** a base de upload, URLs assinadas e galeria; **CRIAR NOVO** padrão transversal, P1, sem decidir Storage físico. Autorização não pode derivar apenas do caminho do objeto.

## 17. Checklist

**[CONFIRMADO V1]** Não há modelo compartilhado e snapshot imutável completo; há apenas estruturas parciais relacionadas à OS/Plano.

**[REQUISITO V2]** Modelos com itens ordenados, tipo de resposta, obrigatoriedade e instruções; associação a categorias, Ativos, Planos ou OS; respostas/evidências; snapshot imutável na OS concluída.

**[CONSOLIDAÇÃO]** **CRIAR NOVO**, P1, com dependência das categorias e das regras de conclusão/validação de OS.

## 18. Histórico

**[CONFIRMADO V1]** Há `historico_demandas` com triggers e UI; `historico_ordens_servico` existe, mas sua escrita e exibição não estão comprovadas de ponta a ponta.

**[REQUISITO V2]** Histórico operacional compartilhado exibe evento, ator, data/hora, alteração, antes/depois quando relevante, motivo, origem e entidade relacionada.

**[CONSOLIDAÇÃO]** **ADAPTAR** o valor de histórico de demanda e **CRIAR NOVO** padrão compartilhado, P1. Histórico é distinto de comentário e auditoria.

## 19. Comentários

**[CONFIRMADO V1]** Não há recurso de comentários como comunicação humana separado do histórico/observações.

**[REQUISITO V2]** Comentários inicialmente em Solicitações e OS, com autor, data/hora, texto e permissões.

**[CONSOLIDAÇÃO]** **CRIAR NOVO**, P1. Não usar comentários para substituir campos estruturados ou eventos de histórico.

## 20. Auditoria

**[CONFIRMADO V1]** Não existe auditoria central com tenant, ator, entidade, registro, ação, antes/depois, data/hora e contexto para atos administrativos e operacionais.

**[REQUISITO V2]** Auditar permissões, perfis, overrides, convites, bloqueio/inativação, Global Admin, tenant, configurações e operações destrutivas excepcionais, além de eventos operacionais sensíveis.

**[CONSOLIDAÇÃO]** **CRIAR NOVO**, P0. Auditoria é técnica/administrativa e não é substituída pelo histórico operacional.

## 21. Notificações

**[CONFIRMADO V1]** Há tabela `notificacoes` e políticas de leitura/atualização no SQL, mas não há gerador de eventos comprovado, sino, central, listagem ou marcação de leitura na UI.

**[REQUISITO V2]** Canal principal é sino interno; eventos incluem atribuição, nova OS, validação pendente, devolução, comentário relevante, atraso, programação próxima e, quando aplicável, documentos. Devem ter destinatário, leitura, severidade, link e autorização.

**[CONSOLIDAÇÃO]** **CRIAR NOVO**, P1, preservando a ideia de notificação persistente somente após revisão de segurança. E-mail apenas quando aplicável; WhatsApp e push são FUTURE.

## 22. Alertas

**[CONFIRMADO V1]** Não há mecanismo transversal de alertas; dashboard e toasts não resolvem condições persistentes.

**[REQUISITO V2]** Alerta é condição que exige atenção (OS atrasada, preventiva próxima/atrasada, documento vencendo, Ativo fora de operação, falha de scheduler, armazenamento cheio), distinto de notificação. Severidades: Info, Atenção e Crítico; nunca apenas por cor.

**[CONSOLIDAÇÃO]** **CRIAR NOVO**, P1 para condições operacionais essenciais; alertas/documentos avançados são P2. Persistido, calculado ou híbrido é decisão de arquitetura.

## 23. Visão Geral

**[CONFIRMADO V1]** O dashboard legado agrega contadores e listas de demandas; não oferece contexto personalizado de trabalho.

**[REQUISITO V2]** Painel operacional acionável: atribuídos a mim, em execução, aguardando minha validação, atrasos, próximos, alertas e atividade recente, sempre dentro do escopo permitido.

**[CONSOLIDAÇÃO]** **SUBSTITUIR**, P1, depois de autorização, OS, Planos e alertas mínimos. Não fechar widgets finais nesta fase.

## 24. Dashboard

**[CONFIRMADO V1]** Há contadores, distribuição e recentes limitados às demandas.

**[REQUISITO V2]** Painel analítico com indicadores, status, prioridades, evolução, preventivas, atrasos, desempenho operacional e filtros que respeitam tenant, permissões e escopos.

**[CONSOLIDAÇÃO]** **REFATORAR**, P1 para dashboard básico; avançados são P2. Indicadores não podem ampliar acesso.

## 25. Relatórios

**[CONFIRMADO V1]** Relatório de demandas com filtros, cache local, XLSX/PDF no navegador, branding, logo, paginação e dados de empresa; não há motor compartilhado nem PDF individual completo de OS.

**[REQUISITO V2]** Mecanismo `Fonte → Permissões → Filtros → Colunas → Indicadores → Prévia → PDF/XLSX` para Solicitações, OS, Planos, Ativos e Fornecedores. PDF individual de OS é obrigatório; relatórios salvos/agendados e layouts avançados são complementares.

**[CONSOLIDAÇÃO]** **SUBSTITUIR** o relatório específico como solução final e **ADAPTAR** exportação/branding úteis, P1. PDF individual de OS é **CRIAR NOVO**, P1. Exportação nunca amplia autorização.

## 26. Empresa

**[CONFIRMADO V1]** Dados básicos de organização e logo são editáveis; não há preferências, manutenção, módulos, limites, uso ou status comercial estruturados.

**[REQUISITO V2]** Configurações: Dados Gerais, Identidade Visual, Preferências e Manutenção; Assinatura: Plano, Módulos/Recursos, Usuários e Armazenamento.

**[CONSOLIDAÇÃO]** **ADAPTAR** dados gerais e branding, P1. Configurações de manutenção são **CRIAR NOVO**, P1: validação de OS exigida (padrão sim), autovalidação (padrão não), descrição de execução, motivos de cancelamento e devolução obrigatórios. Capacidade interna de entitlement é P0/P1 conforme sua dependência; experiência comercial avançada é P2 e billing/checkout é FUTURE.

## 27. Minha Conta

**[CONFIRMADO V1]** Atualiza nome, e-mail, senha e alguns dados de conta, mas não exibe informações efetivas de tenant, perfil, equipes ou permissões.

**[REQUISITO V2]** Nome, e-mail, telefone/avatar quando aplicável, senha, preferências, tenant, perfil, equipes e permissões efetivas. O próprio usuário não altera tenant, perfil, permissões ou equipes.

**[CONSOLIDAÇÃO]** **ADAPTAR**, P1, respeitando autorização e auditoria para mudanças sensíveis.

## 28. Suporte

**[CONFIRMADO V1]** Tela estática de ajuda/contato.

**[REQUISITO V2]** Ajuda básica no MVP; Central de Ajuda, FAQ e ticket estruturado são complementares. Ticket de suporte não é Solicitação de Manutenção.

**[CONSOLIDAÇÃO]** **ADAPTAR** ajuda básica, P1; ticket/central estruturada, P2.

## 29. Busca Global

**[CONFIRMADO V1]** Não há infraestrutura transversal de busca global; buscas atuais são locais e, muitas vezes, em memória.

**[REQUISITO V2]** Busca futura em Solicitação, OS, Ativo, Fornecedor, usuário e Plano, respeitando tenant, recurso, permissão e escopo.

**[CONSOLIDAÇÃO]** **CRIAR NOVO**, P2. Arquitetura de busca permanece pendente.

## 30. Componentes Transversais

| Componente conceitual | Responsabilidade | Prioridade | Consumidores |
| --- | --- | --- | --- |
| CWPermissionGuard | UX coerente para autorização já decidida | P0 | Todos os módulos |
| CWUserSelector | seleção considerando tenant/status/permissão/escopo | P0 | Solicitações, OS, Planos, Usuários |
| CWStatusBadge | status, prioridade, condição e severidade acessíveis | P0 | Todos os domínios |
| CWMediaManager | upload, preview, download, metadados, legenda e estados | P1 | Solicitações, OS, Ativos, Fornecedores, Planos, Empresa |
| CWDataTable | colunas, ações, loading, vazio, erro e responsividade | P1 | Listagens |
| CWFilters | filtros estruturados, URL e limpeza | P1 | Listagens, Dashboard, Relatórios |
| CWHistory | eventos operacionais | P1 | Solicitações, OS, Ativos, Planos |
| CWChecklist | modelos, respostas e evidências | P1 | OS e Planos |
| CWCalendar | visões e links para fontes | P1 | Manutenção |
| CWConfirmDialog | ações críticas e motivos | P1 | Todos os domínios |
| CWNotifications | sino, lista, leitura e links | P1 | Núcleo |
| CWReport | fontes, filtros, prévia e exportação | P1 | Relatórios |

Os nomes são conceituais; tecnologia, biblioteca e implementação permanecem decisões de arquitetura.

## 31. Estados de UI

**[CONFIRMADO V1]** Loading, vazio e erro são locais e inconsistentes; sem permissão, inexistente, conexão indisponível, sucesso e falha não têm padrão comum.

**[CONSOLIDAÇÃO]** **CRIAR NOVO** padrão P0 para carregando, vazio, vazio por filtro, erro, validação, sem permissão, inexistente, conexão indisponível, sucesso, falha de ação, upload e processamento. Diferenciar falha de rede, validação, inexistência e acesso negado.

## 32. Mobile

**[CONFIRMADO V1]** CSS responsivo, sidebar recolhível, grids e overflow de tabelas existem, mas fluxos densos e administrativos não foram concebidos para jornada móvel completa.

**[REQUISITO V2]** Fluxos críticos em celular: Solicitações, consulta e execução de OS, checklist, fotos, comentários, validação, Calendário, notificações, Visão Geral e Ativos. Administração complexa pode ser responsiva sem ser mobile-first.

**[CONSOLIDAÇÃO]** **REFATORAR**, P1. Offline é FUTURE.

## 33. Acessibilidade

**[CONFIRMADO V1]** Há labels, `required`, alguns `aria-label` e `role=status`, mas não há padrão consistente de foco, teclado, diálogos, mensagens, contraste ou status além da cor.

**[CONSOLIDAÇÃO]** **CRIAR NOVO** padrão básico P1: teclado, foco, labels, diálogos, mensagens anunciáveis, contraste, áreas de toque e rótulos/status não dependentes apenas de cor. Não se escolhe biblioteca ou nível normativo nesta etapa.

## 34. Nomenclatura

| Termo V1 ou ambíguo | Termo oficial preliminar V2 | Observação |
| --- | --- | --- |
| Demanda | Solicitação | Termo de UI e negócio |
| Prestador | Fornecedor | Entidade canônica compartilhada |
| EQP | AT | Código humano de Ativo; legado é preservado na migração |
| Média | Normal | Prioridade oficial |
| Aceite | Validação de conclusão | Fluxo de OS |
| Técnico | Executor | Papel de atuação em OS; não necessariamente perfil |
| Organização | Empreendimento / tenant | Empreendimento é termo de negócio; tenant pode ser técnico interno |
| Empresa | Empresa | Área de configuração do Empreendimento |
| Operação / Loja | Não definido automaticamente | Classificar dados antes da migração |

Perfil, Setor, Equipe, Local e Centro de Custo não são sinônimos e não devem ser usados como substitutos entre si.

## 35. Exclusão e Retenção

**[DECISÃO APROVADA]** Registros com referência ou histórico operacional relevante não são fisicamente excluídos por usuários comuns. Preferir:

| Recurso | Tratamento preferencial |
| --- | --- |
| Ativo | Inativar ou Baixar |
| Fornecedor | Inativar ou Bloquear |
| Usuário | Bloquear ou Inativar |
| Equipe, Setor, Local, Centro de Custo, Categoria | Inativar quando referenciado |
| Solicitação / OS | Cancelar conforme regra de negócio |
| Mídia/documento | Exclusão controlada, justificada e auditável quando aplicável |

Exclusão física é excepcional, autorizada, auditada e precedida de análise de relações.

## 36. Segurança P0

1. Isolamento de tenant em UI, backend, banco, RLS e Storage.
2. Tenant coerente em todas as relações e escritas cross-entity.
3. Autorização no backend/banco por Recurso + Ação + Escopo; UI não é autoridade.
4. Perfis como baseline; overrides e anti-escalada com enforcement.
5. Global Admin explícito, mínimo, separado do tenant e auditado.
6. RLS por operação, sem política genérica permissiva como atalho.
7. Autorização de Storage por objeto/contexto, não somente por caminho.
8. `SECURITY DEFINER` mínimo, com validação de tenant/autorização e grants revisados.
9. Transições críticas de OS e autoria aplicadas fora do frontend.
10. Renderização segura contra XSS; não adotar `innerHTML`/handlers inline como padrão.
11. Auditoria de mudanças administrativas e operacionais sensíveis.
12. Relatórios, notificações, URLs assinadas e APIs respeitam o mesmo escopo de acesso.
13. Testes diretos de API/RPC/RLS/Storage entre tenants, incluindo FKs e objetos.

## 37. Dívida Técnica que Não Deve Migrar

- Scripts globais, dependência da ordem de scripts e sobrescrita de funções.
- Estado global como fonte principal e navegação híbrida DOM/hash.
- `innerHTML` amplo e handlers inline como padrão de UI.
- Permissões apenas no frontend, bypass por gestor/admin e papéis legados como autorização absoluta.
- SQL manual acumulativo sem migrations reproduzíveis; policies `FOR ALL` sem desenho por operação.
- Relações sem coerência tenant explícita, update amplo de OS e autoria não garantida no banco.
- Tipos/status/nomenclaturas legados, Preventiva como Solicitação e Prestador como entidade canônica.
- Carregamento integral de listas, filtros somente em memória e componentes/tabelas/modais duplicados.
- `alert`, `confirm` e `prompt` como padrão de fluxo crítico.
- Dashboard centrado apenas em demandas, relatório específico de uma entidade e toast confundido com notificação persistente.

## 38. Matriz Mestre V1 × V2

| Domínio | Elemento | V1 | V2 | Decisão | Prioridade | Dependências | Migração necessária? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Fundação | Tenant/RLS | organização e RLS parciais | isolamento integral | REFATORAR | P0 | Auth, banco, Storage | Sim |
| Fundação | Migrations | 18 SQLs incrementais | mudanças reproduzíveis | SUBSTITUIR | P0 | banco | Sim |
| Identidade | Auth/convite | Auth e Edge Function | convite e status seguros | REFATORAR | P0 | tenant, auditoria | Sim |
| Autorização | perfis/permissões | papéis/ações legados | recurso/ação/escopo/override | SUBSTITUIR | P0 | usuários, RLS | Sim |
| Navegação | rotas | views + hash parcial | URLs profundas autorizadas | SUBSTITUIR | P0 | Auth, UI | Não estrutural |
| Cadastros | equipes/setores | ausentes | estrutura operacional/organizacional | CRIAR NOVO | P0 | usuários, scopes | Sim |
| Cadastros | locais | texto/operações | hierarquia física | CRIAR NOVO | P0 | tenant | Sim |
| Cadastros | centros de custo | básico | independente e ativo/inativo | ADAPTAR | P0 | tenant | Sim |
| Cadastros | categorias | tipos/naturezas | categoria/subcategoria comum | REFATORAR | P0 | Solicitação, OS, Plano | Sim |
| Solicitações | domínio | demandas ampliadas | tipos/status oficiais | REFATORAR | P1 | cadastros, permissões | Sim |
| OS | execução/validação | parcial | fluxo completo | REFATORAR | P1 | autorização, checklist | Sim |
| Relação | Solicitação × OS | opcional/única | 1→0..N, 0..1 | MANTER | P1 | Solicitação, OS | Validar |
| Planos | preventiva | periodicidade parcial | plano/programação/OS separados | REFATORAR | P1 | Ativo, OS | Sim |
| Calendário | visão temporal | estrutura | fontes e reprogramação | CRIAR NOVO | P1 | OS, Plano, Solicitação | Não direta |
| Ativos | entidade | cadastro técnico parcial | prontuário/hierarquia/statuses | REFATORAR | P1 | cadastros, mídia | Sim |
| Fornecedores | prestadores | limitado | fornecedor canônico | SUBSTITUIR | P1 | OS, Plano, Ativo | Sim |
| Mídia | anexos | demanda funcional/parcial | padrão multi-entidade | ADAPTAR | P1 | Storage, autorização | Sim |
| Checklist | modelos/respostas | ausente/parcial | modelo e snapshot | CRIAR NOVO | P1 | OS, Plano, categorias | Sim |
| Histórico | eventos | demanda e parcial OS | padrão operacional | ADAPTAR | P1 | domínios | Sim |
| Comentários | comunicação | ausente | Solicitação/OS | CRIAR NOVO | P1 | usuários, permissão | Não |
| Auditoria | rastreabilidade | ausente | administrativa/técnica | CRIAR NOVO | P0 | Auth, autorização | Sim |
| Notificações | persistência | tabela sem fluxo | sino/eventos autorizados | CRIAR NOVO | P1 | domínios, auditoria | Validar |
| Alertas | condições | ausentes | condições/severidades | CRIAR NOVO | P1 | OS, Plano, Ativo | Não inicial |
| Visão Geral | trabalho pessoal | dashboard legado | operacional acionável | SUBSTITUIR | P1 | OS, Plano, alertas | Não |
| Dashboard | análise | demandas | indicadores multi-domínio | REFATORAR | P1 | fontes autorizadas | Não |
| Relatórios | PDF/XLSX | demandas | motor compartilhado/PDF OS | SUBSTITUIR | P1 | autorização, branding | Não |
| Empresa | configurações | dados/logo | preferências/manutenção/entitlement | ADAPTAR | P1 | tenant | Sim |
| Minha Conta | perfil | básico | preferências e acesso efetivo | ADAPTAR | P1 | usuários | Não |
| UI | componentes/estados | ad hoc | padrões compartilhados | CRIAR NOVO | P0/P1 | arquitetura UI | Não |
| Mobile/a11y | responsividade parcial | jornadas e padrão acessível | REFATORAR | P1 | UI compartilhada | Não |
| Busca/Tags/UOM | ausente | complementar | CRIAR NOVO | P2 | domínio aplicável | Conforme uso |

## 39. Matriz de Decisão

### MANTER

- Independência conceitual e cardinalidade Solicitação × OS.
- Vínculo de registros de negócio ao empreendimento como princípio.
- Ideia de códigos sequenciais por entidade/tenant, sem manter o formato ou a sequência defeituosa.
- Uso de operações de banco para concentrar regras críticas, sob novo desenho seguro.

### ADAPTAR

- Integração básica Supabase/Auth e ciclo de sessão.
- Dados gerais e logo da Empresa.
- Centros de Custo, mídia privada, histórico de demanda, paginação no banco, filtros em URL e exportação/branding.
- Minha Conta e suporte básico.
- Especificações flexíveis de Ativo e relações de plano existentes, após revisão.

### REFATORAR

- Tenant/RLS, usuários, Ativos, Solicitações, OS, Planos, Dashboard, categorias e mobile.
- Estrutura de perfis como baseline, sem carregar a matriz legada.
- Relatórios de demanda como referência para mecanismo compartilhado.
- Navegação/rotas, tabelas, filtros, badges e estados visuais.

### SUBSTITUIR

- Scripts globais, estado global e navegação híbrida.
- Autorização por papel/bypass e políticas permissivas genéricas.
- Prestador por Fornecedor canônico.
- Relatórios isolados por entidade como solução final.
- Dashboard legado dependente apenas de demandas.

### REMOVER

- Preventiva como tipo de Solicitação.
- Papéis, tipos, status e nomenclaturas legados incompatíveis.
- `confirm`/`prompt`/`alert` como padrão principal.
- Escopo baseado em operação/loja e operações/lojas como conceito polivalente sem classificação.

### CRIAR NOVO

- Equipes, Setores, Locais, comentários, auditoria, alertas, checklist, calendário, notificação interna, Visão Geral e modelo de categorias/motivos/documentos.
- Padrões de componentes, UI states, acessibilidade e autorização efetiva.
- Busca global, Tags e Unidades de Medida conforme prioridade definida.

## 40. Matriz de Prioridade

### P0 — Fundação

- Tenant/RLS/Storage e coerência cross-tenant: impedem vazamento e corrupção de dados.
- Auth, usuários e autorização Resource + Action + Scope: pré-requisitos de qualquer domínio.
- Anti-escalada, Global Admin e auditoria: protegem administração e rastreabilidade.
- Padrão arquitetural de rotas: permite deep links, refresh e autorização desde o início.
- Equipes e Setores: estrutura de atribuição/escopo; Setores começam simples.
- Locais, Centros de Custo e estrutura de Categorias/Subcategorias: cadastros que sustentam o núcleo. Categorias recebem apenas estrutura, administração e seeds mínimos aprovados.
- Estados mínimos de UI, StatusBadge, PermissionGuard e UserSelector: consistência operacional e segurança de UX.

### P1 — MVP

- Solicitações, OS, relação entre elas, Planos e Calendário.
- Ativos, Fornecedores, mídia compartilhada, checklist, comentários e histórico operacional.
- Notificações e alertas operacionais essenciais.
- Visão Geral, Dashboard básico, Relatórios compartilhados e PDF individual de OS.
- Empresa, Minha Conta, suporte básico, mobile e acessibilidade básica.
- Motivos, tipos de documento e modelos de checklist.
- Conjunto mínimo de Unidades de Medida somente se materiais de OS ou especificações estruturadas o exigirem.

### P2 — Complementar

- Busca Global, Tags, QR Code e importações.
- Dashboard/relatórios salvos, layouts, agendamento e análises avançadas.
- Alertas avançados de documentos, gestão documental avançada, Central de Ajuda/FAQ/ticket estruturado e experiência comercial avançada de assinatura.
- Cadastro avançado de Unidades de Medida, salvo o conjunto mínimo justificado em P1.

### FUTURE

- Billing/checkout, portal externo de fornecedor, WhatsApp/push, offline, sincronização offline e módulos não contratados.

## 41. Dependências entre Domínios

```text
Governança de migração e estado remoto
        ↓
Tenant / Auth / sessão
        ↓
Usuários ──→ Perfis, permissões, overrides e anti-escalada ──→ RLS/API/Storage
        ↓                                      ↓
Setores, Equipes, Locais, Centros de Custo, Categorias
        ├───────────────┬──────────────────────┤
        ↓               ↓                      ↓
     Ativos         Fornecedores          Solicitações
        ├───────────────┴───────────────┐      ↓
        ↓                               │      OS
     Planos ───────────────→ Programação ──────┤
        ↓                                      ↓
     Calendário                    Checklist / mídia / histórico / comentários
                                                ↓
                                  Notificações / alertas / Visão Geral
                                                ↓
                                  Dashboard / Relatórios / PDF de OS
```

Auditoria, rotas, estados de UI, acessibilidade e mobile atravessam toda a árvore; devem ser definidos antes de sua adoção pelos domínios, sem antecipar tecnologia.

## 42. Ordem Lógica de Construção

1. **Governança de dados e fundação:** validar inventário remoto, estratégia de migrations, tenant, Auth, usuários, RLS, Storage e auditoria.
2. **Autorização e navegação:** Resource + Action + Scope, overrides, anti-escalada, Global Admin, padrão de rotas e estados básicos de UI.
3. **Cadastros estruturais:** Setores, Equipes, Locais, Centros de Custo e estrutura de Categorias/Subcategorias.
4. **Recursos compartilhados do domínio:** Ativos e Fornecedores, com mídia e histórico reutilizáveis.
5. **Núcleo operacional:** Solicitações, OS, relação entre elas, checklist, comentários e regras de transição.
6. **Planejamento:** Planos, Programação e Calendário como visualização.
7. **Experiência e informação:** notificações, alertas essenciais, Visão Geral, Dashboard básico, Relatórios e PDF de OS.
8. **Complementares:** somente após núcleo seguro e estável.

Essa ordem reduz retrabalho porque os domínios operacionais dependem dos limites de tenant, autorização, cadastros e componentes transversais.

## 43. Classificação Preliminar de Migração

| Classe | Dados V1 | Tratamento preliminar |
| --- | --- | --- |
| A — preservar diretamente | organizações/identidade básica, logos, parte dos usuários e vínculos básicos Solicitação × OS | Preservar após validação de tenant e qualidade |
| B — preservar com transformação | perfis, usuários/status, demandas, OS, anexos, históricos, ativos, prestadores, categorias, prioridades, centros de custo, permissões, arquivos | Transformar nomenclatura, estados, relações, códigos e estrutura |
| C — exige classificação manual | operações/lojas, naturezas, especialidades textuais, dados de localização textual, dados de status ambíguos | Classificar significado e destino por tenant/dado |
| D — legado somente para histórico | papéis/ações legados, campos/transições sem equivalente V2, registros operacionais sem semântica confirmada | Reter para rastreabilidade, sem promover a regra à V2 |
| E — candidato a remoção após validação | estruturas sem writer/UI, caches, marcações técnicas ou duplicidades sem referência | Só remover após inventário remoto, referências e preservação confirmados |

Não há migração automática aprovada neste documento. Códigos `EQP-*` devem ser preservados como legado mesmo que o novo código humano seja `AT-*`.

## 44. Riscos de Migração

- Códigos potencialmente duplicados, incluindo sequência anual de ativo com código visível sem ano.
- Nomenclaturas, tipos e status legados incompatíveis com a V2.
- FKs e vínculos que podem cruzar tenants sem coerência garantida.
- Operações/lojas, locais, especialidades e categorias textuais ambíguas.
- Papéis e ações legados sem mapeamento seguro para Resource + Action + Scope.
- Anexos e objetos Storage sem confirmação de privacidade, ownership ou política efetiva.
- Histórico parcial e estruturas presentes sem writer/UI confirmados.
- SQL aplicado manualmente fora do repositório, políticas/triggers/grants remotos desconhecidos e possível divergência entre repositório e Supabase.
- Dados existentes sem UI e UI sem cobertura de todos os dados existentes.
- Edge Function publicada, seus segredos/configuração e sua versão não comprovados.

## 45. Decisões para Arquitetura Técnica V2

Esta fase deve decidir, sem reabrir regras de produto aprovadas:

- arquitetura frontend, router, estrutura de pastas, boundaries, estado e camada de acesso a dados;
- modelo físico do banco, migrations, constraints de tenant, RLS e enforcement de permissões;
- fronteiras de backend/RPC, transições críticas, Storage e padrão físico de mídia;
- implementação de auditoria, comentários, notificações, alertas e scheduler;
- contratos dos componentes conceituais, tabelas, filtros, calendário, gráficos, PDF/XLSX;
- estratégia de testes (incluindo RLS/Storage/API), deploy, observabilidade e erros;
- estratégia de migração, validação do Supabase remoto e rollback quando aplicável.

Não foram decididos aqui: framework, router concreto, biblioteca UI, state management, ORM, bibliotecas de tabela/calendário/gráficos/PDF/XLSX, arquitetura física do banco, Storage físico, layout final ou deploy.

## 46. Invariantes da V2

1. Nenhum dado ou objeto de tenant pode vazar para outro tenant.
2. UI, filtro ou ocultação de menu nunca são autoridade de segurança.
3. Todo acesso considera tenant, recurso, ação e escopo; Perfil é apenas baseline.
4. Ninguém concede autoridade que não possui, salvo capacidade explícita de plataforma.
5. Global Admin não é perfil de tenant e toda atuação em tenant é auditada.
6. Relações tenant-owned preservam coerência entre as duas pontas.
7. Solicitação e OS são independentes; uma Solicitação pode ter várias OS e OS avulsa é permitida.
8. Concluir OS não conclui automaticamente Solicitação.
9. Preventiva não é tipo de Solicitação; Plano, Programação, OS Preventiva e Execução são distintos.
10. Calendário é visualização, não entidade operacional duplicada.
11. Ativo é estrutural; Equipamento é classificação/tipo.
12. Contato de Fornecedor não é Usuário autenticado.
13. Responsável de OS não é necessariamente Executor.
14. Comentário não substitui histórico; histórico não substitui auditoria; notificação não é alerta.
15. Relatórios, Dashboard, Visão Geral, notificações e URLs de mídia nunca ampliam acesso.
16. Registros históricos não são fisicamente apagados normalmente.
17. Status, transições e motivos críticos são aplicados e auditados fora da confiança exclusiva do frontend.
18. Mídia é autorizada pelo contexto da entidade e preserva rastreabilidade.
19. Interface deve tratar loading, vazio, erro, inexistência, sem permissão e falha de ação de forma explícita.
20. Fluxos operacionais críticos devem ser realmente utilizáveis em celular; offline não é requisito da V2 inicial.

## 47. Critérios para Entrada na Arquitetura

**PRONTO.**

O produto possui regras funcionais consolidadas, inventário V1, decisões de reaproveitamento, prioridades, invariantes e dependências suficientes para a Arquitetura Técnica V2. A validação do Supabase remoto, dados e políticas vigentes é trabalho inicial obrigatório da próxima fase e da estratégia de migração; não bloqueia o início porque é uma decisão e verificação naturalmente arquitetural.

## 48. Conclusão

Este GAP Analysis oficializa a transição da V1 para uma V2 segura, modular e orientada a domínio. A próxima fase deve transformar estas decisões de produto em desenho técnico reproduzível, sem antecipar funcionalidades FUTURE e sem carregar as fragilidades estruturais da V1.
