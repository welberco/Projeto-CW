# Componentes Críticos da Migração V1 → V2 — Etapa 10C

| Campo | Valor |
| --- | --- |
| Projeto | CW ERP / CW Manutenção |
| Etapa | Fase A — Etapa 10C |
| Natureza | Plano técnico documental de componentes críticos |
| Estado | Especificação para implementação e ensaio posteriores |
| Execução | Nenhuma migration, ETL, carga, acesso remoto ou alteração de sistema |
| Destino normativo | Arquitetura Técnica Oficial CW ERP V2 — `FROZEN BASELINE` |

## 1. Objetivo

Detalhar o plano técnico de migração dos componentes cujo erro pode provocar perda de identidade, acesso cross-tenant, escalada de privilégio, colisão de códigos, falsificação de autoria, perda de rastreabilidade ou associação incorreta de arquivos.

O documento transforma as decisões aprovadas das Etapas 10A e 10B em contratos conceituais para implementação posterior de migrations, ETL, manifests, validações, reconciliação, rehearsal e cutover, sem escolher DDL ou executar qualquer operação.

Componentes cobertos:

1. Auth identities;
2. application users;
3. tenant memberships;
4. profile baselines e overrides individuais;
5. Global Admin/platform identities;
6. estados de usuário e entitlements;
7. códigos humanos e counters;
8. autoria histórica;
9. Operational History, Audit e Migration Provenance;
10. arquivos, metadados, associações e Storage.

## 2. Escopo

Incluído:

- caminhos de preservação ou remapeamento de Auth UUID;
- separação formal entre identidade, usuário, membership, perfil, permissão e autoridade;
- regras default deny e de menor privilégio para migração de capabilities;
- classificação de atores históricos e autoria cross-tenant;
- inventário, preservação e reconciliação de códigos/counters;
- regras para converter histórico operacional sem retrofabricar Audit;
- registry/ledger bidirecional de provenance;
- manifest de Storage, associação contextual, integridade, inconsistências e retenção;
- gates, blockers, métricas e revalidações necessárias para a 10D.

Fora do escopo:

- acesso a Supabase, PostgreSQL, Auth, Storage, Edge Functions, GitHub ou produção remotos;
- DDL, SQL, migrations, ETL, scripts, RPCs, RLS, policies, buckets, usuários, fixtures ou objetos;
- redefinição automática de senha, modificação de sessão ou disparo de mensagens;
- limpeza física, deduplicação destrutiva ou correção silenciosa;
- reabertura de decisão `CLOSED` ou promoção de item futuro.

## 3. Fontes e precedência

Fontes obrigatórias consideradas integralmente:

1. `PRODUCT_SPEC.md` — regras funcionais e escopo;
2. `docs/ARQUITETURA-TECNICA-V2.md` — decisões técnicas `CLOSED`;
3. `docs/MIGRACAO-V1-V2-10A-ESTRATEGIA.md` — estratégia aprovada;
4. `docs/MIGRACAO-V1-V2-10B-MAPEAMENTO.md` — mappings aprovados;
5. `docs/INVENTARIO-V1.md` — evidência do legado conhecido;
6. `docs/GAP-ANALYSIS-V1-V2.md` — apoio comparativo;
7. `AGENTS.md` — governança do repositório.

Precedência: produto → arquitetura → 10A → 10B → inventário → GAP. SQLs versionados da V1 apoiam a identificação de estruturas, mas não provam o estado remoto.

Toda conclusão que dependa de schema, configuração ou dados remotos recebe `REVALIDATION_REQUIRED`. Ausência de evidência nunca vira default, autorização, tenant, ator, código ou associação por suposição.

## 4. Princípios de segurança

1. **Default deny:** ausência de grant comprovado resulta em ausência de acesso.
2. **Least privilege:** migrar apenas a combinação exata aprovada.
3. **Tenant explícito:** tenant do payload, URL, JWT metadata, path ou maioria dos registros não é autoridade.
4. **Sem autoridade cross-tenant implícita:** plataforma, tenant e processo técnico são autoridades distintas.
5. **Sem ator fabricado:** ausência de autoria permanece explícita.
6. **Sem privilege expansion:** similaridade de papel/permissão não concede capability.
7. **Sem correção silenciosa:** toda resolução cria decisão e provenance.
8. **Sem cleanup destrutivo:** nenhum órfão ou duplicado é apagado nesta etapa.
9. **Provenance integral:** source, regra, run, decisão e target permanecem rastreáveis.
10. **Reconciliação antes de ativação:** carga tecnicamente concluída não significa dado autorizado para uso.
11. **RLS e integridade juntas:** RLS não substitui FK tenant-aware; execução privilegiada não substitui nenhuma delas.
12. **Idempotência:** retry não cria identidade, grant, código, evento ou objeto duplicado.
13. **Segregação de funções:** quem executa tecnicamente não decide sozinho mapping de negócio/segurança.
14. **Imutabilidade histórica:** correções usam eventos/decisões compensatórias, não reescrita oculta.

## 5. Modelo de identidades

### 5.1 Matriz de conceitos

| Conceito | Fonte V1 | Destino V2 | Identidade | Tenant | Autoridade | Migração | Risco |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Auth Identity | `auth.users` | identidade do provedor Auth | UUID Auth preservado ou explicitamente remapeado | não define tenant | autenticação, não autorização | Path A/B | perda de login/referências |
| Application User | `perfis` | usuário operacional | UUID interno vinculado à Auth identity/legacy actor | não substitui membership | nenhuma capability implícita | mapear dados cadastrais | duplicação de autoridade Auth |
| Tenant Membership | `perfis.organizacao_id` + evidência | vínculo User ↔ Tenant | identidade própria/relacional | exatamente um tenant operacional para comum | contexto elegível, não grant | validar explicitamente | acesso cross-tenant |
| Profile Baseline | `perfis.papel` + matriz efetiva | baseline de capabilities | profile V2 | tenant-owned | grants padrão exatos | classificação revisada | privilégio por nome |
| Individual Override | não comprovado como entidade V1 | ALLOW/DENY exato | combinação User+Resource+Action+Scope | tenant-owned | altera combinação exata | criar somente por decisão | álgebra incorreta de scopes |
| Platform Identity | candidatos administrativos aprovados | identidade/capabilities de plataforma | separada do catálogo tenant | independe de membership para existir | commands de plataforma | lista aprovada | Global Admin indevido |
| Technical Identity | functions, workers, processo de migração | identidade técnica limitada | handler/processo/run | target explícito quando aplicável | capability técnica fixa | registrar, não personificar | service role funcional |
| Legacy Actor | UUID/nome histórico sem identidade operacional adequada | referência histórica | identity de provenance | tenant histórico quando conhecido | nenhuma capacidade atual | preservar | perda de autoria |
| Unresolved Actor | null/ID inexistente/ambíguo | marcador explícito | sem usuário humano | desconhecido ou evidenciado | nenhuma | preservar ausência | autoria falsificada |

### 5.2 Invariantes

```text
Auth Identity
!= Application User
!= Tenant Membership
!= Profile Baseline
!= Permission Override
!= Platform Identity
!= Technical Identity
```

- Uma referência pode conectar conceitos, mas não os funde.
- Auth autenticada sem membership não ganha tenant.
- Membership sem capability não autoriza operação.
- Profile não substitui avaliação Resource + Action + Scope.
- Platform identity não depende de papel tenant.
- Technical identity não representa pessoa nem adquire capacidade funcional.

## 6. Auth

