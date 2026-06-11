import { useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { authApi } from '../../lib/api'
import useAuthStore from '../../store/auth'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const { setAuth } = useAuthStore()
  const navigate = useNavigate()

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const res = await authApi.login(email, password)
      const { access_token, ...user } = res.data
      setAuth(user, access_token)
      navigate('/dashboard')
    } catch (err) {
      setError(err.response?.data?.detail || 'Login failed')
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
        width: 360, background: 'var(--bg2)',
        border: '0.5px solid var(--border)',
        borderRadius: 'var(--radius-lg)', padding: '40px 32px',
      }}>
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: 'var(--purple)', letterSpacing: 3 }}>COCO</div>
          <div style={{ fontSize: 11, color: 'var(--text3)', letterSpacing: 1, marginTop: 4 }}>ATTACK & DEFENSE PLATFORM</div>
        </div>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Email</label>
            <input
              type="email" value={email} onChange={e => setEmail(e.target.value)}
              placeholder="your@email.com" required autoFocus
            />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--text2)', marginBottom: 6 }}>Password</label>
            <input
              type="password" value={password} onChange={e => setPassword(e.target.value)}
              placeholder="••••••••••" required
            />
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
            background: 'var(--purple)', color: '#fff',
            border: 'none', padding: '10px 0',
            borderRadius: 'var(--radius)', fontWeight: 500,
            opacity: loading ? 0.7 : 1, marginTop: 8,
          }}>
            {loading ? 'Signing in...' : 'Sign in'}
          </button>
        </form>

        <div style={{ textAlign: 'center', marginTop: 20, fontSize: 13, color: 'var(--text2)' }}>
          Have an invite? <Link to="/register">Register here</Link>
        </div>
      </div>
    </div>
  )
}
