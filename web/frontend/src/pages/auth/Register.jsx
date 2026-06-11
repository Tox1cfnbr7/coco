import { useState } from 'react'
import { useNavigate, useSearchParams, Link } from 'react-router-dom'
import { authApi } from '../../lib/api'

export default function Register() {
  const [params] = useSearchParams()
  const [form, setForm] = useState({
    username: '', email: '', password: '', confirm: '',
    team_type: 'blue', invite_token: params.get('token') || '',
  })
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()

  const set = (k) => (e) => setForm(f => ({ ...f, [k]: e.target.value }))

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    if (form.password !== form.confirm) { setError('Passwords do not match'); return }
    if (form.password.length < 10) { setError('Password must be at least 10 characters'); return }
    setLoading(true)
    try {
      await authApi.register({
        username: form.username,
        email: form.email,
        password: form.password,
        team_type: form.team_type,
        invite_token: form.invite_token,
      })
      navigate('/login?registered=1')
    } catch (err) {
      setError(err.response?.data?.detail || 'Registration failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{
      minHeight: '100vh', display: 'flex',
      alignItems: 'center', justifyContent: 'center',
      background: 'var(--bg)',
    }}>
      <div style={{
        width: 400, background: 'var(--bg2)',
        border: '0.5px solid var(--border)',
        borderRadius: 'var(--radius-lg)', padding: '40px 32px',
      }}>
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{ fontSize: 24, fontWeight: 700, color: 'var(--purple)', letterSpacing: 3 }}>COCO</div>
          <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 4 }}>Create your account</div>
        </div>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Username</label>
            <input value={form.username} onChange={set('username')} placeholder="hackerman" required />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Email</label>
            <input type="email" value={form.email} onChange={set('email')} placeholder="you@company.com" required />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Password</label>
            <input type="password" value={form.password} onChange={set('password')} placeholder="min. 10 characters" required />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Confirm password</label>
            <input type="password" value={form.confirm} onChange={set('confirm')} placeholder="repeat password" required />
          </div>

          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Team</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {['red', 'blue'].map(t => (
                <button key={t} type="button" onClick={() => setForm(f => ({ ...f, team_type: t }))}
                  style={{
                    padding: '10px 0', border: `0.5px solid ${form.team_type === t
                      ? (t === 'red' ? 'var(--red)' : 'var(--blue)')
                      : 'var(--border)'}`,
                    background: form.team_type === t
                      ? (t === 'red' ? 'rgba(226,75,74,0.1)' : 'rgba(55,138,221,0.1)')
                      : 'transparent',
                    color: form.team_type === t
                      ? (t === 'red' ? 'var(--red)' : 'var(--blue)')
                      : 'var(--text2)',
                    borderRadius: 'var(--radius)', fontWeight: 500,
                  }}>
                  {t === 'red' ? 'Red Team' : 'Blue Team'}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Invite token</label>
            <input value={form.invite_token} onChange={set('invite_token')} placeholder="paste your invite token" required />
          </div>

          {error && (
            <div style={{
              background: 'rgba(226,75,74,0.1)', border: '0.5px solid var(--red)',
              borderRadius: 'var(--radius)', padding: '8px 12px',
              color: 'var(--red)', fontSize: 13,
            }}>
              {error}
            </div>
          )}

          <button type="submit" disabled={loading} style={{
            background: 'var(--purple)', color: '#fff', border: 'none',
            padding: '10px 0', borderRadius: 'var(--radius)',
            fontWeight: 500, opacity: loading ? 0.7 : 1, marginTop: 4,
          }}>
            {loading ? 'Creating account...' : 'Create account'}
          </button>
        </form>

        <div style={{ textAlign: 'center', marginTop: 20, fontSize: 13, color: 'var(--text2)' }}>
          Already have an account? <Link to="/login">Sign in</Link>
        </div>
      </div>
    </div>
  )
}
