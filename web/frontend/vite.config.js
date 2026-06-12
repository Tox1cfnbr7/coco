import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      // Pages live in src/pages/X/ and import ../../lib/api etc.
      // These aliases map those paths to the correct src/ locations.
      '../../lib/api':                      path.resolve(__dirname, 'src/lib/api.js'),
      '../../store/auth':                   path.resolve(__dirname, 'src/store/auth.js'),
      '../../components/layout/Layout':     path.resolve(__dirname, 'src/components/layout/Layout.jsx'),
      '../../assets/Logo':                  path.resolve(__dirname, 'src/assets/Logo.jsx'),
      '../lib/api':                         path.resolve(__dirname, 'src/lib/api.js'),
      '../store/auth':                      path.resolve(__dirname, 'src/store/auth.js'),
    },
  },
  server: {
    proxy: {
      '/api': { target: 'https://localhost:443', changeOrigin: true, secure: false },
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
