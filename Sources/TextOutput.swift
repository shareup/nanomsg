import Foundation

// MARK: - Date formatting

private let relativeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.doesRelativeDateFormatting = true
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

private func formatDate(_ date: Date) -> String {
    relativeFormatter.string(from: date)
}

// MARK: - Chats

func printChatsText(_ chats: [ChatDB.ChatInfo]) {
    if chats.isEmpty {
        print("No conversations found.")
        return
    }

    for chat in chats {
        let name = sanitize(chat.displayName
            ?? chat.participantNames.joined(separator: ", ").nonEmpty
            ?? chat.participants.joined(separator: ", "))

        var meta: [String] = ["#\(chat.chatId)"]
        if chat.unreadCount > 0 {
            meta.append("\(chat.unreadCount) unread")
        }
        if chat.isGroup {
            meta.append("group")
        }

        print("\(name)  (\(meta.joined(separator: ", ")))")

        if let messages = chat.recentMessages, !messages.isEmpty {
            for msg in messages {
                let sender = sanitize(msg.isFromMe ? "You" : (msg.senderName ?? msg.sender ?? "Unknown"))
                let date = formatDate(msg.date)
                let text = msg.text.map { "  \(truncate(sanitize($0), to: 60))" } ?? ""
                print("  \(sender), \(date)\(text)")
            }
        } else if let date = chat.lastMessageDate {
            let preview = chat.lastMessageText.map { "  \(truncate(sanitize($0), to: 80))" } ?? ""
            print("  \(formatDate(date))\(preview)")
        }
        print()
    }
}

// MARK: - Messages (history + search)

func printMessagesText(_ messages: [ChatDB.MessageInfo]) {
    if messages.isEmpty {
        print("No messages found.")
        return
    }

    for msg in messages {
        let sender = sanitize(msg.isFromMe ? "You" : (msg.senderName ?? msg.sender ?? "Unknown"))
        let date = formatDate(msg.date)

        print("\(sender)  \(date)")

        if let text = msg.text {
            let clean = sanitize(text)
            for line in clean.split(separator: "\n", omittingEmptySubsequences: false) {
                print("  \(line)")
            }
        }

        if let reactions = msg.reactions, !reactions.isEmpty {
            let grouped = Dictionary(grouping: reactions, by: { $0.type })
            let parts = grouped.map { type, reactors in
                let names = reactors.map { sanitize($0.senderName ?? $0.sender) }.joined(separator: ", ")
                return "\(type) (\(names))"
            }
            print("  [\(parts.joined(separator: "  "))]")
        }

        if let atts = msg.attachments, !atts.isEmpty {
            for att in atts {
                let name = sanitize(att.transferName ?? att.filename ?? "attachment")
                let size = att.totalBytes.map { formatBytes($0) } ?? ""
                let missing = att.missing ? " (missing)" : ""
                print("  📎 \(name)\(size.isEmpty ? "" : " (\(size))")\(missing)")
            }
        }

        print()
    }
}

// MARK: - Unread

func printUnreadText(_ groups: [UnreadGroup]) {
    if groups.isEmpty {
        print("No unread messages.")
        return
    }

    for group in groups {
        let name = sanitize(group.chatName ?? group.participants.joined(separator: ", "))
        print("── \(name)  (#\(group.chatId), \(group.messages.count) unread) ──")
        print()

        for msg in group.messages {
            let sender = sanitize(msg.senderName ?? msg.sender ?? "Unknown")
            let date = formatDate(msg.date)
            print("  \(sender)  \(date)")
            if let text = msg.text {
                let clean = sanitize(text)
                for line in clean.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("    \(line)")
                }
            }
            print()
        }
    }
}

// MARK: - Handles (contacts)

func printHandlesText(_ handles: [ChatDB.HandleInfo]) {
    if handles.isEmpty {
        print("No handles found.")
        return
    }

    // Find column widths
    let maxHandle = max(handles.map { $0.handleId.count }.max() ?? 0, 6)
    let maxService = max(handles.map { $0.service.count }.max() ?? 0, 7)

    print("HANDLE".padding(toLength: maxHandle + 2, withPad: " ", startingAt: 0)
        + "SERVICE".padding(toLength: maxService + 2, withPad: " ", startingAt: 0)
        + "NAME")

    for h in handles {
        let name = h.resolvedName ?? ""
        print(h.handleId.padding(toLength: maxHandle + 2, withPad: " ", startingAt: 0)
            + h.service.padding(toLength: maxService + 2, withPad: " ", startingAt: 0)
            + name)
    }
}

// MARK: - Send result

func printSendResultText(_ result: [String: String]) {
    if let text = result["text"] {
        print("Sent: \(text)")
    } else {
        print("Sent.")
    }
}

// MARK: - Helpers

/// Strip control characters and ANSI escape sequences from text before printing
/// to the terminal. Preserves newlines and tabs.
private func sanitize(_ s: String) -> String {
    var result = ""
    var i = s.startIndex
    while i < s.endIndex {
        let ch = s[i]
        if ch == "\u{1b}" {
            // Skip ANSI escape sequence: ESC followed by [ then params then letter
            i = s.index(after: i)
            if i < s.endIndex && s[i] == "[" {
                i = s.index(after: i)
                while i < s.endIndex && !s[i].isLetter { i = s.index(after: i) }
                if i < s.endIndex { i = s.index(after: i) }
            }
            continue
        }
        if let scalar = ch.unicodeScalars.first,
           (scalar.value < 0x20 || scalar.value == 0x7f),
           ch != "\n" && ch != "\t" {
            // Skip control characters except newline and tab
            i = s.index(after: i)
            continue
        }
        result.append(ch)
        i = s.index(after: i)
    }
    return result
}

private func truncate(_ s: String, to maxLen: Int) -> String {
    let flat = s.replacingOccurrences(of: "\n", with: " ")
    if flat.count <= maxLen { return flat }
    return String(flat.prefix(maxLen - 1)) + "…"
}

private func formatBytes(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
    return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
