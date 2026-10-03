import SwiftUI
import UIKit

struct TabBarItemLongPressHandler: UIViewControllerRepresentable {
    let tabIndex: Int
    let onLongPress: () -> Void

    func makeUIViewController(context: Context) -> HandlerViewController {
        HandlerViewController(tabIndex: tabIndex, onLongPress: onLongPress)
    }

    func updateUIViewController(_ uiViewController: HandlerViewController, context: Context) {
        uiViewController.tabIndex = tabIndex
        uiViewController.onLongPress = onLongPress
    }

    final class HandlerViewController: UIViewController {
        var tabIndex: Int
        var onLongPress: () -> Void
        private weak var attachedTabBar: UITabBar?
        private var gestureRecognizer: UILongPressGestureRecognizer?
        private var installAttempts = 0

        init(tabIndex: Int, onLongPress: @escaping () -> Void) {
            self.tabIndex = tabIndex
            self.onLongPress = onLongPress
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleGestureInstallation()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scheduleGestureInstallation()
        }

        private func scheduleGestureInstallation() {
            installGestureIfNeeded()
            guard gestureRecognizer == nil, installAttempts < 30 else { return }
            installAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.scheduleGestureInstallation()
            }
        }

        private func installGestureIfNeeded() {
            guard let tabBar = findTabBar() else { return }
            if attachedTabBar === tabBar, gestureRecognizer != nil { return }

            if let gestureRecognizer, let attachedTabBar {
                attachedTabBar.removeGestureRecognizer(gestureRecognizer)
            }

            let gesture = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            gesture.minimumPressDuration = 0.45
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delegate = self
            tabBar.addGestureRecognizer(gesture)
            gestureRecognizer = gesture
            attachedTabBar = tabBar
        }

        private func findTabBar() -> UITabBar? {
            if let tabBarController {
                return tabBarController.tabBar
            }

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows where window.isKeyWindow {
                    if let tabBar = window.rootViewController?.firstTabBar?.tabBar {
                        return tabBar
                    }
                }
            }
            return nil
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let tabBar = attachedTabBar ?? findTabBar() else { return }
            let location = gesture.location(in: tabBar)
            guard pressedTabIndex(at: location, in: tabBar) == tabIndex else { return }
            onLongPress()
        }

        private func pressedTabIndex(at location: CGPoint, in tabBar: UITabBar) -> Int? {
            let buttons = tabBar.subviews
                .filter { NSStringFromClass(type(of: $0)).contains("TabBarButton") }
                .sorted { $0.frame.minX < $1.frame.minX }

            if !buttons.isEmpty {
                for (index, button) in buttons.enumerated() where button.frame.contains(location) {
                    return index
                }
                return nil
            }

            guard let items = tabBar.items, !items.isEmpty else { return nil }
            let itemWidth = tabBar.bounds.width / CGFloat(items.count)
            guard itemWidth > 0 else { return nil }
            let index = Int(location.x / itemWidth)
            guard index >= 0, index < items.count else { return nil }
            return index
        }
    }
}

extension TabBarItemLongPressHandler.HandlerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

extension View {
    func onTabBarItemLongPress(tabIndex: Int, perform action: @escaping () -> Void) -> some View {
        overlay {
            TabBarItemLongPressHandler(tabIndex: tabIndex, onLongPress: action)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

private extension UIViewController {
    var firstTabBar: UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }
        for child in children {
            if let found = child.firstTabBar {
                return found
            }
        }
        if let navigationController = self as? UINavigationController,
           let visible = navigationController.visibleViewController {
            return visible.firstTabBar
        }
        return presentedViewController?.firstTabBar
    }
}
