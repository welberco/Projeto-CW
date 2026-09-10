# Implementação V2 — W0

## W0A — Foundation frontend

A V1 permanece na raiz do repositório como referência executável. A V2 usa
`v2/index.html`, código TypeScript em `src/` e saída local em `dist-v2/`, sem
copiar scripts globais ou alterar os SQLs legados.

### Toolchain

- package manager: npm, escolhido porque não havia lockfile estabelecido;
- runtime validado nesta implementação: Node.js 24.19.0 e npm 11.17.0;
- aplicação: React 19, Vite 8 e TypeScript 5.9 em modo strict;
- rotas: React Router 7 em Data Mode com `createBrowserRouter`;
- remote state: TanStack Query 5, somente em memória;
- boundaries: Zod 4, React Hook Form 7 e Supabase JS 2 tipado;
- UI: Tailwind 4, CSS variables, Radix Slot e primitive mínima no padrão shadcn;
- testes W0A: Vitest 5, React Testing Library 16 e jsdom existente.
- tipos do toolchain: `@types/node` 26 e tipos React 19.

As dependências novas diretas usam releases estáveis consultadas no registry
npm oficial:

| Fundação | Versão resolvida | Licença |
| --- | --- | --- |
| React / React DOM | 19.2.8 | MIT |
| React Router DOM | 7.18.3 | MIT |
| TanStack React Query | 5.102.8 | MIT |
| React Hook Form / resolvers | 7.87.0 / 5.9.1 | MIT |
| Zod | 4.5.4 | MIT |
| Supabase JS | 2.116.0 | MIT |
| Radix Slot | 1.3.3 | MIT |
| Tailwind CSS / plugin Vite | 4.3.3 | MIT |
| Vite / plugin React | 8.2.2 / 6.1.1 | MIT |
| Vitest / Testing Library React | 5.0.0 / 16.3.3 | MIT |
| ESLint / typescript-eslint | 10.10.0 / 8.70.0 | MIT |
| TypeScript | 5.9.3 | Apache-2.0 |
| class-variance-authority | 0.7.1 | Apache-2.0 |

Nenhum pacote alpha, beta, canary ou RC foi adotado.

### Uso local

1. Execute `npm install`.
2. Copie `.env.example` para `.env.local` e substitua apenas os placeholders por
   configuração pública do ambiente local.
3. Execute `npm run dev`.

Scripts relevantes:

- `npm run dev`: servidor Vite da V2;
- `npm run typecheck`: TypeScript strict;
- `npm run lint`: lint do código V2 e suas configurações;
- `npm run build`: build em `dist-v2/`;
- `npm run test:v2`: testes unitários e component smoke da W0A;
- `npm run test:legacy`: suíte preservada da V1;
- `npm test`: ambas as suítes.

### Configuração pública

O contrato valida somente `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`,
`VITE_APP_ENV` e `VITE_RELEASE_ID`. Ambientes aceitos: `local`, `test`,
`staging` e `production`. A release possui fallback explícito apenas em
`local`/`test`; staging e production exigem identidade informada. Falhas exibem
mensagem segura sem reproduzir credenciais ou detalhes do provider.

`VITE_SUPABASE_ANON_KEY` é configuração pública do cliente. Mesmo assim, a
implementação não a inclui em logs e nunca admite `service_role` no frontend.

### Estrutura e limites

- `src/app`: bootstrap, config, router, providers, Query Client e AppShell;
- `src/infrastructure/supabase`: criação central do cliente tipado e tipos ainda
  vazios, sem conexão durante build/teste;
- `src/shared`: erro seguro, correlação local não autoritativa, release identity
  e primitives mínimas;
- `src/test`: setup do harness da W0A.

Pages são impedidas por ESLint de importar a infraestrutura Supabase. Não há
persistência do Query Cache, domínio, autenticação, tenant real, permissões,
migrations ou acesso remoto.

### Limite da W0A

Playwright, smoke E2E completo, Supabase/PostgreSQL local, baseline de migrations
e geração real de `database.types.ts` permanecem para W0B. A W0A não fecha o
gate `FOUNDATION_READY`.

Typecheck, lint, build e os 9 testes V2 estão verdes ao concluir a W0A. A suíte
V1 preservada continua falhando no seu harness SQL: `cw_listar_organizacoes()`
consulta `organizacoes.slug`, mas o encadeamento legado do teste não cria essa
coluna. A W0A não altera esse SQL nem enfraquece o teste.

A V1 também mantém URL e anon key públicas hardcoded no seu script histórico.
Esses valores não são importados nem incluídos no bundle V2; sua remoção ou
rotação está fora do escopo desta foundation.

## W0B — Harness de testes e banco local

A W0B adiciona a infraestrutura versionada para executar Vitest/RTL,
Playwright e Supabase/PostgreSQL local sem acessar um projeto remoto. Ela não
adiciona tabelas, Auth, tenant, membership, permissions, RLS, Storage ou domínio.

### Pré-requisitos e versões

- Node.js compatível com `package.json` e npm;
- Docker Engine ou runtime compatível, com o daemon acessível pelo comando
  `docker`, para o Supabase local;
- dependências instaladas por `npm ci`;
- Chromium do Playwright instalado uma vez por
  `npx playwright install chromium`.

Versões fixadas nesta etapa:

| Ferramenta | Versão |
| --- | --- |
| Supabase CLI | 2.117.0 |
| Playwright | 1.63.0 |

O CLI fica nas dependências de projeto e é chamado pelos scripts npm; instalação
global não é necessária. O wrapper `scripts/supabase-local.mjs` desativa a
telemetria do CLI e aceita somente comandos locais allowlisted.

