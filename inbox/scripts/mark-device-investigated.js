#!/usr/bin/env node

/**
 * Mark a device as investigated by the session replay pipeline.
 * Creates the tracking table if it doesn't exist.
 *
 * Usage: node mark-device-investigated.js <device_id> [summary] [outcome_file]
 *
 * If outcome_file is provided, reads it for email_sent_to_user, report_sent_to_matt,
 * issues_found, and bugs_fixed.
 */

const { neon } = require('@neondatabase/serverless');
const fs = require('fs');

async function main() {
  const deviceId = process.argv[2];
  const summary = process.argv[3] || '';
  const outcomeFile = process.argv[4];

  if (!deviceId) {
    console.error('Usage: node mark-device-investigated.js <device_id> [summary] [outcome_file]');
    process.exit(1);
  }

  const dbUrl = process.env.DATABASE_URL;
  if (!dbUrl) {
    console.error('DATABASE_URL not set');
    process.exit(1);
  }

  // Parse outcome file if provided
  let outcome = {};
  if (outcomeFile && fs.existsSync(outcomeFile)) {
    try {
      outcome = JSON.parse(fs.readFileSync(outcomeFile, 'utf8'));
    } catch (e) {
      console.error('Warning: could not parse outcome file:', e.message);
    }
  }

  const emailSent = outcome.userEmailSent === true;
  const reportSent = outcome.reportEmailSent === true;
  const issuesFound = outcome.issuesFound || 0;
  const bugsFixed = outcome.bugsFixed || 0;

  const sql = neon(dbUrl);

  // Create table if not exists
  await sql.query(`
    CREATE TABLE IF NOT EXISTS session_replay_investigations (
      id SERIAL PRIMARY KEY,
      device_id TEXT NOT NULL UNIQUE,
      investigated_at TIMESTAMPTZ DEFAULT NOW(),
      summary TEXT,
      email_sent_to_user BOOLEAN DEFAULT FALSE,
      report_sent_to_matt BOOLEAN DEFAULT FALSE,
      issues_found INTEGER DEFAULT 0,
      bugs_fixed INTEGER DEFAULT 0
    )
  `);

  // Upsert the record with outcome data
  await sql.query(
    `INSERT INTO session_replay_investigations (device_id, investigated_at, summary, email_sent_to_user, report_sent_to_matt, issues_found, bugs_fixed)
     VALUES ($1, NOW(), $2, $3, $4, $5, $6)
     ON CONFLICT (device_id) DO UPDATE SET
       investigated_at = NOW(),
       summary = COALESCE(NULLIF($2, ''), session_replay_investigations.summary),
       email_sent_to_user = $3,
       report_sent_to_matt = $4,
       issues_found = $5,
       bugs_fixed = $6`,
    [deviceId, summary, emailSent, reportSent, issuesFound, bugsFixed]
  );

  console.log(`Marked device ${deviceId} as investigated (issues=${issuesFound}, fixed=${bugsFixed}, userEmail=${emailSent}, report=${reportSent})`);
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
