import Foundation

func cmdChats(db: ChatDB, resolver: ContactResolver?, args: ParsedArgs) {
    let limit = Int(args.flags["limit"] ?? "50") ?? 50
    let offset = Int(args.flags["offset"] ?? "0") ?? 0
    let unreadOnly = args.flags["unread"] == "true"
    let msgCount = Int(args.flags["messages"] ?? "3") ?? 3

    let chats = db.listChats(limit: limit, offset: offset, unreadOnly: unreadOnly)
        .map { chat -> ChatDB.ChatInfo in
            let msgs = db.history(chatId: chat.chatId, limit: msgCount)
            let resolved = resolver?.resolveMessages(msgs) ?? msgs
            return ChatDB.ChatInfo(
                chatId: chat.chatId,
                guid: chat.guid,
                displayName: chat.displayName,
                participants: chat.participants,
                participantNames: chat.participantNames,
                lastMessageDate: chat.lastMessageDate,
                lastMessageText: chat.lastMessageText,
                unreadCount: chat.unreadCount,
                isGroup: chat.isGroup,
                recentMessages: resolved
            )
        }
        .map { resolver?.resolveChat($0) ?? $0 }

    if args.flags["json"] == "true" {
        printJSON(chats)
    } else {
        printChatsText(chats)
    }
}
