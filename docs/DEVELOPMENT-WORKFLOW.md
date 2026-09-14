# Fluxo de desenvolvimento autônomo

## Objetivo

Este documento explica como Usuário, ChatGPT e Codex colaboram com segurança no
CW ERP V2. As regras normativas permanecem em `AGENTS.md`; este guia não
autoriza exceções a elas.

## Papéis e fluxo de missão

O Usuário define objetivo, escopo e aprova ações críticas. ChatGPT organiza a
missão, revisa resultados e decide a próxima etapa. Codex executa localmente a
missão autorizada.

```text
Usuário → ChatGPT → Codex → validações automáticas → revisão ChatGPT → próxima etapa
```

Em uma missão, Codex lê as fontes de verdade aplicáveis, confere branch e
worktree, inspeciona o código, planeja internamente, implementa o recorte,
valida, investiga falhas introduzidas, corrige, revalida, revisa o diff e
atualiza a documentação necessária. Quando autorizado, prepara um commit local
coerente e entrega o relatório.

## Autonomia, checkpoints e ações críticas

Leituras, edição local, testes, build, lint, typecheck, revisão de diff e
commits locais são autônomos quando reversíveis e dentro do escopo. Supabase
local descartável pode ser usado para migrations, pgTAP e reset compatíveis com
a missão.

Pausam para aprovação: qualquer operação remota ou de produção, deploy, escrita
em Supabase remoto, mudança destrutiva de dados persistentes, secrets,
force-push, rebase destrutivo, merge em `main`, alteração arquitetural
congelada, relaxamento de RLS ou bypass de autorização. Checkpoints ocorrem
antes de uma ação crítica, ao encontrar divergência de requisito e antes do
commit final.

## Validação e falhas

`npm run preflight:v2` faz diagnóstico local, sem iniciar serviços nem alterar
arquivos. `npm run verify:v2` executa gates de aplicação e executa o gate DB
somente se Docker e Supabase local já estiverem disponíveis; nesse caso ausente,
declara `DB_GATE = NOT_RUN` e termina em `WARN`, nunca em PASS completo.
`npm run verify:v2:full` exige esse gate DB e falha se ele não puder rodar.

Falhas da missão devem ser investigadas, corrigidas dentro do escopo e testadas
novamente. Falhas anteriores ou externas não devem ser mascaradas nem corrigidas
sem necessidade. Verificações de segurança reportam somente arquivo e categoria,
nunca o valor de um possível secret.

## Git e segurança

Não há push, merge ou PR implícitos. O commit local inclui somente arquivos da
missão após `git diff --check`, revisão do stage e checagem de secrets. Arquivos
preexistentes fora de escopo ficam fora do stage e são relatados.

Tenant, usuário e autorização vêm de fatos autoritativos do banco, não de UI,
URL, cache ou JWT isoladamente. RLS, grants mínimos, fail-closed e ausência de
secrets no repositório, bundle e logs são invariantes.

## Missão única, divisão e roadmap

Use uma missão única para uma alteração pequena e coesa, com gates claros e sem
dependências críticas. Divida quando houver decisões de produto/arquitetura,
migrations complexas, superfícies de segurança distintas, risco de regressão
alto ou necessidade de aprovação entre etapas. O roadmap W0–W17 continua sendo
seguido pelos documentos aprovados: este workflow organiza a execução e não
antecipa W2 ou qualquer etapa futura.

## Gates operacionais

Cada missão operacional declara, sem alterar gates de produto, os seguintes
gates: `AUTONOMOUS_WORKFLOW_READY`, `AGENT_RULES_READY`, `PREFLIGHT_READY` e
`VERIFY_PIPELINE_READY`. Cada um só recebe `YES` quando seu contrato foi
implementado e validado; um `WARN` por artefato preexistente fora de escopo não
equivale a uma falha dos gates executados.

## Relatório padrão

1. Estado inicial.
2. Escopo executado.
3. Arquivos alterados.
4. Decisões técnicas.
5. Testes e validações.
6. Falhas e correções.
7. Segurança e integridade.
8. Documentação.
9. Commits e hashes.
10. Git status.
11. Gates.
12. Riscos residuais.
13. Ações não executadas por exigirem aprovação.
14. Confirmação de não expansão de escopo.
