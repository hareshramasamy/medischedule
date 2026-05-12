import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'
import { Bell, BellOff, RefreshCw } from 'lucide-react'

export default function Waitlist() {
  const [entries, setEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter]   = useState('active')

  async function load() {
    setLoading(true)
    let query = supabase
      .from('waitlist')
      .select('waitlist_id, patient_id, doctor_id, requested_date, priority, reason, is_active, added_at, notified_at')
      .order('priority', { ascending: false })
      .order('added_at', { ascending: true })

    if (filter === 'active')   query = query.eq('is_active', true).is('notified_at', null)
    if (filter === 'notified') query = query.not('notified_at', 'is', null)

    const { data } = await query.limit(50)
    if (!data) { setLoading(false); return }

    const ids = [...new Set([...data.map(w => w.patient_id), ...data.map(w => w.doctor_id)])]
    const { data: users } = await supabase.from('users').select('user_id, full_name').in('user_id', ids)
    const uMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u.full_name]))

    setEntries(data.map(w => ({
      ...w,
      patient_name: uMap[w.patient_id] ?? 'Unknown',
      doctor_name:  uMap[w.doctor_id]  ?? 'Unknown',
    })))
    setLoading(false)
  }

  useEffect(() => { load() }, [filter])

  function priorityColor(p) {
    if (p >= 8) return { bg: 'var(--red-bg)',   color: 'var(--red)',   border: '#4a1a1a' }
    if (p >= 5) return { bg: 'var(--amber-bg)', color: 'var(--amber)', border: '#4a3a0a' }
    return       { bg: 'var(--surface)',  color: 'var(--text2)', border: 'var(--border)' }
  }

  return (
    <div className="animate-in">
      <div className="toolbar">
        <div style={{display:'flex',gap:8}}>
          {['active','notified','all'].map(f => (
            <button
              key={f}
              className={`btn ${filter === f ? 'btn-primary' : 'btn-ghost'}`}
              style={{padding:'6px 14px',fontSize:12,textTransform:'capitalize'}}
              onClick={() => setFilter(f)}
            >{f}</button>
          ))}
        </div>
        <button className="btn btn-ghost" onClick={load}><RefreshCw size={14}/></button>
      </div>

      <div className="card" style={{padding:0}}>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Priority</th>
                <th>Patient</th>
                <th>Doctor</th>
                <th>Requested Date</th>
                <th>Reason</th>
                <th>Added</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr className="loading-row"><td colSpan={7}>Loading waitlist...</td></tr>
              ) : entries.length === 0 ? (
                <tr><td colSpan={7} className="empty-state">No waitlist entries found</td></tr>
              ) : entries.map(w => {
                const pc = priorityColor(w.priority)
                return (
                  <tr key={w.waitlist_id}>
                    <td>
                      <span style={{
                        display:'inline-flex',alignItems:'center',justifyContent:'center',
                        width:28,height:28,borderRadius:'50%',
                        background:pc.bg,color:pc.color,border:`1px solid ${pc.border}`,
                        fontFamily:'var(--font-display)',fontSize:12,fontWeight:700
                      }}>{w.priority}</span>
                    </td>
                    <td style={{fontWeight:500}}>{w.patient_name}</td>
                    <td style={{color:'var(--text2)'}}>{w.doctor_name}</td>
                    <td style={{color:'var(--text2)',fontFamily:'var(--font-display)',fontSize:12}}>
                      {w.requested_date ? format(new Date(w.requested_date), 'MMM d, yyyy') : 'Any date'}
                    </td>
                    <td style={{color:'var(--text2)',maxWidth:200,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'}}>
                      {w.reason ?? '—'}
                    </td>
                    <td style={{color:'var(--text3)',fontSize:12}}>
                      {format(new Date(w.added_at), 'MMM d, h:mm a')}
                    </td>
                    <td>
                      {w.notified_at ? (
                        <div style={{display:'flex',alignItems:'center',gap:6,color:'var(--accent)',fontSize:12}}>
                          <Bell size={13}/>
                          <span>Notified {format(new Date(w.notified_at), 'MMM d, h:mm a')}</span>
                        </div>
                      ) : (
                        <div style={{display:'flex',alignItems:'center',gap:6,color:'var(--text3)',fontSize:12}}>
                          <BellOff size={13}/>
                          <span>Waiting</span>
                        </div>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
