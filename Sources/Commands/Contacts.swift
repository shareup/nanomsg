import Foundation

func cmdContacts(db: ChatDB, resolver: ContactResolver?, args: ParsedArgs) {
    let search = args.flags["query"] ?? args.positional.first
    let limit = args.flags["limit"].flatMap { Int($0) }
    let offset = Int(args.flags["offset"] ?? "0") ?? 0

    let allHandles = db.allHandles()
    var resolved = allHandles.map { h in
        ChatDB.HandleInfo(
            handleId: h.handleId,
            service: h.service,
            resolvedName: resolver?.resolve(h.handleId)
        )
    }

    // Filter by search query (matches handle ID or resolved name)
    if let q = search {
        resolved = resolved.filter { h in
            if h.handleId.localizedCaseInsensitiveContains(q) { return true }
            if let name = h.resolvedName, name.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
    }

    // Apply offset and limit
    if offset > 0 {
        resolved = Array(resolved.dropFirst(offset))
    }
    if let lim = limit {
        resolved = Array(resolved.prefix(lim))
    }

    if args.flags["json"] == "true" {
        printJSON(resolved)
    } else {
        printHandlesText(resolved)
    }
}
