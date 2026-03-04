import Foundation
import SQLite3

// MARK: - Database wrapper

final class ChatDB: @unchecked Sendable {
    private let db: OpaquePointer

    init(path: String? = nil) {
        let dbPath = path ?? (NSHomeDirectory() + "/Library/Messages/chat.db")
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &handle, flags, nil)
        guard rc == SQLITE_OK, let h = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            die("Cannot open chat.db: \(msg)\nPath: \(dbPath)\nGrant Full Disk Access in System Settings > Privacy & Security.")
        }
        self.db = h
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Query runner

    private func query(_ sql: String, params: [Any] = []) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            die("SQL prepare failed: \(msg)\nSQL: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as Int:    sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:  sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            default: break
            }
        }

        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let colCount = sqlite3_column_count(stmt)
            for col in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, col))
                switch sqlite3_column_type(stmt, col) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, col)
                case SQLITE_FLOAT:   row[name] = sqlite3_column_double(stmt, col)
                case SQLITE_TEXT:    row[name] = String(cString: sqlite3_column_text(stmt, col))
                case SQLITE_BLOB:
                    let len = sqlite3_column_bytes(stmt, col)
                    if let ptr = sqlite3_column_blob(stmt, col) {
                        row[name] = Data(bytes: ptr, count: Int(len))
                    }
                default: break // NULL
                }
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - Chat queries

    struct ChatInfo: Encodable {
        let chatId: Int64
        let guid: String
        let displayName: String?
        let participants: [String]
        let participantNames: [String]
        let lastMessageDate: Date?
        let lastMessageText: String?
        let unreadCount: Int
        let isGroup: Bool
        let recentMessages: [MessageInfo]?
    }

    func listChats(limit: Int = 50, offset: Int = 0, unreadOnly: Bool = false) -> [ChatInfo] {
        // Get chats with last message info
        let sql = """
            SELECT
                c.ROWID as chat_id,
                c.guid,
                c.display_name,
                c.style as chat_style,
                (SELECT COUNT(*) FROM message m2
                 JOIN chat_message_join cmj2 ON cmj2.message_id = m2.ROWID
                 WHERE cmj2.chat_id = c.ROWID AND m2.is_read = 0 AND m2.is_from_me = 0
                   AND m2.item_type = 0 AND m2.is_empty = 0) as unread_count,
                m.ROWID as last_msg_rowid,
                m.text as last_text,
                m.date as last_date,
                m.attributedBody as last_attributed_body
            FROM chat c
            LEFT JOIN (
                SELECT cmj.chat_id,
                       MAX(m.ROWID) as max_rowid
                FROM chat_message_join cmj
                JOIN message m ON m.ROWID = cmj.message_id
                WHERE (m.associated_message_type IS NULL OR m.associated_message_type = 0)
                GROUP BY cmj.chat_id
            ) latest ON latest.chat_id = c.ROWID
            LEFT JOIN message m ON m.ROWID = latest.max_rowid
            \(unreadOnly ? """
            WHERE (SELECT COUNT(*) FROM message m3
                   JOIN chat_message_join cmj3 ON cmj3.message_id = m3.ROWID
                   WHERE cmj3.chat_id = c.ROWID AND m3.is_read = 0 AND m3.is_from_me = 0
                     AND m3.item_type = 0 AND m3.is_empty = 0) > 0
            """ : "")
            ORDER BY COALESCE(m.date, 0) DESC
            LIMIT ? OFFSET ?
            """
        let rows = query(sql, params: [limit, offset])

        // Gather all chat IDs for participant lookup
        let chatIds = rows.compactMap { $0["chat_id"] as? Int64 }
        let participantMap = fetchParticipants(chatIds: chatIds)

        return rows.map { row in
            let chatId = row["chat_id"] as! Int64
            let handles = participantMap[chatId] ?? []
            let lastDate: Date? = (row["last_date"] as? Int64).map { dateFromAppleNanos($0) }

            let lastText = extractMessageText(
                text: row["last_text"] as? String,
                attributedBody: row["last_attributed_body"] as? Data
            )

            let isGroup = (row["chat_style"] as? Int64) == 43
            let rawDisplayName = row["display_name"] as? String
            let displayName = (rawDisplayName?.isEmpty == true) ? nil : rawDisplayName

            return ChatInfo(
                chatId: chatId,
                guid: row["guid"] as? String ?? "",
                displayName: displayName,
                participants: handles,
                participantNames: [], // filled by caller with ContactResolver
                lastMessageDate: lastDate,
                lastMessageText: lastText.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) },
                unreadCount: Int(row["unread_count"] as? Int64 ?? 0),
                isGroup: isGroup,
                recentMessages: nil // filled by caller
            )
        }
    }

    private func fetchParticipants(chatIds: [Int64]) -> [Int64: [String]] {
        guard !chatIds.isEmpty else { return [:] }
        let placeholders = chatIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT chj.chat_id, h.id
            FROM chat_handle_join chj
            JOIN handle h ON h.ROWID = chj.handle_id
            WHERE chj.chat_id IN (\(placeholders))
            """
        let rows = query(sql, params: chatIds.map { $0 as Any })
        var result: [Int64: [String]] = [:]
        for row in rows {
            let chatId = row["chat_id"] as! Int64
            let handle = row["id"] as! String
            result[chatId, default: []].append(handle)
        }
        return result
    }

    // MARK: - Message queries

    struct MessageInfo: Encodable {
        let rowid: Int64
        let guid: String
        let text: String?
        let sender: String?
        let senderName: String?
        let isFromMe: Bool
        let date: Date
        let isRead: Bool
        let reactions: [ReactionInfo]?
        let attachments: [AttachmentInfo]?
        let replyToGuid: String?
        let threadOriginator: String?
    }

    struct ReactionInfo: Encodable {
        let type: String
        let sender: String
        let senderName: String?
        let date: Date?
    }

    struct AttachmentInfo: Encodable {
        let filename: String?
        let mimeType: String?
        let transferName: String?
        let totalBytes: Int64?
        let uti: String?
        let missing: Bool
    }

    func history(chatId: Int64, limit: Int = 50, offset: Int = 0, sinceDate: Date? = nil, sinceRowId: Int64? = nil) -> [MessageInfo] {
        var conditions = ["cmj.chat_id = ?", "(m.associated_message_type IS NULL OR m.associated_message_type = 0)", "m.item_type = 0", "m.is_empty = 0"]
        var params: [Any] = [chatId]

        if let d = sinceDate {
            conditions.append("m.date >= ?")
            params.append(appleNanosFromDate(d))
        }
        if let rid = sinceRowId {
            conditions.append("m.ROWID > ?")
            params.append(rid)
        }

        let whereClause = conditions.joined(separator: " AND ")

        // 1. Fetch normal messages (excluding reactions)
        let sql = """
            SELECT
                m.ROWID as rowid,
                m.guid,
                m.text,
                m.attributedBody,
                m.is_from_me,
                m.date,
                m.is_read,
                m.thread_originator_guid,
                h.id as handle_id
            FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE \(whereClause)
            ORDER BY m.date DESC, m.ROWID DESC
            LIMIT ? OFFSET ?
            """
        params.append(limit)
        params.append(offset)
        let rows = query(sql, params: params)

        // 2. Collect GUIDs to fetch reactions for
        let guids = rows.compactMap { $0["guid"] as? String }

        // 3. Fetch reactions for these messages
        let reactionsByGuid = fetchReactions(forGuids: guids, chatId: chatId)

        // 4. Fetch attachments
        let messageRowIds = rows.compactMap { $0["rowid"] as? Int64 }
        let attachmentMap = fetchAttachments(messageRowIds: messageRowIds)

        return rows.reversed().map { row in
            let rowid = row["rowid"] as! Int64
            let guid = row["guid"] as? String ?? ""
            let text = extractMessageText(
                text: row["text"] as? String,
                attributedBody: row["attributedBody"] as? Data
            )

            let isFromMe = (row["is_from_me"] as? Int64 ?? 0) == 1
            let sender = isFromMe ? nil : (row["handle_id"] as? String)
            let date = dateFromAppleNanos(row["date"] as? Int64 ?? 0)

            let reactions = computeReactions(for: guid, from: reactionsByGuid)
            let atts = attachmentMap[rowid]

            return MessageInfo(
                rowid: rowid,
                guid: guid,
                text: text,
                sender: sender,
                senderName: nil, // filled by caller
                isFromMe: isFromMe,
                date: date,
                isRead: (row["is_read"] as? Int64 ?? 0) == 1,
                reactions: reactions?.isEmpty == true ? nil : reactions,
                attachments: atts?.isEmpty == true ? nil : atts,
                replyToGuid: nil,
                threadOriginator: row["thread_originator_guid"] as? String
            )
        }
    }

    /// Fetch reactions (tapbacks) for a set of message GUIDs.
    private func fetchReactions(forGuids guids: [String], chatId: Int64) -> [String: [(type: Int64, sender: String, date: Int64?)]] {
        guard !guids.isEmpty else { return [:] }
        // Reactions reference messages via associated_message_guid with prefixes like "p:0/GUID" or "bp:GUID"
        // We search for reactions in this chat whose associated_message_guid ends with our GUIDs
        let sql = """
            SELECT
                m.associated_message_guid,
                m.associated_message_type,
                m.is_from_me,
                m.date,
                h.id as handle_id
            FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE cmj.chat_id = ?
              AND m.associated_message_type >= 2000
              AND m.associated_message_type <= 3006
            ORDER BY m.date, m.ROWID
            """
        let rows = query(sql, params: [chatId])
        let guidSet = Set(guids)

        var result: [String: [(type: Int64, sender: String, date: Int64?)]] = [:]
        for row in rows {
            guard let assocGuid = row["associated_message_guid"] as? String else { continue }
            let cleanGuid = cleanAssociatedGuid(assocGuid)
            guard guidSet.contains(cleanGuid) else { continue }
            let assocType = row["associated_message_type"] as! Int64
            let sender = row["handle_id"] as? String ?? (row["is_from_me"] as? Int64 == 1 ? "me" : "unknown")
            let date = row["date"] as? Int64
            result[cleanGuid, default: []].append((type: assocType, sender: sender, date: date))
        }
        return result
    }

    // MARK: - Unread messages

    func unreadMessages(limit: Int = 100, offset: Int = 0, chatId: Int64? = nil) -> [Int64: [MessageInfo]] {
        var conditions = ["m.is_read = 0", "m.is_from_me = 0", "m.item_type = 0", "m.is_empty = 0"]
        var params: [Any] = []

        if let cid = chatId {
            conditions.append("cmj.chat_id = ?")
            params.append(cid)
        }

        let whereClause = conditions.joined(separator: " AND ")
        let sql = """
            SELECT
                m.ROWID as rowid,
                m.guid,
                m.text,
                m.attributedBody,
                m.is_from_me,
                m.date,
                m.is_read,
                m.associated_message_type,
                h.id as handle_id,
                cmj.chat_id
            FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE \(whereClause)
              AND (m.associated_message_type IS NULL OR m.associated_message_type = 0)
            ORDER BY m.date DESC
            LIMIT ? OFFSET ?
            """
        params.append(limit)
        params.append(offset)
        let rows = query(sql, params: params)

        var grouped: [Int64: [MessageInfo]] = [:]
        for row in rows {
            let cid = row["chat_id"] as! Int64
            let text = extractMessageText(
                text: row["text"] as? String,
                attributedBody: row["attributedBody"] as? Data
            )

            let msg = MessageInfo(
                rowid: row["rowid"] as! Int64,
                guid: row["guid"] as? String ?? "",
                text: text,
                sender: row["handle_id"] as? String,
                senderName: nil,
                isFromMe: false,
                date: dateFromAppleNanos(row["date"] as? Int64 ?? 0),
                isRead: false,
                reactions: nil,
                attachments: nil,
                replyToGuid: nil,
                threadOriginator: nil
            )
            grouped[cid, default: []].append(msg)
        }
        return grouped
    }

    // MARK: - Search

    func searchMessages(query searchQuery: String, chatId: Int64? = nil, handleIds: [String]? = nil, limit: Int = 50, offset: Int = 0) -> [MessageInfo] {
        var conditions = ["m.text LIKE ?"]
        var params: [Any] = ["%\(searchQuery)%"]

        if let cid = chatId {
            conditions.append("cmj.chat_id = ?")
            params.append(cid)
        }

        if let handles = handleIds {
            if handles.isEmpty {
                // --from specified but no matching handles — return no results
                return []
            }
            let placeholders = handles.map { _ in "?" }.joined(separator: ",")
            conditions.append("h.id IN (\(placeholders))")
            for h in handles { params.append(h) }
        }

        // Exclude reactions and system messages from search results
        conditions.append("(m.associated_message_type IS NULL OR m.associated_message_type = 0)")
        conditions.append("m.item_type = 0")
        conditions.append("m.is_empty = 0")

        let whereClause = conditions.joined(separator: " AND ")
        let sql = """
            SELECT
                m.ROWID as rowid,
                m.guid,
                m.text,
                m.attributedBody,
                m.is_from_me,
                m.date,
                m.is_read,
                h.id as handle_id,
                cmj.chat_id
            FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE \(whereClause)
            ORDER BY m.date DESC
            LIMIT ? OFFSET ?
            """
        params.append(limit)
        params.append(offset)
        let rows = query(sql, params: params)

        return rows.compactMap { row -> MessageInfo? in
            let text = extractMessageText(
                text: row["text"] as? String,
                attributedBody: row["attributedBody"] as? Data
            )

            let isFromMe = (row["is_from_me"] as? Int64 ?? 0) == 1
            return MessageInfo(
                rowid: row["rowid"] as! Int64,
                guid: row["guid"] as? String ?? "",
                text: text,
                sender: isFromMe ? nil : (row["handle_id"] as? String),
                senderName: nil,
                isFromMe: isFromMe,
                date: dateFromAppleNanos(row["date"] as? Int64 ?? 0),
                isRead: (row["is_read"] as? Int64 ?? 0) == 1,
                reactions: nil,
                attachments: nil,
                replyToGuid: nil,
                threadOriginator: nil
            )
        }
    }

    // MARK: - Contacts (handles)

    struct HandleInfo: Encodable {
        let handleId: String
        let service: String
        let resolvedName: String?
    }

    func allHandles(search: String? = nil, limit: Int? = nil, offset: Int = 0) -> [HandleInfo] {
        var sql = "SELECT id, service FROM handle"
        var params: [Any] = []
        if let q = search {
            sql += " WHERE id LIKE ?"
            params.append("%\(q)%")
        }
        sql += " ORDER BY id"
        if let lim = limit {
            sql += " LIMIT ? OFFSET ?"
            params.append(lim)
            params.append(offset)
        }
        let rows = query(sql, params: params)
        return rows.map { row in
            HandleInfo(
                handleId: row["id"] as? String ?? "",
                service: row["service"] as? String ?? "",
                resolvedName: nil // filled by caller
            )
        }
    }

    // MARK: - Chat lookup

    func chatDisplayName(chatId: Int64) -> String? {
        let rows = query("SELECT display_name FROM chat WHERE ROWID = ?", params: [chatId])
        return rows.first?["display_name"] as? String
    }

    func chatGuid(chatId: Int64) -> String? {
        let rows = query("SELECT guid FROM chat WHERE ROWID = ?", params: [chatId])
        return rows.first?["guid"] as? String
    }

    func chatParticipants(chatId: Int64) -> [String] {
        let sql = """
            SELECT h.id FROM chat_handle_join chj
            JOIN handle h ON h.ROWID = chj.handle_id
            WHERE chj.chat_id = ?
            """
        return query(sql, params: [chatId]).compactMap { $0["id"] as? String }
    }

    // MARK: - Attachments

    private func fetchAttachments(messageRowIds: [Int64]) -> [Int64: [AttachmentInfo]] {
        guard !messageRowIds.isEmpty else { return [:] }
        let placeholders = messageRowIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT maj.message_id, a.filename, a.mime_type, a.transfer_name, a.total_bytes, a.uti
            FROM message_attachment_join maj
            JOIN attachment a ON a.ROWID = maj.attachment_id
            WHERE maj.message_id IN (\(placeholders))
            """
        let rows = query(sql, params: messageRowIds.map { $0 as Any })
        var result: [Int64: [AttachmentInfo]] = [:]
        for row in rows {
            let msgId = row["message_id"] as! Int64
            let rawFilename = row["filename"] as? String
            let missing: Bool
            if let fn = rawFilename {
                let expanded = fn.hasPrefix("~") ? NSHomeDirectory() + fn.dropFirst() : fn
                missing = !FileManager.default.fileExists(atPath: expanded)
            } else {
                missing = true
            }
            let att = AttachmentInfo(
                filename: rawFilename,
                mimeType: row["mime_type"] as? String,
                transferName: row["transfer_name"] as? String,
                totalBytes: row["total_bytes"] as? Int64,
                uti: row["uti"] as? String,
                missing: missing
            )
            result[msgId, default: []].append(att)
        }
        return result
    }

    // MARK: - Reaction helpers

    private func cleanAssociatedGuid(_ guid: String) -> String {
        // associated_message_guid has formats like "p:0/GUID" or "bp:GUID"
        if let slashIdx = guid.firstIndex(of: "/") {
            return String(guid[guid.index(after: slashIdx)...])
        }
        if guid.hasPrefix("bp:") {
            return String(guid.dropFirst(3))
        }
        return guid
    }

    private func computeReactions(for guid: String, from map: [String: [(type: Int64, sender: String, date: Int64?)]]) -> [ReactionInfo]? {
        guard let entries = map[guid] else { return nil }

        // Track active reactions: key is (type_base, sender), value is (type string, date)
        var active: [String: (typeName: String, date: Int64?)] = [:]

        for entry in entries {
            let type = entry.type
            let sender = entry.sender

            if type >= 2000 && type <= 2006 {
                // Add reaction
                let typeName = tapbackName(type)
                active["\(type):\(sender)"] = (typeName: typeName, date: entry.date)
            } else if type >= 3000 && type <= 3006 {
                // Remove reaction (3000 removes 2000, etc.)
                let addType = type - 1000
                active.removeValue(forKey: "\(addType):\(sender)")
            }
        }

        return active.map { key, value in
            let sender = String(key.split(separator: ":").dropFirst().joined(separator: ":"))
            let date: Date? = value.date.map { dateFromAppleNanos($0) }
            return ReactionInfo(type: value.typeName, sender: sender, senderName: nil, date: date)
        }
    }

    private func tapbackName(_ type: Int64) -> String {
        switch type {
        case 2000: return "love"
        case 2001: return "like"
        case 2002: return "dislike"
        case 2003: return "laugh"
        case 2004: return "emphasis"
        case 2005: return "question"
        case 2006: return "emoji"
        default:   return "unknown"
        }
    }
}

