#!/usr/bin/env bash
# check-inbound.sh — Process new FAZM inbound emails one at a time
# Called by launchd every 5 minutes.
# For each new inbound email, spins up a full Claude Code session in the FAZM repo.

set -euo pipefail

source "$(dirname "$0")/lock.sh"
acquire_lock "check-inbound" 3600

# Load secrets from analytics (where the DB creds live)
# Can't source the file directly — it has multi-line JSON that breaks bash
ENV_FILE="$HOME/analytics/.env.production.local"
if [ -f "$ENV_FILE" ]; then
    export DATABASE_URL=$(grep '^DATABASE_URL=' "$ENV_FILE" | head -1 | sed 's/^DATABASE_URL=//' | tr -d '"')
    export RESEND_API_KEY=$(grep '^RESEND_API_KEY=' "$ENV_FILE" | sed 's/^RESEND_API_KEY=//' | tr -d '"' | tr -d '\\n')
    export POSTHOG_PERSONAL_API_KEY=$(grep '^POSTHOG_PERSONAL_API_KEY=' "$ENV_FILE" | sed 's/^POSTHOG_PERSONAL_API_KEY=//' | tr -d '"' | tr -d '\\n')
fi

export NODE_PATH="$HOME/analytics/node_modules"
INBOX_DIR="$HOME/fazm/inbox"
SCRIPTS_DIR="$INBOX_DIR/scripts"
LOG_DIR="$INBOX_DIR/skill/logs"
NODE_BIN="$HOME/.nvm/versions/node/v20.19.4/bin/node"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/check-inbound-$(date +%Y-%m-%d_%H%M%S).log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

log "=== FAZM Inbox Check: $(date) ==="

# Check for new unprocessed inbound emails
EMAILS=$("$NODE_BIN" "$SCRIPTS_DIR/check-new-inbound.js" 2>>"$LOG_FILE")

if [ "$EMAILS" = "[]" ] || [ -z "$EMAILS" ]; then
    log "No new inbound emails. Done."
    exit 0
fi

# Parse the first email (we process one at a time)
EMAIL_ID=$(echo "$EMAILS" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['email_id'])")
SENDER_EMAIL=$(echo "$EMAILS" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['sender_email'])")
SENDER_NAME=$(echo "$EMAILS" | python3 -c "import json,sys; d=json.load(sys.stdin)[0]; print(d.get('sender_name') or d['sender_email'])")
SUBJECT=$(echo "$EMAILS" | python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('subject','(no subject)'))")
WORKFLOW_USER_ID=$(echo "$EMAILS" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['workflow_user_id'])")

log "Processing email #$EMAIL_ID from $SENDER_EMAIL: $SUBJECT"

# Build the prompt for Claude
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" <<PROMPT_EOF
Read ~/fazm/inbox/SKILL.md for the full workflow.

## Email to process

Email ID: $EMAIL_ID
Workflow User ID: $WORKFLOW_USER_ID
Sender: $SENDER_NAME <$SENDER_EMAIL>
Subject: $SUBJECT

Full email data (including thread history):
$EMAILS

Process this email now. Follow the SKILL.md workflow exactly.
PROMPT_EOF

# Run Claude Code with full permissions in the FAZM repo
log "Spawning Claude Code session..."
gtimeout 1800 claude \
    -p "$(cat "$PROMPT_FILE")" \
    --dangerously-skip-permissions \
    --no-session-persistence \
    2>&1 | tee -a "$LOG_FILE" || log "WARNING: Claude exited with code $?"

rm -f "$PROMPT_FILE"

# Mark the email as processed regardless of Claude's outcome
"$NODE_BIN" "$SCRIPTS_DIR/mark-processed.js" "$EMAIL_ID" 2>>"$LOG_FILE" || log "WARNING: Failed to mark email $EMAIL_ID as processed"

log "=== Done processing email #$EMAIL_ID ==="

# Cleanup old logs (keep 14 days)
find "$LOG_DIR" -name "check-inbound-*.log" -mtime +14 -delete 2>/dev/null || true
