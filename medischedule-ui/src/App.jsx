import { BrowserRouter, Routes, Route, NavLink, useLocation } from 'react-router-dom'
import {
  LayoutDashboard, Calendar, Users, UserRound,
  ListOrdered, Receipt, ScrollText, Activity
} from 'lucide-react'
import Dashboard    from './pages/Dashboard'
import Appointments from './pages/Appointments'
import Doctors      from './pages/Doctors'
import Patients     from './pages/Patients'
import Waitlist     from './pages/Waitlist'
import Billing      from './pages/Billing'
import AuditLog     from './pages/AuditLog'
import './App.css'

const NAV = [
  { to: '/',            icon: LayoutDashboard, label: 'Dashboard'    },
  { to: '/appointments',icon: Calendar,        label: 'Appointments' },
  { to: '/doctors',     icon: UserRound,       label: 'Doctors'      },
  { to: '/patients',    icon: Users,           label: 'Patients'     },
  { to: '/waitlist',    icon: ListOrdered,     label: 'Waitlist'     },
  { to: '/billing',     icon: Receipt,         label: 'Billing'      },
  { to: '/audit',       icon: ScrollText,      label: 'Audit Log'    },
]

function Sidebar() {
  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <Activity size={20} strokeWidth={2.5} />
        <span>MediSchedule</span>
      </div>
      <nav className="sidebar-nav">
        {NAV.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            end={to === '/'}
            className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
          >
            <Icon size={16} />
            <span>{label}</span>
          </NavLink>
        ))}
      </nav>
      <div className="sidebar-footer">
        <div className="db-badge">
          <span className="db-dot" />
          PostgreSQL · Supabase
        </div>
      </div>
    </aside>
  )
}

function Layout({ children }) {
  const loc = useLocation()
  const page = NAV.find(n => n.to === loc.pathname || (n.to !== '/' && loc.pathname.startsWith(n.to)))
  return (
    <div className="app-layout">
      <Sidebar />
      <main className="app-main">
        <div className="page-header">
          <h1>{page?.label ?? 'MediSchedule'}</h1>
        </div>
        <div className="page-content">
          {children}
        </div>
      </main>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Layout><Dashboard /></Layout>} />
        <Route path="/appointments" element={<Layout><Appointments /></Layout>} />
        <Route path="/doctors"      element={<Layout><Doctors /></Layout>} />
        <Route path="/patients"     element={<Layout><Patients /></Layout>} />
        <Route path="/waitlist"     element={<Layout><Waitlist /></Layout>} />
        <Route path="/billing"      element={<Layout><Billing /></Layout>} />
        <Route path="/audit"        element={<Layout><AuditLog /></Layout>} />
      </Routes>
    </BrowserRouter>
  )
}
