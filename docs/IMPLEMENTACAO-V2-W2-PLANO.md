# Plano de implementação V2 — W2 Authorization

## Estado do planejamento

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = NO
W2B_PROFILES_OVERRIDES_READY = NO
W2C_AUTHORIZATION_ENGINE_READY = NO
W2D_AUTHORIZATION_PROJECTION_READY = NO
W2E_AUTHORIZATION_HARDENING_READY = NO
AUTHORIZATION_READY = NO
```

Este documento formaliza o planejamento da W2 com a taxonomia oficial de quatro
scopes: `OWN`, `ASSIGNED`, `TEAM` e `ALL_TENANT`. O bloqueio W2-BLK-01 foi
resolvido: `ASSIGNED` é scope oficial, distinto de `OWN`; não há change control
para removê-lo. Os gates de implementação permanecem `NO`: nenhuma migration,
função, policy, tela ou permission foi criada nesta etapa.

Base real revisada: branch `feat/v2-w1-identity-tenant`, commit `eecdb93`, com
W1A–W1E, `AUTH_READY`, `TENANT_READY` e `IDENTITY_TENANT_READY` em `YES`. O
único artefato inicial não rastreado era este plano W2.

## 1. Objetivo

A W1 estabeleceu identidade, único tenant operacional do usuário comum,
membership, lifecycle e entitlement autoritativos. A W2 adicionará a decisão:

```text
Usuário + Tenant + Recurso + Ação + Escopo + fatos atuais do registro
```

O objetivo é oferecer uma única semântica de autorização consumível por RLS,
commands e projeções de UI, sem transformar Perfil, rota, cache, JWT ou payload
do browser em autoridade.

Fontes normativas consideradas:

- `AGENTS.md` e `docs/DEVELOPMENT-WORKFLOW.md`;
- `PRODUCT_SPEC.md`, especialmente Usuários, Perfis e Permissões e os requisitos
  transversais;
- `docs/ARQUITETURA-TECNICA-V2.md`, incluindo `AUTH-01`, `AUTH-02`, `RLS-01` e
  `PLAT-01`;
- `docs/GAP-ANALYSIS-V1-V2.md` e
  `docs/MIGRACAO-V1-V2-10E-PLANO-IMPLEMENTACAO.md`;
- `docs/IMPLEMENTACAO-V2-W1-PLANO.md` e
  `docs/IMPLEMENTACAO-V2-W1.md`;
- o modelo W1 implementado em `app_users`, `tenants`, `tenant_memberships`,
  `tenant_invitations`, `tenant_entitlements`, `audit_events`, migrations,
  helpers, testes e resolver de contexto.

## 2. Escopo e fora de escopo

### 2.1 Dentro da W2

- catálogo estrutural de permissions da plataforma;
- perfis tenant e quatro templates padrão;
- um perfil baseline por membership operacional;
- grants baseline de perfil;
- overrides individuais exatos;
- resolução de permissions efetivas e avaliação de scopes;
- helpers estruturais de banco, RLS e commands administrativos mínimos;
- antiescalada na delegação de permission;
- projeção versionada de capabilities para UI;
- invalidação de cache de autorização;
- auditoria mínima das mudanças de autorização;
- concorrência, constraints, grants e testes de segurança correspondentes.

### 2.2 Fora da W2

- Global CW Admin completo, console de plataforma ou impersonação;
- módulos funcionais de Manutenção, Ativos, Fornecedores e Cadastros;
- regras de domínio desses módulos além do contrato de integração;
- W3 History/Outbox e framework completo de auditoria;
- notificações, billing, SSO e relatórios avançados;
- ABAC genérico, rule builder, scripts customizados ou políticas em JSON;
- resources, actions ou scopes arbitrários criados por tenant;
- modelagem definitiva de Setores e Equipes;
- qualquer funcionalidade classificada como futura.

## 3. Princípios e decisões oficiais

| Decisão | Regra | Justificativa |
| --- | --- | --- |
| `W2-DEC-01` | Permission é a combinação exata `Resource + Action + Scope`. | Preserva `AUTH-01` sem hierarquia ou subtração implícita. |
| `W2-DEC-02` | O catálogo materializa somente combinações válidas e pertence à plataforma. | Impede vocabulário arbitrário e combinações cartesianas inválidas. |
| `W2-DEC-03` | Cada membership operacional possui exatamente um perfil baseline ativo. | O produto prevê “Perfil” singular e não exige composição de múltiplos perfis. |
| `W2-DEC-04` | Baseline armazena apenas `ALLOW`; ausência significa deny. | Evita DENY redundante e mantém o baseline simples. |
| `W2-DEC-05` | Override armazena `ALLOW` ou `DENY`; ausência significa herdar. | Representa toda a semântica exata sem persistir `INHERIT`. |
| `W2-DEC-06` | Overrides pertencem à membership, não diretamente ao `app_user`. | Evita que autorização antiga reapareça após revogação e nova membership. |
| `W2-DEC-07` | Banco e commands são autoridade; UI é projeção de capacidade. | Browser manipulado ou cache stale não pode ampliar acesso. |
| `W2-DEC-08` | O evaluator consulta fatos atuais do banco, nunca permission list do JWT. | Alterações produzem efeito sem esperar renovação do token. |
| `W2-DEC-09` | `OWN`, `ASSIGNED`, `TEAM` e `ALL_TENANT` são os scopes oficiais da autorização tenant. | `PRODUCT_SPEC.md`, arquitetura, GAP e roadmap distinguem Próprios, Atribuídos, Equipe e Todos do tenant. |
| `W2-DEC-10` | `ASSIGNED` e `TEAM` só recebem grants de domínio quando o resource possuir resolver autoritativo. | Evita inventar facts, Equipe/Setor ou alcance de assignment antes das waves donas dos recursos. |
| `W2-DEC-11` | Perfis padrão são cópias tenant-owned editáveis, nunca autoridade por nome. | Permite customização sem alterar templates ou semântica por label. |
| `W2-DEC-12` | Mudanças administrativas ocorrem por commands dedicados e versionados. | Centraliza antiescalada, concorrência, auditoria e invariantes. |
| `W2-DEC-13` | Entitlement exigido é metadado da combinação de permission, não inferência livre pelo nome do módulo. | Permite capabilities `core` sem entitlement e exige `maintenance` onde a combinação pertencer ao módulo contratado. |
| `W2-DEC-14` | Cache usa vetor persistido `membership.version + profile.version + catalog_revision` e geração local. | Separa concorrência, revisão compartilhada e catálogo sem fanout sobre todas as memberships. |

### 3.1 Taxonomia oficial de scope

Não é válido tratar `ASSIGNED` como sinônimo de `OWN`: `OWN` expressa relação
funcional de ownership definida pelo resource, e `ASSIGNED` expressa atribuição
operacional individual atual. A taxonomia completa é `OWN`, `ASSIGNED`, `TEAM`
e `ALL_TENANT`; cada combinação de catálogo permanece exata, sem hierarquia ou
subtração entre scopes.

## 4. Modelo conceitual

```text
app_user
  └─ 0..N memberships históricas; no máximo 1 operacional pela W1
       ├─ tenant 1
       ├─ profile baseline 1 quando active/blocked
       └─ 0..N permission overrides exatos

