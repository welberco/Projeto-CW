# Refatoração do CW Manutenção

## Objetivo

Organizar o frontend, remover código legado e reduzir dependências globais sem alterar as regras de negócio ou o isolamento multiempresa.

## Regras

1. Não refatorar diretamente na branch `main`.
2. Cada etapa deve ter escopo pequeno.
3. Todos os testes devem passar antes e depois da alteração.
4. Mudanças no frontend não devem alterar RLS ou permissões do banco.
5. Não remover compatibilidade legada antes de migrar os dados.
6. Não misturar refatoração estrutural com novas funcionalidades.
7. Validar cada etapa no ambiente de pré-visualização.

## Diagnóstico inicial

- `app.js`, `multiempresa.js` e `arquitetura-v2.js` dependem da ordem de carregamento.
- A navegação passa por `show`, `showBase`, `cwLegacyShow` e `cwNavigate`.
- O menu legado do HTML é substituído em tempo de execução.
- Há eventos inline e funções globais que deverão ser removidos gradualmente.
- Os nomes de perfis antigos ainda possuem uma camada temporária de compatibilidade.
- Os testes atuais protegem isolamento, RLS, Storage, permissões, OS e a estrutura principal da interface, mas precisam ganhar cobertura funcional durante a revisão.

## Etapas

- [x] Registrar o resultado inicial dos testes
- [x] Limpar arquivos de configuração obsoletos
- [x] Criar integração contínua
- [ ] Mapear funções globais
- [ ] Mapear dependências entre os três scripts
- [ ] Padronizar os nomes dos perfis
- [ ] Consolidar a navegação
- [ ] Remover o menu legado
- [ ] Remover eventos inline
- [ ] Extrair configuração do Supabase
- [ ] Separar autenticação
- [ ] Separar permissões
- [ ] Separar organizações
- [ ] Separar solicitações
- [ ] Separar ordens de serviço
- [ ] Separar ativos
- [ ] Separar prestadores
- [ ] Atualizar os testes
- [ ] Atualizar o README

## Proteções criadas

- Branch de trabalho: `refactor/limpeza-fase-1`
- Ponto de restauração: `backup/pre-refatoracao-v2`
- CI: `.github/workflows/tests.yml`

## Critério para iniciar a Fase 2

O workflow do GitHub e os testes locais devem concluir sem erros. A próxima fase começará pelo inventário da cadeia `show` → `showBase` → `cwLegacyShow` → `cwNavigate`, sem alterar inicialmente as regras do Supabase.
