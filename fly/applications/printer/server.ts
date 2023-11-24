import puppeteer from 'puppeteer-core'

const PORT = 3000
const KEEP_ALIVE = 15 * 60 * 1000 // fifteen minutes

let timeout = setTimeout(exit, KEEP_ALIVE)

const chrome = process.platform == "darwin"
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  : '/usr/bin/google-chrome'

const browser = await puppeteer.launch({
  headless: "new",
  executablePath: chrome
})

Bun.serve({
  port: PORT,

  async fetch(request) {
    // map URL to showcase site
    const url = new URL(request.url)
    url.hostname = 'smooth.fly.dev'
    url.protocol = 'https:'
    url.port = ''

    // redirect non pdf requests back to smooth.fly.dev
    if (!url.pathname.endsWith('.pdf')) {
      return new Response(`Non PDF request - redirecting`, {
        status: 301,
        headers: { Location: url.href }
      })
    }

    // cancel timeout
    clearTimeout(timeout)

    // strip [index].pdf from end of URL
    url.pathname = url.pathname.slice(0, -4)
    if (url.pathname.endsWith('/index')) url.pathname = url.pathname.slice(0, -5)

    console.log(`Printing ${url.href}`)

    const page = await browser.newPage()
    await page.setJavaScriptEnabled(false)

    // copy headers (including auth, excluding host) from original request
    const headers = Object.fromEntries(request.headers)
    delete headers.host
    await page.setExtraHTTPHeaders(headers)

    // main puppeteer logic: fetch url, convert to URL, return response
    try {
      await page.goto(url.href, { waitUntil: 'networkidle0' })

      const pdf = await page.pdf({
        format: 'letter',
        printBackground: true
      })

      return new Response(pdf, {
        headers: { "Content-Type": "application/pdf" }
      })

    } catch (error : any) {
      if (error.toString().includes("net::ERR_INVALID_AUTH_CREDENTIALS")) {
        return new Response(`Unauthorized`, {
          status: 401,
          headers: { 
            "Content-Type": "text/plain",
            "www-authenticate": 'Basic realm="Showcase"'
          }
        })
      } else {
        console.error(error.stack || error);
        return new Response(`<pre>${error.stack || error}</pre>`, {
          status: 500,
          headers: { "Content-Type": "text/html" }
        })
      }

    } finally {
      page.close()

      // start new timeout
      clearTimeout(timeout)
      timeout = setTimeout(exit, KEEP_ALIVE)
    }

  }
})

console.log(`Printer server listening on port ${PORT}`)

process.on("SIGINT",exit)

function exit() {
  console.log("exiting")
  browser.close()
  process.exit()
}
