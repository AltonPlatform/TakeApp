import CleverAdsSolutions
import SwiftUI
import UIKit

/// Native ad laid out like `TakePostView`: 12pt padding, 32pt avatar, 8pt gutters.
final class NativeAdPostCardUIView: UIView {
    private let nativeView = CASNativeView(frame: .zero)

    private let iconView = UIImageView()
    private let advertiserLabel = UILabel()
    private let sponsoredLabel = UILabel()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let mediaView = CASMediaView(frame: .zero)
    private let ctaButton = UIButton(type: .system)
    private let adChoicesView = CASChoicesView(frame: .zero)

    private let headerRow = UIStackView()
    private let contentColumn = UIStackView()
    private let rootRow = UIStackView()

    private var boundContent: NativeAdContent?
    private var mediaWidthConstraint: NSLayoutConstraint?
    private var mediaHeightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func bind(_ adContent: NativeAdContent) {
        guard !adContent.isExpired else { return }
        if boundContent === adContent {
            updateMediaSize()
            return
        }
        boundContent = adContent

        nativeView.iconView = iconView
        nativeView.advertiserView = advertiserLabel
        nativeView.headlineView = headlineLabel
        nativeView.bodyView = bodyLabel
        nativeView.mediaView = mediaView
        nativeView.callToActionView = ctaButton
        nativeView.adChoicesView = adChoicesView
        nativeView.adLabelView = sponsoredLabel

        nativeView.bindAdContent(adContent, autoPopulateText: true)

        let displayName = NativeAdCopy.displayAdvertiserName(from: adContent)
        advertiserLabel.text = displayName
        sponsoredLabel.text = "Sponsored"

        // Name lives only in the header. Hide CAS headline when it repeats it.
        headlineLabel.text = nil
        headlineLabel.isHidden = true
        let body = NativeAdCopy.contentLine(adContent.body, excluding: displayName)
        bodyLabel.text = body
        bodyLabel.isHidden = body == nil

        if let icon = adContent.icon {
            iconView.image = icon
        }
        iconView.isHidden = false
        applyCTAStyle(title: "Show More...")
        updateMediaSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMediaSize()
    }

