# Observer Session — Product Spec

## Problem

Users currently have to manually create skill files (.skill.md) to teach Fazm their personal preferences and rules — shopping habits, delivery preferences, website registration patterns, etc. This works for power users but is a non-starter for regular users. The AI should learn these automatically from observing the user's behavior and conversations.

## Solution

A parallel ACP session ("the Observer") that runs alongside every main conversation. Same Opus model. It watches the conversation transcript and screen context, learns about the user, updates the knowledge graph, stores observations via Hindsight, and can create new skills — all using existing infrastructure.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                Main ACP Session                      │
│  (interactive — user ↔ agent conversation)           │
│                                                      │
│  Reads knowledge graph + Hindsight at each turn      │
│  Never aware of the observer directly                │
└──────────┬──────────────────────┬────────────────────┘
           │ conversation turns   │ (shared state)
           │ (piped as context)   │
           ▼                      │
┌─────────────────────────────────│────────────────────┐
│           Observer ACP Session  │                    │
│  (parallel Opus — same model)   │                    │
│                                 │                    │
│  Inputs:                        │                    │
│  • Batched conversation turns   │                    │
│  • Periodic screenshots         │                    │
│                                 │                    │
│  Outputs:                       ▼                    │
│  • Knowledge graph (save_knowledge_graph) ───────────│──→ Main session reads via SQL
│  • Hindsight (retain/recall/reflect) ────────────────│──→ Main session recalls
│  • Skills (~/.claude/skills/*.skill.md) ─────────────│──→ Main session discovers
│  • Observer cards (observer_activity table) ──────────│──→ UI renders inline
└──────────────────────────────────────────────────────┘
```

## What the Observer Uses (all existing)

| Capability | Infrastructure | Already exists? |
|------------|---------------|-----------------|
| Store facts about the user | `local_kg_nodes` + `local_kg_edges` | Yes |
| Semantic memory | Hindsight MCP (`retain`, `recall`, `reflect`) | Yes |
| Create automations | Write `.skill.md` files to `~/.claude/skills/` | Yes |
| Query user profile | `query_browser_profile`, `ai_user_profiles` | Yes |
| Read/write DB | `execute_sql` | Yes |
| See the screen | `capture_screenshot` | Yes |
| Interact with user | **observer_activity table** (new) | **No — one new table** |

## The One New Table: `observer_activity`

Everything the observer does — insights, questions, skill creation notices, learned facts — goes here. One table, flexible schema.

```sql
CREATE TABLE observer_activity (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,          -- "card", "insight", "skill_created", "kg_update", "pattern"
    content TEXT NOT NULL,       -- JSON blob: {title, body, options, ...}
    status TEXT DEFAULT 'pending', -- "pending", "shown", "acted", "dismissed"
    user_response TEXT,          -- which button was tapped (for cards)
    created_at TEXT NOT NULL,
    acted_at TEXT
);
```

This is the observer's activity log AND the UI card queue. The Swift UI polls for `status = 'pending'` rows with `type = 'card'` and renders them.

### Example rows

**A learned preference (silent, no UI):**
```json
{
  "id": "obs_001",
  "type": "insight",
  "content": "{\"fact\": \"prefers Amazon for electronics\", \"kg_node_id\": \"n_42\"}",
  "status": "logged",
  "created_at": "2026-03-17T10:30:00Z"
}
```

**A question for the user (shows as card):**
```json
{
  "id": "obs_002",
  "type": "card",
  "content": "{\"title\": \"Two shipping addresses used recently\", \"body\": \"Which should be your default?\", \"options\": [\"123 Main St, SF\", \"456 Oak Ave, LA\"]}",
  "status": "pending",
  "created_at": "2026-03-17T10:31:00Z"
}
```

**A skill was auto-created:**
```json
{
  "id": "obs_003",
  "type": "skill_created",
  "content": "{\"skill_name\": \"client-report-export\", \"description\": \"Export PDF and email to client in one step\", \"path\": \"~/.claude/skills/client-report-export/SKILL.md\"}",
  "status": "pending",
  "created_at": "2026-03-17T10:35:00Z"
}
```

## Observer Responsibilities

### 1. Learn — Update the Knowledge Graph
The observer uses `save_knowledge_graph` (existing tool) to add nodes and edges as it learns about the user from conversations and screen context. Preferences, people, tools, habits — all go into the same graph the onboarding built.

### 2. Remember — Use Hindsight
The observer calls `retain` (Hindsight MCP) to store observations that don't fit neatly into a graph — nuanced context, conversation summaries, behavioral patterns. The main session can `recall` these naturally.

### 3. Automate — Create Skills
When the observer detects a repeated workflow (3+ occurrences), it writes a `.skill.md` file to `~/.claude/skills/` and logs a `skill_created` entry to `observer_activity`. The main session auto-discovers new skills on next prompt.

### 4. Ask — Surface Cards (sparingly)
When the observer needs user input, it writes a `type = 'card'` row to `observer_activity`. The UI renders it inline in the chat.

## UI: Observer Cards

Cards appear inline in the chat but are visually distinct — different background, "Observer" label, button-only interaction.

```
┌─ Observer ─────────────────────────────────────────┐
│ You've done "export PDF → email to client" 4       │
│ times. Want me to make it a single command?        │
│                                                    │
│  [Create skill]    [Not now]    [Never ask]        │
└────────────────────────────────────────────────────┘
```

### UI Rules
1. **Button-only** — user never types to the observer. Text input always goes to the main agent.
2. **Non-blocking** — main conversation continues. Cards appear at natural pauses.
3. **Dismissible** — tap X or swipe. Dismissed = `status: 'dismissed'`.
4. **Rate-limited** — max 2-3 cards per conversation. Observer picks the most valuable.
5. **Clearly labeled** — always shows "Observer" label. Never confused with the main agent.

### Card Interaction Flow
1. Observer writes row to `observer_activity` with `type: 'card'`, `status: 'pending'`
2. Swift UI polls table, renders card inline in chat
3. User taps a button → Swift writes `user_response` and sets `status: 'acted'`
4. Observer reads the response on next batch and acts accordingly (e.g., creates skill, updates KG)

## Observer Session Configuration

### Session Key
`"observer"` — alongside existing `"main"` and `"onboarding"`

### Model
Opus (same as main session)

### Tools Available
- `execute_sql` — read/write observer_activity, knowledge graph, profiles
- `capture_screenshot` — periodic screen context (max 1/minute)
- `save_knowledge_graph` — update user graph with new nodes/edges
- `query_browser_profile` — access browser-extracted profile data
- `load_skill` — read existing skills to avoid duplicates
- Hindsight MCP — `retain`, `recall`, `reflect`
- File write access to `~/.claude/skills/` — for creating new skills

### Tools NOT Available
- No `ask_followup` — observer doesn't talk to user directly via chat
- No onboarding tools
- No Playwright/macos-use — observer observes, it doesn't act

### System Prompt

```
You are the Observer — a parallel intelligence running alongside the user's
conversation with their AI agent. You watch the conversation and screen
activity. Your job is to build an ever-richer understanding of this person
and make their agent more effective over time.

## Your tools

1. KNOWLEDGE GRAPH (save_knowledge_graph)
   Add nodes and edges as you learn about the user. Preferences, people,
   projects, tools, habits, rules — all belong in the graph. This is the
   same graph built during onboarding. Extend it continuously.

2. HINDSIGHT (retain, recall, reflect)
   Store nuanced observations, conversation summaries, and behavioral
   context. Use retain for new observations. Use reflect periodically
   to synthesize patterns across multiple observations.

3. SKILLS (write to ~/.claude/skills/)
   When you detect a repeated multi-step workflow (3+ times), create a
   .skill.md file that automates it. Log the creation to observer_activity.

4. OBSERVER CARDS (execute_sql → observer_activity table)
   When you need user input, write a card. Use sparingly — max 2-3 per
   conversation. Card format:
   INSERT INTO observer_activity (id, type, content, status, created_at)
   VALUES ('obs_xxx', 'card', '{"title":"...","body":"...","options":["A","B"]}',
           'pending', datetime('now'));

## What you receive
- Batched conversation turns (every 5-10 messages from the main session)
- Periodic screenshots (1/minute when user is active)
- The user's response to any cards you surfaced (poll observer_activity)

## Principles
- Surface CONCLUSIONS, not observations. "Saved: you prefer X" not "I noticed you did X"
- Write to the knowledge graph liberally — it's cheap and the main agent reads it
- Use Hindsight for context that's too nuanced for structured data
- Create skills only for clear, repeated patterns — not one-off workflows
- Ask the user only when the answer materially changes how you'd serve them
- You are Opus. Think deeply. Connect dots across sessions.
```

## Conversation Feed Mechanism

The ACP bridge pipes main session turns to the observer in batches:

1. Main session processes a user turn + agent response
2. Bridge appends the turn pair to an observer input buffer
3. Every 5 turns (or when the user goes idle for 30s), the bridge sends the batch to the observer session as a `session/prompt` with:
   - The conversation batch
   - A fresh screenshot (if user was active)
4. The observer processes asynchronously — its outputs (KG updates, Hindsight retains, skill files, cards) happen independently of the main session

## How the Main Session Benefits

The main session already reads from all the stores the observer writes to:

| Observer writes to | Main session reads via | Already wired? |
|-------------------|----------------------|----------------|
| `local_kg_nodes/edges` | `execute_sql` + system prompt context | Yes |
| Hindsight | `recall` MCP tool | Yes |
| `~/.claude/skills/` | Skill discovery in `ChatProvider.swift` | Yes |
| `ai_user_profiles` | `formatAIProfileSection()` | Yes |

No new "preference injection" code needed. The observer enriches the same stores the main session already consults.

## Implementation Phases

### Phase 1: Observer Session + Knowledge Graph Learning
- One new DB table (`observer_activity`)
- Observer ACP session that receives conversation batches
- Observer updates knowledge graph via `save_knowledge_graph`
- Observer stores context via Hindsight `retain`
- **No UI changes** — the main agent just gets smarter because the KG and Hindsight are richer

### Phase 2: Observer Cards
- Swift UI component for rendering cards inline in chat
- Poll `observer_activity` for `type='card', status='pending'`
- Button taps write back to table
- Observer reads responses and acts
- Rate limiting (max 2-3 per conversation)

### Phase 3: Auto-Skill Creation
- Observer detects repeated workflows
- Writes `.skill.md` files to `~/.claude/skills/`
- Surfaces `skill_created` card for user awareness
- Main session auto-discovers new skills

### Phase 4: Screen Context Intelligence
- Periodic screenshot analysis (not just on-demand)
- Observer understands what app the user is in, what they're working on
- Cross-references screen context with conversation for richer KG updates

## Open Questions

1. **Cost**: Running Opus in parallel doubles API cost. Premium feature, opt-in, or default for all?

2. **Privacy**: Should there be a "pause observer" toggle? Private mode?

3. **Hindsight vs KG boundary**: When should the observer use `save_knowledge_graph` vs Hindsight `retain`? Rule of thumb: structured facts (entities, relationships) → KG. Nuanced context (behavioral patterns, conversation summaries) → Hindsight.

4. **Skill quality**: Auto-generated skills need to be good enough to use immediately. Should the observer test them before surfacing, or always ask the user to review?

5. **Cross-session continuity**: The observer session resets each app launch. Its memory persists through KG + Hindsight + observer_activity table. Is that sufficient, or does it need its own persistent context?
