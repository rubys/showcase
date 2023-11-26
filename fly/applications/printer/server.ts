// print on demand app
//
// Handles http requests for paths ending in .pdf, by stripping off the
// extension and using puppeteer to fetch the modified path from the
// host app, convert that page to PDF and return the generated
// PDF as the response.
//
// Requests for anything else will be redirected back to the host application
// after reseting the timeout.  This is useful for ensuring that the Chrome
// instance is "warmed-up" prior to issuing requests.

import puppeteer, { PaperFormat } from 'puppeteer-core'

// fetch configuration fron environment variables
const PORT = process.env.PORT || 3000
const FORMAT = (process.env.FORMAT || "letter") as PaperFormat
const JAVASCRIPT = (process.env.JAVASCRIPT != "false")
const TIMEOUT = (parseInt(process.env.TIMEOUT || '15')) * 60 * 1000 // minutes
const HOSTNAME = process.env.HOSTNAME ||
  (process.env.FLY_APP_NAME?.endsWith("-pdf") &&
    `${process.env.FLY_APP_NAME.slice(0, -4)}.fly.dev`)

if (!HOSTNAME) {
  console.error("HOSTNAME is required")
  process.exit(1)
}

// location of Chrome executable (useful for local debugging)
const chrome = process.platform == "darwin"
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  : '/usr/bin/google-chrome'

// launch a single headless Chrome instance to be used by all requests
const browser = await puppeteer.launch({
  headless: "new",
  executablePath: chrome
})

// start initial timeout
let timeout = setTimeout(exit, TIMEOUT)

// process HTTP requests
const server = Bun.serve({
  port: PORT,

  async fetch(request) {
    // cancel timeout
    clearTimeout(timeout)

    // map URL to showcase site
    const url = new URL(request.url)
    url.hostname = HOSTNAME
    url.protocol = 'https:'
    url.port = ''

    // redirect non pdf requests back to host
    if (!url.pathname.endsWith('.pdf')) {
      // start new timeout
      timeout = setTimeout(exit, TIMEOUT)

      return new Response(`Non PDF request - redirecting`, {
        status: 301,
        headers: { Location: url.href }
      })
    }

    // strip [index].pdf from end of URL
    url.pathname = url.pathname.slice(0, -4)
    if (url.pathname.endsWith('/index')) url.pathname = url.pathname.slice(0, -5)

    console.log(`Printing ${url.href}`)

    // create a new browser page (tab)
    const page = await browser.newPage()

    // main puppeteer logic: fetch url, convert to URL, return response
    try {
      // disable javascript (optional)
      await page.setJavaScriptEnabled(JAVASCRIPT)

      // copy headers (including auth, excluding host) from original request
      const headers = Object.fromEntries(request.headers)
      delete headers.host
      await page.setExtraHTTPHeaders(headers)

      // fetch page to be printed
      await page.goto(url.href, {
        waitUntil: JAVASCRIPT ? 'networkidle2' : 'load'
      })

      // convert page to pdf - using preferred format and in full color
      const pdf = await page.pdf({
        format: FORMAT,
        printBackground: true
      })

      // return the generated PDF as the response
      return new Response(pdf, {
        headers: { "Content-Type": "application/pdf" }
      })

    } catch (error: any) {
      // handle unauthorized separately
      // see: https://github.com/puppeteer/puppeteer/issues/9856
      if (error.toString().includes("net::ERR_INVALID_AUTH_CREDENTIALS")) {
        return new Response(`Unauthorized`, {
          status: 401,
          headers: {
            "Content-Type": "text/plain",
            "www-authenticate": 'Basic realm="Showcase"'
          }
        })
      } else {
        // all other errors
        console.error(error.stack || error);
        return new Response(`<pre>${error.stack || error}</pre>`, {
          status: 500,
          headers: { "Content-Type": "text/html" }
        })
      }

    } finally {
      // close tab
      page.close()

      // start new timeout
      clearTimeout(timeout)
      timeout = setTimeout(exit, TIMEOUT)
    }
  }
})

console.log(`Printer server listening on port ${server.port}`)

process.on("SIGINT", exit)

// Exit cleanly on either SIGINT or timeout.  The fly proxy will restart the
// app when the next request comes in.
function exit() {
  console.log("exiting")
  browser.close()
  process.exit()
}
