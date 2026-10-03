import SwiftUI
import UIKit

/// Presents the draggable bottom sheet via UIKit so SwiftUI state updates
/// (e.g. analytics finishing load) cannot remount / re-animate the sheet.
enum AltonSheetPresenter {
    @MainActor
    static func present(heightRatio: CGFloat = 0.88, @ViewBuilder content: () -> some View) {
        guard let presenter = topViewController() else { return }

        // Don't stack sheets; if one is already up, ignore.
        if presenter is AltonDraggableSheetViewController {
            return
        }
        if presenter.presentedViewController is AltonDraggableSheetViewController {
            return
        }

        let sheet = AltonDraggableSheetViewController(
            heightRatio: heightRatio,
            onDismiss: {},
            rootView: AnyView(content())
        )
        sheet.onDismissHandler = { [weak sheet] in
            sheet?.dismiss(animated: false)
        }
        presenter.present(sheet, animated: false)
    }

    @MainActor
    static func dismiss() {
        guard let top = topViewController() else { return }
        if let sheet = top as? AltonDraggableSheetViewController {
            sheet.animateDismissFromOutside()
            return
        }
        if let sheet = top.presentedViewController as? AltonDraggableSheetViewController {
            sheet.animateDismissFromOutside()
        }
    }

    @MainActor
    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let base = base ?? {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let window = scenes
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            return window?.rootViewController
        }()

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

@MainActor
final class AltonDraggableSheetViewController: UIViewController {
    var onDismissHandler: (() -> Void)?

    private let heightRatio: CGFloat
    private let dimmingView = UIView()
    private let sheetView = UIView()
    private var hostingController: UIHostingController<AnyView>?
    private var contentScrollView: UIScrollView?
    private var sheetHeightConstraint: NSLayoutConstraint?
    private weak var scrollPanRecognizer: UIPanGestureRecognizer?

    private var translationY: CGFloat = 0
    private var activeDismissDirection: DismissDirection = .none
    private var hasPresentedSheet = false
    private var isDismissing = false

    private let dismissDistanceThreshold: CGFloat = 120
    private let dismissVelocityThreshold: CGFloat = 0.5
    private let directionLockDistance: CGFloat = 10

    private enum DismissDirection {
        case none
        case down
        case right
    }

    init(heightRatio: CGFloat, onDismiss: @escaping () -> Void, rootView: AnyView) {
        self.heightRatio = heightRatio
        self.onDismissHandler = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve

        let hosting = UIHostingController(rootView: rootView)
        hosting.view.backgroundColor = .clear
        hostingController = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func animateDismissFromOutside() {
        animateDismiss()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimmingView.alpha = 0
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)

        sheetView.backgroundColor = .systemBackground
        sheetView.layer.cornerRadius = 12
        sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetView.layer.masksToBounds = true
        sheetView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheetView)

