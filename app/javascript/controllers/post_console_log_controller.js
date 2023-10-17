import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="post-console-log"
export default class extends Controller {
  connect() {
  }
}

function postLog(log) {
  log.location = window.location.href;

  fetch("/showcase/events/console", {
    method: "POST",
    body: JSON.stringify(log)
  });
}

function TS(){
  return (new Date).toLocaleString("sv", { timeZone: "UTC" }) + "Z";
}
window.onerror = function (error, url, line) {
  postLog({
    type: "exception",
    timeStamp: TS(),
    value: {
      error: error.toString(),
      stack: (error.stack || "").toString().trim().split("\n"),
      url: url.toString(),
      line: line.toString()
    }
  });

  return false;
};
window.onunhandledrejection = function (e) {
  postLog({
    type: "promiseRejection",
    timeStamp: TS(),
    value: e.reason
  });
}; 

function hookLogType(logType) {
  const original= console[logType].bind(console);
  return function(){
    postLog({ 
      type: logType, 
      timeStamp: TS(), 
      value: Array.from(arguments).map(arg => arg.toString())
    });
    original.apply(console, arguments);
  };
}

["log", "error", "warn", "debug"].forEach(logType=>{
  console[logType] = hookLogType(logType);
});
