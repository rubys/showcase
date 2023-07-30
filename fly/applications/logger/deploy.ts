#!/usr/bin/env node

import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const env = { ...process.env }

// allocate swap space
await exec('fallocate -l 1G /swapfile')
await exec('chmod 0600 /swapfile')
await exec('mkswap /swapfile')
writeFileSync('/proc/sys/vm/swappiness', '10')
await exec('swapon /swapfile')
writeFileSync('/proc/sys/vm/overcommit_memory', '1')

// run command and throw on error
function exec(command: string) {
  const child = spawn(command, { shell: true, stdio: 'inherit', env })
  return new Promise((resolve, reject) => {
    child.on('exit', code => {
      if (code === 0) {
        resolve(null)
      } else {
        reject(new Error(`${command} failed rc=${code}`))
      }
    })
  })
}
