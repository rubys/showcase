// Check for failed machines every 60 minutes and attempt to restart them.
// Alerts are sent to Sentry when a restart is attempted or fails.

import { alert } from "./sentry.ts"

const APP_NAME = "smooth"
const API_BASE = `http://_api.internal:4280/v1/apps/${APP_NAME}/machines`

function headers() {
  return {
    "Authorization": `Bearer ${process.env.ACCESS_TOKEN}`,
    "Content-Type": "application/json"
  }
}

async function monitor() {
  if (!process.env.FLY_REGION) return

  try {
    // list all machines
    const response = await fetch(API_BASE, { headers: headers() })
    if (!response.ok) {
      alert(`monitor: failed to list machines: ${response.status} ${response.statusText}`)
      return
    }

    const machines: any[] = await response.json()
    const failed = machines.filter((m: any) => m.state === "failed")

    for (const machine of failed) {
      const label = `${machine.name || machine.id} (${machine.region})`
      console.log(`monitor: attempting to restart failed machine ${label}`)

      try {
        const startResponse = await fetch(`${API_BASE}/${machine.id}/start`, {
          method: "POST",
          headers: headers()
        })

        if (startResponse.ok) {
          alert(`monitor: restarted failed machine ${label}`)
        } else {
          const body = await startResponse.text()
          alert(`monitor: failed to restart ${label}: ${startResponse.status} ${body}`)
        }
      } catch (error: any) {
        alert(`monitor: error restarting ${label}: ${error.message}`)
      }
    }
  } catch (error: any) {
    alert(`monitor: error checking machines: ${error.message}`)
  }
}

setInterval(monitor, 60 * 60 * 1000)
