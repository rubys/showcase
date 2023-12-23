import { spawn } from 'node:child_process'
import fs from 'node:fs'
import process from "node:process"

const HOME = "/home/log"
const VOLUME = '/logs'
const env = { ...process.env }

// create log user for ssh
if (!fs.existsSync("/home/log")) {
  await exec("useradd log --create-home --shell /bin/bash")
    .catch(console.error)
  await exec("passwd -d log")
    .catch(console.error)
}
let { uid, gid } = fs.statSync(HOME) 

// allocate swap space
if (!fs.existsSync("/swapfile")) {
  await exec('fallocate -l 1G /swapfile')
  await exec('chmod 0600 /swapfile')
  await exec('mkswap /swapfile')
  fs.writeFileSync('/proc/sys/vm/swappiness', '10')
  await exec('swapon /swapfile')
  fs.writeFileSync('/proc/sys/vm/overcommit_memory', '1')
}

// openssh: fly environment variables
fs.writeFileSync(
  "/etc/environment",
  Object.entries(process.env)
    .filter(([key, _]) => /^FLY_*|PRIMARY_REGION/m.test(key))
    .map(([key, value]) => (`${key}=${value}\n`)).join('')
)

// openssh: install authorized key and host keys
const CWD = process.cwd()
fs.mkdirSync(`${VOLUME}/.ssh`, { recursive: true })
try {
  process.chdir(`${VOLUME}/.ssh`)

  // install authorized keys
  if (fs.existsSync("authorized_keys")) {
    if (!fs.existsSync(`${HOME}/.ssh`)) {
      fs.mkdirSync(`${HOME}/.ssh`, { recursive: true })
      fs.chmodSync(`${HOME}/.ssh`, 0o700)
      fs.chownSync(`${HOME}/.ssh`, uid, gid)
    }

    if (!fs.existsSync(`${HOME}/.ssh/authorized_keys`)) {
      copyFileSync("authorized_keys", `${HOME}/.ssh/authorized_keys`)
      fs.chownSync(`${HOME}/.ssh/authorized_keys`, uid, gid)
    }
  }

  // ensure host keys remain stable
  const host_keys = fs.readdirSync('.')
    .filter(name => name.match(/^ssh_host_.*_key/))

  if (host_keys.length == 0) {
    // save keys on volume
    for (const key of fs.readdirSync('/etc/ssh')) {
      if (key.match(/^ssh_host_.*_key/)) {
        copyFileSync(`/etc/ssh/${key}`, key)
      }
    }
  } else {
    // restore keys from volume
    for (const key of host_keys) {
      copyFileSync(key, `/etc/ssh/${key}`)
    }
  }
} finally {
  process.chdir(CWD)
}

// configure sshd
let sshdConfig = fs.readFileSync('/etc/ssh/sshd_config', 'utf-8')
  .replace(/^#\s*Port.*/m, 'Port 2222')
  .replace(/^#\s*PasswordAuthentication.*/m, 'PasswordAuthentication no')
fs.writeFileSync('/etc/ssh/sshd_config', sshdConfig)
fs.mkdirSync(`/var/run/sshd`, { recursive: true })
fs.chmodSync(`/var/run/sshd`, 0o755)

// spawn sshd
exec("/usr/sbin/sshd -D")
  .finally(() => process.exit(1))

// spawn web and logfiler
exec("bun server.ts")
  .finally(() => process.exit(1))

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

// copy file across volumes (avoids "EXDEV: Cross-device link")
function copyFileSync(source: string, dest: string) {
  fs.writeFileSync(dest, fs.readFileSync(source, "utf-8"))
}
