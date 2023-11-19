import expressWs from 'express-ws'
import { Express } from 'express'
import ws from "ws"

import { visit } from './view.ts'

let wss = null as ws.Server | null

const FLY_REGION = process.env.FLY_REGION;

export function startWs(express: Express) {
  const { app, getWss } = expressWs(express)

  function websocket(ws: ws) {
    console.log('websocket connection established')

    ws.on('message', (message : string) => {
      console.log(message)
    })

    ws.on('close', () => {
      console.log('websocket connection closed')
    })
  }

  app.ws(`/regions/${FLY_REGION}/websocket`, websocket)
  app.ws('/websocket', websocket)

  wss = getWss()
}

export function broadcast(message : string, filtered: boolean) {
  if (!wss || wss.clients.size == 0) return

  setTimeout(visit, 1000)

  wss.clients.forEach(client => {
    try { client.send(JSON.stringify({ message, filtered})) } catch {}
  })
}
