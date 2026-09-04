# CW ERP — PRODUCT SPECIFICATION

## CW Manutenção V2

**Especificação funcional consolidada**

**Versão de consolidação: 04/09/2026**

---

# Documento de Produto

Este documento consolida as decisões funcionais definidas para a reconstrução do CW Manutenção como primeiro módulo da plataforma modular CW ERP.

O PRODUCT_SPEC define o que o produto deve fazer, suas regras de negócio, entidades, fluxos e limites de escopo. A modelagem física de banco de dados, políticas RLS, bibliotecas, componentes técnicos e arquitetura de implementação serão especificadas posteriormente.

Princípio de desenvolvimento: segurança, isolamento multiempresa, reutilização de componentes e evolução incremental sem overengineering.

## Sumário dos Blocos

- 1. Visão do Produto e Estrutura Geral
- 2. Estrutura Funcional e Navegação
- 3. Cadastros Gerais, Cadastros de Módulo e Relação entre Entidades
- 4. Solicitações
- 5. Ordens de Serviço
- 6. Planos de Manutenção
- 7. Calendário de Manutenção
- 8. Ativos e Equipamentos
- 9. Fornecedores
- 10. Usuários, Perfis e Permissões
- 11. Cadastros
- 12. Relatórios
- 13. Visão Geral e Dashboard
- 14. Empresa
- 15. Minha Conta
- 16. Notificações e Alertas
- 17. Suporte e Ajuda
- 18. Requisitos Transversais e Escopo da V2

# 1. Visão do Produto e Estrutura Geral

CW ERP será uma plataforma SaaS modular, multiempresa e configurável. O CW Manutenção será o primeiro módulo contratado e implementado.

## 1.1 Estrutura futura

# CW ERP — PRODUCT SPECIFICATION

```text
├── Núcleo
│   ├── Dashboard
│   ├── Empresa
│   ├── Minha Conta
│   ├── Notificações
│   ├── Histórico
│   └── Suporte
├── Recursos compartilhados
│   ├── Ativos e Equipamentos
│   ├── Fornecedores
│   ├── Cadastros
│   ├── Relatórios
│   └── Usuários e Permissões
└── Módulos contratáveis
    ├── Manutenção
    ├── Financeiro
    ├── Compras
    ├── Orçamento
    └── Diário de Obras
```
## 1.2 Modelo multiempresa

- Cada cliente da CW será representado por um Empreendimento (tenant).
- Unidades físicas internas do mesmo cliente serão representadas por Locais, Centros de Custo e estruturas correlatas, e não por novos tenants.
- Cada usuário comum pertence a apenas um Empreendimento.
- O Administrador Global CW é exceção e poderá administrar múltiplos Empreendimentos.
- O isolamento deverá existir na aplicação, backend e banco de dados/RLS.
## 1.3 Modelo comercial

A arquitetura deverá permitir planos diferenciados por funcionalidades/módulos, número de usuários e armazenamento, incluindo futuramente upgrade, downgrade, suspensão e reativação.

## 1.4 Princípio de produto

O sistema deve ser genérico e configurável, evitando regras codificadas especificamente para Serena Mall ou qualquer cliente individual.

# 2. Estrutura Funcional e Navegação

```text
VISÃO GERAL
```

```text
MANUTENÇÃO
├── Solicitações
├── Ordens de Serviço
├── Planos de Manutenção
└── Calendário
```

```text
COMPARTILHADO
├── Dashboard
├── Ativos e Equipamentos
├── Fornecedores
├── Usuários e Permissões
├── Relatórios
└── Cadastros
```

```text
CONFIGURAÇÕES
├── Empresa
├── Minha Conta
└── Suporte
```

```text
CABEÇALHO
├── Busca Global (V2 Complementar)
├── Notificações
└── Usuário
```

A visibilidade do menu depende de Perfil, permissões, escopo, módulos/features habilitados e situação do Empreendimento. Ocultar menu não constitui mecanismo de segurança.

# 3. Cadastros Gerais, Cadastros de Módulo e Relação entre Entidades

## 3.1 Classes de cadastro

- Padrão Estrutural CW: regras estruturais que não devem ser livremente alteradas pelo tenant.
- Padrão CW Personalizável: valores iniciais fornecidos pela CW e adaptáveis pelo tenant; quando referenciados, priorizar inativação.
- Cadastro do Empreendimento: dados operacionais específicos do cliente.
## 3.2 Cadastros compartilhados

