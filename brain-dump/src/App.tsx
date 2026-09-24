import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react'
import { BarChart3, Bot, CircleUserRound, GripVertical, LogOut, Moon, Pencil, Plus, Trash2, UserRound, X } from 'lucide-react'
import type { Session } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from './lib/supabase'
import { loadLocal, saveLocal } from './lib/localStore'
import { WatchDevices } from './features/watch/WatchDevices'
import { executionCommand, stateFromSnapshot, type ExecutionSnapshot, type ExecutionResult } from './lib/execution'
import type { BrainState, ChangeLog, Delegation, ExecutionSession, Thread } from './types'

const emptyState: BrainState = { threads: [], executingThreadId: null }
const confirmationInterval = 60 * 60 * 1000
const confirmationWarning = 5 * 60 * 1000

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
  const [addingThread, setAddingThread] = useState(false)
  const [loading, setLoading] = useState(isSupabaseConfigured)
  const [historyLoading, setHistoryLoading] = useState(false)
  const [historyOpen, setHistoryOpen] = useState(false)
  const [watchOpen, setWatchOpen] = useState(false)
  const [snapshot, setSnapshot] = useState<ExecutionSnapshot | null>(null)
  const commandBusy = useRef(false)
  const requestSequence = useRef(0)
  const historySequence = useRef(0)
  const authUserRef = useRef<string | null>(null)
  const [clockOffset, setClockOffset] = useState(0)
  const [sessions, setSessions] = useState<ExecutionSession[]>([])
  const [changes, setChanges] = useState<ChangeLog[]>([])
  const [error, setError] = useState<string | null>(null)
  const [lastConfirmedAt, setLastConfirmedAt] = useState<number | null>(null)
  const [confirmationOpen, setConfirmationOpen] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const addingThreadRef = useRef(false)

  const userId = session?.user.id

  const acceptSnapshot = useCallback((next: ExecutionSnapshot) => {
    setSnapshot(next)
    setState(stateFromSnapshot(next))
    setClockOffset(new Date(next.server_time).getTime() - Date.now())
    setLastConfirmedAt(next.active ? new Date(next.active.last_confirmed_at).getTime() : null)
    setConfirmationOpen(Boolean(next.active && new Date(next.server_time).getTime() - new Date(next.active.last_confirmed_at).getTime() >= confirmationInterval - confirmationWarning))
  }, [])

  const fetchState = useCallback(async () => {
    if (!supabase || !userId) return
    const sequence = ++requestSequence.current
    const {data, error: fetchError} = await supabase.rpc('execution_snapshot')
    if (sequence !== requestSequence.current) return
    if (fetchError) setError(fetchError.message)
    else if (data) acceptSnapshot(data as ExecutionSnapshot)
    setLoading(false)
  }, [userId, acceptSnapshot])

  const fetchHistory = useCallback(async () => {
    if (!supabase || !userId) return
    setHistoryLoading(true)
    const sequence = ++historySequence.current
    const [{ data: sessionData, error: sessionError }, { data: changeData, error: changeError }] = await Promise.all([
      supabase.from('execution_sessions').select('id,thread_id,thread_title,started_at,last_confirmed_at,ended_at').order('started_at', { ascending: false }),
      supabase.from('change_log').select('id,entity_type,entity_id,operation,changed_at,before_data,after_data').order('changed_at', { ascending: false }).limit(100),
    ])
    if (sequence !== historySequence.current) return
    if (sessionError || changeError) setError(sessionError?.message ?? changeError?.message ?? '履歴を読み込めませんでした')
    else {
      setSessions((sessionData ?? []) as ExecutionSession[])
      setChanges((changeData ?? []) as ChangeLog[])
    }
    setHistoryLoading(false)
  }, [userId])

  useEffect(() => {
    if (!supabase) return
    const applySession = (next: Session | null) => {
      if (authUserRef.current !== (next?.user.id ?? null)) {
        authUserRef.current = next?.user.id ?? null
        ++requestSequence.current
        ++historySequence.current
        setSnapshot(null)
        setState(emptyState)
        setSessions([])
        setChanges([])
        setWatchOpen(false)
        setLastConfirmedAt(null)
        setConfirmationOpen(false)
        setError(null)
      }
      setSession(next)
      setAuthReady(true)
    }
    let receivedAuthEvent = false
    supabase.auth.getSession().then(({data}) => { if (!receivedAuthEvent) applySession(data.session) })
    const { data } = supabase.auth.onAuthStateChange((_event, next) => { receivedAuthEvent = true; applySession(next) })
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
      .on('postgres_changes', { event: '*', schema: 'public', table: 'execution_sessions', filter: `user_id=eq.${userId}` }, fetchState)
      .subscribe()
    return () => { void supabase?.removeChannel(channel) }
  }, [fetchState, userId])

  useEffect(() => {
    if (!supabase || !userId) return
    void fetchHistory()
    const channel = supabase.channel(`brain-dump-history-${userId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'execution_sessions', filter: `user_id=eq.${userId}` }, fetchHistory)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'change_log', filter: `user_id=eq.${userId}` }, fetchHistory)
      .subscribe()
    return () => { void supabase?.removeChannel(channel) }
  }, [fetchHistory, userId])

  const sleepUnconfirmedExecution = useCallback(async () => {
    if (!supabase || !userId) return
    setConfirmationOpen(false)
    const { error: sleepError } = await supabase.rpc('sleep_unconfirmed_execution')
    if (sleepError) { setError(sleepError.message); return }
    await fetchState()
    void fetchHistory()
  }, [fetchHistory, fetchState, userId])

  useEffect(() => {
    if (!state.executingThreadId || !lastConfirmedAt) return
    const elapsed = Date.now() + clockOffset - lastConfirmedAt
    if (elapsed >= confirmationInterval) { void sleepUnconfirmedExecution(); return }
    const warningTimer = confirmationOpen ? undefined : window.setTimeout(() => setConfirmationOpen(true), Math.max(0, confirmationInterval - confirmationWarning - elapsed))
    const sleepTimer = window.setTimeout(() => void sleepUnconfirmedExecution(), Math.max(0, confirmationInterval - elapsed))
    return () => { if (warningTimer) window.clearTimeout(warningTimer); window.clearTimeout(sleepTimer) }
  }, [confirmationOpen, lastConfirmedAt, sleepUnconfirmedExecution, state.executingThreadId, clockOffset])

  const sleeping = state.threads.filter(t => t.delegation === null)
  const delegated = state.threads.filter(t => t.delegation !== null)

  async function addThread(event: FormEvent) {
    event.preventDefault()
    if (addingThreadRef.current) return
    const trimmed = title.trim()
    if (!trimmed) return
    addingThreadRef.current = true
    setAddingThread(true)
    setError(null)
    try {
      if (supabase && userId) {
        const priority = Math.max(0, ...state.threads.map(thread => thread.priority)) + 1024
        const { error: insertError } = await supabase.from('threads').insert({ title: trimmed, delegation, priority, user_id: userId })
        if (insertError) { setError(insertError.message); return }
      } else {
        const now = new Date().toISOString()
        setState(previous => ({ ...previous, threads: [...previous.threads, { id: crypto.randomUUID(), title: trimmed, delegation, priority: Math.max(0, ...previous.threads.map(thread => thread.priority)) + 1024, created_at: now, updated_at: now }] }))
      }
      setTitle('')
      setAdding(false)
    } finally {
      addingThreadRef.current = false
      setAddingThread(false)
    }
  }

  async function runCommand(action: 'confirm' | 'switch', target?: string | null) {
    if (!supabase || !snapshot || commandBusy.current) return
    commandBusy.current = true
    setConfirming(true)
    setError(null)
    ++requestSequence.current
    try {
      const {data, error: commandError} = await supabase.rpc('apply_execution_command', {command: executionCommand(action, snapshot, target)})
      if (commandError) { setError(commandError.message); return }
      const result = data as ExecutionResult
      if (result.status !== 'applied') setError('実行状況が変わりました。最新の状態を確認してください。')
    } finally {
      await fetchState()
      void fetchHistory()
      commandBusy.current = false
      setConfirming(false)
    }
  }

  async function execute(id: string | null) {
    const nextId = state.executingThreadId === id ? null : id
    if (supabase && userId) await runCommand('switch', nextId)
    else setState(previous => ({...previous, executingThreadId: nextId}))
  }

  async function confirmExecution() { await runCommand('confirm') }

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

  async function reorderThreads(sourceId: string, targetId: string) {
    if (sourceId === targetId) return
    const ordered = [...state.threads].sort((a, b) => a.priority - b.priority)
    const sourceIndex = ordered.findIndex(thread => thread.id === sourceId)
    const targetIndex = ordered.findIndex(thread => thread.id === targetId)
    if (sourceIndex < 0 || targetIndex < 0) return
    const [moved] = ordered.splice(sourceIndex, 1)
    const nextIndex = ordered.findIndex(thread => thread.id === targetId)
    ordered.splice(nextIndex, 0, moved)
    const index = ordered.findIndex(thread => thread.id === sourceId)
    const before = ordered[index - 1]?.priority
    const after = ordered[index + 1]?.priority
    const priority = before === undefined ? (after ?? 1024) - 1024 : after === undefined ? before + 1024 : (before + after) / 2
    const updatedAt = new Date().toISOString()
    setState(previous => ({ ...previous, threads: previous.threads.map(thread => thread.id === sourceId ? { ...thread, priority, updated_at: updatedAt } : thread) }))
    if (supabase && userId) {
      const { error: updateError } = await supabase.from('threads').update({ priority }).eq('id', sourceId)
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
          {isSupabaseConfigured && <button className={`history-button ${historyOpen ? 'selected' : ''}`} onClick={() => setHistoryOpen(open => !open)}><BarChart3 size={18} /> 記録</button>}
          {session && <button className="text-button" onClick={() => setWatchOpen(true)}>Watch</button>}
          {session && <button className="icon-button" aria-label="ログアウト" onClick={() => supabase?.auth.signOut()}><LogOut size={19} /></button>}
        </div>
      </header>

      <p className="execution-principle">{historyOpen ? <>LOOK BACK. <strong>MAKE ROOM FOR WHAT MATTERS.</strong></> : <>THINK WIDE. <strong>EXECUTE ONE THREAD.</strong></>}</p>

      {error && <div className="error-banner">{error}<button onClick={() => setError(null)}><X size={16} /></button></div>}

      {watchOpen && session && <WatchDevices key={session.user.id} onClose={() => setWatchOpen(false)} />}
      {confirmationOpen && <ExecutionConfirmationDialog onConfirm={confirmExecution} confirming={confirming} />}

      {historyOpen ? <HistoryView sessions={sessions} changes={changes} loading={historyLoading} /> : <>
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
          <div className="composer-actions"><button type="button" className="text-button" onClick={() => setAdding(false)} disabled={addingThread}>キャンセル</button><button className="save-button" disabled={addingThread}>{addingThread ? '追加中…' : '追加する'}</button></div>
          </div>
        </form>
      )}

      {loading ? <div className="loading">読み込んでいます…</div> : (
        <div className="thread-groups">
          <ThreadGroup title="待機中" caption="まだ誰にも渡していない · 上ほど優先" threads={sleeping} activeId={state.executingThreadId} onExecute={execute} onUpdate={updateThread} onRemove={remove} onReorder={reorderThreads} />
          <ThreadGroup title="進行中" caption="AI・他の人に任せている · 上ほど優先" threads={delegated} activeId={state.executingThreadId} onExecute={execute} onUpdate={updateThread} onRemove={remove} onReorder={reorderThreads} />
          {!state.threads.length && <div className="empty-list"><Moon size={32} /><p>頭の中は空っぽです。</p><span>新しいスレッドを置いてみましょう。</span></div>}
        </div>
      )}</>}
    </main>
  )
}

function durationSeconds(session: ExecutionSession, now: number) {
  const started = new Date(session.started_at).getTime()
  const ended = session.ended_at ? new Date(session.ended_at).getTime() : Math.min(now, new Date(session.last_confirmed_at).getTime())
  return Math.max(0, Math.round((ended - started) / 1000))
}

function ExecutionConfirmationDialog({ onConfirm, confirming }: { onConfirm: () => void; confirming: boolean }) {
  return <div className="dialog-backdrop execution-confirmation" role="presentation">
    <section className="edit-dialog" role="dialog" aria-modal="true" aria-labelledby="execution-confirmation-title">
      <p className="eyebrow">EXECUTION CHECK-IN</p>
      <h2 id="execution-confirmation-title">まだ取り組んでいますか？</h2>
      <p>続ける場合は、5分以内に確認してください。確認がない場合、実行は前回の確認時刻で待機に戻ります。</p>
      <div className="dialog-actions"><button className="save-button" onClick={onConfirm} disabled={confirming}>{confirming ? '確認中…' : '続けている'}</button></div>
    </section>
  </div>
}

function formatDuration(seconds: number) {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (hours) return `${hours}時間${minutes ? `${minutes}分` : ''}`
  return `${minutes}分`
}

function dayKey(value: string) {
  const date = new Date(value)
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function HistoryView({ sessions, changes, loading }: { sessions: ExecutionSession[]; changes: ChangeLog[]; loading: boolean }) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const interval = window.setInterval(() => setNow(Date.now()), 60_000)
    return () => window.clearInterval(interval)
  }, [])
  const today = dayKey(new Date().toISOString())
  const byThread = new Map<string, { title: string; seconds: number; count: number; active: boolean }>()
  const byDay = new Map<string, number>()
  for (const session of sessions) {
    const seconds = durationSeconds(session, now)
    const current = byThread.get(session.thread_id) ?? { title: session.thread_title, seconds: 0, count: 0, active: false }
    current.title = session.thread_title
    current.seconds += seconds
    current.count += 1
    current.active ||= !session.ended_at
    byThread.set(session.thread_id, current)
    const key = dayKey(session.started_at)
    byDay.set(key, (byDay.get(key) ?? 0) + seconds)
  }
  const threads = [...byThread.entries()].map(([id, value]) => ({ id, ...value })).sort((a, b) => b.seconds - a.seconds)
  const total = threads.reduce((sum, thread) => sum + thread.seconds, 0)
  const todayTotal = byDay.get(today) ?? 0
  const maximum = threads[0]?.seconds ?? 1
  const days = Array.from({ length: 7 }, (_, offset) => {
    const date = new Date()
    date.setDate(date.getDate() - (6 - offset))
    const key = dayKey(date.toISOString())
    return { key, label: `${date.getMonth() + 1}/${date.getDate()}`, seconds: byDay.get(key) ?? 0 }
  })
  const dayMaximum = Math.max(...days.map(day => day.seconds), 1)
  const priorityChanges = changes.filter(change => change.entity_type === 'thread' && change.operation === 'update' && change.before_data?.priority !== change.after_data?.priority)

  if (loading) return <div className="loading">記録を読み込んでいます…</div>
  if (!sessions.length && !priorityChanges.length) return <div className="history-empty"><BarChart3 size={32} /><p>まだ記録はありません。</p><span>スレッドを実行したり、優先順位を並べ替えたりすると、ここに記録されます。</span></div>

  return <section className="history-view" aria-label="実行記録">
    <div className="history-summary">
      <div><span>今日の実行</span><strong>{formatDuration(todayTotal)}</strong></div>
      <div><span>これまでの合計</span><strong>{formatDuration(total)}</strong></div>
      <div><span>扱ったスレッド</span><strong>{threads.length}件</strong></div>
    </div>
    {sessions.length > 0 && <><section className="history-section"><div className="history-heading"><h2>直近7日</h2><span>開始日ごとの実行時間</span></div>
      <div className="day-chart">{days.map(day => <div className="day-column" key={day.key}><div className="day-track"><div className="day-fill" style={{ height: `${(day.seconds / dayMaximum) * 100}%` }} title={formatDuration(day.seconds)} /></div><span>{day.label}</span></div>)}</div>
    </section></>}
    {sessions.length > 0 && <section className="history-section"><div className="history-heading"><h2>スレッド別</h2><span>実行時間が長い順</span></div>
      <div className="thread-metrics">{threads.map(thread => <article key={thread.id} className="thread-metric"><div className="metric-title"><div><h3>{thread.title}</h3><span>{thread.count} 回の実行{thread.active && ' · 実行中'}</span></div><strong>{formatDuration(thread.seconds)}</strong></div><div className="metric-track"><div style={{ width: `${(thread.seconds / maximum) * 100}%` }} /></div></article>)}</div>
    </section>}
    {priorityChanges.length > 0 && <section className="history-section"><div className="history-heading"><h2>優先順位の変更</h2><span>新しい順</span></div>
      <div className="priority-history">{priorityChanges.map(change => <article className="priority-change" key={change.id}><strong>{String(change.after_data?.title ?? change.before_data?.title ?? 'スレッド')}</strong><span>{new Intl.DateTimeFormat('ja-JP', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(change.changed_at))} に並べ替え</span></article>)}</div>
    </section>}
  </section>
}

function ThreadGroup({ title, caption, threads, activeId, onExecute, onUpdate, onRemove, onReorder }: { title: string; caption: string; threads: Thread[]; activeId: string | null; onExecute: (id: string) => void; onUpdate: (thread: Thread, title: string, delegation: Delegation) => void; onRemove: (thread: Thread) => void; onReorder: (sourceId: string, targetId: string) => void }) {
  const [editingThread, setEditingThread] = useState<Thread | null>(null)
  const [draggedId, setDraggedId] = useState<string | null>(null)
  const [dropTargetId, setDropTargetId] = useState<string | null>(null)
  const touchTargetId = useRef<string | null>(null)
  const sortedThreads = [...threads].sort((a, b) => a.priority - b.priority)
  function finishDrag(sourceId: string, targetId: string | null) {
    setDraggedId(null)
    setDropTargetId(null)
    touchTargetId.current = null
    if (targetId && sourceId !== targetId) void onReorder(sourceId, targetId)
  }
  if (!threads.length) return null
  return <section className="thread-group">
    <div className="group-title"><h2>{title}</h2><span>{caption}</span></div>
    <div className="thread-list">{sortedThreads.map(thread => (
      <article data-thread-id={thread.id} className={`thread-card ${activeId === thread.id ? "active" : ""} ${draggedId === thread.id ? 'dragging' : ''} ${draggedId && draggedId !== thread.id && dropTargetId === thread.id ? 'drag-target' : ''}`} key={thread.id} onDragOver={event => { event.preventDefault(); event.dataTransfer.dropEffect = 'move'; setDropTargetId(thread.id) }} onDrop={event => { event.preventDefault(); finishDrag(event.dataTransfer.getData('text/plain'), thread.id) }}>
        <button className="drag-handle" type="button" draggable onDragStart={event => { event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/plain', thread.id); setDraggedId(thread.id) }} onDragEnd={() => { setDraggedId(null); setDropTargetId(null) }} onPointerDown={event => { if (event.pointerType === 'touch') { touchTargetId.current = thread.id; setDropTargetId(thread.id); setDraggedId(thread.id); event.currentTarget.setPointerCapture(event.pointerId) } }} onPointerMove={event => { if (event.pointerType !== 'touch' || !draggedId) return; const target = document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>('[data-thread-id]')?.dataset.threadId; if (target && sortedThreads.some(item => item.id === target)) { touchTargetId.current = target; setDropTargetId(target) } }} onPointerUp={event => { if (event.pointerType === 'touch') finishDrag(thread.id, touchTargetId.current) }} aria-label={`${thread.title}の優先順位を並べ替える`} title="ドラッグして並べ替え"><GripVertical size={20} /></button>
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
