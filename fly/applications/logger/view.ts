import fs from 'node:fs'
import process from 'node:process'

import escape from "escape-html"

const { NODE_ENV, FLY_REGION } = process.env
export const LOGS = NODE_ENV == 'development' ? './logs' : '/logs'
const VISITTIME = `${LOGS}/.time`
export const HOST = FLY_REGION ? "https://smooth.fly.dev/showcase" : "https://showcase.party"

// lines to be selected to be send to the browser
export const pattern = new RegExp([
  /^\S+\s+\[.*?\] (\w+) /,           // timestamp, machine, region (#1)
  /\[\w+\] /,                        // log level
  /[\d:]+ web\.1\s* \| /,            // time, procfile source
  /([\d:a-fA-F, .]+) /,              // ip addresses (#2)
  /- (-|\w+) /,                      // - user (#3)
  /\[([\w\/: +-]+)\] /,              // time (#4)
  /"(\w+) \/(\S*) (.*?)" /,          // method (#5), url (#6), protocol (#7)
  /(\d+) (\d+) /,                    // status (#8), length (#9)
  /\[(\w+)\] /,                      // request id (#10)
  /([.\d]+)?/,                       // request time (#11)
  /(.*$)/,                           // rest (#12)
].map(r => r.source).join(''))

// identify which lines are to be filtered
export function filtered(match: RegExpMatchArray) {
  return match[3] === '-' || match[3] === 'rubys' || match[6].endsWith('/cable')
}

// formatted log entry
export function format(match: RegExpMatchArray) {
  let status = match[8];
  let request_id = (match[10] || '').replace(/[^\w]/g, '')
  let request_region = match[12].match(/" - \w+-(\w+)$/)
  if (!status.match(/^20[06]|101|30[2347]/)) {
    if (status === "499" || status == "426") {
      status = `<a href="request/${request_id}" style="background-color: gold">${status}</a>`
    } else {
      status = `<a href="request/${request_id}" style="background-color: orange">${status}</a>`
    }
  } else {
    status = `<a href="request/${request_id}">${status}</a>`
  }

  let path = match[6]
  if (path.startsWith("showcase/")) path = path.slice(9)
  let link = `<a href="${HOST}/${path}">${path}</a>`
  let ip = match[2].split(',')[0]

  let regionColor = request_region && request_region[1] === match[1] ? 'green' : 'maroon'

  return [
    `<time>${match[4].replace(' +0000', 'Z')}</time>`,
    `<a href="${HOST}/regions/${match[1]}/status"><span style="color: ${regionColor}">${match[1]}</span></a>`,
    status,
    match[11],
    `<span style="color: blue">${match[3]}</span>`,
    `<a href="https://iplocation.com/?ip=${ip}">${ip.match(/\w+[.:]+\w+$/)}</a>`,
    match[5],
    link,
  ].join(' ')
}

// indicate that a line is new by setting the background color
export function highlight(log: string) {
  return `<span style="background-color: yellow">${log}</span>`
}

export function visit() {
  let lastVisit = "0"

  try {
    lastVisit = fs.statSync(VISITTIME).mtime.toISOString()
  } catch (e) {
    if (!(e instanceof Error && 'code' in e) || e.code != 'ENOENT') throw e;
    fs.closeSync(fs.openSync(VISITTIME, 'a'))
  }

  let time = new Date();
  fs.utimes(VISITTIME, time, time, error => {
    if (error) console.error(error)
  })

  return lastVisit
}
