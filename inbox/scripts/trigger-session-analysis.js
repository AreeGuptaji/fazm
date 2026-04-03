#!/usr/bin/env node

/**
 * Trigger Gemini video analysis for a device via the orchestrate API.
 * Handles the Vercel function's 800s timeout by making multiple API calls
 * if needed (each call processes ~60 chunks before timing out).
 *
 * Usage: node trigger-session-analysis.js <device_id>
 *
 * Returns JSON with analysis results when complete.
 * Caps at 100 unanalyzed chunks total.
 */

const https = require('https');

const ORCHESTRATE_URL = 'https://omi-analytics.vercel.app/api/session-recordings/orchestrate';
const CRON_SECRET = process.env.CRON_SECRET || '2d17eac34d9fdc61e555e972089a17c9';
const POLL_INTERVAL = 30000; // 30 seconds
const ROUND_TIMEOUT = 900000; // 15 minutes per round (Vercel has 800s, plus buffer)
const MAX_ROUNDS = 3; // At ~60 chunks per round, 3 rounds = ~180 chunks max
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

async function getStatus(deviceId) {
  return fetchJSON(`${ORCHESTRATE_URL}?action=status&deviceId=${deviceId}`);
}

async function getAnalyses(deviceId) {
  return fetchJSON(`${ORCHESTRATE_URL}?action=analyses&deviceId=${deviceId}`);
}

/**
 * Trigger one round of analysis and wait for it to complete or the
 * Vercel function to time out (whichever comes first).
 * Returns the number of newly analyzed chunks.
 */
async function runOneRound(deviceId, startingAnalyzed) {
  // Fire the analysis request (don't await; it runs server-side)
  fetchJSON(ORCHESTRATE_URL, {
    method: 'POST',
    body: JSON.stringify({ action: 'analyze', deviceId }),
  }).catch(() => {}); // Ignore client-side errors; the server processes independently

  const roundStart = Date.now();
  let lastAnalyzed = startingAnalyzed;
  let staleSince = Date.now();

  while (Date.now() - roundStart < ROUND_TIMEOUT) {
    await sleep(POLL_INTERVAL);

    const current = await getStatus(deviceId);
    process.stderr.write(`  Progress: ${current.analyzedChunks}/${current.totalChunks} chunks, ${current.totalAnalyses} analyses\n`);

    if (current.unanalyzedChunks === 0) {
      return current.analyzedChunks - startingAnalyzed;
    }

    if (current.analyzedChunks > lastAnalyzed) {
      lastAnalyzed = current.analyzedChunks;
      staleSince = Date.now();
    } else if (Date.now() - staleSince > 120000) {
      // No progress for 2 minutes; the Vercel function likely timed out
      process.stderr.write(`  No progress for 2 min; Vercel function likely timed out. Round done.\n`);
      return current.analyzedChunks - startingAnalyzed;
    }
  }

  // Round timed out
  const finalStatus = await getStatus(deviceId);
  return finalStatus.analyzedChunks - startingAnalyzed;
}

async function main() {
  const deviceId = process.argv[2];
  if (!deviceId) {
    console.error('Usage: node trigger-session-analysis.js <device_id>');
    process.exit(1);
  }

  // Check current status
  const status = await getStatus(deviceId);

  if (status.error) {
    console.error('Device not found:', status.error);
    process.exit(1);
  }

  if (status.unanalyzedChunks === 0) {
    process.stderr.write(`Device ${deviceId}: all ${status.totalChunks} chunks already analyzed\n`);
    const analyses = await getAnalyses(deviceId);
    console.log(JSON.stringify(analyses));
    return;
  }

  if (status.unanalyzedChunks > MAX_CHUNKS) {
    process.stderr.write(`Device ${deviceId}: ${status.unanalyzedChunks} unanalyzed chunks exceeds cap of ${MAX_CHUNKS}. Skipping.\n`);
    process.exit(2);
  }

  process.stderr.write(`Device ${deviceId}: ${status.unanalyzedChunks} unanalyzed chunks to process\n`);

  // Run multiple rounds if needed (Vercel function handles ~60 chunks per 800s timeout)
  let totalNewChunks = 0;
  for (let round = 1; round <= MAX_ROUNDS; round++) {
    const currentStatus = await getStatus(deviceId);
    if (currentStatus.unanalyzedChunks === 0) break;

    process.stderr.write(`Round ${round}/${MAX_ROUNDS}: ${currentStatus.unanalyzedChunks} chunks remaining...\n`);
    const newChunks = await runOneRound(deviceId, currentStatus.analyzedChunks);
    totalNewChunks += newChunks;
    process.stderr.write(`  Round ${round} analyzed ${newChunks} new chunks\n`);

    if (newChunks === 0) {
      process.stderr.write(`  No progress in this round; stopping.\n`);
      break;
    }
  }

  const finalStatus = await getStatus(deviceId);
  if (finalStatus.unanalyzedChunks > 0) {
    process.stderr.write(`Warning: ${finalStatus.unanalyzedChunks} chunks still unanalyzed after ${MAX_ROUNDS} rounds\n`);
  }

  process.stderr.write(`Analysis complete: ${totalNewChunks} new chunks analyzed across all rounds\n`);
  const analyses = await getAnalyses(deviceId);
  console.log(JSON.stringify(analyses));
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
