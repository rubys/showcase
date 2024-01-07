import fs from 'node:fs'
import { exec } from "node:child_process"
import readline from 'node:readline'
import path from 'node:path'

import express from "express"

import { startWs } from './websocket.ts'

import { pattern, filtered, format, highlight, visit, LOGS } from "./view.ts";

const PORT = 3000

const app = express();

const appName = process.env.FLY_APP_NAME

const FLY_REGION = process.env.FLY_REGION
const SEENFILE = Bun.file('/logs/.seen')

let lastRegionCheck = 0
let lastRegions: string[] = []

async function getRegions(): Promise<string[]> {
  let checkTime = new Date().getTime()

  if (checkTime - lastRegionCheck > 60000) {
    lastRegions = await new Promise((resolve, reject) => {
      let dig = `dig +short -t txt regions.${appName}.internal`

      exec(dig, async (err, stdout, stderr) => {
        if (err) {
          reject(err)
        } else {
          resolve(JSON.parse(stdout).trim().split(","))
        }
      })
    })

    lastRegionCheck = checkTime
  }

  return lastRegions
}

async function getLatest() {
  const { SENTRY_TOKEN, SENTRY_ORG, SENTRY_PROJECT } = process.env
  const url = `https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/issues/`

  const api_response = await fetch(url, {
    headers: { Authorization: `Bearer ${SENTRY_TOKEN}` }
  })

  const issues = await api_response.json() as {lastSeen: string}[]

  let lastSeen = "0";
  for (const issue of issues) {
    if (issue.lastSeen > lastSeen) lastSeen = issue.lastSeen;
  }

  return lastSeen
}

startWs(app)

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
  console.log(JSON.stringify([lastSeen, seen]))

  if (seen === lastSeen) {
    response.send("")
  } else {
    response.send("/sentry/link")
  }
})

app.get("/regions/:region/(*)", async (request, response, next) => {
  let { region } = request.params;

  const REGIONS = await getRegions()

  if (!REGIONS.includes(region)) {
    response.status(404).send('Not found')
  } else if (region === FLY_REGION) {
    request.url = '/' + request.params[0]
    next()
  } else {
    response.set('Fly-Replay', `region=${region}`)
    response.status(409).send("wrong region\n")
  }
})

app.use('/logs', express.static('/logs'))
app.use('/static', express.static('./public'))

let timeout = 0;
app.get("/", async (req, res) => {
  if (req.headers['x-forwarded-port']) {
    if (timeout !== 0) clearTimeout(timeout)
    timeout = +setTimeout(() => fetchOthers("/").catch(console.error), 1000)
  }

  let filter = (req.query.filter !== 'off');

  let lastVisit = visit()

  let logs = await fs.promises.readdir(LOGS);
  logs.sort();

  let results: string[] = [];
  let previous: string[] = [];

  results.push('</pre>')

  while (logs.length > 0) {
    const log = logs.pop();
    if (!log?.endsWith('.log')) continue;

    const rl = readline.createInterface({
      input: fs.createReadStream(path.join(LOGS, log)),
      crlfDelay: Infinity
    });

    await new Promise(resolve => {
      rl.on('line', line => {
        let match = line.match(pattern)
        if (!match) return;

        if (filter && filtered(match)) return

        let log = format(match)

        if (line > lastVisit) log = highlight(log)

        results.push(log)
      });

      rl.on('close', () => {
        resolve(null)
      });
    });

    if (previous.length > 0) results.push(...previous);

    if (results.length > 40) break;

    previous = results;
    results = [ previous.shift() as string ];
  }

  results.push('<pre>')

  results.push("</p>")
  logs = await fs.promises.readdir(LOGS);
  logs.sort();
  for (const log of logs) {
    if (log.match(/^2\d\d\d-\d\d-\d\d\.log$/)) {
      results.push(`<a href=/regions/${FLY_REGION}/logs/${log}>${log.replace('.log', '')}</a>`)
    }
  }
  results.push("<p>")

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
  results.push(`<a href="https://smooth.fly.dev/">smooth.fly.dev</a> logs: ${FLY_REGION}`)
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

// update lastVisit on all machines
async function fetchOthers(path: string) {
  let dig = `dig +short -t txt vms.${appName}.internal`

  return new Promise((resolve, reject) => {
    exec(dig, async (err, stdout, stderr) => {
      if (err) {
        reject(err)
      } else {
        let machines = JSON.parse(stdout).trim().split(",")
          .map((txt: String) => txt.split(' ')[0])

        for await (let machine of machines) {
          if (machine === process.env.FLY_MACHINE_ID) continue

          await fetch(`http://${machine}.vm.${appName}.internal:3000${path}`)
            .catch(console.error)
        }

        resolve(null)
      }
    })
  })
}

app.listen(PORT, () => {
  console.log(`Listening on port ${PORT}...`)
})
