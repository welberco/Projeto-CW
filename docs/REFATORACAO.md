# Refatoração do CW Manutenção

## Objetivo da revisão

Reduzir o acoplamento e o legado do frontend de modo conservador, tornando a navegação e as responsabilidades dos scripts explícitas, sem alterar comportamento funcional ou regras de negócio.

## Regras obrigatórias

1. A refatoração nunca deve ser feita diretamente na branch `main`; cada fase deve usar branch própria e revisão antes da integração.
2. A suíte completa deve ser executada e registrada antes e depois de cada alteração.
3. Refatoração estrutural e novas funcionalidades não podem ser misturadas no mesmo trabalho ou commit.
4. As regras de negócio existentes devem ser preservadas.
5. A integração com o Supabase, suas políticas RLS e a segurança efetiva no banco devem ser preservadas.
6. O isolamento multiempresa deve permanecer garantido no frontend e, principalmente, no banco; nenhuma refatoração pode ampliar o acesso entre organizações.
7. Código legado só pode ser removido depois de identificado, coberto por testes e substituído de forma verificável.
8. Os commits devem ser pequenos, reversíveis e limitados a uma finalidade verificável.
9. A branch deve passar por validação manual no ambiente de pré-visualização antes de ser integrada à `main`.

## Divisão da Fase 2

### Fase 2A — inventário e testes

Mapear globais, sobrescritas, listeners, eventos inline, dependências entre arquivos e o fluxo da navegação. Adicionar testes de caracterização que registrem o comportamento atual. Nesta fase nenhum legado é removido.

### Fase 2B — consolidação da navegação

Consolidar a cadeia de navegação em um controlador oficial, mantendo as rotas, permissões e telas cobertas pelos testes da Fase 2A. A fase foi implementada na branch de refatoração e aguarda a validação manual da pré-visualização.

### Fase 2C — remoção do código obsoleto

Remover apenas os trechos comprovadamente substituídos e sem consumidores, depois da consolidação e de nova validação integral dos testes.

## Linha de base da Fase 2A

Antes das alterações, `npm ci` e `npm test` concluíram com sucesso na branch `refactor/limpeza-fase-2`. A suíte inicial validou sintaxe, banco e isolamento multiempresa, interfaces v1/v2 e administração de usuários.

## Lista de verificação

- [x] Fase 2A criada a partir da Fase 1 validada.
- [x] Testes executados antes das alterações.
- [x] Globais, sobrescritas, eventos e dependências inventariados.
- [x] Navegação atual coberta por testes de caracterização.
- [x] Testes executados depois das alterações.
- [ ] Validação manual da Fase 2A antes da integração.
- [x] Fase 2B: consolidar a navegação sem alterar comportamento.
- [x] Executar a primeira validação manual da Fase 2B e registrar a regressão do menu ativo.
- [x] Corrigir e automatizar a cobertura da regressão do menu ativo.
- [ ] Repetir a validação manual da Fase 2B na nova pré-visualização.
- [ ] Fase 2C: remover somente código comprovadamente obsoleto.
- [ ] Validar manualmente e executar a suíte completa antes de integrar à `main`.

## Arquitetura modular preparada na Fase 2B

O CW passa a ser tratado arquiteturalmente como um ERP modular, sem expor módulos futuros na interface ou no banco. O registro declarativo distingue:

- `core`: Dashboard, Empresa, Minha Conta e Suporte;
- `shared`: Ativos e Equipamentos, Fornecedores, Cadastros Gerais, Relatórios e Grupos e Usuários;
- `module`: funcionalidades pertencentes a um módulo contratável.

Somente o módulo `manutencao` está registrado e ativo. Solicitações, Ordens de Serviço e Calendário pertencem exclusivamente a ele. Financeiro, Compras, Orçamento e Diário de Obras são possibilidades futuras documentadas, não implementadas e não expostas em rotas, menus, permissões, formulários ou Supabase.

O `CWRouter` é a fonte oficial para interpretar o hash, resolver rotas estáticas e dinâmicas, montar URLs, navegar, alterar filtros, paginar, ativar o menu, renderizar e instalar os listeners. Os adaptadores globais `cwNavigate`, `cwSetRouteFilter`, `cwGoPage` e `cwNavigateLegacy` permanecem finos para compatibilidade.

