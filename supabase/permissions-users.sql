-- Matriz de permissões e dados administrativos de usuários
alter table public.perfis add column if not exists email text;

update public.perfis p set email=u.email
from auth.users u where u.id=p.id and p.email is null;

create table if not exists public.permissoes_perfis (
  organizacao_id uuid not null references public.organizacoes(id) on delete cascade,
  papel text not null check (papel in ('gestor_manutencao','tecnico','lojista')),
  acao text not null,
  permitido boolean not null default false,
  atualizado_em timestamptz not null default now(),
  primary key (organizacao_id,papel,acao)
);

alter table public.permissoes_perfis enable row level security;

create or replace function public.tem_permissao_usuario(acao_consultada text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.perfis p
    where p.id=auth.uid() and p.ativo and (
      p.papel='administrador' or exists (
        select 1 from public.permissoes_perfis pp
        where pp.organizacao_id=p.organizacao_id and pp.papel=p.papel
          and pp.acao=acao_consultada and pp.permitido
      )
    )
  );
$$;

drop policy if exists "gestao visualiza permissoes" on public.permissoes_perfis;
drop policy if exists "administrador altera permissoes" on public.permissoes_perfis;
drop policy if exists "usuarios visualizam permissoes da organizacao" on public.permissoes_perfis;
create policy "usuarios visualizam permissoes da organizacao" on public.permissoes_perfis for select to authenticated
using (organizacao_id=(select organizacao_id from public.perfis where id=auth.uid() and ativo));
create policy "administrador altera permissoes" on public.permissoes_perfis for all to authenticated
using (exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel='administrador' and p.organizacao_id=permissoes_perfis.organizacao_id))
with check (exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel='administrador' and p.organizacao_id=permissoes_perfis.organizacao_id));

grant select,insert,update,delete on public.permissoes_perfis to authenticated;
grant execute on function public.tem_permissao_usuario(text) to authenticated;

insert into public.permissoes_perfis (organizacao_id,papel,acao,permitido)
select o.id, r.papel, a.acao,
  case
    when r.papel='gestor_manutencao' then a.acao<>'gerenciar_permissoes'
    when r.papel='tecnico' then a.acao in ('visualizar_todas','visualizar_historico')
    when r.papel='lojista' then a.acao in ('visualizar_proprias','cadastrar_demanda','editar_proprias','excluir_midia','visualizar_historico')
    else false end
from public.organizacoes o
cross join (values ('gestor_manutencao'),('tecnico'),('lojista')) r(papel)
cross join (values
 ('visualizar_todas'),('visualizar_proprias'),('cadastrar_demanda'),('editar_todas'),
 ('editar_proprias'),('classificar_prioridade'),('alterar_status'),('excluir_midia'),
 ('apagar_demanda'),('visualizar_historico'),('gerenciar_usuarios'),('gerenciar_permissoes')
) a(acao)
on conflict (organizacao_id,papel,acao) do nothing;

drop policy if exists "gestao atualiza perfis" on public.perfis;
drop policy if exists "permissao atualiza perfis" on public.perfis;
create policy "permissao atualiza perfis" on public.perfis for update to authenticated
using (public.tem_permissao_usuario('gerenciar_usuarios'))
with check (public.tem_permissao_usuario('gerenciar_usuarios'));

create or replace function public.criar_perfil_usuario()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.perfis (id,organizacao_id,nome,email,papel,ativo)
  values (
    new.id,
    (select id from public.organizacoes order by criado_em limit 1),
    coalesce(new.raw_user_meta_data->>'nome',split_part(new.email,'@',1)),
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'papel',''),'lojista'),
    true
  );
  return new;
end; $$;

create or replace function public.pode_visualizar_demanda(demanda bigint)
returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.demandas d
    where d.id=demanda and (
      public.tem_permissao_usuario('visualizar_todas')
      or (d.criado_por=auth.uid() and public.tem_permissao_usuario('visualizar_proprias'))
    )
  );
$$;

