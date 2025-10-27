// print on demand app
//
// Handles http requests for paths ending in .pdf, by stripping off the
// extension and using puppeteer to fetch the modified path from the
// host app, convert that page to PDF and return the generated
// PDF as the response.
//
// Requests for paths ending in .xlsx are converted to .json and then
// fetched from the host apps, and the results are converted to .xlsx format.
//
// Requests for anything else will be redirected back to the host application
// after reseting the timeout.  This is useful for ensuring that the Chrome
// instance is "warmed-up" prior to issuing requests.

import puppeteer, { PaperFormat, Page } from 'puppeteer-core'
import chalk from 'chalk'
import * as XLSX from 'xlsx'
import { existsSync, readdirSync, statSync, rmSync } from 'fs'
import { join } from 'path'

// fetch configuration fron environment variables
const PORT = process.env.PORT || 3000
const FETCH_TIMEOUT = 30_000
const FORMAT = (process.env.PAPERSIZE || "letter") as PaperFormat
const JAVASCRIPT = (process.env.JAVASCRIPT != "false")
const TIMEOUT = (parseInt(process.env.TIMEOUT || '15')) * 60 * 1000 // minutes

// location of Chrome executable (useful for local debugging)
const chrome = process.platform == "darwin"
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  : '/usr/bin/google-chrome'

let browser: puppeteer.Browser = null

let puppeteerOptions : puppeteer.PuppeteerLaunchOptions = {
  headless: "new",
  executablePath: chrome,
  // https://www.browserless.io/blog/puppeteer-print
  args: [
    '--font-render-hinting=none',
    '--disable-gpu',
    '--disable-dev-shm-usage', // Use /tmp instead of /dev/shm
    '--no-first-run',
    '--no-zygote',
    '--no-sandbox', // Required when using --no-zygote
    '--disable-setuid-sandbox',
    '--single-process', // Helps reduce resource usage
    '--disable-extensions'
  ]
}

// Clean up old Puppeteer temp directories
function cleanupTempFiles() {
  try {
    const tmpDir = '/tmp'
    if (existsSync(tmpDir)) {
      const files = readdirSync(tmpDir)
      const now = Date.now()
      const oneHourAgo = now - (60 * 60 * 1000) // 1 hour in milliseconds

      for (const file of files) {
        if (file.startsWith('puppeteer_')) {
          const filePath = join(tmpDir, file)
          try {
            const stats = statSync(filePath)
            // Remove directories older than 1 hour
            if (stats.isDirectory() && stats.mtimeMs < oneHourAgo) {
              rmSync(filePath, { recursive: true, force: true })
              console.log(chalk.yellow(`Cleaned up old temp directory: ${file}`))
            }
          } catch (err) {
            // Ignore errors for individual files
          }
        }
      }
    }
  } catch (error) {
    console.error(chalk.red('Error cleaning temp files:'), error)
  }
}

// Run cleanup on startup
cleanupTempFiles()

// Run cleanup every 30 minutes
setInterval(cleanupTempFiles, 30 * 60 * 1000)

