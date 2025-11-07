import 'fake-indexeddb/auto'

// Mock Rails helpers
global.window = global.window || {}
global.window.inject_region = (headers) => headers

// Mock CSRF token
const originalQuerySelector = global.document.querySelector.bind(global.document)
global.document.querySelector = (selector) => {
  if (selector === 'meta[name="csrf-token"]') {
    return { content: 'test-csrf-token' }
  }
  return originalQuerySelector(selector)
}
