import { Controller } from "@hotwired/stimulus"

// Controller that provides custom WebSocket-based Turbo Streams support
// Automatically subscribes to streams marked with data-turbo-stream
export default class extends Controller {
  connect() {
    console.log("Turbo Streams WebSocket controller connected")

    // Find all turbo-stream markers in the document
    const markers = document.querySelectorAll('[data-turbo-stream="true"]')

    if (markers.length === 0) {
      console.log("No turbo-stream markers found")
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
      console.log("No streams to subscribe to")
      return
    }

    console.log("Subscribing to streams:", Array.from(this.streams))

    // Create WebSocket connection
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    this.ws = new WebSocket(`${protocol}//${window.location.host}/cable`)
    this.subscribed = new Set()

    this.ws.onopen = () => {
      console.log('WebSocket connected')
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
          console.log('Subscribed to stream:', msg.stream)
          this.subscribed.add(msg.stream)
          break

        case 'message':
          if (this.streams.has(msg.stream)) {
            console.log("Received update on stream:", msg.stream)
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
      console.log('WebSocket disconnected')

      // Auto-reconnect after 3 seconds if we had subscriptions
      if (this.subscribed.size > 0) {
        setTimeout(() => {
          console.log('Attempting to reconnect...')
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
    this.subscribed.clear()
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
      console.log('Dispatched turbo:stream-message event for stream:', stream)
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
          console.log('Replaced element:', target)
        }
        break

      case 'update':
        if (template && template.content) {
          targetElement.innerHTML = template.innerHTML
          console.log('Updated element:', target)
        }
        break

      case 'append':
        if (template && template.content) {
          targetElement.appendChild(template.content.cloneNode(true))
          console.log('Appended to element:', target)
        }
        break

      case 'prepend':
        if (template && template.content) {
          targetElement.prepend(template.content.cloneNode(true))
          console.log('Prepended to element:', target)
        }
        break

      case 'remove':
        targetElement.remove()
        console.log('Removed element:', target)
        break

      default:
        console.warn('Unknown turbo-stream action:', action)
    }
  }
}
