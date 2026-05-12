import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'
import { ChevronDown, ChevronUp, Clock } from 'lucide-react'

const DAYS = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday']

export default function Doctors() {
  const [doctors, setDoctors]   = useState([])
  const [loading, setLoading]   = useState(true)
  const [expanded, setExpanded] = useState(null)
  const [slots, setSlots]       = useState({})
  const [slotsLoading, setSlotsLoading] = useState({})

  useEffect(() => {
    async function load() {
      const { data: docs } = await supabase
        .from('doctors')
        .select('doctor_id, specialty, consultation_fee, metadata, dept_id')

      if (!docs) { setLoading(false); return }

      const ids = docs.map(d => d.doctor_id)
      const [{ data: users }, { data: schedules }, { data: depts }] = await Promise.all([
        supabase.from('users').select('user_id, full_name, email').in('user_id', ids),
        supabase.from('doctor_schedules').select('*').in('doctor_id', ids).eq('is_active', true),
        supabase.from('departments').select('dept_id, name'),
      ])

      const uMap    = Object.fromEntries((users ?? []).map(u => [u.user_id, u]))
      const deptMap = Object.fromEntries((depts ?? []).map(d => [d.dept_id, d.name]))
      const schedMap = {}
      for (const s of (schedules ?? [])) {
        if (!schedMap[s.doctor_id]) schedMap[s.doctor_id] = []
        schedMap[s.doctor_id].push(s)
      }

      setDoctors(docs.map(d => ({
        ...d,
        ...uMap[d.doctor_id],
        dept_name: deptMap[d.dept_id] ?? '—',
        schedules: schedMap[d.doctor_id] ?? [],
      })))
      setLoading(false)
    }
    load()
  }, [])

  async function loadSlots(doctorId) {
    setSlotsLoading(s => ({ ...s, [doctorId]: true }))
    const today = format(new Date(), 'yyyy-MM-dd')
    const { data } = await supabase.rpc('get_available_slots', {
      p_doctor_id: doctorId,
      p_date: today,
    })
    setSlots(s => ({ ...s, [doctorId]: data ?? [] }))
    setSlotsLoading(s => ({ ...s, [doctorId]: false }))
  }

  function toggle(id) {
    if (expanded === id) { setExpanded(null); return }
    setExpanded(id)
    if (!slots[id]) loadSlots(id)
  }

  if (loading) return (
    <div style={{display:'flex',flexDirection:'column',gap:12}}>
      {[...Array(3)].map((_,i) => (
        <div key={i} className="card skeleton" style={{height:80}} />
      ))}
    </div>
  )

  return (
    <div className="animate-in" style={{display:'flex',flexDirection:'column',gap:12}}>
      {doctors.map(doc => (
        <div key={doc.doctor_id} className="card" style={{padding:0,overflow:'hidden'}}>
          <div
            style={{
              display:'flex', alignItems:'center', gap:16,
              padding:'18px 24px', cursor:'pointer',
            }}
            onClick={() => toggle(doc.doctor_id)}
          >
            <div style={{
              width:44, height:44, borderRadius:'50%',
              background:'var(--accent-bg)', display:'flex', alignItems:'center',
              justifyContent:'center', flexShrink:0,
              fontFamily:'var(--font-display)', fontSize:16, fontWeight:700, color:'var(--accent)'
            }}>
              {doc.full_name?.split(' ').map(w=>w[0]).join('').slice(0,2)}
            </div>
            <div style={{flex:1}}>
              <div style={{fontWeight:600, fontSize:15}}>{doc.full_name}</div>
              <div style={{color:'var(--text2)', fontSize:12, marginTop:2}}>
                {doc.specialty} · {doc.dept_name}
              </div>
            </div>
            <div style={{textAlign:'right', marginRight:16}}>
              <div style={{fontFamily:'var(--font-display)', fontSize:18, fontWeight:700, color:'var(--accent)'}}>
                ${parseFloat(doc.consultation_fee).toFixed(0)}
              </div>
              <div style={{color:'var(--text3)', fontSize:11}}>per visit</div>
            </div>
            <div style={{display:'flex', flexDirection:'column', gap:4, marginRight:16}}>
              <span className={`badge ${doc.metadata?.accepting_new_patients ? 'badge-green' : 'badge-red'}`}>
                {doc.metadata?.accepting_new_patients ? 'Accepting' : 'Not Accepting'}
              </span>
            </div>
            {expanded === doc.doctor_id ? <ChevronUp size={16} color="var(--text3)"/> : <ChevronDown size={16} color="var(--text3)"/>}
          </div>

          {expanded === doc.doctor_id && (
            <div style={{borderTop:'1px solid var(--border)', padding:'20px 24px', background:'var(--bg3)'}}>
              <div style={{display:'grid', gridTemplateColumns:'1fr 1fr', gap:24}}>
                <div>
                  <p className="section-title" style={{marginBottom:10}}>Weekly Schedule</p>
                  <div style={{display:'flex', flexDirection:'column', gap:6}}>
                    {DAYS.map(day => {
                      const s = doc.schedules.find(sc => sc.day_of_week === day)
                      return (
                        <div key={day} style={{
                          display:'flex', justifyContent:'space-between',
                          fontSize:12, padding:'6px 10px',
                          background: s ? 'var(--accent-bg)' : 'var(--surface)',
                          borderRadius:6,
                          border: `1px solid ${s ? 'var(--border2)' : 'var(--border)'}`,
                        }}>
                          <span style={{
                            textTransform:'capitalize',
                            color: s ? 'var(--text)' : 'var(--text3)',
                            fontWeight: s ? 500 : 400,
                          }}>{day}</span>
                          {s
                            ? <span style={{color:'var(--accent)', fontFamily:'var(--font-display)'}}>
                                {s.start_time.slice(0,5)} – {s.end_time.slice(0,5)} · {s.slot_duration}min
                              </span>
                            : <span style={{color:'var(--text3)'}}>Off</span>
                          }
                        </div>
                      )
                    })}
                  </div>
                </div>

                <div>
                  <p className="section-title" style={{marginBottom:10}}>
                    <Clock size={12} style={{display:'inline',marginRight:6}} />
                    Today's Available Slots
                  </p>
                  {slotsLoading[doc.doctor_id] ? (
                    <div style={{color:'var(--text3)',fontSize:12}}>Loading slots...</div>
                  ) : (slots[doc.doctor_id] ?? []).length === 0 ? (
                    <div style={{color:'var(--text3)',fontSize:12}}>No schedule today</div>
                  ) : (
                    <div style={{display:'flex', flexWrap:'wrap', gap:6}}>
                      {slots[doc.doctor_id].map((s, i) => (
                        <span
                          key={i}
                          style={{
                            padding:'4px 10px',
                            borderRadius:20,
                            fontSize:11,
                            fontFamily:'var(--font-display)',
                            background: s.is_available ? 'var(--accent-bg)' : 'var(--surface)',
                            color: s.is_available ? 'var(--accent)' : 'var(--text3)',
                            border: `1px solid ${s.is_available ? 'var(--border2)' : 'var(--border)'}`,
                          }}
                        >
                          {format(new Date(s.slot_start), 'h:mm a')}
                        </span>
                      ))}
                    </div>
                  )}

                  <div style={{marginTop:20}}>
                    <p className="section-title" style={{marginBottom:8}}>Details</p>
                    <div style={{fontSize:12, color:'var(--text2)', display:'flex', flexDirection:'column', gap:5}}>
                      <div><span style={{color:'var(--text3)'}}>Languages: </span>{doc.metadata?.languages?.join(', ') ?? '—'}</div>
                      <div><span style={{color:'var(--text3)'}}>Experience: </span>{doc.metadata?.years_experience ?? '—'} years</div>
                      <div><span style={{color:'var(--text3)'}}>Email: </span>{doc.email}</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      ))}
    </div>
  )
}
