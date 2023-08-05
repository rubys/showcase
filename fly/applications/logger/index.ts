import fs from 'node:fs';
import { exec } from "node:child_process"
import readline from 'node:readline';
import path from 'node:path';
import express from "express";
import escape from "escape-html";

const PORT = 3000;
const HOST = "https://smooth.fly.dev"
const LOGS = '/logs';
const VISITTIME = `${LOGS}/.time`

const pattern = new RegExp([
  /(\w+) /,                          // region (#1)
  /\[\w+\] /,                        // log level
  /[\d:]+ web\.1\s* \| /,            // time, procfile source
  /([\d:a-fA-F, .]+) /,              // ip addresses (#2)
  /- (-|\w+) /,                      // - user (#3)
  /\[([\w\/: +-]+)\] /,              // time (#4)
  /"(\w+) (\/showcase\S*) (.*?)" /,  // method (#5), url (#6), protocol (#7)
  /(\d+) (\d+.*$)/,                  // status (#8), length, rest (#9)
].map(r => r.source).join(''))

const app = express();

const appName = process.env.FLY_APP_NAME;

const FLY_REGION = process.env.FLY_REGION;

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

app.get("/regions/:region/(*)", async (request, response, next) => {
  let { region } = request.params;

  const REGIONS = await getRegions()

  if (!REGIONS.includes(region)) {
    response.status(404).send('Not found')
  } else if (region === FLY_REGION) {
    if (request.params[0] === '') request.url = '/'
    next()
  } else {
    response.set('Fly-Replay', `region=${region}`)
    response.status(409).send("wrong region\n")
  }
})

app.use(`/regions/${FLY_REGION}/logs`, express.static('/logs'))

let timeout = 0;
app.get("/", async (req, res) => {
  if (req.headers['x-forwarded-port']) {
    if (timeout !== 0) clearTimeout(timeout)
    timeout = +setTimeout(() => fetchOthers().catch(console.error), 1000)
  }

  let lastVisit = "0";
  try {
    lastVisit = fs.statSync(VISITTIME).mtime.toISOString()
  } catch (e) {
    if (!(e instanceof Error && 'code' in e) || e.code != 'ENOENT') throw e;
    fs.closeSync(fs.openSync(VISITTIME, 'a'));
  }

  let time = new Date();
  fs.utimes(VISITTIME, time, time, error => {
    if (error) console.error(error)
  })

  let logs = await fs.promises.readdir(LOGS);
  logs.sort();

  let results: string[] = [];

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

        let status = match[8];
        if (status === '409') return;
        if (!status.match(/200|101|30[234]/)) {
          status = `<span style="background-color: orange">${status}</span>`
        }

        let link = `<a href="${HOST}${match[6]}">${match[6]}</a>`;

        let log = [
          match[4].replace(' +0000', 'Z'),
          `<span style="color: maroon">${match[1]}</span>`,
          status,
          match[2].split(',')[0],
          `<span style="color: blue">${match[3]}</span>`,
          `"${match[5]} ${link} ${match[7]}"`,
          escape(match[9])
        ].join(' ');

        if (line > lastVisit) {
          log = `<span style="background-color: yellow">${log}</span>`
        }

        results.push(log);
      });

      rl.on('close', () => {
        resolve(null);
      });
    });

    if (results.length > 0) break;
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
  for (const region of REGIONS) {
    if (region != FLY_REGION) {
      results.push(`<a href="/regions/${region}/">${region}</a>`)
    }
  }
  results.push(`<small style="font-weight: normal">`)
  results.push(`smooth.fly.dev logs: ${FLY_REGION}`)
  results.push(`<h2>`)

  res.send(`
    <!DOCTYPE html>
    <style>
      a {color: black; text-decoration: none}
    </style>
    ${results.reverse().join("\n")}
  `)
})

// update lastVisit on all machines
async function fetchOthers() {
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

          await fetch(`http://${machine}.vm.${appName}.internal:3000/`)
            .catch(console.error)
        }

        resolve(null)
      }
    })
  })
}

app.listen(PORT, () => {
  console.log(`Listening on port ${PORT}...`);
});
