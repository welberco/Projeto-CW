-- Endereços amigáveis e estáveis por empreendimento.
begin;

alter table public.organizacoes add column if not exists slug text;

create or replace function public.cw_slug_empresa(valor text)
returns text
language sql
immutable
strict
as $$
  select trim(both '-' from regexp_replace(
    translate(lower(valor),'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),
    '[^a-z0-9]+','-','g'
  ));
$$;

do $$
declare
  empresa record;
  base_slug text;
  slug_livre text;
  contador integer;
begin
  for empresa in select id,nome from public.organizacoes where slug is null or trim(slug)='' order by criado_em nulls last,id
  loop
    base_slug:=coalesce(nullif(public.cw_slug_empresa(empresa.nome),''),'empresa');
    slug_livre:=base_slug;
    contador:=2;
    while exists(select 1 from public.organizacoes where lower(slug)=lower(slug_livre) and id<>empresa.id) loop
      slug_livre:=base_slug||'-'||contador;
      contador:=contador+1;
    end loop;
    update public.organizacoes set slug=slug_livre where id=empresa.id;
  end loop;
end;
$$;

alter table public.organizacoes alter column slug set not null;
create unique index if not exists organizacoes_slug_unique on public.organizacoes(lower(slug));
alter table public.organizacoes drop constraint if exists organizacoes_slug_formato;
alter table public.organizacoes add constraint organizacoes_slug_formato check(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$');

create or replace function public.cw_definir_slug_organizacao()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  base_slug text;
  slug_livre text;
  contador integer:=2;
begin
  if new.slug is not null and trim(new.slug)<>'' then return new; end if;
  base_slug:=coalesce(nullif(public.cw_slug_empresa(new.nome),''),'empresa');
  slug_livre:=base_slug;
  while exists(select 1 from public.organizacoes where lower(slug)=lower(slug_livre) and id<>new.id) loop
    slug_livre:=base_slug||'-'||contador;
    contador:=contador+1;
  end loop;
  new.slug:=slug_livre;
  return new;
end;
$$;

drop trigger if exists cw_definir_slug_organizacao on public.organizacoes;
create trigger cw_definir_slug_organizacao
before insert on public.organizacoes
for each row execute function public.cw_definir_slug_organizacao();

drop function if exists public.cw_listar_organizacoes();
create function public.cw_listar_organizacoes()
returns table(id uuid,nome text,slug text)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.cw_admin() then
    raise exception 'Apenas o Administrador pode listar todos os empreendimentos';
  end if;
  return query select o.id,o.nome,o.slug from public.organizacoes o order by o.nome;
end;
$$;
revoke all on function public.cw_listar_organizacoes() from public,anon;
grant execute on function public.cw_listar_organizacoes() to authenticated;

commit;
