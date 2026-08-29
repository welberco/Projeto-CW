-- Permite que cada usuário atualize somente o próprio nome e loja
drop function if exists public.atualizar_meu_perfil(text,text);
create or replace function public.atualizar_meu_perfil(novo_nome text,novo_email text,nova_loja text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if nullif(trim(novo_nome),'') is null then raise exception 'Nome obrigatório'; end if;
  update public.perfis set nome=trim(novo_nome),email=trim(novo_email),loja=nullif(trim(nova_loja),'') where id=auth.uid() and ativo;
  if not found then raise exception 'Perfil ativo não encontrado'; end if;
end; $$;
revoke all on function public.atualizar_meu_perfil(text,text,text) from public;
grant execute on function public.atualizar_meu_perfil(text,text,text) to authenticated;
