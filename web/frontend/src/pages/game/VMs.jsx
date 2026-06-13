import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Terminal } from 'lucide-react'
import { sessionsApi } from '../../lib/api'
import Layout from '../../components/layout/Layout'

export default function VMs() {
  const [vms, setVms] = useState([])
  const [sessionId, setSessionId] = useState(null)
  const navigate = useNavigate()

  useEffect(() => {
    sessionsApi.list().then(r => {
      const running = r.data.find(s => s.status === 'running')
        || r.data.find(s => s.status === 'provisioning')
      if (running) {
        setSessionId(running.id)
        sessionsApi.vms(running.id).then(v => setVms(v.data)).catch(() => {})
      }
    }).catch(() => {})
  }, [])

  return (
    <Layout title="Virtual machines">
      <div style={{ padding: 24 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '2fr 120px 90px 90px 110px', padding: '7px 0', borderBottom: '1px solid var(--border)', marginBottom: 2 }}>
          {['Name', 'IP', 'Team', 'Status', ''].map(h => (
            <div key={h} style={{ fontSize: 10, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{h}</div>
          ))}
        </div>

        {vms.length === 0 && (
          <div style={{ padding: '32px 0', color: 'var(--text3)' }}>
            No VMs — start a session first.
          </div>
        )}

        {vms.map(vm => (
          <div key={vm.id} style={{ display: 'grid', gridTemplateColumns: '2fr 120px 90px 90px 110px', padding: '11px 0', borderBottom: '1px solid var(--border)', alignItems: 'center' }}>
            <div>
              <div style={{ fontWeight: 500 }}>{vm.name}</div>
              <div style={{ fontSize: 11, color: 'var(--text2)', marginTop: 2 }}>{vm.type} · {vm.role}</div>
            </div>
            <div className="mono" style={{ fontSize: 12, color: 'var(--text2)' }}>{vm.ip || '—'}</div>
            <div><span className={`tag tag-${vm.team === 'red' ? 'err' : 'run'}`}>{vm.team}</span></div>
            <div><span className={`tag tag-${vm.status === 'running' ? 'run' : 'end'}`}>{vm.status}</span></div>
            <div>
              {vm.guacamole_id ? (
                <a href={`/guacamole/#/client/${btoa(vm.guacamole_id + '\0c\0default')}`}
                  target="_blank" rel="noreferrer">
                  <button className="btn" style={{ fontSize: 11 }}>
                    <Terminal size={12} /> Open
                  </button>
                </a>
              ) : (
                <button className="btn" style={{ fontSize: 11 }} onClick={() => navigate(sessionId ? `/sessions/${sessionId}` : '/sessions')}>
                  <Terminal size={12} /> Details
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </Layout>
  )
}
