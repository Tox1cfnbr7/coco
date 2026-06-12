import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Plus, Play, Skull, Clock, Shield, Sword } from 'lucide-react'
import { sessionsApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Layout from '../../components/layout/Layout'

const MODE_LABELS = {
  initial_access:  'Initial Access',
  full_compromise: 'Full Compromise',
  ransomware_sim:  'Ransomware Sim',
  purple_team:     'Purple Team',
}

const STATUS_COLOR = {
  waiting:      'var(--text3)',
  provisioning: 'var(--yellow)',
  running:      'var(--green)',
  ended:        'var(--text3)',
  error:        'var(--red)',
}

export default function Sessions() {
  const [sessions, setSessions]   = useState([])
  const [creating, setCreating]   = useState(false)
  const [loading, setLoading]     = useState(true)
  const { user }                  = useAuthStore()
  const navigate                  = useNavigate()

  const [form, setForm] = useState({
    name:                 '',
    mode:                 'full_compromise',
    duration:             'standard',
    vuln_difficulty:      'medium',
    max_downtime_minutes: 30,
  })

  useEffect(() => {
    sessionsApi.list().then(r => setSessions(r.data)).finally(() => setLoading(false))
  }, [])

  const handleCreate = async () => {
    if (!form.name.trim()) return
    try {
      const res = await sessionsApi.create(form)
      setSessions(s => [res.data, ...s])
      setCreating(false)
      setForm({ name: '', mode: 'full_compromise', duration: 'standard',
                vuln_difficulty: 'medium', max_downtime_minutes: 30 })
    } catch (e) {
      alert(e.response?.data?.detail || 'Error creating session')
    }
  }

  const handleStart = async (id, e) => {
    e.stopPropagation()
    await sessionsApi.start(id)
    setSessions(s => s.map(x => x.id === id ? { ...x, status: 'provisioning' } : x))
  }

  const handleKill = async (id, e) => {
    e.stopPropagation()
    if (!confirm('Kill this session? All VMs will be deleted.')) return
    await sessionsApi.kill(id)
    setSessions(s => s.map(x => x.id === id ? { ...x, status: 'ended' } : x))
  }

  const action = user?.role === 'admin' && (
    <button className="btn btn-solid" onClick={() => setCreating(true)}>
      <Plus size={13} /> New Session
    </button>
  )

  return (
    <Layout title="Sessions" action={action}>
      <div style={{ padding: 24 }}>

        {/* Create form */}
        {creating && (
          <div style={{
            background: 'var(--bg2)', border: '1px solid var(--border)',
            borderRadius: 10, padding: 20, marginBottom: 24,
          }}>
            <div style={{ fontWeight: 600, marginBottom: 16 }}>New Session</div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <div>
                <label style={labelStyle}>Session Name</label>
                <input style={inputStyle} placeholder="e.g. Red vs Blue — June"
                  value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} />
              </div>
              <div>
                <label style={labelStyle}>Game Mode</label>
                <select style={inputStyle} value={form.mode}
                  onChange={e => setForm(f => ({ ...f, mode: e.target.value }))}>
                  <option value="initial_access">Initial Access (2-3h)</option>
                  <option value="full_compromise">Full Compromise (4-6h)</option>
                  <option value="ransomware_sim">Ransomware Sim (4-8h)</option>
                  <option value="purple_team">Purple Team (Training)</option>
                </select>
              </div>
              <div>
                <label style={labelStyle}>Duration</label>
                <select style={inputStyle} value={form.duration}
                  onChange={e => setForm(f => ({ ...f, duration: e.target.value }))}>
                  <option value="quick">Quick (2h)</option>
                  <option value="standard">Standard (4h)</option>
                  <option value="long">Long (8h)</option>
                  <option value="unlimited">Unlimited</option>
                </select>
              </div>
              <div>
                <label style={labelStyle}>Vuln Difficulty</label>
                <select style={inputStyle} value={form.vuln_difficulty}
                  onChange={e => setForm(f => ({ ...f, vuln_difficulty: e.target.value }))}>
                  <option value="easy">Easy (1 vuln/category)</option>
                  <option value="medium">Medium (2 vulns/category)</option>
                  <option value="hard">Hard (3 vulns/category)</option>
                </select>
              </div>
              <div>
                <label style={labelStyle}>Max Downtime (minutes)</label>
                <input style={inputStyle} type="number" min={10} max={120}
                  value={form.max_downtime_minutes}
                  onChange={e => setForm(f => ({ ...f, max_downtime_minutes: +e.target.value }))} />
              </div>
            </div>

            <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
              <button className="btn btn-solid" onClick={handleCreate}>Create Session</button>
              <button className="btn" onClick={() => setCreating(false)}>Cancel</button>
            </div>
          </div>
        )}

        {/* Sessions list */}
        {loading ? (
          <div style={{ color: 'var(--text3)', fontSize: 13 }}>Loading...</div>
        ) : sessions.length === 0 ? (
          <div style={{ color: 'var(--text3)', fontSize: 13, padding: '32px 0' }}>
            No sessions yet. {user?.role === 'admin' ? 'Create one above.' : 'Ask an admin to create a session.'}
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {sessions.map(s => (
              <div key={s.id}
                onClick={() => navigate(`/sessions/${s.id}`)}
                style={{
                  background: 'var(--bg2)', border: '1px solid var(--border)',
                  borderRadius: 8, padding: '14px 18px',
                  cursor: 'pointer', display: 'flex',
                  alignItems: 'center', gap: 16,
                  transition: 'border-color 0.15s',
                }}
                onMouseEnter={e => e.currentTarget.style.borderColor = 'var(--text3)'}
                onMouseLeave={e => e.currentTarget.style.borderColor = 'var(--border)'}
              >
                {/* Status dot */}
                <div style={{
                  width: 8, height: 8, borderRadius: '50%',
                  background: STATUS_COLOR[s.status] || 'var(--text3)',
                  flexShrink: 0,
                  boxShadow: s.status === 'running' ? '0 0 6px var(--green)' : 'none',
                }} />

                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 500, fontSize: 13 }}>{s.name}</div>
                  <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 2 }}>
                    {MODE_LABELS[s.mode]} · {s.duration} · {s.difficulty}
                  </div>
                </div>

                <div style={{ fontSize: 11, color: 'var(--text3)', textAlign: 'right' }}>
                  <div style={{ color: STATUS_COLOR[s.status], fontWeight: 500 }}>
                    {s.status}
                  </div>
                  {s.started_at && (
                    <div style={{ marginTop: 2 }}>
                      {new Date(s.started_at).toLocaleDateString()}
                    </div>
                  )}
                </div>

                {user?.role === 'admin' && (
                  <div style={{ display: 'flex', gap: 6 }} onClick={e => e.stopPropagation()}>
                    {s.status === 'waiting' && (
                      <button className="btn btn-solid"
                        style={{ padding: '4px 10px', fontSize: 11 }}
                        onClick={e => handleStart(s.id, e)}>
                        <Play size={11} /> Start
                      </button>
                    )}
                    {['running', 'provisioning', 'error'].includes(s.status) && (
                      <button className="btn"
                        style={{ padding: '4px 10px', fontSize: 11, color: 'var(--red)' }}
                        onClick={e => handleKill(s.id, e)}>
                        <Skull size={11} /> Kill
                      </button>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </Layout>
  )
}

const labelStyle = {
  display: 'block', fontSize: 11, color: 'var(--text3)',
  marginBottom: 4, textTransform: 'uppercase', letterSpacing: 0.5,
}
const inputStyle = {
  width: '100%', background: 'var(--bg)', border: '1px solid var(--border)',
  borderRadius: 6, padding: '7px 10px', color: 'var(--text)', fontSize: 12,
  boxSizing: 'border-box',
}
