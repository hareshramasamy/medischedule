import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'
import { Plus, Search, RefreshCw } from 'lucide-react'

const STATUS_COLORS = {
  scheduled:   'badge-blue',
  confirmed:   'badge-blue',
  checked_in:  'badge-amber',
  in_progress: 'badge-amber',
  completed:   'badge-green',
  cancelled:   'badge-red',
  no_show:     'badge-red',
  rescheduled: 'badge-gray',
}

const STATUS_TRANSITIONS = {
  scheduled:   ['confirmed', 'cancelled'],
  confirmed:   ['checked_in', 'cancelled'],
  checked_in:  ['in_progress'],
  in_progress: ['completed'],
  completed:   [],
  cancelled:   [],
  no_show:     [],
  rescheduled: [],
}

export default function Appointments() {
  const [appointments, setAppointments] = useState([])
  const [loading, setLoading]   = useState(true)
  const [search, setSearch]     = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [showModal, setShowModal] = useState(false)
  const [doctors, setDoctors]   = useState([])
  const [patients, setPatients] = useState([])
  const [rooms, setRooms]       = useState([])
  const [form, setForm]         = useState({
    patient_id: '', doctor_id: '', room_id: '',
    start: '', end: '', type: 'follow_up', complaint: ''
  })
  const [saving, setSaving] = useState(false)
  const [error, setError]   = useState('')

  async function load() {
    setLoading(true)
    const { data } = await supabase
      .from('appointments')
      .select('appointment_id, scheduled_start, scheduled_end, status, appointment_type, chief_complaint, patient_id, doctor_id, room_id')
      .order('scheduled_start', { ascending: false })
      .limit(50)

    if (!data) { setLoading(false); return }

    const ids = [...new Set([...data.map(a => a.patient_id), ...data.map(a => a.doctor_id)].filter(Boolean))]
    const { data: users } = await supabase.from('users').select('user_id, full_name').in('user_id', ids)
    const userMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u.full_name]))

    setAppointments(data.map(a => ({
      ...a,
      patient_name: userMap[a.patient_id] ?? 'Unknown',
      doctor_name:  userMap[a.doctor_id]  ?? 'Unknown',
    })))
    setLoading(false)
  }

  useEffect(() => {
    load()
    // Load form dropdowns
    Promise.all([
      supabase.from('doctors').select('doctor_id, specialty'),
      supabase.from('patients').select('patient_id'),
      supabase.from('rooms').select('room_id, room_number, room_type').eq('is_active', true),
    ]).then(async ([dRes, pRes, rRes]) => {
      const dIds = (dRes.data ?? []).map(d => d.doctor_id)
      const pIds = (pRes.data ?? []).map(p => p.patient_id)
      const { data: users } = await supabase.from('users').select('user_id, full_name').in('user_id', [...dIds, ...pIds])
      const uMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u.full_name]))
      setDoctors((dRes.data ?? []).map(d => ({ ...d, name: uMap[d.doctor_id] ?? d.doctor_id })))
      setPatients((pRes.data ?? []).map(p => ({ ...p, name: uMap[p.patient_id] ?? p.patient_id })))
      setRooms(rRes.data ?? [])
    })
  }, [])

  async function updateStatus(appt, newStatus) {
    const { error } = await supabase
      .from('appointments')
      .update({
        status: newStatus,
        ...(newStatus === 'cancelled' ? {
          cancelled_by: '00000000-0000-0000-0000-000000000001',
          cancellation_reason: 'Cancelled by staff'
        } : {})
      })
      .eq('appointment_id', appt.appointment_id)
      .eq('scheduled_start', appt.scheduled_start)
    if (!error) load()
  }

  async function bookAppointment() {
    setSaving(true)
    setError('')
    const { data, error } = await supabase.rpc('book_appointment', {
      p_patient_id:       form.patient_id,
      p_doctor_id:        form.doctor_id,
      p_room_id:          form.room_id ? parseInt(form.room_id) : null,
      p_start:            new Date(form.start).toISOString(),
      p_end:              new Date(form.end).toISOString(),
      p_appointment_type: form.type,
      p_chief_complaint:  form.complaint,
      p_created_by:       '00000000-0000-0000-0003-000000000001',
    })
    setSaving(false)
    if (error) { setError(error.message); return }
    setShowModal(false)
    setForm({ patient_id:'', doctor_id:'', room_id:'', start:'', end:'', type:'follow_up', complaint:'' })
    load()
  }

  const filtered = appointments.filter(a => {
    const matchSearch = !search ||
      a.patient_name.toLowerCase().includes(search.toLowerCase()) ||
      a.doctor_name.toLowerCase().includes(search.toLowerCase())
    const matchStatus = statusFilter === 'all' || a.status === statusFilter
    return matchSearch && matchStatus
  })

  return (
    <div className="animate-in">
      <div className="toolbar">
        <div className="search-bar" style={{margin:0, flex:1}}>
          <Search size={15} style={{color:'var(--text3)',flexShrink:0}} />
          <input
            placeholder="Search by patient or doctor..."
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)} style={{width:160}}>
          <option value="all">All statuses</option>
          {Object.keys(STATUS_COLORS).map(s => (
            <option key={s} value={s}>{s.replace('_',' ')}</option>
          ))}
        </select>
        <button className="btn btn-ghost" onClick={load}><RefreshCw size={14}/></button>
        <button className="btn btn-primary" onClick={() => setShowModal(true)}>
          <Plus size={14}/> Book Appointment
        </button>
      </div>

      <div className="card" style={{padding:0}}>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Patient</th>
                <th>Doctor</th>
                <th>Scheduled</th>
                <th>Type</th>
                <th>Complaint</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr className="loading-row"><td colSpan={7}>Loading appointments...</td></tr>
              ) : filtered.length === 0 ? (
                <tr><td colSpan={7} className="empty-state">No appointments found</td></tr>
              ) : filtered.map(a => (
                <tr key={a.appointment_id}>
                  <td style={{fontWeight:500}}>{a.patient_name}</td>
                  <td style={{color:'var(--text2)'}}>{a.doctor_name}</td>
                  <td style={{fontFamily:'var(--font-display)',fontSize:12,color:'var(--text2)'}}>
                    {format(new Date(a.scheduled_start), 'MMM d, h:mm a')}
                  </td>
                  <td style={{color:'var(--text3)',textTransform:'capitalize'}}>{a.appointment_type?.replace('_',' ')}</td>
                  <td style={{color:'var(--text2)',maxWidth:180,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'}}>
                    {a.chief_complaint ?? '—'}
                  </td>
                  <td><span className={`badge ${STATUS_COLORS[a.status]??'badge-gray'}`}>{a.status?.replace('_',' ')}</span></td>
                  <td>
                    <div style={{display:'flex',gap:6}}>
                      {STATUS_TRANSITIONS[a.status]?.map(next => (
                        <button
                          key={next}
                          className={`btn ${next === 'cancelled' ? 'btn-danger' : 'btn-ghost'}`}
                          style={{padding:'4px 10px',fontSize:11}}
                          onClick={() => updateStatus(a, next)}
                        >
                          {next.replace('_',' ')}
                        </button>
                      ))}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setShowModal(false)}>
          <div className="modal">
            <p className="modal-title">Book Appointment</p>
            {error && <p style={{color:'var(--red)',fontSize:12,marginBottom:12,padding:'8px 12px',background:'var(--red-bg)',borderRadius:6}}>{error}</p>}
            <div className="form-group">
              <label>Patient</label>
              <select value={form.patient_id} onChange={e => setForm({...form,patient_id:e.target.value})}>
                <option value="">Select patient...</option>
                {patients.map(p => <option key={p.patient_id} value={p.patient_id}>{p.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>Doctor</label>
              <select value={form.doctor_id} onChange={e => setForm({...form,doctor_id:e.target.value})}>
                <option value="">Select doctor...</option>
                {doctors.map(d => <option key={d.doctor_id} value={d.doctor_id}>{d.name} — {d.specialty}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>Room (optional)</label>
              <select value={form.room_id} onChange={e => setForm({...form,room_id:e.target.value})}>
                <option value="">No room assigned</option>
                {rooms.map(r => <option key={r.room_id} value={r.room_id}>{r.room_number} ({r.room_type})</option>)}
              </select>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Start</label>
                <input type="datetime-local" value={form.start} onChange={e => setForm({...form,start:e.target.value})} />
              </div>
              <div className="form-group">
                <label>End</label>
                <input type="datetime-local" value={form.end} onChange={e => setForm({...form,end:e.target.value})} />
              </div>
            </div>
            <div className="form-group">
              <label>Type</label>
              <select value={form.type} onChange={e => setForm({...form,type:e.target.value})}>
                <option value="new_patient">New Patient</option>
                <option value="follow_up">Follow Up</option>
                <option value="urgent">Urgent</option>
                <option value="procedure">Procedure</option>
              </select>
            </div>
            <div className="form-group">
              <label>Chief Complaint</label>
              <input
                placeholder="e.g. Chest pain, follow-up..."
                value={form.complaint}
                onChange={e => setForm({...form,complaint:e.target.value})}
              />
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setShowModal(false)}>Cancel</button>
              <button className="btn btn-primary" onClick={bookAppointment} disabled={saving}>
                {saving ? 'Booking...' : 'Book Appointment'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
