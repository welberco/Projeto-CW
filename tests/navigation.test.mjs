import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const wait=()=>new Promise(resolve=>setTimeout(resolve,0));
const empty=()=>({data:[],error:null,count:0});
const appSource=read('app.js');
const routerSource=read('arquitetura-v2.js');

function query(table){
  const chain={
    select(){return chain},order(){return chain},eq(){return chain},range(){return chain},gte(){return chain},lte(){return chain},
    insert(){return chain},update(){return chain},upsert(){return chain},delete(){return chain},
    then(resolve){return Promise.resolve(empty()).then(resolve)},
    async single(){
      if(table==='demandas')return{data:{id:123,titulo:'Teste',tipo_demanda:'corretiva',status:'Registrado',prioridade:'Média',local:'Local',criado_em:new Date().toISOString()},error:null};
      if(table==='ordens_servico')return{data:{id:123,codigo:'OS-123',titulo:'Teste',status:'Aberta',prioridade:'Média',local:'Local'},error:null};
      if(table==='organizacoes')return{data:{id:'org',nome:'Empresa de teste'},error:null};
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

for(const path of ['app.js','multiempresa.js','arquitetura-v2.js']){
  const script=w.document.createElement('script');script.textContent=read(path);w.document.body.appendChild(script);
}
await wait();

const router=w.eval('CWRouter');
const routes=w.eval('CW_ROUTES');
const scopes=w.eval('CW_SCOPES');
const modules=w.eval('CW_MODULES');
const aliases=w.eval('CW_LEGACY_ROUTE_ALIASES');
const menu=w.eval('CWV2_MENU');
const approve=()=>w.eval("profile={id:'user',papel:'administrador',ativo:true,aprovacao:'aprovado',organizacao_id:'org'};session={user:{id:'user',email:'test@example.test'}}");
const pending=()=>w.eval("profile={id:'user',papel:'usuario_padrao',ativo:true,aprovacao:'pendente',organizacao_id:'org'};session={user:{id:'user',email:'test@example.test'}}");
const resetHash=hash=>w.history.replaceState(null,'','/'+hash);
const activeMenuRoutes=()=>Array.from(w.document.querySelectorAll('#sidebar [data-route].active'),node=>node.dataset.route);
async function assertFinalRoute(path,view,nav=path){
  approve();
  resetHash('#/'+path);
  const route=router.resolve(path);
  assert.ok(route);
  assert.equal(router.activeNav(route),nav);
  await router.render();
  assert.ok(w.document.getElementById(view).classList.contains('active'));
  assert.deepEqual(activeMenuRoutes(),[nav]);
}
let passed=0;
async function test(label,run){await run();passed++;void label}

await test('1. rota vazia resulta em dashboard',async()=>assert.equal(w.location.hash,'#/dashboard'));
await test('2. show demandas direciona para solicitacoes',async()=>{w.show('demandas');assert.equal(w.location.hash,'#/solicitacoes')});
await test('3. show nova direciona para solicitacoes/nova',async()=>{w.show('nova');assert.equal(w.location.hash,'#/solicitacoes/nova')});
await test('4. show minhaConta direciona para conta',async()=>{w.show('minhaConta');assert.equal(w.location.hash,'#/conta')});
await test('5. show organizacao direciona para empresa',async()=>{w.show('organizacao');assert.equal(w.location.hash,'#/empresa')});
await test('6. rota desconhecida direciona para dashboard',async()=>{approve();resetHash('#/rota-inexistente');await w.cwRenderRoute();assert.equal(w.location.hash,'#/dashboard')});
await test('7. detalhe de solicitação mantém menu ativo',async()=>{resetHash('#/solicitacoes/123');await w.cwRenderRoute();assert.ok(w.document.querySelector('#sidebar [data-route="solicitacoes"]').classList.contains('active'))});
await test('8. detalhe de OS mantém menu ativo',async()=>{resetHash('#/ordens-servico/123');await w.cwRenderRoute();assert.ok(w.document.querySelector('#sidebar [data-route="ordens-servico"]').classList.contains('active'))});
await test('9. parâmetros de consulta são preservados',async()=>{const params=new w.URLSearchParams('status=Aberta&pagina=3');w.cwNavigate('ordens-servico',params);assert.equal(w.location.hash,'#/ordens-servico?status=Aberta&pagina=3')});
await test('10. alteração de filtro remove pagina',async()=>{w.cwSetRouteFilter('status','Concluída');assert.equal(w.location.hash,'#/ordens-servico?status=Conclu%C3%ADda')});
await test('11. mesmo hash solicita nova renderização',async()=>{let calls=0;const original=router.render;router.render=()=>{calls++};resetHash('#/conta');w.cwNavigate('conta');router.render=original;assert.equal(calls,1)});
await test('12. perfil não aprovado não renderiza rota privada',async()=>{pending();resetHash('#/ativos');const before=w.document.querySelector('.view.active')?.id;await w.cwRenderRoute();assert.equal(w.document.querySelector('.view.active')?.id,before)});
await test('13. dashboard continua usando renderizador legado',async()=>{approve();resetHash('#/dashboard');await w.cwRenderRoute();assert.ok(w.document.getElementById('dashboard').classList.contains('active'))});
await test('14. nova solicitação continua usando formulário legado',async()=>{resetHash('#/solicitacoes/nova');await w.cwRenderRoute();assert.ok(w.document.getElementById('nova').classList.contains('active'))});
await test('15. somente um listener hashchange é registrado',async()=>assert.equal(listenerCounts.hashchange,1));

await test('16. show é declarado somente uma vez',async()=>assert.equal((appSource.match(/function\s+show\s*\(/g)||[]).length,1));
await test('17. show não é sobrescrito',async()=>assert.doesNotMatch(appSource+'\n'+routerSource,/\bshow\s*=\s*(?:async\s*)?function|\bshow\s*=\s*\(/));
await test('18. showBase não existe em produção',async()=>assert.doesNotMatch(appSource+'\n'+routerSource,/\bshowBase\b/));
await test('19. cwLegacyShow não existe em produção',async()=>assert.doesNotMatch(appSource+'\n'+routerSource,/\bcwLegacyShow\b/));
await test('20. showLegacyView renderiza dashboard',async()=>{w.showLegacyView('dashboard');assert.ok(w.document.getElementById('dashboard').classList.contains('active'))});
await test('21. showLegacyView preserva nova solicitação',async()=>{w.showLegacyView('nova');assert.ok(w.document.getElementById('nova').classList.contains('active'))});
await test('22. todos os aliases antigos permanecem registrados',async()=>assert.deepEqual({...aliases},{dashboard:'dashboard',demandas:'solicitacoes',nova:'solicitacoes/nova',usuarios:'usuarios',minhaConta:'conta',relatorios:'relatorios',organizacao:'empresa'}));
await test('23. cwNavigate delega ao controlador',async()=>{let args;const original=router.navigate;router.navigate=(...value)=>{args=value};w.cwNavigate('ativos',new w.URLSearchParams('x=1'));router.navigate=original;assert.equal(args[0],'ativos')});
await test('24. cwSetRouteFilter delega ao controlador',async()=>{let args;const original=router.setFilter;router.setFilter=(...value)=>{args=value};w.cwSetRouteFilter('status','Aberta');router.setFilter=original;assert.deepEqual(args,['status','Aberta'])});
await test('25. cwGoPage delega ao controlador',async()=>{let args;const original=router.goPage;router.goPage=(...value)=>{args=value};w.cwGoPage('solicitacoes',2);router.goPage=original;assert.deepEqual(args,['solicitacoes',2])});
await test('26. as rotas estáticas possuem scope válido',async()=>assert.ok(Object.values(routes).every(route=>scopes[route.scope])));
await test('27. dashboard pertence a core',async()=>assert.equal(routes.dashboard.scope,'core'));
await test('28. empresa pertence a core',async()=>assert.equal(routes.empresa.scope,'core'));
await test('29. conta pertence a core',async()=>assert.equal(routes.conta.scope,'core'));
await test('30. suporte pertence a core',async()=>assert.equal(routes.suporte.scope,'core'));
await test('31. ativos pertence a shared',async()=>assert.equal(routes.ativos.scope,'shared'));
await test('32. prestadores pertence a shared e é Fornecedores',async()=>assert.deepEqual([routes.prestadores.scope,routes.prestadores.title],['shared','Fornecedores']));
await test('33. cadastros pertence a shared',async()=>assert.equal(routes.cadastros.scope,'shared'));
await test('34. relatorios pertence a shared',async()=>assert.equal(routes.relatorios.scope,'shared'));
await test('35. usuarios pertence a shared',async()=>assert.equal(routes.usuarios.scope,'shared'));
await test('36. solicitacoes pertence a module manutencao',async()=>assert.deepEqual([routes.solicitacoes.scope,routes.solicitacoes.module],['module','manutencao']));
await test('37. ordens de serviço pertence a module manutencao',async()=>assert.deepEqual([routes['ordens-servico'].scope,routes['ordens-servico'].module],['module','manutencao']));
await test('38. calendario pertence a module manutencao',async()=>assert.deepEqual([routes.calendario.scope,routes.calendario.module],['module','manutencao']));
await test('39. somente Manutenção está registrada como módulo ativo',async()=>assert.deepEqual(Object.keys(modules),['manutencao']));
await test('40. URLs públicas estáticas atuais foram preservadas',async()=>assert.deepEqual(Object.keys(routes),['dashboard','solicitacoes','solicitacoes/nova','ordens-servico','calendario','ativos','prestadores','usuarios','relatorios','cadastros','empresa','conta','suporte']));
await test('41. prestadores continua funcionando',async()=>{resetHash('#/prestadores');await w.cwRenderRoute();assert.ok(w.document.getElementById('cwPrestadores').classList.contains('active'))});
await test('42. texto visível é Fornecedores',async()=>{const button=w.document.querySelector('#sidebar [data-route="prestadores"]').cloneNode(true);button.querySelectorAll('[hidden]').forEach(node=>node.remove());assert.equal(button.textContent.trim().replace(/^♙/,'').trim(),'Fornecedores')});
await test('43. não existe rota pública fornecedores',async()=>assert.equal(router.resolve('fornecedores'),null));
await test('44. solicitação dinâmica válida é resolvida',async()=>assert.equal(router.resolve('solicitacoes/123').params.id,123));
await test('45. Ordem de Serviço dinâmica válida é resolvida',async()=>assert.equal(router.resolve('ordens-servico/456').params.id,456));
await test('46. IDs inválidos são rejeitados',async()=>{const invalid=['solicitacoes/0','solicitacoes/-1','solicitacoes/1.5','solicitacoes/abc','solicitacoes/','solicitacoes/12x','ordens-servico/0','ordens-servico/-2','ordens-servico/3.2','ordens-servico/x7'];assert.ok(invalid.every(path=>router.resolve(path)===null))});
await test('47. instalação repetida não duplica hashchange',async()=>{router.install();router.install();assert.equal(listenerCounts.hashchange,1)});
await test('48. instalação repetida não duplica popstate',async()=>{router.install();router.install();assert.equal(listenerCounts.popstate,1)});
await test('49. instalação repetida não duplica handlers de menu',async()=>{let calls=0;const original=router.navigate;router.navigate=()=>{calls++};router.install();router.install();w.document.querySelector('#sidebar [data-route="ativos"]').click();router.navigate=original;assert.equal(calls,1)});
await test('50. ordem do menu foi preservada',async()=>assert.deepEqual(Array.from(menu,item=>item[0]),['dashboard','solicitacoes','ordens-servico','calendario','ativos','prestadores','usuarios','relatorios','cadastros','empresa','conta','suporte']));
await test('51. filtro preserva os demais parâmetros e remove pagina',async()=>{resetHash('#/solicitacoes?tipo=corretiva&status=Registrado&pagina=4');router.setFilter('status','Concluído');assert.equal(w.location.hash,'#/solicitacoes?tipo=corretiva&status=Conclu%C3%ADdo')});
await test('52. paginação preserva filtros',async()=>{resetHash('#/solicitacoes?tipo=corretiva');router.goPage('solicitacoes',3);assert.equal(w.location.hash,'#/solicitacoes?tipo=corretiva&pagina=3')});
await test('53. parâmetros são interpretados centralmente',async()=>{resetHash('#/solicitacoes?status=Aberta&pagina=2');const state=router.state();assert.deepEqual([state.path,state.query.get('status'),state.query.get('pagina')],['solicitacoes','Aberta','2'])});
await test('54. voltar e avançar usam o controlador',async()=>{let calls=0;const original=router.render;router.render=()=>{calls++};w.dispatchEvent(new w.PopStateEvent('popstate'));router.render=original;assert.equal(calls,1)});
await test('55. rota inválida dinâmica segue para dashboard',async()=>{approve();resetHash('#/solicitacoes/abc');await router.render();assert.equal(w.location.hash,'#/dashboard')});

await test('56. dashboard preserva o menu ativo após o renderizador legado',async()=>assertFinalRoute('dashboard','dashboard'));
await test('57. relatórios preserva o menu ativo após o renderizador legado',async()=>assertFinalRoute('relatorios','relatorios'));
await test('58. empresa preserva o menu ativo após o renderizador legado',async()=>assertFinalRoute('empresa','organizacao'));
await test('59. conta preserva o menu ativo após o renderizador legado',async()=>assertFinalRoute('conta','minhaConta'));
await test('60. solicitações continua com o menu ativo',async()=>assertFinalRoute('solicitacoes','cwSolicitacoes'));
await test('61. Ordens de Serviço continua com o menu ativo',async()=>assertFinalRoute('ordens-servico','cwOrdens'));
await test('62. calendário continua com o menu ativo',async()=>assertFinalRoute('calendario','cwCalendario'));
await test('63. ativos continua com o menu ativo',async()=>assertFinalRoute('ativos','cwAtivos'));
await test('64. prestadores continua com o menu Fornecedores ativo',async()=>assertFinalRoute('prestadores','cwPrestadores'));
await test('65. Grupos e Usuários continua com o menu ativo',async()=>assertFinalRoute('usuarios','usuarios'));
await test('66. cadastros continua com o menu ativo',async()=>assertFinalRoute('cadastros','cwCadastros'));
await test('67. suporte continua com o menu ativo',async()=>assertFinalRoute('suporte','cwSuporte'));
await test('68. existe exatamente um item ativo depois de cada navegação',async()=>{for(const [path,view,nav] of [['dashboard','dashboard'],['solicitacoes','cwSolicitacoes'],['ordens-servico','cwOrdens'],['calendario','cwCalendario'],['ativos','cwAtivos'],['prestadores','cwPrestadores'],['usuarios','usuarios'],['relatorios','relatorios'],['cadastros','cwCadastros'],['empresa','organizacao'],['conta','minhaConta'],['suporte','cwSuporte']])await assertFinalRoute(path,view,nav||path)});
await test('69. navegar entre rota moderna e legada atualiza o menu',async()=>{await assertFinalRoute('solicitacoes','cwSolicitacoes');await assertFinalRoute('dashboard','dashboard');await assertFinalRoute('ativos','cwAtivos');await assertFinalRoute('relatorios','relatorios')});
await test('70. voltar e avançar mantêm o destaque correto',async()=>{approve();resetHash('#/solicitacoes');w.dispatchEvent(new w.PopStateEvent('popstate'));await wait();assert.equal(w.location.hash,'#/solicitacoes');assert.deepEqual(activeMenuRoutes(),['solicitacoes']);resetHash('#/relatorios');w.dispatchEvent(new w.PopStateEvent('popstate'));await wait();assert.equal(w.location.hash,'#/relatorios');assert.deepEqual(activeMenuRoutes(),['relatorios'])});
await test('71. executar novamente o renderizador legado não remove o menu ativo',async()=>{for(const [path,legacyName] of [['dashboard','dashboard'],['relatorios','relatorios'],['empresa','organizacao'],['conta','minhaConta']]){await assertFinalRoute(path,routes[path].view);await w.showLegacyView(legacyName);await wait();assert.deepEqual(activeMenuRoutes(),[path])}});
await test('72. instalação repetida continua sem duplicar listeners',async()=>{const before={hashchange:listenerCounts.hashchange,popstate:listenerCounts.popstate};router.install();router.install();assert.deepEqual({hashchange:listenerCounts.hashchange,popstate:listenerCounts.popstate},before)});
await test('73. o renderizador da rota é chamado uma única vez',async()=>{approve();resetHash('#/dashboard');let calls=0;const original=routes.dashboard.render;routes.dashboard.render=()=>{calls++;return original()};await router.render();routes.dashboard.render=original;assert.equal(calls,1);assert.deepEqual(activeMenuRoutes(),['dashboard'])});

console.log(`PASS: ${passed} cenários de caracterização e consolidação da navegação.`);
w.close();
