import { NavLink, useNavigate } from 'react-router-dom'
import { useState, useEffect } from 'react'
import {
  LayoutDashboard, Target, Terminal,
  Server, Settings, LogOut, Sun, Moon, Shield,
} from 'lucide-react'
import useAuthStore from '../../store/auth'
import Logo from '../../assets/Logo'

const nav = [
  { section: 'Overview' },
  { to: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/sessions',  icon: Shield,          label: 'Sessions' },
  { section: 'Session' },
  { to: '/terminal',  icon: Terminal,        label: 'Terminal' },
  { to: '/vms',       icon: Server,          label: 'VMs' },
]

const navAdmin = [
  { section: 'Admin' },
  { to: '/admin', icon: Settings, label: 'Settings' },
]

const S = {
  shell:    { display: 'flex', height: '100vh', overflow: 'hidden' },
  sidebar:  {
    width: 200, flexShrink: 0,
    background: 'var(--bg)', borderRight: '1px solid var(--border)',
    display: 'flex', flexDirection: 'column',
  },
  logoWrap: {
    padding: '20px 18px 16px',
    borderBottom: '1px solid var(--border)',
    display: 'flex', alignItems: 'center', gap: 10,
  },
  logoText: { fontSize: 14, fontWeight: 700, letterSpacing: 4 },
  logoSub:  { fontSize: 9, letterSpacing: 1.5, color: 'var(--text3)', marginTop: 2 },
  nav:      { flex: 1, padding: '12px 0', overflowY: 'auto' },
  section:  { padding: '10px 18px 4px', fontSize: 10, color: 'var(--text3)', letterSpacing: 1, textTransform: 'uppercase' },
  navItem:  (active) => ({
    display: 'flex', alignItems: 'center', gap: 9,
    padding: '7px 18px', fontSize: 12,
    color: active ? 'var(--text)' : 'var(--text2)',
    fontWeight: active ? 500 : 400,
    cursor: 'pointer', textDecoration: 'none',
    transition: 'color 0.1s',
    borderLeft: `2px solid ${active ? 'var(--text)' : 'transparent'}`,
  }),
  bottom:   { padding: '14px 18px', borderTop: '1px solid var(--border)' },
  userName: { fontSize: 12, fontWeight: 500 },
  userRole: (t) => ({
    fontSize: 11,
    color: t === 'red' ? 'var(--red)' : t === 'blue' ? 'var(--blue)' : 'var(--text3)',
    marginTop: 2,
  }),
  themeBtn: {
    marginTop: 12, background: 'none', border: 'none',
    color: 'var(--text3)', cursor: 'pointer', fontSize: 11,
    padding: 0, display: 'flex', alignItems: 'center', gap: 6,
  },
  main:     { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  topbar:   {
    height: 48, borderBottom: '1px solid var(--border)',
    display: 'flex', alignItems: 'center',
    justifyContent: 'space-between', padding: '0 24px', flexShrink: 0,
  },
  topTitle: { fontSize: 13, fontWeight: 500 },
  topRight: { display: 'flex', alignItems: 'center', gap: 8 },
  content:  { flex: 1, overflowY: 'auto' },
}

export default function Layout({ children, title, action }) {
  const { user, logout } = useAuthStore()
  const navigate = useNavigate()
  const [dark, setDark] = useState(
    () => localStorage.getItem('coco_theme') !== 'light'
  )

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light')
    localStorage.setItem('coco_theme', dark ? 'dark' : 'light')
  }, [dark])

  const allNav = user?.role === 'admin' ? [...nav, ...navAdmin] : nav

  return (
    <div style={S.shell}>
      <aside style={S.sidebar}>
        <div style={S.logoWrap}>
          <Logo size={30} />
          <div>
            <div style={S.logoText}>COCO</div>
            <div style={S.logoSub}>ATTACK & DEFENSE</div>
          </div>
        </div>

        <nav style={S.nav}>
          {allNav.map((item, i) =>
            item.section ? (
              <div key={i} style={S.section}>{item.section}</div>
            ) : (
              <NavLink key={item.to} to={item.to}
                style={({ isActive }) => S.navItem(isActive)}>
                <item.icon size={14} />
                {item.label}
              </NavLink>
            )
          )}
        </nav>

        <div style={S.bottom}>
          <div style={S.userName}>{user?.username || '—'}</div>
          <div style={S.userRole(user?.team_type)}>
            {user?.team_type === 'red'
              ? 'Red Team'
              : user?.team_type === 'blue'
              ? 'Blue Team'
              : user?.role === 'admin' ? 'Admin' : '—'}
          </div>
          <button style={S.themeBtn} onClick={() => setDark(d => !d)}>
            {dark ? <Sun size={13} /> : <Moon size={13} />}
            {dark ? 'Light mode' : 'Dark mode'}
          </button>
          <button
            style={{ ...S.themeBtn, marginTop: 8 }}
            onClick={() => { logout(); navigate('/login') }}
          >
            <LogOut size={13} /> Sign out
          </button>
        </div>
      </aside>

      <div style={S.main}>
        <div style={S.topbar}>
          <span style={S.topTitle}>{title}</span>
          <div style={S.topRight}>{action}</div>
        </div>
        <div style={S.content}>{children}</div>
      </div>
    </div>
  )
}
