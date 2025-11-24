#!/usr/bin/env node

/**
 * Hydrate normalized heat data and render a specific heat
 *
 * This script simulates what the browser does:
 * 1. Fetch /scores/:judge/heats/data (normalized data structure)
 * 2. Hydrate the data for a specific heat number using shared hydration logic
 * 3. Render using the SPA's heat template
 *
 * Usage:
 *   node scripts/hydrate_heats.mjs <judge_id> <heat_number> <style> [data_file]
 *
 * Example:
 *   node scripts/hydrate_heats.mjs 83 136 radio /tmp/heats_data.json
 */

import fs from 'fs';
import { buildHeatTemplateData } from '../app/javascript/lib/heat_hydrator.js';

// Parse command line arguments
const [,, judgeId, heatNumber, style = 'radio', dataFile] = process.argv;

if (!judgeId || !heatNumber) {
  console.error('Usage: node scripts/hydrate_heats.mjs <judge_id> <heat_number> <style> [data_file]');
  console.error('');
  console.error('Example:');
  console.error('  node scripts/hydrate_heats.mjs 83 136 radio /tmp/heats_data.json');
  process.exit(1);
}

// Load the normalized data
let allData;
try {
  const json = fs.readFileSync(dataFile || '/tmp/heats_data.json', 'utf-8');
  allData = JSON.parse(json);
} catch (err) {
  console.error(`Error loading data file: ${err.message}`);
  process.exit(1);
}

// Parse heat number
const targetHeatNumber = parseInt(heatNumber);

// Build complete template data using shared logic (same as browser uses)
try {
  const templateData = buildHeatTemplateData(targetHeatNumber, allData, style);

  // Output the complete template data
  console.log(JSON.stringify(templateData, null, 2));
} catch (err) {
  console.error(err.message);

  // Show available heats
  const availableHeats = [...new Set(allData.heats.map(h => h.number))].sort((a,b) => a-b);
  console.error(`Available heats: ${availableHeats.join(', ')}`);
  process.exit(1);
}
