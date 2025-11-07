import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    setupFiles: ['./test/javascript/setup.js'],
    globals: true,
    include: ['test/javascript/**/*.test.js']
  }
})