- Locais
- Centros de Custo
- Setores
- Equipes
- Tags
- Unidades de Medida
## 3.3 Cadastros do módulo Manutenção

- Categorias e Subcategorias de Serviço
- Motivos de Pausa
- Motivos de Cancelamento
- Motivos de Rejeição
- Tipos de Documento
- Modelos de Checklist
## 3.4 Solicitação e OS

Solicitação e Ordem de Serviço são entidades independentes. Uma Solicitação pode gerar zero, uma ou várias OS. Uma OS pode existir sem Solicitação e poderá estar vinculada a no máximo uma Solicitação.

# 4. Solicitações

A Solicitação representa uma necessidade, ocorrência ou pedido, sem significar obrigatoriamente que haverá execução formal por OS.

## 4.1 Identificação e campos

- ID anual sequencial por Empreendimento, exemplo: 2026-001.
- Data/hora, solicitante, status e última atualização.
- Tipo, categoria, subcategoria e prioridade.
- Local e Centro de Custo.
- Título e descrição detalhada.
- Setor/Equipe responsável, responsável individual e prazo previsto.
- Ativo/Equipamento opcional e OS relacionadas.
- Comentários, anexos, motivos de cancelamento/rejeição e dados de encerramento.
## 4.2 Tipos iniciais

1. Manutenção Corretiva
1. Solicitação de Serviço
1. Agendamento de Serviço
1. Inspeção / Vistoria
Preventiva não é tipo de Solicitação; origina-se de Plano/Programação e gera OS Preventiva.

## 4.3 Prioridades

- Baixa
- Normal
- Alta
- Urgente
Somente usuários autorizados definem prioridade. Toda alteração deverá ser auditada.

## 4.4 Status gerais

- Registrada
- Em análise
- Programada
- Em andamento
- Concluída
- Cancelada
- Rejeitada
Nem todo fluxo precisa percorrer todos os status. Cancelada representa uma demanda válida encerrada sem continuidade; Rejeitada representa demanda analisada e considerada imprópria, não aplicável, fora de escopo ou não autorizada.

## 4.5 Agendamento de Serviço

O Agendamento será genérico e poderá atender equipes internas, Fornecedores, terceiros, ocupantes, lojas, departamentos e demais usuários autorizados.

- Data solicitada
- Horário inicial/final
- Local
- Descrição
- Responsável pelo serviço
- Fornecedor quando aplicável
- Equipe
- Informações e documentos necessários
Fluxo possível: Registrado → Em análise → Aprovado/Rejeitado → Reagendado/Cancelado/Concluído. Agendamentos aprovados aparecem no Calendário e podem, mas não precisam, gerar OS.

## 4.6 Comentários, histórico e mídia

Comentários são comunicação humana. Histórico/Auditoria é registro automático e imutável de eventos. Anexos devem suportar múltiplos arquivos, galeria, lightbox, legendas, edição/exclusão conforme permissão, download, autor, data/hora e auditoria.

## 4.7 Listagem

- Período
- ID/texto
- Status
- Prioridade
- Tipo
- Categoria/Subcategoria
- Local
- Centro de Custo
- Solicitante
- Setor/Equipe
- Responsável
- Ativo
- Com/sem OS
- No prazo/atrasada
A tabela é prioritária no MVP. Kanban poderá ser avaliado posteriormente.

# 5. Ordens de Serviço

A OS é o registro formal do trabalho a planejar, executar, controlar e validar.

## 5.1 Identificação e origem

Numeração anual por tenant, exemplo: OS-2026-001.

- Origem Manual
- Origem Solicitação
- Origem Manutenção Preventiva
## 5.2 Tipos

- Corretiva
- Preventiva
- Inspeção / Vistoria
- Serviço
Agendamento não será tipo de OS; é uma característica temporal.

## 5.3 Campos principais

- Número, origem, tipo, status, criação e criador.
- Categoria, subcategoria, prioridade, Local e Centro de Custo.
- Título, serviço solicitado e serviço executado.
- Setor/Equipe, responsável, múltiplos executores, tipo de execução e Fornecedor.
- Prazo, data programada e horários.
- Início real, pausas, retomadas e término real.
- Solicitação e Ativo opcionais.
- Checklist, materiais, custo estimado e custo real.
- Anexos/evidências, comentários e histórico.
## 5.4 Status

