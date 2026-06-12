import { useState } from 'react'
import { useNavigate, Link, useSearchParams } from 'react-router-dom'
import { authApi } from '../../lib/api'
import Logo from '../../assets/Logo'

export default function Register() {
  const [params] = useSearchParams()
  const [form, setForm] = useState({
    username: '', email: '', password: '', confirm: '',
    team_type: 'blue',
    invite_token: params.get('token') || '',
  })
  const [error, setError]   = useState('')
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()

  const set = (k) => (e) => setForm(f => ({ ...f, [k]: e.target.value }))

  const submit = async (e) => {
    e.preventDefault()
    setError('')
    if (form.password !== form.confirm) { setError('Passwords do not match'); return }
    if (form.password.length < 10)      { setError('Password must be at least 10 characters'); return }
    setLoading(true)
    try {
      await authApi.register({
        username: form.username, email: form.email,
        password: form.password, team_type: form.team_type,
        invite_token: form.invite_token,
      })
      navigate('/login?registered=1')
    } catch (err) {
      setError(err.response?.data?.detail || 'Registration failed')
    } finally {
      setLoading(false)
    }
  }

  const field = (label, key, type = 'text', placeholder = '') => (
    <div style={{ marginBottom: 20 }}>
      <label style={{ display: 'block', fontSize: 11, color: 'var(--text2)', fontWeight: 500, marginBottom: 4 }}>
        {label}
      </label>
      <input type={type} value={form[key]} onChange={set(key)} placeholder={placeholder} required />
    </div>
  )

  return (
    <div style={{
      minHeight: '100vh', display: 'flex',
      alignItems: 'center', justifyContent: 'center',
      background: 'var(--bg)',
    }}>
      <div style={{ width: 340 }}>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 36 }}>
          <Logo size={52} />
          <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: 5, marginTop: 12 }}>COCO</div>
          <div style={{ fontSize: 10, color: 'var(--text3)', letterSpacing: 2, marginTop: 4 }}>CREATE ACCOUNT</div>
        </div>

        <form onSubmit={submit}>
          {field('Username', 'username', 'text', 'hackerman')}
          {field('Email', 'email', 'email', 'you@company.com')}
          {field('Password', 'password', 'password', 'min. 10 characters')}
          {field('Confirm password', 'confirm', 'password', 'repeat password')}

          <div style={{ marginBottom: 20 }}>
            <label style={{ fontSize: 11, color: 'var(--text2)', fontWeight: 500, display: 'block', marginBottom: 8 }}>
              Team
            </label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {['red', 'blue'].map(t => (
                <button key={t} type="button"
                  onClick={() => setForm(f => ({ ...f, team_type: t }))}
                  className="btn"
                  style={{
                    justifyContent: 'center', padding: '9px 0', fontSize: 12, fontWeight: 500,
                    color: form.team_type === t ? (t === 'red' ? 'var(--red)' : 'var(--blue)') : 'var(--text2)',
                    borderColor: form.team_type === t ? (t === 'red' ? 'var(--red)' : 'var(--blue)') : 'var(--border2)',
                  }}>
                  {t === 'red' ? 'Red Team' : 'Blue Team'}
                </button>
              ))}
            </div>
          </div>

          {field('Invite token', 'invite_token', 'text', 'paste your invite token')}

          {error && (
            <div style={{ fontSize: 12, color: 'var(--red)', marginBottom: 16 }}>{error}</div>
          )}

          <button type="submit" disabled={loading} className="btn btn-solid"
            style={{ width: '100%', justifyContent: 'center', padding: '9px 0', fontSize: 13 }}>
            {loading ? 'Creating account...' : 'Create account'}
          </button>
        </form>

        <div style={{ marginTop: 20, fontSize: 12, color: 'var(--text3)' }}>
          Already have an account?{' '}
          <Link to="/login" style={{ color: 'var(--text)', textDecoration: 'underline' }}>Sign in</Link>
        </div>
      </div>
    </div>
  )
}
