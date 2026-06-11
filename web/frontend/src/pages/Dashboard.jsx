import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Sword, Shield, Flag, Activity } from 'lucide-react'
import { gamesApi, adminApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Layout from '../../components/layout/Layout'

const statusColor = { waiting: 'var(--amber)', running: 'var(--green)', ended: 'var(--text3)' }
const statusDot = { waiting: '#ef9f27', running: '#639922', ended: '#5f5e5a' }

export default function Dashboard() {
  const [games, setGames] = useState([])
  const [stats, setStats] = useState(null)
  const { user } = useAuthStore()
  const navigate = useNavigate()

  useEffect(() => {
    gamesApi.list().then(r => setGames(r.data)).catch(() => {})
    if (user?.role === 'admin') {
      adminApi.stats().then(r => setStats(r.data)).catch(() => {})
    }
  }, [user])

  const statCards = stats ? [
    { label: 'Total users', value: stats.total_users, icon: Shield, color: 'var(--purple)' },
    { label: 'Running games', value: stats.running_games, icon: Activity, color: 'var(--green)' },
    { label: 'Flags captured', value: stats.flags_captured, icon: Flag, color: 'var(--red)' },
    { label: 'Total games', value: stats.total_games, icon: Sword, color: 'var(--amber)' },
  ] : []

  return (
    <Layout>
      <div style={{ padding: 28 }}>
        <div style={{ marginBottom: 24 }}>
          <h1 style={{ fontSize: 20, fontWeight: 500 }}>Dashboard</h1>
          <p style={{ color: 'var(--text2)', marginTop: 4 }}>
            Welcome back, {user?.username}
            <span style={{
              marginLeft: 8, fontSize: 11, padding: '2px 8px',
              background: user?.team_type === 'red' ? 'rgba(226,75,74,0.15)' : 'rgba(55,138,221,0.15)',
              color: user?.team_type === 'red' ? 'var(--red)' : 'var(--blue)',
              borderRadius: 20, border: `0.5px solid ${user?.team_type === 'red' ? 'var(--red)' : 'var(--blue)'}`,
            }}>
              {user?.team_type === 'red' ? 'Red Team' : 'Blue Team'}
            </span>
          </p>
        </div>

        {stats && (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 28 }}>
            {statCards.map(({ label, value, icon: Icon, color }) => (
              <div key={label} style={{
                background: 'var(--bg2)', border: '0.5px solid var(--border)',
                borderRadius: 'var(--radius-lg)', padding: '16px 18px',
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                  <span style={{ fontSize: 12, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</span>
                  <Icon size={16} color={color} />
                </div>
                <div style={{ fontSize: 28, fontWeight: 500, color }}>{value}</div>
              </div>
            ))}
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
          <h2 style={{ fontSize: 14, fontWeight: 500, color: 'var(--text2)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            Recent games
          </h2>
          {user?.role === 'admin' && (
            <button onClick={() => navigate('/games/new')} style={{
              background: 'var(--purple)', color: '#fff', border: 'none',
              padding: '6px 14px', borderRadius: 'var(--radius)', fontSize: 13,
            }}>
              New game
            </button>
          )}
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {games.length === 0 && (
            <div style={{
              background: 'var(--bg2)', border: '0.5px solid var(--border)',
              borderRadius: 'var(--radius-lg)', padding: '32px',
              textAlign: 'center', color: 'var(--text3)',
            }}>
              No games yet. {user?.role === 'admin' ? 'Create one above.' : 'Wait for an admin to start a game.'}
            </div>
          )}
          {games.map(g => (
            <div key={g.id} onClick={() => navigate(`/games/${g.id}`)}
              style={{
                background: 'var(--bg2)', border: '0.5px solid var(--border)',
                borderRadius: 'var(--radius-lg)', padding: '14px 18px',
                display: 'flex', alignItems: 'center', gap: 14,
                cursor: 'pointer', transition: 'border-color 0.15s',
              }}
              onMouseEnter={e => e.currentTarget.style.borderColor = 'var(--border2)'}
              onMouseLeave={e => e.currentTarget.style.borderColor = 'var(--border)'}
            >
              <div style={{ width: 8, height: 8, borderRadius: '50%', background: statusDot[g.status], flexShrink: 0 }} />
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 500 }}>{g.name}</div>
                <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 2 }}>
                  {g.mode.replace('_', ' ')} · {g.duration}
                  {g.flag_captured && <span style={{ color: 'var(--red)', marginLeft: 8 }}>Flag captured</span>}
                </div>
              </div>
              <div style={{ fontSize: 12, color: statusColor[g.status], fontWeight: 500 }}>{g.status}</div>
            </div>
          ))}
        </div>
      </div>
    </Layout>
  )
}