- Rascunho
- Aberta
- Programada
- Em execução
- Pausada
- Aguardando validação
- Concluída
- Cancelada
## 5.5 Validação de conclusão

Quando a validação estiver habilitada, o Executor finaliza a execução e envia a OS para Aguardando validação. Usuário com permissão 'Validar conclusão de OS' poderá aprovar ou devolver.

- Aprovação: OS passa para Concluída.
- Devolução: retorna para Em execução e exige motivo obrigatório.
- O ciclo poderá ocorrer várias vezes e todos os eventos serão auditados.
- Durante Aguardando validação, campos de execução ficam essencialmente bloqueados para o Executor.
- Validação será configurável por tenant; padrão CW recomendado: obrigatória.
- Arquitetura deverá permitir impedir autovalidação conforme política.
## 5.6 Pausa

Pausa exige motivo, observação quando aplicável, usuário e datas de início/retomada.

- Aguardando material
- Aguardando Fornecedor
- Aguardando aprovação
- Aguardando acesso/liberação
- Aguardando orçamento
- Condição climática
- Outro, com justificativa
## 5.7 Execução

Tipo de execução: Interna, Fornecedor ou Mista. Responsável não é necessariamente Executor. A OS poderá ter múltiplos Executores.

## 5.8 Custos

Custo estimado e custo real serão opcionais e nunca bloquearão programação, execução ou conclusão.

## 5.9 Checklist

Modelos reutilizáveis poderão ser associados a tipo, categoria, Ativo, Plano ou OS. Respostas iniciais: feito/não feito, conforme/não conforme, sim/não, texto, número e observação.

Quando obrigatório, o checklist deverá estar completo antes da conclusão. A OS preservará snapshot do checklist utilizado.

## 5.10 Conclusão e Solicitação

OS concluída não conclui automaticamente a Solicitação. Quando todas as OS vinculadas estiverem concluídas, o sistema poderá sugerir a conclusão da Solicitação a usuário autorizado.

# 6. Planos de Manutenção

O Plano define o que deve ocorrer periodicamente. A Programação define quando ocorrerá. A OS Preventiva representa a execução.

## 6.1 Campos

- Título e descrição
- Categoria/Subcategoria
- Ativo/Equipamento
- Local
- Centro de Custo
- Equipe/Responsável
- Fornecedor opcional
- Periodicidade
- Data inicial
- Próxima execução
- Checklist padrão
- Instruções
- Prazo esperado
- Status
## 6.2 Periodicidades iniciais

- Diária
- Semanal
- Quinzenal
- Mensal
- Bimestral
- Trimestral
- Semestral
- Anual
- Intervalo personalizado
## 6.3 Geração de OS

Planos poderão gerar OS Preventivas herdando dados aplicáveis. A execução alimentará o histórico do Plano e do Ativo.

## 6.4 Escopo

V2 obrigatório: cadastro básico, vínculo com Ativo, periodicidade, responsável/Equipe, checklist padrão, programação, geração de OS, histórico básico e próxima execução. Automações e recorrências complexas são complementares.

# 7. Calendário de Manutenção

O Calendário é uma visualização temporal e não possui base operacional duplicada.

## 7.1 Fontes

- OS programadas
- Agendamentos de Serviço aprovados
- Atividades provenientes de Planos quando aplicável
## 7.2 Visões

- Dia
- Semana
- Mês
## 7.3 Filtros

- Tipo/status
- Categoria
- Local
- Centro de Custo
- Equipe
- Responsável
- Executor
- Fornecedor
- Ativo
- Origem
- Prioridade
## 7.4 Interação

Ao clicar, o usuário poderá abrir o registro de origem e, conforme permissão, reprogramar, alterar responsável, iniciar execução ou consultar Ativo. Reprogramações atualizam a entidade de origem e são auditadas.

# 8. Ativos e Equipamentos

Ativo é a entidade estrutural. Equipamento é uma classificação/tipo de Ativo.

## 8.1 Identificação

Código por tenant, exemplo: AT-00001, além de patrimônio, serial e código interno do cliente quando aplicável.

## 8.2 Dados

- Nome/descrição
- Categoria/tipo/subcategoria/tags
- Local/Centro de Custo
- Fabricante/modelo
- Especificações técnicas flexíveis
- Aquisição/garantia
- Fornecedores relacionados
- Status cadastral
- Condição operacional
- Fotos/documentos
## 8.3 Status e condição

