import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const wait=()=>new Promise(resolve=>setTimeout(resolve,0));
const empty=()=>({data:[],error:null,count:0});

function query(table){
  const chain={
    select(){return chain},order(){return chain},eq(){return chain},range(){return chain},gte(){return chain},lte(){return chain},
    insert(){return chain},update(){return chain},upsert(){return chain},delete(){return chain},
    then(resolve){return Promise.resolve(empty()).then(resolve)},
    async single(){
      if(table==='demandas')return{data:{id:123,titulo:'Teste',tipo_demanda:'corretiva',status:'Registrado',prioridade:'Média',local:'Local',criado_em:new Date().toISOString()},error:null};
      if(table==='ordens_servico')return{data:{id:123,codigo:'OS-123',titulo:'Teste',status:'Aberta',prioridade:'Média',local:'Local'},error:null};
      return{data:null,error:null};
    },
    async maybeSingle(){return{data:null,error:null}}
  };
  return chain;
}

const client={
  auth:{
    onAuthStateChange(){},getSession:async()=>({data:{session:null},error:null}),signOut:async()=>({error:null}),
    signInWithPassword:async()=>({error:null}),resetPasswordForEmail:async()=>({error:null}),updateUser:async()=>({error:null})
  },
  from:query,
  rpc:async()=>empty(),
  functions:{invoke:async()=>empty()},
  storage:{from:()=>({createSignedUrl:async()=>({data:{signedUrl:''},error:null}),upload:async()=>({error:null}),remove:async()=>({error:null})})}
};

const dom=new JSDOM(read('index.html').replace(/<script[\s\S]*?<\/script>/g,''),{
  runScripts:'dangerously',url:'https://example.test/'
});
const w=dom.window;
w.supabase={createClient:()=>client};
w.HTMLElement.prototype.scrollIntoView=()=>{};
w.confirm=()=>false;
w.prompt=()=>null;

const listenerCounts={};
const nativeAdd=w.addEventListener.bind(w);
w.addEventListener=(type,listener,options)=>{
  listenerCounts[type]=(listenerCounts[type]||0)+1;
  return nativeAdd(type,listener,options);
};

for(const path of ['app.js','multiempresa.js']){
  const script=w.document.createElement('script');script.textContent=read(path);w.document.body.appendChild(script);
}
const legacyCalls=[];
const legacyShow=w.show;
w.show=name=>{legacyCalls.push(name);return legacyShow(name)};
{
  const script=w.document.createElement('script');script.textContent=read('arquitetura-v2.js');w.document.body.appendChild(script);
}
await wait();

const approve=()=>w.eval("profile={id:'user',papel:'administrador',ativo:true,aprovacao:'aprovado',organizacao_id:'org'};session={user:{id:'user',email:'test@example.test'}}");
const pending=()=>w.eval("profile={id:'user',papel:'usuario_padrao',ativo:true,aprovacao:'pendente',organizacao_id:'org'};session={user:{id:'user',email:'test@example.test'}}");
const resetHash=hash=>w.history.replaceState(null,'','/'+hash);

assert.equal(w.location.hash,'#/dashboard','1. rota vazia resulta em dashboard');

w.show('demandas');
assert.equal(w.location.hash,'#/solicitacoes','2. show(demandas) direciona para solicitacoes');
w.show('nova');
assert.equal(w.location.hash,'#/solicitacoes/nova','3. show(nova) direciona para solicitacoes/nova');
w.show('minhaConta');
assert.equal(w.location.hash,'#/conta','4. show(minhaConta) direciona para conta');
w.show('organizacao');
assert.equal(w.location.hash,'#/empresa','5. show(organizacao) direciona para empresa');

approve();
resetHash('#/rota-inexistente');
await w.cwRenderRoute();
assert.equal(w.location.hash,'#/dashboard','6. rota desconhecida direciona para dashboard');

resetHash('#/solicitacoes/123');
await w.cwRenderRoute();
assert.ok(w.document.querySelector('#sidebar [data-route="solicitacoes"]').classList.contains('active'),'7. detalhe de solicitação mantém menu ativo');
resetHash('#/ordens-servico/123');
await w.cwRenderRoute();
assert.ok(w.document.querySelector('#sidebar [data-route="ordens-servico"]').classList.contains('active'),'8. detalhe de OS mantém menu ativo');

const params=new w.URLSearchParams('status=Aberta&pagina=3');
w.cwNavigate('ordens-servico',params);
assert.equal(w.location.hash,'#/ordens-servico?status=Aberta&pagina=3','9. parâmetros de consulta são preservados');
w.cwSetRouteFilter('status','Concluída');
assert.equal(w.location.hash,'#/ordens-servico?status=Conclu%C3%ADda','10. alteração de filtro remove pagina');

pending();
resetHash('#/ativos');
const before=w.document.querySelector('.view.active')?.id;
await w.cwRenderRoute();
assert.equal(w.document.querySelector('.view.active')?.id,before,'12. perfil não aprovado não renderiza rota privada');

approve();
legacyCalls.length=0;
resetHash('#/dashboard');
await w.cwRenderRoute();
assert.ok(legacyCalls.includes('dashboard'),'13. dashboard continua usando cwLegacyShow');
legacyCalls.length=0;
resetHash('#/solicitacoes/nova');
await w.cwRenderRoute();
assert.ok(legacyCalls.includes('nova'),'14. solicitacoes/nova continua usando cwLegacyShow');

assert.equal(listenerCounts.hashchange,1,'15. somente um listener hashchange é registrado');

let sameHashRenders=0;
const originalRender=w.cwRenderRoute;
w.cwRenderRoute=()=>{sameHashRenders++};
resetHash('#/conta');
w.cwNavigate('conta');
assert.equal(sameHashRenders,1,'11. mesmo hash solicita nova renderização');
w.cwRenderRoute=originalRender;

console.log('PASS: 15 cenários de caracterização da navegação.');
w.close();
