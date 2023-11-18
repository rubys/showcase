import expressWs from 'express-ws'
import { Express } from 'express'
import ws from "ws"

let wss = null as ws.Server | null

export function startWs(express: Express) {
  const { app, getWss } = expressWs(express)

  app.ws('/websocket', (ws, req) => {
    console.log('websocket connection established')

    ws.on('message', (message : string) => {
      console.log(message)
    })

    ws.on('close', () => {
      console.log('websocket connection closed')
    })
  })

  wss = getWss()
}

export function broadcast(message : any) {
  if (typeof message === 'object') message = JSON.stringify(message)
  if (wss) wss.clients.forEach(client => {
    try { client.send(message) } catch {}
  })
}
