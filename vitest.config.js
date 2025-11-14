import { defineConfig } from 'vitest/config'
import path from 'path'

export default defineConfig({
  resolve: {
    alias: {
      'components': path.resolve(__dirname, './app/javascript/components'),
      'helpers': path.resolve(__dirname, './app/javascript/helpers')
    }
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./test/javascript/setup.js'],
    globals: true,
    include: ['test/javascript/**/*.test.js']
  }
})
