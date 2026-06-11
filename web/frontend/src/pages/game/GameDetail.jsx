import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Terminal, Flag, Clock, Play, LogIn } from 'lucide-react'
import { gamesApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Layout from '../../components/layout/Layout'

export default function GameDetail() {
  const { id } = useParams()
  const { user } = useAuthStore()
  const navigate = useNavigate()
  const [game, setGame] = useState(null)
  const [flag, setFlag] = useState('')
  const [flagError, setFlagError] = useState('')
  const [captured, setCaptured] = useState(false)
  const [joinCode, setJoinCode] = useState('')
  const [joinError, setJoinError] = useState('')

  const load = () => gamesApi.get(id).then(r => setGame(r.data)).catch(() => {})

  useEffect(() => {
    load()
    const t = setInterval(load, 5000)
    return () => clearInterval(t)
  }, [id])

  const handleFlag = async (e) => {
    e.preventDefault()
    setFlagError('')
    try {
      await gamesApi.submitFlag(id, flag)
      setCaptured(true)
    } catch (err) {
      setFlagError(err.response?.data?.detail || 'Wrong flag')
    }
  }

  const handleJoin = async (e) => {
    e.preventDefault()
    setJoinError('')
    try {
      await gamesApi.join(id, joinCode)
      load()
    } catch (err) {
      setJoinError(err.response?.data?.detail || 'Invalid code')
    }
  }

  const handleStart = async () => {
    await gamesApi.start(id)
    load()
  }

  if (captured || game?.flag_captured) {
    return (
      <div style={{
        minHeight: '100vh', background: '#1a0000',
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        color: '#ff3333',
      }}>
        <div style={{ fontSize: 120, marginBottom: 24 }}>☠</div>
        <div style={{ fontSize: 48, fontWeight: 700, letterSpacing: 4, marginBottom: 16 }}>
          YOU GOT HACKED
        </div>
        <div style={{ fontSize: 18, color: '#cc0000', marginBottom: 40 }}>
          Red Team captured the flag
        </div>
        <button onClick={() => navigate('/dashboard')} style={{
          background: 'transparent', border: '1px solid #ff3333',
          color: '#ff3333', padding: '10px 28px',
          borderRadius: 8, fontSize: 14, cursor: 'pointer',
        }}>
          Back to dashboard
        </button>
      </div>
    )
  }

  if (!game) return (
    <Layout>
      <div style={{ padding: 28, color: 'var(--text2)' }}>Loading...</div>
    </Layout>
  )

  return (
    <Layout>
      <div style={{ padding: 28 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
          <div>
            <h1 style={{ fontSize: 20, fontWeight: 500 }}>{game.name}</h1>
            <div style={{ fontSize: 13, color: 'var(--text2)', marginTop: 4 }}>
              {game.mode?.replace('_', ' ')} · {game.duration}
            </div>
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            {user?.role === 'admin' && game.status === 'waiting' && (
              <button onClick={handleStart} style={{
                display: 'flex', alignItems: 'center', gap: 6,
                background: 'var(--green)', color: '#fff',
                border: 'none', padding: '8px 16px',
                borderRadius: 'var(--radius)', fontSize: 13,
              }}>
                <Play size={14} /> Start game
              </button>
            )}
            <button onClick={() => navigate(`/games/${id}/terminal`)} style={{
              display: 'flex', alignItems: 'center', gap: 6,
              background: 'var(--bg2)', color: 'var(--text)',
              border: '0.5px solid var(--border)', padding: '8px 16px',
              borderRadius: 'var(--radius)', fontSize: 13,
            }}>
              <Terminal size={14} /> Open terminal
            </button>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 20 }}>
          {game.teams?.map(t => (
            <div key={t.id} style={{
              background: 'var(--bg2)', border: `0.5px solid ${t.type === 'red' ? 'var(--red)' : 'var(--blue)'}`,
              borderRadius: 'var(--radius-lg)', padding: '16px 18px',
            }}>
              <div style={{
                display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
                color: t.type === 'red' ? 'var(--red)' : 'var(--blue)',
                fontWeight: 500,
              }}>
                <div style={{ width: 8, height: 8, borderRadius: '50%', background: t.type === 'red' ? 'var(--red)' : 'var(--blue)' }} />
                {t.type === 'red' ? 'Red Team' : 'Blue Team'}
                <span style={{ marginLeft: 'auto', fontSize: 12, color: 'var(--text2)' }}>
                  {t.member_count} players
                </span>
              </div>
              {t.join_code && (
                <div style={{ fontSize: 12, color: 'var(--text2)' }}>
                  Join code: <span style={{ color: 'var(--text)', fontFamily: 'monospace' }}>{t.join_code}</span>
                </div>
              )}
            </div>
          ))}
        </div>

        {!user?.team_id && (
          <div style={{
            background: 'var(--bg2)', border: '0.5px solid var(--border)',
            borderRadius: 'var(--radius-lg)', padding: '20px', marginBottom: 20,
          }}>
            <h3 style={{ fontSize: 14, fontWeight: 500, marginBottom: 14, display: 'flex', alignItems: 'center', gap: 8 }}>
              <LogIn size={16} /> Join a team
            </h3>
            <form onSubmit={handleJoin} style={{ display: 'flex', gap: 10 }}>
              <input value={joinCode} onChange={e => setJoinCode(e.target.value.toUpperCase())}
                placeholder="Enter join code" style={{ flex: 1 }} />
              <button type="submit" style={{
                background: 'var(--purple)', color: '#fff', border: 'none',
                padding: '8px 18px', borderRadius: 'var(--radius)', fontSize: 13, whiteSpace: 'nowrap',
              }}>Join</button>
            </form>
            {joinError && <div style={{ color: 'var(--red)', fontSize: 13, marginTop: 8 }}>{joinError}</div>}
          </div>
        )}

        {user?.team_type === 'red' && game.status === 'running' && (
          <div style={{
            background: 'rgba(226,75,74,0.05)', border: '0.5px solid var(--red)',
            borderRadius: 'var(--radius-lg)', padding: '20px',
          }}>
            <h3 style={{ fontSize: 14, fontWeight: 500, marginBottom: 14, color: 'var(--red)', display: 'flex', alignItems: 'center', gap: 8 }}>
              <Flag size={16} /> Submit flag
            </h3>
            <form onSubmit={handleFlag} style={{ display: 'flex', gap: 10 }}>
              <input value={flag} onChange={e => setFlag(e.target.value)}
                placeholder="COCO{...}" style={{ flex: 1, fontFamily: 'monospace' }} />
              <button type="submit" style={{
                background: 'var(--red)', color: '#fff', border: 'none',
                padding: '8px 18px', borderRadius: 'var(--radius)', fontSize: 13, whiteSpace: 'nowrap',
              }}>Submit</button>
            </form>
            {flagError && <div style={{ color: 'var(--red)', fontSize: 13, marginTop: 8 }}>{flagError}</div>}
          </div>
        )}
      </div>
    </Layout>
  )
}
