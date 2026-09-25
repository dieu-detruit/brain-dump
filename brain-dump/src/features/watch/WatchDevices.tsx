import {useEffect,useState,type FormEvent} from 'react'
import {watchApi} from './watchApi'
interface Device {id:string;created_at:string;notifications_enabled:boolean}
export function WatchDevices({onClose}:{onClose:()=>void}) {
 const [devices,setDevices]=useState<Device[]>([])
 const [code,setCode]=useState('')
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState<string|null>(null)
 const [message,setMessage]=useState<string|null>(null)
 useEffect(()=>{let active=true;watchApi<{devices:Device[]}>('/devices').then(d=>{if(active)setDevices(d.devices)}).catch(e=>{if(active)setError(e.message)});return()=>{active=false}},[])
 async function perform(action:()=>Promise<unknown>){
   if(busy)return;setBusy(true);setError(null);setMessage(null)
   try{await action();setDevices((await watchApi<{devices:Device[]}>('/devices')).devices)}
   catch(e){setError(e instanceof Error?e.message:'更新できませんでした')}finally{setBusy(false)}
 }
 async function approve(e:FormEvent){e.preventDefault();await perform(async()=>{await watchApi('/pairings/approve','POST',{code});setCode('');setMessage('Watchを接続しました。Watchで通知を許可してください。')})}
 return <div className="dialog-backdrop"><section className="edit-dialog watch-devices" role="dialog" aria-modal="true" aria-labelledby="watch-title">
  <div className="dialog-heading"><h2 id="watch-title">Apple Watch</h2><button className="text-button" onClick={onClose}>閉じる</button></div>
  <p>初回だけ、Watchに表示された8桁のコードを入力して、このアカウントと接続します。</p>
  <form onSubmit={approve}><label>接続コード<input autoFocus inputMode="numeric" autoComplete="off" pattern="[0-9]{8}" maxLength={8} value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,''))}/></label><button className="save-button" disabled={busy||code.length!==8}>接続する</button></form>
  {error&&<p role="alert">{error}</p>}{message&&<p role="status">{message}</p>}
  <h3>接続したWatch</h3>
  {devices.length===0?<p>接続済みのWatchはありません。</p>:<ul>{devices.map(d=><li key={d.id}><span>{new Date(d.created_at).toLocaleDateString()} 接続<br/>{d.notifications_enabled?'通知登録済み':'Watchで通知設定を確認してください'}</span><button className="text-button" disabled={busy} onClick={()=>perform(()=>watchApi(`/devices/${d.id}`,'DELETE'))}>解除する</button></li>)}</ul>}
 </section></div>
}
