/* Multiempreendimento: controles são conveniência; o banco valida cada operação. */
let enterpriseOptions=[],authRevision=0;
PERMISSION_LABELS.gerenciar_empreendimento='Editar dados do empreendimento';
const managedRoles=()=>isAdmin()?['empreendimento','gestor_manutencao','tecnico','lojista']:['gestor_manutencao','tecnico','lojista'];
const roleOptions=(selected='lojista')=>managedRoles().map(r=>`<option value="${r}" ${r===selected?'selected':''}>${ROLE_LABELS[r]}</option>`).join('');

el('nameField').insertAdjacentHTML('afterend','<label id="signupEnterpriseField" style="display:none">Empreendimento <select id="signupEnterprise"><option value="">Selecione o empreendimento</option></select></label>');
el('sidebar').querySelector('nav').insertAdjacentHTML('beforebegin','<div id="enterpriseContext" style="display:none;padding:12px"><label for="enterpriseSelect">Empreendimento</label><select id="enterpriseSelect" style="width:100%"></select><button id="manageEnterprises" type="button" class="link">Cadastrar empreendimento</button></div>');
el('authScreen').insertAdjacentHTML('afterend','<div id="approvalScreen" class="auth-screen hidden"><div class="auth-card"><h1>Acesso ao empreendimento</h1><p id="approvalMessage"></p><button id="checkApproval" class="primary" type="button">Verificar aprovação</button><button id="pendingLogout" class="link" type="button">Sair</button></div></div>');
el('organizacao').insertAdjacentHTML('beforebegin','<section id="enterprises" class="view"><article class="panel"><h2>Cadastrar empreendimento</h2><p>Somente o Administrador da plataforma pode cadastrar empresas.</p><form id="enterpriseForm" class="demand-form"><div class="field"><label>Nome *</label><input name="nome" required maxlength="180"></div><div class="actions"><button class="primary">Cadastrar</button></div></form><p id="enterpriseMessage" role="status"></p></article></section>');
el('organizationNav').textContent='▣ Dados do empreendimento';

