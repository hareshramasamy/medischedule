import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'
import { Search, ChevronDown, ChevronUp } from 'lucide-react'

export default function Patients() {
  const [patients, setPatients] = useState([])
  const [loading, setLoading]   = useState(true)
  const [search, setSearch]     = useState('')
  const [expanded, setExpanded] = useState(null)
  const [history, setHistory]   = useState({})
  const [histLoading, setHistLoading] = useState({})

  async function load(q = '') {
    setLoading(true)
    let data, error

    if (q.trim()) {
      const res = await supabase.rpc('search_patients', { p_query: q.trim(), p_limit: 20, p_offset: 0 })
      data  = res.data
      error = res.error
    } else {
      const res = await supabase.from('patients').select('patient_id, date_of_birth, gender, blood_type, allergies, insurance_provider, insurance_id').limit(30)
      data  = res.data
      error = res.error
    }

    if (error || !data) { setLoading(false); return }

    const ids = data.map(p => p.patient_id ?? p.patient_id)
    const { data: users } = await supabase.from('users').select('user_id, full_name, email').in('user_id', ids)
    const uMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u]))

    setPatients(data.map(p => ({ ...p, ...uMap[p.patient_id] })))
    setLoading(false)
  }

  useEffect(() => { load() }, [])

  async function loadHistory(patientId) {
    setHistLoading(h => ({ ...h, [patientId]: true }))
    const { data } = await supabase
      .from('appointments')
      .select('appointment_id, scheduled_start, status, appointment_type, chief_complaint, doctor_id')
      .eq('patient_id', patientId)
      .order('scheduled_start', { ascending: false })
      .limit(10)

    if (data?.length) {
      const { data: users } = await supabase.from('users').select('user_id, full_name')
        .in('user_id', data.map(a => a.doctor_id))
      const uMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u.full_name]))
      setHistory(h => ({ ...h, [patientId]: data.map(a => ({ ...a, doctor_name: uMap[a.doctor_id] ?? '—' })) }))
    } else {
      setHistory(h => ({ ...h, [patientId]: [] }))
    }
    setHistLoading(h => ({ ...h, [patientId]: false }))
  }

  function toggle(id) {
    if (expanded === id) { setExpanded(null); return }
    setExpanded(id)
    if (!history[id]) loadHistory(id)
  }

  const STATUS_COLORS = {
    scheduled:'badge-blue', confirmed:'badge-blue', checked_in:'badge-amber',
    in_progress:'badge-amber', completed:'badge-green', cancelled:'badge-red',
    no_show:'badge-red', rescheduled:'badge-gray',
  }

  return (
    <div className="animate-in">
      <div className="search-bar">
        <Search size={15} style={{color:'var(--text3)',flexShrink:0}} />
        <input
          placeholder="Search by name, insurance provider, or allergy..."
          value={search}
          onChange={e => { setSearch(e.target.value); load(e.target.value) }}
        />
      </div>

      <div style={{display:'flex',flexDirection:'column',gap:10}}>
        {loading ? (
          [...Array(4)].map((_,i) => <div key={i} className="card skeleton" style={{height:70}} />)
        ) : patients.length === 0 ? (
          <div className="empty-state">No patients found</div>
        ) : patients.map(p => (
          <div key={p.patient_id} className="card" style={{padding:0,overflow:'hidden'}}>
            <div
              style={{display:'flex',alignItems:'center',gap:16,padding:'16px 24px',cursor:'pointer'}}
              onClick={() => toggle(p.patient_id)}
            >
              <div style={{
                width:40,height:40,borderRadius:'50%',
                background:'var(--blue-bg)',display:'flex',alignItems:'center',
                justifyContent:'center',flexShrink:0,
                fontFamily:'var(--font-display)',fontSize:14,fontWeight:700,color:'var(--blue)'
              }}>
                {p.full_name?.split(' ').map(w=>w[0]).join('').slice(0,2)}
              </div>
              <div style={{flex:1}}>
                <div style={{fontWeight:600}}>{p.full_name}</div>
                <div style={{color:'var(--text2)',fontSize:12,marginTop:2}}>
                  {p.email} · DOB: {p.date_of_birth ? format(new Date(p.date_of_birth), 'MMM d, yyyy') : '—'}
                </div>
              </div>
              <div style={{display:'flex',gap:8,alignItems:'center'}}>
                {p.blood_type && (
                  <span className="badge badge-amber">{p.blood_type}</span>
                )}
                {p.insurance_provider && (
                  <span className="badge badge-gray">{p.insurance_provider}</span>
                )}
                {(p.allergies ?? []).slice(0,2).map(a => (
                  <span key={a} className="badge badge-red">{a}</span>
                ))}
              </div>
              {expanded === p.patient_id
                ? <ChevronUp size={16} color="var(--text3)"/>
                : <ChevronDown size={16} color="var(--text3)"/>
              }
            </div>

            {expanded === p.patient_id && (
              <div style={{borderTop:'1px solid var(--border)',padding:'20px 24px',background:'var(--bg3)'}}>
                <p className="section-title" style={{marginBottom:12}}>Appointment History</p>
                {histLoading[p.patient_id] ? (
                  <div style={{color:'var(--text3)',fontSize:12}}>Loading...</div>
                ) : (history[p.patient_id] ?? []).length === 0 ? (
                  <div style={{color:'var(--text3)',fontSize:12}}>No appointments on record</div>
                ) : (
                  <table style={{width:'100%'}}>
                    <thead>
                      <tr>
                        <th>Date</th>
                        <th>Doctor</th>
                        <th>Type</th>
                        <th>Complaint</th>
                        <th>Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {history[p.patient_id].map(a => (
                        <tr key={a.appointment_id}>
                          <td style={{fontFamily:'var(--font-display)',fontSize:12}}>
                            {format(new Date(a.scheduled_start), 'MMM d, yyyy h:mm a')}
                          </td>
                          <td style={{color:'var(--text2)'}}>{a.doctor_name}</td>
                          <td style={{color:'var(--text3)',textTransform:'capitalize'}}>{a.appointment_type?.replace('_',' ')}</td>
                          <td style={{color:'var(--text2)',maxWidth:200,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'}}>
                            {a.chief_complaint ?? '—'}
                          </td>
                          <td><span className={`badge ${STATUS_COLORS[a.status]??'badge-gray'}`}>{a.status?.replace('_',' ')}</span></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
