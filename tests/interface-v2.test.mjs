import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const empty=()=>({data:[],error:null});
const client={
  auth:{onAuthStateChange(){},getSession:async()=>({data:{session:null}}),signOut:async()=>({error:null})},
  from(){const chain={select(){return chain},order(){return chain},eq(){return chain},range(){return chain},gte(){return chain},lte(){return chain},then(resolve){return Promise.resolve(empty()).then(resolve)},single:async()=>({data:null,error:null}),maybeSingle:async()=>({data:null,error:null})};return chain},
  rpc:async()=>empty(),functions:{invoke:async()=>empty()},storage:{from:()=>({createSignedUrl:async()=>({data:null,error:null})})}
};
const dom=new JSDOM(read('index.html').replace(/<script[\s\S]*?<\/script>/g,''),{runScripts:'dangerously',url:'https://example.test/'});
const w=dom.window;w.supabase={createClient:()=>client};w.HTMLElement.prototype.scrollIntoView=()=>{};
for(const path of ['app.js','multiempresa.js','arquitetura-v2.js']){const script=w.document.createElement('script');script.textContent=read(path);w.document.body.appendChild(script)}
await new Promise(resolve=>setTimeout(resolve,20));
const labels=[...w.document.querySelectorAll('#sidebar [data-route]')].map(node=>node.textContent.trim());
assert.equal(labels.length,12);
for(const expected of ['Dashboard','Solicitações','Ordens de Serviço','Ativos e Equipamentos','Prestadores','Grupos e Usuários','Suporte'])assert.ok(labels.some(label=>label.includes(expected)));
assert.equal(w.document.getElementById('toggleAuth').style.display,'none');
assert.ok(w.document.getElementById('cwOrdens'));
assert.ok(w.document.getElementById('cwAtivos'));
assert.ok(w.document.getElementById('cwPrestadores'));
assert.equal(w.location.hash,'#/dashboard');
console.log('PASS: navegação v2, módulos separados, rotas persistentes e cadastro público desativado.');
w.close();
