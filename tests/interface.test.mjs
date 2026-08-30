import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const org='10000000-0000-0000-0000-000000000001';
let actor={id:'user',organizacao_id:org,nome:'Teste',email:'test@example.test',papel:'administrador',ativo:true,aprovacao:'aprovado'};
const companies=[{id:org,nome:'Empresa A'},{id:'10000000-0000-0000-0000-000000000002',nome:'Empresa B'}];
const calls=[];
const client={
 auth:{onAuthStateChange(){},getSession:async()=>({data:{session:null}}),signOut:async()=>({error:null})},
 from(table){const filters=[];const chain={select(){return chain},order(){return chain},eq(k,v){filters.push([k,v]);return chain},
   then(resolve){calls.push(table);let data=table==='perfis'?[actor]:table==='organizacoes'?companies:table==='permissoes_perfis'?[{acao:'visualizar_todas',permitido:true},{acao:'gerenciar_usuarios',permitido:actor.papel==='gestor_manutencao'}]:[];
     if(table==='permissoes_perfis')data=data.map(r=>({...r,organizacao_id:org,papel:actor.papel}));data=data.filter(r=>filters.every(([k,v])=>r[k]===v));return Promise.resolve({data,error:null}).then(resolve)},
   async single(){return{data:actor,error:null}},async maybeSingle(){return{data:actor,error:null}}};return chain;},
 rpc:async()=>({data:companies,error:null}),
};
const dom=new JSDOM(read('index.html').replace(/<script[\s\S]*?<\/script>/g,''),{runScripts:'dangerously',url:'https://example.test'});
const w=dom.window;w.supabase={createClient:()=>client};w.HTMLElement.prototype.scrollIntoView=()=>{};
for(const path of ['app.js','multiempresa.js']){const script=w.document.createElement('script');script.textContent=read(path);w.document.body.appendChild(script)}
await new Promise(r=>setTimeout(r,10));
assert.equal(w.document.querySelector('.shell').style.display,'none');
await w.document.getElementById('toggleAuth').onclick();
assert.equal(w.document.getElementById('signupEnterprise').options.length,3);
const session={user:{id:'user',email:'test@example.test'}};
await w.enterApp(session);
assert.equal(w.document.getElementById('enterpriseContext').style.display,'');
assert.equal(w.document.querySelector('.shell').style.display,'');
await w.loadUsers();
assert.ok(w.document.getElementById('matrixPanel'));
assert.equal(w.document.querySelector('#managedCreate select').options[0].textContent,'Empreendimento');
actor={...actor,papel:'gestor_manutencao'};await w.enterApp(session);await w.loadUsers();
assert.equal(w.document.getElementById('matrixPanel').style.display,'none');
 w.openUserEditor('user');
 assert.equal(w.document.getElementById('managedEdit').elements.aprovacao.value,'aprovado');
assert.equal(w.document.getElementById('enterpriseContext').style.display,'none');
actor={...actor,papel:'empreendimento'};await w.enterApp(session);await w.loadUsers();
assert.equal(w.document.getElementById('matrixPanel').style.display,'block');
actor={...actor,papel:'lojista',ativo:false,aprovacao:'pendente'};calls.length=0;await w.enterApp(session);
assert.equal(w.document.querySelector('.shell').style.display,'none');
assert.equal(w.document.getElementById('approvalScreen').classList.contains('hidden'),false);
assert.ok(w.document.getElementById('approvalMessage').textContent.includes('aguardando'));
assert.ok(!calls.includes('demandas'));
actor={...actor,aprovacao:'rejeitado'};await w.enterApp(session);
assert.ok(w.document.getElementById('approvalMessage').textContent.includes('não foi aprovado'));
await w.enterApp(null);assert.equal(w.document.getElementById('authScreen').classList.contains('hidden'),false);
console.log('PASS: cadastro com empreendimento, contextos, matrizes, perfis e telas pendente/rejeitado.');
w.close();
