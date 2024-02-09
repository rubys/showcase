// Check for heartbeat logs from all vms every 60 minutes
// Messages are sent to Sentry if a heartbeat is not found

import { promises as dns } from 'node:dns'
import fs from 'node:fs'
import readline from 'node:readline'
import path from 'node:path'

import * as Sentry from '@sentry/node'

import { LOGS } from "./view.ts"

// get the list of vms from for the smooth application
async function vms() {
  return (await dns.resolveTxt('vms.smooth.internal')).
    map(lines => lines.join('')).join('').split(',')
}

let previous_vms = await vms()

Sentry.init()

async function monitor() {
  // only look for vms that are active and were present in the previous check
  const current_vms = await vms()

  let seeking = new Set()

  for (const vm of previous_vms) {
    if (current_vms.includes(vm)) {
      seeking.add(vm)
    }
  }

  // pattern to match heartbeat logs
  const pattern = new RegExp([
    /^\S+\s+\[.*?\] \w+ /,             // timestamp machine region
    /\[\w+\] /,                        // log level
    /[\d:]+ heartbeat\.1\s* \| /,      // time, procfile source
    /HEARTBEAT (\w+ \w+)/              // vm (#1)
  ].map(r => r.source).join(''))

  // only look for logs from the last hour
  let since = new Date((new Date()).getTime() - 60 * 60_000).toISOString()

  let logs = await fs.promises.readdir(LOGS)
  for (let log of logs) {
    if (!log.endsWith('.log')) continue
    if (log < since.slice(0, 10)) continue

    const rl = readline.createInterface({
      input: fs.createReadStream(path.join(LOGS, log)),
      crlfDelay: Infinity
    });

    // remove vms that have produced a heartbeat log
    await new Promise(resolve => {
      rl.on('line', line => {
        if (line < since) return
        let match = line.match(pattern)
        if (!match) return

        seeking.delete(match[1])
      });

      rl.on('close', () => {
        resolve(null)
      });
    });
  }

  // send a message to Sentry listing vms that did not produce a heartbeat log
  if (seeking.size) {
    Sentry.captureMessage(`heatbeat not found for ${[...seeking].join(', ')}`)
  }

  // update the list of vms for the next check
  previous_vms = current_vms
}

setInterval(monitor, 60 * 60 * 1000)
