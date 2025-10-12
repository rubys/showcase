// Changes times to local time
function fixTime(time) {
  let text = time.textContent
  let date
  if (text.includes('-')) {
    date = new Date(Date.parse(text))
  } else {
    let match = text.match(/^(\d+)\/(\w+)\/(\d+):\d+:\d+:\d+Z/)
    if (!match) return
    date = new Date([match[2], match[1], match[3]].join(' '))
    date = new Date(date.toISOString().slice(0, 11) + text.slice(12, 21))
  }
  time.setAttribute('datetime', date.toISOString())
  time.setAttribute('title', text.slice(0, 21))
  time.textContent = date.toLocaleString().replace(',', '')
}

for (let time of document.querySelectorAll('time')) {
  fixTime(time)
}

// Filter handling: add a query parameter to the URL
let filter = document.querySelector('input[name=filter]')
filter.addEventListener("click", () => {
  let url = new URL(window.location)
  let search = url.searchParams
  search.set('filter', filter.checked ? "on" : "off")
  url.search = search.toString()
  location = url
})

// Websocket handling: add new log entries to the top of the list
let ws = null
let counter = 1
let delay = 1
let interval = null

function openws() {
  if (ws) return

  if (--counter > 0) return
  if (delay < 20) delay *= 2
  counter = delay

  let url = new URL('websocket', window.location)

  ws = new WebSocket(url.href.replace('http', 'ws'))

  ws.onopen = () => {
    if (interval) {
      console.log('reconnected')
      clearInterval(interval)
      interval = null
    }

    counter = delay = 1
  };

  ws.onerror = error => {
    console.log(error)
    if (!interval) interval = setInterval(openws, 500)
  };

  ws.onclose = () => {
    ws = null
    if (!interval) interval = setInterval(openws, 500)
  };

  ws.onmessage = (event) => {
    try {
      let data = JSON.parse(event.data)

      if (data.filtered && filter.checked) return

      let span = document.createElement('span')
      span.innerHTML = data.message

      for (let time of span.querySelectorAll('time')) {
        fixTime(time)
      }

      let pre = document.querySelector('pre')

      pre.prepend(document.createTextNode("\n"))
      for (let element of [...span.children].reverse()) {
        pre.prepend(element)
      }
    } catch (e) {
      console.log(e)
    }
  }
}

// Get realtime updates unless a start date is specified or view is printer
let search = new URL(window.location).searchParams
if (!search.get('start') && search.get('view') !== 'printer' && search.get('view') !== 'demo') {
  openws()
}

// Show the Sentry issue link if a new issue was created
fetch(new URL("/sentry/seen", window.location).href)
  .then(response => response.text())
  .then(text => {
    if (!text) return

    const a = document.createElement('a')
    a.className = "sentry"
    a.href = text
    a.textContent = "Issue"

    const h2 = document.querySelector('h2')
    h2.appendChild(a)
  })

// log traversal via arrow keys
const dates = [...document.querySelectorAll("#archives a")].map(node => node.textContent)
document.addEventListener("keydown", event => {
  let location = new URL(window.location)
  const start = location.searchParams.get("start")
  if (event.key === "ArrowLeft") {
    event.preventDefault()
    let index = dates.indexOf(start)
    if (index === -1) return
    if (index === 0) return
    location.searchParams.set("start", dates[index - 1])
    window.location = location
  } else if (event.key === "ArrowRight") {
    event.preventDefault()
    let index = dates.indexOf(start)
    if (index === -1) index = 0
    if (index === dates.length - 1) return
    location.searchParams.set("start", dates[index + 1])
    window.location = location
  } else if (event.key === "p") {
    event.preventDefault()
    location.searchParams.set("view", "printer")
    window.location = location
  } else if (event.key === "h") {
    event.preventDefault()
    location.searchParams.set("view", "heartbeat")
    window.location = location
  } else if (event.key === "t") {
    event.preventDefault()
    location.searchParams.set("view", "tenant")
    window.location = location
  } else if (event.key === "d") {
    event.preventDefault()
    location.searchParams.set("view", "demo")
    window.location = location
  } else if (event.key === "Enter" || event.key === "Escape") {
    event.preventDefault()
    location.searchParams.delete("view")
    window.location = location
  }
})