#!/usr/bin/env bun

import { Glob } from "bun"
import { basename } from "node:path"

import { Database } from "bun:sqlite"

import { exec } from 'node:child_process'
import { promisify } from 'node:util'

const execPromise = promisify(exec)

// scan databases

let attachments = {}

for await (const file of (Glob("20*.sqlite3")).scan("db")) {
  const db = new Database(`db/${file}`)
  const event = file.split(".")[0]
  
  let results = []

  try {
    const query = db.query(`
      SELECT name, record_type, record_id, key FROM active_storage_attachments 
      LEFT JOIN active_storage_blobs ON
      active_storage_blobs.id = active_storage_attachments.blob_id`)

    results = query.all()
  } catch {
  }

  for (const result of results) {
    result.event = event
    const { key } = result
    delete result.key
    attachments[key] = result
  }
}

// scan files

const files = new Set()
for await (const file of (Glob("*/*/*")).scan("storage")) {
  files.add(basename(file))
}

// scan tigris
const { stdout } = await execPromise("rclone lsf showcase:showcase --files-only --max-depth 1")
const tigris = new Set(stdout.split("\n").filter(Boolean))

const database = new Set(Object.keys(attachments))

console.log("Files in storage but not in database:")
console.log(files.difference(database).size)

console.log("Files in database but not in storage:")
for (const file of database.difference(files)) {
  console.log(file, attachments[file])
}

console.log("files in tigris but not in storage:")
console.log(tigris.difference(files).size)

console.log("files in storage but not in tigris:")
console.log(files.difference(tigris).size)

console.log("files in tigris but not in database:")
console.log(tigris.difference(database).size)

console.log("files in database but not in tigris:")
for (const file of database.difference(tigris)) {
  console.log(file, attachments[file])
}