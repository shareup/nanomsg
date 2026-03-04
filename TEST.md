# nanomsg Integration Tests

Run these tests manually using the built binary. Each test describes what to
run, what to check, and when to ask the user for help.

Use `nanomsg` from `~/bin/nanomsg` (the installed release build).

## Setup

Before starting, verify the binary is installed and working:

```bash
nanomsg help
```

Expect: usage text listing all commands (chats, unread, history, search,
contacts, send, help) and global options (--json, --no-contacts).

---

## 1. Chats

### 1a. Default text output

```bash
nanomsg chats --limit 3
```

Check:
- Exactly 3 chats listed
- Each chat has a name (or phone/email) followed by `(#ID)` or `(#ID, group)`
- Each chat shows up to 3 recent messages with sender, date, and text preview
- Dates are human-readable (e.g., "Today at 10:30", "Yesterday at 18:00", "Feb 14, 2026 at 09:00"), not ISO 8601
- No raw JSON anywhere in the output

### 1b. JSON output

```bash
nanomsg chats --limit 2 --json
```

Check:
- Valid JSON array
- Each object has: chatId (number), guid (string), participants (array), recentMessages (array), unreadCount (number), isGroup (boolean)
- Dates are ISO 8601 strings with fractional seconds

### 1c. Pagination

```bash
nanomsg chats --limit 2
nanomsg chats --limit 2 --offset 2
```

Check:
- The second command returns different chats than the first
- No overlap between the two result sets

### 1d. Contact resolution

```bash
nanomsg chats --limit 3
nanomsg chats --limit 3 --no-contacts
```

Check:
- First command shows resolved names (e.g., "Alice Smith")
- Second command shows raw handles (e.g., "+15550198765")
- Same chats, same order

---

## 2. Unread

### 2a. Check current state

```bash
nanomsg unread
```

If output says "No unread messages." — **stop and ask the user** to open
iMessage and mark at least two different conversations as unread (right-click
a chat > Mark as Unread). Then re-run.

### 2b. Verify unread results

After the user has marked conversations as unread:

```bash
nanomsg unread
```

Check:
- Shows at least 2 chat groups
- Each group has a header with chat name, chat ID, and unread count
- Messages are shown with sender and date
- The chats shown match what the user marked as unread

### 2c. JSON output

```bash
nanomsg unread --json
```

Check:
- Valid JSON array of objects
- Each object has: chatId, participants (array), messages (array)
- chatName is present when non-null (omitted when null — normal Swift JSON behavior)
- Messages have: rowid, text, sender, date, isFromMe (false for all)

### 2d. Filter by chat

Pick one chat ID from the unread output above.

```bash
nanomsg unread --chat-id <ID>
```

Check:
- Only shows messages from that single chat
- Does not show other unread chats

### 2e. Confirm ghost messages are filtered

```bash
nanomsg unread --json | python3 -c "import sys,json; msgs=[m for g in json.load(sys.stdin) for m in g['messages']]; assert all(m.get('text') for m in msgs), 'Found message with no text'; print(f'OK: {len(msgs)} unread messages, all have text')"
```

Check:
- No assertion error — all unread messages have actual text content
- No system messages or empty messages leak through

---

## 3. History

### 3a. Pick a chat and view history

Pick a chat ID from the chats output.

```bash
nanomsg history --chat-id <ID> --limit 5
```

Check:
- Messages ordered oldest to newest
- Each message shows sender (or "You"), date, and text
- Reactions shown as `[like (Name)]` etc.
- Attachments shown as `📎 filename (size)`

### 3b. Positional chat ID

```bash
nanomsg history <ID> --limit 3
```

Check:
- Same behavior as `--chat-id <ID>`

### 3c. Date filter

```bash
nanomsg history --chat-id <ID> --since "2026-01-01" --limit 5
```

Check:
- All messages are from 2026 or later
- No messages from before the specified date

### 3d. JSON output

```bash
nanomsg history --chat-id <ID> --limit 3 --json
```

