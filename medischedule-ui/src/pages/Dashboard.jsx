import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'
import { Calendar, Users, DollarSign, TrendingUp, Clock, CheckCircle, XCircle, AlertCircle } from 'lucide-react'

function statusBadge(status) {
  const map = {
    scheduled:   'badge-blue',
    confirmed:   'badge-blue',
    checked_in:  'badge-amber',
    in_progress: 'badge-amber',
    completed:   'badge-green',
    cancelled:   'badge-red',
    no_show:     'badge-red',
    rescheduled: 'badge-gray',
  }
  return `badge ${map[status] ?? 'badge-gray'}`
}

export default function Dashboard() {
  const [stats, setStats]       = useState(null)
  const [appointments, setAppointments] = useState([])
  const [loading, setLoading]   = useState(true)

  useEffect(() => {
    async function load() {
      const [apptRes, patRes, invoiceRes] = await Promise.all([
        supabase.from('appointments').select('status, scheduled_start, doctor_id'),
        supabase.from('patients').select('patient_id', { count: 'exact', head: true }),
        supabase.from('invoices').select('total_amount, paid_amount, is_paid'),
      ])

      const appts = apptRes.data ?? []
      const today = new Date().toISOString().slice(0, 10)
      const todayAppts = appts.filter(a => a.scheduled_start?.slice(0, 10) === today)

      const invoices = invoiceRes.data ?? []
      const totalRevenue  = invoices.reduce((s, i) => s + parseFloat(i.total_amount || 0), 0)
      const totalCollected = invoices.reduce((s, i) => s + parseFloat(i.paid_amount || 0), 0)

      setStats({
        totalPatients:    patRes.count ?? 0,
        todayTotal:       todayAppts.length,
        todayCompleted:   todayAppts.filter(a => a.status === 'completed').length,
        todayCancelled:   todayAppts.filter(a => a.status === 'cancelled').length,
        totalRevenue,
        totalCollected,
        completionRate:   appts.length
          ? Math.round(appts.filter(a => a.status === 'completed').length / appts.length * 100)
          : 0,
      })

      // Recent appointments with joins via separate queries
      const { data: recentAppts } = await supabase
        .from('appointments')
        .select(`
          appointment_id, scheduled_start, status, appointment_type, chief_complaint,
          patient:patients(patient_id),
          doctor:doctors(specialty)
        `)
        .order('scheduled_start', { ascending: false })
        .limit(8)

      // Get user names separately
      if (recentAppts) {
        const patientIds = [...new Set(recentAppts.map(a => a.patient?.patient_id).filter(Boolean))]
        const doctorIds  = [...new Set(recentAppts.map(a => a.doctor_id).filter(Boolean))]

        const { data: users } = await supabase
          .from('users')
          .select('user_id, full_name')
          .in('user_id', [...patientIds, ...doctorIds])

        const userMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u.full_name]))

        setAppointments(recentAppts.map(a => ({
          ...a,
          patient_name: userMap[a.patient?.patient_id] ?? 'Unknown',
          doctor_name:  userMap[a.doctor_id] ?? 'Unknown',
        })))
      }

      setLoading(false)
    }
    load()
  }, [])

  if (loading) return (
    <div>
      <div className="stat-grid">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="stat-card">
            <div className="skeleton" style={{height:12,width:80,marginBottom:8}} />
            <div className="skeleton" style={{height:32,width:60}} />
          </div>
        ))}
      </div>
    </div>
  )

  return (
    <div className="animate-in">
      <div className="stat-grid">
        <div className="stat-card">
          <span className="stat-label">Total Patients</span>
          <span className="stat-value">{stats.totalPatients}</span>
          <span className="stat-sub">registered</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Today's Appointments</span>
          <span className="stat-value">{stats.todayTotal}</span>
          <span className="stat-sub">{stats.todayCompleted} completed · {stats.todayCancelled} cancelled</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Total Revenue</span>
          <span className="stat-value">${stats.totalRevenue.toFixed(0)}</span>
          <span className="stat-sub">${stats.totalCollected.toFixed(0)} collected</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Completion Rate</span>
          <span className="stat-value">{stats.completionRate}%</span>
          <span className="stat-sub">of all appointments</span>
        </div>
      </div>

      <p className="section-title">Recent Appointments</p>
      <div className="card" style={{padding: 0}}>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Patient</th>
                <th>Doctor</th>
                <th>Date</th>
                <th>Type</th>
                <th>Chief Complaint</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {appointments.length === 0 ? (
                <tr><td colSpan={6} style={{textAlign:'center',color:'var(--text3)',padding:'32px'}}>No appointments found</td></tr>
              ) : appointments.map(a => (
                <tr key={a.appointment_id}>
                  <td style={{fontWeight:500}}>{a.patient_name}</td>
                  <td style={{color:'var(--text2)'}}>{a.doctor_name}</td>
                  <td style={{color:'var(--text2)',fontFamily:'var(--font-display)',fontSize:12}}>
                    {format(new Date(a.scheduled_start), 'MMM d, h:mm a')}
                  </td>
                  <td style={{color:'var(--text3)',textTransform:'capitalize'}}>{a.appointment_type?.replace('_',' ')}</td>
                  <td style={{color:'var(--text2)',maxWidth:200,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'}}>
                    {a.chief_complaint ?? '—'}
                  </td>
                  <td><span className={statusBadge(a.status)}>{a.status?.replace('_',' ')}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
