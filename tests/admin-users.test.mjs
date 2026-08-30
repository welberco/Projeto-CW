import ts from 'typescript';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../supabase/functions/admin-users/index.ts',import.meta.url),'utf8').replace(/import[^\n]+\n/,'');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
assert.equal(compiled.diagnostics.length,0);
async function scenario({allowed=true,pending=false,targetOrg='A',saveError=false,action='create'}={}){
  const writes=[];let handler;
  const actor={id:'actor',papel:'gestor_manutencao',organizacao_id:'A',ativo:!pending,aprovacao:pending?'pendente':'aprovado'};
  const target={id:'target',papel:'lojista',organizacao_id:targetOrg,email:'old@example.test'};
  const caller={auth:{getUser:async()=>({data:{user:{id:'actor'}}})},from(){let id;const q={select(){return q},eq(k,v){id=v;return q},single:async()=>({data:id==='actor'?actor:target})};return q},
    async rpc(name,args){if(name==='cw_pode_gerenciar_usuario')return{data:allowed&&args.p_org==='A',error:null};writes.push({kind:'profile',args});return{error:saveError?{message:'falha simulada'}:null}}};
  const service={auth:{admin:{async createUser(args){writes.push({kind:'auth-create',args});return{data:{user:{id:'new'}}}},async updateUserById(id,args){writes.push({kind:'auth-update',id,args});return{error:null}}}}};
  const context={createClient:(url,key)=>key==='service'?service:caller,Deno:{env:{get:k=>k==='SUPABASE_SERVICE_ROLE_KEY'?'service':'anon'},serve:f=>handler=f},Response,Request,Error,JSON};
  vm.runInNewContext(compiled.outputText,context);
  const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({action,user_id:'target',nome:'Teste',email:'new@example.test',password:'password-test-only',papel:'tecnico',ativo:true,aprovacao:'aprovado',organizacao_id:'B'})}));
  return{status:response.status,body:await response.json(),writes};
}
for(const config of [{allowed:false},{pending:true},{action:'update',targetOrg:'B'}]){
  const r=await scenario(config);assert.equal(r.status,400);assert.equal(r.writes.length,0);
}
const created=await scenario();assert.equal(created.status,200);
assert.equal(created.writes[0].args.user_metadata.organizacao_id,'A');assert.equal(created.writes[0].args.user_metadata.papel,undefined);
assert.equal(created.writes[1].kind,'profile');
const failed=await scenario({saveError:true});assert.equal(failed.status,400);assert.ok(failed.body.error.includes('pendente'));
const updated=await scenario({action:'update'});assert.equal(updated.status,200);assert.equal(updated.writes.at(-1).kind,'profile');
console.log('PASS: Edge Function bloqueia pendentes, outra empresa e falta de permissão; criação força empresa e mantém conta pendente em falha parcial.');