    /// SwiftUI measures `UIViewRepresentable` with a temporary height of 0.
    /// Required 12+12 padding inside `CASNativeView` then conflicts. Floor the fit.
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let fitted = super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
        return CGSize(width: fitted.width, height: max(fitted.height, 72))
    }

    func unbind() {
        nativeView.bindAdContent(nil)
        boundContent = nil
        iconView.image = nil
    }

    private func setup() {
        backgroundColor = .clear

        nativeView.translatesAutoresizingMaskIntoConstraints = false
        nativeView.backgroundColor = .clear
        addSubview(nativeView)

        configureIcon()
        configureLabels()
        configureMedia()
        configureCTA()
        configureAdChoices()
        configureStacks()

        let mediaWidth = mediaView.widthAnchor.constraint(equalToConstant: PostMediaDesign.figmaColumn)
        let mediaHeight = mediaView.heightAnchor.constraint(equalToConstant: 160)
        mediaWidth.priority = .required
        mediaHeight.priority = .required
        mediaWidthConstraint = mediaWidth
        mediaHeightConstraint = mediaHeight

        let nativeBottom = nativeView.bottomAnchor.constraint(equalTo: bottomAnchor)
        nativeBottom.priority = .defaultHigh
        let rootBottom = rootRow.bottomAnchor.constraint(equalTo: nativeView.bottomAnchor, constant: -12)
        rootBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            nativeView.topAnchor.constraint(equalTo: topAnchor),
            nativeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            nativeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nativeBottom,

            rootRow.topAnchor.constraint(equalTo: nativeView.topAnchor, constant: 12),
            rootRow.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor, constant: 12),
            rootRow.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor, constant: -12),
            rootBottom,

            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            headerRow.widthAnchor.constraint(equalTo: contentColumn.widthAnchor),

            adChoicesView.widthAnchor.constraint(equalToConstant: 16),
            adChoicesView.heightAnchor.constraint(equalToConstant: 16),

            mediaWidth,
            mediaHeight,
        ])
    }

    private func configureIcon() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 16
        iconView.backgroundColor = PostColor.uiBorder
    }

    private func configureLabels() {
        advertiserLabel.font = PostFont.uiNameFont
        advertiserLabel.textColor = PostColor.uiLabelPrimary
        advertiserLabel.numberOfLines = 1
        advertiserLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        sponsoredLabel.font = PostFont.uiHandleFont
        sponsoredLabel.textColor = PostColor.uiHandle
        sponsoredLabel.text = "Sponsored"
        sponsoredLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        headlineLabel.font = PostFont.uiHandleFont
        headlineLabel.textColor = PostColor.uiLabelPrimary
        headlineLabel.numberOfLines = 3

        bodyLabel.font = PostFont.uiHandleFont
        bodyLabel.textColor = PostColor.uiLabelPrimary
        bodyLabel.numberOfLines = 4
    }

    private func configureMedia() {
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.layer.cornerRadius = PostMediaDesign.cornerRadius
        mediaView.layer.cornerCurve = .continuous
        mediaView.clipsToBounds = true
        mediaView.backgroundColor = PostColor.uiBorder
        mediaView.setContentHuggingPriority(.required, for: .horizontal)
        mediaView.setContentHuggingPriority(.required, for: .vertical)
        mediaView.setContentCompressionResistancePriority(.required, for: .horizontal)
        mediaView.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func configureCTA() {
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.contentHorizontalAlignment = .leading
        applyCTAStyle(title: "Show More...")
    }

    private func configureAdChoices() {
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        adChoicesView.setContentHuggingPriority(.required, for: .horizontal)
        adChoicesView.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureStacks() {
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 8
        headerRow.addArrangedSubview(advertiserLabel)
        headerRow.addArrangedSubview(sponsoredLabel)
        headerRow.addArrangedSubview(UIView())
        headerRow.addArrangedSubview(adChoicesView)

        contentColumn.axis = .vertical
        contentColumn.alignment = .leading
        contentColumn.spacing = 8
        contentColumn.addArrangedSubview(headerRow)
        contentColumn.addArrangedSubview(headlineLabel)
        contentColumn.addArrangedSubview(bodyLabel)
        contentColumn.addArrangedSubview(mediaView)
        contentColumn.addArrangedSubview(ctaButton)

        rootRow.axis = .horizontal
        rootRow.alignment = .top
        rootRow.spacing = 8
        rootRow.translatesAutoresizingMaskIntoConstraints = false
        rootRow.addArrangedSubview(iconView)
        rootRow.addArrangedSubview(contentColumn)

        nativeView.addSubview(rootRow)
    }

    private func applyCTAStyle(title: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = PostColor.uiShowMore
        config.contentInsets = .zero
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = PostFont.uiShowMoreFont
            return outgoing
        }
        ctaButton.configuration = config
        ctaButton.backgroundColor = .clear
        ctaButton.isHidden = false
    }

    private func updateMediaSize() {
        let column = mediaColumnWidth
        guard column > 1 else { return }

        guard let ad = boundContent, NativeAdCopy.hasMedia(ad) else {
            mediaView.isHidden = true
            mediaWidthConstraint?.constant = 0
            mediaHeightConstraint?.constant = 0
            return
        }

        mediaView.isHidden = false
        var aspect = ad.mediaContentAspectRatio
        if aspect <= 0, let image = ad.mediaImage, image.size.height > 0 {
            aspect = image.size.width / image.size.height
        }
        if aspect <= 0 {
            aspect = 16.0 / 9.0
        }
        let layout: PostMediaDesign.Layout = aspect < 1 ? .v1 : .h1
        let size = PostMediaDesign.displaySize(
            layout: layout,
            rawAspect: aspect,
            firstRawAspect: aspect,
            column: column
        )
        if mediaWidthConstraint?.constant != size.width {
            mediaWidthConstraint?.constant = size.width
        }
        if mediaHeightConstraint?.constant != size.height {
            mediaHeightConstraint?.constant = size.height
        }
    }

    private var mediaColumnWidth: CGFloat {
        let measured = contentColumn.bounds.width
        if measured > 1 { return measured }
        return max(bounds.width - 12 - 32 - 8 - 12, 1)
    }

}

