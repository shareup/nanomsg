import Foundation

func run() async {
    let rawArgs = Array(CommandLine.arguments.dropFirst())
    let command = rawArgs.first

    if command == nil || command == "--help" || command == "-h" || command == "help" {
        if let sub = rawArgs.dropFirst().first {
            printCommandHelp(sub)
        } else {
            printUsage()
        }
        exit(0)
    }

    let parsed = parseArgs(Array(rawArgs.dropFirst()))

    // Commands that don't need DB/contacts
    if command == "send" {
        cmdSend(args: parsed)
        return
    }

    let db = ChatDB()
    let skipContacts = parsed.flags["no-contacts"] == "true"
    let resolver = skipContacts ? nil : ContactResolver()

    switch command {
    case "chats":    cmdChats(db: db, resolver: resolver, args: parsed)
    case "unread":   cmdUnread(db: db, resolver: resolver, args: parsed)
    case "history":  cmdHistory(db: db, resolver: resolver, args: parsed)
    case "search":   cmdSearch(db: db, resolver: resolver, args: parsed)
    case "contacts": cmdContacts(db: db, resolver: resolver, args: parsed)
    default:         die("unknown command: \(command!)")
    }
}

func printUsage() {
    print("""
    Usage: nanomsg <command> [options]

    Commands:
      chats       List conversations
      unread      Unread messages by chat
      history     Message history for a chat
      search      Search messages
      contacts    All handles with resolved names
      send        Send a message
      help        Show help for a command

    Global Options:
      --json          Output JSON instead of human-readable text
      --no-contacts   Skip contact name resolution

    Run 'nanomsg help <command>' for details on a specific command.
    """)
}

func printCommandHelp(_ command: String) {
    switch command {
    case "chats":
        print("""
        Usage: nanomsg chats [options]

        List conversations sorted by most recent message.

        Options:
          --limit N       Max conversations to return (default: 50)
          --offset N      Skip first N results (for pagination)
          --unread        Only show chats with unread messages
          --messages N    Recent messages per chat (default: 3)
          --json          Output JSON instead of human-readable text
          --no-contacts   Skip contact name resolution
        """)
    case "unread":
        print("""
        Usage: nanomsg unread [options]

        Show unread messages grouped by chat.

        Options:
          --limit N       Max messages to return (default: 100)
          --offset N      Skip first N results (for pagination)
          --chat-id N     Only show unread for this chat
          --json          Output JSON instead of human-readable text
          --no-contacts   Skip contact name resolution
        """)
    case "history":
        print("""
        Usage: nanomsg history (--chat-id N | N) [options]

        Show message history for a chat, ordered oldest to newest.

        Options:
          --chat-id N     Chat ID (or pass as positional argument)
          --limit N       Max messages to return (default: 50)
          --offset N      Skip first N results (for pagination)
          --since DATE    Only messages after this date
          --since-rowid N Only messages after this row ID
          --json          Output JSON instead of human-readable text
          --no-contacts   Skip contact name resolution

        Dates: ISO 8601 (2026-02-14T10:00:00) or date-only (2026-02-14)
        """)
    case "search":
        print("""
        Usage: nanomsg search <query> [options]

        Search message text across all chats.

        Options:
          --chat-id N     Limit search to this chat
          --from NAME     Filter by sender name or handle
          --limit N       Max results to return (default: 50)
          --offset N      Skip first N results (for pagination)
          --json          Output JSON instead of human-readable text
          --no-contacts   Skip contact name resolution
        """)
    case "contacts":
        print("""
        Usage: nanomsg contacts [query] [options]

        List all known handles (phone numbers and emails) with resolved
        contact names. Optionally search by handle or contact name.

        Options:
          --query TEXT    Search handles and names (also accepts positional arg)
          --limit N       Max results to return
          --offset N      Skip first N results (for pagination)
          --json          Output JSON instead of human-readable text
          --no-contacts   Skip contact name resolution
        """)
    case "send":
        print("""
        Usage: nanomsg send --text "message" (--to <addr> | --chat-id N)

        Send a message via Messages.app.

        Options:
          --to ADDR       Phone number or email to send to
          --chat-id N     Chat ID to send to (for group chats or existing conversations)
          --text TEXT      Message text (required)
          --json          Output JSON instead of human-readable text

        Either --to or --chat-id is required (not both). Phone numbers should
        include country code (e.g., +1 for US).
        """)
    default:
        die("unknown command: \(command)")
    }
}

await run()
