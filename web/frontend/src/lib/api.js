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

export const authApi = {
  login:          (email, password) => api.post('/auth/login', { email, password }),
  register:       (data)            => api.post('/auth/register', data),
  me:             ()                => api.get('/auth/me'),
  generateInvite: (team_type)       => api.post(`/auth/invite/generate?team_type=${team_type}`),
}

export const gamesApi = {
  list:        ()           => api.get('/games/'),
  get:         (id)         => api.get(`/games/${id}`),
  create:      (data)       => api.post('/games/', data),
  start:       (id)         => api.post(`/games/${id}/start`),
  join:        (id, code)   => api.post(`/games/${id}/join?join_code=${code}`),
  submitFlag:  (id, flag)   => api.post(`/games/${id}/flag`, { flag }),
  surrender:   (id)         => api.post(`/games/${id}/surrender`),
}

export const sessionsApi = {
  list:        ()              => api.get('/sessions/'),
  get:         (id)            => api.get(`/sessions/${id}`),
  create:      (data)          => api.post('/sessions/', data),
  start:       (id)            => api.post(`/sessions/${id}/start`),
  kill:        (id)            => api.post(`/sessions/${id}/kill`),
  join:        (id, code)      => api.post(`/sessions/${id}/join?join_code=${code}`),
  submitFlag:  (id, flag)      => api.post(`/sessions/${id}/flag`, { flag }),
  milestone:   (id, milestone) => api.post(`/sessions/${id}/milestone`, { milestone }),
  scoreboard:  (id)            => api.get(`/sessions/${id}/scoreboard`),
  vms:         (id)            => api.get(`/sessions/${id}/vms`),
  events:      (id)            => api.get(`/sessions/${id}/events`),
}

export const adminApi = {
  users:      ()     => api.get('/admin/users'),
  stats:      ()     => api.get('/admin/stats'),
  toggleUser: (id)   => api.patch(`/admin/users/${id}/toggle`),
  audit:      ()     => api.get('/admin/audit'),
}

export default api