        guard let hosting = hostingController else { return }
        addChild(hosting)
        sheetView.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: sheetView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor),
        ])
        hosting.didMove(toParent: self)

        sheetHeightConstraint = sheetView.heightAnchor.constraint(
            equalTo: view.heightAnchor,
            multiplier: heightRatio
        )

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sheetHeightConstraint!,
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDimmingTap))
        dimmingView.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async { [weak self] in
            self?.attachContentScrollViewIfNeeded()
        }
        guard !hasPresentedSheet else { return }
        hasPresentedSheet = true
        presentSheetAnimated()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let scrollPanRecognizer {
            scrollPanRecognizer.removeTarget(self, action: #selector(handleScrollPan(_:)))
            self.scrollPanRecognizer = nil
        }
    }

    private func attachContentScrollViewIfNeeded() {
        guard contentScrollView == nil, let hostingView = hostingController?.view else { return }
        contentScrollView = findScrollView(in: hostingView)
        guard let scrollView = contentScrollView else { return }

        scrollView.alwaysBounceVertical = true
        let pan = scrollView.panGestureRecognizer
        pan.addTarget(self, action: #selector(handleScrollPan(_:)))
        scrollPanRecognizer = pan
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }

    private func presentSheetAnimated() {
        sheetView.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        dimmingView.alpha = 0
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.4
        ) {
            self.sheetView.transform = .identity
            self.dimmingView.alpha = 1
        }
    }

    @objc private func handleDimmingTap() {
        animateDismiss()
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.view === contentScrollView else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let scrollOffsetY = contentScrollView?.contentOffset.y ?? 0

        switch gesture.state {
        case .began:
            activeDismissDirection = .none
        case .changed:
            if activeDismissDirection == .none {
                updateDismissDirectionIfNeeded(
                    translation: translation,
                    velocity: velocity,
                    scrollOffsetY: scrollOffsetY
                )
                if activeDismissDirection == .none, scrollOffsetY > 0 {
                    return
                }
            }
            applyActiveDismissTransform(translation: translation)
        case .ended, .cancelled:
            if activeDismissDirection == .none {
                translationY = 0
            } else {
                finishInteractiveDismiss(velocity: velocity)
            }
            activeDismissDirection = .none
        default:
            break
        }
    }

    private func updateDismissDirectionIfNeeded(
        translation: CGPoint,
        velocity: CGPoint,
        scrollOffsetY: CGFloat
    ) {
        guard activeDismissDirection == .none else { return }
        guard hypot(translation.x, translation.y) >= directionLockDistance else { return }

        if abs(velocity.x) > abs(velocity.y), velocity.x > 0 {
            activeDismissDirection = .right
            return
        }

        if abs(velocity.y) >= abs(velocity.x),
           velocity.y > 0,
           scrollOffsetY <= 0 {
            activeDismissDirection = .down
        }
    }

    private func applyActiveDismissTransform(translation: CGPoint) {
        switch activeDismissDirection {
        case .right:
            translationY = max(0, translation.x)
            contentScrollView?.contentOffset = .zero
        case .down:
            translationY = max(0, translation.y)
            contentScrollView?.contentOffset = .zero
        case .none:
            translationY = 0
            return
        }

        sheetView.transform = CGAffineTransform(translationX: 0, y: translationY)
        let sheetHeight = max(sheetView.bounds.height, 1)
        dimmingView.alpha = 1 - min(translationY / sheetHeight, 1) * 0.85
    }

    private func finishInteractiveDismiss(velocity: CGPoint) {
        let sheetHeight = max(sheetView.bounds.height, 1)

        switch activeDismissDirection {
        case .down:
            let normalizedVelocity = velocity.y / sheetHeight
            if translationY > dismissDistanceThreshold || normalizedVelocity > dismissVelocityThreshold {
                animateDismiss()
            } else {
                resetSheetPosition()
            }
        case .right:
            let normalizedVelocity = velocity.x / max(view.bounds.width, 1)
            if translationY > dismissDistanceThreshold || normalizedVelocity > dismissVelocityThreshold {
                animateDismiss()
            } else {
                resetSheetPosition()
            }
        case .none:
            if translationY > 0 {
                resetSheetPosition()
            }
        }
    }

    private func resetSheetPosition() {
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.5
        ) {
            self.sheetView.transform = .identity
            self.dimmingView.alpha = 1
        } completion: { _ in
            self.translationY = 0
        }
    }

    private func animateDismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        let sheetHeight = sheetView.bounds.height
        let targetTransform = CGAffineTransform(translationX: 0, y: sheetHeight + 40)

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseIn]
        ) {
            self.sheetView.transform = targetTransform
            self.dimmingView.alpha = 0
        } completion: { _ in
            self.onDismissHandler?()
            if self.presentingViewController != nil {
                self.dismiss(animated: false)
            }
        }
    }
}

/// Shared chrome for post insights / activity sheets.
struct PostSheetChrome<Content: View>: View {
    let title: String
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
