-- Garante que todo empreendimento novo receba cadastros e permissões padrão.
begin;

drop trigger if exists cw_inicializar_matriz_organizacao on public.organizacoes;
create trigger cw_inicializar_matriz_organizacao
after insert on public.organizacoes
for each row execute function public.cw_inicializar_matriz();

insert into public.permissoes_perfis(organizacao_id,papel,acao,permitido)
select o.id,r.papel,a.acao,case
  when r.papel='auxiliar' then a.acao in ('solicitacao_visualizar_todas','solicitacao_criar','solicitacao_editar','solicitacao_alterar_status','os_visualizar_todas','os_criar','os_editar','os_concluir','os_aceitar','ativos_visualizar','prestadores_visualizar','prestadores_editar','relatorios_emitir','custos_visualizar','custos_editar')
  when r.papel='tecnico' then a.acao in ('solicitacao_visualizar_todas','os_visualizar_todas','ativos_visualizar','historico_visualizar')
  else a.acao in ('solicitacao_criar','solicitacao_visualizar_proprias','solicitacao_editar_proprias','os_visualizar_resumo','os_aceitar','galeria_visualizar') end
from public.organizacoes o
cross join (values('auxiliar'),('tecnico'),('usuario_padrao')) r(papel)
cross join (values
  ('solicitacao_visualizar_todas'),('solicitacao_visualizar_proprias'),('solicitacao_criar'),('solicitacao_editar'),('solicitacao_editar_proprias'),('solicitacao_alterar_status'),('solicitacao_excluir'),
  ('os_visualizar_todas'),('os_visualizar_resumo'),('os_criar'),('os_editar'),('os_concluir'),('os_cancelar'),('os_aceitar'),
  ('ativos_visualizar'),('ativos_editar'),('planos_editar'),('prestadores_visualizar'),('prestadores_editar'),('usuarios_gerenciar'),('configuracoes_editar'),
  ('relatorios_emitir'),('custos_visualizar'),('custos_editar'),('historico_visualizar'),('galeria_visualizar'),('galeria_excluir')
) a(acao)
on conflict(organizacao_id,papel,acao) do nothing;

insert into public.prioridades(organizacao_id,nome,ordem)
select o.id,v.nome,v.ordem from public.organizacoes o cross join (values('A definir',0),('Baixa',1),('Média',2),('Alta',3),('Urgente',4)) v(nome,ordem)
on conflict(organizacao_id,nome) do nothing;

insert into public.naturezas_servico(organizacao_id,nome)
select o.id,v.nome from public.organizacoes o cross join (values('Corretiva'),('Preventiva'),('Preditiva'),('Inspeção'),('Instalação'),('Adequação'),('Emergencial'),('Outro')) v(nome)
on conflict(organizacao_id,nome) do nothing;

insert into public.tipos_servico(organizacao_id,nome)
select o.id,v.nome from public.organizacoes o cross join (values('Elétrica'),('Hidráulica'),('Pintura'),('Civil'),('Impermeabilização'),('Climatização'),('Serralheria'),('Marcenaria'),('Segurança'),('Elevadores'),('Jardinagem'),('Limpeza'),('Outros')) v(nome)
on conflict(organizacao_id,nome) do nothing;

commit;