tenant
  └─ 1..N profiles
       └─ 0..N baseline permission grants

permission_catalog (plataforma)
  ├─ referenciado por baseline grants
  └─ referenciado por overrides

profile template (plataforma)
  └─ copiado no provisionamento; não participa da decisão runtime
```

Cardinalidades oficiais:

- `app_users 1:N tenant_memberships` no histórico, preservando a unicidade
  operacional da W1;
- `tenants 1:N tenant_profiles`;
- `tenant_profiles 1:N tenant_memberships` para memberships operacionais;
- `tenant_profiles N:N permission_catalog` por `tenant_profile_permissions`;
- `tenant_memberships N:N permission_catalog` por overrides;
- uma combinação do catálogo pode ser usada por muitos tenants, mas nunca é
  criada ou alterada por eles.

O vínculo do perfil ficará em `tenant_memberships.profile_id`. Uma tabela de
atribuições separada só seria necessária para múltiplos perfis simultâneos ou
histórico temporal próprio, requisitos inexistentes. A FK na membership deixa o
baseline singular, acompanha seu lifecycle e permite preservar o perfil final
na linha revogada. O Audit registra cada troca.

## 5. Modelo físico proposto

Os nomes, ownership e invariantes abaixo são decisões de implementação. A W2A
deve apenas traduzir este contrato para SQL e revisar a sintaxe/índices no diff;
não pode reabrir cardinalidade, authority ou semântica por conveniência.

### 5.1 `public.permission_catalog`

Alternativas avaliadas:

| Opção | Avaliação |
| --- | --- |
| A. uma linha por `Resource + Action + Scope` válido | Escolhida: ID estável diretamente referenciável, seed determinístico e combinação inválida inexistente por construção. |
| B. resources/actions/scopes normalizados e combinados | Rejeitada: normaliza vocabulário, mas ainda exige tabela de combinações válidas e multiplica joins/IDs sem benefício na W2. |
| C. strings/JSON em profiles | Rejeitada: integridade, FK, deprecation, auditoria e antiescalada ficam frágeis. |

Catálogo global, imutável para tenants:

| Campo | Regra proposta |
| --- | --- |
| `id uuid` | ID determinístico declarado por migration; estável entre ambientes |
| `code text` | código humano único e imutável |
| `module_code text` | namespace estrutural, como `core`, `shared`, `maintenance` |
| `resource_code text` | recurso estável, sem label traduzido |
| `action_code text` | ação estável |
| `scope authorization_scope` | um dos scopes oficiais `OWN`, `ASSIGNED`, `TEAM` ou `ALL_TENANT` |
| `required_entitlement_key text null` | `null` para capabilities core; chave exata, como `maintenance`, quando exigida |
| `tenant_delegable boolean` | controla se administrador tenant pode delegar a combinação |
| `label_key text`, `description_key text null` | metadados de apresentação; nunca entram no evaluator |
| `status text` | `active` ou `deprecated`; nunca hard delete |
| `created_at`, `updated_at`, `deprecated_at` | rastreabilidade estrutural |

Constraints mínimas: unicidade de `code`, unicidade da tupla
`(module_code, resource_code, action_code, scope)`, formato lowercase/snake_case
e coerência de status. A aplicação não aceita combinação que não possua linha
ativa no catálogo.

`private.authorization_catalog_state` terá uma única linha com
`catalog_revision bigint > 0`. Apenas migration/plataforma pode incrementá-la,
na mesma transação que altera a semântica efetiva do catálogo. Adicionar uma
permission sem grants não a concede a ninguém, mas ainda altera a revisão
estrutural; deprecar uma permission revoga seu efeito imediatamente. A revisão é
projetada para invalidação cliente, nunca aceita do cliente como autoridade.

### 5.2 Templates da plataforma

`private.authorization_profile_templates` conterá os quatro templates versionados
`manager`, `technician`, `assistant` e `requester`, com nomes iniciais Gestor,
Técnico, Auxiliar e Solicitante. A relação
`private.authorization_profile_template_permissions` conterá apenas os grants que
devem ser copiados para um novo tenant.

Templates pertencem à plataforma, não recebem grants de browser e não entram no
evaluator runtime. Servem exclusivamente ao provisionamento determinístico.

### 5.3 `public.tenant_profiles`

| Campo | Regra proposta |
| --- | --- |
| `id uuid` | PK interna |
| `tenant_id uuid` | tenant proprietário, `ON DELETE RESTRICT` |
| `name text` | label editável; não é autoridade |
| `template_key text null` | origem padrão imutável; `null` para customizado |
| `template_version bigint null` | versão copiada no provisionamento |
| `status text` | `active` ou `inactive` |
| `version bigint` | concorrência e revisão agregada do baseline |
| `created_at`, `updated_at` | timestamps do banco |
| `created_by`, `updated_by` | atores autoritativos |

Haverá unicidade `(tenant_id, id)`, uma única cópia de cada `template_key` por
tenant e nome normalizado único entre perfis ativos. Perfis não serão apagados.
Um perfil não poderá ser inativado enquanto estiver associado a membership
operacional.

### 5.4 `public.tenant_profile_permissions`

Relação de baseline com `tenant_id`, `profile_id`, `permission_id`, `created_at`
e `created_by`. A PK será `(profile_id, permission_id)`; a FK composta
`(tenant_id, profile_id) -> tenant_profiles(tenant_id, id)` impede perfil
cross-tenant, e a FK global para `permission_catalog(id)` impede combinação
inexistente. Presença da linha significa `ALLOW`; não existe coluna de efeito
nem DENY baseline.

Adicionar ou remover uma linha ocorrerá somente por command e incrementará
`tenant_profiles.version` na mesma transação.

### 5.5 Alteração planejada em `tenant_memberships`

- adicionar `profile_id`, `profile_assigned_at` e `profile_assigned_by`;
- usar FK composta `(tenant_id, profile_id)` para impedir perfil de outro tenant;
- exigir `profile_id` para membership `active` ou `blocked` após o backfill;
- manter `profile_id` na revogação; linhas históricas pré-W2 sem inferência segura
  podem permanecer `null` e nunca são autorizadas;
- reutilizar `tenant_memberships.version`: troca de perfil ou override também a
  incrementa e invalida a projeção W1/W2.

### 5.6 `public.tenant_permission_overrides`

| Campo | Regra proposta |
| --- | --- |
| `id uuid` | PK interna |
| `tenant_id uuid` | tenant proprietário |
| `membership_id uuid` | target da autorização individual |
| `permission_id uuid` | combinação exata do catálogo |
| `effect text` | somente `allow` ou `deny` |
| `version bigint` | proteção da edição da própria linha |
| `created_at`, `updated_at` | timestamps do banco |
| `created_by`, `updated_by` | atores autoritativos |

Unicidade `(membership_id, permission_id)` e FKs compostas evitam duplicidade e
cross-tenant. Remover a linha significa voltar a herdar; não haverá `INHERIT`
persistido.

### 5.7 Convites e Audit existentes

`tenant_invitations` receberá `target_profile_id` para que novos convites
definam o baseline antes do aceite. A FK composta com `tenant_id` impede perfil
de outro tenant. Convites W1 pendentes sem profile ficam fail-closed até
atribuição explícita ou revogação/reemissão; nenhum perfil será inferido pelo
e-mail ou nome.

`audit_events` continuará sendo o sink append-only mínimo. W2 não cria um
segundo framework de auditoria.

## 6. Permission semantics

Para usuário `u`, resource `r`, action `a` e scope `s`:

```text
BASE(u,r,a,s) = ALLOW se existe grant ativo no perfil ativo; senão ausência
OVERRIDE(u,r,a,s) = ALLOW, DENY ou ausência

