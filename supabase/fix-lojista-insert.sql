-- Correção do cadastro de demandas pelo perfil Lojista

create or replace function public.pode_criar_demanda(org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.perfis p
    where p.id = auth.uid()
      and p.organizacao_id = org
      and p.ativo
      and p.papel in ('administrador','gestor_manutencao','lojista')
  );
$$;

create or replace function public.preparar_demanda_lojista()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.perfis p
    where p.id = auth.uid() and p.ativo and p.papel = 'lojista'
  ) then
    new.categoria := 'Manutenção';
    new.prioridade := 'Não classificada';
    new.responsavel := null;
    new.status := 'A Fazer';
    new.prazo := null;
    new.proxima_acao := null;
    new.criado_por := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists preparar_demanda_lojista on public.demandas;
create trigger preparar_demanda_lojista
before insert on public.demandas
for each row execute procedure public.preparar_demanda_lojista();

drop policy if exists "perfis autorizados criam demandas" on public.demandas;
create policy "perfis autorizados criam demandas"
on public.demandas for insert to authenticated
with check (
  criado_por = auth.uid()
  and public.pode_criar_demanda(organizacao_id)
);
