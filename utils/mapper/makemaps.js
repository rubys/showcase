import { execSync } from "node:child_process"
import fs from "node:fs"

import yauzl from 'yauzl-promise'
import shapefile from 'shapefile'
import * as d3 from "d3-geo"
import * as yaml from "yaml"

// Custom Albers USA projection that includes Edmonton
const createExtendedUSProjection = () => {
  const albersUsa = d3.geoAlbersUsa();
  const albers = d3.geoAlbers()
    .parallels([29.5, 45.5])
    .rotate([96, 0])
    .center([-0.6, 38.7])
    .scale(1070);
  
  return (coordinates) => {
    // Try standard Albers USA first
    const result = albersUsa(coordinates);
    if (result) return result;
    
    // For points outside standard projection (like Edmonton), use custom Albers
    const [lon, lat] = coordinates;
    if (lat > 49 && lat < 55 && lon > -120 && lon < -110) {
      // Custom projection for Alberta region
      const customResult = albers(coordinates);
      if (customResult) {
        // Adjust to fit with the US map
        return [customResult[0] - 50, customResult[1] + 40];
      }
    }
    
    return null;
  };
};

const PROJECTIONS = {
  us: createExtendedUSProjection(),
  eu: d3.geoConicConformal().rotate([-20, 0]).center([0, 52])
    .parallels([35.0, 65.0]).scale(1000),
  au: d3.geoConicConformal().rotate([-132, 0]).center([13, -25])
    .parallels([-18, -36]).scale(750),
  jp: d3.geoConicEquidistant().rotate([-137, 0]).center([0, 36])
    .parallels([24, 46]).scale(1000),
}

process.chdir(new URL('.', import.meta.url).pathname)

let allfiles = yaml.parse(fs.readFileSync('files.yml', "utf-8"))

let oldYaml = fs.readFileSync(allfiles.files.map_yaml, "utf-8")
let map = yaml.parse(oldYaml)
let points = { ...map.regions, ...map.studios }

for (let files of allfiles.maps) {
  console.log(`Making map for ${files.projection}...`)
  let [width, height] = files.projection == 'us' ? [900, 500] : [600, 500]

  const projection = PROJECTIONS[files.projection]

  // https://www.weather.gov/gis/USStates
  // https://www.census.gov/geographies/mapping-files/time-series/geo/carto-boundary-file.html
  if (!fs.existsSync(files.shapefile_zip)) {
    execSync(`wget ${files.shapefile_url}`, { stdio: "inherit" })
  }

  const zip = await yauzl.open(files.shapefile_zip)

  let shp = null;
  let dbf = null;

  for await (const entry of zip) {
    if (files.select && !entry.filename.startsWith(files.select)) continue
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
      if (!point) continue
      if (point[0] < 0 || point[1] < 0) continue
      if (point[0] > width || point[1] > height) continue
      if (point) points.push(point.map(n => Math.round(n)))
    }

    let path = []
    let last = null
    for (let point of points) {
      if (last == null) {
        path.push(`M${point.join(",")}`)
      } else if (last[0] == point[0]) {
        if (last[1] != point[1]) {
          let length = point[1] - last[1]
          if (last && length < 0 && path.at(-1).startsWith('v-')) {
            length += parseInt(path.at(-1).slice(1))
            path[path.length - 1] = `v${length}`
          } else if (last && length > 0 && path.at(-1).startsWith('v') && !path.at(-1).startsWith('v-')) {
            length += parseInt(path.at(-1).slice(1))
            path[path.length - 1] = `v${length}`
          } else {
            path.push(`v${length}`)
          }
        }
      } else if (last[1] == point[1]) {
        let length = point[0] - last[0]
        if (last && length < 0 && path.at(-1).startsWith('h-')) {
          length += parseInt(path.at(-1).slice(1))
          path[path.length - 1] = `h${length}`
        } else if (last && length > 0 && path.at(-1).startsWith('h') && !path.at(-1).startsWith('h-')) {
          length += parseInt(path.at(-1).slice(1))
          path[path.length - 1] = `h${length}`
        } else {
          path.push(`h${length}`)
        }
      } else {
        path.push(`l${point[0] - last[0]},${point[1] - last[1]}`)
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

    if (!feature.geometry) continue
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
      const name = feature.properties.NAME || feature.properties.STE_NAME21 || feature.properties.ADM0_EN
      paths.push(`<path title="${name.replace(/\0/g, '')}" fill="#e5ecf9" stroke="#AAA" stroke-width="1" d="${d}"/>`)
    }
  }

  let svg = paths.join("\n")

  // Generate circles - regions first (larger, yellow), then studios (smaller, blue)
  // This way studios overlay regions when they're in the same location
  let circles = []

  // Generate region circles for this map (rendered first, underneath)
  for (let [token, point] of Object.entries(map.regions || {})) {
    if (!point.lat || !point.lon) continue
    if (point.lat < files.min_lat || point.lat > files.max_lat) continue
    if (point.lon < files.min_lon || point.lon > files.max_lon) continue

    let dot = projection([point.lon, point.lat])
    if (dot) {
      let [x, y] = dot.map(n => Math.round(n))
      // Store coordinates in map data for reference
      point.map = files.projection
      point.x = x
      point.y = y
      delete point.transform

      // Generate region circle with ERB link (only show if region is deployed)
      const name = point.name || token
      circles.push(`<% if @regions && @regions['${token}'] %>
<a xlink:title="${name}" href="<%= region_path('${token}') %>" class="region-marker">
  <circle cx="${x}" cy="${y}" r="16" fill="#ffd700" stroke="#ffffff" style="cursor: pointer;" stroke-width="1" opacity="0.8"/>
</a>
<% end %>`)
    }
  }

  // Generate studio circles for this map (rendered last, on top)
  for (let [token, point] of Object.entries(map.studios || {})) {
    if (!point.lat || !point.lon) continue
    if (point.lat < files.min_lat || point.lat > files.max_lat) continue
    if (point.lon < files.min_lon || point.lon > files.max_lon) continue

    let dot = projection([point.lon, point.lat])
    if (dot) {
      let [x, y] = dot.map(n => Math.round(n))
      // Store coordinates in map data for reference
      point.map = files.projection
      point.x = x
      point.y = y
      delete point.transform

      // Generate circle with ERB link
      const name = point.name || token
      circles.push(`<a xlink:title="${name}" href="<%= studio_path('${token}') %>">
  <circle cx="${x}" cy="${y}" r="8" fill="#000080" stroke="#ffffff" style="cursor: pointer;" stroke-width="1"/>
</a>`)
    }
  }

  // Combine paths and circles
  let fullSvg = svg
  if (circles.length > 0) {
    fullSvg += "\n" + circles.join("\n")
  }

  if (!fs.existsSync(files.map_svg) || fs.readFileSync(files.map_svg, "utf-8") != fullSvg) {
    fs.writeFileSync(files.map_svg, fullSvg)
  }
}

let newYaml = yaml.stringify(map)
if (newYaml != oldYaml) fs.writeFileSync(allfiles.files.map_yaml, newYaml)
