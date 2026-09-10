# Plano técnico da W1 — Identity / Tenant / Membership

## 1. Objetivo

Planejar a W1 para entregar autenticação, identidade da aplicação, tenant,
membership, sessão e contexto tenant seguros sobre a foundation aprovada no
commit `3c446de51e92f010cd26182487dcefa8c45b51b6`.

O resultado esperado da futura implementação é um usuário autenticado que só
alcança o próprio contexto tenant autoritativo, com lifecycle explícito,
primeira RLS deny-by-default, cache limpo em mudanças de contexto e testes reais
Tenant A/Tenant B no Supabase local.

Este documento é somente planejamento. Ele não inicia schema, migration, código,
configuração, dependência nem a branch de implementação da W1.

## 2. Fontes, precedência e decisões consolidadas

Fontes revisadas integralmente ou nas seções aplicáveis:

1. `PRODUCT_SPEC.md`, fonte funcional;
2. `AGENTS.md`, regras de execução e segurança;
3. `docs/ARQUITETURA-TECNICA-V2.md`, baseline técnica congelada;
4. `docs/MIGRACAO-V1-V2-10E-PLANO-IMPLEMENTACAO.md`, plano oficial das waves;
5. `docs/IMPLEMENTACAO-V2-W0.md`, estado real da foundation;
6. código, testes, configurações e migrations atuais da W0.

Quando uma formulação desta solicitação diverge das fontes congeladas, a regra
funcional do `PRODUCT_SPEC.md` e as decisões `CLOSED` da arquitetura prevalecem;
o plano 10E determina o conteúdo específico da wave. Uma mudança nessas fontes
exige decisão explícita e change control, não uma escolha silenciosa na W1.

| Tema originalmente divergente | Fonte prevalente | Decisão consolidada |
| --- | --- | --- |
| A formulação inicial considerava um usuário comum em várias empresas; produto, arquitetura e 10E exigem um único tenant operacional | `PRODUCT_SPEC` §1.2, Arquitetura §7 `CLOSED`, 10C §8 e 10E §14 | O schema preserva vínculos históricos N:N, mas impede duas memberships operacionais simultâneas. User AB é somente teste negativo. Global Admin continua futuro. |
| A formulação inicial postergava todo Audit para W3; a W1 oficial exige Audit append-only mínimo | 10E W1, seus critérios de saída e Arquitetura §21 | W1 cria somente o substrato mínimo transacional; W3 o consolida com History, Outbox, idempotência e command infrastructure, sem duplicação. |
| A solicitação nomeia `IDENTITY_TENANT_READY`; o plano oficial usa `AUTH_READY` e `TENANT_READY` | Catálogo de gates 10E | Usar `IDENTITY_TENANT_READY` apenas como agregador: aprovado se, e somente se, ambos os gates oficiais passarem. |
| `BD-01` exigia definição de entitlement e estado inicial | 10E W1 e registro de blockers | Product Owner aprovou `maintenance = enabled` e primeiro tenant `active`, exclusivamente após bootstrap consistente. Alterações futuras pertencem à Plataforma/Global Admin. |

## 3. Escopo

Incluído na W1:

- Supabase Auth como autoridade de autenticação;
- Application User e seus estados;
- tenant/Empresa e seus estados;
- membership única para usuário comum;
- convite/provisionamento administrativo sem signup público;
- sessão, bootstrap do contexto e logout;
- resolução segura de `/e/:tenantRef/*`;
- primeira RLS mínima sobre identidade/tenant/membership;
- contexto e disciplina de cache tenant-aware;
- Empresa e Minha Conta apenas no mínimo necessário à identidade/contexto;
- Audit mínimo append-only e transacional exigido pela W1 oficial;
- testes DB/RLS, integração Auth local, unitários e E2E;
- preparação tipada para W2.

## 4. Fora de escopo

- catálogo Resource + Action + Scope, Perfis-base, overrides e antiescalada;
- Equipes e membership de Equipe;
- console ou autoridade operacional de Global Admin;
- qualquer domínio de Solicitação, OS, Ativo, Fornecedor ou Preventiva;
- Storage, avatar, logo e mídia;
- History, Outbox e Audit completo;
- migração de identidades V1, preservação de UUID/senha/sessão V1 e Path A/B;
- billing, checkout, administração comercial e limites completos;
- cadastro público;
- sessão transparente entre projetos;
- acesso, revalidação ou alteração remota.

## 5. Modelo conceitual

```text
auth.users (Auth Identity)
    1
    |
    1
public.app_users (Application User)
    1
    |
    0..N históricos; no máximo 1 membership operacional
    |
public.tenant_memberships
    N
    |
    1
public.tenants (Empresa/Empreendimento)

public.tenant_invitations
    → convite one-time ligado a tenant e identidade/e-mail verificado

public.tenant_entitlements
    → maintenance = enabled no bootstrap inicial aprovado
```

Cardinalidade consolidada:

```text
historicamente:   User N:N Tenant
operacionalmente: User comum 1:1 Tenant
contexto atual:   exatamente um tenant
```

Conceitos deliberadamente separados:

```text
AUTHENTICATION
!= APPLICATION USER / IDENTITY
!= TENANT MEMBERSHIP
!= ACTIVE CONTEXT
!= AUTHORIZATION RESOURCE + ACTION + SCOPE
!= PLATFORM IDENTITY
```

`Profile` não será o nome da identidade pessoal: no produto, Perfil é baseline
de autorização da W2. O nome recomendado para a identidade da aplicação é
`app_users`.

## 6. Modelo de dados proposto

### 6.1 `public.app_users`

Tabela global de identidade da aplicação, não tenant-owned.

| Campo | Regra W1 |
| --- | --- |
| `id uuid` | PK e FK 1:1 para `auth.users(id)`; mesmo UUID da identidade Auth target, sem prometer preservar UUID V1 |
| `status text` | `active`, `blocked` ou `inactive`, com check constraint |
| `display_name text` | nome de exibição mínimo; não é autoridade e pode começar incompleto durante convite |
| `contact_phone text` | opcional e somente se a tela Minha Conta for incluída no bloco W1D; não é fator Auth |
| `created_at timestamptz` | atribuído pelo banco |
| `updated_at timestamptz` | atribuído pelo banco em update permitido |
| `blocked_at timestamptz` | obrigatório quando status for `blocked` |
| `inactivated_at timestamptz` | obrigatório quando status for `inactive` |
| `version bigint` | inicia em 1 e incrementa em alteração concorrente |

Não duplicar e-mail, senha, password hash, providers, MFA, telefone usado como
fator Auth, token, sessão, confirmation state ou `raw_*_meta_data`. Esses fatos
pertencem ao Supabase Auth. `created_by` não deve existir em `app_users`: a
origem é a própria criação autoritativa em `auth.users`; o evento de criação é
registrado no Audit mínimo.

