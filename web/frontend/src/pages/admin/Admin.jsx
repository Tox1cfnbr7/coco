import { useEffect, useState } from 'react'
import { Copy, UserX, UserCheck, RefreshCw } from 'lucide-react'
import { adminApi, authApi } from '../../lib/api'
import Layout from '../../components/layout/Layout'

export default function Admin() {
  const [users, setUsers] = useState([])
  const [stats, setStats] = useState(null)
  const [invite, setInvite] = useState(null)
  const [inviteTeam, setInviteTeam] = useState('blue')
  const [copied, setCopied] = useState(false)

  const load = () => {
    adminApi.users().then(r => setUsers(r.data)).catch(() => {})
    adminApi.stats().then(r => setStats(r.data)).catch(() => {})
  }

  useEffect(() => { load() }, [])

  const toggleUser = async (id) => {
    await adminApi.toggleUser(id)
    load()
  }

  const generateInvite = async () => {
    const res = await authApi.generateInvite(inviteTeam)
    const url = `${window.location.origin}/register?token=${res.data.invite_token}`
    setInvite(url)
  }

  const copy = () => {
    navigator.clipboard.writeText(invite)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <Layout>
      <div style={{ padding: 28 }}>
        <h1 style={{ fontSize: 20, fontWeight: 500, marginBottom: 24 }}>Admin panel</h1>

        {stats && (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 28 }}>
            {[
              { label: 'Users', value: stats.total_users },
              { label: 'Active', value: stats.active_users },
              { label: 'Games', value: stats.total_games },
              { label: 'Flags captured', value: stats.flags_captured },
            ].map(({ label, value }) => (
              <div key={label} style={{
                background: 'var(--bg2)', border: '0.5px solid var(--border)',
                borderRadius: 'var(--radius)', padding: '14px 16px',
              }}>
                <div style={{ fontSize: 11, color: 'var(--text3)', textTransform: 'uppercase', marginBottom: 6 }}>{label}</div>
                <div style={{ fontSize: 24, fontWeight: 500, color: 'var(--purple)' }}>{value}</div>
              </div>
            ))}
          </div>
        )}

        <div style={{
          background: 'var(--bg2)', border: '0.5px solid var(--border)',
          borderRadius: 'var(--radius-lg)', padding: '20px', marginBottom: 24,
        }}>
          <h2 style={{ fontSize: 14, fontWeight: 500, marginBottom: 14 }}>Generate invite link</h2>
          <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
            <select value={inviteTeam} onChange={e => setInviteTeam(e.target.value)} style={{ width: 140 }}>
              <option value="red">Red Team</option>
              <option value="blue">Blue Team</option>
            </select>
            <button onClick={generateInvite} style={{
              background: 'var(--purple)', color: '#fff', border: 'none',
              padding: '8px 16px', borderRadius: 'var(--radius)', fontSize: 13,
            }}>
              Generate
            </button>
          </div>
          {invite && (
            <div style={{ marginTop: 12, display: 'flex', gap: 10, alignItems: 'center' }}>
              <input value={invite} readOnly style={{ flex: 1, fontFamily: 'monospace', fontSize: 12 }} />
              <button onClick={copy} style={{
                display: 'flex', alignItems: 'center', gap: 6,
                background: copied ? 'var(--green)' : 'var(--bg3)',
                color: 'var(--text)', border: '0.5px solid var(--border)',
                padding: '8px 12px', borderRadius: 'var(--radius)', fontSize: 13,
              }}>
                <Copy size={14} /> {copied ? 'Copied!' : 'Copy'}
              </button>
            </div>
          )}
        </div>

        <div style={{
          background: 'var(--bg2)', border: '0.5px solid var(--border)',
          borderRadius: 'var(--radius-lg)', overflow: 'hidden',
        }}>
          <div style={{ padding: '14px 18px', borderBottom: '0.5px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h2 style={{ fontSize: 14, fontWeight: 500 }}>Users</h2>
            <button onClick={load} style={{ background: 'none', border: 'none', color: 'var(--text2)', cursor: 'pointer' }}>
              <RefreshCw size={14} />
            </button>
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
            <thead>
              <tr style={{ borderBottom: '0.5px solid var(--border)' }}>
                {['Username', 'Email', 'Team', 'Role', 'Last login', 'Status', ''].map(h => (
                  <th key={h} style={{ padding: '10px 18px', textAlign: 'left', color: 'var(--text2)', fontWeight: 500, fontSize: 12 }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {users.map(u => (
                <tr key={u.id} style={{ borderBottom: '0.5px solid var(--border)' }}>
                  <td style={{ padding: '10px 18px', fontWeight: 500 }}>{u.username}</td>
                  <td style={{ padding: '10px 18px', color: 'var(--text2)' }}>{u.email}</td>
                  <td style={{ padding: '10px 18px' }}>
                    {u.team_type && (
                      <span style={{
                        fontSize: 11, padding: '2px 8px', borderRadius: 20,
                        background: u.team_type === 'red' ? 'rgba(226,75,74,0.15)' : 'rgba(55,138,221,0.15)',
                        color: u.team_type === 'red' ? 'var(--red)' : 'var(--blue)',
                        border: `0.5px solid ${u.team_type === 'red' ? 'var(--red)' : 'var(--blue)'}`,
                      }}>
                        {u.team_type}
                      </span>
                    )}
                  </td>
                  <td style={{ padding: '10px 18px', color: 'var(--text2)' }}>{u.role}</td>
                  <td style={{ padding: '10px 18px', color: 'var(--text2)', fontSize: 12 }}>
                    {u.last_login ? new Date(u.last_login).toLocaleString() : '—'}
                  </td>
                  <td style={{ padding: '10px 18px' }}>
                    <span style={{
                      fontSize: 11, padding: '2px 8px', borderRadius: 20,
                      background: u.is_active ? 'rgba(99,153,34,0.15)' : 'rgba(226,75,74,0.15)',
                      color: u.is_active ? 'var(--green)' : 'var(--red)',
                    }}>
                      {u.is_active ? 'active' : 'disabled'}
                    </span>
                  </td>
                  <td style={{ padding: '10px 18px' }}>
                    <button onClick={() => toggleUser(u.id)} style={{
                      background: 'none', border: 'none',
                      color: u.is_active ? 'var(--red)' : 'var(--green)',
                      cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4,
                    }}>
                      {u.is_active ? <UserX size={14} /> : <UserCheck size={14} />}
                      {u.is_active ? 'Disable' : 'Enable'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
