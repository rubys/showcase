import fs from 'node:fs';
import readline from 'node:readline';
import path from 'node:path';
import express from "express";
import escape from "escape-html";
import "./deploy"
import "./logfiler"

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

app.get("/", async (req, res) => {
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

  const logs = await fs.promises.readdir(LOGS);
  logs.sort();

  let results: string[] = [];

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

  res.send(`
    <!DOCTYPE html>
    <style>
      a {color: black; text-decoration: none}
    </style>
    <pre>${results.reverse().join("\n")}</pre>
  `)
})

app.listen(PORT, () => {
  console.log(`Listening on port ${PORT}...`);
});
