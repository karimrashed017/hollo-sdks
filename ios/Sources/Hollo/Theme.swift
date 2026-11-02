import SwiftUI
import UIKit

/**
 * How the chat looks. Every setting is optional; anything left out uses
 * Hollo's black-and-white default, which follows light and dark mode.
 */
public struct HolloTheme {
    /** How the close button looks when the chat is shown with `Hollo.present()`. */
    public enum CloseButton: Sendable {
        /** A "Done" text button, in the user's language. */
        case text
        /** A round "×" icon. */
        case icon
    }

    /** Buttons, links, the send button and the user's own bubbles. */
    public var accent: Color?
    /** The chat's background. */
    public var background: Color?
    /** The user's bubbles, if they should differ from `accent`. */
    public var userBubble: Color?
    /** Bubbles for replies from your team and the AI. */
    public var teamBubble: Color?
    /** Text in messages and the composer. */
    public var font: Font?
    /** The title at the top of the chat, like "Help". */
    public var title: String?
    /** The text on the welcome screen before the first message. */
    public var welcome: String?
    /** The image on the welcome screen. Defaults to the app icon. */
    public var welcomeIcon: Image?
    /** Force `.light` or `.dark`; nil follows the system. */
    public var colorScheme: ColorScheme?
    public var closeButton: CloseButton

    public init(
        accent: Color? = nil,
        background: Color? = nil,
        userBubble: Color? = nil,
        teamBubble: Color? = nil,
        font: Font? = nil,
        title: String? = nil,
        welcome: String? = nil,
        welcomeIcon: Image? = nil,
        colorScheme: ColorScheme? = nil,
        closeButton: CloseButton = .text
    ) {
        self.accent = accent
        self.background = background
        self.userBubble = userBubble
        self.teamBubble = teamBubble
        self.font = font
        self.title = title
        self.welcome = welcome
        self.welcomeIcon = welcomeIcon
        self.colorScheme = colorScheme
        self.closeButton = closeButton
    }
}

/** The theme with Hollo's defaults filled in. */
struct ChatStyle {
    let accent: Color
    let background: Color
    let userBubble: Color
    let teamBubble: Color
    let text: Color
    let muted: Color
    let hairline: Color
    let font: Font
    let theme: HolloTheme

    init(_ theme: HolloTheme) {
        self.theme = theme
        accent = theme.accent ?? Ink.accent
        background = theme.background ?? Color(uiColor: .systemBackground)
        userBubble = theme.userBubble ?? accent
        teamBubble = theme.teamBubble ?? Ink.bubble
        text = Ink.text
        muted = Color(uiColor: .secondaryLabel)
        hairline = Color(uiColor: .separator)
        font = theme.font ?? .body
    }
}

/** Hollo's own black and white: ink #0B0B0C on white, inverted in dark mode. */
enum Ink {
    static let accent = dynamic(light: 0x0B0B0C, dark: 0xF5F5F4)
    static let text = dynamic(light: 0x0B0B0C, dark: 0xF5F5F4)
    static let bubble = dynamic(light: 0xF1F1F0, dark: 0x262628)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /**
     * White or ink, whichever reads better on a colour, so a custom accent
     * never ends up with unreadable text.
     */
    static func readable(on color: Color, in environment: EnvironmentValues) -> Color {
        let c = color.resolve(in: environment)
        // Color.Resolved is in linear sRGB, which is what luminance needs.
        let luminance = 0.2126 * Double(c.red) + 0.7152 * Double(c.green) + 0.0722 * Double(c.blue)
        let contrastWithWhite = 1.05 / (luminance + 0.05)
        let contrastWithInk = (luminance + 0.05) / 0.05
        return contrastWithWhite >= contrastWithInk
            ? .white
            : Color(red: 11.0 / 255, green: 11.0 / 255, blue: 12.0 / 255)
    }
}