### 6.1 Manifest Auth futuro

O snapshot autorizado deve capturar, sem secrets ou password hashes exportados indevidamente:

| Campo conceitual | Uso | Tratamento |
| --- | --- | --- |
| legacy Auth UUID | identidade e referências | chave do identity mapping |
| e-mail normalizado + original | login/contato/evidência | detectar duplicidade; não usar sozinho como prova |
| provider/identities | continuidade do mecanismo | validar compatibilidade |
| confirmation state | lifecycle Auth | preservar conforme capability do provider |
| created/updated timestamps | provenance | preservar instantes válidos |
| last sign-in | diagnóstico opcional | não determina status ou entitlement |
| disabled/banned state | lifecycle Auth | mapear apenas se semântica/provider comprovados |
| metadata | evidência auxiliar | nunca autoridade de tenant/papel/permissão |
| referências em tabelas | impacto do remapeamento | contar e resolver todas |

Todos os campos remotos são `REVALIDATION_REQUIRED`.

### 6.2 Path A — UUID Auth preservável

Pré-condições cumulativas:

1. provider e projeto/ambiente permitem preservação segura;
2. UUID é único e não colide no destino;
3. identidade e e-mail/providers correspondem sem ambiguidade;
4. lifecycle/confirmation pode ser preservado sem enfraquecer segurança;
5. password/session continuity é suportada oficialmente e ensaiada;
6. referências apontam para a mesma pessoa/identidade;
7. processo não exige transportar secret não permitido.

Resultado conceitual:

```text
legacy_auth_user_id == target_auth_user_id
+ registry entry
+ provenance
+ references validated
```

Mesmo no Path A, membership, status, profile, entitlement e capabilities são migrados separadamente.

### 6.3 Path B — UUID Auth não preservável

Quando qualquer pré-condição do Path A falhar:

```text
legacy_auth_user_id
→ explicit identity decision
→ new_auth_user_id
→ registry mapping
→ rewrite de todas as referências via registry
→ reconciliation
```

Requisitos:

- mapping 1:1 ou exceção explicitamente aprovada;
- nenhuma referência resolvida por e-mail/nome de forma isolada;
- actor histórico pode permanecer `LEGACY_ACTOR` sem virar login atual;
- mecanismo de convite/ativação e comunicação definido antes do cutover;
- senha não é resetada automaticamente nesta etapa;
- sessões antigas não são presumidas válidas;
- impacto em MFA, providers externos, confirmação e recuperação deve ser ensaiado;
- mapping deve ser idempotente e auditável.

### 6.4 Estados problemáticos

| Caso | Tratamento | Disposition |
| --- | --- | --- |
| Auth sem `perfis` | manter identity; decidir application user/membership separadamente | `REQUIRES_REVIEW` |
| `perfis` sem Auth | preservar como legacy/application record; não criar login automaticamente | `REQUIRES_REVIEW` |
| e-mail duplicado | não escolher vencedor por timestamp | `QUARANTINE` |
| UUID colidido com outra identidade | Path B + revisão | `QUARANTINE` |
| provider incompatível | Path B ou estratégia provider-specific | `REQUIRES_REVIEW` |
| metadata conflita com tabelas | metadata não prevalece | `LEGACY_ONLY` como autoridade |
| estado banned/disabled desconhecido | negar ativação até revisão | `REQUIRES_REVIEW` |

## 7. Application User

O usuário de aplicação contém dados operacionais, não credenciais ou autorização duplicada.

| Fonte `perfis` | Destino V2 | Regra | Ausência/conflito |
| --- | --- | --- | --- |
| `id` | vínculo à Auth identity ou legacy actor | resolver pelo identity registry | sem Auth não cria Auth automaticamente |
| `nome` | nome de exibição | trim não destrutivo; preservar original | vazio = `NOT_CAPTURED`, revisão conforme UX |
| `email` | contato/display candidate | comparar com Auth; Auth governa login | divergência preservada e revisada |
| `loja` | afiliação textual legada | provenance e classificação estrutural | não vira tenant/Local/Equipe automaticamente |
| `organizacao_id` | fonte candidata de membership | resolver tenant registry | null não recebe primeiro tenant |
| `papel` | profile baseline candidate | matriz da seção 10 | não concede capacidade por si só |
| `ativo`, `aprovacao` | evidência de status/lifecycle | matriz da seção 9 | não colapsar em booleano V2 |
| `aprovado_por/em` | história de decisão candidata | actor/time resolution | não retrofabricar Audit |
| `criado_em` | provenance/created timestamp | preservar se válido | distinguir da criação Auth |

O Application User não armazena senha, sessão, provider ou cópia autoritativa das capabilities.

## 8. Membership

### 8.1 Contrato

```text
Application User
+ target Tenant
+ membership status/provenance
→ Tenant Membership
```

Para usuário comum ativo, deve existir exatamente um tenant operacional. Global Admin é tratado fora desta regra; ainda assim, atuar num tenant exige target/contexto explícito por command de plataforma.

### 8.2 Classificação

| Caso | Evidência | Resultado | Disposition |
| --- | --- | --- | --- |
| `perfis.organizacao_id` válido, tenant mapeado e nenhuma evidência conflitante | FK + snapshot + referências coerentes | uma membership candidata | `DETERMINISTIC` após revalidação |
| zero memberships/perfil sem tenant | ausência | nenhuma ativação tenant | `REQUIRES_REVIEW` |
| mais de uma membership candidata para usuário comum | vínculos/uso divergentes | nenhuma escolha por maioria | `QUARANTINE` |
| tenant inexistente | FK quebrada | impedir membership | `QUARANTINE` |
| tenant Suspenso/Inativo | status aprovado | membership pode ser preservada inativa; operação bloqueada | `REQUIRES_REVIEW` |
| vínculo apenas em JWT metadata | metadata | não criar membership | `REQUIRES_REVIEW` |
| `usuario_operacoes`/`loja` sugere outro tenant | relação secundária | investigar, não sobrepor `organizacao_id` | `QUARANTINE` quando segurança é afetada |
| maioria dos registros está em outro tenant | frequência | não inferir membership | `REQUIRES_REVIEW` |

### 8.3 Validação

- tenant mapping existe e está aprovado;
- application user/identity mapping existe;
- não há segunda membership operacional comum;
- membership status não contradiz Auth/application lifecycle;
- origem/evidência e reviewer ficam no registry;
- registros históricos cross-tenant não alteram automaticamente a membership atual;
- capabilities só são avaliadas depois da membership.

## 9. Status e entitlements

### 9.1 Dimensões independentes

| Dimensão | Exemplos | Autoridade |
| --- | --- | --- |
| Auth lifecycle | confirmed, disabled/banned, provider state | Auth/provider |
| Application User status | Active, Blocked, Inactive | comando administrativo V2 |
| Membership status | active/inactive/pending conforme modelo futuro | vínculo tenant |
| Tenant status | Active, Suspended, Inactive | plataforma/tenant conforme campo |
| Entitlement | módulo/recurso/limite habilitado | controle de produto/plataforma |
| Authorization | Resource + Action + Scope efetivos | baseline + override + contexto |

Nenhuma dimensão substitui outra.

### 9.2 Estado legado

