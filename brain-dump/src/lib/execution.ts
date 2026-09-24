import type { BrainState, Thread } from '../types'
export interface ExecutionSnapshot {
  server_time: string
  threads: {id:string;title:string;delegation:'ai'|'colleague'|null;priority:number}[]
  active: {session_id:string;confirmation_revision:string;thread_id:string;last_confirmed_at:string;deadline:string}|null
}
export interface ExecutionCommand {
  operation_id:string;action:'confirm'|'switch'
  expected:{session_id:string;confirmation_revision:string}|null
  target_thread_id?:string|null
}
export interface ExecutionResult {status:'applied'|'stale'|'expired';snapshot:ExecutionSnapshot}
export function stateFromSnapshot(snapshot:ExecutionSnapshot):BrainState {
  return {threads:snapshot.threads.map(t=>({...t,created_at:'',updated_at:''}) as Thread),executingThreadId:snapshot.active?.thread_id??null}
}
export function expectedFromSnapshot(snapshot:ExecutionSnapshot) {
  return snapshot.active?{session_id:snapshot.active.session_id,confirmation_revision:snapshot.active.confirmation_revision}:null
}
export function executionCommand(action:ExecutionCommand['action'],snapshot:ExecutionSnapshot,target?:string|null):ExecutionCommand {
  return {operation_id:crypto.randomUUID(),action,expected:expectedFromSnapshot(snapshot),...(action==='switch'?{target_thread_id:target??null}:{})}
}
