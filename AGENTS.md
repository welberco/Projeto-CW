# AGENTS.md — CW ERP / CW Manutenção V2

## 1. Finalidade

Este arquivo define as regras de trabalho para agentes de IA e desenvolvedores que atuarem neste repositório.

O objetivo é garantir que alterações no **CW ERP / CW Manutenção V2** respeitem:

- a especificação funcional aprovada;
- o isolamento multiempresa;
- a segurança;
- o escopo da V2;
- a rastreabilidade;
- a reutilização de componentes;
- a estabilidade do sistema;
- a evolução incremental do produto.

Estas instruções devem ser consideradas antes de qualquer análise, implementação, refatoração ou alteração estrutural.

---

## 2. Fonte oficial de requisitos

O arquivo:

`PRODUCT_SPEC.md`

é a **fonte oficial de verdade funcional do produto**.

Antes de implementar, alterar ou remover qualquer funcionalidade:

1. localizar a seção correspondente em `PRODUCT_SPEC.md`;
2. compreender a regra funcional completa;
3. identificar se a funcionalidade é:
   - **V2 — Obrigatório**;
   - **V2 — Complementar**;
   - **Futuro**;
4. verificar impactos em permissões, multiempresa, auditoria, histórico e entidades relacionadas.

Em caso de conflito entre código existente e `PRODUCT_SPEC.md`, **não assumir automaticamente que o código atual representa a regra correta da V2**.

A divergência deve ser identificada e tratada explicitamente.

---

## 3. Escopo

### 3.1 V2 — Obrigatório

Possui prioridade de implementação.

### 3.2 V2 — Complementar

Só deve ser implementado quando incluído na fase atual ou quando houver instrução explícita.

### 3.3 Futuro

**Não implementar.**

Referências no `PRODUCT_SPEC.md` a funcionalidades futuras servem apenas para orientar extensibilidade razoável.

Não criar antecipadamente:

- telas;
- tabelas;
- APIs;
- integrações;
- fluxos;
- serviços;
- configurações;
- abstrações complexas

apenas porque uma funcionalidade futura foi mencionada.

---

## 4. Regra contra overengineering

Implementar a solução mais simples que:

- cumpra integralmente o requisito atual;
- seja segura;
- seja testável;
- seja legível;
- permita evolução razoável.

Evitar:

- abstrações prematuras;
- arquiteturas genéricas sem necessidade atual;
- duplicação de infraestrutura;
- dependências desnecessárias;
- sistemas internos complexos para problemas simples;
- antecipação de módulos futuros.

Preparação arquitetural não significa implementação antecipada.

---

## 5. Branches e proteção da V1

A versão anterior do sistema está preservada pela tag:

`v1-legacy`

A branch principal é:

`main`

A reconstrução da V2 ocorre na linha de desenvolvimento correspondente à V2, atualmente:

`develop/v2`

### Regras

- Não modificar `main` durante o desenvolvimento normal da V2.
- Não reescrever ou mover a tag `v1-legacy`.
- Não fazer merge para `main` sem decisão explícita.
- Antes de qualquer alteração, confirmar a branch/worktree em uso.
- Nunca executar alterações em branch diferente da solicitada.
- Não criar branches adicionais sem necessidade ou instrução.
- Não usar `--force`, `reset --hard`, rebase destrutivo ou comandos equivalentes sem autorização explícita.
- Não apagar histórico Git.

---

## 6. Antes de modificar código

Antes de qualquer implementação:

1. confirmar branch e estado do Git;
2. ler a seção aplicável de `PRODUCT_SPEC.md`;
3. localizar a implementação atual relacionada;
4. identificar dependências;
5. verificar impacto no Supabase;
6. verificar impacto em RLS e multiempresa;
7. verificar impacto em permissões;
8. verificar impacto em histórico/auditoria;
9. verificar impacto em arquivos/anexos;
10. verificar testes existentes;
11. verificar se já existe componente reutilizável adequado.

Não começar criando código antes de compreender o fluxo existente.

---

## 7. Inventário da V1 antes da reconstrução

Antes de grandes alterações estruturais da V2, realizar inventário técnico da implementação existente.

O inventário deve ser preferencialmente dividido em etapas:

1. stack e estrutura do repositório;
2. páginas e rotas;
3. funcionalidades existentes;
4. banco de dados e Supabase;
5. autenticação, permissões, RLS e segurança;
6. componentes reutilizáveis, dependências e dívida técnica.

Durante o inventário:

