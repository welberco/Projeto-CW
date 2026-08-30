# Implantação multiempreendimento

Esta atualização altera autenticação, funções e políticas de acesso. Não fazer merge antes de preparar o Supabase. O código no GitHub não é backup do banco, Auth nem dos arquivos do Storage.

## Antes de aplicar

1. Faça backup privado do banco e dos buckets `cw-anexos` e `cw-logos`.
2. Teste primeiro em um projeto de homologação. Os testes locais incluídos usam dados fictícios, não o banco de produção.
3. Confira os administradores existentes. Todos continuarão com o papel `administrador`, agora com acesso global. Execute esta consulta somente de leitura e confirme os nomes:

```sql
select p.id,p.nome,p.email,p.papel,o.nome as empreendimento
from public.perfis p left join public.organizacoes o on o.id=p.organizacao_id
where p.papel='administrador';
```

4. Reserve uma janela sem cadastros/edições durante a implantação.

## Ordem de implantação

1. Supabase → SQL Editor → nova consulta: execute o conteúdo completo de `supabase/multiempresa.sql` desta alteração. Não execute novamente os scripts antigos.
2. Aguarde `Success`. O script usa uma transação: se houver erro, não continue as etapas seguintes; envie a mensagem de erro para análise.
3. Supabase → Edge Functions → `admin-users` → Code: substitua pelo conteúdo completo de `supabase/functions/admin-users/index.ts` desta alteração e publique/deploy a função.
4. Só então faça merge do Pull Request. Isso publica `app.js` e `multiempresa.js` juntos no GitHub Pages.
5. Aguarde a publicação do Pages e recarregue a página. Faça novo login.

Durante o intervalo entre o SQL e a publicação, a tela antiga de cadastro não conhece o campo empreendimento. Por isso novos cadastros podem falhar até terminar a sequência.

## Comportamento e preservação

- Nenhuma demanda, mídia, usuário ou empreendimento existente é apagado/movido.
- Cadastros existentes são considerados aprovados; quem estava bloqueado permanece bloqueado.
- `lojista` permanece como código interno por compatibilidade, mas aparece como **Usuário Padrão**. `gestor_manutencao` aparece como **Gestor**.
- Administrador tem acesso global e seleciona o empreendimento no menu lateral. A navegação, criação e os relatórios usam o empreendimento selecionado.
- Empreendimento tem permissões fixas na própria empresa. Somente Administrador e Empreendimento alteram matrizes.
- Gestor inicia com permissões operacionais e gestão de usuários/dados da empresa, sem editar a matriz. O responsável pode reduzir essas permissões.
- Técnico inicia com visualização das demandas e histórico da própria empresa, sem criação, edição, exclusão ou relatórios.
- Usuário Padrão inicia com demandas próprias, criação corretiva/agendamento e edição de suas próprias demandas.
- Na primeira aplicação, as matrizes existentes recebem esses padrões novos. Reexecutar a migração não apaga alterações posteriores feitas pelo responsável.
- Todo cadastro público, inclusive com metadados manipulados, nasce **Usuário Padrão, pendente e inativo**. Confirmação de e-mail não substitui aprovação do empreendimento.
- Em Usuários → Abrir perfil: selecione Aprovado, mantenha acesso Ativo e salve. Rejeitar ou bloquear impede o acesso sem apagar demandas.
- Cadastrar nova empresa: Administrador → seletor lateral → Cadastrar empreendimento. Depois selecione essa empresa e cadastre um responsável com perfil Empreendimento na página Usuários.
- Matriz é por perfil e por empreendimento, não uma exceção individual por pessoa.

## Verificação após publicar

1. Confira demandas, históricos, anexos e relatórios do empreendimento atual.
2. Crie uma segunda empresa de teste e um responsável Empreendimento nela.
3. Cadastre um Usuário Padrão pela tela pública: antes da aprovação não deve ter acesso aos dados.
4. Aprove-o: ele deve visualizar somente suas próprias demandas.
5. Promova-o a Técnico: deve visualizar as demandas da sua empresa, sem editar/criar inicialmente.
6. Acrescente uma permissão na matriz e confirme-a após novo login.
7. Promova outro usuário a Gestor e retire uma permissão. Ele não deve conseguir reativá-la nem acessar a matriz.
8. Confirme que ambos os responsáveis não acessam registros, usuários, anexos ou relatórios da outra empresa.
9. Como Administrador, alterne as empresas e emita relatório com o cabeçalho correto.

## Testes locais

```sh
npm install
npm test
```

Os testes executam uma instalação PostgreSQL embarcada (PGlite), recriam a estrutura versionada anterior, aplicam a migração e verificam RLS/RPCs com empresas e usuários fictícios. Há testes de interface (DOM) e da função administrativa com respostas simuladas. Ainda é necessário validar o deploy real do Supabase/Pages.

## Restauração

Não restaure somente o JavaScript após aplicar a migração: a estrutura e as regras do banco também mudam. Use o backup completo do Supabase e a versão compatível da Edge Function em conjunto com o marco do GitHub. Não há comando automático de restauração destrutiva neste Pull Request.
