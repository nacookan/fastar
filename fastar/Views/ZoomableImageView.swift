import AppKit
import SwiftUI

struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage?
    @Binding var viewport: ImageViewport
    let containerSize: CGSize
    let acceptsDrop: Bool
    let onDropURL: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport, onDropURL: onDropURL)
    }

    func makeNSView(context: Context) -> FastarScrollView {
        let imageView = FastarImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.isDropEnabled = acceptsDrop
        imageView.dropHandler = onDropURL

        let scrollView = FastarScrollView()
        scrollView.documentView = imageView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.02
        scrollView.maxMagnification = 8
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.viewportDelegate = context.coordinator
        scrollView.postsBoundsChangedNotifications = true
        scrollView.isDropEnabled = acceptsDrop
        scrollView.dropHandler = onDropURL
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        context.coordinator.observeBoundsChanges(in: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: FastarScrollView, context: Context) {
        context.coordinator.binding = $viewport
        context.coordinator.onDropURL = onDropURL
        scrollView.isDropEnabled = acceptsDrop
        scrollView.dropHandler = onDropURL
        context.coordinator.imageView?.isDropEnabled = acceptsDrop
        context.coordinator.imageView?.dropHandler = onDropURL
        context.coordinator.update(scrollView: scrollView, image: image, viewport: viewport, containerSize: containerSize)
    }

    final class Coordinator: NSObject, FastarScrollViewDelegate {
        var binding: Binding<ImageViewport>
        var onDropURL: (URL) -> Void
        weak var imageView: FastarImageView?
        weak var scrollView: FastarScrollView?

        private var lastImageSignature: String?
        private var imageSize = CGSize.zero
        private var lastContainerSize = CGSize.zero
        private var lastAppliedViewport = ImageViewport()
        private var boundsObserver: NSObjectProtocol?
        private var isApplyingFromSwift = false

        init(viewport: Binding<ImageViewport>, onDropURL: @escaping (URL) -> Void) {
            self.binding = viewport
            self.onDropURL = onDropURL
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func observeBoundsChanges(in scrollView: FastarScrollView) {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: nil
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.viewportDidChange(scrollView)
            }
        }

        func update(scrollView: FastarScrollView, image: NSImage?, viewport: ImageViewport, containerSize: CGSize) {
            isApplyingFromSwift = true
            defer { isApplyingFromSwift = false }
            let containerChanged = lastContainerSize != containerSize
            lastContainerSize = containerSize

            let signature = image.map { "\(ObjectIdentifier($0))-\($0.size.width)x\($0.size.height)" }
            let imageChanged = signature != lastImageSignature
            if imageChanged {
                imageView?.image = image
                if let image {
                    imageSize = image.size
                    layoutDocument(scrollView: scrollView, containerSize: containerSize)
                } else {
                    imageSize = .zero
                    imageView?.setFrameSize(.zero)
                    scrollView.documentView?.setFrameSize(.zero)
                }
                lastImageSignature = signature
            }

            guard image != nil else {
                lastAppliedViewport = viewport
                return
            }

            if containerChanged {
                layoutDocument(scrollView: scrollView, containerSize: containerSize)
            }

            var targetViewport = viewport

            if viewport.fitToWindow {
                let fitZoom = self.fitZoom(scrollView: scrollView, containerSize: containerSize)
                if abs(scrollView.magnification - fitZoom) > 0.0001 || viewport.fitRequestID != lastAppliedViewport.fitRequestID {
                    scrollView.magnification = fitZoom
                    layoutDocument(scrollView: scrollView, containerSize: containerSize)
                    targetViewport.zoom = fitZoom
                    targetViewport.center = CGPoint(x: 0.5, y: 0.5)
                    publishViewport(targetViewport)
                }
            } else if abs(scrollView.magnification - viewport.zoom) > 0.0001 {
                scrollView.magnification = viewport.zoom
                layoutDocument(scrollView: scrollView, containerSize: containerSize)
            }

            if imageChanged || containerChanged || targetViewport.center != lastAppliedViewport.center || targetViewport.zoom != lastAppliedViewport.zoom {
                scroll(to: targetViewport.center, in: scrollView)
            }

            lastAppliedViewport = targetViewport
        }

        func viewportDidChange(_ scrollView: FastarScrollView) {
            guard !isApplyingFromSwift else { return }

            layoutDocument(scrollView: scrollView, containerSize: lastContainerSize)
            let center = visibleCenter(in: scrollView)
            var state = binding.wrappedValue
            state.zoom = scrollView.magnification
            state.center = center
            state.fitToWindow = false
            binding.wrappedValue = state
            lastAppliedViewport = state
        }

        func viewportDidMagnify(_ scrollView: FastarScrollView, with event: NSEvent) -> Bool {
            guard imageSize.width > 0,
                  imageSize.height > 0,
                  let documentView = scrollView.documentView else {
                return false
            }

            let oldZoom = scrollView.magnification
            let newZoom = min(max(oldZoom * (1 + event.magnification), scrollView.minMagnification), scrollView.maxMagnification)
            guard abs(newZoom - oldZoom) > 0.0001 else { return true }

            let visibleBefore = scrollView.contentView.bounds
            let anchorPoint = documentPoint(for: event, in: scrollView)
            let anchorImagePoint = normalizedImagePoint(for: anchorPoint, documentSize: documentView.bounds.size)
            let relativeAnchor = CGPoint(
                x: normalizedRelative(anchorPoint.x - visibleBefore.minX, length: visibleBefore.width),
                y: normalizedRelative(anchorPoint.y - visibleBefore.minY, length: visibleBefore.height)
            )

            isApplyingFromSwift = true
            scrollView.magnification = newZoom
            layoutDocument(scrollView: scrollView, containerSize: lastContainerSize)

            let newAnchorPoint = documentPoint(forNormalizedImagePoint: anchorImagePoint, documentSize: documentView.bounds.size)
            let visibleAfter = scrollView.contentView.bounds
            let targetOrigin = CGPoint(
                x: newAnchorPoint.x - (visibleAfter.width * relativeAnchor.x),
                y: newAnchorPoint.y - (visibleAfter.height * relativeAnchor.y)
            )
            scroll(toOrigin: targetOrigin, in: scrollView)
            isApplyingFromSwift = false

            var state = binding.wrappedValue
            state.zoom = newZoom
            state.center = visibleCenter(in: scrollView)
            state.fitToWindow = false
            binding.wrappedValue = state
            lastAppliedViewport = state
            return true
        }

        private func fitZoom(scrollView: FastarScrollView, containerSize: CGSize) -> CGFloat {
            guard imageSize.width > 0,
                  imageSize.height > 0,
                  containerSize.width > 0,
                  containerSize.height > 0 else {
                return 1
            }

            let widthScale = containerSize.width / imageSize.width
            let heightScale = containerSize.height / imageSize.height
            return min(max(min(widthScale, heightScale), scrollView.minMagnification), scrollView.maxMagnification)
        }

        private func layoutDocument(scrollView: FastarScrollView, containerSize: CGSize) {
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let magnification = max(scrollView.magnification, 0.01)
            let minimumDocumentSize = CGSize(
                width: max(containerSize.width / magnification, 0),
                height: max(containerSize.height / magnification, 0)
            )
            let documentSize = CGSize(
                width: max(imageSize.width, minimumDocumentSize.width),
                height: max(imageSize.height, minimumDocumentSize.height)
            )

            imageView?.setFrameSize(documentSize)
            scrollView.documentView?.setFrameSize(documentSize)
        }

        private func documentPoint(for event: NSEvent, in scrollView: FastarScrollView) -> CGPoint {
            guard let documentView = scrollView.documentView else { return CGPoint(x: 0.5, y: 0.5) }
            let pointInClipView = scrollView.contentView.convert(event.locationInWindow, from: nil)
            return documentView.convert(pointInClipView, from: scrollView.contentView)
        }

        private func normalizedImagePoint(for documentPoint: CGPoint, documentSize: CGSize) -> CGPoint {
            let imageOrigin = CGPoint(
                x: max((documentSize.width - imageSize.width) / 2, 0),
                y: max((documentSize.height - imageSize.height) / 2, 0)
            )

            return CGPoint(
                x: clamp((documentPoint.x - imageOrigin.x) / imageSize.width),
                y: clamp((documentPoint.y - imageOrigin.y) / imageSize.height)
            )
        }

        private func documentPoint(forNormalizedImagePoint point: CGPoint, documentSize: CGSize) -> CGPoint {
            let imageOrigin = CGPoint(
                x: max((documentSize.width - imageSize.width) / 2, 0),
                y: max((documentSize.height - imageSize.height) / 2, 0)
            )

            return CGPoint(
                x: imageOrigin.x + (imageSize.width * point.x),
                y: imageOrigin.y + (imageSize.height * point.y)
            )
        }

        private func visibleCenter(in scrollView: FastarScrollView) -> CGPoint {
            guard let documentView = scrollView.documentView,
                  documentView.bounds.width > 0,
                  documentView.bounds.height > 0 else {
                return CGPoint(x: 0.5, y: 0.5)
            }

            let visible = scrollView.contentView.bounds
            return CGPoint(
                x: clamp(visible.midX / documentView.bounds.width),
                y: clamp(visible.midY / documentView.bounds.height)
            )
        }

        private func scroll(to normalizedCenter: CGPoint, in scrollView: FastarScrollView) {
            guard let documentView = scrollView.documentView else { return }

            let visible = scrollView.contentView.bounds
            let maxX = max(documentView.bounds.width - visible.width, 0)
            let maxY = max(documentView.bounds.height - visible.height, 0)
            let origin = CGPoint(
                x: min(max((documentView.bounds.width * normalizedCenter.x) - (visible.width / 2), 0), maxX),
                y: min(max((documentView.bounds.height * normalizedCenter.y) - (visible.height / 2), 0), maxY)
            )

            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scroll(toOrigin origin: CGPoint, in scrollView: FastarScrollView) {
            guard let documentView = scrollView.documentView else { return }

            let visible = scrollView.contentView.bounds
            let maxX = max(documentView.bounds.width - visible.width, 0)
            let maxY = max(documentView.bounds.height - visible.height, 0)
            let clampedOrigin = CGPoint(
                x: min(max(origin.x, 0), maxX),
                y: min(max(origin.y, 0), maxY)
            )

            scrollView.contentView.scroll(to: clampedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func centerDocument(_ scrollView: FastarScrollView) {
            scroll(to: CGPoint(x: 0.5, y: 0.5), in: scrollView)
        }

        private func publishViewport(_ viewport: ImageViewport) {
            DispatchQueue.main.async {
                if self.binding.wrappedValue != viewport {
                    self.binding.wrappedValue = viewport
                }
            }
        }

        private func clamp(_ value: CGFloat) -> CGFloat {
            min(max(value, 0), 1)
        }

        private func normalizedRelative(_ value: CGFloat, length: CGFloat) -> CGFloat {
            guard length > 0 else { return 0.5 }
            return clamp(value / length)
        }
    }
}

protocol FastarScrollViewDelegate: AnyObject {
    func viewportDidChange(_ scrollView: FastarScrollView)
    func viewportDidMagnify(_ scrollView: FastarScrollView, with event: NSEvent) -> Bool
}

final class FastarScrollView: NSScrollView {
    weak var viewportDelegate: FastarScrollViewDelegate?
    var dropHandler: ((URL) -> Void)?
    var isDropEnabled = false {
        didSet {
            if isDropEnabled {
                registerForDraggedTypes([.fileURL, .URL])
            } else {
                unregisterDraggedTypes()
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        viewportDelegate?.viewportDidChange(self)
    }

    override func magnify(with event: NSEvent) {
        if viewportDelegate?.viewportDidMagnify(self, with: event) == true {
            return
        }

        super.magnify(with: event)
        viewportDelegate?.viewportDidChange(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropEnabled && draggedFileURL(from: sender) != nil ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropEnabled && draggedFileURL(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isDropEnabled, let url = draggedFileURL(from: sender) else { return false }
        dropHandler?(url)
        return true
    }

    private func draggedFileURL(from sender: NSDraggingInfo) -> URL? {
        FileDropReader.fileURL(from: sender.draggingPasteboard)
    }
}

final class FastarImageView: NSImageView {
    var dropHandler: ((URL) -> Void)?
    var isDropEnabled = false {
        didSet {
            if isDropEnabled {
                registerForDraggedTypes([.fileURL, .URL])
            } else {
                unregisterDraggedTypes()
            }
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropEnabled && FileDropReader.fileURL(from: sender.draggingPasteboard) != nil ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropEnabled && FileDropReader.fileURL(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isDropEnabled, let url = FileDropReader.fileURL(from: sender.draggingPasteboard) else { return false }
        dropHandler?(url)
        return true
    }
}

private enum FileDropReader {
    static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL],
           let url = urls.first {
            return url as URL
        }

        if let string = pasteboard.string(forType: .fileURL) {
            return URL(string: string)
        }

        if let data = pasteboard.data(forType: .fileURL) {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        return nil
    }
}
