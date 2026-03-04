import Foundation

func cmdHistory(db: ChatDB, resolver: ContactResolver?, args: ParsedArgs) {
    guard let chatIdStr = args.flags["chat-id"] ?? args.positional.first,
          let chatId = Int64(chatIdStr) else {
        die("history requires --chat-id <id>")
    }

    let limit = Int(args.flags["limit"] ?? "50") ?? 50
    let offset = Int(args.flags["offset"] ?? "0") ?? 0

    var sinceDate: Date? = nil
    if let s = args.flags["since"] {
        guard let d = parseDate(s) else { die("invalid --since date: \(s)") }
        sinceDate = d
    }

    let sinceRowId = args.flags["since-rowid"].flatMap { Int64($0) }

    let messages = db.history(chatId: chatId, limit: limit, offset: offset, sinceDate: sinceDate, sinceRowId: sinceRowId)
    let resolved = resolver?.resolveMessages(messages) ?? messages

    if args.flags["json"] == "true" {
        printJSON(resolved)
    } else {
        printMessagesText(resolved)
    }
}
