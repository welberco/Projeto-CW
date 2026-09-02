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

Consolidar progressivamente a cadeia de navegação e reduzir sobrescritas, mantendo as rotas, permissões e telas cobertas pelos testes da Fase 2A.

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
- [ ] Fase 2B: consolidar a navegação sem alterar comportamento.
- [ ] Validar manualmente e automatizar a cobertura da Fase 2B.
- [ ] Fase 2C: remover somente código comprovadamente obsoleto.
- [ ] Validar manualmente e executar a suíte completa antes de integrar à `main`.