### 6.2 `public.tenants`

Tabela da Empresa/Empreendimento cliente.

| Campo | Regra W1 |
| --- | --- |
| `id uuid` | PK interna, gerada pelo banco |
| `tenant_ref uuid` | UUID v4 público opaco, aleatório, único e separado da PK |
| `display_name text` | nome mínimo obrigatório exibido na UI |
| `status text` | `active`, `suspended` ou `inactive` |
| `created_at`, `updated_at` | timestamps do banco |
| `created_by uuid` | FK para `app_users`, derivada do ator do bootstrap/provisionamento |
| `suspended_at`, `inactivated_at` | coerentes com status por constraint |
| `version bigint` | controle otimista para mudanças futuras |

Código humano `EMP-00001`, razão social, nome fantasia separado, documento
fiscal, endereço, timezone, preferências, identidade visual, limites e
configurações de Manutenção ficam fora do núcleo W1. Só devem entrar no bloco
Empresa quando houver caso de uso aprovado; nenhum deles participa da autoridade
tenant.

### 6.3 `public.tenant_memberships`

Associação entre Application User e tenant. O nome é preferível a
`company_users` porque explicita que a linha é um vínculo com lifecycle próprio,
não um segundo cadastro de usuário, e mantém consistência com `tenant_id`.

| Campo | Regra W1 |
| --- | --- |
| `id uuid` | PK interna gerada pelo banco |
| `tenant_id uuid` | FK para `tenants(id)`, não derivada do payload do cliente |
| `user_id uuid` | FK para `app_users(id)`, não aceita como ator autoritativo |
| `status text` | `active`, `blocked` ou `revoked` |
| `joined_at timestamptz` | preenchido na ativação |
| `blocked_at timestamptz` | preenchido durante bloqueio |
| `revoked_at timestamptz` | preenchido na revogação terminal |
| `created_at`, `updated_at` | timestamps do banco |
| `created_by uuid` | ator autoritativo do provisionamento |
| `version bigint` | concorrência e detecção de contexto stale |

Constraints e índices mínimos:

- unique `(tenant_id, user_id)` para preservar um único lifecycle do vínculo;
- unique parcial em `user_id` para status `active` ou `blocked`, garantindo que
  usuário comum não pertença operacionalmente a dois tenants;
- checks de coerência status/timestamps;
- índices `(user_id, status)` e `(tenant_id, status)`;
- `ON DELETE RESTRICT`; desligamento ocorre por status, não hard delete;
- nenhuma coluna de Perfil, role, permission ou scope.

### 6.4 `public.tenant_invitations`

Convite é separado de membership para não misturar uma intenção pendente com um
vínculo já criado.

Campos mínimos: `id`, `invite_ref` opaco, `tenant_id`, `invited_user_id`
opcional, hash normalizado do e-mail verificado, status
`pending|accepted|revoked|expired`, `expires_at`, `accepted_at`, `revoked_at`,
`created_at`, `updated_at`, `invited_by` e `version`.

Não guardar token Auth. O `invite_ref` é locator, não autoridade. Aceite exige
sessão Auth válida, identidade/e-mail verificado compatível, convite pendente e
não expirado, tenant apto e ausência de membership operacional em outro tenant.

### 6.5 `public.tenant_entitlements`

O plano 10E exige entitlement explícito antes de uma operação tenant. `BD-01`
está fechado: o primeiro tenant recebe `maintenance = enabled` e fica `active`
somente como resultado do bootstrap completo e consistente.

O schema mínimo possui PK `(tenant_id, module_key)`, `enabled`, `created_at`,
`updated_at` e autoria necessária. Não inclui billing, planos, checkout, limites,
períodos de cobrança nem administração comercial. Alterações futuras de
entitlement e disponibilidade comercial pertencem à Plataforma/Global Admin,
nunca ao administrador comum do tenant.

## 7. Auth e Application User

Supabase Auth é autoridade para autenticação, sessão, e-mail verificado,
password/recovery e providers. `app_users` é autoridade apenas para identidade
e lifecycle da aplicação.

Decisões consolidadas:

- `app_users.id = auth.users.id` reduz mapeamento e impede identidade órfã;
- todo usuário autenticado com acesso operacional precisa de `app_users`;
- trigger `AFTER INSERT` em `auth.users` cria somente a linha mínima, sem copiar
  metadata não confiável;
- a função do trigger é mínima, `SECURITY DEFINER`, com `search_path` fixo,
  objetos qualificados e sem `PUBLIC EXECUTE`;
- criação de Auth falha se a criação da identidade mínima falhar; não usar
  `ON CONFLICT DO NOTHING` como mascaramento;
- se Auth já existir sem `app_users`, o bootstrap retorna estado
  `profile_missing`, nega contexto tenant e exige reparo administrativo
  controlado; nunca cria profile por fallback de leitura;
- alteração de e-mail/senha e recovery usam exclusivamente fluxos Auth;
- `app_users.status != active` bloqueia contexto mesmo com JWT ainda válido.

O termo de UI “perfil pessoal” pode existir, mas não deve gerar uma tabela
`profiles` que se confunda com Perfil de autorização.

## 8. Tenant / Empresa

`tenants` representa o Empreendimento cliente. Seu UUID interno é autoridade de
relação no banco; `tenant_ref` é apenas locator de rota. A operação tenant exige:

```text
authenticated
AND app_user active
AND active membership
AND target tenant = membership tenant
AND tenant active
AND entitlement explicitamente enabled
```

Tenant `suspended` ou `inactive` não autoriza operação. Suspensão é reversível;
inativação é encerramento lógico duradouro. O primeiro tenant só alcança
`active` no commit do bootstrap consistente, junto com membership,
`maintenance = enabled` e Audit mínimo. Nenhum usuário tenant altera status,
entitlement ou `tenant_ref` na W1.

## 9. Membership

Lifecycle mínimo:

```text
active → blocked → active
active|blocked → revoked
revoked → terminal na W1
```

`invited` não é status de membership; pertence a `tenant_invitations`.
`inactive` não é adicionado porque duplicaria `revoked` sem semântica aprovada.

O usuário comum operacional tem exatamente uma membership `active` ou
`blocked`. Uma segunda associação só pode ser criada depois da revogação da
anterior, em command transacional e auditável. Isso não implementa seleção
multiempresa para usuário comum.

## 10. Bootstrap do primeiro tenant e usuário

### 10.1 Fluxo principal aprovado

