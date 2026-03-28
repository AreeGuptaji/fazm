# test-release: Smoke Test a Fazm Release

Smoke test a Fazm release on **both** the local production app and the MacStadium remote machine. Use after promoting a release to beta or stable, or when the user says "test the release", "smoke test", "verify the build works".

**This skill does NOT build anything.** It tests the shipped product that users receive via Sparkle auto-update.

## Prerequisites

- The release must already be promoted (registered in Firestore on beta or stable channel)
- The production Fazm app must be installed locally (`/Applications/Fazm.app`)
- MacStadium remote machine must be reachable (`./scripts/macstadium/ssh.sh`)

## Flow

### Step 1: Trigger Update on Local Machine

1. Open the production Fazm app (not Fazm Dev):
   ```bash
   open -a "Fazm"
   ```
2. Wait 5 seconds for it to launch, then use `macos-use` MCP to navigate to Settings > About and click "Check for Updates"
3. Wait for Sparkle to find and install the update. Watch logs:
   ```bash
   tail -f /private/tmp/fazm.log | grep -i "sparkle\|update"
   ```
4. If the app restarts after update, wait for it to be ready

### Step 2: Send Test Queries on Local Machine

Send each query via distributed notification. Wait 15 seconds between queries for the AI to respond. After each query, check `/private/tmp/fazm.log` for errors.

```bash
# Query 1: Basic chat (AI responds at all)
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "What is 2+2?"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'

# Query 2: Memory recall (memory pipeline works)
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "What do you remember about me?"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'

# Query 3: Tool use / Google Workspace (MCP tools connected)
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "What events do I have on my calendar today?"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'

# Query 4: File system tool use
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "List the files on my Desktop"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'
```

After each query:
- Check logs for errors: `grep -i "error\|fail\|crash\|unauthorized\|401" /private/tmp/fazm.log | tail -5`
- Check the AI actually responded: `grep -i "AGENT_BRIDGE\|response\|completed" /private/tmp/fazm.log | tail -10`

### Step 3: Trigger Update on MacStadium Remote Machine

1. Check if Fazm is running on the remote machine:
   ```bash
   ./scripts/macstadium/ssh.sh "pgrep -la Fazm"
   ```
2. If not running, launch it:
   ```bash
   ./scripts/macstadium/ssh.sh "open -a Fazm"
   ```
3. Use `macos-use-remote` MCP to navigate to Settings > About and trigger "Check for Updates"
4. Wait for the update to install. Watch remote logs:
   ```bash
   ./scripts/macstadium/ssh.sh "tail -50 /tmp/fazm.log" | grep -i "sparkle\|update"
   ```

### Step 4: Send Test Queries on MacStadium Remote Machine

Use `macos-use-remote` MCP to interact with the floating bar on the remote machine. For each query:

1. Use `macos-use-remote` to activate the floating bar (click or keyboard shortcut)
2. Type the query into the floating bar input
3. Wait for the AI to respond
4. Screenshot the result to verify
5. Check remote logs for errors:
   ```bash
   ./scripts/macstadium/ssh.sh "grep -i 'error\|fail\|crash' /tmp/fazm.log | tail -10"
   ```

**Remote test queries** (same set):
- "What is 2+2?"
- "What do you remember about me?"
- "What events do I have on my calendar today?"
- "List the files on my Desktop"

### Step 5: Check Sentry

After all queries are sent, check Sentry for new errors in this release version:
```bash
./scripts/sentry-release.sh
```

### Step 6: Report Results

Report a summary table:

| Test | Local | Remote |
|------|-------|--------|
| App updated to vX.Y.Z | pass/fail | pass/fail |
| Basic chat ("2+2") | pass/fail | pass/fail |
| Memory recall | pass/fail | pass/fail |
| Tool use (calendar) | pass/fail | pass/fail |
| File system (Desktop) | pass/fail | pass/fail |
| Sentry errors | 0 new / N new | — |

**pass** = AI responded without errors in logs
**fail** = no response, error in logs, or crash

## What Counts as a Failure

- App doesn't update (Sparkle error, appcast not serving correct version)
- Query gets no AI response within 60 seconds
- Logs show `error`, `crash`, `unauthorized`, `401`, or `failed` during the query
- App crashes or becomes unresponsive
- Sentry shows new issues for this release version
