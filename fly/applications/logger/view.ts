import fs from 'node:fs'
import process from 'node:process'

import escape from "escape-html"

const { NODE_ENV, FLY_REGION, KAMAL_CONTAINER_NAME } = process.env
export const LOGS = process.env.LOGS || (NODE_ENV == 'development' ? './logs' : '/logs')
const VISITTIME = `${LOGS}/.time`
export const HOST = FLY_REGION
  ? "https://smooth.fly.dev/showcase"
  : (KAMAL_CONTAINER_NAME
      ? "https://showcase.party"
      : "https://rubix.intertwingly.net/showcase")

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
  // Don't filter password/verify paths
  if (/^(showcase\/)?password\/verify(\?|$)/.test(match[6])) return false

  if (match[6].startsWith("assets")) return true
  if (match[6].startsWith("showcase/assets")) return true
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
    } else if (status === "204") {
      status = `<a href="request/${request_id}" style="background-color: lightgreen">${status}</a>`
    } else {
      status = `<a href="request/${request_id}" style="background-color: orange">${status}</a>`
    }
  } else {
    status = `<a href="request/${request_id}">${status}</a>`
  }

  let [path, query] = match[6].split('?', 2)
  if (path.startsWith("showcase/")) path = path.slice(9)
  let link = query ? `<a href="${HOST}/${path}?${query}" title="${query}">${path}</a>` : `<a href="${HOST}/${path}">${path}</a>`
  let ip = match[2].split(',')[0]

  let regionColor = request_region && request_region[1] === match[1] ? 'green' : 'maroon'
  let title = request_region && request_region[1] !== match[1] ? ` title="${request_region[1].toUpperCase()}"` : ''

  return [
    `<time>${match[4].replace(' +0000', 'Z')}</time>`,
    `<a href="${HOST}/regions/${match[1]}/status"><span style="color: ${regionColor}"${title}>${match[1]}</span></a>`,
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

// Handle JSON formatted logs (both Rails app logs and navigator access logs)
export function formatJsonLog(jsonLog: any, flyData: any, truncate: boolean = true) {
  // Determine if this is an access log or application log based on fields
  if (jsonLog.method && jsonLog.status && jsonLog.client_ip) {
    // This is a navigator access log
    return formatAccessJsonLog(jsonLog, flyData);
  } else if (jsonLog.severity && jsonLog.message) {
    // This is a Rails application log
    return formatAppJsonLog(jsonLog, flyData, truncate);
  }

  return null; // Don't format unrecognized JSON structures
}

// Format navigator access logs in JSON format
function formatAccessJsonLog(log: any, flyData: any) {
  let status = log.status.toString();
  let request_id = (log.request_id || '').replace(/[^\w]/g, '');
  let fly_request_id = log.fly_request_id || '';
  let region_match = fly_request_id.match(/-(\w+)$/);
  let request_region = region_match ? region_match[1] : '';

  // Color code status
  if (!status.match(/^20[06]|101|30[2347]/)) {
    if (status === "499" || status == "426") {
      status = `<a href="request/${request_id}" style="background-color: gold">${status}</a>`;
    } else if (status === "204") {
      status = `<a href="request/${request_id}" style="background-color: lightgreen">${status}</a>`;
    } else {
      status = `<a href="request/${request_id}" style="background-color: orange">${status}</a>`;
    }
  } else {
    status = `<a href="request/${request_id}">${status}</a>`;
  }

  let [path, query] = (log.uri || '').split('?', 2);
  if (path.startsWith("/showcase/")) path = path.slice(10);
  else if (path.startsWith("showcase/")) path = path.slice(9);
  let link = query ? `<a href="${HOST}/${path}?${query}" title="${query}">${path}</a>` : `<a href="${HOST}/${path}">${path}</a>`;

  let ip = (log.client_ip || '').split(',')[0].trim(); // Take first IP if multiple
  let region = flyData.fly.region;
  let regionColor = request_region && request_region === region ? 'green' : 'maroon';
  let title = request_region && request_region !== region ? ` title="${request_region.toUpperCase()}"` : '';

  return [
    `<time>${log['@timestamp'].replace('Z', 'Z')}</time>`,
    `<a href="${HOST}/regions/${region}/status"><span style="color: ${regionColor}"${title}>${region}</span></a>`,
    status,
    log.request_time,
    `<span style="color: blue">${log.remote_user || '-'}</span>`,
    `<a href="https://iplocation.com/?ip=${ip}">${ip.match(/\w+[.:]+\w+$/)}</a>`,
    log.method,
    link,
  ].join(' ');
}

// Format Rails application logs in JSON format
function formatAppJsonLog(log: any, flyData: any, truncate: boolean = true) {
  let request_id = (log.request_id || '').replace(/[^\w]/g, '');
  let severity = log.severity;
  let severityColor = 'black';

  // Color code severity
  switch(severity) {
    case 'ERROR': severityColor = 'red'; break;
    case 'WARN': severityColor = 'orange'; break;
    case 'INFO': severityColor = 'blue'; break;
    case 'DEBUG': severityColor = 'gray'; break;
  }

  let region = flyData.fly.region;
  let message = escape(log.message);

  // Only truncate if requested (for live view, but not for individual request viewer)
  if (truncate && log.message.length > 200) {
    message = message.substring(0, 200) + '...';
  }

  return [
    `<time>${log['@timestamp'].replace('Z', 'Z')}</time>`,
    `<a href="${HOST}/regions/${region}/status"><span style="color: green">${region}</span></a>`,
    request_id ? `<a href="request/${request_id}">APP</a>` : 'APP',
    `<span style="color: ${severityColor}">${severity}</span>`,
    `<span style="color: #333">${message}</span>`,
  ].join(' ');
}

// Filter JSON logs (similar to traditional filtered() function)
// This is only called when filter checkbox is checked
export function filteredJsonLog(jsonLog: any) {
  // Access logs - filter assets and cable requests
  if (jsonLog.uri) {
    // Don't filter password/verify paths
    if (/^\/(showcase\/)?password\/verify(\?|$)/.test(jsonLog.uri)) return false;

    if (jsonLog.uri.includes("/assets/")) return true;
    if (jsonLog.uri.includes("/cable")) return true;
    // Filter out rubys and anonymous users (matching non-JSON behavior)
    return jsonLog.remote_user === '-' || jsonLog.remote_user === 'rubys';
  }

  return false;
}

// Check if this is a Rails application log (always filtered regardless of filter setting)
export function isRailsAppLog(jsonLog: any) {
  // Application logs have severity and message fields
  return jsonLog.severity && jsonLog.message;
}