function approvalView(message){
  demands=[];permissions={};reportCache=null;usersCache=[];
  el('authScreen').classList.add('hidden');el('approvalScreen').classList.remove('hidden');
  el('approvalMessage').textContent=message;
  document.querySelector('.shell').style.display='none';
}
async function refreshEnterpriseOptions(){
  const {data,error}=isAdmin()?await db.rpc('cw_listar_organizacoes'):await db.from('organizacoes').select('id,nome').order('nome');
  if(error)throw error;
  enterpriseOptions=data||[];
  if(isAdmin()){
    if(!enterpriseOptions.some(o=>o.id===activeOrgId))activeOrgId=profile.organizacao_id||enterpriseOptions[0]?.id;
    el('enterpriseSelect').innerHTML=enterpriseOptions.map(o=>`<option value="${o.id}">${esc(o.nome)}</option>`).join('');
    el('enterpriseSelect').value=activeOrgId||'';
  }
  el('enterpriseContext').style.display=isAdmin()?'':'none';
}
loadProfile=async function(){
  const {data,error}=await db.from('perfis').select('*').eq('id',session.user.id).single();
  if(error)throw error;
  profile=data;permissions={};
  if(data.aprovacao!=='aprovado'||!data.ativo)return data;
  if(!canManageCompany()){
    const result=await db.from('permissoes_perfis').select('acao,permitido').eq('organizacao_id',data.organizacao_id).eq('papel',data.papel);
    if(result.error)throw result.error;
    (result.data||[]).forEach(x=>permissions[x.acao]=x.permitido);
  }
  await refreshEnterpriseOptions();
  const name=data.nome||session.user.email;
  el('userName').textContent=name;el('userRole').textContent=ROLE_LABELS[data.papel]||'Usuário';
  el('userInitials').textContent=name.split(' ').map(x=>x[0]).slice(0,2).join('').toUpperCase();
  applyRoleVisibility();
  return data;
};
loadData=async function(){
  if(!profile?.ativo||profile?.aprovacao!=='aprovado')return;
  const {data,error}=await db.from('demandas').select('*').eq('organizacao_id',currentOrganizationId()).order('criado_em',{ascending:false});
  if(error)throw error;
  demands=(data||[]).map(d=>({...d,code:d.codigo,type:d.tipo_demanda||'corretiva',scheduledAt:d.agendamento_em,company:d.empresa_prestador,serviceType:d.tipo_servico,additionalNotes:d.observacoes_adicionais,title:d.titulo,category:d.categoria,location:d.local,priority:d.prioridade,deadline:d.prazo,responsible:d.responsavel,next:d.proxima_acao,notes:d.observacoes,createdAt:d.criado_em}));
  render();
};
enterApp=async function(current){
  const revision=++authRevision;session=current;
  document.querySelector('.shell').style.display='none';
  if(!current){profile=null;permissions={};demands=[];usersCache=[];reportCache=null;activeOrgId=null;el('approvalScreen').classList.add('hidden');el('authScreen').classList.remove('hidden');return}
  try{
    await loadProfile();if(revision!==authRevision)return;
    if(profile.aprovacao==='pendente'){approvalView('Seu cadastro está aguardando aprovação. Você poderá acessar as demandas quando o empreendimento liberar seu acesso.');return}
    if(profile.aprovacao==='rejeitado'){approvalView('Seu cadastro não foi aprovado. Entre em contato com o empreendimento.');return}
    if(!profile.ativo){approvalView('Seu acesso está bloqueado. Entre em contato com o empreendimento.');return}
    await loadData();if(revision!==authRevision)return;
    el('authScreen').classList.add('hidden');el('approvalScreen').classList.add('hidden');document.querySelector('.shell').style.display='';
    el('authMessage').textContent='';
    if(passwordSetupMode)setTimeout(openPasswordSetup,0);
  }catch(error){if(revision===authRevision){el('authScreen').classList.remove('hidden');el('authMessage').textContent='Não foi possível carregar o acesso: '+error.message}}
};
el('toggleAuth').onclick=async()=>{
  signupMode=!signupMode;
  el('nameField').classList.toggle('visible',signupMode);el('authName').required=signupMode;
  el('signupEnterpriseField').style.display=signupMode?'':'none';el('signupEnterprise').required=signupMode;
  el('toggleAuth').textContent=signupMode?'Já tenho cadastro':'Ainda não tenho cadastro';
  document.querySelector('.auth-submit').textContent=signupMode?'Criar conta':'Entrar';el('authMessage').textContent='';
  if(signupMode){const {data,error}=await db.rpc('lista_empreendimentos_cadastro');
    if(error){el('authMessage').textContent='Não foi possível listar os empreendimentos. Tente novamente.';return}
    el('signupEnterprise').innerHTML='<option value="">Selecione o empreendimento</option>'+(data||[]).map(o=>`<option value="${o.id}">${esc(o.nome)}</option>`).join('');
  }
};
el('authForm').onsubmit=async e=>{
  e.preventDefault();const button=document.querySelector('.auth-submit');if(button.disabled)return;
  button.disabled=true;el('authMessage').textContent='Aguarde...';
  try{
    const credentials={email:el('authEmail').value.trim(),password:el('authPassword').value};
    if(signupMode&&!el('signupEnterprise').value)throw new Error('Selecione o empreendimento.');
    const {data,error}=signupMode?await db.auth.signUp({...credentials,options:{data:{nome:el('authName').value.trim(),organizacao_id:el('signupEnterprise').value}}}):await db.auth.signInWithPassword(credentials);
    if(error)throw error;
    el('authPassword').value='';
    if(data.session)await enterApp(data.session);
    else el('authMessage').textContent='Confirme seu e-mail. Depois, aguarde a aprovação do empreendimento.';
  }catch(error){el('authMessage').textContent=error.message||'Não foi possível entrar. Tente novamente.'}
  finally{button.disabled=false}
};
el('pendingLogout').onclick=()=>db.auth.signOut();
el('checkApproval').onclick=async()=>{const b=el('checkApproval');b.disabled=true;try{await enterApp(session)}finally{b.disabled=false}};
el('enterpriseSelect').onchange=async()=>{
  activeOrgId=el('enterpriseSelect').value;demands=[];reportCache=null;usersCache=[];editingId=null;
  el('userEditor')?.style.setProperty('display','none');el('detailsContent').innerHTML='';el('detailsAttachments').innerHTML='';
  try{await loadData();show('dashboard')}catch(error){toast(error.message)}
};
el('manageEnterprises').onclick=()=>{
  if(!isAdmin())return;
  document.querySelectorAll('.view').forEach(x=>x.classList.remove('active'));el('enterprises').classList.add('active');
  el('title').textContent='Empreendimentos';el('subtitle').textContent='Administração da plataforma';el('sidebar').classList.remove('open');
};
el('enterpriseForm').onsubmit=async e=>{
  e.preventDefault();if(!isAdmin())return;const button=e.target.querySelector('button');button.disabled=true;
  try{const {data,error}=await db.rpc('cw_criar_organizacao',{p_nome:e.target.elements.nome.value.trim()});if(error)throw error;
    activeOrgId=data;await refreshEnterpriseOptions();e.target.reset();el('enterpriseMessage').textContent='Empreendimento criado. Em Usuários, cadastre ou aprove o responsável com perfil Empreendimento.';
  }catch(error){el('enterpriseMessage').textContent=error.message}finally{button.disabled=false}
};

