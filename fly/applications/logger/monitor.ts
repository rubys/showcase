// Check for failed/stuck/silent machines every 60 minutes and take action.
// Failed machines are restarted. Machines stuck in replacing state
// (with no evidence of being started in the last 15 minutes) trigger alerts.
// Started machines that have gone silent (no log output for 20 minutes)
// are restarted.

import { alert } from "./sentry.ts"
import { lastSeen, logfilerStarted } from "./logfiler.ts"

const APP_NAME = "smooth"
const API_BASE = `http://_api.internal:4280/v1/apps/${APP_NAME}/machines`
const SILENCE_THRESHOLD = 20 * 60_000 // 20 minutes

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
      } else if (machine.state === "started") {
        await checkSilentStarted(machine, label)
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

async function checkSilentStarted(machine: any, label: string) {
  // only check once logfiler has been running long enough to establish baselines
  if (Date.now() - logfilerStarted < SILENCE_THRESHOLD) return

  const lastTime = lastSeen.get(machine.id)
  if (lastTime === undefined) return
  if (Date.now() - lastTime < SILENCE_THRESHOLD) return

  const silentMinutes = Math.round((Date.now() - lastTime) / 60_000)
  console.log(`monitor: machine ${label} started but silent for ${silentMinutes} minutes, attempting restart`)

  try {
    const restartResponse = await fetch(`${API_BASE}/${machine.id}/restart`, {
      method: "POST",
      headers: headers()
    })

    if (restartResponse.ok) {
      lastSeen.set(machine.id, Date.now())
      alert(`monitor: restarted silent machine ${label} (silent for ${silentMinutes} min)`)
    } else {
      const body = await restartResponse.text()
      alert(`monitor: failed to restart silent ${label}: ${restartResponse.status} ${body}`)
    }
  } catch (error: any) {
    alert(`monitor: error restarting silent ${label}: ${error.message}`)
  }
}

setInterval(monitor, 60 * 60 * 1000)
