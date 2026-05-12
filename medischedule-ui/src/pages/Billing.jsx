import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'
import { ChevronDown, ChevronUp } from 'lucide-react'

export default function Billing() {
  const [invoices, setInvoices]   = useState([])
  const [loading, setLoading]     = useState(true)
  const [filter, setFilter]       = useState('all')
  const [expanded, setExpanded]   = useState(null)
  const [lineItems, setLineItems] = useState({})
  const [claims, setClaims]       = useState({})

  async function load() {
    setLoading(true)
    let query = supabase
      .from('invoices')
      .select('invoice_id, appointment_id, patient_id, subtotal, total_amount, paid_amount, balance_due, due_date, is_paid, created_at')
      .order('created_at', { ascending: false })
      .limit(50)

    if (filter === 'unpaid') query = query.eq('is_paid', false)
    if (filter === 'paid')   query = query.eq('is_paid', true)

    const { data } = await query
    if (!data) { setLoading(false); return }

    const ids = data.map(i => i.patient_id)
    const { data: users } = await supabase.from('users').select('user_id, full_name').in('user_id', ids)
    const uMap = Object.fromEntries((users ?? []).map(u => [u.user_id, u.full_name]))

    setInvoices(data.map(i => ({ ...i, patient_name: uMap[i.patient_id] ?? 'Unknown' })))
    setLoading(false)
  }

  useEffect(() => { load() }, [filter])

  async function expand(invoiceId) {
    if (expanded === invoiceId) { setExpanded(null); return }
    setExpanded(invoiceId)

    if (!lineItems[invoiceId]) {
      const [liRes, clRes] = await Promise.all([
        supabase.from('invoice_line_items').select('*').eq('invoice_id', invoiceId),
        supabase.from('insurance_claims').select('*').eq('invoice_id', invoiceId),
      ])
      setLineItems(l => ({ ...l, [invoiceId]: liRes.data ?? [] }))
      setClaims(c => ({ ...c, [invoiceId]: clRes.data ?? [] }))
    }
  }

  const CLAIM_COLORS = {
    draft:'badge-gray', submitted:'badge-blue', acknowledged:'badge-blue',
    pending_info:'badge-amber', approved:'badge-green', partially_approved:'badge-amber',
    denied:'badge-red', appealed:'badge-amber', paid:'badge-green',
  }

  const totalRevenue   = invoices.reduce((s,i) => s + parseFloat(i.total_amount||0), 0)
  const totalCollected = invoices.reduce((s,i) => s + parseFloat(i.paid_amount||0), 0)
  const totalOutstanding = invoices.reduce((s,i) => s + parseFloat(i.balance_due||0), 0)

  return (
    <div className="animate-in">
      <div className="stat-grid" style={{marginBottom:20}}>
        <div className="stat-card">
          <span className="stat-label">Total Billed</span>
          <span className="stat-value">${totalRevenue.toFixed(0)}</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Collected</span>
          <span className="stat-value" style={{color:'var(--accent)'}}>${totalCollected.toFixed(0)}</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Outstanding</span>
          <span className="stat-value" style={{color:'var(--amber)'}}>${totalOutstanding.toFixed(0)}</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Collection Rate</span>
          <span className="stat-value">
            {totalRevenue > 0 ? Math.round(totalCollected / totalRevenue * 100) : 0}%
          </span>
        </div>
      </div>

      <div className="toolbar">
        <div style={{display:'flex',gap:8}}>
          {['all','unpaid','paid'].map(f => (
            <button
              key={f}
              className={`btn ${filter === f ? 'btn-primary' : 'btn-ghost'}`}
              style={{padding:'6px 14px',fontSize:12,textTransform:'capitalize'}}
              onClick={() => setFilter(f)}
            >{f}</button>
          ))}
        </div>
      </div>

      <div style={{display:'flex',flexDirection:'column',gap:10}}>
        {loading ? (
          [...Array(4)].map((_,i) => <div key={i} className="card skeleton" style={{height:64}} />)
        ) : invoices.length === 0 ? (
          <div className="empty-state">No invoices found</div>
        ) : invoices.map(inv => (
          <div key={inv.invoice_id} className="card" style={{padding:0,overflow:'hidden'}}>
            <div
              style={{display:'flex',alignItems:'center',gap:16,padding:'14px 24px',cursor:'pointer'}}
              onClick={() => expand(inv.invoice_id)}
            >
              <div style={{flex:1}}>
                <div style={{fontWeight:600}}>{inv.patient_name}</div>
                <div style={{color:'var(--text3)',fontSize:11,marginTop:2,fontFamily:'var(--font-display)'}}>
                  {format(new Date(inv.created_at), 'MMM d, yyyy')} · Due {format(new Date(inv.due_date), 'MMM d')}
                </div>
              </div>
              <div style={{textAlign:'right',marginRight:8}}>
                <div style={{fontFamily:'var(--font-display)',fontWeight:700,fontSize:16}}>
                  ${parseFloat(inv.total_amount).toFixed(2)}
                </div>
                {!inv.is_paid && parseFloat(inv.balance_due) > 0 && (
                  <div style={{color:'var(--amber)',fontSize:11}}>
                    ${parseFloat(inv.balance_due).toFixed(2)} due
                  </div>
                )}
              </div>
              <span className={`badge ${inv.is_paid ? 'badge-green' : 'badge-amber'}`}>
                {inv.is_paid ? 'Paid' : 'Unpaid'}
              </span>
              {expanded === inv.invoice_id
                ? <ChevronUp size={16} color="var(--text3)"/>
                : <ChevronDown size={16} color="var(--text3)"/>
              }
            </div>

            {expanded === inv.invoice_id && (
              <div style={{borderTop:'1px solid var(--border)',padding:'20px 24px',background:'var(--bg3)'}}>
                <div className="two-col" style={{marginBottom:0}}>
                  <div>
                    <p className="section-title" style={{marginBottom:10}}>Line Items</p>
                    <table>
                      <thead>
                        <tr>
                          <th>Description</th>
                          <th>CPT</th>
                          <th>Qty</th>
                          <th>Unit</th>
                          <th>Total</th>
                        </tr>
                      </thead>
                      <tbody>
                        {(lineItems[inv.invoice_id] ?? []).map(li => (
                          <tr key={li.line_id}>
                            <td>{li.description}</td>
                            <td style={{color:'var(--text3)',fontFamily:'var(--font-display)',fontSize:11}}>{li.cpt_code ?? '—'}</td>
                            <td style={{color:'var(--text2)'}}>{li.quantity}</td>
                            <td style={{color:'var(--text2)'}}>${parseFloat(li.unit_price).toFixed(2)}</td>
                            <td style={{fontWeight:600}}>${parseFloat(li.line_total).toFixed(2)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <div>
                    <p className="section-title" style={{marginBottom:10}}>Insurance Claims</p>
                    {(claims[inv.invoice_id] ?? []).length === 0 ? (
                      <div style={{color:'var(--text3)',fontSize:12}}>No insurance claims</div>
                    ) : (claims[inv.invoice_id] ?? []).map(c => (
                      <div key={c.claim_id} style={{
                        padding:'12px 16px',background:'var(--surface)',
                        borderRadius:8,border:'1px solid var(--border)',marginBottom:8
                      }}>
                        <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:6}}>
                          <span style={{fontWeight:600}}>{c.insurance_provider}</span>
                          <span className={`badge ${CLAIM_COLORS[c.status]??'badge-gray'}`}>{c.status}</span>
                        </div>
                        <div style={{fontSize:12,color:'var(--text2)',display:'flex',gap:16}}>
                          <span>Claimed: <strong>${parseFloat(c.claim_amount).toFixed(2)}</strong></span>
                          {c.approved_amount && <span>Approved: <strong style={{color:'var(--accent)'}}>${parseFloat(c.approved_amount).toFixed(2)}</strong></span>}
                        </div>
                        {c.denial_reason && (
                          <div style={{fontSize:11,color:'var(--red)',marginTop:4}}>{c.denial_reason}</div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
