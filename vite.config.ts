import path from 'node:path'
import { fileURLToPath } from 'node:url'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

const projectRoot = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  root: path.join(projectRoot, 'v2'),
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: [
      { find: '@', replacement: path.join(projectRoot, 'src') },
      { find: /^\/src(?=\/)/, replacement: path.join(projectRoot, 'src') },
    ],
  },
  build: {
    outDir: path.join(projectRoot, 'dist-v2'),
    emptyOutDir: true,
  },
})
