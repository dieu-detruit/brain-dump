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
