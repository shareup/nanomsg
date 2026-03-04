# nanomsg

**_Experimental. Shouldn't be considered production ready yet._**

A Swift CLI for reading and sending iMessage/SMS on macOS.

Reads `chat.db` directly and resolves phone numbers and emails to contact names via the Contacts framework. Human-readable text by default, `--json` for structured output.

## Install

```bash
./install.sh
```

This builds a release binary and symlinks it to `~/bin/nanomsg`.

### Requirements

- macOS 14 (Sonoma) or later
- Swift 6.0+ (included with Xcode 16+)
- `~/bin` in your `PATH`

### Permissions

Grant your terminal app in **System Settings > Privacy & Security**:

- **Full Disk Access** — to read `~/Library/Messages/chat.db`
- **Contacts** — to resolve names (optional; falls back to raw handles)
- **Automation > Messages** — for the `send` command

## Commands

```bash
# List recent conversations (with 3 most recent messages each)
nanomsg chats --limit 10

# Only conversations with unread messages
nanomsg chats --unread

# Unread messages grouped by chat
nanomsg unread
nanomsg unread --chat-id 207

# Message history for a chat
nanomsg history --chat-id 207 --limit 20
nanomsg history --chat-id 207 --since "2026-02-14"

# Search messages
nanomsg search "dinner" --limit 10
nanomsg search "dinner" --chat-id 207
nanomsg search "hello" --from "Alice"

# Search contacts by handle or name
nanomsg contacts "smith"
nanomsg contacts "+1540" --limit 10

# Send a message
nanomsg send --to "+1234567890" --text "Hello"
nanomsg send --chat-id 207 --text "Hello"

# Per-command help
nanomsg help chats
```

## Global options

| Flag | Description |
|------|-------------|
| `--json` | Output JSON instead of human-readable text |
| `--no-contacts` | Skip contact name resolution (raw handles) |
| `--limit N` | Max results to return |
| `--offset N` | Skip first N results (pagination) |

## Output format

Default output is human-readable text with relative dates ("Today at 10:30", "Yesterday at 18:00"). Use `--json` for structured JSON with ISO 8601 dates.

JSON shapes:

- **chats**: `chatId`, `guid`, `displayName`, `participants`, `participantNames`, `lastMessageDate`, `lastMessageText`, `unreadCount`, `isGroup`, `recentMessages`
- **history/search**: `rowid`, `guid`, `text`, `sender`, `senderName`, `isFromMe`, `date`, `isRead`, `reactions[]`, `attachments[]`, `threadOriginator`
- **unread**: groups of `chatId`, `chatName`, `participants`, `messages[]`
- **contacts**: `handleId`, `service`, `resolvedName`
- **send**: `{"status": "sent", "text": "..."}`

## Testing

`TEST.md` contains integration test instructions designed to be run by a coding agent (like Claude Code). To run them:

```
claude -p "Read TEST.md and run all the tests. Report pass/fail for each."
```

The tests exercise every command in both text and JSON modes, check pagination, edge cases, and error handling. Some tests require real iMessage state (e.g., unread messages) — the instructions tell the agent when to ask you to set that up.

## Use as a coding agent skill

Symlink this repo into your project's `.claude/skills/`:

```bash
ln -s /path/to/nanomsg /your/project/.claude/skills/nanomsg
```

The repo root contains a `SKILL.md` that teaches a coding agent how to use nanomsg for iMessage access.

## License

MIT
