-- CW Manutenção - edição e exclusão somente pelo criador ou administrador
drop policy if exists "usuario atualiza demandas da organizacao" on public.demandas;
create policy "criador ou administrador atualiza demanda" on public.demandas for update to authenticated
using (criado_por = auth.uid() or exists (select 1 from public.perfis p where p.id = auth.uid() and p.organizacao_id = demandas.organizacao_id and p.papel = 'administrador'))
with check (criado_por = auth.uid() or exists (select 1 from public.perfis p where p.id = auth.uid() and p.organizacao_id = demandas.organizacao_id and p.papel = 'administrador'));

drop policy if exists "usuario exclui os proprios anexos" on public.anexos_demandas;
create policy "criador ou administrador exclui anexo" on public.anexos_demandas for delete to authenticated
using (criado_por = auth.uid() or exists (select 1 from public.demandas d join public.perfis p on p.organizacao_id = d.organizacao_id where d.id = anexos_demandas.demanda_id and p.id = auth.uid() and p.papel = 'administrador'));

drop policy if exists "usuario exclui os proprios arquivos" on storage.objects;
create policy "criador ou administrador exclui arquivo" on storage.objects for delete to authenticated
using (bucket_id = 'cw-anexos' and (owner_id = auth.uid()::text or exists (select 1 from public.demandas d join public.perfis p on p.organizacao_id = d.organizacao_id where d.id = ((storage.foldername(name))[1])::bigint and p.id = auth.uid() and p.papel = 'administrador')));

revoke update on public.perfis from authenticated;
grant update (nome) on public.perfis to authenticated;