Check:
- Valid JSON array
- Each message has: rowid, guid, text, sender, senderName, isFromMe, date, isRead
- Reactions (if present) have: type, sender, senderName, date
- Dates are ISO 8601

### 3e. Pagination

```bash
nanomsg history --chat-id <ID> --limit 3
nanomsg history --chat-id <ID> --limit 3 --offset 3
```

Check:
- Second command shows older messages
- No overlap

---

## 4. Search

### 4a. Basic text search

```bash
nanomsg search "hello" --limit 5
```

Check:
- All results contain "hello" (case-insensitive) in the message text
- Results shown with sender, date, and full text
- Ordered newest first

### 4b. Search within a chat

```bash
nanomsg search "the" --chat-id <ID> --limit 5
```

Check:
- All results are from the specified chat only

### 4c. Search by sender

Pick a contact name that appears in your messages.

```bash
nanomsg search "the" --from "<Name>" --limit 5
```

Check:
- All results are from that sender (or show that sender's name)
- No messages from other senders

### 4d. Search with no matches

```bash
nanomsg search "xyzzy_nonexistent_string_12345"
```

Check:
- Output: "No messages found."
- No errors

### 4e. --from with no matching sender

```bash
nanomsg search "the" --from "Nonexistent Person XYZZY"
```

Check:
- Output: "No messages found."
- Must NOT return unfiltered results from all senders

---

## 5. Contacts

### 5a. List all

```bash
nanomsg contacts | head -5
```

Check:
- Columnar output: HANDLE, SERVICE, NAME
- Handles are phone numbers or emails
- Services are iMessage, SMS, or RCS
- Names are resolved where possible

### 5b. Search by handle

```bash
nanomsg contacts "+1540"
```

Check:
- Only handles containing "+1540" are shown
- May also show name matches

### 5c. Search by name

```bash
nanomsg contacts "smith"
```

Check:
- Shows handles whose resolved name contains "smith"
- May also show handles containing "smith" in the ID

### 5d. Limit and offset

```bash
nanomsg contacts --limit 3
nanomsg contacts --limit 3 --offset 3
```

Check:
- First returns exactly 3 results
- Second returns 3 different results
- No overlap

### 5e. JSON output

```bash
nanomsg contacts --limit 3 --json
```

Check:
- Valid JSON array
- Each object has: handleId, service, resolvedName (string or null)

---

## 6. Send (skip in CI — sends real messages)

**Only run these if the user explicitly approves sending test messages.**

### 6a. Mutual exclusivity

```bash
nanomsg send --to "+1234567890" --chat-id 123 --text "test"
```

Check:
- Error: "send requires --chat-id or --to, not both"

### 6b. Missing text

```bash
nanomsg send --to "+1234567890"
```

Check:
- Error: "send requires --text <message>"

### 6c. Send to chat (if approved)

Ask the user for a chat ID to send a test message to.

```bash
nanomsg send --chat-id <ID> --text "nanomsg test message, please ignore"
```

Check:
- Output: "Sent: nanomsg test message, please ignore"
- Message appears in iMessage

---

## 7. Help

### 7a. Global help

```bash
nanomsg help
```

Check:
- Lists all commands
- Shows --json and --no-contacts as global options

### 7b. Per-command help

```bash
nanomsg help chats
nanomsg help history
nanomsg help send
nanomsg help contacts
```

Check:
- Each shows usage, description, and options
- `chats` mentions --messages, --unread, --offset
- `history` mentions positional chat ID alternative
- `send` mentions --json in the Options block, mutual exclusivity note
- `contacts` mentions --query, --limit, --offset

---

## 8. Edge cases

### 8a. No arguments

```bash
nanomsg
```

Check:
- Shows usage help (same as `nanomsg help`)

### 8b. Unknown command

```bash
nanomsg foobar 2>&1
```

Check:
- Error on stderr: "nanomsg: unknown command: foobar"
- Exit code is non-zero

### 8c. Missing required args

```bash
nanomsg history 2>&1
nanomsg search 2>&1
```

Check:
- `history` errors about missing --chat-id
- `search` errors about missing query string
