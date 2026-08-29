import type { BrainState } from '../types'

const key = 'brain-dump-state-v1'
const initial: BrainState = {
  executingThreadId: null,
  threads: [
    { id: crypto.randomUUID(), title: 'Brain Dumpを触ってみる', delegation: null, created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
    { id: crypto.randomUUID(), title: '次に任せたいことを考える', delegation: 'ai', created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
  ],
}

export function loadLocal(): BrainState {
  try { return JSON.parse(localStorage.getItem(key) ?? '') as BrainState } catch { return initial }
}
export function saveLocal(state: BrainState) { localStorage.setItem(key, JSON.stringify(state)) }