Status cadastral: Ativo, Inativo, Baixado. Condição operacional: Operacional, Operação parcial, Em manutenção, Fora de operação.

## 8.4 Hierarquia

Ativos poderão possuir Ativo-pai e componentes/subativos, cada qual com histórico e relacionamentos próprios.

## 8.5 Histórico técnico

O Ativo deverá funcionar como prontuário técnico, consolidando alterações, Solicitações, OS, preventivas, inspeções, documentos, localização, componentes e garantia.

## 8.6 QR Code e importação

QR Code e importação XLSX/CSV são V2 Complementar. O QR deverá apontar para rota segura e respeitar autenticação/permissões.

# 9. Fornecedores

Fornecedor será entidade compartilhada para pessoas físicas ou jurídicas que forneçam serviços, materiais, assistência, locação, fabricação, consultoria ou outros.

## 9.1 Tipos

- Prestador de serviço
- Fornecedor de material
- Fabricante
- Assistência técnica
- Locador
- Consultoria
- Outros configuráveis
## 9.2 Dados e contatos

- PF/PJ
- Razão social/nome fantasia
- CPF/CNPJ opcional conforme regra
- Inscrições
- Site
- Observações
- Status
- Múltiplos contatos com finalidade Comercial, Técnico, Financeiro, Administrativo, Emergência etc.
## 9.3 Especialidades e documentos

Especialidades serão multi-seleção e poderão relacionar-se às categorias de serviço. Documentos poderão conter tipo, arquivo, número, emissão, validade e observação.

## 9.4 Status

- Ativo
- Inativo
- Bloqueado
## 9.5 Relações

Fornecedor poderá relacionar-se a OS, Ativos e Planos. O contato do Fornecedor é entidade distinta de usuário da plataforma.

## 9.6 Evoluções

Avaliação de desempenho e portal externo de Fornecedor são futuros. Gestão documental avançada e importação são V2 Complementar.

# 10. Usuários, Perfis e Permissões

## 10.1 Modelo de autorização

Autorização efetiva = Recurso + Ação + Escopo. Perfil fornece permissões padrão, mas não é a autorização final.

## 10.2 Administrador Global CW

É papel de plataforma, não Perfil comum de tenant. Poderá administrar tenants, módulos, limites e suporte; suas ações dentro de clientes serão auditadas.

## 10.3 Perfis-base

- Gestor
- Técnico / Executor
- Auxiliar
- Solicitante
## 10.4 Escopos conceituais

- Próprios registros
- Atribuídos ao usuário
- Registros das Equipes do usuário
- Todos os registros do Empreendimento
## 10.5 Permissões individuais

Usuários do mesmo Perfil poderão ter permissões diferentes. Gestor autorizado poderá ajustar permissões dentro de sua própria autoridade. Ninguém poderá conceder permissão que não possua ou que seja reservada à CW.

## 10.6 Equipes

Usuário poderá participar de múltiplas Equipes. Equipe é estrutura operacional e não Perfil.

## 10.7 Criação e status

Não haverá cadastro público. Usuário autorizado cria/convida por e-mail. Status: Ativo, Bloqueado e Inativo. Preferir inativação à exclusão quando houver histórico.

## 10.8 Tenant

Cada usuário normal pertence a apenas um Empreendimento. Essa regra deverá ser aplicada no banco/RLS e aplicação.

# 11. Cadastros

```text
CADASTROS
├── Gerais
│   ├── Locais
│   ├── Centros de Custo
│   ├── Setores
│   ├── Equipes
│   ├── Tags
│   └── Unidades de Medida
└── Manutenção
    ├── Categorias e Subcategorias de Serviço
    ├── Motivos de Pausa
    ├── Motivos de Cancelamento
    ├── Motivos de Rejeição
    ├── Tipos de Documento
    └── Modelos de Checklist
```
## 11.1 Locais

Estrutura espacial genérica e hierárquica. Tipos configuráveis como Edificação, Bloco, Pavimento, Sala, Área, Unidade, Loja etc.

## 11.2 Centros de Custo

Independentes de Local, com código, nome, descrição, hierarquia opcional e status.

## 11.3 Setores e Equipes

Setor representa divisão organizacional. Equipe representa agrupamento operacional e pode opcionalmente vincular-se a Setor.

## 11.4 Tags e unidades

Tags são classificações flexíveis controladas. Unidades terão defaults CW e poderão ser ampliadas pelo tenant.