| `ativo` | `aprovacao` | Candidato V2 | Regra | Disposition |
| --- | --- | --- | --- | --- |
| true | aprovado | Active candidate | Auth válido, membership resolvida e tenant operacional | `CONDITIONAL` |
| false | aprovado | Blocked ou Inactive | booleano não distingue intenção | `REQUIRES_REVIEW` |
| false | pendente | membership/application pending; não Active | preservar lifecycle sem ativar | `CONDITIONAL` |
| false | rejeitado | Inactive/Blocked candidate | intenção e retenção precisam revisão | `REQUIRES_REVIEW` |
| true | pendente/rejeitado | estado conflitante | negar ativação até resolver | `QUARANTINE` |
| null/valor fora do enum | UNKNOWN | estado não classificável | não aplicar Active por default | `QUARANTINE` |

Blocked/Inactive preservam autoria e referências; não causam exclusão física.

### 9.3 Entitlements

Entitlement V2 nasce de decisão/configuração explícita de plataforma:

```text
target tenant
+ approved product/module configuration
+ effective period/status
→ entitlement
```

- existência de tabela, usuário, permissão ou dado V1 é somente evidência de uso;
- nenhum módulo futuro é habilitado por presença de dado;
- ausência de decisão resulta em default deny;
- entitlement de migração precisa de source/reviewer/approved_at/reason;
- limites de usuários/Storage não são inferidos de contagens atuais;
- dados históricos podem ser preservados mesmo sem entitlement operacional, conforme acesso/retention aprovados.

## 10. Profiles

### 10.1 Baselines oficiais

Perfis funcionais conhecidos: Manager/Gestor, Technician/Executor, Assistant/Auxiliar e Requester/Solicitante. Global Admin não integra esse catálogo.

### 10.2 Matriz preliminar

| Legacy role/profile | Significado conhecido | Candidate V2 profile | Confidence | Evidência exigida | Disposition |
| --- | --- | --- | --- | --- | --- |
| `administrador` | bypass/ampla gestão em gerações V1 | Manager tenant candidate ou platform candidate separado | LOW | tenant real, capabilities efetivas, aprovação de plataforma | `REQUIRES_REVIEW` |
| `gestor` | gestão ampla no tenant na camada incremental | Manager | MEDIUM | matriz efetiva e tenant único | `CONDITIONAL` |
| `gestor_manutencao` | gestão de manutenção em geração anterior | Manager candidate | MEDIUM | ações efetivas e diferenças para baseline | `CONDITIONAL` |
| `empreendimento` | papel antigo normalizado para gestor | Manager candidate | LOW | significado histórico e ações | `REQUIRES_REVIEW` |
| `tecnico` | leitura/execução parcial conforme geração | Technician | MEDIUM | capabilities reais e atribuições | `CONDITIONAL` |
| `manutencao` | papel antigo normalizado para técnico | Technician candidate | LOW | significado e período | `REQUIRES_REVIEW` |
| `auxiliar` | operações administrativas/operacionais amplas em seed incremental | Assistant | MEDIUM | matriz por tenant e privilégio excessivo | `CONDITIONAL` |
| `usuario_padrao` | criação/visão própria e aceite parcial | Requester candidate | MEDIUM | ações efetivas e escopo | `CONDITIONAL` |
| `lojista` | criação própria/agendamento e vínculo loja | Requester candidate | MEDIUM | tenant/operação e grants efetivos | `CONDITIONAL` |
| `solicitante` | papel base anterior | Requester | MEDIUM | permissões efetivas | `CONDITIONAL` |
| valor desconhecido | UNKNOWN | nenhum | UNKNOWN | decisão humana | `QUARANTINE` |

### 10.3 Perfil incompatível

Quando as permissões comprovadas não cabem com segurança num baseline:

1. escolher o baseline de menor privilégio que corresponda ao núcleo comprovado;
2. representar exceções somente por overrides individuais exatos e aprovados;
3. não criar perfil genérico privilegiado para “preservar comportamento”;
4. manter capability sem scope conhecido como não concedida;
5. registrar diferença V1 conhecida × V2 planejada.

## 11. Permissions Resource/Action/Scope

### 11.1 Semântica imutável

```text
Capability = Resource + Action + Scope

EFFECTIVE_SCOPES =
  baseline scopes sem DENY exato
  union
  ALLOW overrides exatos
```

- `DENY OWN` não recorta `ALLOW ALL_TENANT`.
- `DENY TEAM` não recorta `ALLOW ALL_TENANT`.
- Para remover `ALL_TENANT`, remover/negar `ALL_TENANT` explicitamente e conceder menores quando aprovado.
- O acesso é permitido se ao menos um scope efetivo alcançar o registro.
- Definições OWN, ASSIGNED e TEAM são específicas por Resource.

### 11.2 Registro de classificação

Cada legacy permission recebe:

| Campo | Conteúdo |
| --- | --- |
| rule ID/version | identidade imutável do mapping |
| source tenant/profile/action | chave legada |
| semantic evidence | policies, UI, functions e uso revalidado |
| Resource/Action/Scope candidates | combinação exata |
| destination kind | baseline ou override individual |
| confidence | HIGH/MEDIUM/LOW/UNKNOWN |
| decision | SAFE_MAP, revisão, legacy-only ou quarantine |
| reviewer/approval | identidade, motivo e timestamp |
| privilege comparison | V1 known versus V2 planned |

### 11.3 Categorias de decisão

| Categoria | Critério | Resultado |
| --- | --- | --- |
| `SAFE_MAP` | Resource, Action e Scope inequívocos e não ampliados | candidato à carga após validações |
| `REQUIRES_SCOPE_REVIEW` | ação conhecida, alcance ausente/ambíguo | nenhum grant até decisão |
| `REQUIRES_ACTION_REVIEW` | nome amplo combina várias ações V2 | decompor; nenhum grant aproximado |
| `LEGACY_ONLY` | comportamento incompatível, como delete comum/bypass | preservar evidência, não conceder |
| `QUARANTINE` | grant crítico conflitante/desconhecido | bloqueia ativação aplicável |

### 11.4 Procedimento

1. Inventariar linhas `permissoes_perfis`, seeds, policies, funções, UI e bypasses.
2. Determinar comportamento conhecido por versão/tenant.
3. Separar permissão explícita de bypass por papel.
4. Classificar Resource e Action sem agrupar mutações críticas em “editar”.
5. Classificar Scope; ausência nunca vira `ALL_TENANT`.
6. Escolher baseline de menor privilégio.
7. Criar override somente para diferença exata, comprovada e aprovada.
8. Comparar privilégio efetivo V1 conhecido × V2 planejado.
9. Rejeitar expansão não aprovada.
10. Registrar reviewer, evidence e rule version.

### 11.5 Exemplos de risco

- `configuracoes_editar`, `os_editar`, `ativos_editar` e `prestadores_editar` precisam decomposição por Action.
- `solicitacao_editar` não codifica Scope; exige revisão.
- `os_visualizar_resumo` não justifica inventar novo Scope sem matriz técnica.
- `administrador`/`gestor` com bypass não gera todos os grants explícitos.
- `permitido=false` de baseline não vira DENY individual automaticamente.
- `criar_preventiva` em Request é `LEGACY_ONLY`; autoridade preventiva deve ser classificada no domínio correto.

## 12. Global Admin

### 12.1 Separação

Global Admin é platform identity/capability, não Profile tenant. A migração utiliza uma lista explicitamente aprovada:

| Campo | Requisito |
| --- | --- |
| legacy identity | Auth mapping inequívoco |
| platform identity | target separado do profile tenant |
| evidence | vínculo/autoridade CW documentados |
| approved_by | autoridade competente distinta quando exigido |
| approved_at | timestamp da decisão |
| reason | necessidade e escopo |
| capabilities | mínimas e explícitas |
| provenance | source, rule, run e resolução |

