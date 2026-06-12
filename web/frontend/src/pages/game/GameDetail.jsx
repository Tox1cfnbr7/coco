import { useEffect, useState, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Terminal, Server, Flag } from 'lucide-react'
import { gamesApi } from '../../lib/api'
import useAuthStore from '../../store/auth'
import Layout from '../../components/layout/Layout'

function useTimer(startedAt, duration) {
  const [remaining, setRemaining] = useState(null)
  useEffect(() => {
    if (!startedAt || duration === 'unlimited') return
    const limits = { quick: 7200, standard: 28800 }
    const limit = limits[duration] || 0
    const tick = () => {
      const elapsed = (Date.now() - new Date(startedAt).getTime()) / 1000
      const left = Math.max(0, limit - elapsed)
      setRemaining(left)
    }
    tick()
    const t = setInterval(tick, 1000)
    return () => clearInterval(t)
  }, [startedAt, duration])
  if (remaining === null) return null
  const h = String(Math.floor(remaining / 3600)).padStart(2, '0')
  const m = String(Math.floor((remaining % 3600) / 60)).padStart(2, '0')
  const s = String(Math.floor(remaining % 60)).padStart(2, '0')
  return `${h}:${m}:${s}`
}

export default function GameDetail() {
  const { id } = useParams()
  const { user } = useAuthStore()
  const navigate = useNavigate()
  const [game, setGame]       = useState(null)
  const [flag, setFlag]       = useState('')
  const [flagErr, setFlagErr] = useState('')
  const [captured, setCaptured] = useState(false)
  const [joinCode, setJoinCode] = useState('')
  const [joinErr, setJoinErr]   = useState('')

  const load = () => gamesApi.get(id).then(r => setGame(r.data)).catch(() => {})
  useEffect(() => { load(); const t = setInterval(load, 5000); return () => clearInterval(t) }, [id])

  const timer = useTimer(game?.started_at, game?.duration)

  const submitFlag = async (e) => {
    e.preventDefault()
    setFlagErr('')
    try {
      await gamesApi.submitFlag(id, flag)
      setCaptured(true)
    } catch (err) {
      setFlagErr(err.response?.data?.detail || 'Wrong flag')
    }
  }

  const joinTeam = async (e) => {
    e.preventDefault()
    setJoinErr('')
    try {
      await gamesApi.join(id, joinCode)
      load()
    } catch (err) {
      setJoinErr(err.response?.data?.detail || 'Invalid code')
    }
  }

  if (captured || game?.flag_captured) {
    return (
      <div style={{
        minHeight: '100vh', background: '#0a0000',
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        color: '#cc0000',
      }}>
        <div style={{ fontSize: 96, lineHeight: 1, marginBottom: 24, filter: 'grayscale(0.3)' }}>☠</div>
        <div style={{ fontSize: 36, fontWeight: 700, letterSpacing: 6, marginBottom: 12 }}>YOU GOT HACKED</div>
        <div style={{ fontSize: 14, color: '#880000', marginBottom: 40, letterSpacing: 1 }}>
          Red Team captured the flag
        </div>
        <button onClick={() => navigate('/dashboard')} className="btn"
          style={{ color: '#cc0000', borderColor: '#cc0000', fontSize: 12 }}>
          Back to dashboard
        </button>
      </div>
    )
  }

  if (!game) return <Layout title="Loading..."><div style={{ padding: 24, color: 'var(--text3)' }}>Loading...</div></Layout>

  const redTeam  = game.teams?.find(t => t.type === 'red')
  const blueTeam = game.teams?.find(t => t.type === 'blue')

  const action = (
    <div style={{ display: 'flex', gap: 8 }}>
      {user?.role === 'admin' && game.status === 'waiting' && (
        <button className="btn" style={{ color: 'var(--green)', borderColor: 'var(--green)' }}
          onClick={() => gamesApi.start(id).then(load)}>
          Start game
        </button>
      )}
      <button className="btn" onClick={() => navigate('/terminal')}>
        <Terminal size={13} /> Terminal
      </button>
      <button className="btn" onClick={() => navigate('/vms')}>
        <Server size={13} /> VMs
      </button>
      {game.duration === 'unlimited' && game.status === 'running' && (
        <button className="btn" style={{ color: 'var(--amber)', borderColor: 'var(--amber)' }}
          onClick={() => gamesApi.surrender(id).then(load)}>
          Surrender
        </button>
      )}
    </div>
  )

  return (
    <Layout title={game.name} action={action}>
      <div style={{ padding: 24 }}>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1, background: 'var(--border)', border: '1px solid var(--border)', marginBottom: 24 }}>
          {[
            { l: 'Mode',     v: game.mode?.replace('_', ' ') },
            { l: 'Duration', v: game.duration },
            { l: 'Status',   v: <span className={`tag tag-${game.status === 'running' ? 'run' : game.status === 'waiting' ? 'wait' : 'end'}`}>{game.status}</span> },
            { l: 'Network',  v: <span className="mono">{game.network_cidr || '—'}</span> },
            { l: 'Timer',    v: timer ? <span className="mono">{timer}</span> : '—' },
            { l: 'Started',  v: game.started_at ? new Date(game.started_at).toLocaleString() : '—' },
          ].map(({ l, v }) => (
            <div key={l} style={{ background: 'var(--bg)', padding: '12px 16px' }}>
              <div style={{ fontSize: 10, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>{l}</div>
              <div style={{ fontSize: 13, fontWeight: 500 }}>{v}</div>
            </div>
          ))}
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24, marginBottom: 24 }}>
          {[redTeam, blueTeam].filter(Boolean).map(t => (
            <div key={t.id}>
              <div style={{
                fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8,
                color: t.type === 'red' ? 'var(--red)' : 'var(--blue)',
                borderBottom: `2px solid ${t.type === 'red' ? 'var(--red)' : 'var(--blue)'}`,
                paddingBottom: 8, marginBottom: 10,
                display: 'flex', justifyContent: 'space-between',
              }}>
                <span>{t.type === 'red' ? 'Red Team' : 'Blue Team'}</span>
                <span style={{ fontWeight: 400, opacity: 0.7 }}>{t.member_count} players</span>
              </div>
              {user?.role === 'admin' && t.join_code && (
                <div style={{ fontSize: 11, color: 'var(--text2)', marginBottom: 8 }}>
                  Join code: <span className="mono" style={{ color: 'var(--text)' }}>{t.join_code}</span>
                </div>
              )}
              {t.members?.map(m => (
                <div key={m.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '7px 0', borderBottom: '1px solid var(--border)', fontSize: 12 }}>
                  <span style={{ fontWeight: 500 }}>{m.username}</span>
                  <span style={{ color: 'var(--text3)' }}>{m.team_type}</span>
                </div>
              ))}
            </div>
          ))}
        </div>

        {!user?.team_id && (
          <div style={{ borderTop: '1px solid var(--border)', paddingTop: 20, marginBottom: 20 }}>
            <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 10 }}>Join a team</div>
            <form onSubmit={joinTeam} style={{ display: 'flex', gap: 8 }}>
              <input value={joinCode} onChange={e => setJoinCode(e.target.value.toUpperCase())}
                placeholder="Enter join code" style={{ maxWidth: 200, borderBottom: '1px solid var(--border2)', padding: '7px 0' }} />
              <button type="submit" className="btn btn-solid" style={{ fontSize: 12 }}>Join</button>
            </form>
            {joinErr && <div style={{ fontSize: 12, color: 'var(--red)', marginTop: 8 }}>{joinErr}</div>}
          </div>
        )}

        {user?.team_type === 'red' && game.status === 'running' && (
          <div style={{ borderTop: '1px solid var(--red)', paddingTop: 16 }}>
            <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, color: 'var(--red)', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
              <Flag size={13} /> Submit flag
            </div>
            <form onSubmit={submitFlag} style={{ display: 'flex', gap: 8 }}>
              <input value={flag} onChange={e => setFlag(e.target.value)}
                placeholder="COCO{...}"
                className="mono"
                style={{ maxWidth: 300, borderBottom: '1px solid var(--border2)', padding: '7px 0', fontSize: 12 }} />
              <button type="submit" className="btn btn-danger" style={{ fontSize: 12 }}>Submit</button>
            </form>
            {flagErr && <div style={{ fontSize: 12, color: 'var(--red)', marginTop: 8 }}>{flagErr}</div>}
          </div>
        )}
      </div>
    </Layout>
  )
}
