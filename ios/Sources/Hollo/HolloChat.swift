import PhotosUI
import SwiftUI
import UIKit

/**
 * The support chat as a SwiftUI view. Put it in a `NavigationStack`, a tab,
 * a sheet you manage yourself or a split view. `Hollo.present()` shows the
 * same view in a sheet.
 */
public struct HolloChat: View {
    private let onClose: (() -> Void)?
    @Environment(\.colorScheme) private var systemScheme

    public init() {
        onClose = nil
    }

    init(onClose: (() -> Void)?) {
        self.onClose = onClose
    }

    public var body: some View {
        let theme = Hollo.theme
        let remote = Hollo.store.remoteTheme
        let scheme = ChatStyle.scheme(remote: remote, local: theme.colorScheme, system: systemScheme)
        let strings = HolloStrings.forLanguage(Hollo.language)
        ChatScreen(
            store: Hollo.store,
            style: ChatStyle(theme, remote: remote, scheme: scheme),
            strings: strings,
            onClose: onClose
        )
        .environment(\.colorScheme, scheme)
        .environment(\.layoutDirection, strings.layoutDirection)
    }
}

struct ChatScreen: View {
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings
    let onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(store: store, style: style, strings: strings, onClose: onClose)
            Divider()
            if store.offline {
                Text(strings.offline)
                    .font(.footnote)
                    .foregroundStyle(style.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(style.teamBubble)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if store.messages.isEmpty && store.outbox.isEmpty {
                Welcome(store: store, style: style, strings: strings)
            } else {
                MessageList(store: store, style: style, strings: strings)
            }
            Composer(store: store, style: style, strings: strings)
            if store.branding {
                BrandingFooter(style: style)
            }
        }
        .animation(.default, value: store.offline)
        .background(style.background.ignoresSafeArea())
        .onAppear { store.chatAppeared() }
        .onDisappear { store.chatDisappeared() }
    }
}

// MARK: Header

struct ChatHeader: View {
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Avatar(photo: store.profile.photo, size: 36, style: style)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.profile.name ?? style.title ?? strings.support)
                    .font(.headline)
                    .foregroundStyle(style.text)
                Text(store.profile.role ?? strings.replyTime)
                    .font(.caption)
                    .foregroundStyle(style.muted)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    switch style.theme.closeButton {
                    case .text:
                        Text(strings.done).fontWeight(.semibold).foregroundStyle(style.text)
                    case .icon:
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(style.text)
                    }
                }
                .accessibilityLabel(strings.close)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, onClose == nil ? 12 : 20)
        .padding(.bottom, 14)
    }
}

/** The owner's photo when they've added one, otherwise the Hollo dot. */
struct Avatar: View {
    let photo: URL?
    let size: CGFloat
    let style: ChatStyle
    @Environment(\.self) private var environment

