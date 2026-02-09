// Check for failed/stuck machines every 60 minutes and take action.
// Failed machines are restarted. Machines stuck in replacing state
// (with no evidence of being started in the last 15 minutes) trigger alerts.

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

    for (const machine of machines) {
      const label = `${machine.name || machine.id} (${machine.region})`

      if (machine.state === "failed") {
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
      } else if (machine.state === "replacing") {
        await checkStuckReplacing(machine, label)
      }
    }
  } catch (error: any) {
    alert(`monitor: error checking machines: ${error.message}`)
  }
}

async function checkStuckReplacing(machine: any, label: string) {
  try {
    // fetch full machine details including events
    const response = await fetch(`${API_BASE}/${machine.id}`, { headers: headers() })
    if (!response.ok) return

    const details = await response.json()
    const events: any[] = details.events || []
    const fifteenMinutesAgo = Date.now() - 15 * 60_000

    // look for any evidence the machine was started recently
    const recentlyStarted = events.some((e: any) =>
      e.status === "started" && e.timestamp > fifteenMinutesAgo
    )

    if (!recentlyStarted) {
      alert(`monitor: machine ${label} stuck in replacing state`)
    }
  } catch (error: any) {
    alert(`monitor: error checking replacing machine ${label}: ${error.message}`)
  }
}

setInterval(monitor, 60 * 60 * 1000)
