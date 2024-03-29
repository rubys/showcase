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

import puppeteer, { PaperFormat, Page } from 'puppeteer-core'
import chalk from 'chalk'

// fetch configuration fron environment variables
const PORT = process.env.PORT || 3000
const FETCH_TIMEOUT = 30_000
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

let browser: puppeteer.Browser = null

// launch a single headless Chrome instance to be used by all requests
try {
  browser = await puppeteer.launch({
    headless: "new",
    executablePath: chrome
  })
} catch (error: any) {
  console.error(chalk.white.bgRed.bold(`Error launching browser - exiting`))
  console.error(chalk.white.bgRed.bold(error.stack || error))
  process.exit(1)
}

// start initial timeout
let timeout = setTimeout(exit, TIMEOUT)

// is a shutdown needed?  Used to avoid starting a new timeout after an error.
let shutdown = false

// determine if fetches should be cancelled
let deadManSwitch = false

// process HTTP requests
const server = Bun.serve({
  port: PORT,

  async fetch(request) {
    // if the previous request never completed, shut down the server and replay request
    if (deadManSwitch) {
      console.log(chalk.red(`Dead server, replaying request`))

      timeout = setTimeout(exit, 500)

      return new Response(`Service Unavailable`, {
        status: 307,
        headers: { "Fly-Replay": "elsewhere=true" }
      })
    }

    deadManSwitch = true

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

      console.log(`${chalk.yellow('Redirecting')} ${chalk.black(url.href)}`)
      deadManSwitch = false

      return new Response(`Non PDF request - redirecting`, {
        status: 301,
        headers: { Location: url.href }
      })
    }

    // strip [index].pdf from end of URL
    url.pathname = url.pathname.slice(0, -4)
    if (url.pathname.endsWith('/index')) url.pathname = url.pathname.slice(0, -5)

    console.log(`${chalk.green.bold('Fetching')} ${chalk.black(url.href)}`)

    // create a new browser page (tab)
    let page: Page
    try {
      page = await browser.newPage()
    } catch (error: any) {
      console.error(chalk.white.bgRed.bold(`Error creating page - replaying and shutting down server`))
      console.error(chalk.white.bgRed.bold(error.stack || error))
      timeout = setTimeout(exit, 500)
      return new Response(`<pre>${error.stack || error}</pre>`, {
        status: 307,
        headers: { "Content-Type": "text/html", "Fly-Replay": "elsewhere=true" }
      })
    }

    page.setDefaultNavigationTimeout(FETCH_TIMEOUT)
    page.setDefaultTimeout(FETCH_TIMEOUT)

    // main puppeteer logic: fetch url, convert to URL, return response
    try {
      // disable javascript (optional)
      await page.setJavaScriptEnabled(JAVASCRIPT)

      // copy headers (including auth, excluding host) from original request
      const headers = {} as Record<string, string>
      request.headers.forEach((value, key) => {
        if (key != 'host') headers[key] = value
      })
      await page.setExtraHTTPHeaders(headers)

      // fetch page to be printed
      try {
        await page.goto(url.href, {
          waitUntil: JAVASCRIPT ? 'networkidle2' : 'load',
          timeout: FETCH_TIMEOUT
        })
      } catch (error: any) {
        if (error.message.includes("ERR_NETWORK_CHANGED")) {
          await new Promise((resolve) => setTimeout(resolve, 100));

          console.log(`${chalk.yellow.bold('Retrying')} ${chalk.black(url.href)}`)
          await page.goto(url.href, {
            waitUntil: JAVASCRIPT ? 'networkidle2' : 'load',
            timeout: FETCH_TIMEOUT * 4
          })
        } else {
          throw error
        }
      }

      // convert page to pdf - using preferred format and in full color
      console.log(`${chalk.green.bold('Converting')} ${chalk.black(url.href + ' to PDF')}`)
      const pdf = await page.pdf({
        format: FORMAT,
        preferCSSPageSize: true,
        printBackground: true
      })

      // indicate that a request has completed
      deadManSwitch = false

      // return the generated PDF as the response
      console.log(`${chalk.green.bold('Responding')} ${chalk.black('with ' + url.href)}`)
      return new Response(pdf, {
        headers: { "Content-Type": "application/pdf" }
      })

    } catch (error: any) {
      // handle unauthorized separately
      // see: https://github.com/puppeteer/puppeteer/issues/9856
      if (error.toString().includes("net::ERR_INVALID_AUTH_CREDENTIALS")) {
        console.log(chalk.red(`Unauthorized`))
        deadManSwitch = false
        return new Response(`Unauthorized`, {
          status: 401,
          headers: {
            "Content-Type": "text/plain",
            "www-authenticate": 'Basic realm="Showcase"'
          }
        })
      } else {
        // indicate that a shutdown is warranted
        shutdown = true

        // all other errors
        console.log(chalk.white.bgRed.bold(`Error fetching ${url.href} - Shutting down server`))
        console.error(chalk.white.bgRed.bold(error.stack || error))
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
      timeout = setTimeout(exit, shutdown ? 500 : TIMEOUT)
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