- trabalhar em modo somente leitura;
- não corrigir problemas encontrados;
- não refatorar;
- não instalar dependências;
- não criar migrations;
- não alterar banco;
- documentar fatos observados e incertezas.

Somente depois do inventário deverá ser definida a estratégia de reaproveitamento, substituição ou remoção da V1.

---

## 8. Multiempresa é requisito crítico

A CW ERP é uma aplicação SaaS multiempresa.

Todo dado pertencente a cliente deve possuir vínculo inequívoco com um **Empreendimento**.

A autorização deve considerar, conforme aplicável:

`Usuário + Empreendimento + Permissão + Escopo`

### É proibido

- confiar apenas em filtros de frontend para isolamento;
- buscar dados de múltiplos tenants e filtrá-los somente no navegador;
- aceitar `empreendimento_id` enviado pelo cliente sem validação de autorização;
- criar consultas que permitam vazamento entre Empreendimentos;
- usar ocultação de menu como mecanismo de segurança.

O isolamento deverá existir no banco/backend, preferencialmente com RLS adequada no Supabase.

---

## 9. Administrador Global CW

O Administrador Global CW é uma função de plataforma, não um Perfil comum de tenant.

Qualquer bypass administrativo deverá:

- ser explícito;
- ser mínimo;
- possuir justificativa;
- respeitar o desenho de segurança;
- ser auditável.

Não criar bypass genérico de RLS apenas para facilitar desenvolvimento.

---

## 10. Perfis, permissões e escopos

Perfil não é autorização final.

O modelo conceitual é:

`Recurso + Ação + Escopo`

Perfis fornecem conjuntos padrão de permissões.

Evitar regras críticas como:

```javascript
if (user.profile === 'gestor') {
  // autorizar
}
```

quando a ação deveria verificar uma permissão.

Exemplo correto conceitualmente:

`Ordem de Serviço + Validar conclusão + Escopo permitido`

O backend e o banco deverão aplicar as regras necessárias; `CWPermissionGuard` ou equivalente no frontend melhora UX, mas não substitui segurança.

---

## 11. Supabase e banco de dados

Alterações de banco devem ser controladas e reproduzíveis.

### Regras

- Preferir migrations versionadas.
- Não alterar produção manualmente sem migration correspondente.
- Não remover tabela ou coluna sem análise de dependências e dados.
- Não renomear estruturas críticas sem plano de migração.
- Não presumir que dados atuais podem ser descartados.
- Preservar histórico e rastreabilidade.
- Avaliar índices, constraints, foreign keys e RLS.
- Não usar service role no frontend.
- Não expor secrets no repositório.
- Não registrar tokens, chaves ou credenciais em logs.

Antes de migration destrutiva, apresentar impacto e estratégia de preservação/rollback.

---

## 12. RLS

Toda nova tabela tenant-owned deverá ser analisada quanto a RLS.

Para cada entidade, determinar explicitamente:

- quem pode visualizar;
- quem pode inserir;
- quem pode atualizar;
- quem pode excluir/inativar;
- qual o tenant;
- qual o escopo;
- quais exceções administrativas existem.

Não criar política permissiva genérica como solução temporária sem autorização explícita.

Testes de isolamento entre tenants devem fazer parte das validações de segurança.

---

## 13. Entidades e relações fundamentais

Preservar as decisões do `PRODUCT_SPEC.md`, especialmente:

### Solicitação e OS

- são entidades independentes;
- uma Solicitação pode ter zero, uma ou várias OS;
- uma OS pode ter no máximo uma Solicitação;
- OS pode existir sem Solicitação;
- concluir OS não conclui automaticamente Solicitação.

### Preventiva

Manter separação conceitual:

`Plano → Programação → OS Preventiva → Execução`

### Ativo

Ativo é a entidade estrutural.

Equipamento é classificação/tipo de Ativo.

### Fornecedor

Contato de Fornecedor não é automaticamente usuário da plataforma.

### Calendário

Calendário é visualização temporal das entidades de origem, não uma base operacional duplicada.

---

## 14. Status e regras de negócio

Não alterar listas de status, transições ou significados sem consultar `PRODUCT_SPEC.md`.

Especial atenção ao fluxo de OS:

`Rascunho → Aberta → Programada → Em execução → Pausada/Aguardando validação → Concluída/Cancelada`

Quando validação estiver habilitada:

`Executor → Aguardando validação → Aprovação ou Devolução`

Devolução:

- exige motivo;
- retorna a OS para execução;
- deve ser auditada;
- pode ocorrer várias vezes.

---

## 15. Histórico, auditoria, comentários, notificações e alertas