### Supabase local e migrations

Os SQLs incrementais da V1 continuam diretamente em `supabase/` como evidência
legada. Eles não foram apagados, alterados, reordenados ou promovidos para a
cadeia V2. `supabase/.temp/` também continua preservado e ignorado pelo Git.

A V2 usa somente:

- `supabase/config.toml`, com projeto `cw-erp-v2-local` e portas locais;
- API e PostgreSQL local habilitados;
- Auth, Storage, Realtime, Studio, Edge Runtime e Analytics desabilitados nesta
  wave;
- `supabase/migrations/20260909000000_v2_foundation_baseline.sql`, uma migration
  intencionalmente sem DDL para provar o runner sem inventar schema de domínio;
- seed desabilitado, pois a W0B não possui fixtures de domínio.

Todos os comandos destrutivos ou de introspecção incluem `--local` no wrapper.
O wrapper não aceita argumentos extras, não usa `--linked`, `--project-ref` ou
URL de banco, e testa a disponibilidade do Docker antes de executar. Portanto,
o target de `db:reset`, `db:types` e `test:v2:db` é exclusivamente o ambiente
descartável descrito por `supabase/config.toml`.

Sequência from-zero:

```text
npm ci
npx playwright install chromium
npm run db:start
npm run db:reset
npm run db:types
npm run test:v2:all
npm run build
```

`npm run db:reset` executa `supabase db reset --local --no-seed`. Ele só deve
ser chamado para este ambiente local descartável depois de `npm run db:start`.
Nunca se deve adicionar `--linked` ou substituir o wrapper por uma connection
string remota.

`npm run db:types` executa o gerador oficial com
`supabase gen types typescript --local --schema public` e só então substitui
`src/infrastructure/supabase/database.types.ts`. Esse arquivo é gerado e não
deve receber edição manual; adaptações futuras pertencem a wrappers separados.

O smoke `npm run test:v2:db` verifica, no banco local:

1. conexão e lint do schema `public`;
2. presença da migration `20260909000000` no histórico aplicado;
3. ausência de qualquer tabela em `public` na baseline W0B.

W1 e W2 ampliarão esse mesmo harness com fixtures reproduzíveis, Tenant A,
Tenant B, constraints, RLS, commands e concorrência. Nada disso é simulado na
W0B.

Migrations ainda exercitadas somente em LOCAL/TEST descartável podem ser
ajustadas antes da publicação. Depois de promovidas para qualquer ambiente
compartilhado persistente, tornam-se imutáveis e correções exigem nova migration.

### Gates de teste

| Script | Responsabilidade |
| --- | --- |
| `npm run test:v2:unit` | Vitest + React Testing Library da V2 |
| `npm run test:v2` | alias compatível para o gate unitário V2 |
| `npm run test:v2:e2e` | Playwright/Chromium contra a entrada Vite da V2 |
| `npm run test:v2:db` | smoke PostgreSQL/Supabase exclusivamente local |
| `npm run test:v2:all` | unitário, DB local e E2E, nesta ordem |
| `npm run test:legacy` | suíte original da V1, sem skips ou expectativas alteradas |
| `npm test` | unitários V2 seguidos da suíte legada V1 |

O Vitest usa `jsdom`, setup comum com jest-dom e cleanup, e um helper pequeno
`renderWithProviders` para QueryClient e identidade técnica de teste. Ele não
cria arquitetura fake de Auth ou tenant.

O Playwright usa porta/baseURL exclusivos (`127.0.0.1:4173`) e inicia/encerra o
Vite programaticamente no lifecycle global do runner. Essa alternativa mantém
o servidor automático e evita o encerramento retido por `taskkill /T` observado
no `webServer` do Playwright neste Windows. Os testes cobrem `/`, rota tenant
opaca, rota de plataforma, deep link inexistente, refresh e back/forward.

### Evidência desta execução

Em 2026-09-10, Node.js 24.19.0 e npm 11.17.0 executaram:

- typecheck: PASS;
- lint: PASS;
- Vitest/RTL: PASS, 3 arquivos e 9 testes;
- Playwright/Chromium: PASS, 4 testes;
- build: PASS;
- Supabase local start: PASS;
- Supabase local reset: PASS;
- geração oficial de `database.types.ts`: PASS;
- DB smoke: PASS, com a migration `20260909000000` aplicada e o schema
  `public` sem tabelas;
- `git diff --check`: PASS, sem erros de whitespace.

`database.types.ts` foi regenerado pelo Supabase CLI a partir do banco local,
sem edição manual. O wrapper normaliza somente o EOF do conteúdo gerado para
uma única quebra de linha final antes de gravar o arquivo.

A suíte V1 continua separada e não foi silenciada. O encadeamento legado
reproduz `column o.slug does not exist` em `cw_listar_organizacoes()` porque não
aplica previamente o SQL que cria a coluna. Execuções isoladas confirmaram ainda
que `interface.test.mjs` e `interface-v2.test.mjs` passam, enquanto
`admin-users.test.mjs` possui outra falha preexistente (`400 !== 200`) no mock da
cadeia `delete().eq(...)`. Os arquivos envolvidos são idênticos ao HEAD inicial
`8b5fc59`; não são regressões da W0B.

Nenhum Supabase remoto, PostgreSQL remoto, Auth remoto, Storage remoto, GitHub
API, produção, push ou deploy foi acessado. Com todos os gates da W0B aprovados,
esta etapa declara `W0B_COMPLETE`. A W0C permanece obrigatória antes de
`FOUNDATION_READY`, que continua `PENDING`.
