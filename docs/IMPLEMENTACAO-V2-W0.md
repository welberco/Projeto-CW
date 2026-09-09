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