### 12.2 Casos

| Caso | Resultado |
| --- | --- |
| admin de um tenant | candidato a Manager tenant, nunca Global Admin automático |
| bypass legado permitia múltiplos tenants | `QUARANTINE` até explicar autoridade e dados |
| metadata/papel contém “admin” | evidência insuficiente |
| identidade CW nominal e formalmente aprovada | platform mapping condicionado à Auth identity |
| candidato não aprovado | nenhuma platform capability; preservar decisão |

Platform identity existe sem membership tenant, mas cada command tenant-targeted exige target explícito, capability de plataforma, motivo quando aplicável, reautorização e Audit.

## 13. Technical identities

### 13.1 Migration actor

```text
technical identity
+ migration_run_id
+ release/migration identifier
+ handler/operation allowlist
+ target tenant/entity
→ ação técnica auditável
```

Invariantes:

- não é usuário humano;
- não recebe profile ou override funcional;
- capability é fixa por processo/handler e limitada ao efeito;
- payload não define tenant, ator ou autoridade;
- origem é relida do snapshot/registry confiável;
- logs preservam correlação e omitem secrets/signed URLs/conteúdo excessivo;
- retries são idempotentes;
- kill switch e revogação são possíveis;
- resultado inclui sucesso/falha/quarentena sem mascarar erro.

### 13.2 Service role

`service_role` é credencial privilegiada capaz de bypassar RLS, não “usuário técnico comum”. Se a implementação futura justificar seu uso:

- somente runtime server-side controlado;
- credencial isolada por ambiente e, quando possível, por responsabilidade;
- mínimo escopo e duração possíveis;
- nunca em frontend, bundle, fixture, log ou registry;
- rotação antes/depois conforme plano de segurança;
- kill switch operacional;
- nenhuma autorização funcional derivada dela;
- validação explícita de tenant/FKs/invariants antes da escrita;
- Audit técnico e reconciliação obrigatórios.

## 14. Autoria

### 14.1 Classificação

| Classe | Critério | Destino |
| --- | --- | --- |
| `MAPPED_ACTOR` | identity mapping confiável e contexto plausível | referência ao Application User/Auth identity apropriada |
| `LEGACY_ACTOR` | ator histórico conhecido, sem login/identidade operacional adequada | referência histórica/provenance sem capacidade |
| `UNRESOLVED_ACTOR` | null, inexistente, duplicado ou ambíguo | marcador explícito; nenhuma pessoa inventada |
| `TECHNICAL_ACTOR` | trigger/function/scheduler/processo comprovado | identidade técnica e origem do mecanismo |

### 14.2 Resolução

```text
source actor ID/name
→ identity registry lookup
→ tenant/context at event time
→ technical/platform evidence
→ classification
→ target reference or unresolved marker
→ provenance
```

Nome, e-mail ou tenant atual isolados não bastam. `usuario_nome` histórico é snapshot de exibição, não prova de identidade. `auth.uid()` nulo em trigger pode indicar execução técnica, mas precisa de evidência do writer.

### 14.3 Regras por tipo de fato

- autoria obrigatória de criação sem ator resolvido pode bloquear o registro conforme criticidade;
- histórico operacional pode permanecer com `UNRESOLVED_ACTOR` se o fato e parent forem válidos e a política aprovar;
- aprovação, permissão ou ação administrativa sensível sem ator confiável exige revisão/quarentena;
- nunca atribuir registros ao primeiro gestor, criador do tenant ou migration actor como substituto do autor histórico;
- migration actor assina a transformação, não o fato legado.

## 15. Cross-tenant authorship

### 15.1 Workflow

```text
DETECT record.tenant != actor.current_tenant
→ CLASSIFY tipo de vínculo/tempo
→ GATHER membership histórica, parent, Auth, writer, platform/technical evidence
→ RESOLVE actor/tenant ou QUARANTINE
→ REGISTER provenance/reviewer
→ RECONCILE por tenant e classe
```

### 15.2 Reason codes

| Reason code | Uso |
| --- | --- |
| `ACTOR_TENANT_MISMATCH` | tenant atual/conhecido do ator diverge do registro |
| `RECORD_TENANT_UNCERTAIN` | próprio tenant do registro não é confiável |
| `ACTOR_MEMBERSHIP_UNCERTAIN` | membership na data do fato não pode ser provada |
| `LEGACY_CROSS_TENANT_CONTEXT` | contexto legado/plataforma pode explicar a ação |
| `UNRESOLVED_AUTHORSHIP` | ator não pode ser identificado com segurança |

### 15.3 Decisões

| Evidência | Resultado | Disposition |
| --- | --- | --- |
| membership histórica válida no tenant do fato | `MAPPED_ACTOR` com contexto histórico | `CONDITIONAL` |
| function/trigger/scheduler comprovado | `TECHNICAL_ACTOR` | `CONDITIONAL` |
| authority de plataforma explicitamente aprovada | platform actor + target tenant | `CONDITIONAL` |
| apenas membership atual diverge | não declarar vazamento/corrupção | `REQUIRES_REVIEW` |
| relation cross-tenant viola parent/child | não corrigir pelo ator | `QUARANTINE` |
| sem evidência suficiente | `UNRESOLVED_ACTOR` ou quarantine conforme impacto | `REQUIRES_REVIEW` |

## 16. Códigos

### 16.1 Dimensões

| Dimensão | Regra |
| --- | --- |
| internal UUID | identidade técnica V2; nunca depende do código |
| legacy ID | source identity no registry |
| human code | valor histórico emitido, preservado exatamente |
| namespace | Request, OS, Asset, Tenant etc. |
| tenant | dimensão obrigatória de unicidade quando definida |
| year | aplicável a Request/OS; não presumido para Asset |
| counter | estado de alocação, não prova única dos códigos emitidos |

### 16.2 Inventário conceitual

Por `entity type + tenant + namespace + year quando aplicável`:

- source table/fields;
- todos os issued codes e source IDs;
- formato parseável ou raw;
- duplicate groups;
- máximo componente numérico parseável;
- stored counters/sequences;
- gaps;
- código nulo/inválido;
- target preservation status;
- safe next candidate;
- conflicts/reviewer/resolution;
- snapshot e delta identity.

### 16.3 Regras

- preservar códigos emitidos, inclusive `EQP-*` quando o padrão novo for `AT-*`;
- preservar `demandas.codigo` e `codigo_solicitacao` como aliases/source values até decisão de precedência;
- não renumerar, compactar gap, reutilizar ou substituir silenciosamente;
- formato inválido não apaga o valor histórico;
- código novo gerado para registro legado sem código deve ser marcado como V2, não fingido como histórico;
- código duplicado no mesmo namespace/tenant entra em quarentena;
- duplicidade cross-tenant pode ser válida se namespace for tenant-scoped e ambos os tenants estiverem resolvidos;
- todo mapping de código referencia source ID e target UUID.

## 17. Counters/sequences

### 17.1 Fontes híbridas conhecidas

- `sequencias_demandas`: ano + último número, sem tenant na definição local;
- `cw_sequencias`: organização + ano + entidade (`SOL`, `OS`, `EQP`);
- códigos efetivamente gravados em `demandas`, `ordens_servico` e `ativos`;
- PostgreSQL identity sequences de PKs, que não são counters humanos;
- possíveis sequences/configurações remotas adicionais: `REVALIDATION_REQUIRED`.

