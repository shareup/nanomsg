import Foundation

func cmdSearch(db: ChatDB, resolver: ContactResolver?, args: ParsedArgs) {
    guard let query = args.positional.first else {
        die("search requires a query string")
    }

    let limit = Int(args.flags["limit"] ?? "50") ?? 50
    let offset = Int(args.flags["offset"] ?? "0") ?? 0
    let chatId = args.flags["chat-id"].flatMap { Int64($0) }

    // --from matches contact name or handle ID
    var handleIds: [String]? = nil
    if let fromQuery = args.flags["from"] {
        // First check if it matches known handle identifiers from contacts
        let matchedHandles = resolver?.handlesMatching(name: fromQuery) ?? []

        if matchedHandles.isEmpty {
            // Treat as a raw handle identifier pattern — search DB handles directly
            let allHandles = db.allHandles()
            let matching = allHandles.filter {
                $0.handleId.localizedCaseInsensitiveContains(fromQuery)
            }.map { $0.handleId }
            // Set to matching results (empty array = no matches = no results)
            handleIds = matching
        } else {
            // Need to find actual handle IDs (phone/email) from the normalized matches
            let allHandles = db.allHandles()
            let normalizedMatches = Set(matchedHandles)
            handleIds = allHandles.filter { handle in
                // Check if this handle's normalized form is in our matches
                let digits = handle.handleId.filter { $0.isNumber }
                let norm = digits.count >= 10 ? String(digits.suffix(10)) : digits
                if normalizedMatches.contains(norm) { return true }
                if normalizedMatches.contains(handle.handleId.lowercased()) { return true }
                return false
            }.map { $0.handleId }
        }
    }

    let messages = db.searchMessages(query: query, chatId: chatId, handleIds: handleIds, limit: limit, offset: offset)
    let resolved = resolver?.resolveMessages(messages) ?? messages

    if args.flags["json"] == "true" {
        printJSON(resolved)
    } else {
        printMessagesText(resolved)
    }
}
