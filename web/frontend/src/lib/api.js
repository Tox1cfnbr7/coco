import axios from 'axios'

const api = axios.create({
  baseURL: '/api',
  headers: { 'Content-Type': 'application/json' },
})

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('coco_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('coco_token')
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

// ── Auth ───────────────────────────────────────
export const authApi = {
  login:          (email, password) => api.post('/auth/login', { email, password }),
  register:       (data)            => api.post('/auth/register', data),
  me:             ()                => api.get('/auth/me'),
  generateInvite: (team_type)       => api.post(`/auth/invite/generate?team_type=${team_type}`),
}

// ── Games (legacy) ─────────────────────────────
export const gamesApi = {
  list:       ()           => api.get('/games/'),
  get:        (id)         => api.get(`/games/${id}`),
  create:     (data)       => api.post('/games/', data),
  start:      (id)         => api.post(`/games/${id}/start`),
  join:       (id, code)   => api.post(`/games/${id}/join?join_code=${code}`),
  submitFlag: (id, flag)   => api.post(`/games/${id}/flag`, { flag }),
  surrender:  (id)         => api.post(`/games/${id}/surrender`),
}

// ── Sessions ───────────────────────────────────
export const sessionsApi = {
  list:       ()              => api.get('/sessions/'),
  get:        (id)            => api.get(`/sessions/${id}`),
  create:     (data)          => api.post('/sessions/', data),
  start:      (id)            => api.post(`/sessions/${id}/start`),
  kill:       (id)            => api.post(`/sessions/${id}/kill`),
  join:       (id, code)      => api.post(`/sessions/${id}/join?join_code=${code}`),
  submitFlag: (id, flag)      => api.post(`/sessions/${id}/flag`, { flag }),
  milestone:  (id, milestone) => api.post(`/sessions/${id}/milestone`, { milestone }),
  scoreboard: (id)            => api.get(`/sessions/${id}/scoreboard`),
  vms:        (id)            => api.get(`/sessions/${id}/vms`),
  events:     (id)            => api.get(`/sessions/${id}/events`),
}

// ── Admin ──────────────────────────────────────
export const adminApi = {
  // Users
  users:          ()     => api.get('/admin/users'),
  toggleUser:     (id)   => api.patch(`/admin/users/${id}/toggle`),
  generateInvite: (type) => api.post(`/auth/invite/generate?team_type=${type}`),
  stats:          ()     => api.get('/admin/stats'),
  audit:          ()     => api.get('/admin/audit'),

  // Proxmox
  proxmoxStatus:  ()     => api.get('/admin/proxmox/status'),
  proxmoxStorage: ()     => api.get('/admin/proxmox/storage'),
  proxmoxVms:     ()     => api.get('/admin/proxmox/vms'),
  vmAction:       (vmid, action) => {
    if (action === 'start')   return api.post(`/admin/proxmox/vms/${vmid}/start`)
    if (action === 'stop')    return api.post(`/admin/proxmox/vms/${vmid}/stop`)
    if (action === 'restart') return api.post(`/admin/proxmox/vms/${vmid}/restart`)
    if (action === 'delete')  return api.delete(`/admin/proxmox/vms/${vmid}`)
  },

  // Templates
  templates:      ()     => api.get('/admin/templates'),
  buildTemplate:  (key)  => api.post(`/admin/templates/${key}/build`),
  deleteTemplate: (vmid) => api.delete(`/admin/templates/${vmid}`),
  templateLogs:   (key)  => api.get(`/admin/templates/${key}/logs`),

  // Sessions
  adminSessions:  ()     => api.get('/admin/sessions'),

  // Health
  health:         ()     => api.get('/admin/health'),
}

export default api