### 17.2 Cálculo do safe next

```text
issued_numeric_max = max(componente numérico dos códigos elegíveis e parseáveis)
stored_counter_max = max(counters relevantes revalidados)
concurrent_delta_max = max(códigos emitidos após snapshot até freeze)

safe_next > max(issued_numeric_max, stored_counter_max, concurrent_delta_max)
```

Regras:

1. inventariar códigos antes de counters;
2. separar counter humano de identity sequence;
3. detectar namespaces/formatos concorrentes;
4. counter abaixo do emitidos não prevalece;
5. counter acima preserva gap; allocator não retrocede;
6. `EQP` anual na estrutura híbrida não autoriza reiniciar Asset code anualmente;
7. inicialização do allocator ocorre somente após snapshot + delta reconciliados;
8. allocator target deve ser atômico e tenant-aware;
9. decisão e valores de entrada ficam no ledger;
10. nenhuma inicialização ocorre nesta etapa.

## 18. Colisões

| Tipo | Definição | Impacto padrão | Tratamento |
| --- | --- | --- | --- |
| `DUPLICATE_WITHIN_TENANT` | mesmo código operacional no tenant/namespace | `CUTOVER_BLOCKER` | quarantine + decisão; sem renumerar |
| `DUPLICATE_CROSS_TENANT` | mesmo código em tenants diferentes | não bloqueante se namespace tenant-scoped | confirmar tenant e regra |
| `DUPLICATE_WITHIN_YEAR` | repetição no período anual aplicável | `CUTOVER_BLOCKER` | quarantine |
| `INVALID_FORMAT` | código não parseia no padrão conhecido | `DATA_BLOCKER` | preservar raw; decidir se operacional |
| `COUNTER_BEHIND` | counter < máximo emitido | `DATA_BLOCKER`, vira cutover se não corrigido | safe next pelos emitidos |
| `COUNTER_AHEAD` | counter > máximo emitido | normalmente não bloqueante | preservar gap e não retroceder |
| `UNKNOWN_NAMESPACE` | fonte não pode ser atribuída a namespace | `DATA_BLOCKER` | review/quarantine |
| aliases conflitantes | `codigo` e `codigo_solicitacao` divergem | `DATA_BLOCKER` | preservar ambos e decidir precedência |

Nenhuma resolução altera o código histórico original. Se um código operacional V2 alternativo for indispensável, ele deve coexistir com alias/provenance e depender de decisão explícita.

## 19. Operational History

### 19.1 Contrato de evento migrado

| Campo conceitual | Origem/Regra |
| --- | --- |
| source event identity | PK/tabela/hash estável da fonte |
| parent entity/ID | resolvido pelo registry |
| tenant | derivado do parent, comparado à fonte |
| event type | dicionário exato versionado |
| source timestamp | preservado; inconsistências sinalizadas |
| actor resolution | MAPPED/LEGACY/UNRESOLVED/TECHNICAL |
| payload relevante | campos conhecidos; raw protegido em provenance |
| target event identity | gerado/register |
| mapping rule/version | obrigatório |
| suppression/merge | somente por regra objetiva e auditável |

### 19.2 Fontes

- `historico_demandas.alteracoes`: candidato a eventos de Request;
- `historico_ordens_servico.acao/detalhes`: candidato a eventos de OS;
- eventos de anexos produzidos por triggers: histórico de mídia candidato;
- status/timestamps finais sem linha histórica: estado atual/provenance, não evento inventado;
- functions/triggers: evidência de writer, não eventos em si.

### 19.3 Deduplicação semântica

Um update legado pode produzir evento genérico e específico. Suprimir duplicata exige mesma source identity ou regra forte baseada no writer/payload, nunca apenas texto parecido e timestamp próximo. Toda supressão registra rule/version e conta na reconciliação.

Evento desconhecido permanece `LEGACY_ONLY`; não é mapeado para “updated” genérico se isso perder significado. History não vira Comment, Notification ou Audit.

## 20. Audit

### 20.1 Proibição de retrofabricação

Não criar Audit V2 histórico para permissões, logins, decisões ou alterações que não foram auditadas com os fatos mínimos. Policies/functions legadas demonstram comportamento possível, não uma ação específica executada.

### 20.2 Audit técnico futuro

Cada ação real de migração deve gerar evento append-only com:

| Campo | Requisito |
| --- | --- |
| technical actor | identidade do processo/handler |
| migration run | ID imutável |
| release/migration identity | versão do artefato/regra |
| tenant | target quando aplicável |
| source entity/ID/snapshot | origem precisa |
| target entity/ID | destino ou null em falha |
| operation | map/load/associate/resolve/activate etc. |
| result | success/failure/quarantine/skip idempotente |
| reason/correlation | reason code e correlation ID |
| timestamp | fonte autoritativa do processo |
| approval | quando decisão humana for necessária |

Falha em Audit obrigatório aborta/impede confirmação da operação correspondente. Correção usa novo evento/compensação, nunca update destrutivo do Audit.

## 21. Provenance

### 21.1 Registry/ledger

O registry dedicado deve responder bidirecionalmente:

- de onde veio o registro V2;
- qual source system/entity/ID/tenant/snapshot;
- qual regra/versão o transformou;
- em qual migration run/lote/onda;
- qual disposition/confidence;
- quais targets foram criados num split ou quais sources participaram de merge;
- se houve review/quarantine/resolution;
- quem aprovou, quando e por quê;
- quais códigos/aliases foram preservados;
- qual foi o resultado idempotente.

Campos conceituais mínimos:

```text
migration_run_id
source_system / source_snapshot
source_entity / source_id / source_tenant
target_entity / target_id / target_tenant
mapping_rule / rule_version
disposition / confidence / status
evidence_reference / source_hash quando aplicável
reviewed_by / approved_by / resolution / resolved_at
wave / correlation_id / timestamps
```

### 21.2 Separação

| Mecanismo | Pergunta respondida | Visibilidade |
| --- | --- | --- |
| Operational History | o que aconteceu ao registro | usuários autorizados do domínio |
| Audit | quem/qual autoridade realizou ação sensível | capability de auditoria |
| Migration Provenance | de onde veio e como foi transformado | operação técnica/governança |
| Comment | o que uma pessoa comunicou | participantes autorizados |
| Notification | qual evento foi entregue ao destinatário | destinatário autorizado |

Operational History não é o único mecanismo de provenance. Evita-se espalhar `legacy_*` por todas as tabelas operacionais; exceções dependem de necessidade aprovada.

## 22. Storage model

### 22.1 Modelo conceitual

```text
bytes no Storage
+ metadata no banco
+ association ao parent
+ tenant
+ uploader/actor resolution
+ lifecycle/classification
+ provenance
= arquivo migrado utilizável
```

Buckets V1 conhecidos: `cw-anexos`, `cw-logos`, `cw-arquivos`. Eles não determinam a quantidade, nomes ou classes de buckets V2. Destino permanece provider/lifecycle-dependent.

### 22.2 Classes de arquivos

| Fonte conhecida | Parent/class candidate | Regra |
| --- | --- | --- |
| `anexos_demandas` | Request attachment/evidence | parent Request mapeado e objeto verificado |
| `ordem_servico_arquivos` | OS evidence/document by `etapa` | `antes/durante/depois/documento` validado |
| `ativo_arquivos` | Asset photo/document | classificação depende de metadata/contexto |
| `prestador_documentos` | Supplier document | parent Supplier e tipo/finalidade quando conhecidos |
| `organizacoes.logo_path` | Tenant branding | exatamente um/versão ativa conforme decisão |

