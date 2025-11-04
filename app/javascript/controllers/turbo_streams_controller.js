import { Controller } from "@hotwired/stimulus"

// Controller that provides custom WebSocket-based Turbo Streams support
// Automatically subscribes to streams marked with data-turbo-stream
export default class extends Controller {
  connect() {
    console.debug("Turbo Streams WebSocket controller connected")

    // Find all turbo-stream markers in the document
    const markers = document.querySelectorAll('[data-turbo-stream="true"]')

    if (markers.length === 0) {
      console.debug("No turbo-stream markers found")
      return
    }

    // Collect all stream names
    this.streams = new Set()
    markers.forEach(marker => {
      const streams = marker.dataset.streams
      if (streams) {
        streams.split(',').forEach(stream => this.streams.add(stream.trim()))
      }
    })

    if (this.streams.size === 0) {
      console.debug("No streams to subscribe to")
      return
    }

    console.debug("Subscribing to streams:", Array.from(this.streams))

    // Create WebSocket connection using the cable URL from meta tag
    const cableUrlMeta = document.querySelector('meta[name="action-cable-url"]')
    const cableUrl = cableUrlMeta?.content || `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/cable`
    this.ws = new WebSocket(cableUrl)
    this.subscribed = new Set()

    this.ws.onopen = () => {
      console.debug('WebSocket connected')
      // Subscribe to all streams
      this.streams.forEach(stream => {
        this.ws.send(JSON.stringify({
          type: 'subscribe',
          stream: stream
        }))
      })
    }

    this.ws.onmessage = (event) => {
      const msg = JSON.parse(event.data)

      switch (msg.type) {
        case 'subscribed':
          console.debug('Subscribed to stream:', msg.stream)
          this.subscribed.add(msg.stream)
          break

        case 'message':
          if (this.streams.has(msg.stream)) {
            console.debug("Received update on stream:", msg.stream)
            this.processTurboStream(msg.stream, msg.data)
          }
          break

        case 'ping':
          // Respond to ping
          this.ws.send(JSON.stringify({ type: 'pong' }))
          break
      }
    }

    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error)
    }

    this.ws.onclose = () => {
      console.debug('WebSocket disconnected')

      // Auto-reconnect after 3 seconds if we had subscriptions
      if (this.subscribed.size > 0) {
        setTimeout(() => {
          console.debug('Attempting to reconnect...')
          this.connect()
        }, 3000)
      }
    }
  }

  disconnect() {
    // Clean up subscription when controller is removed
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.streams.forEach(stream => {
        this.ws.send(JSON.stringify({
          type: 'unsubscribe',
          stream: stream
        }))
      })
      this.ws.close()
    }
    this.subscribed?.clear()
  }

  processTurboStream(stream, data) {
    // Check if data is a string (Turbo Stream HTML) or object (custom JSON)
    if (typeof data === 'string') {
      // Process as Turbo Stream HTML
      this.processTurboStreamHTML(data)
    } else {
      // Dispatch custom event for JSON data
      const event = new CustomEvent('turbo:stream-message', {
        detail: { stream: stream, data: data },
        bubbles: true
      })
      document.dispatchEvent(event)
      console.debug('Dispatched turbo:stream-message event for stream:', stream)
    }
  }

  processTurboStreamHTML(html) {
    // Parse the Turbo Stream HTML and apply the action
    const parser = new DOMParser()
    const doc = parser.parseFromString(html, 'text/html')
    const turboStream = doc.querySelector('turbo-stream')

    if (!turboStream) {
      console.warn('No turbo-stream element found in:', html)
      return
    }

    const action = turboStream.getAttribute('action')
    const target = turboStream.getAttribute('target')
    const template = turboStream.querySelector('template')

    if (!target) {
      console.warn('No target specified in turbo-stream')
      return
    }

    const targetElement = document.getElementById(target)
    if (!targetElement) {
      console.warn('Target element not found:', target)
      return
    }

    switch (action) {
      case 'replace':
        if (template && template.content) {
          const newElement = template.content.firstElementChild.cloneNode(true)
          targetElement.replaceWith(newElement)
          console.debug('Replaced element:', target)
        }
        break

      case 'update':
        if (template && template.content) {
          targetElement.innerHTML = template.innerHTML
          console.debug('Updated element:', target)
        }
        break

      case 'append':
        if (template && template.content) {
          targetElement.appendChild(template.content.cloneNode(true))
          console.debug('Appended to element:', target)
        }
        break

      case 'prepend':
        if (template && template.content) {
          targetElement.prepend(template.content.cloneNode(true))
          console.debug('Prepended to element:', target)
        }
        break

      case 'remove':
        targetElement.remove()
        console.debug('Removed element:', target)
        break

      default:
        console.warn('Unknown turbo-stream action:', action)
    }
  }
}
