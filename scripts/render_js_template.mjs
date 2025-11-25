#!/usr/bin/env node

/**
 * Script to render JavaScript-converted ERB templates with actual data
 *
 * Usage:
 *   node scripts/render_js_template.mjs <judge_id> <heat_number> [style]
 *
 * Example:
 *   node scripts/render_js_template.mjs 83 123 radio
 *
 * This script:
 * 1. Fetches the converted JavaScript templates from /templates/scoring.js
 * 2. Fetches the heat data JSON from /scores/:judge/heats/:heat
 * 3. Executes the appropriate template function with the data
 * 4. Outputs the rendered HTML
 */

import http from 'http';

const BASE_URL = 'http://localhost:3000';

// Parse command line arguments
const [judgeId, heatNumber, style = 'radio'] = process.argv.slice(2);

if (!judgeId || !heatNumber) {
  console.error('Usage: node scripts/render_js_template.mjs <judge_id> <heat_number> [style]');
  console.error('Example: node scripts/render_js_template.mjs 83 123 radio');
  process.exit(1);
}

/**
 * Fetch URL content via HTTP
 */
function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        } else {
          resolve(data);
        }
      });
    }).on('error', reject);
  });
}

/**
 * Load and evaluate the converted JavaScript templates
 */
async function loadTemplates() {
  const url = `${BASE_URL}/templates/scoring.js`;
  console.error(`Fetching templates from ${url}...`);

  const jsCode = await fetchUrl(url);

  // Helper function for domId (used by templates)
  function domId(object) {
    if (typeof object === 'object' && object.id) {
      return `heat_${object.id}`;
    }
    return String(object);
  }

  // Strip 'export ' keywords to convert ES modules to regular functions
  const regularCode = jsCode.replace(/^export /gm, '');

  // Wrap the code to capture the functions
  const wrappedCode = `
    ${regularCode}
    return { soloHeat, rankHeat, tableHeat, cardsHeat };
  `;

  // Evaluate the code with domId in scope
  const templateFn = new Function('domId', wrappedCode);
  const templates = templateFn(domId);

  console.error('Templates loaded successfully');
  return templates;
}

/**
 * Fetch heat data JSON
 */
async function loadHeatData(judgeId, heatNumber, style) {
  const url = `${BASE_URL}/scores/${judgeId}/heats/${heatNumber}?style=${style}`;
  console.error(`Fetching heat data from ${url}...`);

  const jsonText = await fetchUrl(url);
  const data = JSON.parse(jsonText);

  console.error('Heat data loaded successfully');
  return data;
}

/**
 * Select appropriate template based on heat data
 */
function selectTemplate(templates, data) {
  if (data.heat.category === 'Solo') {
    console.error('Using soloHeat template');
    return templates.soloHeat;
  } else if (data.final) {
    console.error('Using rankHeat template');
    return templates.rankHeat;
  } else if (data.style !== 'cards' || !data.scores || data.scores.length === 0) {
    console.error('Using tableHeat template');
    return templates.tableHeat;
  } else {
    console.error('Using cardsHeat template');
    return templates.cardsHeat;
  }
}

/**
 * Main execution
 */
async function main() {
  try {
    // Load templates and data in parallel
    const [templates, data] = await Promise.all([
      loadTemplates(),
      loadHeatData(judgeId, heatNumber, style)
    ]);

    // Select and execute template
    const templateFn = selectTemplate(templates, data);
    const html = templateFn(data);

    // Output rendered HTML to stdout
    console.log(html);

    console.error('\nRendering complete!');
    console.error(`HTML length: ${html.length} characters`);

  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

main();
