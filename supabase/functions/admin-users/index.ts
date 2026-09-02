import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Método não permitido' }), { status: 405, headers: cors })
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } }, auth: { persistSession: false } })
    const { data: identity, error: identityError } = await caller.auth.getUser()
    if (identityError || !identity.user) throw new Error('Sessão inválida')
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } })
    const body = await req.json()
    if (!['create', 'update'].includes(body.action)) throw new Error('Ação inválida')
    const { data: actor, error: actorError } = await caller.from('perfis').select('*').eq('id', identity.user.id).single()
    if (actorError || !actor?.ativo || actor.aprovacao !== 'aprovado') throw new Error('Acesso não aprovado')
    let target = null
    if (body.action === 'update') {
      // Leitura com JWT do solicitante, nunca com bypass de RLS.
      const { data, error } = await caller.from('perfis').select('*').eq('id', body.user_id).single()
      if (error || !data) throw new Error('Usuário não encontrado ou sem acesso')
      target = data
    }
    const org = target?.organizacao_id || (actor.papel === 'administrador' ? body.organizacao_id : actor.organizacao_id)
    const papel = body.papel || 'usuario_padrao'
    const { data: allowed, error: allowedError } = await caller.rpc('cw_pode_gerenciar_usuario', {
      p_org: org, p_usuario: target?.id || null, p_papel: papel,
    })
    if (allowedError || allowed !== true) throw new Error('Sem permissão para gerenciar este usuário ou empreendimento')
    const nome = String(body.nome || '').trim()
    const email = String(body.email || '').trim()
    const operationId = body.operacao_id ? Number(body.operacao_id) : null
    if (!nome || !email.includes('@')) throw new Error('Nome e e-mail são obrigatórios')
    if (operationId !== null && (!Number.isInteger(operationId) || operationId <= 0)) throw new Error('Operação inválida')
    let operation = null
    if (operationId !== null) {
      const result = await caller.from('operacoes').select('id,nome').eq('id', operationId).eq('organizacao_id', org).eq('ativo', true).single()
      if (result.error || !result.data) throw new Error('Operação não encontrada neste empreendimento')
      operation = result.data
    }
    const aprovacao = body.action === 'create' ? 'aprovado' : body.aprovacao
    const ativo = body.action === 'create' ? true : body.ativo
    if (!['pendente', 'aprovado', 'rejeitado'].includes(aprovacao) || typeof ativo !== 'boolean') throw new Error('Aprovação/acesso inválidos')
    if (target?.id === actor.id && (papel !== actor.papel || !ativo || aprovacao !== 'aprovado')) throw new Error('Não altere seu próprio perfil ou acesso')
    let userId = target?.id
    if (body.action === 'create') {
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { nome, organizacao_id: org },
        redirectTo: body.redirect_to || undefined,
      })
      if (error) throw error
      userId = data.user.id
    } else if (email !== target.email) {
      const { error } = await admin.auth.admin.updateUserById(userId, { email, email_confirm: true })
      if (error) throw error
    }
    const { error: profileError } = await caller.rpc('cw_salvar_usuario', {
      p_usuario: userId, p_nome: nome, p_email: email, p_loja: operation?.nome || '',
      p_papel: papel, p_ativo: ativo, p_aprovacao: aprovacao,
    })
    if (profileError) {
      // Conta nova permanece pendente/inativa; nunca liberar acesso após falha parcial.
      throw new Error(body.action === 'create'
        ? 'Conta criada, mas permanece pendente. Abra o perfil e conclua a aprovação. ' + profileError.message
        : 'Não foi possível concluir a atualização do perfil. ' + profileError.message)
    }
    const { error: unlinkError } = await caller.from('usuario_operacoes').delete().eq('usuario_id', userId)
    if (unlinkError) throw new Error('Perfil salvo, mas não foi possível atualizar a operação. ' + unlinkError.message)
    if (operationId !== null) {
      const { error: linkError } = await caller.from('usuario_operacoes').insert({ usuario_id: userId, operacao_id: operationId, principal: true })
      if (linkError) throw new Error('Perfil salvo, mas não foi possível vincular a operação. ' + linkError.message)
    }
    return new Response(JSON.stringify({ user_id: userId, updated: true }), { headers: cors })
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Erro inesperado' }), { status: 400, headers: cors })
  }
})