- usa runner operacional one-time executado fora do browser;
- ocorre uma única vez por instalação/ambiente;
- não é endpoint público e não revela se o sistema está inicializado;
- não contém senha, usuário real ou token em migration/seed/repositório;
- não usa service role no frontend;
- serializa concorrência com advisory transaction lock;
- confirma zero tenants e zero memberships antes de criar;
- cria tenant, membership inicial, `maintenance = enabled`, Audit mínimo e muda
  o tenant para `active` em uma única transação após a identidade Auth existir;
- repetições retornam `SYSTEM_ALREADY_INITIALIZED` sem mutation parcial;
- tenants posteriores pertencem a command de plataforma futuro, não ao bootstrap.

Fluxo conceitual:

```text
Auth Identity
→ Application User
→ advisory transaction lock
→ verificar sistema não inicializado
→ criar primeiro tenant ainda não operacional
→ criar membership inicial
→ criar maintenance entitlement enabled
→ registrar Audit mínimo
→ tenant active
→ commit
```

Qualquer falha da transação não ativa o tenant nem deixa membership operacional
parcial. Se a identidade Auth já tiver sido criada, ela permanece sem contexto e
sem acesso até retry/reparo controlado.

### 10.2 Execução por ambiente

| Ambiente | Fluxo |
| --- | --- |
| LOCAL | Runner operacional cria Auth user descartável com segredo apenas no processo e chama procedure DB não concedida a `anon/authenticated`; sem senha versionada |
| TEST/CI | Mesmo contrato, dados aleatórios por execução, teardown/rebuild; seed de domínio permanece desabilitado |
| STAGING | Operador autorizado cria/convida a identidade no provider e executa procedure one-time por canal administrativo, com evidência e dupla revisão |
| PRODUCTION | Operação manual controlada equivalente, janela aprovada, target explícito, Audit e confirmação pós-condição; não será executada nem testada remotamente na W1 local |

Migration cria somente estrutura/procedure, nunca dados de pessoa/tenant. Variável
de ambiente não é autoridade suficiente isoladamente. A procedure permanece sem
grants de cliente e, depois de inicializado, a precondição de ausência de tenant
torna novo uso impossível. A capacidade/credencial operacional é desabilitada
após o sucesso; eventual remoção da procedure ocorre por migration revisada.

## 11. Cadastro e convite

- signup público deve ser desabilitado na configuração Auth;
- W1 prova convite/provisionamento pelo provider, mas não cria tela de gestão de
  usuários nem autorização tenant improvisada;
- até W2, convites adicionais são operação controlada de provisionamento,
  server-side/ops, não um botão liberado por role hardcoded;
- o provider envia e-mail transacional Auth; a aplicação não envia e-mail
  operacional próprio;
- convite é ligado a `tenant_id`, `invite_ref`, identidade/e-mail verificado,
  validade e ator;
- link roubado não basta: aceite exige controle da identidade Auth convidada;
- expiração é obrigatória; prazo concreto deve ser configuração server-side;
- reenvio revoga/substitui o convite pendente anterior de forma transacional;
- revogação impede aceite posterior;
- aceite duplo é impedido por update condicional de `pending` para `accepted` e
  constraints de membership;
- e-mail já associado a membership operacional em outro tenant recebe resposta
  externa não enumerativa e não é convidado;
- o e-mail não é duplicado em `app_users`; no convite guarda-se somente o mínimo
  para vinculação segura, preferencialmente hash normalizado;
- o comportamento exato do Supabase local para convite, criação antecipada de
  `auth.users` e callback deve ser provado em W1B; não será assumido.

## 12. Empresa ativa

Sob a regra congelada de uma membership operacional, não há seletor de empresa
para usuário comum na W1. O tenant ativo é derivado da única membership ativa.

Estado cliente:

- URL contém o `tenant_ref` opaco;
- memória do `SessionProvider` contém a projeção de contexto autorizada;
- QueryClient contém apenas queries chaveadas pelo principal/contexto e tenant;
- não criar cookie, claim customizado, localStorage ou sessionStorage de empresa
  ativa;
- sessão Auth pode usar a persistência segura padrão do SDK, mas a aplicação não
  duplica token nem tenant em storage próprio.

Se uma mudança futura permitir múltiplas memberships comuns, ela exige alteração
formal do produto/arquitetura e novo desenho de seleção; não deve ser preparada
silenciosamente agora.

## 13. `tenantRef`

Decisão aprovada para `DEC-01`:

- UUID v4 aleatório separado de `tenants.id`;
- único globalmente, não semântico e não sequencial;
- estável para preservar links; rotação somente por command de plataforma futuro;
- não contém slug, nome, código humano ou dado do cliente;
- resolve no banco junto com `auth.uid()`, app user, membership, tenant status e
  entitlement;
- jamais é convertido em `tenant_id` confiável no frontend;
- tenant inexistente e tenant sem membership retornam o mesmo resultado externo
  `TENANT_CONTEXT_UNAVAILABLE`, sem confirmar existência;
- tenant suspenso do próprio usuário pode produzir estado específico somente
  após o vínculo já ter sido provado pelo resolver autoritativo;
- lookup deve ser indexado por unique constraint.

## 14. Sessão e bootstrap da aplicação

Fluxo:

```text
BOOTING
→ Auth session
  ├─ ausente → UNAUTHENTICATED
  └─ válida → carregar contexto server-side
       ├─ app_user ausente → PROFILE_MISSING
       ├─ app_user blocked/inactive → PRINCIPAL_UNAVAILABLE
       ├─ membership ausente → NO_MEMBERSHIP
       ├─ membership blocked/revoked → MEMBERSHIP_UNAVAILABLE
       ├─ tenant suspended/inactive → TENANT_UNAVAILABLE
       ├─ entitlement disabled → FEATURE_UNAVAILABLE
       └─ tudo válido → READY(authorized context)
```

Comportamentos:

- carregamento inicial e refresh sempre reexecutam o resolver;
- token refresh não troca tenant; revalida contexto antes de continuar queries
  sensíveis se identidade/claims mudarem;
- logout cancela requests, limpa cache/estado, encerra sessão Auth e volta a
  `/login`;
- sessão expirada segue o mesmo cleanup antes de mostrar estado seguro;
- mudança de usuário nunca reutiliza contexto/cache do principal anterior;
- membership/tenant revogado é aplicado imediatamente pela RLS mesmo com token
  ainda válido; quando detectado pela UI, dispara cleanup e revalidação;
- múltiplas abas dependem dos eventos Auth suportados pelo SDK e revalidam no
  foco; não criar protocolo customizado antes de provar necessidade;
- JWT metadata nunca fornece tenant, Perfil ou membership autoritativos.

## 15. Cache e troca de contexto

Contrato mínimo reutilizável:

```text
ContextIdentity = {
  principalId,
  tenantId,
  membershipId,
  membershipVersion,
  contextGeneration
}

tenant query key =
  principal/context
  + tenant
  + resource/query
  + filters
  + sensitive projection quando aplicável
```

