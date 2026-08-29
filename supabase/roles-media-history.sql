-- CW Manutenção - perfis de lojista e histórico de mídias
alter table public.perfis
alter column papel set default 'solicitante';

create or replace function public.registrar_historico_anexo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  nome_usuario text;
  demanda bigint;
  arquivo text;
  acao text;
begin
  demanda := coalesce(new.demanda_id, old.demanda_id);
  arquivo := coalesce(new.nome_arquivo, old.nome_arquivo);
  acao := case when tg_op = 'INSERT' then 'Mídia adicionada' else 'Mídia removida' end;
  select nome into nome_usuario from public.perfis where id = auth.uid();

  insert into public.historico_demandas
    (demanda_id, usuario_id, usuario_nome, alteracoes)
  values (
    demanda,
    auth.uid(),
    coalesce(nome_usuario, 'Usuário'),
    jsonb_build_object(
      acao,
      jsonb_build_object(
        'anterior', case when tg_op = 'DELETE' then arquivo else null end,
        'novo', case when tg_op = 'INSERT' then arquivo else null end
      )
    )
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists registrar_adicao_anexo on public.anexos_demandas;
create trigger registrar_adicao_anexo
after insert on public.anexos_demandas
for each row execute procedure public.registrar_historico_anexo();

drop trigger if exists registrar_exclusao_anexo on public.anexos_demandas;
create trigger registrar_exclusao_anexo
after delete on public.anexos_demandas
for each row execute procedure public.registrar_historico_anexo();
