import fs from 'node:fs'

import escape from "escape-html"

export const LOGS = '/logs'
const VISITTIME = `${LOGS}/.time`
const HOST = "https://smooth.fly.dev"

// lines to be selected to be send to the browser
export const pattern = new RegExp([
  /(\w+) /,                          // region (#1)
  /\[\w+\] /,                        // log level
  /[\d:]+ web\.1\s* \| /,            // time, procfile source
  /([\d:a-fA-F, .]+) /,              // ip addresses (#2)
  /- (-|\w+) /,                      // - user (#3)
  /\[([\w\/: +-]+)\] /,              // time (#4)
  /"(\w+) (\/showcase\S*) (.*?)" /,  // method (#5), url (#6), protocol (#7)
  /(\d+) (\d+.*$)/,                  // status (#8), length, rest (#9)
].map(r => r.source).join(''))

// identify which lines are to be filtered
export function filtered(match: RegExpMatchArray) {
  return match[3] === '-' || match[3] === 'rubys'
}

// formatted log entry
export function format(match: RegExpMatchArray) {
  let status = match[8];
  if (!status.match(/200|101|30[234]/)) {
    status = `<span style="background-color: orange">${status}</span>`
  }

  let link = `<a href="${HOST}${match[6]}">${match[6]}</a>`;

  return [
    `<time>${match[4].replace(' +0000', 'Z')}</time>`,
    `<a href="https://smooth.fly.dev/showcase/regions/${match[1]}/status"><span style="color: maroon">${match[1]}</span></a>`,
    status,
    match[2].split(',')[0],
    `<span style="color: blue">${match[3]}</span>`,
    `"${match[5]} ${link} ${match[7]}"`,
    escape(match[9])
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