`ContextIdentity` melhora isolamento de cache, mas não autoriza requests.

| Evento | Ação obrigatória |
| --- | --- |
| Login | limpar estado anônimo transitório, carregar contexto antes de queries tenant |
| Logout/sessão expirada | bloquear novas queries, cancelar inflight, `queryClient.clear()`, limpar seleção/estado visual e navegar para login |
| Troca de usuário | mesmo cleanup total; criar nova geração de contexto |
| Membership revogada/bloqueada | DB nega; ao detectar, cancelar/limpar cache tenant e revalidar router/contexto |
| Tenant suspenso/inativo | impedir novas queries, limpar cache tenant e mostrar estado seguro |
| Mudança de tenant | `NOT_APPLICABLE` para usuário comum na W1; não implementar seletor |

Preferir `cancelQueries` seguido de `clear` no logout/troca de principal. Apenas
`invalidateQueries` não é suficiente porque mantém payload antigo renderizável.

## 16. RLS mínima deny-by-default

Princípios:

- habilitar RLS na mesma migration que cria cada tabela exposta;
- revogar privilégios amplos e conceder apenas operações necessárias;
- ator sempre deriva de `auth.uid()`;
- `tenant_id`, `user_id`, JWT metadata, URL ou payload nunca concedem acesso;
- INSERT/UPDATE críticos ocorrem por commands server-side estreitos;
- DELETE de cliente não possui grant/policy;
- policy de UPDATE não substitui allowlist de colunas/command;
- resposta por tenant ref não diferencia inexistente de não autorizado.

| Tabela | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `app_users` | próprio `id = auth.uid()`; projeção pública mínima | somente trigger/provisionamento | próprio `display_name` e eventual `contact_phone` via command/column grant; status nunca pelo próprio usuário | nenhum |
| `tenants` | apenas tenant alcançado por principal ativo + membership ativa + tenant ativo; projeção mínima | somente bootstrap/platform provisioning | nenhuma alteração direta na W1; config por command autorizado quando a autoridade estiver definida | nenhum |
| `tenant_memberships` | somente a própria membership; listagem de terceiros aguarda W2 | somente provisionamento/convite protegido | bloqueio/revogação/reativação por command protegido | nenhum |
| `tenant_invitations` | sem leitura direta genérica; resolver/command retorna projeção mínima ao convidado correto | command protegido | aceite/reenvio/revogação condicionais em command | nenhum |
| `tenant_entitlements` | somente via contexto/projeção autorizada | provisionamento controlado após `BD-01` | platform command futuro | nenhum |

O próprio usuário não altera status, tenant, membership, `tenant_ref`,
entitlement, `created_by` ou timestamps protegidos.

## 17. Helpers RLS e resolver

Helpers mínimos propostos:

1. `private.is_active_principal()` — sem parâmetros; usa `auth.uid()` e verifica
   `app_users.status = active`;
2. `private.can_access_tenant(target_tenant_id uuid)` — aceita apenas o target a
   confrontar, deriva ator com `auth.uid()` e verifica principal, membership,
   tenant e entitlement;
3. `public.resolve_my_tenant_context(target_tenant_ref uuid default null)` — RPC
   de query sem efeito colateral que retorna somente a projeção autorizada do
   próprio contexto ou zero linha/erro estável não enumerativo.

Regras físicas:

- evitar helper se expressão RLS simples e não recursiva for suficiente;
- `SECURITY DEFINER` somente quando necessário para romper circularidade;
- owner controlado, `search_path` vazio/fixo, nomes totalmente qualificados;
- `REVOKE ALL ... FROM PUBLIC` e grants exatos apenas para `authenticated`;
- nenhuma função recebe `user_id` como autoridade;
- nenhuma função confia em `tenant_id` sem confrontar membership;
- policies de membership não consultam tenant por caminho que volte à própria
  policy; testes de plano de execução/recursão são obrigatórios;
- helpers são pequenos, estáveis e cobertos diretamente.

## 18. Plano de testes Tenant A / Tenant B

### DB/RLS reais no Supabase local

- User A + Tenant A e User B + Tenant B;
- A lê a própria identidade, membership e Tenant A;
- A não lê Tenant B nem memberships de B;
- B não lê Tenant A nem memberships de A;
- inserts/updates/deletes diretos são negados conforme matriz;
- `user_id` e `tenant_id` forjados não ampliam acesso;
- tenantRef B usado por A retorna o mesmo resultado de ref inexistente;
- app user bloqueado/inativo perde contexto com JWT ainda válido;
- membership bloqueada/revogada perde acesso;
- tenant suspenso/inativo perde acesso;
- metadata JWT adulterada com tenant/role não altera decisão;
- tentativa de segunda membership ativa para User AB falha por constraint e
  command; não é cenário positivo nesta baseline;
- aceite concorrente do mesmo convite produz uma única membership;
- bootstrap concorrente produz exatamente um tenant/membership inicial;
- helper/RPC não possui `PUBLIC EXECUTE` indevido.

Asserções de RLS usam clientes autenticados/JWTs reais do Auth local. Service
role pode existir somente no harness administrativo para arrange/cleanup e nunca
serve de evidência de permissão positiva do usuário.

### Unitários

- state machine de sessão/contexto;
- mapeamento de erros para estados seguros;
- cache cleanup por evento;
- composição de query key com principal/contexto e tenant;
- parsing de `tenantRef` sem tratá-lo como tenant ID;
- transições de status puras e invariantes de convite.

### Integração

- Auth local: login, refresh, logout, recovery/invite suportado;
- trigger Auth → `app_users`;
- missing profile sem fallback;
- resolver de contexto e responses não enumerativas;
- eventos Auth acionam cleanup e reload corretos.

### E2E

- ausência de signup público;
- login válido e inválido;
- callback/recovery sem dados sensíveis na UI;
- deep link do próprio tenant e refresh;
- manipulação para tenant B/inexistente com resposta indistinguível;
- logout/back não reexibe payload tenant;
- sessão expirada, principal bloqueado e tenant suspenso;
- duas abas: logout propagado ou revalidado conforme comportamento provado do
  SDK local;
- mobile smoke das rotas de login/contexto/sem acesso.

## 19. Fronteira W1 / W2

W1 implementa somente a condição basal:

```text
authenticated
+ principal active
+ context valid
+ membership active
+ tenant operational
+ entitlement enabled
```

W2 adicionará, sem substituir a base:

```text
Resource + Action + Scope
+ Perfil baseline
+ overrides exatos
+ capabilities de UI
+ antiescalada
+ policies/commands por ação
```

W1 não cria role `admin`, `gestor`, `owner`, permission JSON, capability fake,
menu como segurança ou bypass temporário. Administração de memberships por
usuário tenant só começa quando W2 definir autoridade delegável.

