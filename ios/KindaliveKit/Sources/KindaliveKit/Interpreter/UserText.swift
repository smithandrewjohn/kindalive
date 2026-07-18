// UserText — the only input: a freeform paragraph the owner typed.
// Ports kindalive/interpreter/text_input.py.

import Foundation

public struct UserText: Sendable {
    /// The paragraph.
    public let summary: String
    public let timestamp: Date
    public let source = "user"
    public let eventType = "freeform"

    public init(summary: String, timestamp: Date = Date()) {
        self.summary = summary
        self.timestamp = timestamp
    }
}
