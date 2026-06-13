import { useEffect, useState, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Skull, RefreshCw, Terminal, Flag, Activity, AlertTriangle } from 'lucide-react'
import { sessionsApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Layout from '../../components/layout/Layout'

const STATUS_COLOR = {
  waiting:      'var(--text3)',
  provisioning: 'var(--yellow)',
  running:      'var(--green)',
  ended:        'var(--text3)',
  error:        'var(--red)',
}

const VM_STATUS_COLOR = {
  creating: 'var(--yellow)',
  running:  'var(--green)',
  stopped:  'var(--text3)',
  error:    'var(--red)',
}

export default function SessionDetail() {
  const { id }           = useParams()
  const [session, setSession]   = useState(null)
  const [vms, setVms]           = useState([])
  const [scoreboard, setScoreboard] = useState(null)
  const [flag, setFlag]         = useState('')
  const [flagMsg, setFlagMsg]   = useState(null)
  const [milestone, setMilestone] = useState('')
  const [loading, setLoading]   = useState(true)
  const { user }                = useAuthStore()
  const navigate                = useNavigate()
  const intervalRef             = useRef(null)

  const load = async () => {
    try {
      const [s, v, sb] = await Promise.all([
        sessionsApi.get(id),
        sessionsApi.vms(id),
        sessionsApi.scoreboard(id),
      ])
      setSession(s.data)
      setVms(v.data)
      setScoreboard(sb.data)
    } catch {
      navigate('/sessions')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    intervalRef.current = setInterval(load, 15000)  // refresh every 15s
    return () => clearInterval(intervalRef.current)
  }, [id])

  const handleKill = async () => {
    if (!confirm('Kill this session? All VMs will be destroyed.')) return
    await sessionsApi.kill(id)
    load()
  }

  const handleFlagSubmit = async () => {
    try {
      const res = await sessionsApi.submitFlag(id, flag)
      setFlagMsg({ ok: true, msg: res.data.message })
      setFlag('')
      load()
    } catch (e) {
      setFlagMsg({ ok: false, msg: e.response?.data?.detail || 'Wrong flag' })
    }
  }

  const handleMilestone = async () => {
    if (!milestone) return
    try {
      const res = await sessionsApi.milestone(id, milestone)
      alert(`Milestone reported: +${res.data.points_awarded} pts`)
      setMilestone('')
      load()
    } catch (e) {
      alert(e.response?.data?.detail || 'Error')
    }
  }

  if (loading || !session) {
    return (
      <Layout title="Session">
        <div style={{ padding: 24, color: 'var(--text3)', fontSize: 13 }}>Loading...</div>
      </Layout>
    )
  }

  const isRunning = session.status === 'running'
  const isAdmin   = user?.role === 'admin'

  // ── Red Team win → full-screen "YOU GOT HACKED" takeover ──
  const endEvent = scoreboard?.events?.find(
    e => e.type === 'red_wins' || e.type === 'blue_lost_downtime'
  )
  const allFlagsCaptured =
    scoreboard?.flags?.length > 0 && scoreboard.flags.every(f => f.captured)
  const redWon = session.status === 'ended' && (endEvent || allFlagsCaptured)

  if (redWon) {
    return (
      <div style={{
        minHeight: '100vh', background: '#0a0000',
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        color: '#cc0000', textAlign: 'center', padding: 24,
      }}>
        <div style={{ fontSize: 110, lineHeight: 1, marginBottom: 24 }}>☠</div>
        <div style={{ fontSize: 40, fontWeight: 800, letterSpacing: 8, marginBottom: 14 }}>
          YOU GOT HACKED
        </div>
        <div style={{ fontSize: 14, color: '#aa0000', letterSpacing: 1, marginBottom: 8 }}>
          {endEvent?.detail || 'Red Team captured every flag.'}
        </div>
        <div style={{ fontSize: 12, color: '#770000', marginBottom: 40 }}>
          All defended systems have been shut down.
        </div>
        <button onClick={() => navigate('/sessions')} className="btn"
          style={{ color: '#cc0000', borderColor: '#cc0000', fontSize: 12 }}>
          Back to sessions
        </button>
      </div>
    )
  }

  const killAction = isAdmin && ['running', 'provisioning', 'error'].includes(session.status) && (
    <button className="btn" style={{ color: 'var(--red)' }} onClick={handleKill}>
      <Skull size={13} /> Kill Session
    </button>
  )

  return (
    <Layout title={session.name} action={killAction}>
      <div style={{ padding: 24, display: 'flex', flexDirection: 'column', gap: 20 }}>

        {/* Header */}
        <div style={{
          background: 'var(--bg2)', border: '1px solid var(--border)',
          borderRadius: 10, padding: 16,
          display: 'flex', gap: 32, alignItems: 'center',
        }}>
          <div>
            <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>Status</div>
            <div style={{ fontWeight: 600, color: STATUS_COLOR[session.status] }}>
              {session.status}
            </div>
          </div>
          <div>
            <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>Mode</div>
            <div style={{ fontWeight: 500, fontSize: 13 }}>{session.mode?.replace('_', ' ')}</div>
          </div>
          <div>
            <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>Network</div>
            <div className="mono" style={{ fontSize: 12 }}>{session.network || '—'}</div>
          </div>
          {session.started_at && (
            <div>
              <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>Started</div>
              <div style={{ fontSize: 12 }}>{new Date(session.started_at).toLocaleString()}</div>
            </div>
          )}
          <div style={{ marginLeft: 'auto' }}>
            <button className="btn" onClick={load} style={{ padding: '4px 10px' }}>
              <RefreshCw size={12} />
            </button>
          </div>
        </div>

        {/* Join codes (admin only) */}
        {isAdmin && session.teams?.some(t => t.join_code) && (
          <div style={{
            background: 'var(--bg2)', border: '1px solid var(--border)',
            borderRadius: 10, padding: 16,
          }}>
            <div style={sectionTitle}>Join Codes</div>
            <div style={{ display: 'flex', gap: 24, marginTop: 10 }}>
              {session.teams?.map(t => t.join_code && (
                <div key={t.id}>
                  <div style={{ fontSize: 11, color: t.type === 'red' ? 'var(--red)' : 'var(--blue)',
                    textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>
                    {t.type} team
                  </div>
                  <div className="mono" style={{
                    fontSize: 20, fontWeight: 700, letterSpacing: 4,
                    color: t.type === 'red' ? 'var(--red)' : 'var(--blue)',
                  }}>
                    {t.join_code}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Scoreboard */}
        {scoreboard && (
          <div style={{
            background: 'var(--bg2)', border: '1px solid var(--border)',
            borderRadius: 10, padding: 16,
          }}>
            <div style={sectionTitle}>Scoreboard</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 12 }}>
              {scoreboard.teams?.map(t => (
                <div key={t.type} style={{
                  background: 'var(--bg)', border: `1px solid ${t.type === 'red' ? 'var(--red)' : 'var(--blue)'}22`,
                  borderRadius: 8, padding: 14,
                }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{
                      fontSize: 12, fontWeight: 600,
                      color: t.type === 'red' ? 'var(--red)' : 'var(--blue)',
                      textTransform: 'uppercase', letterSpacing: 1,
                    }}>
                      {t.type} team
                    </div>
                    <div style={{ fontSize: 22, fontWeight: 700 }}>{t.score}</div>
                  </div>
                  <div style={{ display: 'flex', gap: 16, marginTop: 10, fontSize: 11 }}>
                    <div>
                      <span style={{ color: 'var(--text3)' }}>Attack </span>
                      <span style={{ color: 'var(--red)' }}>+{t.attack_points}</span>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text3)' }}>Defense </span>
                      <span style={{ color: 'var(--green)' }}>+{t.defense_points}</span>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text3)' }}>Penalties </span>
                      <span style={{ color: 'var(--red)' }}>-{t.penalty_points}</span>
                    </div>
                  </div>
                  {t.type === 'blue' && (
                    <div style={{ marginTop: 10 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between',
                        fontSize: 11, color: 'var(--text3)', marginBottom: 4 }}>
                        <span>Downtime</span>
                        <span style={{ color: t.downtime_pct > 75 ? 'var(--red)' : 'var(--text3)' }}>
                          {t.downtime_minutes}min / {t.downtime_limit}min
                        </span>
                      </div>
                      <div style={{ background: 'var(--bg2)', borderRadius: 4, height: 6, overflow: 'hidden' }}>
                        <div style={{
                          height: '100%', borderRadius: 4, transition: 'width 0.5s',
                          width: `${t.downtime_pct}%`,
                          background: t.downtime_pct > 75 ? 'var(--red)' : 'var(--yellow)',
                        }} />
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>

            {/* Flags */}
            {scoreboard.flags?.length > 0 && (
              <div style={{ marginTop: 14 }}>
                <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase',
                  letterSpacing: 0.5, marginBottom: 8 }}>Flags</div>
                <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                  {scoreboard.flags.map(f => (
                    <div key={f.service} style={{
                      padding: '4px 10px', borderRadius: 6, fontSize: 11,
                      border: '1px solid var(--border)',
                      color: f.captured ? 'var(--red)' : 'var(--text3)',
                      background: f.captured ? 'var(--red)11' : 'var(--bg)',
                    }}>
                      <Flag size={10} style={{ marginRight: 4 }} />
                      {f.service} ({f.points} pts)
                      {f.captured && ' ✓'}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* VMs */}
        <div style={{
          background: 'var(--bg2)', border: '1px solid var(--border)',
          borderRadius: 10, padding: 16,
        }}>
          <div style={sectionTitle}>Virtual Machines ({vms.length})</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 12 }}>
            {vms.length === 0 ? (
              <div style={{ color: 'var(--text3)', fontSize: 13 }}>
                No VMs yet — start the session to provision them.
              </div>
            ) : vms.map(vm => (
              <div key={vm.id} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '10px 12px', background: 'var(--bg)',
                border: '1px solid var(--border)', borderRadius: 8,
              }}>
                <div style={{
                  width: 8, height: 8, borderRadius: '50%', flexShrink: 0,
                  background: VM_STATUS_COLOR[vm.status] || 'var(--text3)',
                  boxShadow: vm.status === 'running' && vm.reachable
                    ? '0 0 6px var(--green)' : 'none',
                }} />
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 500 }}>{vm.name}</div>
                  <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 2 }}>
                    {vm.type} · {vm.role}
                    {vm.ip && <span className="mono" style={{ marginLeft: 8 }}>{vm.ip}</span>}
                  </div>
                </div>
                <div style={{
                  fontSize: 10, padding: '2px 7px', borderRadius: 4,
                  background: vm.team === 'red' ? 'var(--red)22' : 'var(--blue)22',
                  color: vm.team === 'red' ? 'var(--red)' : 'var(--blue)',
                }}>
                  {vm.team}
                </div>
                {!vm.reachable && vm.status === 'running' && (
                  <AlertTriangle size={14} style={{ color: 'var(--yellow)' }} />
                )}
                {vm.guacamole_id && (
                  <a href={`/guacamole/#/client/${btoa(vm.guacamole_id + '\0c\0')}`}
                    target="_blank" rel="noreferrer"
                    onClick={e => e.stopPropagation()}>
                    <button className="btn" style={{ padding: '3px 8px', fontSize: 11 }}>
                      <Terminal size={11} /> Connect
                    </button>
                  </a>
                )}
              </div>
            ))}
          </div>
        </div>

        {/* Flag submit (Red Team) */}
        {isRunning && user?.team_type === 'red' && (
          <div style={{
            background: 'var(--bg2)', border: '1px solid var(--red)33',
            borderRadius: 10, padding: 16,
          }}>
            <div style={{ ...sectionTitle, color: 'var(--red)' }}>Submit Flag</div>
            <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
              <input
                style={{ ...inputStyle, flex: 1, fontFamily: 'monospace' }}
                placeholder="COCO{...}"
                value={flag}
                onChange={e => setFlag(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleFlagSubmit()}
              />
              <button className="btn btn-solid" style={{ background: 'var(--red)' }}
                onClick={handleFlagSubmit}>
                <Flag size={13} /> Submit
              </button>
            </div>
            {flagMsg && (
              <div style={{ marginTop: 8, fontSize: 12,
                color: flagMsg.ok ? 'var(--green)' : 'var(--red)' }}>
                {flagMsg.msg}
              </div>
            )}
          </div>
        )}

        {/* Milestone report (Red Team) */}
        {isRunning && user?.team_type === 'red' && (
          <div style={{
            background: 'var(--bg2)', border: '1px solid var(--border)',
            borderRadius: 10, padding: 16,
          }}>
            <div style={sectionTitle}>Report Milestone</div>
            <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
              <select style={{ ...inputStyle, flex: 1 }} value={milestone}
                onChange={e => setMilestone(e.target.value)}>
                <option value="">Select milestone...</option>
                <option value="initial_access">Initial Access (+100 pts)</option>
                <option value="lateral_movement">Lateral Movement (+200 pts)</option>
                <option value="domain_admin">Domain Admin (+300 pts)</option>
                <option value="data_exfil">Data Exfiltration (+500 pts)</option>
                <option value="persistence">Persistence (+200 pts)</option>
              </select>
              <button className="btn btn-solid" onClick={handleMilestone}
                disabled={!milestone}>Report</button>
            </div>
          </div>
        )}

        {/* Event log */}
        {scoreboard?.events?.length > 0 && (
          <div style={{
            background: 'var(--bg2)', border: '1px solid var(--border)',
            borderRadius: 10, padding: 16,
          }}>
            <div style={sectionTitle}>Event Log</div>
            <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 4 }}>
              {scoreboard.events.map((e, i) => (
                <div key={i} style={{
                  display: 'flex', gap: 12, alignItems: 'flex-start',
                  fontSize: 12, padding: '4px 0',
                  borderBottom: i < scoreboard.events.length - 1
                    ? '1px solid var(--border)' : 'none',
                }}>
                  <span className="mono" style={{ color: 'var(--text3)', fontSize: 11, flexShrink: 0 }}>
                    {new Date(e.ts).toLocaleTimeString()}
                  </span>
                  <span style={{ color: 'var(--text2)' }}>{e.detail || e.type}</span>
                  {e.points !== 0 && (
                    <span style={{
                      marginLeft: 'auto', flexShrink: 0,
                      color: e.points > 0 ? 'var(--green)' : 'var(--red)',
                      fontWeight: 600,
                    }}>
                      {e.points > 0 ? '+' : ''}{e.points}
                    </span>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </Layout>
  )
}

const sectionTitle = {
  fontSize: 11, color: 'var(--text3)',
  textTransform: 'uppercase', letterSpacing: 0.5,
}
const inputStyle = {
  background: 'var(--bg)', border: '1px solid var(--border)',
  borderRadius: 6, padding: '7px 10px', color: 'var(--text)', fontSize: 12,
}