## 20. Global Admin

`DEFERRED_BY_DESIGN` para W13, com foundations de commands/Audit em W3. W1 não
cria Platform Identity, console, impersonação, union cross-tenant ou flag
`bypass=true`.

O bootstrap one-time é autoridade técnica/operacional fora dos endpoints tenant;
não transforma o primeiro usuário em Global Admin. O namespace `/plataforma/*`
continua apenas boundary técnica.

## 21. Audit mínimo e auditoria futura

A baseline 10E exige que mudanças críticas da W1 já sejam auditadas de forma
append-only e transacional. A decisão aprovada é um substrato `audit_events`
sem UI, History ou Outbox, com:

- `id`, `occurred_at`, `tenant_id` quando aplicável;
- actor Auth/Application User ou autoridade técnica identificada;
- contexto/correlação;
- tipo de evento allowlisted;
- entidade/registro target;
- metadata segura mínima, sem token, senha, e-mail completo ou payload bruto.

Eventos W1 obrigatórios: bootstrap, criação de tenant, criação/aceite/reenvio/
revogação de convite, criação/bloqueio/inativação de app user, criação/bloqueio/
revogação de membership, mudança de tenant status e entitlement.

W3 consolidará o mesmo substrato com schema/retention completos, leitura
autorizada, History, Outbox, idempotência, workers e command SDK genérico. W1
não cria infraestrutura concorrente nem antecipa esses elementos.

## 22. Exclusão e inativação

| Entidade | Operação normal | Hard delete |
| --- | --- | --- |
| Auth identity user | bloquear/inativar no Application User e usar fluxo Auth compatível | excepcional, após análise de referências/retenção |
| `app_users` | `blocked` reversível; `inactive` lógico | proibido para usuário comum |
| `tenants` | `suspended` reversível; `inactive` lógico | operação de plataforma excepcional futura |
| `tenant_memberships` | `blocked` reversível; `revoked` terminal | não usado no fluxo normal |
| `tenant_invitations` | `revoked` ou `expired`; aceitos preservados | apenas expurgo futuro por retenção aprovada |

FKs usam `RESTRICT` por padrão para impedir que remoção Auth apague histórico em
cascata. Reativação respeita constraints de membership única.

## 23. Dados pessoais

W1 mantém somente:

- `display_name` necessário à identificação humana;
- `contact_phone` opcional apenas se Minha Conta realmente o editar;
- hash normalizado do e-mail durante convite, quando indispensável à vinculação.

E-mail canônico, telefone de autenticação, providers, verification state, senha,
MFA e sessões ficam em Auth. Avatar/Storage e cargo/função ficam deferidos.
CPF não é criado. Logs e Audit não armazenam e-mail completo, token ou payload
de formulário.

## 24. Migrations planejadas

Fixtures nunca entram em migration ou seed de domínio; testes criam seus dados
por harness local após reset.

| Ordem | Migration | Objetivo/dependências | Risco e rollback lógico | Validação isolada |
| --- | --- | --- | --- | --- |
| 1 | `w1_identity_core` | criar `app_users`, checks, índices, trigger Auth e RLS/grants seguros; depende apenas da baseline W0 | trigger pode impedir criação Auth; corrigir por nova migration após publicação, ou reset local antes dela | criar Auth local, confirmar 1:1, missing/duplicate e RLS own-only |
| 2 | `w1_tenant_membership_core` | criar `tenants`, `tenant_memberships`, `tenant_invitations` e `tenant_entitlements`; RLS habilitada na mesma transação | constraint excessiva pode bloquear lifecycle; forward fix ou reset local | constraints, segunda membership, statuses, `maintenance = enabled`, cross-tenant e grants |
| 3 | `w1_identity_audit_and_provisioning` | criar Audit mínimo e procedures protegidas de bootstrap/convite/status; depende das tabelas core | authority/grants incorretos são blocker; revogar/forward fix | concorrência, atomicidade, audit failure, no public execute |
| 4 | `w1_context_resolver_rls` | criar helpers mínimos, policies finais e resolver de contexto; depende de lifecycle/entitlement | recursão ou policy permissiva; deny-by-default permanece durante correção | matriz SELECT/INSERT/UPDATE/DELETE, A/B, explain/recursão, anti-enumeration |

Cada migration cria um estado intermediário seguro. Nenhuma tabela fica exposta
sem RLS/grants adequados aguardando migration posterior. Após schema final:

1. `npm run db:reset`;
2. `npm run db:types` sem edição manual;
3. `npm run test:v2:db` e suíte W1 completa;
4. revisão de diff/tipos/checksums.

## 25. Services e boundaries TypeScript

Evitar uma camada de services genérica. Contratos mínimos:

| Boundary | Responsabilidade | Dependência permitida |
| --- | --- | --- |
| `AuthGateway` | sessão, login, logout, refresh, recovery e callback/invite Auth | implementação em `infrastructure/supabase`; não conhece tenant |
| `loadSessionContext` | query única sem side effect para Application User + membership + tenant autorizado | chama resolver tipado; não aceita `user_id` como autoridade |
| `SessionProvider` / state machine | orquestra Auth state, contexto, rotas e estados UI | app pode depender de AuthGateway/query boundary, nunca do raw client em page |
| `clearPrincipalContext` | cancela/limpa QueryClient e estado visual em transição | recebe QueryClient e callback de router; sem storage próprio |
| provisioning commands | bootstrap/convite/status controlados | server-side/DB; payload não decide ator/tenant |

Estrutura física provável, criada somente quando houver conteúdo:

```text
src/app/session/
src/app/pages/login-page.tsx
src/app/pages/recovery-page.tsx
src/infrastructure/supabase/auth-gateway.ts
src/infrastructure/supabase/session-context.ts
src/shared/contracts/ (somente contratos realmente compartilhados)
tests/db/w1/
tests/e2e/w1/
```

Pages/hooks não importam o raw Supabase client; o ESLint deve ampliar a regra
para os novos diretórios quando eles forem criados.

## 26. Rotas W1

| Rota/estado | Decisão |
| --- | --- |
| `/login` | necessária; sem link de signup |
| `/recuperar-acesso` | necessária se recovery for provado na W1 |
| `/auth/callback` | necessária conforme fluxo PKCE/invite/recovery confirmado no Auth local |
| `/e/:tenantRef/*` | existente; protegida por bootstrap de sessão/contexto |
| `/sem-acesso` | pode reutilizar o estado existente; resposta não enumera tenant |
| `/sessao-expirada` | preferir estado/redirect para `/login?reason=expired` sem dado sensível; rota separada somente se UX exigir |
| `/selecionar-empresa` | `NOT_APPLICABLE` sob membership única; não criar |

