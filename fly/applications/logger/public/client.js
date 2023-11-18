for (let time of document.querySelectorAll('time')) {
  let text = time.textContent;
  let match = text.match(/^(\d+)\/(\w+)\/(\d+):\d+:\d+:\d+Z/)
  if (!match) continue
  let date = new Date([match[2], match[1], match[3]].join(' '))
  date = new Date(date.toISOString().slice(0,11) + text.slice(12,21))
  time.setAttribute('datetime', date.toISOString())
  time.setAttribute('title', text.slice(0,21))
  time.textContent = date.toLocaleString().replace(',', '')
}

let filter = document.querySelector('input[name=filter]')
filter.addEventListener("click", () => {
  let url = new URL(window.location)
  let search = url.searchParams
  search.set('filter',  filter.checked ? "on" : "off")
  url.search = search.toString()
  location = url
})

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
      let span = document.createElement('span')
      span.innerHTML = event.data

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

openws()