import { execSync } from "node:child_process"
import fs from "node:fs"

import yauzl from 'yauzl-promise'
import shapefile from 'shapefile'
import * as d3 from "d3-geo"
import * as yaml from "yaml"

let files = yaml.parse(fs.readFileSync("files.yml", "utf-8"))

const projection = d3.geoAlbersUsa()

// https://www.weather.gov/gis/USStates
// https://www.census.gov/geographies/mapping-files/time-series/geo/carto-boundary-file.html
if (!fs.existsSync(files.shapefile_zip)) {
  execSync(`wget ${files.shapefile_url}`, { stdio: "inherit" })
}

const zip = await yauzl.open(files.shapefile_zip)

let shp = null;
let dbf = null;

for await (const entry of zip) {
  if (entry.filename.endsWith('.shp')) {
    shp = await entry.openReadStream();
  }

  if (entry.filename.endsWith('.dbf')) {
    let stream = await entry.openReadStream();

    dbf = await new Promise(resolve => {
      let buffers = [];
      stream.on('readable', function (buffer) {
        for (; ;) {
          let buffer = stream.read();
          if (!buffer) { break; }
          buffers.push(buffer);
        }
      })

      stream.on('end', function () {
        resolve(Buffer.concat(buffers));
      })
    })
  }
}

function polygon(group) {
  let points = []

  for (let group2 of group) {
    let point = projection(group2)
    if (point) points.push(point.map(n => Math.round(n)))
  }

  let path = []
  let last = null
  for (let point of points) {
    if (last == null) {
      path.push(`M${point.join(",")}`)
    } else if (last[0] == point[0]) {
      if (last[1] != point[1]) {
        let length = point[1]-last[1]
        if (last && length < 0 && path.at(-1).startsWith('v-')) {
          length += parseInt(path.at(-1).slice(1))
          path[path.length-1] = `v${length}`
        } else if (last && length > 0 && path.at(-1).startsWith('v') && ! path.at(-1).startsWith('v-')) {
          length += parseInt(path.at(-1).slice(1))
          path[path.length-1] = `v${length}`
        } else {
          path.push(`v${length}`)
        }
      }
    } else if (last[1] == point[1]) {
      let length = point[0]-last[0]
      if (last && length < 0 && path.at(-1).startsWith('h-')) {
        length += parseInt(path.at(-1).slice(1))
        path[path.length-1] = `h${length}`
      } else if (last && length > 0 && path.at(-1).startsWith('h') && ! path.at(-1).startsWith('h-')) {
        length += parseInt(path.at(-1).slice(1))
        path[path.length-1] = `h${length}`
      } else {
        path.push(`h${length}`)
      }
    } else {
      path.push(`l${point[0]-last[0]},${point[1]-last[1]}`)
    }

    last = point
  }

  return path.join("")
}

let paths = []
const usmap = await shapefile.open(shp, dbf)

for (; ;) {
  let record = await usmap.read()
  if (record.done) break
  let feature = record.value
  let d = ""

  for (let group1 of feature.geometry.coordinates) {
    if (feature.geometry.type === 'MultiPolygon') {
      for (let group2 of group1) {
        d += polygon(group2)
      }
    } else {
      d += polygon(group1)
    }
  }

  if (d) {
    paths.push(`<path title="${feature.properties.NAME}" fill="#e5ecf9" stroke="#AAA" stroke-width="1" d="${d}"/>`)
  }
}

let svg = paths.join("\n")
if (fs.readFileSync(files.map_svg, "utf-8") != svg) {
  fs.writeFileSync(files.map_svg, svg)
}

let oldYaml = fs.readFileSync(files.map_yaml, "utf-8")
let map = yaml.parse(oldYaml)
let points = { ...map.regions, ...map.studios }
for (let point of Object.values(points)) {
  if (!point.lat || !point.lon) continue
  [point.x, point.y] = projection([point.lon, point.lat])
  delete point.transform
}

let newYaml = yaml.stringify(map) 
if (newYaml != oldYaml) fs.writeFileSync(files.map_yaml, newYaml)
