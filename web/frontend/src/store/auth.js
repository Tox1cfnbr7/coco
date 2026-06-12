import { create } from 'zustand'

const useAuthStore = create((set, get) => ({
  user: null,
  token: localStorage.getItem('coco_token') || null,

  setAuth: (user, token) => {
    localStorage.setItem('coco_token', token)
    set({ user, token })
  },

  logout: () => {
    localStorage.removeItem('coco_token')
    set({ user: null, token: null })
  },

  isAuthenticated: () => !!get().token,
}))

export default useAuthStore
