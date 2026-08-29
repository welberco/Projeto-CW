import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors})
  try {
    const url=Deno.env.get('SUPABASE_URL')!, anon=Deno.env.get('SUPABASE_ANON_KEY')!, service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const token=req.headers.get('Authorization')||''
    const caller=createClient(url,anon,{global:{headers:{Authorization:token}}})
    const {data:allowed,error:permissionError}=await caller.rpc('tem_permissao_usuario',{acao_consultada:'gerenciar_usuarios'})
    if(permissionError||!allowed) throw new Error('Sem permissão para gerenciar usuários')
    const body=await req.json(), admin=createClient(url,service)
    if(body.action==='create'){
      const {data,error}=await admin.auth.admin.createUser({email:body.email,password:body.password,email_confirm:true,user_metadata:{nome:body.nome,papel:body.papel||'lojista'}})
      if(error)throw error
      if(body.loja)await admin.from('perfis').update({loja:body.loja}).eq('id',data.user.id)
      return new Response(JSON.stringify({user_id:data.user.id}),{headers:{...cors,'Content-Type':'application/json'}})
    }
    throw new Error('Ação inválida')
  } catch(error){return new Response(JSON.stringify({error:error.message}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
})
