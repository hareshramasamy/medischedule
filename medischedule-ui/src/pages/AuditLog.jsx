import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'
import { ChevronDown, ChevronUp } from 'lucide-react'

const OP_COLORS = {
  INSERT: 'badge-green',
  UPDATE: 'badge-amber',
  DELETE: 'badge-red',
}

export default function AuditLog() {
  const [logs, setLogs]         = useState([])
  const [loading, setLoading]   = useState(true)
  const [tableFilter, setTableFilter] = useState('all')
  const [opFilter, setOpFilter] = useState('all')
  const [expanded, setExpanded] = useState(null)
  const [tables, setTables]     = useState([])

  async function load() {
    setLoading(true)
    let query = supabase
      .from('audit_log')
      .select('log_id, table_name, record_id, operation, changed_by, changed_at, diff, old_data, new_data')
      .order('changed_at', { ascending: false })
      .limit(100)

    if (tableFilter !== 'all') query = query.eq('table_name', tableFilter)
    if (opFilter    !== 'all') query = query.eq('operation',  opFilter)

    const { data } = await query
    if (!data) { setLoading(false); return }

    // collect unique tables for filter dropdown
    const allTables = [...new Set(data.map(l => l.table_name))]
    setTables(allTables)

    // get changed_by user names
    const userIds = [...new Set(data.map(l => l.changed_by).filter(Boolean))]
    let uMap = {}
    if (userIds.length) {
      const { data: users } = await supabase.from('users').select('user_id, full_name').in('user_id', userIds)
      uMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u.full_name]))
    }

    setLogs(data.map(l => ({ ...l, changed_by_name: uMap[l.changed_by] ?? 'System' })))
    setLoading(false)
  }

  useEffect(() => { load() }, [tableFilter, opFilter])

  function renderDiff(diff) {
    if (!diff) return null
    return Object.entries(diff).map(([key, val]) => (
      <div key={key} style={{
        display:'flex',gap:8,alignItems:'flex-start',
        padding:'6px 0',borderBottom:'1px solid var(--border)',fontSize:12
      }}>
        <span style={{color:'var(--text3)',minWidth:120,fontFamily:'var(--font-display)'}}>{key}</span>
        <span style={{color:'var(--red)',flex:1,wordBreak:'break-all'}}>
          {JSON.stringify(val?.old ?? null)}
        </span>
        <span style={{color:'var(--text3)'}}>→</span>
        <span style={{color:'var(--accent)',flex:1,wordBreak:'break-all'}}>
          {JSON.stringify(val?.new ?? null)}
        </span>
      </div>
    ))
  }

  return (
    <div className="animate-in">
      <div className="toolbar">
        <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
          <select
            value={tableFilter}
            onChange={e => setTableFilter(e.target.value)}
            style={{width:180}}
          >
            <option value="all">All tables</option>
            {tables.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
          <select
            value={opFilter}
            onChange={e => setOpFilter(e.target.value)}
            style={{width:140}}
          >
            <option value="all">All operations</option>
            <option value="INSERT">INSERT</option>
            <option value="UPDATE">UPDATE</option>
            <option value="DELETE">DELETE</option>
          </select>
        </div>
        <div style={{color:'var(--text3)',fontSize:12}}>
          {logs.length} entries
        </div>
      </div>

      <div className="card" style={{padding:0}}>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Table</th>
                <th>Operation</th>
                <th>Changed By</th>
                <th>Record ID</th>
                <th>Changes</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr className="loading-row"><td colSpan={6}>Loading audit log...</td></tr>
              ) : logs.length === 0 ? (
                <tr><td colSpan={6} className="empty-state">No audit entries found</td></tr>
              ) : logs.map(log => (
                <>
                  <tr
                    key={log.log_id}
                    style={{cursor: log.diff ? 'pointer' : 'default'}}
                    onClick={() => log.diff && setExpanded(expanded === log.log_id ? null : log.log_id)}
                  >
                    <td style={{fontFamily:'var(--font-display)',fontSize:11,color:'var(--text2)',whiteSpace:'nowrap'}}>
                      {format(new Date(log.changed_at), 'MMM d, HH:mm:ss')}
                    </td>
                    <td style={{fontFamily:'var(--font-display)',fontSize:12,color:'var(--text2)'}}>{log.table_name}</td>
                    <td><span className={`badge ${OP_COLORS[log.operation]??'badge-gray'}`}>{log.operation}</span></td>
                    <td style={{color:'var(--text2)'}}>{log.changed_by_name}</td>
                    <td style={{
                      fontFamily:'monospace',fontSize:11,color:'var(--text3)',
                      maxWidth:160,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'
                    }}>
                      {log.record_id}
                    </td>
                    <td>
                      {log.diff && Object.keys(log.diff).length > 0 ? (
                        <div style={{display:'flex',alignItems:'center',gap:6,color:'var(--amber)',fontSize:12}}>
                          <span>{Object.keys(log.diff).join(', ')}</span>
                          {expanded === log.log_id
                            ? <ChevronUp size={13}/>
                            : <ChevronDown size={13}/>
                          }
                        </div>
                      ) : (
                        <span style={{color:'var(--text3)',fontSize:12}}>—</span>
                      )}
                    </td>
                  </tr>
                  {expanded === log.log_id && log.diff && (
                    <tr key={`${log.log_id}-diff`}>
                      <td colSpan={6} style={{
                        background:'var(--bg3)',padding:'12px 24px',
                        borderBottom:'1px solid var(--border)'
                      }}>
                        <div style={{marginBottom:6}}>
                          <span style={{fontSize:11,color:'var(--text3)',fontFamily:'var(--font-display)',textTransform:'uppercase',letterSpacing:'0.06em'}}>
                            Field changes
                          </span>
                        </div>
                        {renderDiff(log.diff)}
                      </td>
                    </tr>
                  )}
                </>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
