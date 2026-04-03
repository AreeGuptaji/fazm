#!/usr/bin/env node

/**
 * Mark a device as investigated by the session replay pipeline.
 * Creates the tracking table if it doesn't exist.
 *
 * Usage: node mark-device-investigated.js <device_id> [summary]
 */

const { neon } = require('@neondatabase/serverless');

async function main() {
  const deviceId = process.argv[2];
  const summary = process.argv[3] || '';

  if (!deviceId) {
    console.error('Usage: node mark-device-investigated.js <device_id> [summary]');
    process.exit(1);
  }

  const dbUrl = process.env.DATABASE_URL;
  if (!dbUrl) {
    console.error('DATABASE_URL not set');
    process.exit(1);
  }

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

  // Upsert the record
  await sql.query(
    `INSERT INTO session_replay_investigations (device_id, investigated_at, summary)
     VALUES ($1, NOW(), $2)
     ON CONFLICT (device_id) DO UPDATE SET
       investigated_at = NOW(),
       summary = COALESCE(NULLIF($2, ''), session_replay_investigations.summary)`,
    [deviceId, summary]
  );

  console.log(`Marked device ${deviceId} as investigated`);
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
