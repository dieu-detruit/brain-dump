export type Delegation = 'ai' | 'colleague' | null

export interface Thread {
  id: string
  title: string
  delegation: Delegation
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
  ended_at: string | null
}