## 11.5 Categorias e motivos

Categorias/Subcategorias serão compartilhadas pelas rotinas de Manutenção. Motivos estruturam pausa, cancelamento e rejeição.

## 11.6 Checklist

Modelos conterão nome, descrição, categoria, itens ordenados, tipo de resposta, obrigatoriedade, instruções e status. Histórico concluído usa snapshot.

## 11.7 Importação

Importação XLSX/CSV de Locais e Centros de Custo é V2 Complementar.

# 12. Relatórios

A plataforma terá mecanismo compartilhado: fonte → permissões → filtros → colunas → indicadores → prévia → PDF/XLSX.

## 12.1 Relatórios iniciais

- Solicitações
- Ordens de Serviço
- Planos/Preventivas
- Ativos
- Fornecedores
## 12.2 Formatos

Relatórios poderão ter resumo + detalhe, apenas resumo ou apenas detalhe. Todo relatório exportado deverá indicar filtros aplicados.

## 12.3 PDF

PDF terá identidade do cliente, título, período, filtros, indicadores, conteúdo, paginação, data/hora e marca CW ERP discreta.

## 12.4 XLSX

Exportações poderão conter dados estruturados e abas de Resumo, Registros e Filtros. Recursos avançados são complementares.

## 12.5 Relatório individual de OS

Deverá consolidar dados da OS, execução, responsáveis, checklist, materiais, custos quando autorizados, serviço executado, validação e opcionalmente evidências/histórico.

## 12.6 Segurança

Relatórios e exportações respeitam as mesmas permissões e RLS da aplicação. Compartilhar configuração de relatório não concede acesso aos dados.

# 13. Visão Geral e Dashboard

## 13.1 Visão Geral

Página operacional que responde: 'O que precisa da minha atenção agora?'

- Solicitações aguardando análise
- OS aguardando validação
- OS atrasadas
- OS sem responsável
- Preventivas próximas/atrasadas
- Documentos críticos
- Ativos fora de operação
- Minhas OS e atividades, conforme Perfil
Cards deverão ser acionáveis e abrir listas filtradas.

## 13.2 Dashboard

Página analítica que responde: 'Como está a operação?'

- Solicitações/OS abertas e concluídas
- OS atrasadas/pausadas/aguardando validação
- % no prazo
- Tempo médio
- Cumprimento preventivo
- Ativos fora de operação
- Documentos críticos
Gráficos poderão analisar status, categoria, Local, prioridade, corretiva x preventiva, tendência mensal, Equipe/responsável e atrasos. Dashboard básico é obrigatório; recursos avançados são complementares.

## 13.3 Permissões

Visão Geral e Dashboard nunca ampliam acesso. Indicadores serão calculados somente sobre registros visíveis ao usuário.

# 14. Empresa

Central de configuração do Empreendimento, separando configuração operacional de aspectos comerciais/estruturais controlados pela CW.

## 14.1 Estrutura

```text
EMPRESA
├── CONFIGURAÇÕES
│   ├── Dados Gerais
│   ├── Identidade Visual
│   ├── Preferências
│   └── Manutenção
└── ASSINATURA
    ├── Plano
    ├── Módulos e Recursos
    ├── Usuários
    └── Armazenamento
```
## 14.2 Dados e identidade

Dados gerais: nome, razão social, nome fantasia, documento fiscal quando aplicável, contatos, site, endereço, cidade/estado, fuso horário e observações. Tenant terá identificador interno estável, exemplo EMP-00001.

Identidade visual inicial: logo e nome de exibição. White-label completo não faz parte da V2.

## 14.3 Configurações de Manutenção

- Validação da conclusão: Obrigatória/Não obrigatória; padrão recomendado: Obrigatória.
- Executor pode validar própria OS? padrão recomendado: Não.
- Exigir descrição do serviço executado.
- Exigir motivo de cancelamento.
- Exigir motivo de devolução.
## 14.4 Numeração

Padrões: Solicitação 2026-001; OS OS-2026-001; Ativo AT-00001. A lógica não será livremente editável na V2.

## 14.5 Plano, módulos e features

Tenant poderá visualizar plano, módulos/features habilitados, usuários e armazenamento. Gestor não ativa comercialmente módulos nem altera limites; isso é controlado pela CW.

## 14.6 Armazenamento

