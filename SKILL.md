---
name: nanomsg
description: Read and send iMessage or SMS with the nanomsg CLI. Use when working on a Mac where nanomsg is installed and you need terminal access to Messages data or sending.
---

# nanomsg CLI

Always use `--json` — output is human-readable text by default, but agents need structured JSON.

## Read

```bash
nanomsg chats --json --limit 20
nanomsg chats --json --unread
nanomsg unread --json --limit 20
nanomsg unread --json --chat-id 207
nanomsg history --json --chat-id 207 --limit 20
nanomsg history --json --chat-id 207 --since "2026-02-13"
nanomsg search --json "query" --limit 20
nanomsg search --json "query" --chat-id 207
nanomsg search --json "query" --from "Alice"
nanomsg contacts --json
```

## Write

```bash
nanomsg send --json --to "+1234567890" --text "Hello"
nanomsg send --json --chat-id 207 --text "Hello"
```

## Workflow

1. Run `chats --json` first to identify target chat IDs.
2. Use `history --json` for context before replying.
3. Use `search --json --from` when sender context matters.
4. Ask for confirmation before sending messages.