EFFECTIVE(u,r,a,s) =
  DENY,  se principal/contexto/entitlement/perfil não estiver operacional
  ALLOW, se override exato = ALLOW
  DENY,  se override exato = DENY
  ALLOW, se override ausente e baseline exato existe
  DENY,  nos demais casos

EFFECTIVE_SCOPES(u,r,a) = { s | EFFECTIVE(u,r,a,s) = ALLOW }
```

O catálogo ausente ou deprecated também resulta em deny. Perfil ausente ou
inativo resulta em conjunto vazio; overrides não reativam perfil inativo. Para
cada combinação candidata, `required_entitlement_key = null` dispensa
entitlement de módulo; valor não nulo exige linha atual
`tenant_entitlements(tenant_id,module_key)` com `enabled = true`. `module_code`
organiza namespace, mas não é usado como inferência automática de entitlement.

Exemplos obrigatórios AUTH-01:

1. baseline `WORK_ORDER:UPDATE:ALL_TENANT=ALLOW` e override
   `WORK_ORDER:UPDATE:ASSIGNED=DENY` produzem `ASSIGNED=DENY` e
   `ALL_TENANT=ALLOW`; a operação continua autorizada se `ALL_TENANT` alcançar
   o registro.
2. baseline `WORK_ORDER:UPDATE:ASSIGNED=ALLOW` e override
   `WORK_ORDER:UPDATE:OWN=DENY` mantêm `ASSIGNED=ALLOW`.
3. baseline `WORK_ORDER:READ:TEAM=ALLOW` e
   `WORK_ORDER:READ:ASSIGNED=ALLOW`, com override
   `WORK_ORDER:READ:TEAM=DENY`, produzem `TEAM=DENY` e `ASSIGNED=ALLOW`.

O conjunto final é a união dos scopes com `ALLOW`; a autorização existe quando
ao menos um scope permitido alcança o target autoritativo.

Não existe precedência entre scopes, wildcard, herança por nome de recurso,
negação global ou permission JSON.

## 7. Resource catalog inicial

Convenção oficial:

```text
<module>.<resource>.<action>.<scope>
```

Exemplos: `core.profiles.read.all_tenant` e
`maintenance.work_orders.update.own`. Códigos são lowercase, estáveis e não
traduzidos; labels ficam na camada de apresentação.

| Resource | Tratamento inicial |
| --- | --- |
| `core.tenant_settings` | namespace reservado; combinações entram com a wave de Empresa/configuração. Entitlements comerciais continuam fora. |
| `core.users` | W2 cobre leitura administrativa, convite, atribuição de perfil, overrides e lifecycle autorizado. |
| `core.profiles` | W2 cobre leitura, criação, edição, ativação/inativação e mudança de baseline. |
| `shared.assets` | resource reservado; combinações e OWN serão definidos na W de Ativos. |
| `shared.suppliers` | resource reservado; contatos externos não viram usuários. |
| `shared.registrations` | umbrella somente para cadastros equivalentes e de baixo risco; exceções ganharão resource próprio na W correspondente. |
| `shared.reports` | governará uso/configuração/exportação, mas nunca amplia linhas das fontes. |
| `maintenance.requests` | resource oficial; matriz e facts serão definidos na W de Solicitações. |
| `maintenance.work_orders` | resource oficial; ações de execução e validação serão definidas na W de OS. |
| `maintenance.preventive_plans` | resource oficial; programação e geração de OS serão definidas na W de Preventiva. |
| `maintenance.calendar` | não será autoridade de dados própria; acesso aos itens deriva dos resources de origem. Eventual capability de navegação não amplia RLS. |

Na W2, somente combinações necessárias à governança `core.users`,
`core.profiles` e à projeção/configuração mínima comprovada serão semeadas. Os
demais códigos acima são reserva de namespace documental: não geram linha
curinga, grant vazio ou capability navegacional antecipada. Cada wave funcional
materializa suas combinações exatas, entitlement e resolver junto dos testes.

Comentários e anexos não serão resources independentes na W2. Leitura herda o
alcance do registro pai; criar/remover será action do resource pai até surgir
necessidade funcional comprovada. Validação e atribuição também são actions do
resource pai. Isso evita uma matriz duplicada e não antecipa W3 ou mídia.

## 8. Action catalog inicial

### 8.1 Ações genéricas reutilizáveis

- `read`: consultar/listar dentro dos scopes alcançáveis;
- `create`: criar sob o tenant atual e as regras do domínio;
- `update`: alterar campos ordinários permitidos;
- `activate` / `inactivate`: lifecycle cadastral quando previsto;
- `delete`: somente para entidade cuja exclusão física seja explicitamente
  permitida; não será sinônimo de inativação;
- `export`: gerar saída dos mesmos dados já visíveis.

### 8.2 Ações específicas

- `invite`, `assign_profile`, `manage_overrides`, `change_permissions` e
  `change_status` para governança W2;
- `assign`, `cancel`, `validate_completion`, `complete` e `reopen` para domínios
  que realmente tenham essas transições;
- `approve` apenas quando aprovação for semanticamente diferente de validação.

Uma action específica será criada quando houver transição, invariantes, efeito
ou risco diferente de CRUD. `manage` não será usado como wildcard: só poderá
existir para uma superfície indivisível e documentada. Duplicar perfil usa
`core.profiles.create`, não cria action `duplicate`.

Como o catálogo materializa combinações, essa lista é vocabulário de projeto,
não uma tabela onde o tenant possa cadastrar verbos.

O catálogo administrativo inicial usa somente `ALL_TENANT`: governança de
usuários e perfis sempre está limitada ao tenant atual e não possui semântica
útil de `OWN`, `ASSIGNED` ou `TEAM`. As combinações mínimas são enumeradas na
seção 20.3; nenhum wildcard `<resource>.*` ou action `manage` as substitui.

## 9. Scope semantics

Scopes serão um tipo estrutural controlado pela plataforma e só aparecerão em
combinações materializadas no catálogo.

### 9.1 `OWN`

`OWN` significa que uma relação funcional de ownership, explicitamente
declarada na matriz do resource, liga o ator ao registro. Pode envolver
requester, creator, functional owner ou relação equivalente; não existe campo
universal e `created_by` não é pressuposto para todo resource.

Cada resource deverá publicar antes de sua implementação:

- relações que satisfazem `OWN` por action;
- tabelas e joins autoritativos usados;
- comportamento quando a relação muda;
- testes positivos, negativos e cross-tenant.

### 9.2 `ASSIGNED`

`ASSIGNED` significa atribuição operacional individual explícita e autoritativa
ao usuário, distinta de ownership/criação. Pode ser responsável individual,
executor individual ou outra relação canônica definida pelo resource; a W2 não
congela `responsible_user_id`, `executor_user_id` ou qualquer coluna universal.
Cada wave dona define relações autoritativas, efeito de reatribuição e testes
antes do primeiro grant. Facts são derivados do banco; o frontend não pode
declarar que um registro está atribuído ao usuário.

### 9.3 `TEAM`

`TEAM` significa que o registro está relacionado a Equipe, Setor ou grupo atual
do usuário segundo o resolver daquele resource. A W2 não inventa esse modelo:
onde não houver resolver autoritativo, nenhuma combinação `TEAM` funcionalmente
dependente dele será concedida (pode permanecer apenas catalogada). A wave que
modelar essas entidades cria os facts, resolver e testes antes do primeiro grant.

### 9.4 `ALL_TENANT`

Alcança somente registro cujo `tenant_id` corresponda ao tenant atual derivado
e autorizado pela W1. `tenant_id` informado pelo browser nunca é autoridade;
este scope não significa cross-tenant, Global Admin ou bypass de entitlement.

Scopes formam união de alcance. Eles não são roles, não têm ordem de precedência
e nenhum DENY de uma combinação reduz outra combinação permitida.

## 10. Roles/profiles

O provisionamento de cada tenant cria Gestor, Técnico, Auxiliar e Solicitante a
partir dos templates vigentes. O profile tenant é uma cópia independente:

- nome pode ser alterado sem efeito na autorização;
- baseline pode ser editado por command sujeito à antiescalada;
- `template_key` não muda e nunca é consultado pelo evaluator;
- perfil pode ser inativado somente sem memberships operacionais associadas;
- nenhum perfil é fisicamente excluído;
- perfil customizado segue as mesmas tabelas e regras.

A atribuição é singular por membership. Alterar perfil substitui todo o baseline,
mas preserva overrides individuais; o command mostra e audita o diff efetivo e
impede novo grant que o ator não possa delegar.

O sistema deverá preservar ao menos uma membership ativa com capacidade efetiva
de administrar perfis e usuários, evitando lockout administrativo do tenant.

## 11. Overrides e antiescalada

Override é sempre uma linha exata do catálogo:

- `ALLOW` adiciona ou substitui o baseline exato;
- `DENY` remove somente o baseline exato;
- remover a linha retorna à herança;
- override de catálogo deprecated ou perfil inativo não produz acesso.

Commands de governança exigem a permission administrativa apropriada e aplicam
antiescalada:

1. derivar ator, membership e tenant pela W1;
2. bloquear e reler os fatos relevantes;
3. calcular o diff de permissions efetivas do target;
4. para cada combinação que passará de deny para allow, exigir que o ator possua
   a mesma combinação exata e que ela seja `tenant_delegable`;
5. impedir combinação reservada à plataforma;
6. validar versão, invariantes e último administrador;
7. mutar e auditar na mesma transação.

Remover um override `DENY` pode restaurar um ALLOW baseline e portanto também é
tratado como concessão. Trocar perfil só é permitido se todo novo ALLOW do target
for delegável pelo ator. Nome “Gestor” nunca dispensa essas verificações.

## 12. Effective permission resolution

O núcleo de resolução recebe resource/action definidos pelo código servidor e
retorna os scopes efetivos atuais. Conceitualmente:

```text
resolveEffectiveScopes(actor, tenant, resource, action)
  validar W1: principal + membership + tenant + entitlement
  exigir profile ativo da membership
  obter ALLOWs baseline ativos
  aplicar override exato ALLOW/DENY
  retornar conjunto distinto de scopes permitidos
