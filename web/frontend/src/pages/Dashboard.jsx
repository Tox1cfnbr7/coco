import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Plus } from 'lucide-react'
import { gamesApi, adminApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Layout from '../../components/layout/Layout'

const COL = 'grid-template-columns: 2fr 1fr 1fr 90px'

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
  }, [])

  const action = user?.role === 'admin' && (
    <button className="btn btn-solid" onClick={() => navigate('/games/new')}>
      <Plus size={13} /> New game
    </button>
  )

  return (
    <Layout title="Dashboard" action={action}>
      <div style={{ padding: '24px' }}>

        {stats && (
          <div style={{ display: 'flex', gap: 40, paddingBottom: 20, borderBottom: '1px solid var(--border)', marginBottom: 20 }}>
            {[
              { n: stats.running_games, l: 'Running games' },
              { n: stats.flags_captured, l: 'Flags captured', c: 'var(--red)' },
              { n: stats.total_users, l: 'Total players' },
              { n: stats.total_games, l: 'Total games' },
            ].map(({ n, l, c }) => (
              <div key={l}>
                <div style={{ fontSize: 22, fontWeight: 600, letterSpacing: -0.5, color: c || 'var(--text)' }}>{n}</div>
                <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5, marginTop: 3 }}>{l}</div>
              </div>
            ))}
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 90px', padding: '7px 0', borderBottom: '1px solid var(--border)', marginBottom: 2 }}>
          {['Game', 'Mode', 'Status', 'Timer'].map(h => (
            <div key={h} style={{ fontSize: 10, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{h}</div>
          ))}
        </div>

        {games.length === 0 && (
          <div style={{ padding: '32px 0', color: 'var(--text3)', fontSize: 13 }}>
            No games yet.{user?.role === 'admin' ? ' Create one above.' : ' Wait for an admin to create a game.'}
          </div>
        )}

        {games.map(g => (
          <div key={g.id} onClick={() => navigate(`/games/${g.id}`)}
            style={{
              display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 90px',
              padding: '11px 0', borderBottom: '1px solid var(--border)',
              cursor: 'pointer', alignItems: 'center',
            }}
            onMouseEnter={e => e.currentTarget.style.background = 'var(--bg2)'}
            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
          >
            <div>
              <div style={{ fontWeight: 500 }}>{g.name}</div>
              <div style={{ fontSize: 11, color: 'var(--text2)', marginTop: 2 }}>{g.duration}</div>
            </div>
            <div style={{ color: 'var(--text2)' }}>{g.mode?.replace('_', ' ')}</div>
            <div>
              <span className={`tag tag-${g.status === 'running' ? 'run' : g.status === 'waiting' ? 'wait' : 'end'}`}>
                {g.status}
              </span>
            </div>
            <div className="mono" style={{ fontSize: 12, color: 'var(--text2)' }}>
              {g.status === 'running' ? '—:——:——' : '—'}
            </div>
          </div>
        ))}
      </div>
    </Layout>
  )
}
