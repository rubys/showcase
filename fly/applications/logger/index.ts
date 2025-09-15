import fs from 'node:fs'
import { promises as dns } from 'node:dns'
import readline from 'node:readline'
import path from 'node:path'

import express from "express"
import Convert from 'ansi-to-html'
import * as bcrypt from "bcrypt"

import { startWs } from './websocket.ts'

import { pattern, filtered, format, highlight, visit, HOST, LOGS, formatJsonLog, filteredJsonLog, isRailsAppLog } from "./view.ts"

const PORT = 3000
const { NODE_ENV } = process.env

const app = express();

const appName = process.env.FLY_APP_NAME

const FLY_REGION = process.env.FLY_REGION || 'undefined'
const SEENFILE = Bun.file(`${LOGS}/.seen`)

let lastRegionCheck = 0
let lastRegions: string[] = []

async function getRegions(): Promise<string[]> {
  if (!process.env.FLY_REGION) return []
  let checkTime = new Date().getTime()

  if (NODE_ENV != 'development' && checkTime - lastRegionCheck > 60000) {
    try {
      lastRegions = (await dns.resolveTxt(`regions.${appName}.internal`)).join(',').split(',')
    } catch (err) {
      console.error("DNSException in getRegions:", err)
      lastRegions = []
    }
    lastRegionCheck = checkTime
  }

  return lastRegions
}

async function getLatest() {
  const { SENTRY_TOKEN, SENTRY_ORG, SENTRY_PROJECT } = process.env
  if (!SENTRY_TOKEN || !SENTRY_ORG || !SENTRY_PROJECT) return "0"
  const url = `https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/issues/`

  const api_response = await fetch(url, {
    headers: { Authorization: `Bearer ${SENTRY_TOKEN}` }
  })

  const issues = await api_response.json() as { lastSeen: string }[]

  let lastSeen = "0";
  for (const issue of issues) {
    if (issue.lastSeen > lastSeen) lastSeen = issue.lastSeen;
  }

  return lastSeen
}

startWs(app)

// health check (not authenticated)
app.get("/up", (_, response) => {
  response.status(200).send("OK")
})

// authentication middleware
app.use(async (req, res, next) => {
  const { HTPASSWD, HTPASSWD2 } = process.env

  if (NODE_ENV == "development") return next()

  // parse login and password from headers
  const b64auth = (req.headers.authorization || '').split(' ')[1] || ''

  if (HTPASSWD && await bcrypt.compare(b64auth, HTPASSWD)) return next()
  if (HTPASSWD2 && await bcrypt.compare(b64auth, HTPASSWD2)) return next()
  // console.log(`fly secrets set --stage 'HTPASSWD=${await bcrypt.hash(b64auth, 10)}'`)

  // Access denied...
  res.set('WWW-Authenticate', 'Basic realm="smooth-logger"')
  res.status(401).send('Authentication required.')
})

app.get("/sentry/link", (_, response) => {
  const { SENTRY_ORG, SENTRY_PROJECT } = process.env
  const link = `https://${SENTRY_ORG}.sentry.io/issues/?project=${SENTRY_PROJECT}`
  response.redirect(302, link)

  getLatest().then(latest => {
    Bun.write(SEENFILE, latest)
    setTimeout(() => fetchOthers("/sentry/link").catch(console.error), 1000)
  })
})

app.get("/sentry/seen", async (_, response) => {
  const lastSeen = await getLatest()
  const seen = (await SEENFILE.exists()) ? (await SEENFILE.text()) : "0"
  response.set('Access-Control-Allow-Origin', '*')

  if (seen === lastSeen || NODE_ENV === "development") {
    response.send("")
  } else {
    response.send("/sentry/link")
  }
})

