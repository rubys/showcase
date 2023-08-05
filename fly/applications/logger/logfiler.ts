import { connect, StringCodec } from "nats";
import fs from 'node:fs';

fs.mkdirSync("/logs", { recursive: true });

(async () => {
  while (true) {
    try {

      // to create a connection to a nats-server:
      const nc = await connect({
        servers: "[fdaa::3]:4223",
        user: "dance-showcase",
        pass: process.env.ACCESS_TOKEN
      });

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
      for await (const m of sub) {
        const data = JSON.parse(sc.decode(m.data));

        // skip log entries from builders
        if (data.fly.app.name.match(/^fly-builder-/)) continue;

        // skip logs from THIS app
        if (data.fly.app.name === process.env.FLY_APP_NAME) continue;

        // skip static file miss log messages
        if (data.message.endsWith("\u001b[31mERROR\u001b[0m No such file or directory (os error 2)")) continue;

        // report errors to this apps's log
        let reportError: NoParamCallback = error => {
          if (error) console.error(error)
        }

        // build log file name using timestamp
        const date = data.timestamp.slice(0, 10);
        const name = `/logs/${date}.log`;

        // if log file is not already open, open it
        if (name != current.name) {
          current.name = name;
          if (current.file) fs.close(current.file, reportError);
          current.file = fs.openSync(name, 'a+');

          // Prune oldest files once we have a full week
          fs.readdir("/logs", (error, files) => {
            if (error)
              reportError(error);
            else {
              files = files.filter(file => file.startsWith('2'))
              files.sort();
              while (files.length > 8) {
                const file = files.unshift();
                fs.unlink(`/logs/${file}`, reportError)
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
        ].join(' ') + "\n";

        // write entry to disk
        fs.write(current.file, log, reportError);
        current.active = true;
      }

      console.log("log nats subscription closed");

    } catch (error) {
      console.error(error);
    }
  }
})()
