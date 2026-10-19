import SwiftUI

enum EmojiCatalog {
    struct Section: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let symbols: [String]
    }

    private static let ranges: [(id: String, title: String, spans: [(UInt32, UInt32)])] = [
        ("smileys", "Smileys", [(0x1F600, 0x1F64F)]),
        ("people", "People", [(0x1F466, 0x1F487), (0x1F9D0, 0x1F9FF)]),
        ("animals", "Animals", [(0x1F400, 0x1F43F), (0x1F980, 0x1F9AE)]),
        ("food", "Food", [(0x1F32D, 0x1F37F)]),
        ("travel", "Travel", [(0x1F680, 0x1F6FF)]),
        ("objects", "Objects", [(0x1F4A0, 0x1F4FF)]),
        ("symbols", "Symbols", [(0x2600, 0x27BF)]),
    ]

    static func build() -> [Section] {
        var sections: [Section] = []
        for range in ranges {
            var symbols: [String] = []
            for span in range.spans {
                var scalar = span.0
                while scalar <= span.1 {
                    if let unicode = Unicode.Scalar(scalar) {
                        let character = Character(unicode)
                        if character.unicodeScalars.contains(where: \.properties.isEmojiPresentation) {
                            symbols.append(String(character))
                        }
                    }
                    scalar += 1
                }
            }
            if !symbols.isEmpty {
                sections.append(Section(id: range.id, title: range.title, symbols: symbols))
            }
        }
        let flags = flagSymbols()
        if !flags.isEmpty {
            sections.append(Section(id: "flags", title: "Flags", symbols: flags))
        }
        return sections
    }

    private static func flagSymbols() -> [String] {
        var flags: [String] = []
        for first in 0x1F1E6...0x1F1FF {
            for second in 0x1F1E6...0x1F1FF {
                guard let a = Unicode.Scalar(first), let b = Unicode.Scalar(second) else { continue }
                let pair = String(Character(a)) + String(Character(b))
                if a.properties.isEmoji && b.properties.isEmoji {
                    flags.append(pair)
                }
            }
        }
        return flags
    }
}

actor EmojiCatalogStore {
    static let shared = EmojiCatalogStore()
    private var cached: [EmojiCatalog.Section]?

    func sections() async -> [EmojiCatalog.Section] {
        if let cached { return cached }
        let built = await Task.detached(priority: .utility) {
            EmojiCatalog.build()
        }.value
        cached = built
        return built
    }
}

enum EmojiRecents {
    private static let key = "chat.emoji.recents"
    static let limit = 32

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ emoji: String) {
        var list = load().filter { $0 != emoji }
        list.insert(emoji, at: 0)
        if list.count > limit {
            list = Array(list.prefix(limit))
        }
        UserDefaults.standard.set(list, forKey: key)
    }
}

struct EmojiGridView: View {
    var onInsert: (String) -> Void

    @State private var sections: [EmojiCatalog.Section] = []
    @State private var recents: [String] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !recents.isEmpty {
                    section(title: "Recent", symbols: recents)
                }
                if sections.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(sections) { section in
                        self.section(title: section.title, symbols: section.symbols)
                    }
                }
            }
            .padding(12)
        }
        .task {
            recents = EmojiRecents.load()
            sections = await EmojiCatalogStore.shared.sections()
        }
    }

    private func section(title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(symbols, id: \.self) { emoji in
                    Button {
                        EmojiRecents.record(emoji)
                        recents = EmojiRecents.load()
                        onInsert(emoji)
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