app.get("/sentry/seen.debug", async (_, response) => {
  const lastSeen = await getLatest()
  const seen = (await SEENFILE.exists()) ? (await SEENFILE.text()) : "0"
  response.set('Access-Control-Allow-Origin', '*')

  response.write(`region:   ${process.env.FLY_REGION}\n`)
  response.write(`seen:     ${seen}\n`)
  response.write(`lastSeen: ${lastSeen}\n`)
  response.write('seenFile: ' + SEENFILE.name + '\n')
  response.write(`exists:   ${await SEENFILE.exists()}\n`)
  response.write(`text:     ${await SEENFILE.text()}\n`)
  response.write('result:   ' + (seen === lastSeen ? '""' : "/sentry/link"))
  response.end()
})

app.get("/regions/:region/(*)", async (request, response, next) => {
  let { region } = request.params;

  const REGIONS = await getRegions()

  if (region === FLY_REGION) {
    request.url = '/' + request.params[0]
    next()
  } else if (!REGIONS.includes(region)) {
    response.status(404).send('Not found')
  } else {
    response.set('Fly-Replay', `region=${region}`)
    response.status(409).send("wrong region\n")
  }
})

app.use('/logs', express.static(LOGS))
app.use('/static', express.static('./public'))

let timeout = 0;
app.get("/", async (req, res) => {
  if (req.headers['x-forwarded-port']) {
    if (timeout !== 0) clearTimeout(timeout)
    timeout = +setTimeout(() => fetchOthers("/").catch(console.error), 1000)
  }

  let printer = (req.query.view == 'printer')

  let heartbeat = (req.query.view == 'heartbeat')
  interface RegionHeartbeats {[key: string]: number}
  let regionHeatbeats : RegionHeartbeats = {}

  let demo = (req.query.view == 'demo')
  let demoVisitors = new Set()

  let filter = (req.query.filter !== 'off') && !demo

  let printerApps = new Set()
  let lastVisit = visit()

  let logs = await fs.promises.readdir(LOGS);
  logs.sort();

  let results: string[] = [];
  let previous: string[] = [];

  const convert = printer ? new Convert() : null;

  results.push('</pre>')

  let start = (req.query.start || '') as string

  while (logs.length > 0) {
    const log = logs.pop();
    if (!log?.endsWith('.log')) continue;
    if (log.slice(0, start.length) > start) continue;

    const rl = readline.createInterface({
      input: fs.createReadStream(path.join(LOGS, log)),
      crlfDelay: Infinity
    });

    await new Promise(resolve => {
      rl.on('line', line => {
        if (printer) {
          let match = line.match(/\[(\w+)\] .* Preparing to run: .* as chrome/)
          if (match) printerApps.add(match[1])
          match = line.match(/^(\S+)\s+\[(\w+)\]\s(\w+)\s(.*)/)

          if (match && printerApps.has(match[2])) {
            results.push([
              `<time>${match[1]}</time>`,
              `[${match[2]}]`,
              `<a href="${HOST}/regions/${match[3]}/status"><span style="color: maroon">${match[3]}</span></a>`,
              convert?.toHtml(match[4]) || ''
            ].join(' '))
          }

          return
        } else if (heartbeat) {
          if (line.includes(' heartbeat.1 | HEARTBEAT ')) {
            let date = Date.parse(line.split(' ')[0])
            let region = line.split(' ').pop() || '???'
            if (!regionHeatbeats[region]) regionHeatbeats[region] = date
            if (date - regionHeatbeats[region] > 35 * 60 * 1000) {
              results.push(`<span style="color: red">${line}</span>`)
            } else {
              results.push(line)
            }
            regionHeatbeats[region] = date
          }
          return
        }

        // Try to handle as JSON log first
        let jsonLog = null;
        let logEntry = null;

        // Extract the message part from the log line (after timestamp, machine, region, level)
        let messageMatch = line.match(/^\S+\s+\[.*?\]\s+(\w+)\s+\[\w+\]\s+(.*)$/);
        if (messageMatch) {
          let region = messageMatch[1];
          let message = messageMatch[2];
          if (message.trim().startsWith('{')) {
            try {
              jsonLog = JSON.parse(message.trim());

              // Create flyData equivalent for refresh context
              let flyData = {
                fly: {
                  region: region
                }
              };

              logEntry = formatJsonLog(jsonLog, flyData);
            } catch (e) {
              // Not valid JSON, fall through to traditional parsing
            }
          }
        }

        if (!logEntry) {
          // Handle traditional log format
          let match = line.match(pattern);
          if (!match) return;
          if (demo && !line.includes('demo')) return;
          if (filter && filtered(match)) return;
          logEntry = format(match);

          if (demo) {
            if (line.includes("POST") && !line.includes("events/console")) demoVisitors.add(match[2])
            if (demoVisitors.has(match[2])) logEntry = highlight(logEntry)
          } else if (line > lastVisit) {
            logEntry = highlight(logEntry)
          }
        } else {
          // Handle JSON log filtering and highlighting
          if (demo && !line.includes('demo')) return;

          // Always filter Rails application logs (they're too verbose)
          if (jsonLog && isRailsAppLog(jsonLog)) return;

          // Apply access log filtering only when filter is enabled (matching non-JSON behavior)
          if (filter && jsonLog && filteredJsonLog(jsonLog)) return;

          if (line > lastVisit) {
            logEntry = highlight(logEntry)
          }
        }

        results.push(logEntry)
      });

      rl.on('close', () => {
        resolve(null)
      });
    });

    if (previous.length > 0) results.push(...previous);
    previous = [];

    if (results.length > 40) break;

    previous = results;
    results = [previous.shift() as string];
  }

  if (previous.length > 0) results.push(...previous);

  results.push('<pre>')

  results.push("</p>")
  logs = await fs.promises.readdir(LOGS);
  logs = logs.filter(log => log.match(/^2\d\d\d-\d\d-\d\d\.log$/))
  logs.sort();
  if (!start) start = logs[logs.length - 1]
  for (const log of logs) {
    if (log.slice(0, start.length) == start) results.push('</u>')
    results.push(`<a href=/regions/${FLY_REGION}/logs/${log}>${log.replace('.log', '')}</a>`)
    if (log.slice(0, start.length) == start) results.push('<u>')
  }
  results.push('<p id="archives">')

  const REGIONS = await getRegions()

  results.push(`</h2>`)
  results.push(`</small>`)

  results.push(`<span style="float: right">
  <input name="filter" type="checkbox"${filter ? " checked" : ""}>
  filter
  </span>`)

  for (const region of REGIONS) {
    if (region != FLY_REGION) {
      results.push(`<a href="/regions/${region}/">${region}</a>`)
    }
  }
  results.push(`<small style="font-weight: normal">`)
  if (process.env.FLY_REGION) {
    results.push(`<a href="https://smooth.fly.dev/">smooth.fly.dev</a> logs: ${FLY_REGION}`)
  } else {
    results.push(`<a href="https://showcase.party/">showcase.party</a> logs`)
  }
  results.push(`<h2>`)

  res.send(`
    <!DOCTYPE html>
    <style>
      a {color: black; text-decoration: none}
      .sentry {margin: 0 10px; padding: 4px; border: solid red 2px; border-radius: 10px}
    </style>
    ${results.reverse().join("\n")}
    <script src="/static/client.js"></script>
  `)
})

