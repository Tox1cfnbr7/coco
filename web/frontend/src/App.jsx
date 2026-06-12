import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import useAuthStore from './store/auth'
import Login        from './pages/auth/Login'
import Register     from './pages/auth/Register'
import Dashboard    from './pages/Dashboard'
import Games        from './pages/game/Games'
import GameDetail   from './pages/game/GameDetail'
import Terminal     from './pages/game/Terminal'
import VMs          from './pages/game/VMs'
import Admin        from './pages/admin/Admin'
import Sessions     from './pages/sessions/Sessions'
import SessionDetail from './pages/sessions/SessionDetail'

function Guard({ children, adminOnly = false }) {
  const { token, user } = useAuthStore()
  if (!token) return <Navigate to="/login" replace />
  if (adminOnly && user?.role !== 'admin') return <Navigate to="/dashboard" replace />
  return children
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login"    element={<Login />} />
        <Route path="/register" element={<Register />} />

        <Route path="/dashboard"   element={<Guard><Dashboard /></Guard>} />
        <Route path="/games"       element={<Guard><Games /></Guard>} />
        <Route path="/games/:id"   element={<Guard><GameDetail /></Guard>} />
        <Route path="/terminal"    element={<Guard><Terminal /></Guard>} />
        <Route path="/vms"         element={<Guard><VMs /></Guard>} />

        <Route path="/sessions"     element={<Guard><Sessions /></Guard>} />
        <Route path="/sessions/:id" element={<Guard><SessionDetail /></Guard>} />

        <Route path="/admin" element={<Guard adminOnly><Admin /></Guard>} />

        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
