import SwiftUI
import UIKit

/**
 * The chat as a view controller, for UIKit apps. Push it onto a navigation
 * controller, add it as a child, or put it in a tab bar.
 */
public final class HolloChatViewController: UIHostingController<AnyView> {
    public init() {
        super.init(rootView: AnyView(HolloChat()))
        applyTheme()
    }

    /** The sheet `Hollo.present()` shows, with a close button. */
    init(onClose: @escaping () -> Void) {
        super.init(rootView: AnyView(HolloChat(onClose: onClose)))
        applyTheme()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: AnyView(HolloChat()))
        applyTheme()
    }

    private func applyTheme() {
        // Forcing a look in SwiftUI alone would leave the sheet's own
        // background following the system.
        switch Hollo.theme.colorScheme {
        case .light?: overrideUserInterfaceStyle = .light
        case .dark?: overrideUserInterfaceStyle = .dark
        default: overrideUserInterfaceStyle = .unspecified
        }
        title = Hollo.theme.title
    }
}

/** Shows the chat as a sheet over whatever is on screen. */
@MainActor
enum Presenter {
    private static weak var sheet: UIViewController?

    static var isPresenting: Bool {
        guard let sheet else { return false }
        return sheet.presentingViewController != nil && !sheet.isBeingDismissed
    }

    static func present(attempt: Int = 0) {
        guard !isPresenting else { return }
        guard let top = topViewController() else {
            // Cold launch from a notification: the window may not exist yet.
            if attempt < 20 {
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    present(attempt: attempt + 1)
                }
            }
            return
        }
        let chat = HolloChatViewController(onClose: { Presenter.dismiss() })
        chat.modalPresentationStyle = .pageSheet
        if let sheet = chat.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        sheet = chat
        top.present(chat, animated: true)
    }

    static func dismiss(then action: (() -> Void)? = nil) {
        guard let sheet, isPresenting else {
            action?()
            return
        }
        sheet.dismiss(animated: true) { action?() }
    }

    /** Closes the sheet (if it's open), then runs action once it's gone. */
    static func closeThen(_ action: @escaping () -> Void) {
        dismiss(then: action)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first,
              var top = window.rootViewController
        else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        // Can't present over a view controller that's still appearing or leaving.
        if top.isBeingPresented || top.isBeingDismissed { return nil }
        return top
    }
}
