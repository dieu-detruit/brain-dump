import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Bot, CircleUserRound, LogOut, Moon, Pencil, Plus, Trash2, UserRound, X } from 'lucide-react'
import type { Session } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from './lib/supabase'
import { loadLocal, saveLocal } from './lib/localStore'
import type { BrainState, Delegation, Thread } from './types'

const emptyState: BrainState = { threads: [], executingThreadId: null }

function delegationLabel(value: Delegation) {
  return value === 'ai' ? 'AI' : value === 'colleague' ? '他の人' : '寝かせる'
}

function DelegationIcon({ value, size = 18 }: { value: Delegation; size?: number }) {
  if (value === 'ai') return <Bot size={size} strokeWidth={1.8} />
  if (value === 'colleague') return <UserRound size={size} strokeWidth={1.8} />
  return <Moon size={size} strokeWidth={1.8} />
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [authReady, setAuthReady] = useState(!isSupabaseConfigured)
  const [state, setState] = useState<BrainState>(() => isSupabaseConfigured ? emptyState : loadLocal())
  const [title, setTitle] = useState('')
  const [delegation, setDelegation] = useState<Delegation>(null)
  const [adding, setAdding] = useState(false)
  const [loading, setLoading] = useState(isSupabaseConfigured)
  const [error, setError] = useState<string | null>(null)

  const userId = session?.user.id

  const fetchState = useCallback(async () => {
    if (!supabase || !userId) return
    const [{ data: threads, error: threadError }, { data: appState, error: stateError }] = await Promise.all([
      supabase.from('threads').select('id,title,delegation,created_at,updated_at').order('created_at'),
      supabase.from('brain_state').select('executing_thread_id').maybeSingle(),
    ])
    if (threadError || stateError) setError(threadError?.message ?? stateError?.message ?? '読み込めませんでした')
    else setState({ threads: (threads ?? []) as Thread[], executingThreadId: appState?.executing_thread_id ?? null })
    setLoading(false)
  }, [userId])

  useEffect(() => {
    if (!supabase) return
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setAuthReady(true) })
    const { data } = supabase.auth.onAuthStateChange((_event, next) => { setSession(next); setAuthReady(true) })
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!isSupabaseConfigured) saveLocal(state)
  }, [state])

  useEffect(() => {
    if (!supabase || !userId) return
    setLoading(true)
    void fetchState()
    const channel = supabase.channel(`brain-dump-${userId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'threads', filter: `user_id=eq.${userId}` }, fetchState)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'brain_state', filter: `user_id=eq.${userId}` }, fetchState)
      .subscribe()
    return () => { void supabase?.removeChannel(channel) }
  }, [fetchState, userId])

  const sleeping = state.threads.filter(t => t.delegation === null)
  const delegated = state.threads.filter(t => t.delegation !== null)

  async function addThread(event: FormEvent) {
    event.preventDefault()
    const trimmed = title.trim()
    if (!trimmed) return
    setError(null)
    if (supabase && userId) {
      const { error: insertError } = await supabase.from('threads').insert({ title: trimmed, delegation, user_id: userId })
      if (insertError) { setError(insertError.message); return }
    } else {
      const now = new Date().toISOString()
      setState(previous => ({ ...previous, threads: [...previous.threads, { id: crypto.randomUUID(), title: trimmed, delegation, created_at: now, updated_at: now }] }))
    }
    setTitle('')
    setAdding(false)
  }

  async function execute(id: string | null) {
    const nextId = state.executingThreadId === id ? null : id
    setState(previous => ({ ...previous, executingThreadId: nextId }))
    if (supabase && userId) {
      const { error: updateError } = await supabase.from('brain_state').upsert({ user_id: userId, executing_thread_id: nextId })
      if (updateError) { setError(updateError.message); void fetchState() }
    }
  }

  async function remove(thread: Thread) {
    setState(previous => ({ threads: previous.threads.filter(t => t.id !== thread.id), executingThreadId: previous.executingThreadId === thread.id ? null : previous.executingThreadId }))
    if (supabase && userId) {
      const { error: deleteError } = await supabase.from('threads').delete().eq('id', thread.id)
      if (deleteError) { setError(deleteError.message); void fetchState() }
    }
  }

  async function updateThread(thread: Thread, nextTitle: string, nextDelegation: Delegation) {
    const trimmed = nextTitle.trim()
    if (!trimmed || (trimmed === thread.title && nextDelegation === thread.delegation)) return
    const updatedAt = new Date().toISOString()
    setState(previous => ({
      ...previous,
      threads: previous.threads.map(item => item.id === thread.id ? { ...item, title: trimmed, delegation: nextDelegation, updated_at: updatedAt } : item),
    }))
    if (supabase && userId) {
      const { error: updateError } = await supabase.from("threads").update({ title: trimmed, delegation: nextDelegation }).eq("id", thread.id)
      if (updateError) { setError(updateError.message); void fetchState() }
    }
  }

  async function signIn() {
    if (!supabase) return
    await supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: new URL('/', window.location.origin).toString() } })
  }

  if (!authReady) return <main className="center"><div className="pulse">●</div></main>
  if (isSupabaseConfigured && !session) return (
    <main className="login">
      <div className="login-mark"><span /></div>
      <p className="eyebrow">BRAIN DUMP</p>
      <h1>頭の中に、<br />余白をつくる。</h1>
      <p className="login-copy">抱えていることをすべて置いて、<br />今やるひとつだけを選びます。</p>
      <button className="google-button" onClick={signIn}><CircleUserRound size={20} /> Googleで続ける</button>
    </main>
  )

  return (
    <main className="app-shell">
      <header>
        <div><p className="eyebrow">BRAIN DUMP</p></div>
        <div className="header-actions">
          {!isSupabaseConfigured && <span className="demo-badge">この端末に保存</span>}
          {session && <button className="icon-button" aria-label="ログアウト" onClick={() => supabase?.auth.signOut()}><LogOut size={19} /></button>}
        </div>
      </header>

      <p className="execution-principle">THINK WIDE. <strong>EXECUTE ONE THREAD.</strong></p>

      {error && <div className="error-banner">{error}<button onClick={() => setError(null)}><X size={16} /></button></div>}


      <div className="toolbar">
        <div><span className="count">{state.threads.length}</span><span className="muted"> threads</span></div>
        <button className="add-button" onClick={() => setAdding(true)}><Plus size={20} /> スレッドを置く</button>
      </div>

      {adding && (
        <form className="composer" onSubmit={addThread}>
          <input autoFocus value={title} onChange={e => setTitle(e.target.value)} placeholder="何を頭から出しますか？" aria-label="スレッド名" />
          <aside className="new-thread-checklist" aria-labelledby="new-thread-checklist-title">
            <p id="new-thread-checklist-title">IS THIS A NEW THREAD?</p>
            <ul>
              <li>既存のThreadとは異なる成果を目指している？</li>
              <li>ほかのThreadと独立して進められる？</li>
              <li>比較するだけの分岐ではなく、進むと決めた方向？</li>
              <li>今進められる実行者に任せている？</li>
            </ul>
          </aside>
          <div className="composer-footer">
          <div className="delegation-picker">
            {([null, 'ai', 'colleague'] as Delegation[]).map(value => (
              <button type="button" key={value ?? 'sleep'} className={delegation === value ? 'selected' : ''} onClick={() => setDelegation(value)} aria-label={delegationLabel(value)} title={delegationLabel(value)}>
                <DelegationIcon value={value} size={25} />
              </button>
            ))}
          </div>
          <div className="composer-actions"><button type="button" className="text-button" onClick={() => setAdding(false)}>キャンセル</button><button className="save-button">追加する</button></div>
          </div>
        </form>
      )}

      {loading ? <div className="loading">読み込んでいます…</div> : (
        <div className="thread-groups">
          <ThreadGroup title="待機中" caption="まだ誰にも渡していない" threads={sleeping} activeId={state.executingThreadId} onExecute={execute} onUpdate={updateThread} onRemove={remove} />
          <ThreadGroup title="進行中" caption="AI・他の人に任せている" threads={delegated} activeId={state.executingThreadId} onExecute={execute} onUpdate={updateThread} onRemove={remove} />
          {!state.threads.length && <div className="empty-list"><Moon size={32} /><p>頭の中は空っぽです。</p><span>新しいスレッドを置いてみましょう。</span></div>}
        </div>
      )}
    </main>
  )
}

function ThreadGroup({ title, caption, threads, activeId, onExecute, onUpdate, onRemove }: { title: string; caption: string; threads: Thread[]; activeId: string | null; onExecute: (id: string) => void; onUpdate: (thread: Thread, title: string, delegation: Delegation) => void; onRemove: (thread: Thread) => void }) {
  const [editingThread, setEditingThread] = useState<Thread | null>(null)
  if (!threads.length) return null
  return <section className="thread-group">
    <div className="group-title"><h2>{title}</h2><span>{caption}</span></div>
    <div className="thread-list">{threads.map(thread => (
      <article className={`thread-card ${activeId === thread.id ? "active" : ""}`} key={thread.id}>
        <button className="magnet" onClick={() => onExecute(thread.id)} aria-label={`${thread.title}を自分が実行する`}><span /></button>
        <button className="thread-info title-button" onClick={() => setEditingThread(thread)} aria-label={`${thread.title}を編集`}>
          <h3>{thread.title}</h3><Pencil className="edit-icon" size={15} aria-hidden="true" />
        </button>
        <div className={`delegation ${thread.delegation ?? "sleep"}`} role="img" aria-label={delegationLabel(thread.delegation)} title={delegationLabel(thread.delegation)}><DelegationIcon value={thread.delegation} size={23} /></div>
        <button className="delete-button" onClick={() => onRemove(thread)} aria-label={`${thread.title}を削除`}><Trash2 size={17} /></button>
      </article>
    ))}</div>
    {editingThread && <EditThreadDialog key={editingThread.id} thread={editingThread} onClose={() => setEditingThread(null)} onSave={(nextTitle, nextDelegation) => { void onUpdate(editingThread, nextTitle, nextDelegation); setEditingThread(null) }} />}
  </section>
}

function EditThreadDialog({ thread, onClose, onSave }: { thread: Thread; onClose: () => void; onSave: (title: string, delegation: Delegation) => void }) {
  const [value, setValue] = useState(thread.title)
  const [nextDelegation, setNextDelegation] = useState<Delegation>(thread.delegation)

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) onClose() }}>
      <form className="edit-dialog" role="dialog" aria-modal="true" aria-labelledby="edit-dialog-title" onSubmit={event => { event.preventDefault(); if (value.trim()) onSave(value.trim(), nextDelegation) }} onKeyDown={event => { if (event.key === "Escape") onClose() }}>
        <div className="dialog-heading"><h2 id="edit-dialog-title">スレッドを編集</h2><button type="button" className="icon-button" onClick={onClose} aria-label="閉じる"><X size={19} /></button></div>
        <label className="field-label" htmlFor="edit-title">タイトル</label>
        <input id="edit-title" className="dialog-title-input" autoFocus value={value} maxLength={500} onChange={event => setValue(event.target.value)} />
        <span className="field-label">任せ先</span>
        <div className="dialog-delegation-picker">
          {([null, "ai", "colleague"] as Delegation[]).map(option => (
            <button type="button" key={option ?? "sleep"} className={nextDelegation === option ? "selected" : ""} onClick={() => setNextDelegation(option)} aria-label={delegationLabel(option)} title={delegationLabel(option)}>
              <DelegationIcon value={option} size={27} />
            </button>
          ))}
        </div>
        <div className="dialog-actions"><button type="button" className="text-button" onClick={onClose}>キャンセル</button><button className="save-button" disabled={!value.trim()}>保存する</button></div>
      </form>
    </div>
  )
}
