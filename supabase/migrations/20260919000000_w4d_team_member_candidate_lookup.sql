-- W4D.2.1: minimal, add-capability-bound candidate lookup for Team membership.
-- This read-time suggestion does not reserve a candidate. add_team_member remains
-- authoritative under its W4B locks, lifecycle checks and active-pair index.

create function public.lookup_team_member_candidates(
  target_team_id uuid,
  search_text text default null,
  result_limit integer default 20,
  result_offset integer default 0
)
returns table(membership_id uuid, user_id uuid, display_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_tenant_id uuid;
  normalized_search text := pg_catalog.btrim(search_text);
begin
  actor_tenant_id := private.assert_w4b_all_tenant_access(
    'team_memberships', 'add'
  );

  if result_limit is null or result_limit not between 1 and 100
     or result_offset is null or result_offset < 0
     or (normalized_search is not null
         and pg_catalog.char_length(normalized_search) > 160) then
    raise exception using errcode = '22023', message = 'INVALID_QUERY_INPUT';
  end if;

  if not exists (
    select 1 from public.teams as team
    where team.id = target_team_id
      and team.tenant_id = actor_tenant_id
      and team.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'TEAM_UNAVAILABLE';
  end if;

  return query
  select membership.id, membership.user_id, app_user.display_name
  from public.tenant_memberships as membership
  join public.app_users as app_user
    on app_user.id = membership.user_id
   and app_user.status = 'active'
  where membership.tenant_id = actor_tenant_id
    and membership.status = 'active'
    and (
      normalized_search is null or normalized_search = ''
      or pg_catalog.strpos(
        pg_catalog.lower(app_user.display_name),
        pg_catalog.lower(normalized_search)
      ) > 0
    )
    and not exists (
      select 1 from public.team_memberships as association
      where association.tenant_id = actor_tenant_id
        and association.team_id = target_team_id
        and association.membership_id = membership.id
        and association.status = 'active'
    )
  order by pg_catalog.lower(app_user.display_name) nulls last,
           membership.user_id, membership.id
  limit result_limit offset result_offset;
end;
$$;

alter function public.lookup_team_member_candidates(uuid,text,integer,integer)
  owner to postgres;
revoke all on function public.lookup_team_member_candidates(uuid,text,integer,integer)
  from public, anon, authenticated, service_role, cw_worker;
grant execute on function public.lookup_team_member_candidates(uuid,text,integer,integer)
  to authenticated;

comment on function public.lookup_team_member_candidates(uuid,text,integer,integer) is
  'Minimal read-time candidates for add_team_member, scoped to the current active tenant and exact add capability; the command revalidates on mutation.';
