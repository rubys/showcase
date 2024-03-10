#!/usr/bin/env bun
import { execSync } from 'child_process'
import { dirname } from 'path'
import { chdir } from 'process'

chdir(dirname(import.meta.dirname))

execSync(
  'rsync -avz --delete --exclude=lost+found --exclude=.ssh log.smooth:/logs .',
  { stdio: 'inherit' }
)