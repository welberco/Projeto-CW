-- Cadastro seguro de demanda para o perfil Lojista
create or replace function public.criar_demanda_lojista(
  p_titulo text,
  p_local text,
  p_observacoes text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  perfil public.perfis%rowtype;
  demanda_id bigint;
begin
  select * into perfil from public.perfis
  where id = auth.uid() and ativo and papel = 'lojista';

  if perfil.id is null then
    raise exception 'Perfil Lojista ativo não encontrado';
  end if;
  if nullif(trim(p_titulo), '') is null or nullif(trim(p_local), '') is null or nullif(trim(p_observacoes), '') is null then
    raise exception 'Título, local e descrição são obrigatórios';
  end if;

  insert into public.demandas (
    organizacao_id, titulo, categoria, local, prioridade,
    responsavel, status, prazo, proxima_acao, observacoes, criado_por
  ) values (
    perfil.organizacao_id, trim(p_titulo), 'Manutenção', trim(p_local), 'Não classificada',
    null, 'A Fazer', null, null, trim(p_observacoes), auth.uid()
  ) returning id into demanda_id;

  return jsonb_build_object('id', demanda_id);
end;
$$;

revoke all on function public.criar_demanda_lojista(text,text,text) from public;
grant execute on function public.criar_demanda_lojista(text,text,text) to authenticated;