### 22.3 Estados de lifecycle de migração

| Estado | Significado |
| --- | --- |
| `DISCOVERED` | objeto/metadata capturado no manifest |
| `CLASSIFIED` | parent, tenant e classe candidatos resolvidos |
| `COPIED_UNVERIFIED` | bytes copiados, associação ainda indisponível |
| `INTEGRITY_VERIFIED` | tamanho/MIME/checksum exigido validado |
| `ASSOCIATED` | metadata e parent target vinculados |
| `AVAILABLE` | acesso pode ser ativado após autorização/reconciliação |
| `QUARANTINED` | inconsistente; não disponível operacionalmente |
| `LEGACY_ONLY` | retido fora do fluxo operacional V2 |

Nenhum objeto vai direto de `DISCOVERED` para `AVAILABLE`.

## 23. Storage manifest

Manifest conceitual por objeto:

| Grupo | Campos |
| --- | --- |
| Run/source | `migration_run_id`, snapshot, source environment |
| Identity | `source_bucket`, `source_key`, `source_object_id` quando houver |
| Physical facts | source size, declared/effective MIME, created/updated, checksum quando aplicável |
| Metadata | source table/record, name, description, stage/classification |
| Parent | source parent type/ID, target parent type/ID |
| Tenant | source tenant candidates, target tenant, evidence |
| Actor | source uploader, actor resolution |
| Target | target class, bucket class, object identity/key candidate |
| State | mapping, copy, association, integrity and availability status |
| Decision | disposition, reason code, reviewer/resolution |
| Provenance | mapping rule/version, correlation and timestamps |

Requisitos:

- identidade lógica não depende apenas de path;
- manifest diferencia metadata row e object;
- source facts são imutáveis por snapshot;
- target key é gerado/controlado, não necessariamente igual ao path V1;
- retry localiza o mesmo target por registry/idempotency key;
- contagens e bytes são agregáveis por tenant/classe/status;
- signed URL nunca integra o manifest persistente.

Nenhum inventário remoto ou download foi executado; todos os valores são `REVALIDATION_REQUIRED`.

## 24. Storage inconsistencies

| Reason code | Detecção futura | Tratamento |
| --- | --- | --- |
| `OBJECT_WITHOUT_METADATA` | object não possui metadata associável | quarantine/legacy-only; nunca apagar automaticamente |
| `METADATA_WITHOUT_OBJECT` | metadata aponta para ausência | quarantine; crítico se evidência obrigatória |
| `PARENT_NOT_FOUND` | parent source/target inexistente | quarantine ou legacy-only por valor histórico |
| `TENANT_MISMATCH` | metadata, parent, path ou owner divergem | quarantine; path não decide vencedor |
| `UPLOADER_UNRESOLVED` | ator não mapeável | unresolved actor; disponibilidade depende da política |
| `UNSUPPORTED_MIME` | effective MIME não permitido | quarantine |
| `INVALID_PATH` | key fora do formato esperado | classificar por metadata/parent, nunca autorizar pelo path |
| `DUPLICATE_OBJECT_REFERENCE` | múltiplas metadata referem mesmo object | preservar associações; revisar lifecycle |
| `POSSIBLE_DUPLICATE_CONTENT` | checksum igual | candidato informativo; sem deduplicação destrutiva |
| `CHECKSUM_MISMATCH` | source/target ou manifest divergem | quarantine e retry/investigação |
| `UNKNOWN_OBJECT_CLASS` | finalidade não identificável | review/quarantine |
| `EVIDENCE_RETENTION_REQUIRED` | arquivo é evidência/checkpoint | retenção especial; exclusão normal proibida |

Órfãos permanecem na equação de reconciliação. Nem todo órfão histórico bloqueia cutover; severidade depende de tenant, parent, valor operacional/legal e retenção.

## 25. Storage integrity

### 25.1 Níveis

| Nível | Verificações | Aplicação candidata |
| --- | --- | --- |
| Básico | existência, size, effective MIME, readable object | arquivos não críticos permitidos pela política |
| Forte | básico + checksum source/target + metadata/parent consistency | evidências, documentos relevantes e arquivos críticos |
| Retenção especial | forte + lifecycle/hold e prova de associação | checkpoint/evidência legal/operacional conhecida |

Checksum forte não é universalmente obrigatório antes de `AVAILABLE` sem análise de custo/risco, mas é obrigatório onde a política classificar o arquivo como evidência ou crítico.

### 25.2 Associação

Uma file association só pode alcançar `ASSOCIATED` quando:

1. parent mapping existe;
2. parent tenant está resolvido;
3. object tenant é coerente;
4. metadata é válida e allowlisted para a classe;
5. objeto real satisfaz tamanho/MIME/integridade exigidos;
6. uploader recebe classificação, inclusive unresolved quando permitido;
7. provenance e Audit técnico foram registrados;
8. nenhuma quarantine bloqueante permanece.

Mesmo checksum não implica mesmo significado. Cada associação lógica é preservada até decisão formal. Signed URLs antigas são `LEGACY_ONLY` ou `DISCARD_CANDIDATE`, nunca autoridade ou dado operacional.

## 26. RLS e execução privilegiada

### 26.1 RLS/FKs

O plano não depende de “desligar RLS e corrigir depois”. Ao final de cada lote, dados devem satisfazer:

- tenant target explícito e registrado;
- parent/child no mesmo tenant por FK/constraint equivalente;
- tabela tenant-owned protegida por RLS por operação;
- autoria/estado/código/invariants do domínio;
- arquivos autorizados pelo parent/contexto, não apenas path;
- nenhuma policy/grant V1 copiada literalmente.

### 26.2 Execução privilegiada

Processo técnico pode precisar de privilégio para carregar dados antes da ativação, mas:

- autoridade técnica é allowlisted e separada da funcional;
- source/tenant/target são relidos de registry confiável;
- payload não concede autoridade;
- escrita ocorre em transação/lote com validações;
- falha produz rollback/quarantine conforme contrato;
- Audit técnico e correlação são obrigatórios;
- credencial tem blast radius mínimo, rotação e kill switch;
- ativação depende de testes RLS/FK e reconciliação.

### 26.3 Artefatos legados

Functions `SECURITY DEFINER`, grants amplos e policies V1 são `legacy technical artifacts`. Regras funcionais ainda necessárias são redesenhadas conforme a baseline. Uma function existente não é uma RPC V2 validada.

Testes futuros A/B devem cobrir SELECT, INSERT, UPDATE, commands, children, files, reports/aggregates, Calendar e workers com ao menos dois tenants. Nenhum teste remoto foi executado nesta etapa.

## 27. Reconciliation Auth

### 27.1 Métricas

```text
auth_source
auth_eligible
auth_uuid_preserved
auth_uuid_remapped
auth_unresolved
auth_quarantined
auth_legacy_only

profiles_source
application_users_created
profiles_without_auth
auth_without_profiles
profiles_quarantined

membership_candidates
memberships_created
memberships_inactive
memberships_unresolved
multi_membership_conflicts

platform_candidates
platform_approved
platform_rejected
platform_unresolved
```

### 27.2 Equações/invariantes

```text
auth_eligible
= auth_uuid_preserved
+ auth_uuid_remapped
+ auth_quarantined
+ auth_legacy_only
+ approved_discard

membership_candidates
= memberships_created
+ memberships_inactive
+ memberships_unresolved
+ memberships_quarantined
```

