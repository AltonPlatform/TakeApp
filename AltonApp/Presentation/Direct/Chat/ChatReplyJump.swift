import Foundation

enum ChatReplyJump {
    /// Row id to scroll to when tapping a reply quote. Nil when the original is missing or deleted.
    static func targetRowID(reply: DMMessage?, rows: [ChatRow]) -> String? {
        guard let reply, reply.deletedAt == nil else { return nil }
        let preferred = reply.clientMsgID.isEmpty ? reply.id : reply.clientMsgID
        if rows.contains(where: { $0.id == preferred }) {
            return preferred
        }
        if let match = rows.first(where: { $0.message.id == reply.id || $0.message.seq == reply.seq }) {
            return match.id
        }
        return nil
    }
}
