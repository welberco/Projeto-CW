# CW Manutenção

MVP da plataforma da CW Engenharia para gestão de demandas de manutenção, obras e facilities.

## Primeira versão

- painel com indicadores por status e prioridade;
- cadastro de demandas;
- consulta com busca e filtros;
- responsáveis, prazos, dependências e próxima ação;
- identificação automática de demandas atrasadas;
- interface responsiva para computador e celular;
- persistência local no navegador, sem necessidade de servidor nesta fase.

## Executar

Abra `index.html` no navegador ou execute `python3 -m http.server 8080` e acesse `http://localhost:8080`.

## Próximas etapas

1. Validar campos e fluxo com o uso real no Serena Mall.
2. Implementar autenticação, banco de dados e anexos.
3. Adicionar edição, histórico, comentários, notificações e relatórios.
4. Preparar a arquitetura multiempresa para comercialização.

## Configuração do Supabase

1. Abra o SQL Editor do projeto no Supabase.
2. Copie e execute o conteúdo de `supabase/schema.sql`.
3. O script cria a organização Serena Mall, perfis, demandas, índices e políticas de segurança por organização.

## Arquitetura v2

A versão v2 preserva as demandas existentes como solicitações e acrescenta:

- navegação modular por rotas persistentes;
- solicitações, ordens de serviço e aceite;
- prestadores próprios e terceirizados;
- ativos, equipamentos e planos periódicos;
- operações/lojas, centros de custo e cadastros gerais;
- perfis Administrador, Gestor, Auxiliar, Técnico/Executor e Usuário Padrão;
- matriz de permissões exclusiva por empresa;
- paginação no banco e galeria com miniaturas privadas;
- isolamento por empreendimento aplicado por RLS.

### Publicação no projeto existente

1. Faça o backup do banco e do Storage.
2. Execute `supabase/arquitetura-v2.sql` no SQL Editor. A migração é aditiva e reexecutável.
3. Publique a função `admin-users` atualizada.
4. Publique os arquivos do frontend.
5. Valide login, criação de solicitação, geração/conclusão de OS e acesso com dois empreendimentos diferentes.

O frontend v2 não deve ser publicado antes da migração SQL, pois os novos módulos dependem das novas tabelas e funções.
