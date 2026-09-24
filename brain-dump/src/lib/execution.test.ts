import {describe,it,expect} from 'vitest'
import {stateFromSnapshot, expectedFromSnapshot, executionCommand} from './execution'
const snapshot={server_time:'2026-09-24T00:00:00Z',threads:[{id:'t',title:'作業',delegation:null,priority:1}],active:{session_id:'9007199254740993',confirmation_revision:'revision',thread_id:'t',last_confirmed_at:'2026-09-24T00:00:00Z',deadline:'2026-09-24T01:00:00Z'}}
describe('execution response adapter',()=>{
 it('keeps execution active when server rejects an early timeout',()=>{expect(stateFromSnapshot(snapshot).executingThreadId).toBe('t')})
 it('never rounds session IDs and captures the selected generation',()=>{expect(expectedFromSnapshot(snapshot)).toEqual({session_id:'9007199254740993',confirmation_revision:'revision'})})
 it('switches explicitly rather than toggling a new server state',()=>{const cmd=executionCommand('switch',snapshot,'next');expect(cmd.target_thread_id).toBe('next');expect(cmd.expected?.session_id).toBe('9007199254740993')})
})
