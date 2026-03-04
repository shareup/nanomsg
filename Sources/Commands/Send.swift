import Foundation

func cmdSend(args: ParsedArgs) {
    guard let text = args.flags["text"] else {
        die("send requires --text <message>")
    }

    let chatId = args.flags["chat-id"]
    let toAddr = args.flags["to"]

    if chatId != nil && toAddr != nil {
        die("send requires --chat-id or --to, not both")
    }
    guard chatId != nil || toAddr != nil else {
        die("send requires --chat-id <id> or --to <address>")
    }

    let escapedText = escapeAppleScript(text)

    // Build AppleScript
    let script: String
    if let to = toAddr {
        // Send to a specific address (phone/email)
        let escapedTo = escapeAppleScript(to)
        script = """
            tell application "Messages"
                set targetService to 1st account whose service type = iMessage
                set targetBuddy to participant "\(escapedTo)" of targetService
                send "\(escapedText)" to targetBuddy
            end tell
            """
    } else {
        // Send to existing chat by GUID — works for both 1:1 and group chats
        let db = ChatDB()
        guard let cid = Int64(chatId!) else { die("invalid --chat-id") }
        guard let guid = db.chatGuid(chatId: cid) else {
            die("no chat found with id \(chatId!)")
        }
        let escapedGuid = escapeAppleScript(guid)

        script = """
            tell application "Messages"
                set targetChat to chat id "\(escapedGuid)"
                send "\(escapedText)" to targetChat
            end tell
            """
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", script]

    let errPipe = Pipe()
    proc.standardError = errPipe

    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        die("failed to run osascript: \(error.localizedDescription)")
    }

    if proc.terminationStatus != 0 {
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        die("osascript failed (exit \(proc.terminationStatus)): \(errStr)")
    }

    let result = ["status": "sent", "text": text]
    if args.flags["json"] == "true" {
        printJSON(result)
    } else {
        printSendResultText(result)
    }
}

/// Escape a string for safe embedding inside AppleScript double-quoted strings.
/// Handles backslash, double-quote, and control characters.
private func escapeAppleScript(_ s: String) -> String {
    var result = ""
    for ch in s {
        switch ch {
        case "\\": result += "\\\\"
        case "\"": result += "\\\""
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        default:
            if let scalar = ch.unicodeScalars.first, scalar.value < 0x20 || scalar.value == 0x7f {
                // Skip other control characters
            } else {
                result.append(ch)
            }
        }
    }
    return result
}
