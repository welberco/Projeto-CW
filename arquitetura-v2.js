/* CW Manutenção v2 — rotas, módulos e paginação. Segurança efetiva permanece no RLS. */
const CWV2_PAGE_SIZE=20;
const CWV2_ROUTES={
  dashboard:['dashboard','Visão geral','Indicadores do empreendimento'],
  solicitacoes:['cwSolicitacoes','Solicitações','Corretivas, agendamentos e programadas'],
  'solicitacoes/nova':['nova','Nova solicitação','Cadastre uma nova solicitação'],
  'ordens-servico':['cwOrdens','Ordens de Serviço','Planejamento, execução e aceite'],
  calendario:['cwCalendario','Calendário','Programação de serviços'],
  ativos:['cwAtivos','Ativos e Equipamentos','Cadastro, hierarquia e manutenção'],
  prestadores:['cwPrestadores','Prestadores','Equipe própria e empresas terceirizadas'],
  usuarios:['usuarios','Grupos e Usuários','Perfis, operações e acessos'],
  relatorios:['relatorios','Relatórios','Indicadores e arquivos personalizados'],
  cadastros:['cwCadastros','Cadastros Gerais','Tipos, naturezas, prioridades e centros de custo'],
  empresa:['organizacao','Empresa','Dados e identidade do empreendimento'],
  conta:['minhaConta','Minha Conta','Seus dados e senha'],
  suporte:['cwSuporte','Suporte','Ajuda, manual e contato com a CW Engenharia']
};
const CWV2_MENU=[
  ['dashboard','▦','Dashboard'],['solicitacoes','☷','Solicitações'],['ordens-servico','▣','Ordens de Serviço'],
  ['calendario','◷','Calendário'],['ativos','◇','Ativos e Equipamentos'],['prestadores','♙','Prestadores'],
  ['usuarios','♚','Grupos e Usuários'],['relatorios','▤','Relatórios'],['cadastros','⚙','Cadastros Gerais'],
  ['empresa','▧','Empresa'],['conta','○','Minha Conta'],['suporte','?','Suporte']
];
const CWV2_PERMISSION_LABELS={
  solicitacao_visualizar_todas:'Visualizar todas as solicitações',solicitacao_visualizar_proprias:'Visualizar somente as próprias',
  solicitacao_criar:'Criar solicitações',solicitacao_editar:'Editar qualquer solicitação',solicitacao_editar_proprias:'Editar as próprias solicitações',
  solicitacao_alterar_status:'Alterar status e classificação',solicitacao_excluir:'Excluir solicitações',
  os_visualizar_todas:'Visualizar OS completas',os_visualizar_resumo:'Visualizar resumo das OS vinculadas',os_criar:'Criar e gerar OS',
  os_editar:'Planejar e editar OS',os_concluir:'Concluir OS',os_cancelar:'Cancelar OS',os_aceitar:'Registrar aceite ou recusa',
  ativos_visualizar:'Visualizar ativos e histórico',ativos_editar:'Cadastrar e editar ativos',planos_editar:'Gerenciar planos periódicos',
  prestadores_visualizar:'Visualizar prestadores',prestadores_editar:'Cadastrar e editar prestadores',usuarios_gerenciar:'Gerenciar usuários',
  configuracoes_editar:'Alterar configurações da empresa',relatorios_emitir:'Emitir relatórios',custos_visualizar:'Visualizar custos',
  custos_editar:'Lançar custos',historico_visualizar:'Visualizar históricos',galeria_visualizar:'Visualizar galeria',galeria_excluir:'Excluir arquivos da galeria'
};

Object.assign(PERMISSION_LABELS,CWV2_PERMISSION_LABELS);
el('toggleAuth').style.display='none';
signupMode=false;
el('nameField').classList.remove('visible');
el('authName').required=false;
el('signupEnterpriseField')?.remove();
document.querySelector('#authScreen .auth-card p').textContent='Acesse a gestão de manutenção';

const cwMain=document.querySelector('.shell main');
for(const [id,html] of Object.entries({
  cwSolicitacoes:'<article class="panel"><div id="cwSolicitacaoFiltros"></div><div id="cwSolicitacaoLista"></div></article>',
  cwOrdens:'<div id="cwOrdensConteudo"></div>',
  cwCalendario:'<article class="panel empty-state"><h2>Calendário</h2><p>Este módulo foi reservado para a próxima etapa. As datas previstas já permanecem organizadas nas solicitações, OS e planos.</p></article>',
  cwAtivos:'<div id="cwAtivosConteudo"></div>',
  cwPrestadores:'<div id="cwPrestadoresConteudo"></div>',
  cwCadastros:'<div id="cwCadastrosConteudo"></div>',
  cwSuporte:'<article class="panel"><h2>Central de suporte</h2><div class="cw-help-grid"><section><h3>Primeiros passos</h3><p>Cadastre operações, prestadores e ativos antes de criar planos recorrentes.</p></section><section><h3>Dúvidas frequentes</h3><p>Consulte o manual da empresa ou solicite apoio ao administrador.</p></section><section><h3>CW Engenharia</h3><p>Desenvolvimento e suporte técnico do sistema CW Manutenção.</p></section></div></article>'
})){
  if(!el(id)){const section=document.createElement('section');section.id=id;section.className='view';section.innerHTML=html;cwMain.appendChild(section)}
}

