import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Terminal } from 'lucide-react'
import { gamesApi } from '../../lib/api'
import Layout from '../../components/layout/Layout'

export default function VMs() {
  const [vms, setVms] = useState([])
  const navigate = useNavigate()

  useEffect(() => {
    gamesApi.list().then(r => {
      const running = r.data.find(g => g.status === 'running')
      if (running) gamesApi.get(running.id).then(g => setVms(g.data.vms || []))
    }).catch(() => {})
  }, [])

  return (
    <Layout title="Virtual machines">
      <div style={{ padding: 24 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '2fr 120px 80px 80px 100px', padding: '7px 0', borderBottom: '1px solid var(--border)', marginBottom: 2 }}>
          {['Name', 'IP', 'Team', 'Status', ''].map(h => (
            <div key={h} style={{ fontSize: 10, color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{h}</div>
          ))}
        </div>

        {vms.length === 0 && (
          <div style={{ padding: '32px 0', color: 'var(--text3)' }}>No VMs — start a game first.</div>
        )}

        {vms.map(vm => (
          <div key={vm.id} style={{ display: 'grid', gridTemplateColumns: '2fr 120px 80px 80px 100px', padding: '11px 0', borderBottom: '1px solid var(--border)', alignItems: 'center' }}>
            <div>
              <div style={{ fontWeight: 500 }}>{vm.name}</div>
              <div style={{ fontSize: 11, color: 'var(--text2)', marginTop: 2 }}>{vm.type}</div>
            </div>
            <div className="mono" style={{ fontSize: 12, color: 'var(--text2)' }}>{vm.ip || '—'}</div>
            <div><span className={`tag tag-${vm.team === 'red' ? 'red' : 'blue'}`}>{vm.team}</span></div>
            <div><span className={`tag tag-${vm.status === 'running' ? 'run' : 'end'}`}>{vm.status}</span></div>
            <div>
              <button className="btn" style={{ fontSize: 11 }}
                onClick={() => navigate('/terminal')}>
                <Terminal size={12} /> Open
              </button>
            </div>
          </div>
        ))}
      </div>
    </Layout>
  )
}