Não criar gestão de usuários, Perfis ou permissões na W1.

## 27. Estados de UI

Estados explícitos:

- loading Auth;
- unauthenticated;
- sessão expirada;
- authenticated com `app_users` ausente;
- profile pessoal incompleto, se display name for obrigatório ao onboarding;
- app user bloqueado/inativo;
- sem membership;
- membership bloqueada/revogada;
- tenant suspenso/inativo;
- entitlement indisponível;
- tenantRef inválido ou não autorizado, com resposta indistinguível;
- contexto ready;
- erro/rede indisponível com mensagem segura.

Não renderizar payload tenant anterior durante transições. Estados devem ser
acessíveis e responsivos, com foco/labels e sem depender apenas de cor.

## 28. Matriz de autoridade

| Dado/decisão | Autoridade |
| --- | --- |
| autenticação, password, recovery, e-mail verificado, provider | Supabase Auth |
| user ID autenticado | `auth.uid()` |
| identidade/lifecycle da aplicação | `public.app_users` |
| nome/telefone de contato da conta | `app_users`, editados por contract próprio |
| tenant/Empresa e status | `public.tenants` |
| vínculo usuário ↔ tenant | `public.tenant_memberships` |
| convite e validade | `public.tenant_invitations` + Auth provider |
| entitlement habilitado | `tenant_entitlements`; bootstrap inicial grava `maintenance = enabled` |
| tenant ativo do usuário comum | única membership ativa validada no banco |
| contexto em memória | projeção navegacional; não autoriza |
| `tenantRef` | seletor de navegação somente |
| tenant efetivo autorizado | DB/RLS/resolver confrontando `auth.uid()` e fatos atuais |
| JWT metadata customizada | não autoritativa para tenant/role/membership |
| query cache | cópia temporária isolada por principal/contexto + tenant |
| status/bloqueio/revogação | commands protegidos e estado no banco/Auth conforme conceito |
| Perfil, Resource, Action, Scope, override | W2 |
| Global Admin | Platform Identity/commands em W13 |
| Audit mínimo de lifecycle W1 | append-only transacional requerido pelo plano 10E |
| History/Outbox/Audit completo | W3 |
| migrations/fixtures local | migrations versionadas / harness de teste, nunca UI |

## 29. Threat model W1

| Ameaça | Impacto | Mitigação W1 | Mitigação futura | Teste obrigatório |
| --- | --- | --- | --- | --- |
| trocar `tenantRef` manualmente | leitura cross-tenant/enumeration | resolver confronta ref com membership derivada; resposta uniforme | W2 adiciona capability | A usa ref B e ref inexistente, mesmo resultado |
| forjar `tenant_id` | acesso/escrita indevida | RLS/commands derivam tenant; payload apenas target confrontado | actions W2 | REST/RPC com Tenant B negado |
| forjar `user_id` | agir como outro usuário | ator exclusivo `auth.uid()` | commands W2/W3 reautorizam | payload user B não muda ator |
| membership stale membership | acesso após revogação | RLS consulta estado atual; UI limpa ao detectar | eventos/observability W3/W14 | JWT ainda válido após revoke é negado |
| app user bloqueado com sessão válida | continuidade de acesso | condição `principal active` em resolver/RLS | gestão lifecycle W2 | bloquear A e repetir queries |
| tenant suspenso | operação em cliente suspenso | tenant status integra condição basal | W13 define operações de plataforma | suspender A e negar acesso |
| cache do tenant anterior | vazamento visual | keys por contexto/tenant; cancel + clear | projections por capability W2 | trocar principal e verificar cache vazio |
| aba antiga | payload stale após logout/revoke | eventos Auth + revalidação no foco; DB nega sempre | canal operacional se necessário | logout em aba 1, revalidar aba 2 |
| convite roubado | takeover de membership | convite não basta; exige identidade/e-mail Auth verificado | rate limit/monitoring W14 | usuário diferente tenta aceitar |
| convite reutilizado | membership duplicada | update condicional one-time + uniqueness | idempotency kernel W3 | aceite concorrente, uma linha |
| enumeração de tenant | descoberta de clientes | ref aleatório + resposta uniforme + projeção mínima | rate limit W14 | tempos/códigos/conteúdo equivalentes |
| `app_users` ausente | fallback inseguro ou erro interno | estado seguro, zero acesso, reparo administrativo | tooling de reconciliação W15 | Auth órfã não cria contexto |
| duplicate membership | dois tenants para usuário comum | unique parcial + command transacional | alteração formal se produto mudar | User AB tenta segunda membership e recebe rejeição |
| race no bootstrap | dois tenants iniciais | advisory xact lock + precondição zero | platform provisioning W13 | chamadas paralelas, um sucesso |
| race no aceite | duas ativações/eventos | lock/update condicional + unique + Audit atômico | idempotency W3 | duas requests simultâneas |
| sessão válida após revoke | chamada REST direta ainda funciona| RLS usa fatos atuais, não JWT role/tenant | revogação Auth complementar | cliente REST antigo negado |
| frontend manipulado | bypass de UI | RLS/grants/commands são enforcement | W2 capabilities apenas UX | chamar endpoint direto sem UI |
| REST direto Supabase | contorno do app | policies por operação e menor privilégio | testes por domínio W2+ | SELECT/INSERT/UPDATE/DELETE negativos |
| helper RLS recursivo/permissivo | indisponibilidade ou leak | helpers mínimos security definer revisados | evaluator W2 | testes de recursão, grants e A/B |
| secret/token em log | comprometimento Auth | logger seguro; não logar session/error bruto | observability W14 | captura de logs sem token/e-mail |

## 30. Critérios de aceite `IDENTITY_TENANT_READY`

`IDENTITY_TENANT_READY` é apenas agregador local do planejamento e exige
simultaneamente `AUTH_READY = YES` e `TENANT_READY = YES`.

Critérios bloqueantes:

1. Auth local funcional para login, refresh, logout e fluxo invite/recovery
   incluído;
2. signup público desabilitado e sem backdoor de bootstrap;
3. `auth.users` e `app_users` 1:1, missing profile em fail closed;
4. lifecycles de Application User, membership e tenant separados;
5. uma única membership operacional por usuário comum;
6. bootstrap first-user/tenant serializado, one-time, sem password/secret em
   migration e com resultado atômico;
7. `tenantRef`/`DEC-01` fechado e comprovadamente não autoritativo;
8. resolver deriva contexto de `auth.uid()` + fatos atuais;
9. RLS deny-by-default e grants mínimos em todas as tabelas W1;
10. policies SELECT/INSERT/UPDATE/DELETE documentadas e testadas;
11. Tenant A/B real no Supabase local sem cross-tenant por UI, SDK, REST ou RPC;
12. segunda membership operacional rejeitada;
13. app user/membership bloqueado e tenant suspenso perdem acesso com JWT válido;
14. cache inclui principal/contexto + tenant e é removido em logout, expiração,
    troca de principal e invalidação detectada;
