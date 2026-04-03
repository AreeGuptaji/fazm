#!/usr/bin/env node

/**
 * Trigger Gemini video analysis for a device via the orchestrate API.
 * Waits for completion by polling the status endpoint.
 *
 * Usage: node trigger-session-analysis.js <device_id>
 *
 * Returns JSON with analysis results when complete.
 * Caps at 100 unanalyzed chunks (skips if device has more).
 */

const https = require('https');

const ORCHESTRATE_URL = 'https://omi-analytics.vercel.app/api/session-recordings/orchestrate';
const CRON_SECRET = process.env.CRON_SECRET || '2d17eac34d9fdc61e555e972089a17c9';
const POLL_INTERVAL = 30000; // 30 seconds
const MAX_WAIT = 600000; // 10 minutes
const MAX_CHUNKS = 100;

function fetchJSON(url, options = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const reqOptions = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: options.method || 'GET',
      headers: {
        'Authorization': `Bearer ${CRON_SECRET}`,
        'Content-Type': 'application/json',
        ...options.headers,
      },
    };
    const req = https.request(reqOptions, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`Invalid JSON: ${data.slice(0, 200)}`)); }
      });
    });
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
  const deviceId = process.argv[2];
  if (!deviceId) {
    console.error('Usage: node trigger-session-analysis.js <device_id>');
    process.exit(1);
  }

  // Check current status
  const status = await fetchJSON(`${ORCHESTRATE_URL}?action=status&deviceId=${deviceId}`);

  if (status.error) {
    console.error('Device not found:', status.error);
    process.exit(1);
  }

  if (status.unanalyzedChunks === 0) {
    process.stderr.write(`Device ${deviceId}: all ${status.totalChunks} chunks already analyzed\n`);
    // Fetch existing analyses
    const analyses = await fetchJSON(`${ORCHESTRATE_URL}?action=analyses&deviceId=${deviceId}`);
    console.log(JSON.stringify(analyses));
    return;
  }

  if (status.unanalyzedChunks > MAX_CHUNKS) {
    process.stderr.write(`Device ${deviceId}: ${status.unanalyzedChunks} unanalyzed chunks exceeds cap of ${MAX_CHUNKS}. Skipping.\n`);
    process.exit(2);
  }

  process.stderr.write(`Device ${deviceId}: triggering analysis for ${status.unanalyzedChunks} unanalyzed chunks...\n`);

  // Trigger analysis (fire and forget, it runs server-side)
  const triggerPromise = fetchJSON(ORCHESTRATE_URL, {
    method: 'POST',
    body: JSON.stringify({ action: 'analyze', deviceId }),
  });

  // Poll for completion
  const startTime = Date.now();
  let lastAnalyzed = status.analyzedChunks;

  while (Date.now() - startTime < MAX_WAIT) {
    await sleep(POLL_INTERVAL);

    const current = await fetchJSON(`${ORCHESTRATE_URL}?action=status&deviceId=${deviceId}`);
    process.stderr.write(`  Progress: ${current.analyzedChunks}/${current.totalChunks} chunks, ${current.totalAnalyses} analyses\n`);

    if (current.unanalyzedChunks === 0) {
      process.stderr.write(`  Analysis complete!\n`);
      // Fetch full analyses
      const analyses = await fetchJSON(`${ORCHESTRATE_URL}?action=analyses&deviceId=${deviceId}`);
      console.log(JSON.stringify(analyses));
      return;
    }

    if (current.analyzedChunks > lastAnalyzed) {
      lastAnalyzed = current.analyzedChunks;
      // Reset timer on progress
    }
  }

  // Timed out but may have partial results
  process.stderr.write(`  Timed out after ${MAX_WAIT / 1000}s. Fetching partial results.\n`);
  const analyses = await fetchJSON(`${ORCHESTRATE_URL}?action=analyses&deviceId=${deviceId}`);
  console.log(JSON.stringify(analyses));

  // Wait for the trigger promise to settle
  try { await triggerPromise; } catch (e) { /* ignore */ }
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
