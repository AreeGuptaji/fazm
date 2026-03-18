---
name: hindsight-memory
description: "Persistent memory across conversations using Hindsight. Automatically recall relevant context at conversation start and retain important facts, preferences, and decisions the user shares. Use retain/recall/reflect tools from the hindsight MCP server."
---

# Hindsight Memory

Hindsight is a persistent memory layer that stores facts, preferences, and context across conversations. It runs as a local MCP server with three core tools: **retain**, **recall**, and **reflect**.

The memory bank is pre-configured in the MCP URL — no `bank_id` parameter needed.

## When to Recall

- **Start of every conversation**: call `recall` with a query derived from the user's first message to load relevant context
- When the user asks about something they may have mentioned before
- Before making recommendations that should account for past preferences
- Keep `budget` at `low` or `mid` for routine lookups; use `high` only for broad synthesis

Example:
```json
{ "name": "recall", "arguments": { "query": "user preferences and recent projects", "budget": "mid" } }
```

## When to Retain

Call `retain` when the user shares meaningful information worth remembering across sessions:

- Personal facts, role, or background
- Preferences and opinions (tools, languages, workflows)
- Decisions and their reasoning
- Project context, goals, deadlines
- Important people, teams, or relationships
- Corrections to previous assumptions

Do NOT retain:
- Every message or trivial exchanges
- Information already stored (check recall first if unsure)
- Temporary debugging context or one-off questions

Example:
```json
{ "name": "retain", "arguments": { "content": "User prefers Swift Package Manager over Xcode projects", "context": "development_preferences", "tags": ["preferences", "tooling"] } }
```

## When to Reflect

Call `reflect` for synthesized analysis across multiple memories:

- "What patterns do you see in how I work?"
- "Based on what you know about me, what would you recommend?"
- Questions requiring reasoning across many past observations

Example:
```json
{ "name": "reflect", "arguments": { "query": "What are the user's key technical preferences and workflow patterns?", "budget": "mid" } }
```

## Guidelines

- Be selective — retain quality over quantity
- Use `context` parameter to categorize (e.g., `programming_preferences`, `project_context`, `personal`)
- Use `tags` for filtering (e.g., `["preferences"]`, `["project:fazm"]`)
- Don't announce every retain/recall to the user — do it silently in the background
- If recall returns nothing relevant, proceed normally without mentioning it
