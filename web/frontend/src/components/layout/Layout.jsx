import { NavLink, useNavigate } from 'react-router-dom'
import { LayoutDashboard, Sword, Users, Flag, Server, Settings, User, LogOut, Sun, Moon } from 'lucide-react'
import useAuthStore from '../../store/auth'
import { useState, useEffect } from 'react'

const nav = [
  { to: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/games', icon: Sword, label: 'Games' },
  { to: '/teams', icon: Users, label: 'Teams' },
  { to: '/flags', icon: Flag, label: 'Flags' },
  { to: '/vms', icon: Server, label: 'VMs' },
]

export default function Layout({ children }) {
  const { user, logout } = useAuthStore()
  const navigate = useNavigate()
  const [theme, setTheme] = useState(localStorage.getItem('coco_theme') || 'dark')

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    localStorage.setItem('coco_theme', theme)
  }, [theme])

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  return (
    <div style={{ display: 'flex', height: '100vh', overflow: 'hidden' }}>
      <aside style={{
        width: 200, background: 'var(--bg2)',
        borderRight: '0.5px solid var(--border)',
        display: 'flex', flexDirection: 'column',
        flexShrink: 0,
      }}>
        <div style={{ padding: '20px 16px 16px', borderBottom: '0.5px solid var(--border)' }}>
          <div style={{ fontSize: 20, fontWeight: 600, color: 'var(--purple)', letterSpacing: 2 }}>COCO</div>
          <div style={{ fontSize: 10, color: 'var(--text3)', letterSpacing: 1, marginTop: 2 }}>ATTACK & DEFENSE</div>
        </div>

        <nav style={{ flex: 1, padding: '12px 0' }}>
          {nav.map(({ to, icon: Icon, label }) => (
            <NavLink key={to} to={to} style={({ isActive }) => ({
              display: 'flex', alignItems: 'center', gap: 10,
              padding: '9px 16px', color: isActive ? 'var(--purple)' : 'var(--text2)',
              background: isActive ? 'rgba(127,119,221,0.1)' : 'transparent',
              borderLeft: isActive ? '2px solid var(--purple)' : '2px solid transparent',
              textDecoration: 'none', fontSize: 13, transition: 'all 0.15s',
            })}>
              <Icon size={16} />
              {label}
            </NavLink>
          ))}
          {user?.role === 'admin' && (
            <NavLink to="/admin" style={({ isActive }) => ({
              display: 'flex', alignItems: 'center', gap: 10,
              padding: '9px 16px', color: isActive ? 'var(--purple)' : 'var(--text2)',
              background: isActive ? 'rgba(127,119,221,0.1)' : 'transparent',
              borderLeft: isActive ? '2px solid var(--purple)' : '2px solid transparent',
              textDecoration: 'none', fontSize: 13,
            })}>
              <Settings size={16} />
              Admin
            </NavLink>
          )}
        </nav>

        <div style={{ padding: '12px 0', borderTop: '0.5px solid var(--border)' }}>
          <button onClick={() => setTheme(t => t === 'dark' ? 'light' : 'dark')}
            style={{
              display: 'flex', alignItems: 'center', gap: 10,
              padding: '9px 16px', width: '100%', background: 'none',
              border: 'none', color: 'var(--text2)', fontSize: 13,
            }}>
            {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
            {theme === 'dark' ? 'Light mode' : 'Dark mode'}
          </button>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '9px 16px', color: 'var(--text2)', fontSize: 13,
          }}>
            <User size={16} />
            {user?.username || '—'}
          </div>
          <button onClick={handleLogout} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '9px 16px', width: '100%', background: 'none',
            border: 'none', color: 'var(--text2)', fontSize: 13,
          }}>
            <LogOut size={16} />
            Logout
          </button>
        </div>
      </aside>

      <main style={{ flex: 1, overflow: 'auto', background: 'var(--bg)' }}>
        {children}
      </main>
    </div>
  )
}
