import { defineConfig } from 'vite'

export default defineConfig({
  clearScreen: false,
  server: { port: 1420, strictPort: true, watch: { ignored: ['**/ios/**', '**/src-tauri/**'] } },
  build: { rollupOptions: { input: ['index.html', 'pair.html'] } },
})