drop policy if exists "perfis autorizados criam demandas" on public.demandas;
drop policy if exists "permissao cria demanda" on public.demandas;
create policy "permissao cria demanda" on public.demandas for insert to authenticated
with check (criado_por=auth.uid() and public.tem_permissao_usuario('cadastrar_demanda'));

drop policy if exists "gestao ou criador atualiza demanda" on public.demandas;
drop policy if exists "permissao atualiza demanda" on public.demandas;
create policy "permissao atualiza demanda" on public.demandas for update to authenticated
using (public.tem_permissao_usuario('editar_todas') or (criado_por=auth.uid() and public.tem_permissao_usuario('editar_proprias')))
with check (public.tem_permissao_usuario('editar_todas') or (criado_por=auth.uid() and public.tem_permissao_usuario('editar_proprias')));

drop policy if exists "permissao apaga demanda" on public.demandas;
create policy "permissao apaga demanda" on public.demandas for delete to authenticated
using (public.tem_permissao_usuario('apagar_demanda'));

create or replace function public.restringir_campos_por_permissao()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  new.organizacao_id:=old.organizacao_id; new.criado_por:=old.criado_por; new.criado_em:=old.criado_em;
  if not public.tem_permissao_usuario('classificar_prioridade') then new.prioridade:=old.prioridade; end if;
  if not public.tem_permissao_usuario('alterar_status') then
    new.categoria:=old.categoria; new.responsavel:=old.responsavel; new.status:=old.status;
    new.prazo:=old.prazo; new.proxima_acao:=old.proxima_acao;
  end if;
  return new;
end; $$;
drop trigger if exists restringir_edicao_lojista on public.demandas;
drop trigger if exists restringir_campos_por_permissao on public.demandas;
create trigger restringir_campos_por_permissao before update on public.demandas for each row execute procedure public.restringir_campos_por_permissao();

drop policy if exists "usuario visualiza historico permitido" on public.historico_demandas;
drop policy if exists "permissao visualiza historico" on public.historico_demandas;
create policy "permissao visualiza historico" on public.historico_demandas for select to authenticated
using (public.tem_permissao_usuario('visualizar_historico') and public.pode_visualizar_demanda(demanda_id));

drop policy if exists "criador ou gestao exclui anexo" on public.anexos_demandas;
drop policy if exists "permissao exclui anexo" on public.anexos_demandas;
create policy "permissao exclui anexo" on public.anexos_demandas for delete to authenticated
using (public.tem_permissao_usuario('excluir_midia') and public.pode_visualizar_demanda(demanda_id));

drop policy if exists "usuario adiciona anexos permitidos" on public.anexos_demandas;
drop policy if exists "permissao adiciona anexo" on public.anexos_demandas;
create policy "permissao adiciona anexo" on public.anexos_demandas for insert to authenticated
with check (criado_por=auth.uid() and public.pode_visualizar_demanda(demanda_id) and (public.tem_permissao_usuario('cadastrar_demanda') or public.tem_permissao_usuario('editar_todas') or public.tem_permissao_usuario('editar_proprias')));

drop policy if exists "usuario envia arquivos permitidos" on storage.objects;
drop policy if exists "permissao envia arquivo" on storage.objects;
create policy "permissao envia arquivo" on storage.objects for insert to authenticated
with check (bucket_id='cw-anexos' and public.pode_visualizar_demanda(((storage.foldername(name))[1])::bigint) and (public.tem_permissao_usuario('cadastrar_demanda') or public.tem_permissao_usuario('editar_todas') or public.tem_permissao_usuario('editar_proprias')));

drop policy if exists "criador ou gestao exclui arquivo" on storage.objects;
drop policy if exists "permissao exclui arquivo" on storage.objects;
create policy "permissao exclui arquivo" on storage.objects for delete to authenticated
using (bucket_id='cw-anexos' and public.tem_permissao_usuario('excluir_midia') and public.pode_visualizar_demanda(((storage.foldername(name))[1])::bigint));
