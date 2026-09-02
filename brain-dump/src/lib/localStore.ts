import type { BrainState } from '../types'

const key = 'brain-dump-state-v1'
const initial: BrainState = {
  executingThreadId: null,
  threads: [
    { id: crypto.randomUUID(), title: 'Brain Dumpを触ってみる', delegation: null, priority: 1024, created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
    { id: crypto.randomUUID(), title: '次に任せたいことを考える', delegation: 'ai', priority: 2048, created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
  ],
}

export function loadLocal(): BrainState {
  try {
    const state = JSON.parse(localStorage.getItem(key) ?? '') as BrainState
    return {
      ...state,
      threads: state.threads.map((thread, index) => ({ ...thread, priority: thread.priority ?? (index + 1) * 1024 })),
    }
  } catch { return initial }
}
export function saveLocal(state: BrainState) { localStorage.setItem(key, JSON.stringify(state)) }
