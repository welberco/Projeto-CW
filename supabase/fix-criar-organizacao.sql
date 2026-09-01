-- Corrige a criação de empreendimentos sem flexibilizar o RLS.
-- Somente um Administrador global ativo e aprovado pode executar esta função.
begin;

create or replace function public.cw_inicializar_matriz()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.permissoes_perfis(organizacao_id,papel,acao,permitido)
  select new.id,r.papel,a.acao,case
    when r.papel='auxiliar' then a.acao in ('solicitacao_visualizar_todas','solicitacao_criar','solicitacao_editar','solicitacao_alterar_status','os_visualizar_todas','os_criar','os_editar','os_concluir','os_aceitar','ativos_visualizar','prestadores_visualizar','prestadores_editar','relatorios_emitir','custos_visualizar','custos_editar')
    when r.papel='tecnico' then a.acao in ('solicitacao_visualizar_todas','os_visualizar_todas','ativos_visualizar','historico_visualizar')
    else a.acao in ('solicitacao_criar','solicitacao_visualizar_proprias','solicitacao_editar_proprias','os_visualizar_resumo','os_aceitar','galeria_visualizar') end
  from (values('auxiliar'),('tecnico'),('usuario_padrao')) r(papel)
  cross join (values
    ('solicitacao_visualizar_todas'),('solicitacao_visualizar_proprias'),('solicitacao_criar'),('solicitacao_editar'),('solicitacao_editar_proprias'),('solicitacao_alterar_status'),('solicitacao_excluir'),
    ('os_visualizar_todas'),('os_visualizar_resumo'),('os_criar'),('os_editar'),('os_concluir'),('os_cancelar'),('os_aceitar'),
    ('ativos_visualizar'),('ativos_editar'),('planos_editar'),('prestadores_visualizar'),('prestadores_editar'),('usuarios_gerenciar'),('configuracoes_editar'),
    ('relatorios_emitir'),('custos_visualizar'),('custos_editar'),('historico_visualizar'),('galeria_visualizar'),('galeria_excluir')
  ) a(acao)
  on conflict(organizacao_id,papel,acao) do nothing;

  insert into public.prioridades(organizacao_id,nome,ordem)
  select new.id,v.nome,v.ordem from (values('A definir',0),('Baixa',1),('Média',2),('Alta',3),('Urgente',4)) v(nome,ordem)
  on conflict(organizacao_id,nome) do nothing;

  insert into public.naturezas_servico(organizacao_id,nome)
  select new.id,v.nome from (values('Corretiva'),('Preventiva'),('Preditiva'),('Inspeção'),('Instalação'),('Adequação'),('Emergencial'),('Outro')) v(nome)
  on conflict(organizacao_id,nome) do nothing;

  insert into public.tipos_servico(organizacao_id,nome)
  select new.id,v.nome from (values('Elétrica'),('Hidráulica'),('Pintura'),('Civil'),('Impermeabilização'),('Climatização'),('Serralheria'),('Marcenaria'),('Segurança'),('Elevadores'),('Jardinagem'),('Limpeza'),('Outros')) v(nome)
  on conflict(organizacao_id,nome) do nothing;

  return new;
end;
$$;

create or replace function public.cw_criar_organizacao(p_nome text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  novo_id uuid;
  nome_limpo text := nullif(trim(p_nome), '');
begin
  if auth.uid() is null or not public.cw_admin() then
    raise exception 'Apenas o Administrador pode cadastrar empreendimentos';
  end if;

  if nome_limpo is null then
    raise exception 'Informe o nome do empreendimento';
  end if;

  insert into public.organizacoes(nome)
  values (nome_limpo)
  returning id into novo_id;

  return novo_id;
end;
$$;

revoke all on function public.cw_criar_organizacao(text) from public, anon;
grant execute on function public.cw_criar_organizacao(text) to authenticated;

commit;