Não misturar os conceitos:

- **Comentário:** comunicação humana;
- **Histórico:** acontecimentos do registro;
- **Auditoria:** rastreabilidade técnica/administrativa;
- **Notificação:** evento relevante para determinado usuário;
- **Alerta:** condição que exige atenção.

Quando possível, utilizar mecanismos compartilhados em vez de implementar versões independentes em cada módulo.

---

## 16. Exclusão e preservação histórica

Registros operacionais com histórico relevante não devem ser fisicamente apagados por usuários comuns.

Preferir, conforme entidade:

- Cancelar;
- Inativar;
- Baixar;
- Arquivar.

Exclusão física deverá ser excepcional, autorizada e analisada quanto a relacionamentos e auditoria.

---

## 17. Componentes reutilizáveis

Antes de criar uma nova implementação, verificar se o comportamento já existe ou pode ser compartilhado.

Componentes conceituais previstos incluem:

- `CWMediaManager`;
- `CWDataTable`;
- `CWFilters`;
- `CWStatusBadge`;
- `CWHistory`;
- `CWChecklist`;
- `CWCalendar`;
- `CWConfirmDialog`;
- `CWPermissionGuard`;
- `CWUserSelector`;
- `CWNotifications`;
- `CWReport`.

Os nomes são conceituais e não obrigam implementação técnica específica.

Evitar duplicar:

- galerias;
- uploaders;
- tabelas;
- filtros;
- modais;
- checklists;
- históricos;
- seletores de usuário;
- controles de permissão.

---

## 18. Bibliotecas externas

Antes de desenvolver componente complexo do zero, avaliar solução madura existente.

Avaliar:

- licença;
- manutenção;
- segurança;
- acessibilidade;
- responsividade;
- compatibilidade com a stack;
- tamanho/impacto;
- maturidade;
- facilidade de customização.

Não adicionar dependência apenas por conveniência mínima.

Quando uma biblioteca for adotada para comportamento compartilhado, preferir encapsulá-la atrás de componente/padrão interno quando isso reduzir acoplamento.

---

## 19. Mídia e anexos

Anexos deverão seguir padrão compartilhado.

Quando aplicável, suportar:

- upload;
- múltiplos arquivos;
- galeria;
- lightbox;
- legenda;
- edição conforme permissão;
- exclusão controlada;
- download;
- autor;
- data/hora;
- auditoria.

Nunca confiar apenas no caminho do arquivo para autorização.

Buckets e objetos do Supabase Storage devem respeitar isolamento e políticas adequadas.

Detalhes serão consolidados em:

`docs/media-standard.md`

quando esse documento for criado.

---

## 20. UX e mobile

Fluxos operacionais do CW Manutenção são prioritários em celular.

Verificar especialmente:

- abertura de Solicitação;
- consulta de OS;
- início;
- pausa;
- retomada;
- checklist;
- fotos;
- comentários;
- serviço executado;
- envio para validação;
- OS devolvida;
- Calendário.

Não tratar mobile apenas como desktop reduzido.

Estados obrigatórios de interface devem ser tratados de forma consistente:

- carregando;
- vazio;
- erro;
- sem permissão;
- inexistente;
- conexão indisponível;
- sucesso;
- falha.

---

## 21. Offline

A V2 inicial exige conexão com internet.

Não implementar:

- cache operacional offline;
- sincronização offline;
- resolução de conflitos;
- fila offline de uploads

sem inclusão explícita no escopo.

---

## 22. Testes

Toda alteração funcional deverá avaliar necessidade de testes.

Prioridades:

1. regras de negócio;
2. isolamento multiempresa;
3. permissões;
4. RLS;
5. transições de status;
6. relacionamentos críticos;
7. regressões;
8. fluxos principais do usuário.

Correção de bug relevante deve, quando viável, incluir teste que reproduza a falha.

Não remover ou enfraquecer testes apenas para fazer a suíte passar.

Se algum teste não puder ser executado, registrar isso claramente.

---

## 23. Qualidade de código

Priorizar:

- nomes claros;
- funções pequenas e focadas;
- baixo acoplamento;
- ausência de duplicação relevante;
- tratamento explícito de erros;
- validação de entradas;
- tipos/contratos claros quando a stack permitir;
- comentários apenas quando agregarem contexto não óbvio.

Evitar refatorações não relacionadas à tarefa atual.

---

## 24. Segurança

Sempre considerar:

- autenticação;
- autorização;
- tenant isolation;
- RLS;
- validação de entrada;
- upload seguro;
- exposição de dados;
- secrets;
- logs;
- dependências;
- XSS;
- injeção;
- acesso indevido a objetos;
- operações administrativas.

