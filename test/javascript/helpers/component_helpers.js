/**
 * Component Testing Helpers
 *
 * Utilities for rendering and testing web components in isolation.
 */

import { JSDOM } from 'jsdom'

/**
 * Setup DOM environment for testing
 */
export const setupDOM = () => {
  const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
    url: 'http://localhost:3000',
    pretendToBeVisual: true,
    resources: 'usable'
  })

  global.window = dom.window
  global.document = dom.window.document
  global.HTMLElement = dom.window.HTMLElement
  global.customElements = dom.window.customElements
  global.Event = dom.window.Event
  global.CustomEvent = dom.window.CustomEvent

  return dom
}

/**
 * Cleanup DOM environment
 */
export const cleanupDOM = () => {
  if (global.window) {
    global.window.close()
  }
  delete global.window
  delete global.document
  delete global.HTMLElement
  delete global.customElements
  delete global.Event
  delete global.CustomEvent
}

/**
 * Create a container element for testing
 */
export const createContainer = () => {
  const container = document.createElement('div')
  container.id = 'test-container'
  document.body.appendChild(container)
  return container
}

/**
 * Clean up container
 */
export const cleanupContainer = (container) => {
  if (container && container.parentNode) {
    container.parentNode.removeChild(container)
  }
}

/**
 * Render a component with data
 *
 * @param {string} tagName - Component tag name (e.g., 'heat-solo')
 * @param {object} attributes - Attributes to set on the component
 * @param {object} data - Data to inject into the component
 * @returns {HTMLElement} The rendered component
 */
export const renderComponent = (tagName, attributes = {}, data = null) => {
  const container = createContainer()
  const component = document.createElement(tagName)

  // Set attributes
  Object.entries(attributes).forEach(([key, value]) => {
    component.setAttribute(key, value)
  })

  // Inject data if provided
  if (data) {
    component.data = data
  }

  container.appendChild(component)

  // Wait for component to be connected
  if (component.connectedCallback) {
    component.connectedCallback()
  }

  return component
}

/**
 * Wait for async rendering to complete
 */
export const waitForRender = async (component, timeout = 1000) => {
  return new Promise((resolve, reject) => {
    const start = Date.now()
    const checkRender = () => {
      if (component.innerHTML.trim() !== '') {
        resolve(component)
      } else if (Date.now() - start > timeout) {
        reject(new Error('Render timeout'))
      } else {
        setTimeout(checkRender, 10)
      }
    }
    checkRender()
  })
}

/**
 * Simulate user interaction - click
 */
export const click = (element) => {
  const event = new Event('click', { bubbles: true, cancelable: true })
  element.dispatchEvent(event)
}

/**
 * Simulate user interaction - input
 */
export const input = (element, value) => {
  element.value = value
  const event = new Event('input', { bubbles: true, cancelable: true })
  element.dispatchEvent(event)
}

/**
 * Simulate user interaction - change
 */
export const change = (element, value) => {
  if (value !== undefined) {
    element.value = value
  }
  const event = new Event('change', { bubbles: true, cancelable: true })
  element.dispatchEvent(event)
}

/**
 * Simulate drag and drop
 */
export const dragAndDrop = (source, target) => {
  // Dragstart on source
  const dragStartEvent = new Event('dragstart', { bubbles: true, cancelable: true })
  dragStartEvent.dataTransfer = {
    data: {},
    setData(key, value) {
      this.data[key] = value
    },
    getData(key) {
      return this.data[key]
    }
  }
  source.dispatchEvent(dragStartEvent)

  // Dragenter on target
  const dragEnterEvent = new Event('dragenter', { bubbles: true, cancelable: true })
  target.dispatchEvent(dragEnterEvent)

  // Drop on target
  const dropEvent = new Event('drop', { bubbles: true, cancelable: true })
  dropEvent.dataTransfer = dragStartEvent.dataTransfer
  target.dispatchEvent(dropEvent)

  // Dragend on source
  const dragEndEvent = new Event('dragend', { bubbles: true, cancelable: true })
  source.dispatchEvent(dragEndEvent)
}

/**
 * Query helpers
 */