15. múltiplas abas não reexibem dado tenant depois de logout detectado;
16. convite expira, revoga, não reutiliza e não aceita identidade errada;
17. Audit mínimo registra mutations críticas atomicamente, conforme 10E;
18. bootstrap cria exatamente `maintenance = enabled` e só então torna o
    primeiro tenant `active`, preservando default deny fora desse fluxo;
19. nenhum role/permission/scope/Global Admin de W2/W13 foi antecipado;
20. nenhum secret, service role client-side, PII excessiva ou URL remota entrou;
21. migrations reconstroem DB do zero e `database.types.ts` é regenerado;
22. unit, Auth integration, DB/RLS, E2E, typecheck, lint, build e security review
    passam;
23. falhas V1 não são mascaradas e SQL legado permanece intacto;
24. documentação, diff e Git final estão consistentes.

Qualquer `FAIL` mantém os gates em `NO`. Itens de W2/W3/W13 corretamente
deferidos não bloqueiam, exceto Audit mínimo explicitamente exigido pela W1.

## 31. Subdivisão recomendada da implementação

### W1A — Modelo seguro e RLS basal

| Campo | Plano |
| --- | --- |
| Objetivo | implementar o schema e as decisões já fechadas, com tabelas core, constraints, RLS/grants e Audit mínimo |
| Escopo | `app_users`, `tenants`, memberships, invitations, entitlements, lifecycles, constraints, índices, grants, RLS basal e Audit mínimo |
| Arquivos esperados | migrations W1, testes DB/RLS, tipos gerados, documentação de schema |
| Migrations | `w1_identity_core`, `w1_tenant_membership_core`, início do Audit mínimo |
| Testes | reset from-zero, constraints, CRUD negado/permitido, Tenant A/B, grants/helpers |
| Riscos | recursão RLS, membership dupla, lifecycle incoerente, Audit divergente |
| Gate | `W1_DATA_BASE_READY` |
| Dependência | W0/FOUNDATION_READY + planejamento W1 versionado |
| Docker/Supabase local | obrigatório |
| Modelo Codex recomendado | `gpt-6-astra`, esforço `xhigh` |

### W1B — Auth, bootstrap e convite controlado

| Campo | Plano |
| --- | --- |
| Objetivo | habilitar Auth local sem signup, provar trigger, login/recovery/invite e provisioning one-time |
| Escopo | AuthGateway, criação 1:1 de Application User, runner de bootstrap, lifecycle completo de convite e aceite transacional |
| Arquivos esperados | config local Auth, AuthGateway, provisioning commands, testes Auth/integration |
| Migrations | procedures/trigger/Audit necessários; nenhuma fixture em migration |
| Testes | Auth→app user, bootstrap concorrente, invite lifecycle, missing profile, secret/log review |
| Riscos | provider local incompatível, service-role leakage, bootstrap backdoor, invite race |
| Gate | `W1_AUTH_CORE_READY` |
| Dependência | W1A |
| Docker/Supabase local | obrigatório |
| Modelo Codex recomendado | `gpt-6-astra`, esforço `xhigh` |

### W1C — Session context e cache isolation

| Campo | Plano |
| --- | --- |
| Objetivo | resolver contexto autoritativo, state machine, Auth events e cleanup QueryClient/router |
| Escopo | resolver tenant, provider de sessão, eventos Auth, query keys e limpeza de estado/cache; sem CompanySwitcher comum |
| Arquivos esperados | session provider/state, context query boundary, cache coordinator e testes |
| Migrations | resolver/helper/policies finais se não fechados em W1A |
| Testes | estados, refresh, logout, revoke com JWT válido, query keys, troca de principal/abas |
| Riscos | cache stale, loop de revalidação, UI usar route como authority |
| Gate | `W1_CONTEXT_READY` |
| Dependência | W1A + W1B |
| Docker/Supabase local | obrigatório para integração; unitários não |
| Modelo Codex recomendado | `gpt-6-astra`, esforço `high` |

### W1D — Rotas e UX mínima

| Campo | Plano |
| --- | --- |
| Objetivo | login/recovery/callback, proteção de rotas, Minha Conta mínima e estados seguros/mobile |
| Escopo | rotas W1, estados loading/erro/sem acesso/sessão expirada, deep links próprios, acessibilidade e mobile básico |
| Arquivos esperados | pages, route loaders/boundaries, hooks públicos e E2E W1 |
| Migrations | nenhuma esperada; qualquer necessidade volta a W1A–W1C |
| Testes | E2E login/deep-link/refresh/logout/back/tenant errado/session expired/mobile |
| Riscos | enumeration, flash de dado antigo, accessibility, signup exposto |
| Gate | `W1_UX_READY` |
| Dependência | W1C |
| Docker/Supabase local | obrigatório para E2E Auth real |
| Modelo Codex recomendado | `gpt-5.6-sol`, esforço `high` |

### W1E — Hardening e gates oficiais

| Campo | Plano |
| --- | --- |
| Objetivo | adversarial/security review, reconstrução from-zero, tipos/docs e decisão final |
| Escopo | regressão Auth/RLS/cache, concorrência, segurança, documentação e evidências finais; nenhuma feature nova |
| Arquivos esperados | testes negativos finais e documentação; sem feature nova |
| Migrations | nenhuma nova salvo correção versionada de finding real |
| Testes | todos os gates, A/B interleaved, grants, cache, invite/bootstrap races e build |
| Riscos | finding de segurança tardio, evidência incompleta, dívida empurrada à W2 |
| Gate | `AUTH_READY`, `TENANT_READY` e agregador `IDENTITY_TENANT_READY` |
| Dependência | W1A–W1D |
| Docker/Supabase local | obrigatório |
| Modelo Codex recomendado | `gpt-6-astra`, esforço `xhigh` |

Todos os blocos ficam na mesma branch W1, com commits pequenos por capacidade.
O bloco seguinte só começa após o gate interno anterior.

## 32. Estratégia de branch

1. Após versionar este plano, criar
   `feat/v2-w1-identity-tenant` exatamente a partir de
   `3c446de51e92f010cd26182487dcefa8c45b51b6` ou do commit equivalente já
   integrado em `develop/v2`.
2. Não continuar W1 indefinidamente em `feat/v2-w0-foundation`.
3. Manter W1A–W1E na mesma branch para que migrations, generated types e testes
   evoluam em uma única cadeia; usar commits coerentes, não branches paralelas
   por subbloco, salvo necessidade real de múltiplos desenvolvedores.