- todo Application User aponta para Auth mapping, Legacy Actor ou decisão explícita;
- usuário comum operacional tem exatamente uma membership ativa;
- nenhuma platform identity é criada fora da lista aprovada;
- nenhum password hash/secret aparece em relatório;
- todas as referências Auth são contadas antes/depois.

## 28. Reconciliation permissions

### 28.1 Métricas

```text
legacy_permission_rows
legacy_effective_bypass_cases
safe_mapped_exact
mapped_after_scope_review
mapped_after_action_review
individual_overrides_created
quarantined
legacy_only
unresolved
```

### 28.2 Invariante anti-expansão

Para cada `user/profile + tenant + Resource + Action + Scope`:

```text
V2_planned_privilege
<= V1_proven_privilege
```

Exceção somente com aprovação explícita, motivo, reviewer, timestamp e Audit/provenance. “Era administrador” ou “nome parecido” não é aprovação.

Comparações obrigatórias:

- capabilities baseline antes/depois;
- overrides ALLOW/DENY exatos;
- scopes efetivos coletados após overrides;
- usuários que perderam acesso deliberadamente por default deny;
- grants ALL_TENANT, platform e sensitive projections;
- bypasses V1 que não foram promovidos;
- permissões sem scope/action resolvidos.

## 29. Reconciliation codes

Por `tenant + entity namespace + year quando aplicável`:

```text
source_code_rows
source_non_null_codes
unique_source_codes
duplicate_groups
invalid_format
target_preserved_codes
target_aliases
quarantined_codes
max_emitted_numeric
stored_counter
delta_max
safe_next
allocator_initialized
```

Invariantes:

- nenhum código emitido elegível desaparece;
- todos os duplicados possuem group/reason/resolution;
- gaps são preservados;
- `safe_next` excede emitidos/counter/delta relevantes;
- allocator não é ativado com namespace ambíguo;
- target UUID e human code permanecem independentes;
- aliases V1 são consultáveis no registry.

## 30. Reconciliation history

Por tenant e domínio:

```text
source_history_records
eligible_history_records
mapped_operational_history
legacy_only_events
unresolved_actor_events
technical_actor_events
quarantined_events
duplicates_intentionally_suppressed
failed_events
```

Equação:

```text
eligible_history_records
= mapped_operational_history
+ legacy_only_events
+ quarantined_events
+ duplicates_intentionally_suppressed
+ failed_events
```

Toda supressão possui rule/version e source identities. `failed_events` precisa chegar a zero ou converter-se em classe controlada antes de encerrar. Contagem fechada não basta se parent/tenant/event type estiver incorreto.

## 31. Reconciliation Storage

### 31.1 Métricas

```text
source_objects
source_metadata_rows
matched_pairs
objects_without_metadata
metadata_without_object
parent_unresolved
tenant_mismatch
mapped_associations
quarantined
legacy_only
approved_discard
failed
target_objects
integrity_basic_verified
integrity_strong_verified
bytes_expected
bytes_copied
bytes_verified
```

### 31.2 Invariantes

- todo objeto e metadata aparecem numa classe;
- matched pair não implica association até parent/tenant/integrity passarem;
- target object sem metadata/parent não chega a `AVAILABLE`;
- bytes são comparados por tenant/classe/lote quando tecnicamente viável;
- mesmo conteúdo não reduz número de associações lógicas;
- arquivo de evidência crítico ausente ou não verificado é blocker;
- nenhum signed URL integra target metadata;
- retry não duplica object/association.

## 32. Cutover gates

### 32.1 Auth/identity

Bloquear quando:

- identidade crítica não possui mapping;
- membership é inválida, múltipla ou ausente para usuário ativo;
- há duplicidade Auth relevante;
- Global Admin não foi explicitamente aprovado;
- status crítico permanece ambíguo;
- continuidade/ativação/recuperação Auth não foi ensaiada;
- referências não fecham na reconciliação.

### 32.2 Permissions

Bloquear quando:

- `ALL_TENANT` foi inferido;
- Scope/Action crítico é desconhecido;
- baseline é inseguro;
- admin tenant/plataforma permanece misturado;
- privilege expansion não foi aprovada;
- membership/capability divergem;
- testes negativos A/B falham.

### 32.3 Codes

Bloquear quando:

- duplicidade operacional não resolvida;
- `safe_next` é desconhecido;
- namespace/ano/tenant é ambíguo;
- allocator pode reutilizar código;
- snapshot + delta não reconciliam.

### 32.4 History/Audit/Provenance

Bloquear quando:

- source history crítico desaparece da equação;
- parent/tenant de evento está incorreto;
- Audit técnico obrigatório não funciona;
- registry não permite rastreio bidirecional;
- resolução de quarantine não registra reviewer/razão;
- evento sensível recebeu ator fabricado.

### 32.5 Storage

Bloquear para dados críticos quando:

- objeto obrigatório está ausente;
- parent mapping não existe;
- tenant diverge;
- evidência foi perdida ou retenção não está aplicada;
- integridade exigida não foi verificada;
- DB × Storage/bytes não reconciliam;
- acesso contextual/RLS falha.

Órfão histórico não crítico pode permanecer quarantined/legacy-only sem bloquear, desde que classificado, retido e fora do acesso operacional.

## 33. Blockers

| Blocker | Categoria | Domínio | Evidência necessária | Resolver em | Bloqueia |
| --- | --- | --- | --- | --- | --- |
| compatibilidade de preservação Auth UUID | `DESIGN_BLOCKER` | Auth | capacidade/provider e ensaio Path A/B | 10D/preparação técnica | implementação Auth final |
| schema do identity/provenance registry | `DESIGN_BLOCKER` | Identidade | modelo aprovado e consultas bidirecionais | implementação pré-10D | ETL crítico |
| placeholder/modelo de Legacy/Unresolved Actor | `DESIGN_BLOCKER` | Autoria | contrato de FK/projeção/UX | implementação pré-10D | History load |
| matriz técnica Resource/Action/Scope | `DESIGN_BLOCKER` | Permissions | catálogo, scopes e enforcement | antes do permission ETL | permission load |
| regra de entitlement inicial | `DESIGN_BLOCKER` | Produto | configuração/aprovação de plataforma | antes de ACTIVATE | ativação |
| regra de safe-next/allocator por namespace | `DESIGN_BLOCKER` | Codes | formatos e política V2 | antes do code ETL | allocator |
| modelo de Audit técnico | `DESIGN_BLOCKER` | Audit | evento/retention/failure contract | antes de LOAD | cargas auditáveis |
| protocolo Storage copy/finalize | `DESIGN_BLOCKER` | Storage | lifecycle, idempotência e integrity tiers | antes de file ETL | Storage load |
| Auth/perfis remotos não inventariados | `DATA_BLOCKER` | Auth | snapshot Auth/app | 10D PREPARE | mapping final |
| membership zero/múltipla | `DATA_BLOCKER` | Membership | tenant e histórico de vínculo | revisão de dados | ativação do usuário |
| candidatos a Global Admin | `DATA_BLOCKER` | Platform | lista/aprovação nominal | governança antes do cutover | platform access |
| scopes/actions legados | `DATA_BLOCKER` | Permissions | rows + uso/policies/functions | mapping/review | capability load |
| códigos/counters remotos | `DATA_BLOCKER` | Codes | manifest por namespace/tenant/ano | PREPARE/MAP | safe next |
| autoria cross-tenant/nula | `DATA_BLOCKER` | Authorship | membership histórica/writer | MAP/review | registros críticos |
| históricos e duplicates reais | `DATA_BLOCKER` | History | counts/payloads/writers | MAP | History load |
| manifest DB × Storage | `DATA_BLOCKER` | Storage | objects/metadata/parents/checksums | PREPARE/MAP | file load |
| identity crítica unresolved | `CUTOVER_BLOCKER` | Auth | mapping ou quarantine aceita fora do escopo | go/no-go | produção |
| privilege expansion/falha A/B | `CUTOVER_BLOCKER` | Permissions | comparação e testes negativos | rehearsal | produção |
| allocator reutiliza código | `CUTOVER_BLOCKER` | Codes | reconciliação snapshot+delta | rehearsal final | produção |
| provenance/Audit técnico incompletos | `CUTOVER_BLOCKER` | Governance | testes e consultas | rehearsal | produção |
| arquivo/evidência crítico ausente | `CUTOVER_BLOCKER` | Storage | recuperação ou decisão formal | antes do go/no-go | produção |
| reconciliação crítica aberta | `CUTOVER_BLOCKER` | Todos | relatório fechado por tenant | go/no-go | produção |