Exibir usado, contratado e percentual. Ao atingir limite, novos uploads podem ser bloqueados, mas a operação sem novos arquivos deve continuar.

## 14.7 Situação

- Ativo
- Suspenso
- Inativo
Inativação não implica exclusão automática dos dados.

# 15. Minha Conta

Área de autogestão do usuário, sem duplicar administração de Usuários e Permissões.

## 15.1 Dados

- Nome/nome de exibição
- Foto/avatar
- E-mail
- Telefone
- Função/cargo quando aplicável
CPF não é obrigatório.

## 15.2 Segurança

Alteração e recuperação de senha usarão fluxo seguro do provedor de autenticação. E-mail sensível deverá ser validado. Arquitetura preparada para gerenciamento de sessões/dispositivos.

## 15.3 Consulta administrativa

Usuário poderá consultar Perfil, Equipes, Empreendimento e principais permissões/escopos, mas não poderá alterar unilateralmente esses vínculos.

## 15.4 Preferências

Preferências pessoais poderão incluir visualização e notificações. Configurações organizacionais permanecem em Empresa.

# 16. Notificações e Alertas

## 16.1 Conceitos

- Comentário: o que as pessoas conversaram.
- Histórico: o que aconteceu no registro.
- Notificação: o que aconteceu que interessa ao usuário.
- Alerta: o que exige atenção.
## 16.2 Central

Central interna acessível pelo sino no cabeçalho, com título, mensagem, tipo, entidade/registro, data/hora, leitura, severidade e link.

Status mínimo: Lida/Não lida, com ações individuais, múltiplas e 'marcar todas'.

## 16.3 Eventos

Eventos relevantes incluem atribuições, mudanças de responsável, programação/reprogramação, comentários, validação/devolução, aprovação, Agendamentos, preventivas, prazos, condições de Ativos e documentos de Fornecedores.

## 16.4 Severidade

- Informativo
- Atenção
- Crítico
## 16.5 Canais

V2 prioriza notificação interna. E-mail será usado em eventos relevantes. WhatsApp e push são futuros.

## 16.6 Agrupamento e deduplicação

Eventos repetitivos poderão ser agrupados. Alertas persistentes não devem gerar duplicatas idênticas continuamente.

## 16.7 Segurança

Notificação nunca poderá revelar registro ao qual o destinatário não tenha acesso.

# 17. Suporte e Ajuda

Suporte CW ERP é entidade distinta de Solicitação de Manutenção.

## 17.1 Estrutura

- Central de Ajuda
- Meus Chamados
- Novo Chamado
- Sobre a CW ERP
## 17.2 Chamados

- Assunto
- Categoria
- Descrição
- Prioridade percebida
- Anexos
- Empreendimento/usuário/página/versão quando aplicável
Categorias iniciais: Dúvida, Problema técnico, Acesso, Relatório, Sugestão e Outro.

Status possíveis: Aberto, Em análise, Em atendimento, Aguardando cliente, Resolvido, Encerrado.

## 17.3 Escopo

Central de Ajuda e chamados estruturados são V2 Complementar. A arquitetura deverá permitir evolução para SLA, filas, responsáveis, indicadores e base de conhecimento.

# 18. Requisitos Transversais e Escopo da V2

## 18.1 Classes de escopo

- V2 - Obrigatório: necessário para produto operacional, seguro e utilizável.
- V2 - Complementar: previsto para V2, mas não bloqueia disponibilização do núcleo.
- Futuro: arquitetura pode considerar, mas não implementar agora.
## 18.2 Regra de desenvolvimento

A existência de uma funcionalidade neste PRODUCT_SPEC não autoriza sua implementação imediata. Agentes de IA e desenvolvedores deverão respeitar a classificação de escopo e evitar antecipação de integrações, módulos e complexidade.

## 18.3 Multiempresa

Todo dado de cliente deverá possuir vínculo inequívoco com Empreendimento. Autorização considera Usuário + Empreendimento + Permissão + Escopo. Isolamento deve existir em UI, backend e banco/RLS.

## 18.4 Mobile

Fluxos operacionais críticos deverão ser projetados para celular, especialmente Solicitação, OS, início/pausa/retomada, checklist, fotos, comentários, conclusão, devolução e Calendário. Mobile não deve ser apenas desktop encolhido.

## 18.5 Offline

A primeira V2 exige internet. Offline/PWA com sincronização é futuro.

## 18.6 Componentes compartilhados