struct NativeAdPostCardRepresentable: UIViewRepresentable {
    let adContent: NativeAdContent

    func makeUIView(context: Context) -> NativeAdPostCardUIView {
        let view = NativeAdPostCardUIView()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: NativeAdPostCardUIView, context: Context) {
        uiView.bind(adContent)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: NativeAdPostCardUIView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        uiView.bounds.size.width = width
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        let size = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    static func dismantleUIView(_ uiView: NativeAdPostCardUIView, coordinator: ()) {
        uiView.unbind()
    }
}

enum NativeAdCopy {
    static func displayAdvertiserName(from ad: NativeAdContent) -> String {
        #if ALTON_DEV || DEBUG
        return "Test Native Ad"
        #else
        let advertiser = ad.advertiser?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if advertiser.isEmpty || advertiser.caseInsensitiveCompare("cas.ai") == .orderedSame {
            let headline = ad.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return headline.isEmpty ? "Sponsored" : headline
        }
        return advertiser
        #endif
    }

    static func hasMedia(_ ad: NativeAdContent) -> Bool {
        if ad.hasVideoContent { return true }
        if ad.mediaImage != nil { return true }
        if ad.mediaImageURL != nil { return true }
        return ad.mediaContentAspectRatio > 0
    }

    static func contentLine(_ value: String?, excluding name: String) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.caseInsensitiveCompare(name) == .orderedSame { return nil }
        if raw.caseInsensitiveCompare("cas.ai") == .orderedSame { return nil }
        if raw.caseInsensitiveCompare("Test Native Ad") == .orderedSame { return nil }
        return raw
    }

    static func callToActionTitle(from ad: NativeAdContent) -> String {
        let raw = ad.callToAction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Show More" : raw
    }
}

/// Full-screen native ad laid out like a shot page: bleed media, bottom meta, CTA.
final class NativeAdShotCardUIView: UIView {
    private let nativeView = CASNativeView(frame: .zero)
    private let mediaView = CASMediaView(frame: .zero)
    private let iconView = UIImageView()
    private let advertiserLabel = UILabel()
    private let headlineLabel = UILabel()
    private let sponsoredLabel = UILabel()
    private let bodyLabel = UILabel()
    private let ctaButton = UIButton(type: .system)
    private let adChoicesView = CASChoicesView(frame: .zero)
    private let gradientView = NativeAdShotGradientView()
    private let identityRow = UIStackView()
    private let textColumn = UIStackView()
    private let bottomStack = UIStackView()

    private var boundContent: NativeAdContent?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func bind(_ adContent: NativeAdContent) {
        guard !adContent.isExpired else { return }
        if boundContent === adContent {
            updateMediaVisibility()
            return
        }
        boundContent = adContent

        nativeView.iconView = iconView
        nativeView.advertiserView = advertiserLabel
        nativeView.headlineView = headlineLabel
        nativeView.bodyView = bodyLabel
        nativeView.mediaView = mediaView
        nativeView.callToActionView = ctaButton
        nativeView.adChoicesView = adChoicesView
        nativeView.adLabelView = sponsoredLabel

        nativeView.bindAdContent(adContent, autoPopulateText: true)

        let displayName = NativeAdCopy.displayAdvertiserName(from: adContent)
        advertiserLabel.text = displayName
        sponsoredLabel.text = "Sponsored"
        headlineLabel.text = nil
        headlineLabel.isHidden = true
        let body = NativeAdCopy.contentLine(adContent.body, excluding: displayName)
            ?? NativeAdCopy.contentLine(adContent.headline, excluding: displayName)
        bodyLabel.text = body
        bodyLabel.isHidden = body == nil

        if let icon = adContent.icon {
            iconView.image = icon
        }
        iconView.isHidden = false
        applyCTAStyle(title: NativeAdCopy.callToActionTitle(from: adContent))
        updateMediaVisibility()
        setNeedsLayout()
    }

    func unbind() {
        nativeView.bindAdContent(nil)
        boundContent = nil
        iconView.image = nil
    }

