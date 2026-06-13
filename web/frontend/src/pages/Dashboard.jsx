import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Plus } from 'lucide-react'
import { sessionsApi, adminApi } from '../lib/api'
import useAuthStore from '../store/auth'
import Layout from '../components/layout/Layout'

const MODE_LABELS = {
  initial_access:  'Initial Access',
  full_compromise: 'Full Compromise',
  ransomware_sim:  'Ransomware Sim',
  purple_team:     'Purple Team',
}

export default function Dashboard() {
  const [sessions, setSessions] = useState([])
  const [stats, setStats] = useState(null)
  const { user } = useAuthStore()
  const navigate = useNavigate()

  useEffect(() => {
    sessionsApi.list().then(r => setSessions(r.data)).catch(() => {})
    if (user?.role === 'admin') {
      adminApi.stats().then(r => setStats(r.data)).catch(() => {})
    }
  }, [])

  const action = user?.role === 'admin' && (
    <button className="btn btn-solid" onClick={() => navigate('/sessions')}>
      <Plus size={13} /> New session
    </button>
  )

  return (
    <Layout title="Dashboard" action={action}>
      <div style={{ padding: '24px' }}>

        {stats && (
          <div style={{ display: 'flex', gap: 40, paddingBottom: 20, borderBottom: '1px solid var(--border)', marginBottom: 20 }}>
            {[
              { n: stats.running_games, l: 'Running sessions' },
              { n: stats.flags_captured, l: 'Flags captured', c: 'var(--red)' },
              { n: stats.total_users, l: 'Total players' },
              { n: stats.total_games, l: 'Total sessions' },
            ].map(({ n, l, c }) => (
              <div key={l}>
                <div style={{ fontSize: 22, fontWeight: 600, letterSpacing: -0.5, color: c || 'var(--text)' }}>{n ?? '—'}</div>
                <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5, marginTop: 3 }}>{l}</div>
              </div>
            ))}
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 110px', padding: '7px 0', borderBottom: '1px solid var(--border)', marginBottom: 2 }}>
          {['Session', 'Mode', 'Status', 'Difficulty'].map(h => (
            <div key={h} style={{ fontSize: 10, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{h}</div>
          ))}
        </div>

        {sessions.length === 0 && (
          <div style={{ padding: '32px 0', color: 'var(--text3)', fontSize: 13 }}>
            No sessions yet.{user?.role === 'admin' ? ' Create one from the Sessions page.' : ' Wait for an admin to create a session.'}
          </div>
        )}

        {sessions.map(s => (
          <div key={s.id} onClick={() => navigate(`/sessions/${s.id}`)}
            style={{
              display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 110px',
              padding: '11px 0', borderBottom: '1px solid var(--border)',
              cursor: 'pointer', alignItems: 'center',
            }}
            onMouseEnter={e => e.currentTarget.style.background = 'var(--bg2)'}
            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
          >
            <div>
              <div style={{ fontWeight: 500 }}>{s.name}</div>
              <div style={{ fontSize: 11, color: 'var(--text2)', marginTop: 2 }}>{s.duration}</div>
            </div>
            <div style={{ color: 'var(--text2)' }}>{MODE_LABELS[s.mode] || s.mode}</div>
            <div>
              <span className={`tag tag-${s.status === 'running' ? 'run' : s.status === 'waiting' ? 'wait' : s.status === 'error' ? 'err' : 'end'}`}>
                {s.status}
              </span>
            </div>
            <div className="mono" style={{ fontSize: 12, color: 'var(--text2)' }}>
              {s.difficulty || '—'}
            </div>
          </div>
        ))}
      </div>
    </Layout>
  )
}