Todas as URLs existentes foram preservadas. `show` permanece como adaptador global único; as telas antigas necessárias são chamadas explicitamente por `showLegacyView`. Dashboard e o formulário de nova solicitação continuam usando a interface legada, assim como Minha Conta, Relatórios, Empresa e Grupos e Usuários mantêm seus renderizadores existentes.

## Fornecedores e compatibilidade técnica

A apresentação adotou **Fornecedores** no menu, títulos, mensagens e campos visíveis. Temporariamente, a rota continua `#prestadores`, a tabela continua `prestadores`, os vínculos continuam usando os nomes atuais e as funções/RPCs/policies não foram renomeadas.

> Dívida técnica: o nome técnico `prestadores` será migrado para `fornecedores` em uma fase posterior, com compatibilidade para a rota e os relacionamentos antigos.

## Itens reservados para a Fase 2C

- avaliar e remover versões antigas sobrescritas de `loadUsers` e a referência `loadUsersBasic`;
- avaliar wrappers intermediários de galeria e renderizadores antigos;
- consolidar, somente após testes específicos, outras sobrescritas globais fora da navegação;
- revisar handlers antigos substituídos durante o carregamento;
- manter eventos inline até existir uma migração comportamental coberta por testes;
- decidir a migração técnica de `prestadores` separadamente da limpeza de código.

## Checklist manual da pré-visualização

Os itens abaixo permanecem pendentes porque esta execução automatizada não acessa nem altera dados reais de produção:

- [ ] Login.
- [ ] Dashboard.
- [ ] Solicitações.
- [ ] Nova solicitação.
- [ ] Detalhes de solicitação.
- [ ] Filtros de solicitações.
- [ ] Paginação.
- [ ] Ordens de Serviço.
- [ ] Detalhes de Ordem de Serviço.
- [ ] Calendário.
- [ ] Ativos e Equipamentos.
- [ ] Fornecedores.
- [ ] Grupos e Usuários.
- [ ] Relatórios.
- [ ] Cadastros Gerais.
- [ ] Empresa.
- [ ] Minha Conta.
- [ ] Suporte.
- [ ] Voltar e avançar no navegador.
- [ ] Acesso direto por URL.
- [ ] Rota antiga `#prestadores`.
- [ ] Menu ativo.
- [ ] Troca de empreendimento.
- [ ] Perfil não aprovado.
- [ ] Responsividade básica.

## Correção pós-validação da Fase 2B

A validação manual do commit `3df4dd7` identificou uma regressão visual de gravidade média: Dashboard, Relatórios, Empresa e Minha Conta abriam corretamente, mas terminavam sem o item correspondente ativo no menu. `CWRouter.activeNav()` retornava o valor correto e o controlador aplicava `active` por `data-route`; em seguida, os renderizadores legados percorriam todos os elementos `.nav` e recalculavam o destaque por `data-view`. Como o menu instalado pela arquitetura v2 usa `data-route`, essa segunda passagem removia a classe aplicada pelo roteador.

A correção restringe a manipulação legada do menu a `.nav[data-view]`. Assim, o comportamento anterior permanece disponível antes da instalação da arquitetura v2, enquanto o menu atual, composto por elementos `data-route`, continua sob responsabilidade exclusiva do `CWRouter`. Os renderizadores legados permanecem responsáveis por exibir a seção, carregar seu conteúdo, atualizar textos próprios e fechar a barra lateral; eles não alteram mais o menu moderno.

Foram acrescentados testes comportamentais que executam a ordem real `CWRouter.render()` → renderizador da rota → renderizador legado → estado final do DOM. A suíte de navegação passou de 55 para 73 cenários e cobre as quatro rotas corrigidas, as oito rotas de controle, unicidade do item ativo, transição entre tela moderna e legada, eventos de histórico, nova execução do legado, idempotência da instalação e chamada única do renderizador.

A Fase 2C permanece bloqueada até que a nova pré-visualização seja validada manualmente por clique, acesso direto, atualização, Voltar e Avançar.