- CWMediaManager: upload, galeria, lightbox, legenda, edição/exclusão controlada, download, autor, data/hora, permissões e auditoria.
- CWDataTable: busca, filtros, ordenação, paginação, colunas, ações e exportação quando aplicável.
- Outros componentes conceituais: CWFilters, CWStatusBadge, CWHistory, CWChecklist, CWCalendar, CWConfirmDialog, CWPermissionGuard, CWUserSelector, CWNotifications e CWReport.
## 18.7 Estados de interface

- Carregando
- Sem resultados
- Erro
- Sem permissão
- Registro inexistente
- Conexão indisponível
- Operação concluída
- Operação falhou
## 18.8 Exclusão e histórico

Registros operacionais com histórico relevante não serão fisicamente apagados por usuários comuns. Preferir Cancelar, Inativar, Baixar ou Arquivar. Exclusão física será excepcional e controlada.

## 18.9 Auditoria central

Mecanismo compartilhado deverá registrar Empreendimento, usuário, entidade, registro, ação, antes/depois, data/hora e contexto quando aplicável.

## 18.10 Busca Global

Busca no cabeçalho poderá localizar Solicitações, OS, Ativos, Fornecedores, usuários e outros recursos autorizados, agrupando resultados por tipo. Classificação: V2 Complementar.

## 18.11 V2 - Obrigatório

- Fundação: autenticação, multiempresa, RLS/segurança, usuários, Perfis, permissões, escopos e Equipes.
- Manutenção: Solicitações, OS, relação Solicitação-OS, execução, pausa/retomada, validação, comentários, histórico, anexos/galeria e checklist.
- Planos: cadastro básico, vínculo com Ativo, periodicidade, responsável/Equipe, checklist, programação, geração de OS Preventiva, histórico básico e próxima execução.
- Operação: Calendário e Visão Geral.
- Cadastros essenciais: Locais, Centros de Custo, Setores, Equipes, Categorias/Subcategorias e Motivos.
- Compartilhado: Ativos e Fornecedores.
- Gestão: Dashboard básico, relatórios básicos e PDF individual da OS.
- Configurações: Empresa e Minha Conta.
- Sistema: notificações internas essenciais, auditoria, mídia/tabelas compartilhadas, estados de interface e responsividade dos fluxos críticos.
## 18.12 V2 - Complementar

- Busca Global
- QR Code de Ativos
- Importação XLSX/CSV
- Exportações XLSX avançadas
- Relatórios salvos e avançados
- Dashboard avançado
- Garantias e alertas avançados
- Gestão documental avançada de Fornecedores
- Central de Ajuda
- Chamados de Suporte
- Automações e recorrências avançadas de Planos de Manutenção
## 18.13 Futuro

- Portal/acesso externo de Fornecedores
- WhatsApp
- Push notifications
- Relatórios automáticos recorrentes por e-mail
- Avaliação avançada de Fornecedores
- White-label completo
- Modo/sincronização offline
- Financeiro
- Compras
- Orçamento
- Estoque
- Diário de Obras
- Checkout e cobrança automática
- Gestão financeira da assinatura
- Dashboards totalmente personalizáveis
- Integrações futuras não explicitamente aprovadas
## 18.14 Regra contra overengineering

Preparação para o futuro não deve gerar complexidade desnecessária hoje. Priorizar modularidade, segurança, reutilização, clareza, extensibilidade razoável e baixo acoplamento.

## 18.15 Reutilização antes de desenvolvimento próprio

Antes de desenvolver componentes complexos, a etapa técnica deverá avaliar bibliotecas maduras e soluções existentes considerando manutenção, segurança, licença, acessibilidade, responsividade, compatibilidade e customização.

## 18.16 Ordem de prioridade

Segurança → Fundação → Fluxo operacional → Consistência → Experiência do usuário → Recursos complementares → Evoluções futuras.

# Próximas Etapas

1. Inventário técnico da V1.
1. Comparação V1 × especificação V2.
1. Definição da arquitetura V2.
1. Modelagem de banco de dados.
1. Definição de RLS e matriz técnica de permissões.
1. Definição dos componentes compartilhados e bibliotecas.
1. Plano de implementação por fases.
1. Implementação e testes.
A V1 deverá ser preservada em branch/tag e backup antes da reconstrução. Nenhuma migração deverá ser iniciada antes do inventário técnico e da definição da estratégia de dados.
