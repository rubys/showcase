import * as Sentry from '@sentry/node'

Sentry.init()

export function alert(message: string) {
  Sentry.captureMessage(message)
}