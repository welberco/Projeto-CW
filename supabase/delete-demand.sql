-- Exclusão de demanda controlada pela matriz de permissões
update public.permissoes_perfis
set permitido=false,atualizado_em=now()
where acao='apagar_demanda' and papel in ('gestor_manutencao','tecnico','lojista');

drop policy if exists "permissao apaga demanda" on public.demandas;
create policy "permissao apaga demanda" on public.demandas for delete to authenticated
using (public.tem_permissao_usuario('apagar_demanda'));

drop policy if exists "permissao exclui arquivo" on storage.objects;
create policy "permissao exclui arquivo" on storage.objects for delete to authenticated
using (
  bucket_id='cw-anexos'
  and (public.tem_permissao_usuario('excluir_midia') or public.tem_permissao_usuario('apagar_demanda'))
  and public.pode_visualizar_demanda(((storage.foldername(name))[1])::bigint)
);