loadUsers=async function(){
  if(!canManage())return;
  const result=await db.from('perfis').select('*').eq('organizacao_id',currentOrganizationId()).order('nome');
  if(result.error){toast(result.error.message);return}
  usersCache=result.data||[];
  el('usuarios').innerHTML=`<article class="panel"><h2>Novo usuário</h2><p>Empreendimento: ${esc(enterpriseOptions.find(o=>o.id===currentOrganizationId())?.nome||'')}</p><form id="managedCreate" class="demand-form"><div class="field"><label>Nome *</label><input name="nome" required></div><div class="field"><label>E-mail *</label><input type="email" name="email" required></div><div class="field"><label>Senha provisória *</label><input type="password" name="password" minlength="8" required></div><div class="field"><label>Loja/local</label><input name="loja"></div><div class="field"><label>Perfil</label><select name="papel">${roleOptions()}</select></div><div class="actions"><button class="primary">Cadastrar usuário</button></div></form></article><article class="panel" style="margin-top:22px"><h2>Usuários e aprovações</h2><div id="usersList"></div></article><article id="userEditor" class="panel" style="display:none;margin-top:22px"></article><article id="matrixPanel" class="panel" style="margin-top:22px;display:${canManageCompany()?'block':'none'}"><h2>Matriz de permissões</h2><p>Administrador e Empreendimento têm acesso fixo. As alterações abaixo valem somente para esta empresa.</p><div id="permissionMatrix"></div></article>`;
  usersCache.sort((a,b)=>(a.aprovacao==='pendente'?0:1)-(b.aprovacao==='pendente'?0:1));
  el('usersList').innerHTML=usersCache.map(u=>`<article style="display:flex;justify-content:space-between;padding:16px 0;border-bottom:1px solid #ddd"><span><strong>${esc(u.nome)}</strong><small style="display:block">${esc(u.email)} • ${ROLE_LABELS[u.papel]} • ${u.aprovacao==='pendente'?'Aguardando aprovação':u.aprovacao==='rejeitado'?'Rejeitado':u.ativo?'Ativo':'Bloqueado'}</small></span>${(isAdmin()||!['administrador','empreendimento'].includes(u.papel))?`<button class="edit-button" onclick="openUserEditor('${u.id}')">Abrir perfil</button>`:''}</article>`).join('')||'<p>Nenhum usuário cadastrado.</p>';
  el('managedCreate').onsubmit=async e=>{e.preventDefault();const f=e.target,b=f.querySelector('button');b.disabled=true;
    try{await managedRequest({...Object.fromEntries(new FormData(f)),action:'create',organizacao_id:currentOrganizationId()});await loadUsers();toast('Usuário cadastrado e aprovado.')}catch(error){toast(error.message)}finally{b.disabled=false}};
  if(canManageCompany())await loadPermissionMatrix();
};
async function managedRequest(body){
  const {data,error}=await db.functions.invoke('admin-users',{body});
  if(error||data?.error){let message=data?.error||error?.message;try{const detail=await error?.context?.json();message=detail?.error||message}catch{}throw new Error(message||'Não foi possível salvar')}
  return data;
}
openUserEditor=function(id){
  const u=usersCache.find(x=>x.id===id);if(!u)return;
  const roles=u.papel==='administrador'?'<option value="administrador">Administrador</option>':roleOptions(u.papel);
  el('userEditor').innerHTML=`<h2>Perfil do usuário</h2><form id="managedEdit" class="demand-form"><div class="field"><label>Nome *</label><input name="nome" required value="${esc(u.nome)}"></div><div class="field"><label>E-mail *</label><input name="email" type="email" required value="${esc(u.email)}"></div><div class="field"><label>Loja/local</label><input name="loja" value="${esc(u.loja)}"></div><div class="field"><label>Perfil</label><select name="papel">${roles}</select></div><div class="field"><label>Aprovação</label><select name="aprovacao"><option value="pendente">Aguardando aprovação</option><option value="aprovado">Aprovado</option><option value="rejeitado">Rejeitado</option></select></div><div class="field"><label>Acesso após aprovação</label><select name="ativo"><option value="true">Ativo</option><option value="false">Bloqueado</option></select></div><div class="actions"><button class="primary">Salvar alterações</button><button id="managedReset" type="button" class="secondary">Enviar redefinição de senha</button></div></form>`;
  const f=el('managedEdit');f.elements.aprovacao.value=u.aprovacao;f.elements.ativo.value=String(u.aprovacao==='pendente'||u.ativo);
  el('userEditor').style.display='block';el('userEditor').scrollIntoView({behavior:'smooth'});
  el('managedReset').onclick=()=>sendPasswordReset(u.email);
  f.onsubmit=async e=>{e.preventDefault();const b=f.querySelector('button');b.disabled=true;
    try{await managedRequest({...Object.fromEntries(new FormData(f)),action:'update',user_id:id,ativo:f.elements.ativo.value==='true'});await loadUsers();toast('Usuário atualizado.')}catch(error){toast(error.message)}finally{b.disabled=false}};
};
loadPermissionMatrix=async function(){
  if(!canManageCompany())return;
  const {data,error}=await db.from('permissoes_perfis').select('*').eq('organizacao_id',currentOrganizationId());if(error){toast(error.message);return}
  const map={};(data||[]).forEach(x=>map[x.papel+':'+x.acao]=x.permitido);const roles=['gestor_manutencao','tecnico','lojista'];
  el('permissionMatrix').innerHTML=`<div style="overflow:auto"><table class="table"><thead><tr><th>Ação</th>${roles.map(r=>`<th>${ROLE_LABELS[r]}</th>`).join('')}</tr></thead><tbody>${Object.entries(PERMISSION_LABELS).filter(([action])=>action!=='gerenciar_permissoes').map(([action,label])=>`<tr><td>${label}</td>${roles.map(r=>`<td><input type="checkbox" aria-label="${esc(label+' — '+ROLE_LABELS[r])}" ${map[r+':'+action]?'checked':''} onchange="savePermission('${r}','${action}',this.checked)"></td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
};
savePermission=async function(papel,acao,permitido){
  if(!canManageCompany())return;
  const {error}=await db.from('permissoes_perfis').upsert({organizacao_id:currentOrganizationId(),papel,acao,permitido,atualizado_em:new Date().toISOString()});
  toast(error?'Não foi possível salvar a permissão.':'Permissão atualizada.');if(error)await loadPermissionMatrix();
};

// Não aguardar chamadas Supabase dentro do callback de autenticação.
db.auth.onAuthStateChange((event,current)=>{if(event==='TOKEN_REFRESHED'){session=current;return}if(event==='PASSWORD_RECOVERY')passwordSetupMode=true;setTimeout(()=>enterApp(current),0)});
db.auth.getSession().then(({data,error})=>{if(error){el('authMessage').textContent=error.message;return}return enterApp(data.session)});
