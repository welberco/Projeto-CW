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
    const papel = body.papel || 'lojista'
    const { data: allowed, error: allowedError } = await caller.rpc('cw_pode_gerenciar_usuario', {
      p_org: org, p_usuario: target?.id || null, p_papel: papel,
    })
    if (allowedError || allowed !== true) throw new Error('Sem permissão para gerenciar este usuário ou empreendimento')
    const nome = String(body.nome || '').trim()
    const email = String(body.email || '').trim()
    if (!nome || !email.includes('@')) throw new Error('Nome e e-mail são obrigatórios')
    const aprovacao = body.action === 'create' ? 'aprovado' : body.aprovacao
    const ativo = body.action === 'create' ? true : body.ativo
    if (!['pendente', 'aprovado', 'rejeitado'].includes(aprovacao) || typeof ativo !== 'boolean') throw new Error('Aprovação/acesso inválidos')
    if (target?.id === actor.id && (papel !== actor.papel || !ativo || aprovacao !== 'aprovado')) throw new Error('Não altere seu próprio perfil ou acesso')
    let userId = target?.id
    if (body.action === 'create') {
      if (typeof body.password !== 'string' || body.password.length < 8) throw new Error('Senha provisória deve ter ao menos 8 caracteres')
      const { data, error } = await admin.auth.admin.createUser({
        email, password: body.password, email_confirm: true,
        user_metadata: { nome, organizacao_id: org },
      })
      if (error) throw error
      userId = data.user.id
    } else if (email !== target.email) {
      const { error } = await admin.auth.admin.updateUserById(userId, { email, email_confirm: true })
      if (error) throw error
    }
    const { error: profileError } = await caller.rpc('cw_salvar_usuario', {
      p_usuario: userId, p_nome: nome, p_email: email, p_loja: String(body.loja || ''),
      p_papel: papel, p_ativo: ativo, p_aprovacao: aprovacao,
    })
    if (profileError) {
      // Conta nova permanece pendente/inativa; nunca liberar acesso após falha parcial.
      throw new Error(body.action === 'create'
        ? 'Conta criada, mas permanece pendente. Abra o perfil e conclua a aprovação. ' + profileError.message
        : 'Não foi possível concluir a atualização do perfil. ' + profileError.message)
    }
    return new Response(JSON.stringify({ user_id: userId, updated: true }), { headers: cors })
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Erro inesperado' }), { status: 400, headers: cors })
  }
})