## 34. Revalidações

Checklist remoto futuro — todos os itens são `REVALIDATION_REQUIRED` e não foram executados:

### 34.1 Auth

- users, UUIDs, e-mails, providers e identities;
- confirmation, disabled/banned e lifecycle states;
- duplicates, Auth sem profile e profile sem Auth;
- created/updated/last sign-in quando necessário;
- compatibilidade de senha, MFA, sessão, convite e recuperação;
- referências a cada Auth UUID.

### 34.2 Aplicação/tenant

- `perfis`, `organizacao_id`, roles, `ativo`, `aprovacao`, aprovadores e timestamps;
- zero/múltiplas memberships candidatas;
- tenants inexistentes/Suspensos/Inativos;
- `loja`, `operacoes`, `usuario_operacoes` e vínculos divergentes;
- candidatos a platform identity.

### 34.3 Permissions/RLS

- linhas/valores de `permissoes_perfis` por tenant/profile/action;
- bypasses efetivos, grants e funções;
- policies RLS vigentes por operação;
- `SECURITY DEFINER`, owners, search paths e PUBLIC EXECUTE;
- uso real por UI/RPC/Edge Function;
- scopes comprováveis e sensitive projections.

### 34.4 Codes

- todos os códigos emitidos por entidade/tenant/ano;
- nulls, formatos, aliases e duplicidades;
- `sequencias_demandas`, `cw_sequencias` e PostgreSQL sequences;
- counter behind/ahead e namespaces adicionais;
- códigos emitidos após snapshot.

### 34.5 History/authorship

- counts por tenant/domínio/tipo;
- actor nulls/inexistentes e cross-tenant;
- payloads, timestamps e parents;
- triggers/functions/writers vigentes;
- duplicidades e eventos sem correspondência.

### 34.6 Storage

- buckets, configuração privada, quotas e policies;
- objects/metadata, IDs, keys, sizes e MIME efetivo;
- parent/tenant/uploader;
- órfãos, duplicate references e possible duplicate content;
- checksums onde viável/necessário;
- arquivos classificados como evidência/retenção;
- delta de uploads após snapshot.

### 34.7 Drift técnico

- novas tabelas/colunas/constraints/indexes/views;
- triggers, functions, grants e Edge Functions;
- schema drift e alterações manuais;
- novos casos cross-tenant;
- release atualmente publicada.

## 35. Entregáveis para 10D

A 10D deve receber deste plano e de suas revalidações:

1. snapshot/manifest versionado de Auth, app, permissions, codes, history e Storage;
2. registry/quarantine/Audit technical contracts aprovados;
3. lista Path A/Path B de Auth identities e todos os reference mappings;
4. application users, memberships e estados classificados;
5. lista nominal aprovada/rejeitada de platform identities;
6. profile baselines, exact overrides e privilege comparison;
7. catalog de rule IDs/versions e reviewers;
8. code inventory, collision register e safe-next por namespace;
9. history mapping/suppression rules e actor resolution manifest;
10. Storage manifest, integrity tier e association plan;
11. blockers/quarantine classificados por impacto;
12. métricas/equações de reconciliação e tolerâncias aprovadas;
13. artefatos idempotentes prontos para rehearsal/dry-run;
14. estratégia de delta e freeze window;
15. runbook de migration run, go/no-go, cutover e verification;
16. rollback/roll-forward/recovery ensaiados;
17. resultados de testes RLS/FK/Auth/permissions/Storage A/B;
18. critérios de estabilização e relatório pós-cutover.

Este documento não desenha todo o runbook 10D nem executa rehearsal.

## 36. Decisões deferidas

- capacidade técnica real de preservar UUID/password/session por provider;
- schema físico de identities, memberships, registry, quarantine e Audit;
- representação física de Legacy/Unresolved Actor;
- catálogo final de Resource/Action/Scope e baselines;
- lista/aprovação de platform identities;
- estados físicos de membership e política de status conflitante;
- entitlements iniciais por tenant;
- precedência operacional de códigos/aliases e política para código ausente;
- allocator/counter físico e estratégia de convivência/delta;
- taxonomia final e retenção de Operational History/Audit/Provenance;
- tolerâncias de supressão/reconciliação;
- provider/runtime/credencial do processo técnico;
- classes/quantidade de buckets e target key strategy;
- algoritmo/checksum e integrity tier por tipo de arquivo;
- retenções legais e classificação final de evidence;
- janela de freeze, thresholds Serena e estratégia exata de rollback.

Todas dependem de evidência/implementação futura e devem preservar decisões `CLOSED`.

## 37. Conclusão

### 37.1 Revisão adversarial

O plano foi revisado explicitamente e não contém regra que:

- promova tenant admin a Global Admin;
- trate JWT metadata como autoridade;
- dê tenant a usuário sem membership por inferência;
- converta permissão incerta em `ALL_TENANT`;
- faça DENY estreito subtrair Scope largo;
- trate `service_role` como usuário funcional;
- invente ator histórico;
- renumere código ou copie counter sem inventariar emitidos;
- converta History em Audit;
- produza evento sem provenance;
- use file path como única prova de parent/tenant;
- persista signed URL;
- apague órfão;
- use checksum para deduplicação destrutiva;
- disponibilize Storage sem reconciliação;
- deixe dado crítico desaparecer da equação.

Casos dependentes de dados estão explicitamente em `REVALIDATION_REQUIRED`, review ou quarantine. Execução privilegiada permanece técnica, mínima e auditada; não é atalho funcional.

### 37.2 Fechamento

Auth pode seguir Path A somente após comprovar preservação segura; caso contrário segue Path B com identity mapping total. Application User, Membership, Profile, Override, Platform Identity e Technical Identity permanecem separados. Permissões usam default deny e comparação anti-expansão.

Códigos emitidos são preservados e o allocator só nasce de issued codes + counters + delta reconciliados. Operational History, Audit e Provenance mantêm semânticas distintas, e autoria ausente/cross-tenant não recebe solução fictícia. Storage só chega a `AVAILABLE` depois de parent, tenant, metadata, integridade, provenance e autorização validados.

O próximo estágio pode implementar e ensaiar esses contratos apenas depois de resolver os `DESIGN_BLOCKER` e obter os manifests remotos classificados como `DATA_BLOCKER`. Nenhuma migration, ETL, carga, teste remoto ou alteração de sistema foi realizada na Etapa 10C.
