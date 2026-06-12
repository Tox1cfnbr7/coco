import { useState, useEffect } from 'react'
import { useNavigate, Link, useSearchParams } from 'react-router-dom'
import { authApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Logo from '../../assets/Logo'

export default function Login() {
  const [email, setEmail]       = useState('')
  const [password, setPassword] = useState('')
  const [error, setError]       = useState('')
  const [loading, setLoading]   = useState(false)
  const [params]                = useSearchParams()
  const { setAuth, isAuthenticated } = useAuthStore()
  const navigate                = useNavigate()

  useEffect(() => {
    if (isAuthenticated()) navigate('/dashboard')
  }, [])

  const submit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const res = await authApi.login(email, password)
      const { access_token, ...user } = res.data
      setAuth(user, access_token)
      navigate('/dashboard')
    } catch (err) {
      setError(err.response?.data?.detail || 'Invalid credentials')
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
      <div style={{ width: 320 }}>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 36 }}>
          <Logo size={64} />
          <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: 5, marginTop: 14 }}>COCO</div>
          <div style={{ fontSize: 10, color: 'var(--text3)', letterSpacing: 2, marginTop: 4 }}>ATTACK & DEFENSE PLATFORM</div>
        </div>

        {params.get('registered') && (
          <div style={{ fontSize: 12, color: 'var(--green)', borderBottom: '1px solid var(--green)', paddingBottom: 8, marginBottom: 20 }}>
            Account created — sign in below.
          </div>
        )}

        <form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
          <label style={{ fontSize: 11, color: 'var(--text2)', fontWeight: 500, marginBottom: 4 }}>Email</label>
          <input type="email" value={email} onChange={e => setEmail(e.target.value)}
            placeholder="you@company.com" required autoFocus />
          <div style={{ height: 20 }} />

          <label style={{ fontSize: 11, color: 'var(--text2)', fontWeight: 500, marginBottom: 4 }}>Password</label>
          <input type="password" value={password} onChange={e => setPassword(e.target.value)}
            placeholder="••••••••••" required />
          <div style={{ height: 28 }} />

          {error && (
            <div style={{ fontSize: 12, color: 'var(--red)', marginBottom: 16 }}>{error}</div>
          )}

          <button type="submit" disabled={loading} className="btn btn-solid"
            style={{ width: '100%', justifyContent: 'center', padding: '9px 0', fontSize: 13 }}>
            {loading ? 'Signing in...' : 'Sign in'}
          </button>
        </form>

        <div style={{ marginTop: 20, fontSize: 12, color: 'var(--text3)' }}>
          Have an invite?{' '}
          <Link to="/register" style={{ color: 'var(--text)', textDecoration: 'underline' }}>
            Register here
          </Link>
        </div>
      </div>
    </div>
  )
}
