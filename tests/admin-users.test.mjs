import ts from 'typescript';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../supabase/functions/admin-users/index.ts',import.meta.url),'utf8').replace(/import[^\n]+\n/,'');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
assert.equal(compiled.diagnostics.length,0);
async function scenario({allowed=true,pending=false,targetOrg='A',saveError=false,action='create',operationId=null}={}){
  const writes=[];let handler;
  const actor={id:'actor',papel:'gestor',organizacao_id:'A',ativo:!pending,aprovacao:pending?'pendente':'aprovado'};
  const target={id:'target',papel:'usuario_padrao',organizacao_id:targetOrg,email:'old@example.test'};
  const caller={auth:{getUser:async()=>({data:{user:{id:'actor'}}})},from(table){let id;const q={select(){return q},eq(k,v){if(k==='id')id=v;return q},single:async()=>({data:table==='operacoes'?{id:operationId,nome:'Loja A'}:id==='actor'?actor:target,error:null}),delete(){writes.push({kind:'operation-unlink'});return q},insert(row){writes.push({kind:'operation-link',row});return Promise.resolve({error:null})},then(resolve){return Promise.resolve({error:null}).then(resolve)}};return q},
    async rpc(name,args){if(name==='cw_pode_gerenciar_usuario')return{data:allowed&&args.p_org==='A',error:null};writes.push({kind:'profile',args});return{error:saveError?{message:'falha simulada'}:null}}};
  const service={auth:{admin:{async inviteUserByEmail(email,args){writes.push({kind:'auth-invite',email,args});return{data:{user:{id:'new'}}}},async updateUserById(id,args){writes.push({kind:'auth-update',id,args});return{error:null}}}}};
  const context={createClient:(url,key)=>key==='service'?service:caller,Deno:{env:{get:k=>k==='SUPABASE_SERVICE_ROLE_KEY'?'service':'anon'},serve:f=>handler=f},Response,Request,Error,JSON};
  vm.runInNewContext(compiled.outputText,context);
  const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({action,user_id:'target',nome:'Teste',email:'new@example.test',papel:'tecnico',ativo:true,aprovacao:'aprovado',organizacao_id:'B',redirect_to:'https://example.test/#/conta',operacao_id:operationId})}));
  return{status:response.status,body:await response.json(),writes};
}
for(const config of [{allowed:false},{pending:true},{action:'update',targetOrg:'B'}]){
  const r=await scenario(config);assert.equal(r.status,400);assert.equal(r.writes.length,0);
}
const created=await scenario();assert.equal(created.status,200);
assert.equal(created.writes[0].args.data.organizacao_id,'A');assert.equal(created.writes[0].args.data.papel,undefined);assert.equal(created.writes[0].kind,'auth-invite');
assert.equal(created.writes[1].kind,'profile');
const failed=await scenario({saveError:true});assert.equal(failed.status,400);assert.ok(failed.body.error.includes('pendente'));
const updated=await scenario({action:'update'});assert.equal(updated.status,200);assert.ok(updated.writes.some(x=>x.kind==='profile'));
const linked=await scenario({operationId:7});assert.equal(linked.status,200);assert.equal(linked.writes.find(x=>x.kind==='operation-link').row.operacao_id,7);
console.log('PASS: Edge Function bloqueia pendentes, outra empresa e falta de permissão; criação força empresa e mantém conta pendente em falha parcial.');
