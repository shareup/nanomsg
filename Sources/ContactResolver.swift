import Foundation
import Contacts

final class ContactResolver: @unchecked Sendable {
    /// Normalized phone (last 10 digits) → full name
    private var phoneToName: [String: String] = [:]
    /// Lowercase email → full name
    private var emailToName: [String: String] = [:]

    init() {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                guard !name.isEmpty else { return }

                for phone in contact.phoneNumbers {
                    let normalized = self.normalizePhone(phone.value.stringValue)
                    if !normalized.isEmpty {
                        self.phoneToName[normalized] = name
                    }
                }
                for email in contact.emailAddresses {
                    self.emailToName[(email.value as String).lowercased()] = name
                }
            }
        } catch {
            // Contacts access denied or failed — continue with empty maps.
            // Names will just show raw handles.
            FileHandle.standardError.write(Data("nanomsg: contacts unavailable: \(error.localizedDescription)\n".utf8))
        }
    }

    /// Resolve a handle identifier (phone or email) to a contact name.
    func resolve(_ identifier: String) -> String? {
        // Try email first (cheap)
        if identifier.contains("@") {
            return emailToName[identifier.lowercased()]
        }
        // Try phone
        let normalized = normalizePhone(identifier)
        if !normalized.isEmpty {
            return phoneToName[normalized]
        }
        return nil
    }

    /// Given a name query, return all handle identifiers that match.
    func handlesMatching(name query: String) -> [String] {
        let q = query.lowercased()
        var results: [String] = []

        // Reverse lookup: find all phones/emails whose resolved name contains the query
        for (phone, name) in phoneToName {
            if name.lowercased().contains(q) {
                // Return the original phone — but we only store normalized.
                // The caller will need to match against handle IDs in the DB.
                results.append(phone)
            }
        }
        for (email, name) in emailToName {
            if name.lowercased().contains(q) {
                results.append(email)
            }
        }
        return results
    }

    /// Resolve handles for an entire message list, returning updated messages.
    func resolveMessages(_ messages: [ChatDB.MessageInfo]) -> [ChatDB.MessageInfo] {
        messages.map { msg in
            ChatDB.MessageInfo(
                rowid: msg.rowid, guid: msg.guid, text: msg.text,
                sender: msg.sender, senderName: msg.sender.flatMap { resolve($0) },
                isFromMe: msg.isFromMe, date: msg.date, isRead: msg.isRead,
                reactions: msg.reactions.map { resolveReactions($0) },
                attachments: msg.attachments,
                replyToGuid: msg.replyToGuid, threadOriginator: msg.threadOriginator
            )
        }
    }

    /// Resolve sender names in reactions.
    func resolveReactions(_ reactions: [ChatDB.ReactionInfo]) -> [ChatDB.ReactionInfo] {
        reactions.map { r in
            ChatDB.ReactionInfo(
                type: r.type,
                sender: r.sender,
                senderName: resolve(r.sender),
                date: r.date
            )
        }
    }

    /// Resolve participant names for a chat.
    func resolveChat(_ chat: ChatDB.ChatInfo) -> ChatDB.ChatInfo {
        ChatDB.ChatInfo(
            chatId: chat.chatId,
            guid: chat.guid,
            displayName: chat.displayName,
            participants: chat.participants,
            participantNames: chat.participants.map { resolve($0) ?? $0 },
            lastMessageDate: chat.lastMessageDate,
            lastMessageText: chat.lastMessageText,
            unreadCount: chat.unreadCount,
            isGroup: chat.isGroup,
            recentMessages: chat.recentMessages.map { resolveMessages($0) }
        )
    }

    // MARK: - Phone normalization

    /// Strip non-digits and keep last 10 digits for comparison.
    private func normalizePhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count >= 10 {
            return String(digits.suffix(10))
        }
        return digits
    }
}
