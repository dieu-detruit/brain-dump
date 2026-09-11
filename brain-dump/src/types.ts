export type Delegation = 'ai' | 'colleague' | null

export interface Thread {
  id: string
  title: string
  delegation: Delegation
  priority: number
  created_at: string
  updated_at: string
}

export interface BrainState {
  threads: Thread[]
  executingThreadId: string | null
}

export interface ExecutionSession {
  id: number
  thread_id: string
  thread_title: string
  started_at: string
  last_confirmed_at: string
  ended_at: string | null
}

export interface ChangeLog {
  id: number
  entity_type: 'thread' | 'brain_state'
  entity_id: string
  operation: 'insert' | 'update' | 'delete'
  changed_at: string
  before_data: Record<string, unknown> | null
  after_data: Record<string, unknown> | null
}