// scan for request
app.get("/request/:request_id", async (request, response, next) => {
  let { request_id } = request.params;
  if (request_id.length < 20 || !request_id.match(/^\w+$/)) return next()

  const isRaw = request.query.raw !== undefined;
  const convert = new Convert();

  let logs = await fs.promises.readdir(LOGS);
  logs.sort();

  let results: string[] = [];
  let rawResults: string[] = [];

  results.push('<pre>')

  while (logs.length > 0) {
    const log = logs.pop();
    if (!log?.endsWith('.log')) continue;

    const rl = readline.createInterface({
      input: fs.createReadStream(path.join(LOGS, log)),
      crlfDelay: Infinity
    });

    await new Promise(resolve => {
      rl.on('line', line => {
        if (!line.includes(request_id)) return;

        // Always collect raw lines
        rawResults.push(line);

        if (!isRaw) {
          // Try to handle as JSON log first
          let messageMatch = line.match(/^\S+\s+\[.*?\]\s+(\w+)\s+\[\w+\]\s+(.*)$/);
          if (messageMatch) {
            let region = messageMatch[1];
            let message = messageMatch[2];
            if (message.trim().startsWith('{')) {
              try {
                let jsonLog = JSON.parse(message.trim());

                // Create flyData equivalent for request context
                let flyData = {
                  fly: {
                    region: region
                  }
                };

                let formattedJson = formatJsonLog(jsonLog, flyData, false); // Don't truncate in request viewer
                if (formattedJson) {
                  // Apply ANSI conversion to the formatted JSON log
                  results.push(convert.toHtml(formattedJson));
                  return;
                }
              } catch (e) {
                // Not valid JSON, fall through to traditional handling
              }
            }
          }

          // Traditional log format with ANSI conversion
          results.push(convert.toHtml(line));
        }
      });

      rl.on('close', () => {
        resolve(null)
      });
    });

    if (results.length > 1 || rawResults.length > 0) break;
  }

  results.push('</pre>')

  const buttonStyle = `
    float: right;
    padding: 8px 16px;
    margin-top: 0.67em;
    background-color: #f0f0f0;
    border: 1px solid #ccc;
    border-radius: 4px;
    text-decoration: none;
    color: black;
    font-size: 14px;
  `;

  if (isRaw) {
    response.send(`
      <!DOCTYPE html>
      <style>
        .header-container { display: flex; align-items: center; justify-content: space-between; }
        a.toggle-button {
          padding: 8px 16px;
          background-color: #f0f0f0;
          border: 1px solid #ccc;
          border-radius: 4px;
          text-decoration: none;
          color: black;
          font-size: 14px;
        }
        a.toggle-button:hover { background-color: #e0e0e0; }
        pre { font-family: monospace; white-space: pre-wrap; word-wrap: break-word; }
        h1 { margin: 0.67em 0; }
      </style>
      <div class="header-container">
        <h1>Request ${request_id} (Raw)</h1>
        <a href="/request/${request_id}" class="toggle-button">View Formatted</a>
      </div>
      <pre>${rawResults.join("\n")}</pre>
    `)
  } else {
    response.send(`
      <!DOCTYPE html>
      <style>
        .header-container { display: flex; align-items: center; justify-content: space-between; }
        a.toggle-button {
          padding: 8px 16px;
          background-color: #f0f0f0;
          border: 1px solid #ccc;
          border-radius: 4px;
          text-decoration: none;
          color: black;
          font-size: 14px;
        }
        a.toggle-button:hover { background-color: #e0e0e0; }
        h1 { margin: 0.67em 0; }
      </style>
      <div class="header-container">
        <h1>Request ${request_id}</h1>
        <a href="/request/${request_id}?raw" class="toggle-button">View Raw</a>
      </div>
      ${results.join("\n")}
    `)
  }
})

// update lastVisit on all machines
async function fetchOthers(path: string) {
  let machines = (await dns.resolveTxt(`vms.${appName}.internal`)).join(',').split(',')
    .map((txt: String) => txt.split(' ')[0])

  for await (let machine of machines) {
    if (machine === process.env.FLY_MACHINE_ID) continue

    await fetch(`http://${machine}.vm.${appName}.internal:3000${path}`)
      .catch(console.error)
  }
}

app.listen(PORT, () => {
  console.log(`Listening on port ${PORT}...`)
})
