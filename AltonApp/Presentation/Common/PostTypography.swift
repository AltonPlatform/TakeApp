import SwiftUI
import UIKit

enum PostTypography {
    static func regular(_ size: CGFloat, relativeTo _: Font.TextStyle) -> Font {
        .system(size: size, weight: .regular)
    }

    static func medium(_ size: CGFloat, relativeTo _: Font.TextStyle) -> Font {
        .system(size: size, weight: .medium)
    }

    static func semiBold(_ size: CGFloat, relativeTo _: Font.TextStyle) -> Font {
        .system(size: size, weight: .semibold)
    }

    static var name: Font { semiBold(14, relativeTo: .subheadline) }
    static var handle: Font { regular(14, relativeTo: .subheadline) }
    static var body: Font { regular(14, relativeTo: .body) }
    static var showMore: Font { medium(14, relativeTo: .body) }
    static var count: Font { medium(14, relativeTo: .subheadline) }
    static var repostLabel: Font { semiBold(12, relativeTo: .caption) }

    static var uiBodyFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }

    static var uiNameFont: UIFont {
        UIFont.systemFont(ofSize: 14, weight: .semibold)
    }

    static var uiHandleFont: UIFont {
        UIFont.systemFont(ofSize: 14, weight: .regular)
    }

    static var uiShowMoreFont: UIFont {
        UIFont.systemFont(ofSize: 14, weight: .medium)
    }
}

typealias PostFont = PostTypography

enum PostColors {
    /// System label: black in light mode, white in dark mode.
    static let labelPrimary = Color.primary
    static let labelSecondary = Color("PostLabelSecondary")
    static let handle = Color("PostHandle")
    static let border = Color("PostBorder")
    static let showMore = Color("PostShowMore")
    static let repostLabel = Color("PostRepostLabel")
    static let mediaPlaceholder = Color("PostBorder")

    static var uiLabelPrimary: UIColor { .label }
    static var uiHandle: UIColor { UIColor(named: "PostHandle") ?? .secondaryLabel }
    static var uiShowMore: UIColor { UIColor(named: "PostShowMore") ?? .systemBlue }
    static var uiBorder: UIColor { UIColor(named: "PostBorder") ?? .separator }
}

typealias PostColor = PostColors
