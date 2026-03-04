import Foundation

struct UnreadGroup: Encodable {
    let chatId: Int64
    let chatName: String?
    let participants: [String]
    let messages: [ChatDB.MessageInfo]
}

func cmdUnread(db: ChatDB, resolver: ContactResolver?, args: ParsedArgs) {
    let limit = Int(args.flags["limit"] ?? "100") ?? 100
    let offset = Int(args.flags["offset"] ?? "0") ?? 0
    let chatId = args.flags["chat-id"].flatMap { Int64($0) }

    let grouped = db.unreadMessages(limit: limit, offset: offset, chatId: chatId)

    var results: [UnreadGroup] = []
    for (cid, messages) in grouped {
        let participants = db.chatParticipants(chatId: cid)
        let rawDisplayName = db.chatDisplayName(chatId: cid)
        let displayName = (rawDisplayName?.isEmpty == true) ? nil : rawDisplayName
        let resolvedName = displayName ?? participants.compactMap { resolver?.resolve($0) ?? $0 }.joined(separator: ", ")
        let resolved = resolver?.resolveMessages(messages) ?? messages
        results.append(UnreadGroup(
            chatId: cid,
            chatName: resolvedName.isEmpty ? nil : resolvedName,
            participants: participants.map { resolver?.resolve($0) ?? $0 },
            messages: resolved
        ))
    }

    // Sort by most recent message first
    results.sort { a, b in
        let aDate = a.messages.first?.date ?? .distantPast
        let bDate = b.messages.first?.date ?? .distantPast
        return aDate > bDate
    }

    if args.flags["json"] == "true" {
        printJSON(results)
    } else {
        printUnreadText(results)
    }
}
