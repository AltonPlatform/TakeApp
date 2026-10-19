import SwiftUI
import UIKit

/// Owns the custom transition. `transitioningDelegate` is weak, so the presented controller keeps this alive.
@MainActor
final class GrokPanelTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    /// Weak: `UIPresentationController` retains the presented controller, which retains this delegate.
    private weak var panelPresentation: GrokPanelPresentationController?

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        GrokPanelAnimator(isPresenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        GrokPanelAnimator(isPresenting: false)
    }

    func interactionControllerForDismissal(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        guard let interaction = panelPresentation?.interaction, interaction.isInteracting else { return nil }
        return interaction
    }

    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        if let panelPresentation { return panelPresentation }
        let controller = GrokPanelPresentationController(
            presentedViewController: presented,
            presenting: presenting
        )
        panelPresentation = controller
        return controller
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}

/// Base type so the presenter can find a panel without knowing its SwiftUI content type.
@MainActor
class GrokPanelHostingControllerBase: UIViewController {
    var onDismiss: (() -> Void)?
    private let transitionDelegate = GrokPanelTransitioningDelegate()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        modalPresentationStyle = .custom
        transitioningDelegate = transitionDelegate
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .clear
        view = root
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentingViewController == nil else { return }
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

/// Presented with `modalPresentationStyle = .custom`.
///
/// ```swift
/// let panel = GrokPanelHostingController(rootView: MyView())
/// panel.onDismiss = { [weak self] in self?.reload() }
/// present(panel, animated: true)
/// ```
@MainActor
final class GrokPanelHostingController<Content: View>: GrokPanelHostingControllerBase {
    private let hostingController: UIHostingController<Content>

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.frame = view.bounds
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
}

/// Presents a card over the current screen. A second panel is ignored while one is already up,
/// and `dismiss()` is ignored while the panel is still being presented.
@MainActor
enum GrokPanelPresenter {
    static func present(onDismiss: @escaping () -> Void = {}, @ViewBuilder content: () -> some View) {
        guard let presenter = topViewController() else { return }
        if presenter is GrokPanelHostingControllerBase { return }
        if presenter.presentedViewController is GrokPanelHostingControllerBase { return }

        let panel = GrokPanelHostingController(rootView: AnyView(content()))
        panel.onDismiss = onDismiss
        presenter.present(panel, animated: true)
    }

    static func dismiss() {
        guard let top = topViewController() else { return }
        let panel = (top as? GrokPanelHostingControllerBase)
            ?? (top.presentedViewController as? GrokPanelHostingControllerBase)
        guard let panel, !panel.isBeingPresented, !panel.isBeingDismissed else { return }
        panel.dismiss(animated: true)
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? keyWindowRoot()
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

    private static func keyWindowRoot() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        return window?.rootViewController
    }
}