// launch a single headless Chrome instance to be used by all requests
try {
  browser = await puppeteer.launch(puppeteerOptions)
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
  idleTimeout: 255,
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

    // map URL to original site
    const url = new URL(request.url)
    if (process.env.BASE_HOSTNAME) url.hostname = process.env.BASE_HOSTNAME
    url.protocol = 'https:'
    url.port = ''

    if (url.pathname == "/up") {
      deadManSwitch = false
      return new Response("OK")
    }

    if (url.pathname.match(/\/env(\.\w+)?$/)) {
      // Build HTML page showing request and environment information
      const requestInfo = {
        method: request.method,
        url: request.url,
        pathname: url.pathname,
        hostname: url.hostname,
        search: url.search,
        headers: {} as Record<string, string>
      }
      
      request.headers.forEach((value, key) => {
        requestInfo.headers[key] = value
      })

      const html = `<!DOCTYPE html>
<html>
<head>
  <title>Environment Information</title>
  <style>
    body { font-family: monospace; margin: 20px; }
    h2 { color: #333; border-bottom: 2px solid #ccc; padding-bottom: 5px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background-color: #f2f2f2; }
    tr:nth-child(even) { background-color: #f9f9f9; }
    .key { font-weight: bold; color: #0066cc; }
  </style>
</head>
<body>
  <h1>Environment Information</h1>
  
  <h2>Request Information</h2>
  <table>
    <tr><th>Property</th><th>Value</th></tr>
    <tr><td class="key">Method</td><td>${requestInfo.method}</td></tr>
    <tr><td class="key">URL</td><td>${requestInfo.url}</td></tr>
    <tr><td class="key">Pathname</td><td>${requestInfo.pathname}</td></tr>
    <tr><td class="key">Hostname</td><td>${requestInfo.hostname}</td></tr>
    <tr><td class="key">Search</td><td>${requestInfo.search || '(none)'}</td></tr>
  </table>

  <h2>Request Headers</h2>
  <table>
    <tr><th>Header</th><th>Value</th></tr>
    ${Object.entries(requestInfo.headers).map(([key, value]) => 
      `<tr><td class="key">${key}</td><td>${value}</td></tr>`
    ).join('')}
  </table>

  <h2>Environment Variables</h2>
  <table>
    <tr><th>Variable</th><th>Value</th></tr>
    ${Object.entries(process.env).sort().map(([key, value]) => 
      `<tr><td class="key">${key}</td><td>${value}</td></tr>`
    ).join('')}
  </table>

  <h2>Server Configuration</h2>
  <table>
    <tr><th>Setting</th><th>Value</th></tr>
    <tr><td class="key">PORT</td><td>${PORT}</td></tr>
    <tr><td class="key">FORMAT</td><td>${FORMAT}</td></tr>
    <tr><td class="key">JAVASCRIPT</td><td>${JAVASCRIPT}</td></tr>
    <tr><td class="key">TIMEOUT</td><td>${TIMEOUT / 60000} minutes</td></tr>
    <tr><td class="key">FETCH_TIMEOUT</td><td>${FETCH_TIMEOUT / 1000} seconds</td></tr>
    <tr><td class="key">Platform</td><td>${process.platform}</td></tr>
    <tr><td class="key">Chrome Path</td><td>${chrome}</td></tr>
  </table>
</body>
</html>`

      deadManSwitch = false
      return new Response(html, {
        headers: { "Content-Type": "text/html" }
      })
    }

    if (url.pathname.endsWith('.xlsx')) {
      url.pathname = url.pathname.slice(0, -4) + 'json'
      let headers = {} as Record<string, string>
      request.headers.forEach((value, key) => {
        if (key != 'host'  && key != "accept-encoding") headers[key] = value
      })

      console.log(`${chalk.green.bold('Fetching')} ${chalk.black(url.href)}`)
      let response = await fetch(url.href, { headers, credentials: 'include'})
      if (!response.ok) {
        console.error(`${chalk.red.bold('Error fetching')} ${chalk.black(url.href)} ${response.status}`)
        return response
      }

      console.log(`${chalk.green.bold('Converting')} ${chalk.black(url.href + ' to XLSX')}`)
      let json = await response.json()
      let wb = XLSX.utils.book_new()
      for (const [name, sheet] of Object.entries(json)) {
        const ws = XLSX.utils.json_to_sheet(sheet as any[])
        XLSX.utils.book_append_sheet(wb, ws, name)
      }

      url.pathname = url.pathname.slice(0, -4) + 'xlsx'
      console.log(`${chalk.green.bold('Responding')} ${chalk.black('with ' + url.href)}`)
      return new Response(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }),
        { headers: { "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" } })
    }

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
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36')

    // main puppeteer logic: fetch url, convert to URL, return response
    try {
      // disable javascript (optional)
      await page.setJavaScriptEnabled(JAVASCRIPT)

      // copy headers (including auth, excluding host) from original request
      const headers = {} as Record<string, string>
      request.headers.forEach((value, key) => {
        if (key != 'host' && key != 'te') headers[key] = value
      })
      await page.setExtraHTTPHeaders(headers)

      // fetch page to be printed
      let response: any
      try {
        response = await page.goto(url.href, {
          waitUntil: JAVASCRIPT ? 'networkidle2' : 'load',
          timeout: FETCH_TIMEOUT
        })
      } catch (error: any) {
        if (error.message.includes("ERR_NETWORK_CHANGED")) {
          await new Promise((resolve) => setTimeout(resolve, 100));

          console.log(`${chalk.yellow.bold('Retrying')} ${chalk.black(url.href)}`)
          response = await page.goto(url.href, {
            waitUntil: JAVASCRIPT ? 'networkidle2' : 'load',
            timeout: FETCH_TIMEOUT * 4
          })
        } else {
          throw error
        }
      }

      // Retry on 503 responses (deployment updates)
      if (response && response.status() === 503) {
        const maxRetries = 10
        for (let attempt = 1; attempt <= maxRetries; attempt++) {
          console.log(`${chalk.yellow.bold('503 detected, retry')} ${attempt}/${maxRetries} ${chalk.black(url.href)}`)
          await new Promise((resolve) => setTimeout(resolve, 1000))

          try {
            response = await page.goto(url.href, {
              waitUntil: JAVASCRIPT ? 'networkidle2' : 'load',
              timeout: FETCH_TIMEOUT
            })

            if (response && response.status() !== 503) {
              console.log(`${chalk.green.bold('Retry successful')} ${chalk.black(url.href)}`)
              break
            }
          } catch (error: any) {
            if (attempt === maxRetries) {
              throw error
            }
            console.log(`${chalk.yellow.bold('Retry attempt failed')} ${attempt}/${maxRetries}`)
          }
        }
      }

      const format = url.searchParams.get('papersize') as PaperFormat || FORMAT;

      // convert page to pdf - using preferred format and in full color
      console.log(`${chalk.green.bold('Converting')} ${chalk.black(url.href + ' to PDF')}`)
      const pdf = await page.pdf({
        format: format,
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
      await page.close()

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
