import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Plus } from 'lucide-react'
import { gamesApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Layout from '../../components/layout/Layout'

const MODES    = ['active_directory', 'web_application', 'database']
const DURATIONS = ['quick', 'standard', 'unlimited']

export default function Games() {
  const [games, setGames]   = useState([])
  const [creating, setCreating] = useState(false)
  const [form, setForm]     = useState({ name: '', mode: 'active_directory', duration: 'quick', network_cidr: '10.10.0.0/24' })
  const [error, setError]   = useState('')
  const { user } = useAuthStore()
  const navigate = useNavigate()

  useEffect(() => {
    gamesApi.list().then(r => setGames(r.data)).catch(() => {})
  }, [])

  const create = async (e) => {
    e.preventDefault()
    setError('')
    try {
      const res = await gamesApi.create(form)
      navigate(`/games/${res.data.id}`)
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to create game')
    }
  }

  const action = user?.role === 'admin' && (
    <button className="btn btn-solid" onClick={() => setCreating(c => !c)}>
      <Plus size={13} /> {creating ? 'Cancel' : 'New game'}
    </button>
  )

  return (
    <Layout title="Games" action={action}>
      <div style={{ padding: 24 }}>

        {creating && (
          <div style={{ borderBottom: '1px solid var(--border)', marginBottom: 24, paddingBottom: 24 }}>
            <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 16 }}>New game</div>
            <form onSubmit={create}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 20, marginBottom: 16 }}>
                <div>
                  <label style={{ fontSize: 11, color: 'var(--text2)', display: 'block', marginBottom: 4 }}>Name</label>
                  <input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                    placeholder="Corp Sim 2026" required />
                </div>
                <div>
                  <label style={{ fontSize: 11, color: 'var(--text2)', display: 'block', marginBottom: 4 }}>Mode</label>
                  <select value={form.mode} onChange={e => setForm(f => ({ ...f, mode: e.target.value }))}
                    style={{ borderBottom: '1px solid var(--border2)', padding: '7px 0' }}>
                    {MODES.map(m => <option key={m} value={m}>{m.replace(/_/g, ' ')}</option>)}
                  </select>
                </div>
                <div>
                  <label style={{ fontSize: 11, color: 'var(--text2)', display: 'block', marginBottom: 4 }}>Duration</label>
                  <select value={form.duration} onChange={e => setForm(f => ({ ...f, duration: e.target.value }))}
                    style={{ borderBottom: '1px solid var(--border2)', padding: '7px 0' }}>
                    {DURATIONS.map(d => <option key={d} value={d}>{d}</option>)}
                  </select>
                </div>
              </div>
              {error && <div style={{ fontSize: 12, color: 'var(--red)', marginBottom: 12 }}>{error}</div>}
              <button type="submit" className="btn btn-solid" style={{ fontSize: 12 }}>Create game</button>
            </form>
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 90px', padding: '7px 0', borderBottom: '1px solid var(--border)', marginBottom: 2 }}>
          {['Game', 'Mode', 'Status', 'Timer'].map(h => (
            <div key={h} style={{ fontSize: 10, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{h}</div>
          ))}
        </div>

        {games.length === 0 && (
          <div style={{ padding: '32px 0', color: 'var(--text3)' }}>No games yet.</div>
        )}

        {games.map(g => (
          <div key={g.id} onClick={() => navigate(`/games/${g.id}`)}
            style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 90px', padding: '11px 0', borderBottom: '1px solid var(--border)', cursor: 'pointer', alignItems: 'center' }}
            onMouseEnter={e => e.currentTarget.style.background = 'var(--bg2)'}
            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
          >
            <div>
              <div style={{ fontWeight: 500 }}>{g.name}</div>
              <div style={{ fontSize: 11, color: 'var(--text2)', marginTop: 2 }}>{g.duration}</div>
            </div>
            <div style={{ color: 'var(--text2)', fontSize: 12 }}>{g.mode?.replace('_', ' ')}</div>
            <div><span className={`tag tag-${g.status === 'running' ? 'run' : g.status === 'waiting' ? 'wait' : 'end'}`}>{g.status}</span></div>
            <div className="mono" style={{ fontSize: 12, color: 'var(--text2)' }}>—</div>
          </div>
        ))}
      </div>
    </Layout>
  )
}
