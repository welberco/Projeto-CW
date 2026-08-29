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