function cwCan(action){return hasPermission(action)}
function cwRouteState(){const raw=location.hash.replace(/^#\/?/,'')||'dashboard',parts=raw.split('?');return{path:parts[0]||'dashboard',params:new URLSearchParams(parts[1]||'')}}
function cwUrl(path,params){const query=params&&String(params);return`#/${path}${query?'?'+query:''}`}
function cwNavigate(path,params){const url=cwUrl(path,params);if(location.hash===url)cwRenderRoute();else location.hash=url}
function cwSetRouteFilter(name,value){const state=cwRouteState();value?state.params.set(name,value):state.params.delete(name);state.params.delete('pagina');cwNavigate(state.path,state.params)}
function cwActiveNav(path){return path.startsWith('solicitacoes')?'solicitacoes':path.startsWith('ordens-servico')?'ordens-servico':path}
function cwInstallNavigation(){
  const nav=el('sidebar').querySelector('nav');
  nav.innerHTML=CWV2_MENU.map(([route,icon,label])=>`<button class="nav" data-route="${route}"><span>${icon}</span>${label}</button>`).join('');
  nav.onclick=e=>{const button=e.target.closest('[data-route]');if(button)cwNavigate(button.dataset.route)};
  document.querySelectorAll('[data-new]').forEach(button=>button.onclick=()=>cwNavigate('solicitacoes/nova'));
}
cwInstallNavigation();

const cwLegacyShow=show;
show=function(name){
  const map={dashboard:'dashboard',demandas:'solicitacoes',nova:'solicitacoes/nova',usuarios:'usuarios',minhaConta:'conta',relatorios:'relatorios',organizacao:'empresa'};
  if(map[name]){cwNavigate(map[name]);return}
  cwLegacyShow(name);
};

async function cwRenderRoute(){
  if(!profile||profile.aprovacao!=='aprovado'||!profile.ativo)return;
  const state=cwRouteState(),base=state.path.replace(/\/$/,'');
  let route=CWV2_ROUTES[base],detail=null;
  if(/^solicitacoes\/\d+$/.test(base)){route=['cwSolicitacoes','Solicitação','Detalhes e histórico'];detail=['solicitacao',Number(base.split('/')[1])]}
  if(/^ordens-servico\/\d+$/.test(base)){route=['cwOrdens','Ordem de Serviço','Planejamento, execução e aceite'];detail=['os',Number(base.split('/')[1])]}
  if(!route){cwNavigate('dashboard');return}
  document.querySelectorAll('.view').forEach(node=>node.classList.remove('active'));
  el(route[0])?.classList.add('active');el('title').textContent=route[1];el('subtitle').textContent=route[2];el('sidebar').classList.remove('open');
  document.querySelectorAll('#sidebar [data-route]').forEach(node=>node.classList.toggle('active',node.dataset.route===cwActiveNav(base)));
  if(base==='dashboard'){cwLegacyShow('dashboard');document.querySelectorAll('#sidebar [data-route]').forEach(node=>node.classList.toggle('active',node.dataset.route==='dashboard'));return}
  if(base==='solicitacoes')await cwRenderSolicitacoes(state.params);
  else if(base==='solicitacoes/nova'){cwLegacyShow('nova');document.querySelectorAll('#sidebar [data-route]').forEach(node=>node.classList.toggle('active',node.dataset.route==='solicitacoes'));}
  else if(detail?.[0]==='solicitacao')await cwRenderSolicitacao(detail[1]);
  else if(base==='ordens-servico')await cwRenderOrdens(state.params);
  else if(detail?.[0]==='os')await cwRenderOrdem(detail[1]);
  else if(base==='ativos')await cwRenderAtivos();
  else if(base==='prestadores')await cwRenderPrestadores();
  else if(base==='cadastros')await cwRenderCadastros();
  else if(base==='usuarios')await loadUsers();
  else if(base==='relatorios')openReports();
  else if(base==='empresa')openOrganization();
  else if(base==='conta')openMyAccount();
}
window.addEventListener('hashchange',cwRenderRoute);
window.addEventListener('popstate',cwRenderRoute);

function cwDate(value,withTime=false){if(!value)return'—';return new Intl.DateTimeFormat('pt-BR',withTime?{dateStyle:'short',timeStyle:'short'}:{dateStyle:'short'}).format(new Date(value))}
function cwPager(path,params,page,total){const pages=Math.max(1,Math.ceil(total/CWV2_PAGE_SIZE)),p=Number(page)||1;if(pages===1)return'';const button=(n,label,disabled)=>`<button class="secondary" ${disabled?'disabled':''} onclick="cwGoPage('${path}',${n})">${label}</button>`;return`<div class="cw-pager">${button(p-1,'← Anterior',p<=1)}<span>Página ${p} de ${pages} · ${total} registros</span>${button(p+1,'Próxima →',p>=pages)}</div>`}
function cwGoPage(path,page){const s=cwRouteState();s.params.set('pagina',page);cwNavigate(path,s.params)}

async function cwRenderSolicitacoes(params){
  const target=el('cwSolicitacaoLista'),page=Math.max(1,Number(params.get('pagina'))||1),type=params.get('tipo')||'',status=params.get('status')||'',from=params.get('inicio')||'',to=params.get('fim')||'';
  el('cwSolicitacaoFiltros').innerHTML=`<div class="cw-toolbar"><select onchange="cwSetRouteFilter('tipo',this.value)"><option value="">Todos os tipos</option>${Object.entries(DEMAND_TYPES).map(([v,l])=>`<option value="${v}" ${type===v?'selected':''}>${l}</option>`).join('')}</select><select onchange="cwSetRouteFilter('status',this.value)"><option value="">Todos os status</option>${STATUS.map(v=>`<option ${status===v?'selected':''}>${v}</option>`).join('')}</select><label>De <input type="date" value="${esc(from)}" onchange="cwSetRouteFilter('inicio',this.value)"></label><label>Até <input type="date" value="${esc(to)}" onchange="cwSetRouteFilter('fim',this.value)"></label><button class="primary" onclick="cwNavigate('solicitacoes/nova')">＋ Nova solicitação</button></div>`;
  target.innerHTML='<p class="muted">Carregando solicitações...</p>';
  let query=db.from('demandas').select('id,codigo,codigo_solicitacao,tipo_demanda,titulo,local,prioridade,status,responsavel,empresa_prestador,criado_em,prazo,agendamento_em',{count:'exact'}).eq('organizacao_id',currentOrganizationId()).order('criado_em',{ascending:false}).range((page-1)*CWV2_PAGE_SIZE,page*CWV2_PAGE_SIZE-1);
  if(type)query=query.eq('tipo_demanda',type);if(status)query=query.eq('status',status);if(from)query=query.gte('criado_em',from+'T00:00:00');if(to)query=query.lte('criado_em',to+'T23:59:59');
  const {data,error,count}=await query;if(error){target.innerHTML=`<p class="error">${esc(error.message)}</p>`;return}
  const groups=type?[type]:Object.keys(DEMAND_TYPES);
  target.innerHTML=groups.map(kind=>{const rows=(data||[]).filter(x=>x.tipo_demanda===kind);return`<section class="cw-block"><div class="heading"><span><h2>${DEMAND_TYPES[kind]}</h2><p>${rows.length} nesta página</p></span></div>${rows.length?`<div class="cw-table-wrap"><table class="table"><thead><tr><th>Código</th><th>Tipo</th><th>Local</th><th>Prioridade</th><th>Status</th><th>Data</th><th></th></tr></thead><tbody>${rows.map(x=>`<tr><td><strong>${esc(x.codigo_solicitacao||x.codigo||x.id)}</strong></td><td>${esc(x.titulo)}</td><td>${esc(x.local)}</td><td>${badge(x.prioridade,'priority')}</td><td>${badge(x.status,'status')}</td><td>${cwDate(x.criado_em)}</td><td><button class="link" onclick="cwNavigate('solicitacoes/${x.id}')">Abrir</button></td></tr>`).join('')}</tbody></table></div>`:'<p class="muted">Nenhum registro neste período.</p>'}</section>`}).join('')+cwPager('solicitacoes',params,page,count||0);
}

async function cwRenderSolicitacao(id){
  const target=el('cwSolicitacaoLista');el('cwSolicitacaoFiltros').innerHTML='';target.innerHTML='<p class="muted">Carregando...</p>';
  const orderRequest=cwCan('os_visualizar_todas')?db.from('ordens_servico').select('id,codigo,titulo,status,inicio_previsto,executor_id').eq('solicitacao_id',id).order('criado_em',{ascending:false}):db.rpc('cw_resumo_os_solicitacao',{p_solicitacao:id});
  const [{data:d,error},{data:orders}]=await Promise.all([db.from('demandas').select('*').eq('id',id).single(),orderRequest]);
  if(error){target.innerHTML=`<p class="error">${esc(error.message)}</p>`;return}
  const orderCards=orders?.length?orders.map(o=>cwCan('os_visualizar_todas')?`<button class="cw-linked" onclick="cwNavigate('ordens-servico/${o.id}')"><strong>${esc(o.codigo)} · ${esc(o.titulo)}</strong><span>${badge(o.status,'status')}</span></button>`:`<div class="cw-linked"><strong>${esc(o.codigo)} · ${esc(o.titulo)}</strong><span>${badge(o.status,'status')}</span></div>`).join(''):'<p class="muted">Nenhuma OS vinculada.</p>';
  const editableDemand=demands.find(item=>Number(item.id)===Number(d.id)),canEdit=canEditDemand(editableDemand);
  target.innerHTML=`<article class="panel"><div class="heading"><span><h2>${esc(d.codigo_solicitacao||d.codigo||d.id)} · ${esc(d.titulo)}</h2><p>${DEMAND_TYPES[d.tipo_demanda]||d.tipo_demanda}</p></span><div class="actions"><button class="secondary" onclick="cwNavigate('solicitacoes')">Voltar</button>${canEdit?`<button class="secondary" onclick="cwEditSolicitacao(${d.id})">Editar solicitação</button>`:''}${cwCan('os_criar')?`<button class="primary" onclick="cwGenerateOs(${d.id})">Gerar OS</button>`:''}</div></div><div class="cw-detail-grid"><div><small>Status</small>${badge(d.status,'status')}</div><div><small>Prioridade</small>${badge(d.prioridade,'priority')}</div><div><small>Local</small><strong>${esc(d.local)}</strong></div><div><small>Criada em</small><strong>${cwDate(d.criado_em,true)}</strong></div><div class="wide"><small>Descrição</small><p>${esc(d.observacoes||'Sem descrição')}</p></div></div><hr><h3>Ordens de Serviço vinculadas</h3>${orderCards}<hr><h3>Galeria</h3><div id="cwDetailGallery" class="cw-gallery"></div></article>`;
  await cwLoadGallery(id,'cwDetailGallery');
}
function cwEditSolicitacao(id){const demand=demands.find(item=>Number(item.id)===Number(id));if(!canEditDemand(demand)){toast('Você não possui permissão para editar esta solicitação.');return}startEdit(id)}
async function cwGenerateOs(id){const {data,error}=await db.rpc('cw_gerar_os_solicitacao',{p_solicitacao:id});if(error){toast(error.message);return}toast(`OS ${data.codigo} criada.`);cwNavigate(`ordens-servico/${data.id}`)}

async function cwRenderOrdens(params){
  const page=Math.max(1,Number(params.get('pagina'))||1),status=params.get('status')||'',target=el('cwOrdensConteudo');target.innerHTML='<p class="muted">Carregando ordens de serviço...</p>';
  let query=db.from('ordens_servico').select('id,codigo,titulo,natureza,status,prioridade,local,inicio_previsto,fim_previsto,solicitacao_id',{count:'exact'}).eq('organizacao_id',currentOrganizationId()).order('criado_em',{ascending:false}).range((page-1)*CWV2_PAGE_SIZE,page*CWV2_PAGE_SIZE-1);if(status)query=query.eq('status',status);
  const {data,error,count}=await query;if(error){target.innerHTML=`<p class="error">${esc(error.message)}</p>`;return}
  target.innerHTML=`<article class="panel"><div class="heading"><span><h2>Ordens de Serviço</h2><p>${count||0} registros</p></span>${cwCan('os_criar')?'<button class="primary" onclick="cwShowOsForm()">＋ Nova OS</button>':''}</div><div class="cw-toolbar"><select onchange="cwSetRouteFilter('status',this.value)"><option value="">Todos os status</option>${['Aberta','Planejada','Aguardando execução','Em execução','Pausada','Concluída','Cancelada'].map(v=>`<option ${status===v?'selected':''}>${v}</option>`).join('')}</select></div><div id="cwOsForm"></div>${data?.length?`<div class="cw-table-wrap"><table class="table"><thead><tr><th>Código</th><th>Serviço</th><th>Natureza</th><th>Previsão</th><th>Status</th><th></th></tr></thead><tbody>${data.map(o=>`<tr><td><strong>${esc(o.codigo)}</strong></td><td>${esc(o.titulo)}</td><td>${esc(o.natureza||'—')}</td><td>${cwDate(o.inicio_previsto,true)}</td><td>${badge(o.status,'status')}</td><td><button class="link" onclick="cwNavigate('ordens-servico/${o.id}')">Abrir</button></td></tr>`).join('')}</tbody></table></div>`:'<p class="muted">Nenhuma OS encontrada.</p>'}${cwPager('ordens-servico',params,page,count||0)}</article>`;
}
function cwShowOsForm(){el('cwOsForm').innerHTML=`<form class="demand-form cw-inline-form" onsubmit="cwCreateOs(event)"><div class="field"><label>Título *</label><input name="titulo" required></div><div class="field"><label>Natureza</label><select name="natureza">${['Corretiva','Preventiva','Preditiva','Inspeção','Instalação','Adequação','Emergencial','Outro'].map(x=>`<option>${x}</option>`).join('')}</select></div><div class="field"><label>Local</label><input name="local"></div><div class="field"><label>Início previsto</label><input name="inicio_previsto" type="datetime-local"></div><div class="field wide"><label>Descrição</label><textarea name="descricao"></textarea></div><div class="actions"><button class="primary">Criar OS</button></div></form>`}
async function cwCreateOs(event){event.preventDefault();const f=event.target,b=f.querySelector('button');b.disabled=true;const x=Object.fromEntries(new FormData(f));const {data,error}=await db.from('ordens_servico').insert({organizacao_id:currentOrganizationId(),titulo:x.titulo,natureza:x.natureza,local:x.local||null,descricao:x.descricao||null,inicio_previsto:x.inicio_previsto?new Date(x.inicio_previsto).toISOString():null,criado_por:session.user.id}).select('id,codigo').single();b.disabled=false;if(error){toast(error.message);return}cwNavigate(`ordens-servico/${data.id}`)}
async function cwRenderOrdem(id){const target=el('cwOrdensConteudo');target.innerHTML='<p class="muted">Carregando...</p>';const {data:o,error}=await db.from('ordens_servico').select('*,prestadores(nome),ativos(nome,codigo)').eq('id',id).single();if(error){target.innerHTML=`<p class="error">${esc(error.message)}</p>`;return}target.innerHTML=`<article class="panel"><div class="heading"><span><h2>${esc(o.codigo)} · ${esc(o.titulo)}</h2><p>${esc(o.natureza||'Ordem de serviço')}</p></span><button class="secondary" onclick="cwNavigate('ordens-servico')">Voltar</button></div><div class="cw-detail-grid"><div><small>Status</small>${badge(o.status,'status')}</div><div><small>Prioridade</small>${badge(o.prioridade,'priority')}</div><div><small>Local</small><strong>${esc(o.local||'—')}</strong></div><div><small>Previsão</small><strong>${cwDate(o.inicio_previsto,true)}</strong></div><div><small>Prestador</small><strong>${esc(o.prestadores?.nome||'—')}</strong></div><div><small>Ativo</small><strong>${esc(o.ativos?.codigo||'')} ${esc(o.ativos?.nome||'—')}</strong></div><div class="wide"><small>Descrição</small><p>${esc(o.descricao||'—')}</p></div></div>${cwCan('os_concluir')&&!['Concluída','Cancelada'].includes(o.status)?`<hr><form onsubmit="cwConcludeOs(event,${o.id})" class="demand-form"><div class="field wide"><label>Descrição da execução *</label><textarea name="descricao" required></textarea></div><div class="field wide"><label>Observações do executor</label><textarea name="observacoes"></textarea></div><div class="actions"><button class="primary">Concluir OS</button></div></form>`:''}${o.status==='Concluída'&&cwCan('os_aceitar')?`<hr><div class="actions"><button class="primary" onclick="cwAcceptOs(${o.id},true)">Aceitar serviço</button><button class="secondary" onclick="cwAcceptOs(${o.id},false)">Recusar e reabrir</button></div>`:''}</article>`}
async function cwConcludeOs(event,id){event.preventDefault();const f=event.target,b=f.querySelector('button');b.disabled=true;const {data,error}=await db.rpc('cw_concluir_os',{p_os:id,p_descricao:f.descricao.value,p_observacoes:f.observacoes.value||null});b.disabled=false;if(error){toast(error.message);return}if(data?.perguntar_finalizacao&&confirm('Esta foi a última OS em aberto. Deseja finalizar também a solicitação?'))await db.rpc('cw_finalizar_solicitacao_por_os',{p_solicitacao:data.solicitacao_id,p_finalizar:true});await cwRenderOrdem(id);toast('Ordem de serviço concluída.')}
async function cwAcceptOs(id,accept){let reason=null;if(!accept){reason=prompt('Informe o motivo da recusa:');if(!reason?.trim())return}const {error}=await db.rpc('cw_registrar_aceite_os',{p_os:id,p_aceitar:accept,p_observacao:reason,p_avaliacao:null});if(error){toast(error.message);return}await cwRenderOrdem(id);toast(accept?'Serviço aceito.':'OS reaberta para execução.')}

async function cwRenderAtivos(){const target=el('cwAtivosConteudo');const {data,error}=await db.from('ativos').select('id,codigo,nome,categoria,local,garantia_ate,ativo,ativo_pai_id').eq('organizacao_id',currentOrganizationId()).order('nome');if(error){target.innerHTML=`<p class="error">${esc(error.message)}</p>`;return}target.innerHTML=`<article class="panel"><div class="heading"><span><h2>Ativos e Equipamentos</h2><p>${data?.length||0} cadastrados</p></span>${cwCan('ativos_editar')?'<button class="primary" onclick="cwShowAssetForm()">＋ Novo ativo</button>':''}</div><div id="cwAssetForm"></div>${data?.length?`<div class="cw-card-list">${data.map(a=>`<article><span><strong>${esc(a.codigo||'Sem código')} · ${esc(a.nome)}</strong><small>${esc(a.categoria||'Sem categoria')} · ${esc(a.local||'Local não informado')}${a.garantia_ate?' · Garantia até '+cwDate(a.garantia_ate):''}</small></span>${badge(a.ativo?'Ativo':'Inativo','status')}</article>`).join('')}</div>`:'<p class="muted">Nenhum ativo cadastrado.</p>'}</article>`}
function cwShowAssetForm(){el('cwAssetForm').innerHTML=`<form class="demand-form cw-inline-form" onsubmit="cwCreateAsset(event)"><div class="field"><label>Nome *</label><input name="nome" required></div><div class="field"><label>Categoria</label><input name="categoria"></div><div class="field"><label>Local</label><input name="local"></div><div class="field"><label>Fabricante</label><input name="fabricante"></div><div class="field"><label>Modelo</label><input name="modelo"></div><div class="field"><label>Número de série</label><input name="numero_serie"></div><div class="field"><label>Data de aquisição</label><input type="date" name="data_aquisicao"></div><div class="field"><label>Garantia até</label><input type="date" name="garantia_ate"></div><div class="actions"><button class="primary">Cadastrar ativo</button></div></form>`}
async function cwCreateAsset(event){event.preventDefault();const f=event.target,x=Object.fromEntries(new FormData(f)),b=f.querySelector('button');b.disabled=true;const {data:code,error:codeError}=await db.rpc('cw_proximo_codigo',{p_org:currentOrganizationId(),p_entidade:'EQP',p_data:new Date().toISOString().slice(0,10)});if(codeError){b.disabled=false;toast(codeError.message);return}const {error}=await db.from('ativos').insert({...x,organizacao_id:currentOrganizationId(),codigo:code,criado_por:session.user.id,data_aquisicao:x.data_aquisicao||null,garantia_ate:x.garantia_ate||null});b.disabled=false;if(error){toast(error.message);return}toast('Ativo cadastrado.');cwRenderAtivos()}

async function cwRenderPrestadores(){const target=el('cwPrestadoresConteudo');const {data,error}=await db.from('prestadores').select('*').eq('organizacao_id',currentOrganizationId()).order('nome');if(error){target.innerHTML=`<p class="error">${esc(error.message)}</p>`;return}target.innerHTML=`<article class="panel"><div class="heading"><span><h2>Prestadores</h2><p>Equipe própria e terceirizados</p></span>${cwCan('prestadores_editar')?'<button class="primary" onclick="cwShowProviderForm()">＋ Novo prestador</button>':''}</div><div id="cwProviderForm"></div>${data?.length?`<div class="cw-card-list">${data.map(p=>`<article><span><strong>${esc(p.nome)}</strong><small>${p.tipo_vinculo==='proprio'?'Próprio':'Terceirizado'} · ${esc(p.especialidades?.join(', ')||'Sem especialidade')} · ${esc(p.telefone||p.email||'Sem contato')}</small></span>${badge(p.ativo?'Ativo':'Inativo','status')}</article>`).join('')}</div>`:'<p class="muted">Nenhum prestador cadastrado.</p>'}</article>`}
function cwShowProviderForm(){el('cwProviderForm').innerHTML=`<form class="demand-form cw-inline-form" onsubmit="cwCreateProvider(event)"><div class="field"><label>Nome/Razão social *</label><input name="nome" required></div><div class="field"><label>Vínculo *</label><select name="tipo_vinculo"><option value="proprio">Próprio</option><option value="terceirizado">Terceirizado</option></select></div><div class="field"><label>Pessoa</label><select name="tipo_pessoa"><option value="juridica">Jurídica</option><option value="fisica">Física</option></select></div><div class="field"><label>CPF/CNPJ</label><input name="cpf_cnpj"></div><div class="field"><label>E-mail</label><input type="email" name="email"></div><div class="field"><label>Telefone</label><input name="telefone"></div><div class="field wide"><label>Especialidades (separadas por vírgula)</label><input name="especialidades"></div><div class="actions"><button class="primary">Cadastrar prestador</button></div></form>`}
async function cwCreateProvider(event){event.preventDefault();const f=event.target,x=Object.fromEntries(new FormData(f)),b=f.querySelector('button');b.disabled=true;x.especialidades=x.especialidades.split(',').map(v=>v.trim()).filter(Boolean);const {error}=await db.from('prestadores').insert({...x,organizacao_id:currentOrganizationId(),criado_por:session.user.id});b.disabled=false;if(error){toast(error.message);return}toast('Prestador cadastrado.');cwRenderPrestadores()}

async function cwRenderCadastros(){const target=el('cwCadastrosConteudo'),tables=[['tipos_servico','Tipos de serviço'],['naturezas_servico','Naturezas'],['prioridades','Prioridades'],['centros_custo','Centros de custo'],['operacoes','Operações/lojas']];const results=await Promise.all(tables.map(([t])=>db.from(t).select('id,nome,ativo').eq('organizacao_id',currentOrganizationId()).order('nome')));target.innerHTML=`<div class="cw-register-grid">${tables.map(([table,label],i)=>`<article class="panel"><div class="heading"><span><h2>${label}</h2><p>${results[i].data?.length||0} itens</p></span></div><div class="cw-tags">${(results[i].data||[]).map(x=>`<span>${esc(x.nome)}</span>`).join('')||'<p class="muted">Nenhum item.</p>'}</div>${cwCan('configuracoes_editar')?`<form onsubmit="cwAddRegister(event,'${table}')" class="cw-mini-form"><input name="nome" required placeholder="Novo item"><button class="primary">Adicionar</button></form>`:''}</article>`).join('')}</div>`}
async function cwAddRegister(event,table){event.preventDefault();const f=event.target,{error}=await db.from(table).insert({organizacao_id:currentOrganizationId(),nome:f.nome.value.trim()});if(error){toast(error.message);return}cwRenderCadastros()}

function cwManagedRoles(){return isAdmin()?['gestor','auxiliar','tecnico','usuario_padrao']:['auxiliar','tecnico','usuario_padrao']}
function cwRoleOptions(selected='usuario_padrao'){return cwManagedRoles().map(value=>`<option value="${value}" ${value===selected?'selected':''}>${ROLE_LABELS[value]}</option>`).join('')}
let cwOperationOptions=[];
function cwOperationSelect(selected=''){return`<option value="">Nenhuma operação específica</option>${cwOperationOptions.map(item=>`<option value="${item.id}" ${String(item.id)===String(selected)?'selected':''}>${esc(item.nome)}</option>`).join('')}`}
loadUsers=async function(){
  if(!canManage())return toast('Acesso restrito.');
  const [result,operations,links]=await Promise.all([db.from('perfis').select('*').eq('organizacao_id',currentOrganizationId()).order('nome'),db.from('operacoes').select('id,nome').eq('organizacao_id',currentOrganizationId()).eq('ativo',true).order('nome'),db.from('usuario_operacoes').select('usuario_id,operacao_id,principal')]);
  if(result.error||operations.error||links.error){toast(result.error?.message||operations.error?.message||links.error?.message);return}cwOperationOptions=operations.data||[];const operationByUser={};(links.data||[]).forEach(link=>{if(link.principal||!operationByUser[link.usuario_id])operationByUser[link.usuario_id]=link.operacao_id});usersCache=(result.data||[]).map(user=>({...user,operacao_id:operationByUser[user.id]||null}));
  el('usuarios').innerHTML=`<article class="panel"><div class="heading"><span><h2>Novo usuário</h2><p>O convite para definir a senha será enviado por e-mail.</p></span></div><form id="cwManagedCreate" class="demand-form"><div class="field"><label>Nome *</label><input name="nome" required></div><div class="field"><label>E-mail *</label><input type="email" name="email" required></div><div class="field"><label>Operação/loja</label><select name="operacao_id">${cwOperationSelect()}</select></div><div class="field"><label>Perfil</label><select name="papel">${cwRoleOptions()}</select></div><div class="actions"><button class="primary">Enviar convite</button></div></form></article><article class="panel" style="margin-top:22px"><h2>Usuários e acessos</h2><div id="usersList" class="cw-card-list"></div></article><article id="userEditor" class="panel" style="display:none;margin-top:22px"></article>${isAdmin()?'<article class="panel" style="margin-top:22px"><h2>Matriz de permissões</h2><p>Administrador e Gestor são perfis fixos. A matriz abaixo é exclusiva de cada empresa.</p><div id="permissionMatrix"></div></article>':''}`;
  el('usersList').innerHTML=usersCache.map(u=>`<article><span><strong>${esc(u.nome||'Sem nome')}</strong><small>${esc(u.email||'Sem e-mail')} · ${ROLE_LABELS[u.papel]||u.papel} · ${u.ativo?'Ativo':'Bloqueado'}</small></span>${(isAdmin()||!['administrador','gestor'].includes(u.papel))?`<button type="button" class="secondary" data-open-user="${u.id}">Abrir perfil</button>`:''}</article>`).join('')||'<p class="muted">Nenhum usuário cadastrado.</p>';
  el('usersList').querySelectorAll('[data-open-user]').forEach(button=>button.onclick=()=>cwOpenUser(button.dataset.openUser));
  el('cwManagedCreate').onsubmit=async event=>{event.preventDefault();const f=event.target,b=f.querySelector('button');b.disabled=true;try{await managedRequest({...Object.fromEntries(new FormData(f)),action:'create',organizacao_id:currentOrganizationId(),redirect_to:location.origin+location.pathname+'#/conta'});toast('Convite enviado para o e-mail do usuário.');await loadUsers()}catch(error){toast(error.message)}finally{b.disabled=false}};
  if(isAdmin())await loadPermissionMatrix();
};
function cwOpenUser(id){const u=usersCache.find(item=>item.id===id);if(!u){toast('Usuário não encontrado. Atualize a lista e tente novamente.');return}const target=el('userEditor'),locked=!isAdmin()&&['administrador','gestor'].includes(u.papel);target.innerHTML=`<h2>Perfil do usuário</h2><form id="cwManagedEdit" class="demand-form"><div class="field"><label>Nome *</label><input name="nome" required value="${esc(u.nome||'')}"></div><div class="field"><label>E-mail *</label><input name="email" type="email" required value="${esc(u.email||'')}"></div><div class="field"><label>Operação/loja</label><select name="operacao_id">${cwOperationSelect(u.operacao_id)}</select></div><div class="field"><label>Perfil</label><select name="papel" ${locked?'disabled':''}>${u.papel==='administrador'?'<option value="administrador">Administrador</option>':cwRoleOptions(u.papel)}</select></div><div class="field"><label>Acesso</label><select name="ativo"><option value="true" ${u.ativo?'selected':''}>Ativo</option><option value="false" ${!u.ativo?'selected':''}>Bloqueado</option></select></div><div class="actions"><button class="primary">Salvar</button><button type="button" class="secondary" id="cwResetPassword">Enviar redefinição de senha</button></div></form>`;target.style.display='block';target.scrollIntoView({behavior:'smooth',block:'start'});el('cwResetPassword').onclick=()=>sendPasswordReset(u.email);const f=el('cwManagedEdit');f.onsubmit=async event=>{event.preventDefault();const b=f.querySelector('button');b.disabled=true;try{await managedRequest({...Object.fromEntries(new FormData(f)),papel:f.papel.value,action:'update',user_id:id,ativo:f.ativo.value==='true',aprovacao:'aprovado'});toast('Usuário atualizado.');await loadUsers()}catch(error){toast(error.message)}finally{b.disabled=false}}}
loadPermissionMatrix=async function(){
  if(!isAdmin())return;const {data,error}=await db.from('permissoes_perfis').select('*').eq('organizacao_id',currentOrganizationId());if(error)return toast(error.message);const map={};(data||[]).forEach(x=>map[x.papel+':'+x.acao]=x.permitido);const roles=['auxiliar','tecnico','usuario_padrao'];
  el('permissionMatrix').innerHTML=`<div class="cw-table-wrap"><table class="table permission-table"><thead><tr><th>Ação</th>${roles.map(r=>`<th>${ROLE_LABELS[r]}</th>`).join('')}</tr></thead><tbody>${Object.entries(CWV2_PERMISSION_LABELS).map(([action,label])=>`<tr><td>${label}</td>${roles.map(r=>`<td><input type="checkbox" aria-label="${esc(label+' — '+ROLE_LABELS[r])}" ${map[r+':'+action]?'checked':''} onchange="savePermission('${r}','${action}',this.checked)"></td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
};
savePermission=async function(papel,acao,permitido){if(!isAdmin())return;const {error}=await db.from('permissoes_perfis').upsert({organizacao_id:currentOrganizationId(),papel,acao,permitido,atualizado_em:new Date().toISOString()});toast(error?error.message:'Permissão atualizada.');if(error)await loadPermissionMatrix()};

let cwGalleryItems=[],cwGalleryIndex=0;
async function cwLoadGallery(demandId,targetId){const target=el(targetId);target.innerHTML='<p class="muted">Carregando miniaturas...</p>';const {data,error}=await db.from('anexos_demandas').select('*').eq('demanda_id',demandId).order('criado_em',{ascending:false}).range(0,23);if(error||!data?.length){target.innerHTML='<p class="muted">Nenhum arquivo.</p>';return}const cards=await Promise.all(data.map(async(item,index)=>{let thumb='';const caption=item.descricao?.trim();if(item.tipo_arquivo?.startsWith('image/')){const {data:signed}=await db.storage.from('cw-anexos').createSignedUrl(item.storage_path,300,{transform:{width:360,height:240,resize:'cover',quality:60}});thumb=`<img loading="lazy" src="${signed?.signedUrl||''}" alt="${esc(caption||'Imagem da solicitação')}">`}else if(item.tipo_arquivo?.startsWith('video/'))thumb='<span class="cw-file-icon">▶</span>';else thumb='<span class="cw-file-icon">▤</span>';return`<button class="cw-thumb" onclick="cwOpenGallery(${demandId},${index})">${thumb}${caption?`<strong>${esc(caption)}</strong>`:''}</button>`}));target.innerHTML=cards.join('');target.dataset.demandId=demandId;target._items=data}
function cwBytes(value){const n=Number(value)||0;if(n<1024)return n+' B';if(n<1048576)return(n/1024).toFixed(1)+' KB';return(n/1048576).toFixed(1)+' MB'}
async function cwOpenGallery(demandId,index){const {data,error}=await db.from('anexos_demandas').select('*').eq('demanda_id',demandId).order('criado_em',{ascending:false}).range(0,99);if(error)return toast(error.message);cwGalleryItems=data||[];cwGalleryIndex=index;await cwRenderGalleryModal()}
async function cwRenderGalleryModal(){const item=cwGalleryItems[cwGalleryIndex];if(!item)return;el('mediaModal').style.display='flex';el('mediaContent').innerHTML='<p style="color:white">Carregando arquivo...</p>';const {data,error}=await db.storage.from('cw-anexos').createSignedUrl(item.storage_path,300);if(error)return;const url=data.signedUrl,caption=item.descricao?.trim(),content=item.tipo_arquivo.startsWith('image/')?`<img src="${url}" alt="${esc(caption||'Imagem da solicitação')}">`:item.tipo_arquivo.startsWith('video/')?`<video src="${url}" controls autoplay preload="metadata"></video>`:`<a class="primary" href="${url}" target="_blank" rel="noopener">Baixar arquivo</a>`;el('mediaContent').innerHTML=`<div class="cw-modal-media">${content}<div class="cw-modal-caption"><button ${cwGalleryIndex===0?'disabled':''} onclick="cwGalleryMove(-1)">←</button><span>${cwGalleryIndex+1}/${cwGalleryItems.length}${caption?' · '+esc(caption):''}</span><button ${cwGalleryIndex===cwGalleryItems.length-1?'disabled':''} onclick="cwGalleryMove(1)">→</button></div></div>`}
function cwGalleryMove(step){cwGalleryIndex+=step;cwRenderGalleryModal()}

loadGallery=async function(id,target){await cwLoadGallery(id,target)};
const cwEnterAppBase=enterApp;
enterApp=async function(current){const result=await cwEnterAppBase(current);if(profile?.ativo&&profile?.aprovacao==='aprovado'){el('toggleAuth').style.display='none';signupMode=false;await cwRenderRoute()}return result};
const cwEnterpriseChange=el('enterpriseSelect').onchange;
el('enterpriseSelect').onchange=async function(event){await cwEnterpriseChange.call(this,event);await cwRenderRoute()};
if(!location.hash)history.replaceState(null,'',cwUrl('dashboard'));
