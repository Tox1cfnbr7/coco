import { useEffect, useState } from 'react'
import { Copy, RefreshCw } from 'lucide-react'
import { adminApi, authApi } from '../../lib/api'
import Layout from '../../components/layout/Layout'

export default function Admin() {
  const [users, setUsers]       = useState([])
  const [stats, setStats]       = useState(null)
  const [inviteTeam, setInviteTeam] = useState('blue')
  const [inviteUrl, setInviteUrl]   = useState('')
  const [copied, setCopied]         = useState(false)

  const load = () => {
    adminApi.users().then(r => setUsers(r.data)).catch(() => {})
    adminApi.stats().then(r => setStats(r.data)).catch(() => {})
  }
  useEffect(() => { load() }, [])

  const generate = async () => {
    const res = await authApi.generateInvite(inviteTeam)
    setInviteUrl(`${window.location.origin}/register?token=${res.data.invite_token}`)
  }

  const copy = () => {
    navigator.clipboard.writeText(inviteUrl)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const toggle = async (id) => {
    await adminApi.toggleUser(id)
    load()
  }

  const action = (
    <button className="btn" onClick={load}><RefreshCw size={13} /> Refresh</button>
  )

  return (
    <Layout title="Settings" action={action}>
      <div style={{ padding: 24 }}>

        {stats && (
          <div style={{ display: 'flex', gap: 40, paddingBottom: 20, borderBottom: '1px solid var(--border)', marginBottom: 24 }}>
            {[
              { n: stats.total_users,   l: 'Total users' },
              { n: stats.active_users,  l: 'Active users' },
              { n: stats.total_games,   l: 'Games' },
              { n: stats.flags_captured, l: 'Flags captured', c: 'var(--red)' },
            ].map(({ n, l, c }) => (
              <div key={l}>
                <div style={{ fontSize: 22, fontWeight: 600, letterSpacing: -0.5, color: c || 'var(--text)' }}>{n}</div>
                <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5, marginTop: 3 }}>{l}</div>
              </div>
            ))}
          </div>
        )}

        <div style={{ marginBottom: 28 }}>
          <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 12 }}>Generate invite link</div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 10 }}>
            <select value={inviteTeam} onChange={e => setInviteTeam(e.target.value)}
              style={{ width: 130, borderBottom: '1px solid var(--border2)', padding: '6px 0', fontSize: 12 }}>
              <option value="red">Red Team</option>
              <option value="blue">Blue Team</option>
            </select>
            <button className="btn btn-solid" onClick={generate} style={{ fontSize: 12 }}>Generate</button>
          </div>
          {inviteUrl && (
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <input value={inviteUrl} readOnly className="mono"
                style={{ fontSize: 11, borderBottom: '1px solid var(--border)', maxWidth: 420, padding: '6px 0' }} />
              <button className="btn" onClick={copy} style={{ fontSize: 11 }}>
                <Copy size={12} /> {copied ? 'Copied' : 'Copy'}
              </button>
            </div>
          )}
        </div>

        <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 12 }}>Users</div>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '1px solid var(--border)' }}>
              {['User', 'Team', 'Role', 'Last login', 'Status', ''].map(h => (
                <th key={h} style={{ padding: '8px 0', textAlign: 'left', fontSize: 10, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5, fontWeight: 500 }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {users.filter(u => u.hashed_password).map(u => (
              <tr key={u.id} style={{ borderBottom: '1px solid var(--border)' }}>
                <td style={{ padding: '10px 0' }}>
                  <div style={{ fontWeight: 500 }}>{u.username}</div>
                  <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 2 }}>{u.email}</div>
                </td>
                <td style={{ padding: '10px 0' }}>
                  {u.team_type && <span className={`tag tag-${u.team_type}`}>{u.team_type}</span>}
                </td>
                <td style={{ padding: '10px 0', color: 'var(--text2)', fontSize: 12 }}>{u.role}</td>
                <td style={{ padding: '10px 0', color: 'var(--text2)', fontSize: 12 }} className="mono">
                  {u.last_login ? new Date(u.last_login).toLocaleString() : '—'}
                </td>
                <td style={{ padding: '10px 0' }}>
                  <span style={{ fontSize: 11, color: u.is_active ? 'var(--green)' : 'var(--red)' }}>
                    {u.is_active ? 'active' : 'disabled'}
                  </span>
                </td>
                <td style={{ padding: '10px 0' }}>
                  <button className="btn" onClick={() => toggle(u.id)}
                    style={{ fontSize: 11, color: u.is_active ? 'var(--red)' : 'var(--green)', borderColor: u.is_active ? 'var(--red)' : 'var(--green)' }}>
                    {u.is_active ? 'Disable' : 'Enable'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  )
}