    private func setup() {
        backgroundColor = .black

        nativeView.translatesAutoresizingMaskIntoConstraints = false
        nativeView.backgroundColor = .black
        addSubview(nativeView)

        configureMedia()
        configureIcon()
        configureLabels()
        configureCTA()
        configureAdChoices()
        configureStacks()

        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.isUserInteractionEnabled = false
        nativeView.insertSubview(gradientView, belowSubview: bottomStack)

        NSLayoutConstraint.activate([
            nativeView.topAnchor.constraint(equalTo: topAnchor),
            nativeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            nativeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nativeView.bottomAnchor.constraint(equalTo: bottomAnchor),

            mediaView.topAnchor.constraint(equalTo: nativeView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: nativeView.bottomAnchor),

            adChoicesView.topAnchor.constraint(equalTo: nativeView.safeAreaLayoutGuide.topAnchor, constant: 12),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor, constant: -12),
            adChoicesView.widthAnchor.constraint(equalToConstant: 20),
            adChoicesView.heightAnchor.constraint(equalToConstant: 20),

            bottomStack.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor, constant: -16),
            bottomStack.bottomAnchor.constraint(equalTo: nativeView.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            gradientView.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: nativeView.bottomAnchor),
            gradientView.topAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -72),

            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            ctaButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func configureMedia() {
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.backgroundColor = .black
        nativeView.addSubview(mediaView)
    }

    private func configureIcon() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 20
        iconView.layer.borderWidth = 1.5
        iconView.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        iconView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    }

    private func configureLabels() {
        advertiserLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        advertiserLabel.textColor = .white
        advertiserLabel.numberOfLines = 1

        headlineLabel.font = .systemFont(ofSize: 15, weight: .regular)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 2
        headlineLabel.isHidden = true

        sponsoredLabel.font = .systemFont(ofSize: 14, weight: .regular)
        sponsoredLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        sponsoredLabel.text = "Sponsored"

        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        bodyLabel.numberOfLines = 3
    }

    private func configureCTA() {
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        applyCTAStyle(title: "Show More")
    }

    private func configureAdChoices() {
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        adChoicesView.setContentHuggingPriority(.required, for: .horizontal)
        adChoicesView.setContentCompressionResistancePriority(.required, for: .horizontal)
        nativeView.addSubview(adChoicesView)
    }

    private func configureStacks() {
        let nameColumn = UIStackView(arrangedSubviews: [advertiserLabel, sponsoredLabel])
        nameColumn.axis = .vertical
        nameColumn.alignment = .leading
        nameColumn.spacing = 2

        identityRow.axis = .horizontal
        identityRow.alignment = .center
        identityRow.spacing = 10
        identityRow.addArrangedSubview(iconView)
        identityRow.addArrangedSubview(nameColumn)

        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 8
        textColumn.addArrangedSubview(identityRow)
        textColumn.addArrangedSubview(bodyLabel)

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.spacing = 14
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(textColumn)
        bottomStack.addArrangedSubview(ctaButton)
        nativeView.addSubview(bottomStack)
    }

    private func applyCTAStyle(title: String) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .black
        config.baseBackgroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }
        ctaButton.configuration = config
        ctaButton.isHidden = false
    }

    private func updateMediaVisibility() {
        guard let ad = boundContent, NativeAdCopy.hasMedia(ad) else {
            mediaView.isHidden = true
            return
        }
        mediaView.isHidden = false
    }
}

private final class NativeAdShotGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let layer = layer as? CAGradientLayer else { return }
        layer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.75).cgColor,
        ]
        layer.locations = [0, 1]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

struct NativeAdShotCardRepresentable: UIViewRepresentable {
    let adContent: NativeAdContent

    func makeUIView(context: Context) -> NativeAdShotCardUIView {
        NativeAdShotCardUIView()
    }

    func updateUIView(_ uiView: NativeAdShotCardUIView, context: Context) {
        uiView.bind(adContent)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: NativeAdShotCardUIView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let height = proposal.height ?? UIScreen.main.bounds.height
        return CGSize(width: width, height: height)
    }

    static func dismantleUIView(_ uiView: NativeAdShotCardUIView, coordinator: ()) {
        uiView.unbind()
    }
}
