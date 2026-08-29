-- Relatórios personalizados e identidade visual por organização
alter table public.organizacoes add column if not exists cnpj text;
alter table public.organizacoes add column if not exists endereco text;
alter table public.organizacoes add column if not exists telefone text;
alter table public.organizacoes add column if not exists email text;
alter table public.organizacoes add column if not exists logo_path text;

insert into public.permissoes_perfis(organizacao_id,papel,acao,permitido)
select o.id,r.papel,'emitir_relatorios',false
from public.organizacoes o
cross join (values('gestor_manutencao'),('tecnico'),('lojista')) r(papel)
on conflict(organizacao_id,papel,acao) do nothing;

drop policy if exists "usuario visualiza sua organizacao" on public.organizacoes;
create policy "usuario visualiza sua organizacao" on public.organizacoes for select to authenticated
using (id=(select organizacao_id from public.perfis where perfis.id=auth.uid() and ativo));
drop policy if exists "administrador atualiza sua organizacao" on public.organizacoes;
create policy "administrador atualiza sua organizacao" on public.organizacoes for update to authenticated
using (exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel='administrador' and p.organizacao_id=organizacoes.id))
with check (exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel='administrador' and p.organizacao_id=organizacoes.id));
grant select,update on public.organizacoes to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('cw-logos','cw-logos',false,5242880,array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "usuarios visualizam logo da organizacao" on storage.objects;
create policy "usuarios visualizam logo da organizacao" on storage.objects for select to authenticated
using (bucket_id='cw-logos' and (storage.foldername(name))[1]=(select organizacao_id::text from public.perfis where id=auth.uid() and ativo));
drop policy if exists "administrador envia logo da organizacao" on storage.objects;
create policy "administrador envia logo da organizacao" on storage.objects for insert to authenticated
with check (bucket_id='cw-logos' and (storage.foldername(name))[1]=(select organizacao_id::text from public.perfis where id=auth.uid() and ativo and papel='administrador'));
drop policy if exists "administrador atualiza logo da organizacao" on storage.objects;
create policy "administrador atualiza logo da organizacao" on storage.objects for update to authenticated
using (bucket_id='cw-logos' and (storage.foldername(name))[1]=(select organizacao_id::text from public.perfis where id=auth.uid() and ativo and papel='administrador'))
with check (bucket_id='cw-logos' and (storage.foldername(name))[1]=(select organizacao_id::text from public.perfis where id=auth.uid() and ativo and papel='administrador'));

create or replace function public.dados_relatorio()
returns jsonb language plpgsql security definer set search_path=public as $$
declare perfil public.perfis%rowtype; resultado jsonb;
begin
  select * into perfil from public.perfis where id=auth.uid() and ativo;
  if perfil.id is null then raise exception 'Perfil ativo não encontrado'; end if;
  if perfil.papel<>'administrador' and not public.tem_permissao_usuario('emitir_relatorios') then raise exception 'Sem permissão para emitir relatórios'; end if;
  select jsonb_build_object(
    'organizacao',to_jsonb(o),
    'solicitante',jsonb_build_object('nome',perfil.nome,'email',perfil.email),
    'demandas',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'codigo',d.codigo,'tipo_demanda',d.tipo_demanda,'tipo',d.titulo,'local',d.local,
      'status',d.status,'prioridade',d.prioridade,'responsavel',d.responsavel,'prestador',d.empresa_prestador,
      'data_cadastro',d.criado_em,'data_prevista',d.agendamento_em,'prazo',d.prazo,
      'descricao',d.observacoes,'usuario_id',d.criado_por,'usuario_nome',coalesce(p.nome,p.email,'Usuário'),'loja',p.loja
    ) order by d.criado_em desc) from public.demandas d left join public.perfis p on p.id=d.criado_por where d.organizacao_id=perfil.organizacao_id),'[]'::jsonb)
  ) into resultado from public.organizacoes o where o.id=perfil.organizacao_id;
  return resultado;
end; $$;
revoke all on function public.dados_relatorio() from public;
grant execute on function public.dados_relatorio() to authenticated;
