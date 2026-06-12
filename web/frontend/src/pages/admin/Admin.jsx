import { useEffect, useState, useRef, useCallback } from 'react'
import {
  Server, Cpu, HardDrive, Activity, Play, Square,
  RotateCw, Trash2, Terminal, Package, CheckCircle,
  XCircle, Clock, AlertTriangle, Users, BarChart2,
  RefreshCw, ChevronDown, ChevronRight, Zap, Shield,
  Database, Wifi, Eye
} from 'lucide-react'
import { adminApi } from '../../lib/api'
import Layout from '../../components/layout/Layout'

const TABS = [
  { id: 'overview',   label: 'Overview',   icon: BarChart2 },
  { id: 'templates',  label: 'Templates',  icon: Package },
  { id: 'vms',        label: 'VMs',        icon: Server },
  { id: 'sessions',   label: 'Sessions',   icon: Shield },
  { id: 'users',      label: 'Users',      icon: Users },
  { id: 'health',     label: 'Health',     icon: Activity },
]

export default function Admin() {
  const [tab, setTab] = useState('overview')

  return (
    <Layout title="Admin Panel">
      <div style={{ display: 'flex', height: '100%' }}>
        {/* Sub-nav */}
        <div style={{
          width: 160, borderRight: '1px solid var(--border)',
          padding: '12px 0', flexShrink: 0,
        }}>
          {TABS.map(t => (
            <button key={t.id}
              onClick={() => setTab(t.id)}
              style={{
                display: 'flex', alignItems: 'center', gap: 8,
                width: '100%', padding: '8px 16px',
                background: tab === t.id ? 'var(--bg2)' : 'none',
                border: 'none', borderLeft: `2px solid ${tab === t.id ? 'var(--text)' : 'transparent'}`,
                color: tab === t.id ? 'var(--text)' : 'var(--text3)',
                fontSize: 12, cursor: 'pointer', textAlign: 'left',
              }}>
              <t.icon size={13} />
              {t.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div style={{ flex: 1, overflow: 'auto' }}>
          {tab === 'overview'  && <OverviewTab />}
          {tab === 'templates' && <TemplatesTab />}
          {tab === 'vms'       && <VMsTab />}
          {tab === 'sessions'  && <SessionsTab />}
          {tab === 'users'     && <UsersTab />}
          {tab === 'health'    && <HealthTab />}
        </div>
      </div>
    </Layout>
  )
}

// ═══════════════════════════════════════════════
// OVERVIEW TAB — live Proxmox stats via WebSocket
// ═══════════════════════════════════════════════
function OverviewTab() {
  const [stats, setStats]     = useState(null)
  const [storage, setStorage] = useState([])
  const [error, setError]     = useState(null)
  const wsRef = useRef(null)

  useEffect(() => {
    // Load storage once
    adminApi.proxmoxStorage().then(r => setStorage(r.data)).catch(() => {})

    // WebSocket for live stats
    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(`${proto}://${window.location.host}/api/admin/ws/stats`)
    wsRef.current = ws

    ws.onmessage = e => {
      try {
        const d = JSON.parse(e.data)
        if (d.error) setError(d.error)
        else { setStats(d); setError(null) }
      } catch {}
    }
    ws.onerror = () => setError('WebSocket error — falling back to polling')

    // Fallback polling if WS fails
    const poll = setInterval(() => {
      if (ws.readyState !== WebSocket.OPEN) {
        adminApi.proxmoxStatus().then(r => setStats(r.data)).catch(e => setError(String(e)))
      }
    }, 5000)

    // Initial load
    adminApi.proxmoxStatus().then(r => setStats(r.data)).catch(e => setError(String(e)))

    return () => { ws.close(); clearInterval(poll) }
  }, [])

  return (
    <div style={{ padding: 24 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
        <div style={{ fontSize: 13, fontWeight: 600 }}>Proxmox Node</div>
        {error && <div style={{ fontSize: 11, color: 'var(--yellow)' }}>{error}</div>}
        {stats && <div className="mono" style={{ fontSize: 11, color: 'var(--text3)' }}>{stats.pve_version}</div>}
      </div>

      {/* Stat cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 24 }}>
        <StatCard label="CPU" value={stats ? `${stats.cpu_pct}%` : '—'}
          icon={<Cpu size={16} />} pct={stats?.cpu_pct}
          color={stats?.cpu_pct > 80 ? 'var(--red)' : 'var(--green)'} />
        <StatCard label="RAM"
          value={stats ? `${stats.ram_used_gb} / ${stats.ram_total_gb} GB` : '—'}
          icon={<Activity size={16} />} pct={stats?.ram_pct}
          color={stats?.ram_pct > 85 ? 'var(--red)' : 'var(--green)'} />
        <StatCard label="VMs Running"
          value={stats ? `${stats.vm_running} / ${stats.vm_count}` : '—'}
          icon={<Server size={16} />} pct={null} color="var(--blue)" />
        <StatCard label="Uptime"
          value={stats ? `${stats.uptime_hours}h` : '—'}
          icon={<Clock size={16} />} pct={null} color="var(--text3)" />
      </div>

      {/* Storage */}
      {storage.length > 0 && (
        <div>
          <div style={sectionTitle}>Storage</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 10 }}>
            {storage.map(s => (
              <div key={s.storage} style={card}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div>
                    <span style={{ fontSize: 13, fontWeight: 500 }}>{s.storage}</span>
                    <span style={{ fontSize: 11, color: 'var(--text3)', marginLeft: 8 }}>{s.type}</span>
                  </div>
                  <span style={{ fontSize: 12, color: s.pct > 85 ? 'var(--red)' : 'var(--text3)' }}>
                    {s.used_gb} / {s.total_gb} GB ({s.pct}%)
                  </span>
                </div>
                <ProgressBar pct={s.pct} color={s.pct > 85 ? 'var(--red)' : 'var(--blue)'} />
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════
// TEMPLATES TAB
// ═══════════════════════════════════════════════
function TemplatesTab() {
  const [templates, setTemplates]   = useState([])
  const [building, setBuilding]     = useState({})   // key → log lines[]
  const [expanded, setExpanded]     = useState({})
  const wsRefs = useRef({})

  const load = useCallback(() => {
    adminApi.templates().then(r => setTemplates(r.data)).catch(() => {})
  }, [])

  useEffect(() => { load(); const t = setInterval(load, 10000); return () => clearInterval(t) }, [load])

  const startBuild = async (key) => {
    try {
      await adminApi.buildTemplate(key)
      setBuilding(b => ({ ...b, [key]: [] }))
      setExpanded(e => ({ ...e, [key]: true }))

      // WebSocket log stream
      const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
      const ws = new WebSocket(`${proto}://${window.location.host}/api/admin/ws/logs/${key}`)
      wsRefs.current[key] = ws

      ws.onmessage = e => {
        if (e.data === '__BUILD_DONE__') {
          ws.close()
          load()
          return
        }
        setBuilding(b => ({ ...b, [key]: [...(b[key] || []), e.data] }))
      }
    } catch (err) {
      alert(err.response?.data?.detail || 'Build failed to start')
    }
  }

  const deleteTemplate = async (vmid) => {
    if (!confirm(`Delete template VMID ${vmid}?`)) return
    await adminApi.deleteTemplate(vmid)
    load()
  }

  const ROLE_COLOR = {
    attacker: 'var(--red)', 'web/linux': 'var(--green)', 'dc/mssql': 'var(--blue)',
    workstation: 'var(--text3)', 'dc-ca': 'var(--yellow)', fileserver: 'var(--text3)',
    siem: 'var(--yellow)',
  }

  return (
    <div style={{ padding: 24 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
        <div style={{ fontSize: 13, fontWeight: 600 }}>VM Templates</div>
        <button className="btn" onClick={load}><RefreshCw size={12} /></button>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {templates.map(t => (
          <div key={t.template_key} style={card}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              {/* Status indicator */}
              <div style={{
                width: 8, height: 8, borderRadius: '50%', flexShrink: 0,
                background: t.status === 'built' ? 'var(--green)'
                  : t.status === 'building' ? 'var(--yellow)'
                  : 'var(--text3)',
                boxShadow: t.status === 'building' ? '0 0 8px var(--yellow)' : 'none',
                animation: t.status === 'building' ? 'pulse 1s infinite' : 'none',
              }} />

              {/* Info */}
              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{ fontSize: 13, fontWeight: 500 }}>{t.label}</span>
                  <span style={{
                    fontSize: 10, padding: '1px 6px', borderRadius: 4,
                    background: `${ROLE_COLOR[t.role] || 'var(--text3)'}22`,
                    color: ROLE_COLOR[t.role] || 'var(--text3)',
                  }}>{t.role}</span>
                </div>
                <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 2 }}>
                  {t.ram_gb}GB RAM · {t.disk_gb}GB Disk
                  {t.vmid && <span className="mono" style={{ marginLeft: 8 }}>VMID {t.vmid}</span>}
                </div>
              </div>

              {/* Status */}
              <div style={{ fontSize: 11, color: 'var(--text3)', marginRight: 8 }}>
                {t.status === 'built'     && <span style={{ color: 'var(--green)' }}>✓ Built</span>}
                {t.status === 'building'  && <span style={{ color: 'var(--yellow)' }}>⟳ Building...</span>}
                {t.status === 'not_built' && <span>Not built</span>}
              </div>

              {/* Actions */}
              <div style={{ display: 'flex', gap: 6 }}>
                {t.status !== 'building' && (
                  <button className="btn btn-solid"
                    style={{ padding: '4px 10px', fontSize: 11 }}
                    onClick={() => startBuild(t.template_key)}>
                    <Play size={11} />
                    {t.status === 'built' ? 'Rebuild' : 'Build'}
                  </button>
                )}
                {t.vmid && (
                  <button className="btn"
                    style={{ padding: '4px 8px', color: 'var(--red)' }}
                    onClick={() => deleteTemplate(t.vmid)}>
                    <Trash2 size={11} />
                  </button>
                )}
                {building[t.template_key] && (
                  <button className="btn"
                    style={{ padding: '4px 8px' }}
                    onClick={() => setExpanded(e => ({ ...e, [t.template_key]: !e[t.template_key] }))}>
                    {expanded[t.template_key] ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
                  </button>
                )}
              </div>
            </div>

            {/* Build log */}
            {expanded[t.template_key] && building[t.template_key] && (
              <BuildLog lines={building[t.template_key]} />
            )}
          </div>
        ))}
      </div>

      <style>{`
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
      `}</style>
    </div>
  )
}

// ═══════════════════════════════════════════════
// VMs TAB
// ═══════════════════════════════════════════════
function VMsTab() {
  const [vms, setVms]       = useState([])
  const [loading, setLoading] = useState(true)

  const load = () => {
    setLoading(true)
    adminApi.proxmoxVms().then(r => setVms(r.data)).finally(() => setLoading(false))
  }
  useEffect(() => { load() }, [])

  const action = async (vmid, act) => {
    if (act === 'delete' && !confirm(`Delete VM ${vmid}?`)) return
    try {
      await adminApi.vmAction(vmid, act)
      setTimeout(load, 1500)
    } catch (e) {
      alert(e.response?.data?.detail || 'Action failed')
    }
  }

  const cocoVms  = vms.filter(v => v.is_coco && !v.is_template)
  const tplVms   = vms.filter(v => v.is_coco && v.is_template)
  const otherVms = vms.filter(v => !v.is_coco)

  return (
    <div style={{ padding: 24 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 20 }}>
        <div style={{ fontSize: 13, fontWeight: 600 }}>Virtual Machines ({vms.length})</div>
        <button className="btn" onClick={load}><RefreshCw size={12} /></button>
      </div>

      {loading ? (
        <div style={{ color: 'var(--text3)', fontSize: 13 }}>Loading...</div>
      ) : (
        <>
          {cocoVms.length > 0 && (
            <VMSection title="COCO Session VMs" vms={cocoVms} onAction={action} />
          )}
          {tplVms.length > 0 && (
            <VMSection title="Templates" vms={tplVms} onAction={action} />
          )}
          {otherVms.length > 0 && (
            <VMSection title="Other VMs" vms={otherVms} onAction={action} />
          )}
          {vms.length === 0 && (
            <div style={{ color: 'var(--text3)', fontSize: 13 }}>No VMs found.</div>
          )}
        </>
      )}
    </div>
  )
}

function VMSection({ title, vms, onAction }) {
  return (
    <div style={{ marginBottom: 24 }}>
      <div style={{ ...sectionTitle, marginBottom: 10 }}>{title}</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {vms.map(vm => (
          <div key={vm.vmid} style={{
            ...card, display: 'flex', alignItems: 'center', gap: 12,
          }}>
            <div style={{
              width: 7, height: 7, borderRadius: '50%', flexShrink: 0,
              background: vm.status === 'running' ? 'var(--green)'
                : vm.status === 'stopped' ? 'var(--text3)' : 'var(--yellow)',
            }} />

            <div className="mono" style={{ fontSize: 11, color: 'var(--text3)', width: 40 }}>
              {vm.vmid}
            </div>

            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 12, fontWeight: 500 }}>{vm.name}</div>
              {vm.status === 'running' && (
                <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 1 }}>
                  CPU {vm.cpu}% · RAM {vm.ram_mb}MB
                </div>
              )}
            </div>

            <span style={{
              fontSize: 10, padding: '2px 7px', borderRadius: 4,
              background: vm.status === 'running' ? 'var(--green)22' : 'var(--bg)',
              color: vm.status === 'running' ? 'var(--green)' : 'var(--text3)',
              border: '1px solid var(--border)',
            }}>{vm.status}</span>

            <div style={{ display: 'flex', gap: 4 }}>
              {vm.status === 'stopped' && (
                <button className="btn" style={{ padding: '3px 8px' }}
                  onClick={() => onAction(vm.vmid, 'start')} title="Start">
                  <Play size={11} />
                </button>
              )}
              {vm.status === 'running' && (
                <>
                  <button className="btn" style={{ padding: '3px 8px' }}
                    onClick={() => onAction(vm.vmid, 'restart')} title="Restart">
                    <RotateCw size={11} />
                  </button>
                  <button className="btn" style={{ padding: '3px 8px' }}
                    onClick={() => onAction(vm.vmid, 'stop')} title="Stop">
                    <Square size={11} />
                  </button>
                </>
              )}
              <button className="btn" style={{ padding: '3px 8px', color: 'var(--red)' }}
                onClick={() => onAction(vm.vmid, 'delete')} title="Delete">
                <Trash2 size={11} />
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════
// SESSIONS TAB
// ═══════════════════════════════════════════════
function SessionsTab() {
  const [sessions, setSessions] = useState([])
  useEffect(() => {
    adminApi.adminSessions().then(r => setSessions(r.data)).catch(() => {})
  }, [])

  const STATUS_COLOR = {
    waiting: 'var(--text3)', provisioning: 'var(--yellow)',
    running: 'var(--green)', ended: 'var(--text3)', error: 'var(--red)',
  }

  return (
    <div style={{ padding: 24 }}>
      <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 20 }}>
        All Sessions ({sessions.length})
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {sessions.map(s => (
          <div key={s.id} style={{ ...card, display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 7, height: 7, borderRadius: '50%', flexShrink: 0,
              background: STATUS_COLOR[s.status] || 'var(--text3)',
              boxShadow: s.status === 'running' ? '0 0 6px var(--green)' : 'none',
            }} />
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 12, fontWeight: 500 }}>{s.name}</div>
              <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 1 }}>
                {s.mode?.replace('_',' ')} · {s.vm_count} VMs
              </div>
            </div>
            <span style={{ fontSize: 11, color: STATUS_COLOR[s.status] }}>{s.status}</span>
            {s.started_at && (
              <span style={{ fontSize: 11, color: 'var(--text3)' }}>
                {new Date(s.started_at).toLocaleDateString()}
              </span>
            )}
          </div>
        ))}
        {sessions.length === 0 && (
          <div style={{ color: 'var(--text3)', fontSize: 13 }}>No sessions yet.</div>
        )}
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════
// USERS TAB
// ═══════════════════════════════════════════════
function UsersTab() {
  const [users, setUsers] = useState([])
  const [invite, setInvite] = useState(null)

  const load = () => adminApi.users().then(r => setUsers(r.data)).catch(() => {})
  useEffect(() => { load() }, [])

  const toggle = async (id) => {
    await adminApi.toggleUser(id)
    load()
  }

  const genInvite = async (type) => {
    const r = await adminApi.generateInvite(type)
    setInvite(r.data)
  }

  return (
    <div style={{ padding: 24 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
        <div style={{ fontSize: 13, fontWeight: 600 }}>Users ({users.length})</div>
        <div style={{ display: 'flex', gap: 6 }}>
          <button className="btn" style={{ color: 'var(--red)', fontSize: 11 }}
            onClick={() => genInvite('red')}>+ Red Invite</button>
          <button className="btn" style={{ color: 'var(--blue)', fontSize: 11 }}
            onClick={() => genInvite('blue')}>+ Blue Invite</button>
        </div>
      </div>

      {invite && (
        <div style={{
          ...card, marginBottom: 16, border: '1px solid var(--green)33',
          background: 'var(--green)08',
        }}>
          <div style={{ fontSize: 11, color: 'var(--text3)', marginBottom: 4 }}>
            Invite token ({invite.team_type} team) — share this with the player:
          </div>
          <div className="mono" style={{ fontSize: 13, letterSpacing: 1 }}>
            {invite.invite_token}
          </div>
          <button className="btn" style={{ marginTop: 8, fontSize: 11 }}
            onClick={() => setInvite(null)}>Dismiss</button>
        </div>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {users.map(u => (
          <div key={u.id} style={{ ...card, display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 30, height: 30, borderRadius: '50%', flexShrink: 0,
              background: 'var(--bg)', border: '1px solid var(--border)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 12, fontWeight: 600,
            }}>
              {u.username?.[0]?.toUpperCase()}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 12, fontWeight: 500 }}>{u.username}</div>
              <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 1 }}>
                {u.email} · {u.role}
                {u.team_type && (
                  <span style={{
                    marginLeft: 6,
                    color: u.team_type === 'red' ? 'var(--red)' : 'var(--blue)',
                  }}>
                    {u.team_type} team
                  </span>
                )}
              </div>
            </div>
            {u.last_login && (
              <span style={{ fontSize: 11, color: 'var(--text3)' }}>
                {new Date(u.last_login).toLocaleDateString()}
              </span>
            )}
            <button className="btn"
              style={{ fontSize: 11, color: u.is_active ? 'var(--text3)' : 'var(--green)' }}
              onClick={() => toggle(u.id)}>
              {u.is_active ? 'Disable' : 'Enable'}
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════
// HEALTH TAB
// ═══════════════════════════════════════════════
function HealthTab() {
  const [health, setHealth] = useState(null)
  const load = () => adminApi.health().then(r => setHealth(r.data)).catch(() => {})
  useEffect(() => { load(); const t = setInterval(load, 15000); return () => clearInterval(t) }, [])

  const ICONS = {
    database:   <Database size={14} />,
    redis:      <Zap size={14} />,
    guacamole:  <Terminal size={14} />,
    proxmox:    <Server size={14} />,
    coco:       <Shield size={14} />,
  }

  return (
    <div style={{ padding: 24 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 20 }}>
        <div style={{ fontSize: 13, fontWeight: 600 }}>System Health</div>
        <button className="btn" onClick={load}><RefreshCw size={12} /></button>
      </div>

      {health && (
        <>
          <div style={{
            ...card, marginBottom: 16,
            borderColor: health.all_ok ? 'var(--green)33' : 'var(--red)33',
            background: health.all_ok ? 'var(--green)08' : 'var(--red)08',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              {health.all_ok
                ? <CheckCircle size={16} style={{ color: 'var(--green)' }} />
                : <XCircle    size={16} style={{ color: 'var(--red)' }} />}
              <span style={{ fontWeight: 500, fontSize: 13 }}>
                {health.all_ok ? 'All systems operational' : 'Some services degraded'}
              </span>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {Object.entries(health.checks).map(([name, check]) => (
              <div key={name} style={{ ...card, display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{ color: check.ok ? 'var(--green)' : 'var(--red)' }}>
                  {ICONS[name] || <Activity size={14} />}
                </div>
                <span style={{ fontSize: 12, fontWeight: 500, flex: 1, textTransform: 'capitalize' }}>
                  {name}
                </span>
                {check.version && (
                  <span className="mono" style={{ fontSize: 11, color: 'var(--text3)' }}>
                    v{check.version}
                  </span>
                )}
                {check.error && (
                  <span style={{ fontSize: 11, color: 'var(--red)' }}>{check.error}</span>
                )}
                {check.ok
                  ? <CheckCircle size={14} style={{ color: 'var(--green)' }} />
                  : <XCircle    size={14} style={{ color: 'var(--red)' }} />}
              </div>
            ))}
          </div>

          <div style={{ marginTop: 12, fontSize: 11, color: 'var(--text3)' }}>
            Last checked: {new Date(health.ts).toLocaleTimeString()}
          </div>
        </>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════
// SHARED COMPONENTS
// ═══════════════════════════════════════════════
function StatCard({ label, value, icon, pct, color }) {
  return (
    <div style={card}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
        <span style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
          {label}
        </span>
        <span style={{ color }}>{icon}</span>
      </div>
      <div style={{ fontSize: 20, fontWeight: 700, marginBottom: 8 }}>{value}</div>
      {pct !== null && pct !== undefined && (
        <ProgressBar pct={pct} color={color} />
      )}
    </div>
  )
}

function ProgressBar({ pct, color }) {
  return (
    <div style={{ background: 'var(--bg)', borderRadius: 4, height: 4, overflow: 'hidden' }}>
      <div style={{
        height: '100%', borderRadius: 4,
        width: `${Math.min(100, pct)}%`,
        background: color,
        transition: 'width 0.5s',
      }} />
    </div>
  )
}

function BuildLog({ lines }) {
  const bottomRef = useRef(null)
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [lines])

  return (
    <div style={{
      marginTop: 12, background: 'var(--bg)', border: '1px solid var(--border)',
      borderRadius: 6, padding: 12, maxHeight: 300, overflowY: 'auto',
    }}>
      <div className="mono" style={{ fontSize: 11, lineHeight: 1.6 }}>
        {lines.map((line, i) => (
          <div key={i} style={{
            color: line.includes('ERROR') || line.includes('FAIL') ? 'var(--red)'
              : line.includes('OK') || line.includes('success') ? 'var(--green)'
              : line.includes('WARN') ? 'var(--yellow)'
              : 'var(--text2)',
          }}>
            {line}
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  )
}

// ── Shared styles ──────────────────────────────
const card = {
  background: 'var(--bg2)',
  border: '1px solid var(--border)',
  borderRadius: 8, padding: '12px 14px',
}
const sectionTitle = {
  fontSize: 11, color: 'var(--text3)',
  textTransform: 'uppercase', letterSpacing: 0.5,
}