4. Abrir revisão contra `develop/v2` somente após `AUTH_READY` e `TENANT_READY`.
5. Não fazer merge automático em `main`; `v1-legacy` permanece intocada.
6. Nenhuma branch é criada nesta tarefa de planejamento.

## 33. Decisões formalmente fechadas

| Decisão | Estado final | Aplicação na W1 |
| --- | --- | --- |
| Cardinalidade User × Tenant | `CLOSED` pela arquitetura e confirmada neste planejamento | histórico N:N; usuário comum com no máximo uma membership operacional; exatamente um tenant no contexto |
| Schema físico `DD-02` / `DEC-03` | `CLOSED` para W1 | `app_users`, `tenants`, `tenant_memberships`, `tenant_invitations`, `tenant_entitlements` |
| Relação Auth/Application User | `CLOSED` | `app_users.id = auth.users.id` no target W1 |
| `tenantRef` / `DEC-01` | `CLOSED` | UUID v4 público, aleatório, único, separado de `tenants.id` e não autoritativo |
| `BD-01` | `CLOSED` pelo Product Owner | bootstrap grava `maintenance = enabled`; primeiro tenant fica `active` somente no commit transacional consistente |
| Autoridade de entitlement/status comercial | `CLOSED` | Plataforma/Global Admin futuro; nunca administrador comum do tenant |
| Audit mínimo | `CLOSED` | append-only e transacional apenas para mutations críticas W1; W3 consolida o framework completo |
| Bootstrap | `CLOSED` | runner operacional one-time fora do browser, advisory lock, fail closed e sem endpoint público |
| Convites | `CLOSED` | infraestrutura/lifecycle/aceite na W1 por operação server-side controlada; autorização tenant completa na W2 |
| Contexto tenant | `CLOSED` | sem CompanySwitcher comum; URL seleciona, provider mantém projeção e DB/RLS autoriza |
| Gate agregado | `CLOSED` | `IDENTITY_TENANT_READY` não substitui `AUTH_READY` e `TENANT_READY` |

### 33.1 Validação ainda dependente da implementação

O comportamento do Supabase local para invite, callback, refresh, recovery e
sincronização entre abas continua `IMPLEMENTATION-DEPENDENT` e deve ser provado
no início da W1B. Isso não é decisão de produto nem reabre o planejamento. Se o
ambiente local não reproduzir o comportamento necessário, aplicar `IB-02` em vez
de usar mocks como evidência de segurança.

Não há decisão crítica de produto pendente para iniciar W1A. Findings técnicos
durante a implementação devem seguir os gates e owners já definidos, sem reabrir
decisões `CLOSED` silenciosamente.

## 34. Riscos e checklist de implementação

### 34.1 Riscos prioritários

1. **Crítico — cardinalidade divergente:** implementar seleção multiempresa
   comum violaria regra funcional e arquitetura.
2. **Crítico — bootstrap/backdoor:** endpoint reutilizável ou grant amplo cria
   autoridade permanente fora do modelo.
3. **Crítico — RLS circular/permissiva:** helper que consulta policy dependente
   de si mesma pode falhar aberto, vazar ou indisponibilizar.
4. **Alto — invitation race/takeover:** aceite sem identidade verificada ou
   update condicional cria membership indevida.
5. **Alto — stale cache/session:** UI pode reexibir dados após revoke/logout,
   embora DB já negue novas queries.
6. **Alto — Audit divergente:** postergar o mínimo viola exit criterion; criar
   modelo completo antecipa W3.
7. **Alto — autoridade de entitlement:** permitir que administrador tenant altere
   `maintenance` ou status comercial violaria a autoridade exclusiva futura da
   Plataforma/Global Admin.
8. **Médio — trigger Auth:** erro no trigger pode bloquear provisionamento;
   exige testes e recovery documentado.
9. **Médio — PII duplicada:** copiar e-mail/metadata Auth cria drift e exposição.
10. **Médio — provider local:** mocks não substituem prova de Auth/RLS real.

### 34.2 Checklist antes de iniciar W1A

- [x] W0 concluída e `FOUNDATION_READY = YES`;
- [x] decisões `CLOSED` da arquitetura preservadas;
- [x] cardinalidade histórica N:N e operacional 1:1 definida;
- [x] DD-02/DEC-03 fechados com o schema físico W1;
- [x] DEC-01 fechado com `tenant_ref` UUID v4 público separado;
- [x] BD-01 fechado: primeiro tenant `active` com `maintenance = enabled`;
- [x] bootstrap one-time por runner operacional definido;
- [x] Audit mínimo append-only e transacional definido;
- [x] fronteiras W1/W2/W3 e Global Admin futuro definidas;
- [x] nenhuma decisão crítica de produto pendente;
- [x] nenhuma implementação W1 iniciada prematuramente;
- [x] migration plan e matriz RLS conceituais revisados;
- [x] nenhum arquivo V1 ou SQL legado incluído no escopo;
- [ ] criar a branch W1 do commit FOUNDATION_READY no início da implementação;
- [ ] confirmar Docker/Supabase local operacional antes da primeira migration.

### 34.3 Checklist por implementação

- [ ] migration cria cada tabela já deny-by-default;
- [ ] `auth.uid()` é a única origem do ator autenticado;
- [ ] nenhuma policy aceita tenant/user do payload como autoridade;
- [ ] nenhuma função possui `PUBLIC EXECUTE` indevido;
- [ ] trigger/Auth failure e recovery são testados;
- [ ] unique parcial impede segunda membership operacional;
- [ ] invite/accept/bootstrap concorrentes são testados;
- [ ] Tenant A/B é provado via JWT/REST/RPC reais locais;
- [ ] cache é limpo, não apenas invalidado, nas transições críticas;
- [ ] resposta não diferencia tenant inexistente de não autorizado;
- [ ] logs/Audit não contêm token, senha, e-mail completo ou metadata bruta;
- [ ] `database.types.ts` é regenerado, nunca editado manualmente;
- [ ] unit/integration/DB/E2E/typecheck/lint/build/diff/security passam;
- [ ] documentação e gates oficiais são atualizados;
- [ ] nenhuma permissão granular, Global Admin ou domínio futuro foi antecipado;
- [ ] Git termina limpo após commits coerentes e sem push automático.

## Estado deste planejamento

```text
W0_COMPLETE = YES
FOUNDATION_READY = YES
W1_PLANNING_COMPLETE = YES
W1_IMPLEMENTATION_STARTED = NO
AUTH_READY = NO
TENANT_READY = NO
IDENTITY_TENANT_READY = NO
```

Motivo dos gates de implementação em `NO`: as decisões de planejamento estão
fechadas, mas nenhuma migration, Auth flow, RLS ou teste W1 foi implementado.