Não introduzir credenciais, tokens ou chaves privadas em código versionado.

Problemas de segurança encontrados durante uma tarefa devem ser relatados, mesmo quando não forem corrigidos naquela fase.

---

## 25. Migrations e dados existentes

Antes de alterar estruturas que já possuem dados:

1. identificar volume e dependências;
2. definir transformação;
3. preservar dados válidos;
4. prever rollback quando razoável;
5. testar migration;
6. documentar mudanças relevantes.

Não presumir banco vazio.

A V2 deverá considerar estratégia explícita para dados da V1 antes da migração definitiva.

---

## 26. Documentação

Documentação deve acompanhar decisões relevantes.

Estrutura planejada:

```text
/
├── AGENTS.md
├── PRODUCT_SPEC.md
├── README.md
└── docs/
    ├── architecture.md
    ├── business-rules.md
    ├── permissions.md
    ├── ui-patterns.md
    ├── media-standard.md
    ├── database.md
    ├── security.md
    └── development-workflow.md
```

Não criar todos os documentos vazios apenas para completar a estrutura.

Criá-los quando houver conteúdo consolidado e necessário.

---

## 27. Mudanças de requisito

Se uma solicitação nova contradizer `PRODUCT_SPEC.md`:

1. identificar explicitamente a divergência;
2. não esconder a inconsistência;
3. confirmar/registrar a nova decisão;
4. atualizar a documentação correspondente;
5. somente então implementar a regra nova.

Código e documentação não devem permanecer deliberadamente divergentes.

---

## 28. Procedimento de implementação

Para cada funcionalidade:

### Antes

- entender requisito;
- localizar código relacionado;
- analisar dados;
- analisar segurança;
- analisar permissões;
- analisar reutilização;
- definir plano pequeno.

### Durante

- limitar alteração ao escopo;
- reutilizar padrões existentes adequados;
- manter isolamento;
- preservar histórico;
- evitar refatorações paralelas.

### Depois

- executar testes relevantes;
- revisar diff;
- verificar regressões;
- verificar segurança;
- verificar mobile quando aplicável;
- atualizar documentação quando necessário;
- resumir exatamente o que mudou.

---

## 29. Commits

Commits devem ser pequenos, coerentes e descritivos.

Padrões recomendados:

```text
feat: adicionar validação de conclusão da OS
fix: impedir acesso cruzado entre empreendimentos
docs: documentar regras de permissões
refactor: consolidar componente de galeria
test: cobrir isolamento de solicitações por tenant
chore: atualizar dependência
```

Evitar misturar múltiplas funcionalidades não relacionadas no mesmo commit.

---

## 30. Pull Requests e merge

Não fazer merge automático para `main`.

Antes de merge relevante:

- revisar diff;
- executar testes;
- verificar migrations;
- verificar RLS;
- verificar regressões;
- confirmar documentação;
- confirmar escopo;
- validar que nenhuma funcionalidade futura foi incluída acidentalmente.

---

## 31. Saída esperada de agentes de IA

Ao concluir uma tarefa de desenvolvimento, informar de forma objetiva:

1. o que foi analisado;
2. o que foi alterado;
3. arquivos modificados;
4. migrations criadas, se houver;
5. testes executados e resultados;
6. riscos ou pendências;
7. qualquer decisão que ainda precise de aprovação.

Não afirmar que algo foi testado se não foi efetivamente executado.

Não afirmar que uma funcionalidade está segura apenas porque funciona na interface.

---

## 32. Regra para tarefas de análise

Quando a tarefa solicitar somente análise, inventário, auditoria ou revisão:

**não modificar arquivos.**

Entregar primeiro o diagnóstico solicitado.

Mudanças só deverão ocorrer quando a tarefa autorizar explicitamente implementação.

---

## 33. Prioridade geral da V2

A ordem geral é:

**Segurança → Fundação → Fluxo operacional → Consistência → Experiência do usuário → Recursos complementares → Evoluções futuras.**

Funcionalidade complementar não deve atrasar a estabilização do núcleo obrigatório.

Funcionalidade futura não deve ser implementada sem decisão explícita.

---

## 34. Princípio final

O objetivo não é reconstruir o maior sistema possível.

O objetivo é construir um **CW Manutenção V2 seguro, consistente, modular, reutilizável e comercialmente viável**, preservando espaço para a evolução futura do CW ERP sem comprometer a simplicidade e a confiabilidade da versão atual.
