import {supabase} from '../../lib/supabase'
export async function watchApi<T>(path:string,method='GET',body?:unknown):Promise<T> {
  const {data}=await supabase!.auth.getSession()
  if(!data.session)throw new Error('もう一度ログインしてください')
  const response=await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/watch-api${path}`,{
    method,headers:{Authorization:`Bearer ${data.session.access_token}`,'Content-Type':'application/json'},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000),
  })
  if(!response.ok)throw new Error(response.status===429?'しばらく待ってから試してください':response.status===400?'コードと有効期限を確認してください':'Watchの設定を更新できませんでした')
  return response.json()
}