```

Resources e actions de commands de negócio serão constantes server-side. Um
cliente não transforma um command em outro enviando strings de permission.

O resolver não usa nome/template do perfil, metadata JWT, rota, cache ou lista
fornecida pelo browser.

No PostgreSQL, o contrato planejado é privado e estreito:
`private.resolve_effective_scopes(resource_code, action_code)` deriva
`auth.uid()`, membership, tenant e entitlement atuais. Policies e commands
passam literais definidos no servidor; a função não recebe actor, profile,
scopes desejados nem facts do browser.

## 13. Scope evaluation e authorization facts

A W2 separará duas responsabilidades:

1. `effective scopes`: cálculo genérico sobre catálogo/perfil/override;
2. `scope reaches`: predicado específico do resource sobre facts do registro.

Contrato conceitual mínimo:

```text
AuthorizationSubject
  actorUserId      <- auth.uid()
  tenantId         <- contexto W1 atual
  membershipId     <- contexto W1 atual

AuthorizationTarget
  resource         <- constante do policy/command
  action           <- constante do policy/command
  recordTenantId   <- linha relida no banco
  resourceFacts    <- relações autoritativas específicas do resource
```

Não haverá um JSON genérico aceito do frontend nem uma “god function” com todos
os possíveis campos. Cada domínio fornece um resolver pequeno e testável. Facts
vêm da própria linha ou de relações relidas no banco; o payload pode conter
somente um target a confrontar.

Cada wave de domínio registra a integração em uma matriz técnica versionada e
implementa predicados específicos, por exemplo
`private.work_order_scope_reaches(target_work_order_id, action_code,
candidate_scope)`. Isso não é dispatch dinâmico por texto fornecido pelo
cliente: policy/command escolhe o resolver e a action por constante. O resolver
de domínio relê o target e associações necessárias, valida tenant e não consulta
recursivamente a mesma policy que o chamou. Facts simples disponíveis na linha
podem ser comparados diretamente pela policy para reduzir privilégio.

## 14. RLS e autorização no banco

### 14.1 Opções avaliadas

| Opção | Vantagem | Limite |
| --- | --- | --- |
| A. Policies consultam todas as tabelas diretamente | explícita por policy | duplica algoritmo e aumenta risco de divergência/recursão |
| B. `private.has_permission(resource,action,scope)` | centraliza combinação exata | sozinho não decide se scope alcança o registro |
| C. evaluator completo recebe todos os facts | interface única | vira god function e fatos parametrizados podem ser spoofados |
| D. híbrido | centraliza permissions e mantém facts no domínio | requer matriz e helper pequeno por resource |

### 14.2 Arquitetura escolhida: híbrida

- helper privado central calcula scopes efetivos a partir dos fatos W1 e tabelas
  W2 atuais;
- helper booleano exato poderá atender policies simples;
- cada policy combina esses scopes com colunas/facts autoritativos do resource;
- relações auxiliares usam resolver privado específico que não consulta de modo
  recursivo a tabela protegida;
- `ALL_TENANT` sempre confronta o `tenant_id` da linha com o contexto W1;
- INSERT, SELECT, UPDATE e DELETE/inativação recebem análise separada.

Helpers privilegiados terão `SECURITY DEFINER` somente quando necessário,
`search_path` vazio, nomes qualificados, owner não cliente e grants mínimos.
`auth.uid()` continua a identidade. JWT não leva permissions mutáveis.

Tabelas de autorização não terão mutation grants diretos para browser. Catálogo,
profiles, baseline e overrides serão expostos por projections/commands específicos.
RLS permanece defesa adicional, não substitui invariantes de command.

## 15. Command authorization

Commands críticos seguem `AUTH-02`:

```text
begin
→ identificar tenant, target, permission e facts relevantes
→ adquirir locks em ordem canônica
→ reler W1 + profile + grants + overrides + registro
→ reavaliar entitlement + permission + scope
→ validar input + domínio + expected version + invariantes
→ mutar
→ registrar audit obrigatório
→ commit
```

Ordem canônica proposta: tenant → membership target → profile → override →
registro de domínio. Um command que altera apenas profile não bloqueia
memberships em massa; o incremento de `tenant_profiles.version` invalida todas
as projeções que o referenciam.

Responsabilidades:

- RLS limita linhas e operações diretas permitidas;
- evaluator resolve permission/scopes atuais;
- command estabiliza fatos, aplica domínio, concorrência e auditoria;
- application service valida contrato e traduz erros, sem decidir por Perfil;
- frontend oculta/desabilita ações apenas como UX e trata negação autoritativa.

### 15.1 Administração de usuários e convites pós-W2

Os commands W1 `create_tenant_invitation`, `revoke_tenant_invitation` e
`expire_tenant_invitation` continuam restritos a `service_role` e não serão
concedidos ao browser. Eles são primitives operacionais legadas, não autorização
funcional do administrador.

A W2 introduzirá boundaries autenticadas dedicadas para convidar, reenviar,
revogar e alterar lifecycle/profile de usuário. O fluxo seguro é:

```text
browser envia intenção sem actor/tenant autoritativos
→ boundary server-side valida a sessão do chamador
→ command DB executado no contexto JWT do chamador deriva auth.uid()
→ deriva membership/tenant W1 e exige permission exata
→ bloqueia e relê profile, convite e target relevantes
→ valida antiescalada, estado, version e target_profile_id
→ grava estado + Audit e retorna resultado mínimo
→ integração Auth server-side usa service_role somente para o efeito técnico
```

O segredo técnico nunca chega ao navegador. A chamada ao provider Auth não
substitui a decisão tenant e não aceita `operator_user_id` como autoridade. Se
o efeito Auth não puder participar da transação PostgreSQL, o command terá
estado/idempotência e compensação explícitos; não poderá retornar sucesso final
antes de o resultado necessário estar confirmado. O desenho detalhado do envio
fica na implementação do boundary, mas não autoriza bypass temporário,
`is_admin` ou concessão direta dos commands ops W1 a `authenticated`.

### 15.2 Fronteiras de plataforma e autoridade técnica

Global CW Admin permanece fora destas tabelas, profiles e scopes. Não existe
profile tenant “Global Admin”, `ALL_TENANT` cross-tenant, `bypass=true` ou
impersonação invisível. A futura autoridade de plataforma usará identidade,
capability e command próprios, target tenant explícito, motivo e Audit, conforme
`PLAT-01`.

`service_role` permanece autoridade técnica server-side de blast radius mínimo.
Ela pode executar o efeito allowlisted necessário do provider, mas nunca prova
que a pessoa solicitante podia administrar o tenant; essa prova já deve ter sido
feita pelo command autenticado e relida quando houver continuação/compensação.

## 16. Frontend projection e cache

Um endpoint/RPC somente leitura, por exemplo `resolve_my_authorization`, derivará
o contexto W1 e retornará somente:

- `profileId`, label segura e status;
- `membershipVersion`, `profileVersion` e `catalogRevision`;
- conjunto de códigos/scopes efetivamente permitidos;
- `authorizationRevision`, representação canônica do vetor acima.

Não retornará grants de outros usuários, regras internas de antiescalada,
segredos ou capabilities de plataforma.

Chave conceitual de cache:

```text
authorization
+ principalId
+ tenantId
+ membershipId
+ membershipVersion
+ profileId
+ profileVersion
+ catalogRevision
+ authorizationGeneration
```

Mudança de override ou atribuição de perfil incrementa `membershipVersion`;
mudança no baseline/status incrementa `profileVersion`; mudança estrutural do
catálogo incrementa `catalogRevision`. O backend aplica tudo imediatamente
porque consulta o banco atual, mesmo com JWT e projeção cliente antigos.

Ao observar revisão diferente, o provider cancela requests tenant-owned,
remove caches e dados sensíveis do contexto, incrementa
`authorizationGeneration` local e só então libera novas queries com a nova
chave. Não basta invalidar apenas o cache de capabilities: toda query cuja linha
ou projeção dependa de permission participa dessa fronteira.

A UI mantém capabilities somente em memória e revalida a projeção:

- após qualquer command de governança;
- em eventos Auth/contexto e ao voltar a foco/visibilidade;
- a cada 30 segundos enquanto a aplicação estiver visível e online, usando a
  mesma ordem segura de cancelamento/limpeza da W1C quando a revisão mudar;
- após resposta autoritativa de perda de permission.

`BroadcastChannel` propaga apenas pedido de revalidação/revisão, nunca a lista
de permissions, entre abas do mesmo dispositivo. A revalidação periódica cobre
alterações feitas em outro dispositivo ou sessão. Não haverá permissions em
`localStorage`/`sessionStorage`, nem dependência de refresh do JWT ou Realtime
para segurança.

## 17. Auditoria

Eventos mínimos:

- `authorization.profile.created`;
- `authorization.profile.updated`;
- `authorization.profile.activated` / `inactivated`;
- `authorization.profile_permission.changed`;
- `authorization.membership_profile.changed`;
- `authorization.user_override.changed` / `removed`.

Cada evento registra ator derivado, tenant, target, IDs estáveis, permission
exata, valor anterior/novo, versões, correlation ID e reason quando o command o
exigir. Mudança de perfil, override, status e baseline exige reason não vazio.
Payloads não incluem JWT, tokens, service role ou dados pessoais desnecessários.

Audit é gravado na mesma transação; falha aborta a mudança. Retenção e consulta
administrativa completa continuam fora da W2/W3 conforme planejamento próprio.

## 18. Concorrência e versionamento

Alternativas avaliadas:

| Alternativa | Avaliação |
| --- | --- |
| A. somente `tenant_memberships.version` | Reutiliza W1C, mas exigiria fanout em todas as memberships quando um profile compartilhado mudar. |
| B. `authz_version` único separado por membership/tenant | Simplifica uma chave, mas duplica estado e cria hot row ou fanout sem necessidade nesta escala. |
| C. vetor de versões existentes + catálogo | Escolhida: mantém ownership e concorrência no agregado que realmente mudou. |

Estratégia oficial C:

- `tenant_profiles.version` protege nome, status e baseline como agregado;
- command de edição recebe `expected_profile_version`, bloqueia o profile e falha com
  conflito se stale;
- mudança de `tenant_profile_permissions` toca o profile e incrementa sua versão;
- atribuição de perfil/override recebe `expected_membership_version`, bloqueia a
  membership e incrementa sua versão;
- override individual também possui versão para alteração pontual;
- `authorization_catalog_state.catalog_revision` cobre mudança estrutural;
- o evaluator sempre relê versões/estado após locks relevantes;
- duas edições concorrentes não aplicam last-write-wins silencioso;
- troca durante sessão vale imediatamente no banco e invalida projeções pela
  tupla de versões.

Não haverá fanout atualizando toda membership quando um perfil mudar. A versão
do profile representa a revisão compartilhada; a generation cliente muda após
revalidar o vetor. Se carga real futura provar que o vetor é insuficiente, um
`authz_version` agregado exige nova decisão técnica, não é antecipado na W2.

## 19. Soft delete e histórico

- profiles tornam-se `inactive`; não são fisicamente apagados;
- permission do catálogo torna-se `deprecated`; código e ID permanecem;
- grant baseline pode ser removido fisicamente porque é relação de estado; o
  Audit obrigatório preserva before/after;
- override pode ser removido fisicamente para expressar herança; o Audit
  preserva seu histórico;
- membership revogada mantém `profile_id` e seus overrides ficam inefetivos;
- constraints `ON DELETE RESTRICT` protegem referências históricas.

## 20. Seeds e provisionamento

### 20.1 Platform seed

Migrations determinísticas mantêm catálogo, IDs, templates e baseline padrão.
Tenant não escreve nessas estruturas. Seed é idempotente por ID/code e não
renomeia nem reativa objeto tenant.

### 20.2 Tenant provisioning

Command privado controlado copia os quatro templates e grants para o tenant:

- primeiro tenant existente: identifica a membership de bootstrap e atribui
  Gestor;
- novo tenant: cria os quatro perfis antes de ativar o tenant e associa o criador
  a Gestor na mesma transação;
- novo convite pós-W2: exige `target_profile_id` ativo e o aceite copia esse
  profile para a membership;
- membership operacional existente sem inferência segura recebe conjunto efetivo
  vazio até atribuição explícita; não se presume Gestor/Técnico por nome ou e-mail.

Nova permission adicionada em versão posterior não é concedida automaticamente
a perfis existentes. A plataforma decide explicitamente se ela entra no template
para novos tenants e, separadamente, se haverá command/migration auditável de
adoção para tenants existentes.

### 20.3 Baseline inicial mínimo

Somente Gestor recebe grants administrativos W2, sempre `ALL_TENANT`:

```text
core.users.read.all_tenant
core.users.invite.all_tenant
core.users.assign_profile.all_tenant
core.users.manage_overrides.all_tenant
core.users.change_status.all_tenant
core.profiles.read.all_tenant
core.profiles.create.all_tenant
core.profiles.update.all_tenant
core.profiles.activate.all_tenant
core.profiles.inactivate.all_tenant
core.profiles.change_permissions.all_tenant
```

Essas onze combinações são `tenant_delegable = true`, sempre sujeitas à
permission administrativa, à posse exata da combinação pelo concedente e à
regra de último administrador. Capabilities de plataforma/CW não são
representadas como profile tenant; se algum catálogo tenant precisar referenciar
uma operação não delegável no futuro, a combinação nasce explicitamente com
`tenant_delegable = false`.

Técnico, Auxiliar e Solicitante não recebem autoridade administrativa W2. A
consulta do próprio Perfil e permissions efetivas usa projeção self e não exige
`core.profiles.read.all_tenant`.

Baselines de Solicitações, OS, Ativos, Fornecedores, Cadastros, Preventiva,
Calendário e Relatórios serão definidos nas respectivas Ws, junto de seus facts
e regras de negócio. Não serão inventados neste plano. Adições futuras serão
explícitas e não retroativas por padrão.

## 21. Estratégia de migrations futura

Nenhuma migration é criada agora. Sequência planejada:

1. **W2-01 — authorization catalog:** enum dos quatro scopes oficiais,
   catálogo, `authorization_catalog_state`, templates e constraints;
2. **W2-02 — platform seed:** IDs/códigos determinísticos, entitlement metadata
   e templates administrativos mínimos;
3. **W2-03 — tenant profiles:** profiles, baseline grants, índices, RLS fechada
   e versões;
4. **W2-04 — membership authorization:** `profile_id`, overrides e
   `target_profile_id` em convites, inicialmente nullable para backfill seguro;
5. **W2-05 — provisioning/backfill:** quatro profiles, Gestor inicial e
   tratamento fail-closed de memberships/convites existentes;
6. **W2-06 — integrity finalization:** validar o backfill antes de `NOT NULL`,
   FKs compostas, uniqueness e checks finais;
7. **W2-07 — evaluator/projection:** effective scopes, entitlement, revisão de
   autorização e contratos para resolvers resource-specific;
8. **W2-08 — governance commands:** profile, baseline, assignment, override,
   lifecycle e convite autenticado com antiescalada, versões e Audit;
9. **W2-09 — RLS/grants/hardening:** policies por operação, grants finais,
   owners/search paths, projeção frontend e inspeções adversariais.

A separação evita circularidade: catálogo existe antes dos grants; profiles
antes da atribuição; backfill é verificado antes do `NOT NULL`; evaluator existe
antes das policies e commands finais. Nenhuma tabela pública fica permissiva
aguardando migration posterior: nasce com RLS e sem grants de cliente. Cada
migration é reproduzível, forward-only e acompanhada por teste do estado
intermediário/final aplicável.

## 22. Estratégia de testes

### 22.1 pgTAP / integração PostgreSQL

- profile do Tenant A não afeta Tenant B;
- baseline exato ALLOW e ausência deny;
- override DENY exato substitui baseline exato;
- override ALLOW exato adiciona combinação;
- baseline `ASSIGNED` ALLOW; override `ASSIGNED` DENY e ALLOW;
- `ASSIGNED` de User A não alcança User B e assignment cross-tenant é rejeitado;
- DENY `ASSIGNED` não remove `ALL_TENANT` ALLOW;
- DENY `OWN` não remove `ASSIGNED` ALLOW;
- DENY `TEAM` não remove `ASSIGNED` ALLOW;
- alteração de assignment invalida permission/cache; facts `ASSIGNED` enviados
  pelo cliente não influenciam o banco;
- usuário sem profile e profile inactive recebem conjunto vazio;
- permission/catalog deprecated não autoriza;
- entitlement exigido ausente/desabilitado nega; capability core sem
  entitlement continua avaliável;
- mudança de profile/grant/override/catalog vale com o mesmo JWT;
- membership revogada e tenant incorreto continuam negados pela W1;
- anon não acessa evaluator/projection;
- `service_role` não vira autoridade tenant comum nem chega ao browser;
- grants, owners, `SECURITY DEFINER` e `search_path` inspecionados;
- mutation direta e cross-tenant negadas;
- antiescalada impede conceder combinação ausente ou reservada;
- remover DENY que restauraria grant também passa por antiescalada;
- concorrência por `expected_version` rejeita editor stale;
- profile inativo atribuído e último administrador são protegidos;
- convite deriva ator/tenant de `auth.uid()`, exige profile do mesmo tenant e
  não expõe command ops/service role ao browser;
- cache/JWT enviados pelo cliente não influenciam o banco;
- audit é transacional, append-only e sem secrets.

### 22.2 Unit

- algoritmo puro de baseline + override exato;
- resolução do conjunto de scopes;
- sem subtração entre scopes;
- chaves/revisões do cache;
- projeção de capabilities e estados sem permission;
- invalidação por membership/profile/catalog revision;
- troca de `authorizationGeneration` limpa caches de dados, não só capabilities;
- matriz de antiescalada e diffs de concessão.

### 22.3 Integration/E2E futuro

- Gestor, Técnico, Auxiliar e Solicitante com projeções distintas;
- perfil customizado e override ALLOW/DENY;
- alteração refletida sem novo JWT;
- alteração em outra sessão e múltiplas abas convergem no limite definido;
- rota continua tenant-safe e UI não renderiza ação antes da projeção;
- chamada direta continua negada quando botão está oculto.

Mocks não comprovam RLS. Os gates W2 exigirão reset local, migrations, pgTAP,
schema lint, unit, E2E, typecheck, lint e build conforme aplicável.

## 23. Subdivisão da W2 e gates

### W2A — modelo e catálogo

- objetivo: criar o vocabulário estrutural e o catálogo de combinações válidas;
- escopo: enum dos quatro scopes oficiais, permission catalog opção A, entitlement metadata,
  revisão de catálogo, templates e seed administrativo mínimo;
- fora de escopo: profiles tenant, grants tenant, evaluator, domínio e UI;
- artefatos: W2-01/W2-02, matriz inicial, tipos gerados e testes DB;
- testes: IDs/seed determinísticos, combinação inválida/duplicada, deprecation,
  revisão, ausência de mutation grant e owners;
- gate: `W2A_AUTHORIZATION_MODEL_READY = YES` somente após DB real local.

### W2B — perfis, baseline e overrides

- objetivo: materializar profiles tenant, baseline e exceções individuais;
- escopo: W2-03 a W2-06, profile singular na membership, target do convite,
  overrides, provisioning/backfill e constraints finais;
- fora de escopo: resolver de domínio, UI administrativa e permissions de
  módulos ainda não modelados;
- artefatos: migrations, tipos, fixtures e comandos privados de provisioning;
- testes: Tenant A/B, lifecycle, profile único, backfill fail-closed,
  concorrência estrutural e integridade composta;
- gate: `W2B_PROFILES_OVERRIDES_READY = YES` somente após fluxo DB completo.

### W2C — evaluator e enforcement

- objetivo: entregar resolução exata, enforcement e governança segura;
- escopo: W2-07/W2-08, entitlement, antiescalada, commands de profiles,
  usuários/convites e contrato de resolvers resource-specific;
- fora de escopo: regras funcionais de recursos futuros, Global Admin e
  service-role como autorização de usuário;
- artefatos: evaluator privado, commands autenticados, matriz técnica e Audit;
- testes: álgebra exata, entitlement, stale JWT, commands, convite,
  concorrência, último administrador e chamadas diretas;
- gate: `W2C_AUTHORIZATION_ENGINE_READY = YES` somente com pgTAP real.

### W2D — projection e cache

- objetivo: expor capabilities self seguras e convergir cache/UI;
- escopo: projection RPC, vetor de revisão, provider/hook, query keys,
  revalidação em foco/intervalo/command e BroadcastChannel de invalidação;
- fora de escopo: tela administrativa completa, autorização pelo frontend e
  persistência de permissions no storage do browser;
- artefatos: RPC tipada, provider/hook, geração, query keys e estados;
- testes: revisão, limpeza integral, outra sessão, multitab, sem permission e
  rota tenant-safe;
- gate: `W2D_AUTHORIZATION_PROJECTION_READY = YES` após unit/E2E.

### W2E — hardening e fechamento

- objetivo: revisão adversarial de W2A–W2D e fechamento formal;
- escopo: W2-09, RLS por operação, grants/helpers, regressão W1, segurança,
  documentação e gates;
- fora de escopo: feature nova, Global Admin, resources funcionais e W3;
- artefatos: policies finais, suíte consolidada, inspeções e docs;
- testes: matriz completa A/B, anon, cross-tenant, grants/search paths,
  commands, cache, regressão W1 e suíte final;
- gate: `W2E_AUTHORIZATION_HARDENING_READY = YES` somente sem finding bloqueante.

Somente depois de todos os subgates poderão ser avaliados:

```text
W2A_AUTHORIZATION_MODEL_READY
W2B_PROFILES_OVERRIDES_READY
W2C_AUTHORIZATION_ENGINE_READY
W2D_AUTHORIZATION_PROJECTION_READY
W2E_AUTHORIZATION_HARDENING_READY
AUTHORIZATION_READY
```

## 24. CLOSED / DEFERRED / BLOCKER

### 24.1 CLOSED

- catálogo físico opção A: uma linha por combinação válida;
- `OWN`, `ASSIGNED`, `TEAM` e `ALL_TENANT` são a taxonomia oficial; `ASSIGNED`
  é atribuição operacional individual e não sinônimo de `OWN`;
- código `<module>.<resource>.<action>.<scope>` lowercase/snake_case e ID UUID
  determinístico; labels não são autoridade;
- profile singular ligado à `tenant_membership`, nunca ao `app_user`;
- baseline presença=`ALLOW`, ausência=deny implícito;
- override `ALLOW`/`DENY`, ausência=herdar e nenhum `INHERIT` persistido;
- evaluator central de scopes + resolvers/facts resource-specific;
- arquitetura RLS híbrida, commands `AUTH-02`, UI somente projeção;
- vetor de revisão membership/profile/catalog + generation local;
- profiles padrão tenant-owned editáveis, inativação sem hard delete;
- seed de plataforma separado de provisioning tenant e grant futuro não
  retroativo;
- `BD-02` fechado para o catálogo W2: as onze combinations administrativas
  tenant da seção 20.3 são delegáveis sob antiescalada exata; capabilities CW
  permanecem fora do catálogo tenant;
- Global Admin fora da autorização tenant e service role somente técnica.

### 24.2 DEFERRED — não bloqueia W2A

- predicados `OWN`/`ASSIGNED` exatos de Solicitação, OS, Ativo e demais recursos,
  definidos com o schema de cada módulo;
- modelagem de Equipes/Setores e resolvers `TEAM`; até lá, nenhum grant TEAM;
- baselines funcionais de Técnico, Auxiliar e Solicitante por módulo;
- permission de navegação do Calendário, se a UX provar necessidade além da
  união dos resources de origem;
- autoridade/commands completos de Global CW Admin (`PLAT-01`, fase própria);
- retenção legal e UI de consulta completa do Audit;
- expansão futura de resources/actions, sempre por migration e decisão
  explícita, sem auto-grant.

### 24.3 BLOCKER

Nenhum. `W2-BLK-01` está **CLOSED**: `ASSIGNED` é scope oficial da autorização
tenant. Facts concretos de `OWN` e `ASSIGNED` por resource, e os resolvers de
`TEAM`, continuam diferidos e não bloqueiam W2A, pois a infraestrutura suporta
os quatro scopes sem inventar facts de domínio.

## Gates atuais

```text
W2_PLAN_COMPLETE = YES
W2A_AUTHORIZATION_MODEL_READY = NO
W2B_PROFILES_OVERRIDES_READY = NO
W2C_AUTHORIZATION_ENGINE_READY = NO
W2D_AUTHORIZATION_PROJECTION_READY = NO
W2E_AUTHORIZATION_HARDENING_READY = NO
AUTHORIZATION_READY = NO
```

W2A–W2E e W3 não foram iniciadas. `W2_PLAN_COMPLETE = YES` formaliza somente o
plano; não promove nenhum gate de implementação.