export const query = (container, selector) => {
  return container.querySelector(selector)
}

export const queryAll = (container, selector) => {
  return Array.from(container.querySelectorAll(selector))
}

/**
 * Get text content, trimmed
 */
export const getText = (element) => {
  return element ? element.textContent.trim() : ''
}

/**
 * Check if element has class
 */
export const hasClass = (element, className) => {
  return element && element.classList.contains(className)
}

/**
 * Check if element is visible
 */
export const isVisible = (element) => {
  if (!element) return false

  const style = window.getComputedStyle(element)
  return style.display !== 'none' &&
         style.visibility !== 'hidden' &&
         style.opacity !== '0'
}

/**
 * Mock fetch for testing HTTP requests
 */
export const mockFetch = (responses = {}) => {
  const originalFetch = global.fetch

  global.fetch = async (url, options) => {
    // Check if we have a mock response for this URL
    const mockResponse = responses[url] || responses['*']

    if (mockResponse) {
      return Promise.resolve({
        ok: mockResponse.ok !== undefined ? mockResponse.ok : true,
        status: mockResponse.status || 200,
        json: async () => mockResponse.json || {},
        text: async () => mockResponse.text || '',
        headers: new Headers(mockResponse.headers || {})
      })
    }

    // Fall back to original fetch if available
    if (originalFetch) {
      return originalFetch(url, options)
    }

    throw new Error(`No mock response for ${url}`)
  }

  // Return cleanup function
  return () => {
    if (originalFetch) {
      global.fetch = originalFetch
    } else {
      delete global.fetch
    }
  }
}

/**
 * Helper to test component rendering with specific data
 *
 * Usage:
 *   testRender('heat-solo', data, (component) => {
 *     expect(component.querySelector('input')).toBeTruthy()
 *   })
 */
export const testRender = async (tagName, data, testFn) => {
  const component = renderComponent(tagName, {}, data)

  try {
    // Wait for render if needed
    if (component.render) {
      await component.render()
    }

    // Run test
    await testFn(component)
  } finally {
    // Cleanup
    const container = component.parentElement
    cleanupContainer(container)
  }
}

/**
 * Create a spy/mock function
 */
export const createSpy = () => {
  const calls = []

  const spy = function(...args) {
    calls.push(args)
    return spy.returnValue
  }

  spy.calls = calls
  spy.returnValue = undefined
  spy.callCount = () => calls.length
  spy.calledWith = (...expectedArgs) => {
    return calls.some(args =>
      args.length === expectedArgs.length &&
      args.every((arg, i) => arg === expectedArgs[i])
    )
  }
  spy.reset = () => {
    calls.length = 0
  }

  return spy
}

/**
 * Assert helpers for common patterns
 */
export const assertRendersCorrectly = (component, expectations) => {
  if (expectations.hasElement) {
    expectations.hasElement.forEach(selector => {
      const element = component.querySelector(selector)
      if (!element) {
        throw new Error(`Expected element not found: ${selector}`)
      }
    })
  }

  if (expectations.hasText) {
    Object.entries(expectations.hasText).forEach(([selector, expectedText]) => {
      const element = component.querySelector(selector)
      const actualText = getText(element)
      if (actualText !== expectedText) {
        throw new Error(`Expected "${expectedText}" but got "${actualText}" for ${selector}`)
      }
    })
  }

  if (expectations.hasClass) {
    Object.entries(expectations.hasClass).forEach(([selector, className]) => {
      const element = component.querySelector(selector)
      if (!hasClass(element, className)) {
        throw new Error(`Expected element to have class "${className}": ${selector}`)
      }
    })
  }

  if (expectations.isVisible) {
    expectations.isVisible.forEach(selector => {
      const element = component.querySelector(selector)
      if (!isVisible(element)) {
        throw new Error(`Expected element to be visible: ${selector}`)
      }
    })
  }

  if (expectations.isHidden) {
    expectations.isHidden.forEach(selector => {
      const element = component.querySelector(selector)
      if (isVisible(element)) {
        throw new Error(`Expected element to be hidden: ${selector}`)
      }
    })
  }
}
