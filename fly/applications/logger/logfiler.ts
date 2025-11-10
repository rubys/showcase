import { connect, StringCodec } from "nats";
import fs from 'node:fs';

import { pattern, highlight, filtered, format, formatJsonLog, filteredJsonLog, isRailsAppLog, LOGS } from "./view.ts"
import { broadcast } from "./websocket.ts"
import { alert } from "./sentry.ts"

fs.mkdirSync(LOGS, { recursive: true });

(async () => {
  while (true) {
    try {

      // create a connection to a nats-server
      let nc;
      if (process.env.NATS_URL) {
        // Explicit NATS URL provided (e.g., for rubymini)
        nc = await connect({
          servers: process.env.NATS_URL,
        });
      } else if (process.env.FLY_REGION) {
        // Running on Fly.io - use internal NATS
        nc = await connect({
          servers: "[fdaa::3]:4223",
          user: "dance-showcase",
          pass: process.env.ACCESS_TOKEN
        });
      } else {
        // Running in Docker locally - use host.docker.internal
        nc = await connect({
          servers: "host.docker.internal:4222",
        });
      }

      // keep track of current log file
      let current = {
        name: "",
        file: 0,
        active: false
      }

      // flush file every second
      setInterval(() => {
        if (current.active) {
          fs.fsyncSync(current.file);
          current.active = false;
        }
      }, 1000);

      // create a codec
      const sc = StringCodec();

      // create a simple subscriber and iterate over messages
      // matching the subscription
      const sub = nc.subscribe("logs.>");

      const FLY_REGION = process.env.FLY_REGION;
      const HOSTNAME = process.env.HOSTNAME || 'unknown';

      for await (const m of sub) {
        let data: any;
        if (!m.data) continue;
        let message = sc.decode(m.data);
        if (!message) continue;

        try {
          data = JSON.parse(message);
        } catch (error) {
          console.error(`logfiler error: ${error}`);
          console.error(`logfiler message: ${message}`);
          continue;
        }

        if (FLY_REGION) {
          // skip log entries from builders
          if (data.fly.app.name.match(/^fly-builder-/)) continue;

          // skip staging app
          if (data.fly.app.name == "smooth-nav") continue;

          // skip logs from THIS app
          if (data.fly.app.name === process.env.FLY_APP_NAME) continue;

          // skip static file miss log messages
          if (data.message.endsWith("\u001b[31mERROR\u001b[0m No such file or directory (os error 2)")) continue;
        } else {
          if (data.label?.service == "showcase-logger") continue;

          data.fly = {
            app: {
              name: data.label?.service || "showcase",
              instance: (data.container_id || HOSTNAME).slice(-12)
            },
            region: "hel"
          }

          data.log = {
            level: data.stream
          }
        }

        // report errors to this apps's log
        let reportError: (error: NodeJS.ErrnoException | null) => void = error => {
          if (error) console.error(error)
        }

        // build log file name using timestamp
        const date = data.timestamp.slice(0, 10);
        const name = `${LOGS}/${date}.log`;

        // if log file is not already open, open it
        if (name != current.name) {
          current.name = name;
          if (current.file) fs.close(current.file, reportError);
          current.file = fs.openSync(name, 'a+');

          // Prune oldest files once we have a full week
          fs.readdir(LOGS, (error, files) => {
            if (error)
              reportError(error);
            else {
              files = files.filter(file => file.startsWith('2'))
              files.sort();
              while (files.length > 8) {
                const file = files.shift();
                fs.unlink(`${LOGS}/${file}`, reportError);
              }
            }
          })
        }

        // build log file entry
        const log = [
          data.timestamp.padEnd(30),
          `[${data.fly.app.instance}]`,
          data.fly.region,
          `[${data.log.level}]`,
          data.message
        ].join(' ')

        // write entry to disk
        fs.write(current.file, log + "\n", reportError);
        current.active = true;

        // Try to parse the message as JSON first
        let jsonLog = null;
        try {
          // Check if the message starts with JSON
          if (data.message.trim().startsWith('{')) {
            jsonLog = JSON.parse(data.message.trim());
          }
        } catch (e) {
          // Not JSON, continue with traditional parsing
        }

        if (jsonLog) {
          // Handle JSON formatted logs
          let formattedJson = formatJsonLog(jsonLog, data);
          if (formattedJson && !isRailsAppLog(jsonLog)) {
            // For broadcast, we send the filtered flag to let client decide
            broadcast(highlight(formattedJson), filteredJsonLog(jsonLog));
          }
        } else {
          // Handle traditional log format
          let match = log.match(pattern)
          if (match) broadcast(highlight(format(match)), filtered(match))
        }
      }

      console.log("log nats subscription closed");

    } catch (error: any) {
      let message = "message" in error ? error.message : error.toString();
      alert(`logfiler error: ${message}`);
      console.error(error);
      process.exit(1);
    }
  }
})()
