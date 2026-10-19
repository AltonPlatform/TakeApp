import Foundation

/// Curated DM reaction sets (Telegram-style quick bar + expanded grid).
/// Keep in sync with `ALLOWED_REACTION_EMOJIS` in message-service.
enum DMReactionCatalog {
    /// Strip shown above the bubble on long-press.
    static let quick: [String] = ["❤️", "👍", "😂", "🔥", "😮", "😢", "🙏"]

    /// Full grid opened via the chevron on the reaction bar.
    static let all: [String] = [
        "❤️", "👍", "👎", "😂", "😭", "🥰", "😍", "😘",
        "😊", "😁", "😅", "🤣", "😉", "😌", "😎", "🤩",
        "😮", "😯", "😲", "😳", "🥺", "😢", "😤", "😠",
        "😡", "🤬", "😈", "💀", "👻", "👀", "🙈", "🙉",
        "👋", "🤝", "💪", "✌️", "🤞", "👏", "🙌", "🙏",
        "👌", "🤟", "🤘", "👆", "👇", "👈", "👉", "🖖",
        "🔥", "✨", "⭐️", "🌟", "💯", "🎉", "🎊", "💥",
        "❤️‍🔥", "💔", "💕", "💗", "💖", "💘", "💝", "💞",
        "🌹", "🌸", "☀️", "🌙", "⚡️", "🌈", "🍀", "🎁",
        "🍕", "☕️", "🍺", "🎂", "⚽️", "🎮", "🐶", "🦄",
    ]

    static func contains(_ emoji: String) -> Bool {
        all.contains(emoji)
    }
}
