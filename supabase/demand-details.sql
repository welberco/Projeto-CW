-- CW Manutenção - data da ocorrência e histórico
alter table public.demandas
add column if not exists data_ocorrencia date;

update public.demandas
set data_ocorrencia = criado_em::date
where data_ocorrencia is null;

alter table public.demandas
alter column data_ocorrencia set default current_date;

create or replace function public.registrar_historico_demanda()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  mudancas jsonb := '{}'::jsonb;
  nome_usuario text;
begin
  if old.titulo is distinct from new.titulo then
    mudancas := mudancas || jsonb_build_object('Título', jsonb_build_object('anterior', old.titulo, 'novo', new.titulo));
  end if;
  if old.data_ocorrencia is distinct from new.data_ocorrencia then
    mudancas := mudancas || jsonb_build_object('Data', jsonb_build_object('anterior', old.data_ocorrencia, 'novo', new.data_ocorrencia));
  end if;
  if old.categoria is distinct from new.categoria then
    mudancas := mudancas || jsonb_build_object('Categoria', jsonb_build_object('anterior', old.categoria, 'novo', new.categoria));
  end if;
  if old.local is distinct from new.local then
    mudancas := mudancas || jsonb_build_object('Local', jsonb_build_object('anterior', old.local, 'novo', new.local));
  end if;
  if old.prioridade is distinct from new.prioridade then
    mudancas := mudancas || jsonb_build_object('Prioridade', jsonb_build_object('anterior', old.prioridade, 'novo', new.prioridade));
  end if;
  if old.responsavel is distinct from new.responsavel then
    mudancas := mudancas || jsonb_build_object('Responsável', jsonb_build_object('anterior', old.responsavel, 'novo', new.responsavel));
  end if;
  if old.status is distinct from new.status then
    mudancas := mudancas || jsonb_build_object('Status', jsonb_build_object('anterior', old.status, 'novo', new.status));
  end if;
  if old.prazo is distinct from new.prazo then
    mudancas := mudancas || jsonb_build_object('Prazo', jsonb_build_object('anterior', old.prazo, 'novo', new.prazo));
  end if;
  if old.proxima_acao is distinct from new.proxima_acao then
    mudancas := mudancas || jsonb_build_object('Próxima ação', jsonb_build_object('anterior', old.proxima_acao, 'novo', new.proxima_acao));
  end if;
  if old.observacoes is distinct from new.observacoes then
    mudancas := mudancas || jsonb_build_object('Descrição do problema', jsonb_build_object('anterior', old.observacoes, 'novo', new.observacoes));
  end if;

  if mudancas <> '{}'::jsonb then
    select nome into nome_usuario from public.perfis where id = auth.uid();
    insert into public.historico_demandas (demanda_id, usuario_id, usuario_nome, alteracoes)
    values (new.id, auth.uid(), coalesce(nome_usuario, 'Usuário'), mudancas);
  end if;
  return new;
end;
$$;