    var body: some View {
        Group {
            if let photo {
                AsyncImage(url: photo) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    style.teamBubble
                }
            } else {
                ZStack {
                    style.accent
                    Circle()
                        .strokeBorder(style.onAccent(style.accent, in: environment), lineWidth: size / 12)
                        .frame(width: size * 0.39, height: size * 0.39)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: Welcome

struct Welcome: View {
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                icon
                Text(strings.emptyTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(style.text)
                    .padding(.top, 4)
                Text(store.profile.welcome ?? style.theme.welcome ?? strings.emptyText)
                    .font(.subheadline)
                    .foregroundStyle(style.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var icon: some View {
        if let custom = style.theme.welcomeIcon {
            custom.resizable().scaledToFit().frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let photo = store.profile.photo {
            Avatar(photo: photo, size: 72, style: style)
        } else if let appIcon = AppIcon.image {
            Image(uiImage: appIcon).resizable().frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

enum AppIcon {
    /** The app's own icon, from its Info.plist, if it can be loaded. */
    static let image: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last
        else { return nil }
        return UIImage(named: name)
    }()
}

// MARK: Messages

struct MessageList: View {
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings
    /** Photos open full screen from here, not the row, which a lazy stack can drop. */
    @State private var viewing: PhotoViewing?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.messages) { message in
                        Group {
                            if message.isActionConfirm {
                                ActionConfirmCard(message: message, store: store, style: style, strings: strings)
                            } else {
                                MessageRow(
                                    message: message, profileName: store.profile.name, style: style, strings: strings,
                                    openPhoto: { viewing = PhotoViewing(photos: message.photos, index: $0) }
                                )
                            }
                        }
                        .id(message.id)
                    }
                    ForEach(store.outbox) { item in
                        PendingRow(item: item, store: store, style: style, strings: strings)
                            .id(item.id.uuidString)
                    }
                    PushFooter(store: store, style: style, strings: strings)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count + store.outbox.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: store.askPush) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .fullScreenCover(item: $viewing) { viewing in
            PhotoViewer(photos: viewing.photos, start: viewing.index, strings: strings)
        }
    }
}

struct MessageRow: View {
    let message: HolloMessage
    let profileName: String?
    let style: ChatStyle
    let strings: HolloStrings
    /** Opens the message's photo at this index full screen. */
    let openPhoto: (Int) -> Void

    private var label: String? {
        message.sender == .ai ? strings.ai : message.sender == .team ? profileName : nil
    }

    var body: some View {
        if message.isCard {
            CardView(content: CardContent(message, strings: strings), style: style) {
                Hollo.tapCard(message)
            }
        } else if message.sender == .system {
            Text(message.body)
                .font(.footnote)
                .foregroundStyle(style.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else if !message.photos.isEmpty {
            let photos = message.photos
            PhotoBubble(
                count: photos.count, caption: message.body, mine: message.sender == .endUser,
                label: label, style: style, strings: strings
            ) { index, size in
                Button {
                    openPhoto(index)
                } label: {
                    RemotePhoto(url: photos[index], size: size, style: style)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings.photoLabel(index + 1, of: photos.count))
                .accessibilityAddTraits(.isImage)
            }
        } else {
            Bubble(
                // An image message whose links didn't arrive still says what it was.
                text: message.body.isEmpty && message.kind == "image" ? strings.photo : message.body,
                mine: message.sender == .endUser,
                label: label,
                style: style,
                strings: strings
            )
        }
    }
}

struct Bubble: View {
    let text: String
    let mine: Bool
    let label: String?
    let style: ChatStyle
    let strings: HolloStrings

    var body: some View {
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 48) }
            BubbleText(text: text, mine: mine, label: label, style: style, strings: strings)
            if !mine { Spacer(minLength: 48) }
        }
    }
}

/** A bubble's text and fill, without the row around it; photo captions use it too. */
struct BubbleText: View {
    let text: String
    let mine: Bool
    let label: String?
    let style: ChatStyle
    let strings: HolloStrings
    @Environment(\.self) private var environment

    var body: some View {
        let fill = mine ? style.userBubble : style.teamBubble
        let foreground = mine ? style.onAccent(fill, in: environment) : style.incomingText
        VStack(alignment: .leading, spacing: 2) {
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(mine ? foreground.opacity(0.7) : style.muted)
            }
            Text(HolloLinks.linkified(text))
                .font(style.font)
                .foregroundStyle(foreground)
                .tint(mine ? foreground : style.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            fill,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: mine ? 18 : 6,
                bottomTrailingRadius: mine ? 6 : 18,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label(strings.copy, systemImage: "doc.on.doc")
            }
        }
    }
}

/** A message the user wrote that's still on its way. */
struct PendingRow: View {
    let item: OutgoingMessage
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Group {
                if item.photos.isEmpty {
                    Bubble(text: item.body, mine: true, label: nil, style: style, strings: strings)
                } else {
                    let photos = item.photos
                    PhotoBubble(
                        count: photos.count, caption: item.body, mine: true,
                        label: nil, style: style, strings: strings
                    ) { index, size in
                        LocalPhoto(jpeg: photos[index], size: size, style: style)
                            .accessibilityElement()
                            .accessibilityLabel(strings.photoLabel(index + 1, of: photos.count))
                            .accessibilityAddTraits(.isImage)
                    }
                }
            }
            .opacity(item.state == .failed ? 0.5 : 0.7)
            switch item.state {
            case .sending:
                Text(strings.sending).font(.caption2).foregroundStyle(style.muted)
            case .waiting:
                Text(strings.waiting).font(.caption2).foregroundStyle(style.muted)
            case .failed:
                Button {
                    store.retry(item.id)
                } label: {
                    Label(strings.failed, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(style.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: Cards

/** A review request, offer or link the team sent, with one button. */
struct CardView: View {
    let content: CardContent
    let style: ChatStyle
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !content.title.isEmpty {
                Text(content.title).font(.headline).foregroundStyle(style.text)
            }
            if !content.text.isEmpty {
                Text(HolloLinks.linkified(content.text))
                    .font(.subheadline)
                    .foregroundStyle(style.muted)
                    .tint(style.accent)
            }
            FilledButton(title: content.button, style: style, action: action)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style.teamBubble, lineWidth: 1)
        )
    }
}

struct FilledButton: View {
    let title: String
    let style: ChatStyle
    let action: () -> Void
    @Environment(\.self) private var environment
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(style.onAccent(style.accent, in: environment))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(style.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/** The secondary button beside a FilledButton: an outline, no fill. */
struct OutlineButton: View {
    let title: String
    let style: ChatStyle
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(style.text)
                .frame(maxWidth: .infinity, minHeight: 40)
                .overlay(Capsule().strokeBorder(style.teamBubble, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/**
 * The AI asking before it changes something (F-42): what will change, then
 * Confirm or Cancel. Once answered, or past its time, it shows the outcome
 * instead. The AI's reply arrives with the normal poll.
 */
struct ActionConfirmCard: View {
    let message: HolloMessage
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings

    var body: some View {
        let card = ActionConfirm(message.payload)
        let progress = store.confirmations[message.id]
        // Redrawn every minute, so a card left open turns to "Expired" on time.
        TimelineView(.everyMinute) { _ in
            content(card, progress: progress, state: card.state(progress: progress, now: Date()))
        }
    }

    private func content(
        _ card: ActionConfirm, progress: ConfirmationProgress?, state: ActionConfirm.State
    ) -> some View {
        // An older server, or a card with nothing filled in, still says something.
        let title = card.title.isEmpty && card.summary.isEmpty ? message.body : card.title
        return VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title).font(.headline).foregroundStyle(style.text)
            }
            if !card.summary.isEmpty {
                Text(card.summary).font(.subheadline).foregroundStyle(style.muted)
            }
            if !card.inputs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(card.inputs.enumerated()), id: \.offset) { _, input in
                        Text(verbatim: Self.line(input))
                            .font(.subheadline)
                            .foregroundStyle(style.text)
                    }
                }
                .padding(.top, 2)
            }
            if state == .pending {
                let sending = progress == .sending
                HStack(spacing: 8) {
                    OutlineButton(title: strings.cancel, style: style) {
                        _ = store.answerConfirmation(message, confirm: false)
                    }
                    FilledButton(title: strings.confirm, style: style) {
                        _ = store.answerConfirmation(message, confirm: true)
                    }
                }
                .disabled(sending)
                .padding(.top, 8)
                if progress == .failed {
                    Text(strings.confirmFailed)
                        .font(.caption)
                        .foregroundStyle(style.muted)
                }
            } else {
                Text(label(state))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.muted)
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style.teamBubble, lineWidth: 1)
        )
    }

    /** "Streak days: 41"; just the label or value when the other is missing. */
    static func line(_ input: ActionConfirm.Input) -> String {
        if input.label.isEmpty { return input.value }
        if input.value.isEmpty { return input.label }
        return "\(input.label): \(input.value)"
    }

    private func label(_ state: ActionConfirm.State) -> String {
        switch state {
        case .confirmed: return strings.confirmed
        case .cancelled: return strings.cancelled
        case .expired: return strings.expired
        case .unavailable, .pending: return strings.noLongerAvailable
        }
    }
}

/**
 * Under the user's latest message: the card asking to turn on notifications
 * (F-40), or a line saying they'll be notified of the reply (F-16).
 */
struct PushFooter: View {
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings

    var body: some View {
        if store.askPush {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.push.permissionCard == .repliesOffers ? strings.pushRepliesOffers : strings.pushReplies)
                    .font(.subheadline)
                    .foregroundStyle(style.text)
                HStack(spacing: 8) {
                    Button {
                        Task { await store.answerPushCard(accept: false) }
                    } label: {
                        Text(strings.noThanks)
                            .foregroundStyle(style.text)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .overlay(Capsule().strokeBorder(style.teamBubble, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    FilledButton(title: strings.continueLabel, style: style) {
                        Task { await store.answerPushCard(accept: true) }
                    }
                }
                .padding(.top, 8)
            }
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style.teamBubble, lineWidth: 1)
            )
        } else if waitingForReply, store.pushRegistered, store.notificationsAllowed, store.push.notifyLine {
            Text(strings.notifyLine)
                .font(.caption)
                .foregroundStyle(style.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var waitingForReply: Bool {
        store.outbox.isEmpty && store.messages.last?.sender == .endUser
    }
}

// MARK: Composer

struct Composer: View {
    let store: HolloStore
    let style: ChatStyle
    let strings: HolloStrings
    @State private var draft = ""
    @State private var photos: [DraftPhoto] = []
    @State private var picked: [PhotosPickerItem] = []
    /** Photos still being read and compressed. */
    @State private var preparing = 0
    @State private var photoFailed = false
    @Environment(\.self) private var environment

    private var canSend: Bool {
        preparing == 0
            && (!photos.isEmpty || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /** How many more photos this message can take. */
    private var room: Int {
        HolloPhotos.maxPerMessage - photos.count - preparing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !photos.isEmpty || preparing > 0 {
                DraftStrip(photos: photos, preparing: preparing, style: style, strings: strings) { id in
                    photos.removeAll { $0.id == id }
                }
            }
            if photoFailed {
                Text(strings.photoFailed)
                    .font(.caption)
                    .foregroundStyle(style.muted)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            field
        }
        .onChange(of: picked) {
            add(picked)
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // The system picker runs outside the app, so it needs no photo
            // library permission and no usage string in Info.plist.
            PhotosPicker(
                selection: $picked,
                maxSelectionCount: max(1, room),
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .compatible
            ) {
                Image(systemName: "photo")
                    .font(.system(size: 19))
                    .foregroundStyle(style.text)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room <= 0)
            .opacity(room <= 0 ? 0.35 : 1)
            .accessibilityLabel(strings.addPhotos)
            TextField(strings.placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .font(style.font)
                .foregroundStyle(style.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(style.teamBubble, lineWidth: 1)
                )
                .onChange(of: draft) {
                    if draft.count > 4000 { draft = String(draft.prefix(4000)) }
                }
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(style.onAccent(style.accent, in: environment))
                    .frame(width: 40, height: 40)
                    .background(style.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.35)
            .accessibilityLabel(strings.send)
        }
        .padding(12)
    }

    private func send() {
        let text = draft
        let jpegs = photos.map(\.jpeg)
        draft = ""
        photos = []
        photoFailed = false
        // The outbox keeps it, so nothing is lost if it can't go out yet.
        store.send(text, photos: jpegs)
    }

    /** Compresses newly picked photos, in the order they were picked. */
    @MainActor private func add(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        picked = []
        let items = Array(items.prefix(max(0, room)))
        photoFailed = false
        preparing += items.count
        Task {
            for item in items {
                let jpeg = await Self.prepare(item)
                preparing -= 1
                if let jpeg, let photo = DraftPhoto(jpeg: jpeg) {
                    photos.append(photo)
                } else {
                    photoFailed = true
                }
            }
        }
    }

    private static func prepare(_ item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        // Off the main thread: decoding a 48 MP photo takes a moment.
        return await Task.detached(priority: .userInitiated) {
            HolloPhotos.jpeg(from: data)
        }.value
    }
}

/** A photo picked for the next message, compressed and ready to upload. */
struct DraftPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let preview: UIImage

    init?(jpeg: Data) {
        guard let thumbnail = HolloPhotos.thumbnail(jpeg, maxEdge: 240) else { return nil }
        self.jpeg = jpeg
        preview = UIImage(cgImage: thumbnail)
    }
}

/** The picked photos above the composer, each with a remove button. */
struct DraftStrip: View {
    let photos: [DraftPhoto]
    let preparing: Int
    let style: ChatStyle
    let strings: HolloStrings
    let remove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Image(uiImage: photo.preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(strings.photoLabel(index + 1, of: photos.count))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                remove(photo.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(style.background, style.text)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel(strings.removePhoto)
                        }
                }
                ForEach(0..<preparing, id: \.self) { _ in
                    ProgressView()
                        .frame(width: 64, height: 64)
                        .background(style.teamBubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

// MARK: Branding

/** "Runs on Hollo" under the composer, unless the server turns it off. */
struct BrandingFooter: View {
    let style: ChatStyle

    var body: some View {
        Button {
            UIApplication.shared.open(HolloLinks.brandingURL)
        } label: {
            HStack(spacing: 5) {
                HolloMark()
                    .fill(style.muted, style: FillStyle(eoFill: true))
                    .frame(width: 12, height: 12)
                // The product name, so it isn't translated.
                Text(verbatim: "Runs on Hollo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(style.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Runs on Hollo"))
    }
}

/**
 * The Hollo mark from brand/hollo-mark.svg (48 × 48): a speech bubble with a
 * bubble-shaped hole and a dot. Fill it with eoFill so the hole stays open.
 */
struct HolloMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 48
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        // A disc of radius r around (24, 24) whose bottom-left quarter is square.
        func bubble(_ path: inout Path, _ r: CGFloat) {
            let lo = 24 - r, hi = 24 + r
            path.move(to: p(lo, 24))
            path.addArc(tangent1End: p(lo, lo), tangent2End: p(24, lo), radius: r * scale)
            path.addArc(tangent1End: p(hi, lo), tangent2End: p(hi, 24), radius: r * scale)
            path.addArc(tangent1End: p(hi, hi), tangent2End: p(24, hi), radius: r * scale)
            path.addLine(to: p(lo, hi))
            path.closeSubpath()
        }
        var path = Path()
        bubble(&path, 24)
        bubble(&path, 13)
        path.addEllipse(in: CGRect(origin: p(18.5, 18.5), size: CGSize(width: 11 * scale, height: 11 * scale)))
        return path
    }
}
