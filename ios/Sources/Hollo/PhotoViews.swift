import SwiftUI
import UIKit

// Photo messages (F-17): the thumbnail grid in a bubble, and the full-screen
// viewer with pinch and double-tap zoom.

/** Which photos the full-screen viewer shows, and where it starts. */
struct PhotoViewing: Identifiable {
    let id = UUID()
    let photos: [URL]
    let index: Int
}

/** An image message: the photos, then the caption in a bubble below. */
struct PhotoBubble<Cell: View>: View {
    let count: Int
    let caption: String
    let mine: Bool
    let label: String?
    let style: ChatStyle
    let strings: HolloStrings
    let cell: (Int, CGSize) -> Cell

    init(
        count: Int, caption: String, mine: Bool, label: String?, style: ChatStyle, strings: HolloStrings,
        @ViewBuilder cell: @escaping (Int, CGSize) -> Cell
    ) {
        self.count = count
        self.caption = caption
        self.mine = mine
        self.label = label
        self.style = style
        self.strings = strings
        self.cell = cell
    }

    var body: some View {
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if let label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(style.muted)
                        .padding(.horizontal, 4)
                }
                PhotoGrid(count: count, alignment: mine ? .trailing : .leading, cell: cell)
                if !caption.isEmpty {
                    BubbleText(text: caption, mine: mine, label: nil, style: style, strings: strings)
                }
            }
            if !mine { Spacer(minLength: 48) }
        }
    }
}

/** One photo large, or several in two columns. */
struct PhotoGrid<Cell: View>: View {
    static var width: CGFloat { 240 }
    static var spacing: CGFloat { 4 }

    let count: Int
    let alignment: HorizontalAlignment
    let cell: (Int, CGSize) -> Cell

    var body: some View {
        if count == 1 {
            cell(0, CGSize(width: Self.width, height: Self.width))
        } else {
            let side = (Self.width - Self.spacing) / 2
            let size = CGSize(width: side, height: side)
            VStack(alignment: alignment, spacing: Self.spacing) {
                ForEach(Array(stride(from: 0, to: count, by: 2)), id: \.self) { first in
                    HStack(spacing: Self.spacing) {
                        cell(first, size)
                        if first + 1 < count { cell(first + 1, size) }
                    }
                }
            }
        }
    }
}

/** A photo from the server, cropped to fill its square. */
struct RemotePhoto: View {
    let url: URL
    let size: CGSize
    let style: ChatStyle

    var body: some View {
        style.teamBubble
            .frame(width: size.width, height: size.height)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(style.muted)
                    default:
                        ProgressView()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
    }
}

/** A photo still on the device, in a message that hasn't gone out yet. */
struct LocalPhoto: View {
    let jpeg: Data
    let size: CGSize
    let style: ChatStyle
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        style.teamBubble
            .frame(width: size.width, height: size.height)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task { await load() }
    }

    @MainActor private func load() async {
        guard image == nil else { return }
        let edge = Int(max(size.width, size.height) * displayScale)
        image = HolloPhotos.thumbnail(jpeg, maxEdge: edge).map { UIImage(cgImage: $0) }
    }
}

// MARK: Viewer

/** A message's photos full screen on black: swipe between them, pinch or double-tap to zoom. */
struct PhotoViewer: View {
    let photos: [URL]
    let strings: HolloStrings
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(photos: [URL], start: Int, strings: HolloStrings) {
        self.photos = photos
        self.strings = strings
        _index = State(initialValue: min(max(0, start), max(0, photos.count - 1)))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, url in
                    ViewerPage(url: url, label: strings.photoLabel(offset + 1, of: photos.count))
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel(strings.closePhoto)
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }
}

/** One photo in the viewer, loaded at full size. */
struct ViewerPage: View {
    let url: URL
    let label: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image, label: label)
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityLabel(label)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { await load() }
    }

    @MainActor private func load() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let loaded = UIImage(data: data) else {
                failed = true
                return
            }
            // Decodes off the main thread, so swiping stays smooth.
            image = await loaded.byPreparingForDisplay() ?? loaded
        } catch {
            failed = true
        }
    }
}

/** UIScrollView does pinch zoom properly; SwiftUI gestures fight the pager. */
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let label: String

    func makeUIView(context: Context) -> ZoomingView {
        ZoomingView(frame: .zero)
    }

    func updateUIView(_ view: ZoomingView, context: Context) {
        view.image = image
        view.accessibilityLabel = label
    }
}

final class ZoomingView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    /** The size the image was last fitted to, so it's refitted on rotation. */
    private var fitted = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var image: UIImage? {
        get { imageView.image }
        set {
            guard newValue !== imageView.image else { return }
            imageView.image = newValue
            zoomScale = minimumZoomScale
            fitted = .zero
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only while not zoomed: zooming moves the image view itself.
        let refit = zoomScale == minimumZoomScale && bounds.size != fitted
        if refit { fit() }
        centre()
        if refit { contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top) }
    }

    /** Sizes the image view to the photo at aspect fit. */
    private func fit() {
        fitted = bounds.size
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0
        else { return }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
    }

    /** Keeps a photo smaller than the screen in the middle. */
    private func centre() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
    }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = tap.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            let rect = CGRect(
                origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                size: size
            )
            zoom(to: rect, animated: true)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
    }
}