// MARK: - Message text extraction

/// Extract and clean message text, falling through to attributedBody as needed.
/// Handles the iMessage control-char artifact: text column may contain just
/// "X\x08" (printable + control) with the real text in attributedBody.
func extractMessageText(text rawText: String?, attributedBody: Data?) -> String? {
    // 1. Try the text column first
    if let t = rawText, !t.isEmpty {
        let cleaned = cleanMessageText(t)
        // If cleaning produced meaningful text (not just 1-2 artifact chars), use it
        if cleaned.count > 2 { return cleaned }
        // Short results might be artifacts — try attributedBody before giving up
        if let blob = attributedBody, let fromBlob = extractTextFromAttributedBody(blob) {
            let cleanedBlob = cleanMessageText(fromBlob)
            if !cleanedBlob.isEmpty { return cleanedBlob }
        }
        // Fall back to the short cleaned text if attributedBody didn't help
        if !cleaned.isEmpty { return cleaned }
    }

    // 2. text was nil/empty — try attributedBody
    if let blob = attributedBody, let fromBlob = extractTextFromAttributedBody(blob) {
        let cleaned = cleanMessageText(fromBlob)
        if !cleaned.isEmpty { return cleaned }
    }

    return nil
}

// MARK: - attributedBody text extraction

/// Extract plain text from the attributedBody blob.
/// The blob is in Apple's legacy `typedstream` format (not NSKeyedArchiver).
/// The text is stored as a counted UTF-8 string after the NSString class info.
func extractTextFromAttributedBody(_ data: Data) -> String? {
    // The typedstream format stores the string with a length prefix.
    // After the class hierarchy markers (NSMutableAttributedString, etc.),
    // the actual text appears as a length-prefixed byte sequence.
    //
    // Strategy: find "NSString" marker, then scan forward for a length-prefixed
    // string. The length encoding uses:
    //   - Single byte if length < 128
    //   - 0x81 + 2-byte little-endian if length < 32768
    //   - 0x82 + 4-byte little-endian for larger

    guard let nsStringRange = data.range(of: Data("NSString".utf8)) else {
        return nil
    }

    // Typedstream layout after "NSString":
    //   01 (version) 94|95 (end marker) 84 01 XX (artifact byte)
    //   Then: length-prefixed UTF-8 string (the actual text)
    // Skip the 5 metadata bytes to land on the length prefix.
    let textStart = nsStringRange.upperBound + 5
    guard textStart < data.count else { return nil }

    // Try extended-length first (0x81 = 2-byte LE, 0x82 = 4-byte LE)
    if let result = readLengthPrefixedString(data, at: textStart) {
        return result
    }

    // Try single-byte length
    let len = Int(data[textStart])
    if len > 0 && len < 128 {
        let strStart = textStart + 1
        if strStart + len <= data.count {
            return String(data: data[strStart..<(strStart + len)], encoding: .utf8)
        }
    }

    return nil
}

private func readLengthPrefixedString(_ data: Data, at offset: Int) -> String? {
    guard offset < data.count else { return nil }
    let marker = data[offset]

    var length: Int
    var strStart: Int

    if marker == 0x81 && offset + 3 <= data.count {
        // 2-byte length, little-endian
        length = Int(data[offset + 1]) | (Int(data[offset + 2]) << 8)
        strStart = offset + 3
    } else if marker == 0x82 && offset + 5 <= data.count {
        // 4-byte length, little-endian
        length = Int(data[offset + 1]) | (Int(data[offset + 2]) << 8) |
                 (Int(data[offset + 3]) << 16) | (Int(data[offset + 4]) << 24)
        strStart = offset + 5
    } else {
        return nil
    }

    guard length > 0 && length < 1_000_000 && strStart + length <= data.count else { return nil }
    return String(data: data[strStart..<(strStart + length)], encoding: .utf8)
}
