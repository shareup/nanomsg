import Foundation

// MARK: - Arg parsing

struct ParsedArgs: Sendable {
    var flags: [String: String] = [:]
    var positional: [String] = []
}

func parseArgs(_ args: [String]) -> ParsedArgs {
    var result = ParsedArgs()
    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg == "--" {
            result.positional.append(contentsOf: args[(i + 1)...])
            break
        }
        if arg.hasPrefix("--") {
            let key = String(arg.dropFirst(2))
            if i + 1 < args.count && !looksLikeFlag(args[i + 1]) {
                i += 1
                result.flags[key] = args[i]
            } else {
                result.flags[key] = "true"
            }
        } else if arg.hasPrefix("-") && arg.count == 2 {
            let key = String(arg.dropFirst(1))
            if i + 1 < args.count && !looksLikeFlag(args[i + 1]) {
                i += 1
                result.flags[key] = args[i]
            } else {
                result.flags[key] = "true"
            }
        } else {
            result.positional.append(arg)
        }
        i += 1
    }
    return result
}

/// Returns true if the string looks like a flag (--foo or -X where X is a letter).
/// Values like "-1" or "-someone" are not treated as flags.
private func looksLikeFlag(_ s: String) -> Bool {
    if s.hasPrefix("--") { return true }
    if s.count == 2 && s.hasPrefix("-") {
        let ch = s[s.index(after: s.startIndex)]
        return ch.isLetter
    }
    return false
}

// MARK: - Date helpers

/// Apple's Core Data epoch: 2001-01-01 00:00:00 UTC
/// chat.db stores dates as nanoseconds since this epoch.
let appleEpoch: Date = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: DateComponents(year: 2001, month: 1, day: 1))!
}()

func dateFromAppleNanos(_ nanos: Int64) -> Date {
    let seconds = Double(nanos) / 1_000_000_000.0
    return appleEpoch.addingTimeInterval(seconds)
}

func appleNanosFromDate(_ date: Date) -> Int64 {
    let seconds = date.timeIntervalSince(appleEpoch)
    return Int64(seconds * 1_000_000_000.0)
}

func parseDate(_ string: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: string) { return d }

    let localDT = DateFormatter()
    localDT.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    localDT.timeZone = .current
    if let d = localDT.date(from: string) { return d }

    let dateOnly = DateFormatter()
    dateOnly.dateFormat = "yyyy-MM-dd"
    dateOnly.timeZone = .current
    if let d = dateOnly.date(from: string) { return d }

    return nil
}

// MARK: - Output helpers

nonisolated(unsafe) let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = .current
    return f
}()

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(isoFormatter.string(from: date))
    }
    guard let data = try? encoder.encode(value),
          let str = String(data: data, encoding: .utf8) else {
        die("JSON encoding failed")
    }
    print(str)
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("nanomsg: \(message)\n".utf8))
    exit(1)
}

// MARK: - Text cleaning

/// Strip leading control characters from attributedBody encoding artifacts.
/// iMessage attributedBody leaks a random printable byte + control byte
/// (e.g., "X\x08", "7\x02", "C\x03") before the actual text.
func cleanMessageText(_ text: String) -> String {
    var s = text
    var textStart = s.startIndex
    let limit = min(s.count, 10)
    for i in 0..<limit {
        let idx = s.index(s.startIndex, offsetBy: i)
        let scalar = s.unicodeScalars[idx]
        if scalar.value < 0x20 {
            textStart = s.index(after: idx)
        }
    }
    if textStart > s.startIndex {
        s = String(s[textStart...])
    }
    // Strip leading replacement characters
    while s.hasPrefix("\u{FFFD}") {
        s = String(s.dropFirst())
    }
    return s
}
