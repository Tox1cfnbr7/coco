import { useState } from 'react'
import { Maximize2, Minimize2, Upload, Download, RefreshCw, Copy } from 'lucide-react'
import Layout from '../../components/layout/Layout'

export default function Terminal() {
  const [fullscreen, setFullscreen] = useState(false)
  const [activeTab, setActiveTab]   = useState(0)

  const tabs = [
    { label: 'kali-red · 10.10.10.30',   url: '/guacamole/#/client/kali-red' },
    { label: 'win-dc · 10.10.10.10',     url: '/guacamole/#/client/win-dc' },
    { label: 'win-client · 10.10.10.20', url: '/guacamole/#/client/win-client' },
  ]

  if (fullscreen) {
    return (
      <div style={{ position: 'fixed', inset: 0, zIndex: 9999, background: '#000', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: '#111', padding: '6px 12px', borderBottom: '1px solid #222' }}>
          {tabs.map((t, i) => (
            <button key={i} onClick={() => setActiveTab(i)}
              style={{
                background: 'none', border: 'none', cursor: 'pointer',
                fontSize: 11, fontFamily: 'monospace',
                color: activeTab === i ? '#fff' : '#666',
                borderBottom: activeTab === i ? '2px solid #fff' : '2px solid transparent',
                padding: '4px 10px',
              }}>
              {t.label}
            </button>
          ))}
          <button onClick={() => setFullscreen(false)}
            style={{ marginLeft: 'auto', background: 'none', border: 'none', color: '#666', cursor: 'pointer' }}>
            <Minimize2 size={14} />
          </button>
        </div>
        <iframe src={tabs[activeTab].url} style={{ flex: 1, border: 'none' }} title="Terminal" />
      </div>
    )
  }

  const action = (
    <button className="btn btn-solid" onClick={() => setFullscreen(true)}>
      <Maximize2 size={13} /> Fullscreen
    </button>
  )

  return (
    <Layout title="Terminal" action={action}>
      <div style={{ padding: 24 }}>
        <div style={{ border: '1px solid var(--border)', overflow: 'hidden' }}>
          <div style={{ background: 'var(--bg3)', borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', gap: 0 }}>
            {tabs.map((t, i) => (
              <button key={i} onClick={() => setActiveTab(i)}
                style={{
                  background: 'none', border: 'none', cursor: 'pointer',
                  fontSize: 11, fontFamily: 'monospace', padding: '8px 14px',
                  color: activeTab === i ? 'var(--text)' : 'var(--text3)',
                  borderBottom: `2px solid ${activeTab === i ? 'var(--text)' : 'transparent'}`,
                  transition: 'color 0.1s',
                }}>
                {t.label}
              </button>
            ))}
          </div>

          <iframe
            src={tabs[activeTab].url}
            style={{ width: '100%', height: 440, border: 'none', display: 'block', background: '#000' }}
            title="Terminal"
          />

          <div style={{ borderTop: '1px solid var(--border)', padding: '8px 14px', display: 'flex', gap: 8 }}>
            <button className="btn" style={{ fontSize: 11 }}><Upload size={12} /> Upload file</button>
            <button className="btn" style={{ fontSize: 11 }}><Download size={12} /> Download file</button>
            <button className="btn" style={{ fontSize: 11 }}><Copy size={12} /> Copy</button>
            <button className="btn" style={{ marginLeft: 'auto', fontSize: 11 }}><RefreshCw size={12} /> Reconnect</button>
          </div>
        </div>

        <div style={{ marginTop: 16, fontSize: 11, color: 'var(--text3)' }}>
          All connections are proxied through Guacamole — no VPN or local VM required.
        </div>
      </div>
    </Layout>
  )
}
