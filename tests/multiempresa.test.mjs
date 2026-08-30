import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const read = p => readFileSync(new URL('../'+p, import.meta.url), 'utf8');
await db.exec(`
create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create schema storage;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,owner_id text);
create function storage.foldername(text) returns text[] language sql immutable as $$ select string_to_array($1,'/') $$;
alter table storage.objects enable row level security;
grant usage on schema public,auth,storage to anon,authenticated;
grant select,insert,update,delete on storage.objects to authenticated;
`);
for (const file of ['schema.sql','attachments.sql','history.sql','user-roles.sql','permissions-users.sql','demand-types-codes.sql','reports.sql']) {
  await db.exec(read('supabase/'+file).replace('create extension if not exists pgcrypto;', ''));
}
await db.exec(`grant select,insert,update,delete on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;`);
const A='10000000-0000-0000-0000-000000000001', B='10000000-0000-0000-0000-000000000002';
const admin='20000000-0000-0000-0000-000000000001', enterprise='20000000-0000-0000-0000-000000000002', manager='20000000-0000-0000-0000-000000000003', tech='20000000-0000-0000-0000-000000000004', standard='20000000-0000-0000-0000-000000000005', other='20000000-0000-0000-0000-000000000006', pending='20000000-0000-0000-0000-000000000007';
await db.query('insert into public.organizacoes(id,nome) values($1,$2),($3,$4)',[A,'Empresa A',B,'Empresa B']);
for(const [id,role,org] of [[admin,'administrador',A],[enterprise,'gestor_manutencao',A],[manager,'gestor_manutencao',A],[tech,'tecnico',A],[standard,'lojista',A],[other,'lojista',B]]){
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[id,id+'@example.test',{nome:role,papel:role}]);
  await db.query('update public.perfis set papel=$1,organizacao_id=$2 where id=$3',[role,org,id]);
}
await db.query(`insert into demandas(organizacao_id,titulo,categoria,local,prioridade,status,tipo_demanda,criado_por) values
($1,'A própria','Manutenção','Loja','Alta','Registrado','corretiva',$3),
($1,'A outra','Manutenção','Loja','Baixa','Registrado','corretiva',$4),
($2,'B privada','Manutenção','Loja','Alta','Aguardando aprovação','agendamento',$5)`,[A,B,standard,manager,other]);
await db.exec(read('supabase/multiempresa.sql'));
await db.query('update public.perfis set papel=$1 where id=$2',['empreendimento',enterprise]);
const act=async(user,sql,params=[])=>{
  await db.exec('begin; set local role authenticated;');
  try{await db.query("select set_config('request.jwt.claim.sub',$1,true)",[user]);const r=await db.query(sql,params);await db.exec('commit');return r.rows;}
  catch(e){await db.exec('rollback');throw e;}
};
const deny=async(user,sql,params=[])=>assert.rejects(()=>act(user,sql,params));
assert.equal((await act(tech,'select * from demandas')).length,2);
assert.equal((await act(standard,'select * from demandas')).length,1);
assert.equal((await act(other,'select * from demandas')).length,1);
assert.equal((await act(admin,'select * from demandas')).length,3);
assert.equal((await act(manager,'select * from demandas where organizacao_id=$1',[B])).length,0);
await deny(manager,'select decidir_agendamento(3,$1)',['Aprovado']);
await deny(tech,`insert into demandas(organizacao_id,titulo,categoria,local,prioridade,status,criado_por) values($1,'x','Manutenção','x','Alta','Registrado',$2)`,[A,tech]);
assert.equal((await act(manager,'update permissoes_perfis set permitido=true where organizacao_id=$1 returning *',[B])).length,0);
assert.equal((await act(manager,'update permissoes_perfis set permitido=false where organizacao_id=$1 returning *',[A])).length,0);
await act(enterprise,"update permissoes_perfis set permitido=false where organizacao_id=$1 and papel='gestor_manutencao' and acao='apagar_demanda'",[A]);
assert.equal((await act(manager,"select tem_permissao_usuario('apagar_demanda') ok"))[0].ok,false);
await act(enterprise,"update permissoes_perfis set permitido=true where organizacao_id=$1 and papel='tecnico' and acao='criar_corretiva'",[A]);
assert.equal((await act(tech,"select tem_permissao_usuario('criar_corretiva') ok"))[0].ok,true);
await deny(enterprise,"update permissoes_perfis set permitido=true where organizacao_id=$1 and acao='gerenciar_permissoes'",[A]);
await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[pending,'pending@example.test',{organizacao_id:A,nome:'Novo',papel:'administrador',aprovado:true,ativo:true}]);
const p=(await db.query('select * from perfis where id=$1',[pending])).rows[0];assert.equal(p.papel,'lojista');assert.equal(p.aprovacao,'pendente');assert.equal(p.ativo,false);
assert.equal((await act(pending,'select * from demandas')).length,0);
assert.equal((await act(pending,'select * from organizacoes')).length,0);
assert.equal((await act(pending,'select * from perfis')).length,1);
await deny(pending,"update perfis set ativo=true,aprovacao='aprovado',papel='administrador' where id=$1",[pending]);
await deny(pending,'select criar_demanda_empresa($1,$2,$3,$4,$5,null,null,null,null,null,null)',[A,'Teste','Loja','Problema','corretiva']);
await deny(pending,'select dados_relatorio_empresa($1)',[A]);
await deny(manager,'select cw_salvar_usuario($1,$2,$3,$4,$5,true,$6)',[other,'Nome','other@example.test','','gestor_manutencao','aprovado']);
await deny(manager,'select cw_salvar_usuario($1,$2,$3,$4,$5,true,$6)',[pending,'Nome','pending@example.test','','administrador','aprovado']);
await act(manager,'select cw_salvar_usuario($1,$2,$3,$4,$5,true,$6)',[pending,'Nome','pending@example.test','','tecnico','aprovado']);
assert.equal((await act(pending,'select * from demandas')).length,2);
await deny(manager,'select cw_salvar_usuario($1,$2,$3,$4,$5,true,$6)',[enterprise,'Nome','enterprise@example.test','','tecnico','aprovado']);
await deny(enterprise,'select dados_relatorio_empresa($1)',[B]);
assert.equal((await act(admin,'select dados_relatorio_empresa($1) r',[B]))[0].r.demandas.length,1);
await act(admin,'select criar_demanda_empresa($1,$2,$3,$4,$5,null,null,null,null,null,null)',[B,'Nova','Local','Problema','corretiva']);
assert.equal((await act(other,'select * from demandas')).length,1);
assert.equal((await act(admin,'select * from demandas where organizacao_id=$1',[B])).length,2);
assert.equal((await act(tech,"select cw_storage_permitido('cw-anexos','3/foto.jpg','select') ok"))[0].ok,false);
assert.equal((await act(tech,"select cw_storage_permitido('cw-logos',$1,'insert') ok",[A+'/logo.png']))[0].ok,false);
assert.equal((await act(enterprise,"select cw_storage_permitido('cw-logos',$1,'insert') ok",[A+'/logo.png']))[0].ok,true);
assert.equal((await act(enterprise,"select cw_storage_permitido('cw-logos',$1,'insert') ok",[B+'/logo.png']))[0].ok,false);
assert.equal((await act(manager,"update demandas set titulo='invadida' where organizacao_id=$1 returning *",[B])).length,0);
assert.equal((await act(manager,'delete from demandas where organizacao_id=$1 returning *',[B])).length,0);
assert.equal((await act(standard,"select cw_storage_permitido('cw-anexos','2/foto.jpg','insert') ok"))[0].ok,false);
await act(enterprise,"update permissoes_perfis set permitido=true where organizacao_id=$1 and papel='lojista' and acao='emitir_relatorios'",[A]);
assert.equal((await act(standard,'select dados_relatorio() r'))[0].r.demandas.length,1);
await act(admin,"insert into organizacoes(nome) values('Empresa C')");
const companyC=(await db.query("select id from organizacoes where nome='Empresa C'")).rows[0].id;
const rules=(await db.query('select * from permissoes_perfis where organizacao_id=$1',[companyC])).rows;
assert.equal(rules.length,51);assert.equal(rules.filter(r=>r.papel==='tecnico'&&r.permitido).length,2);
await db.exec("create policy generic_legacy_storage on storage.objects for all to authenticated using(true) with check(true);");
await db.query("insert into storage.objects(bucket_id,name) values('cw-anexos','3/foto.jpg'),('cw-logos',$1)",[A+'/logo.png']);
assert.equal((await act(tech,"select * from storage.objects where name='3/foto.jpg'")).length,0);
assert.equal((await act(tech,"delete from storage.objects where bucket_id='cw-logos' returning *")).length,0);
await deny(tech,"insert into storage.objects(bucket_id,name) values('cw-logos',$1)",[A+'/bad.png']);
await db.exec(read('supabase/multiempresa.sql'));
assert.equal((await act(manager,"select tem_permissao_usuario('apagar_demanda') ok"))[0].ok,false);
console.log('PASS: isolamento de 2 empresas, 7 usuários, pendência, promoção, matriz, RPCs, Storage, reexecução preservando permissões.');
await db.close();
