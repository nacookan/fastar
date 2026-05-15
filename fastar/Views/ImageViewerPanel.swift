import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageViewerPanel: View {
    let title: String
    let subtitle: String
    let image: NSImage?
    @Binding var viewport: ImageViewport
    let acceptsDrop: Bool
    let onDropURL: (URL) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    ZoomableImageView(
                        image: image,
                        viewport: $viewport,
                        containerSize: geometry.size,
                        acceptsDrop: acceptsDrop,
                        onDropURL: onDropURL
                    )
                } else {
                    emptyState
                }

                VStack {
                    HStack {
                        Text(title)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)

                        Spacer()
                    }

                    Spacer()
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .padding(8)
                }
            }
            .clipped()
            .onDrop(
                of: [UTType.fileURL.identifier, UTType.url.identifier],
                isTargeted: acceptsDrop ? $isDropTargeted : nil,
                perform: acceptsDrop ? handleDrop(providers:) : { _ in false }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let typeIdentifiers = [UTType.fileURL.identifier, UTType.url.identifier]
        guard let provider = providers.first(where: { provider in
            typeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }) else {
            return false
        }

        let typeIdentifier = typeIdentifiers.first { provider.hasItemConformingToTypeIdentifier($0) } ?? UTType.fileURL.identifier
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            let url: URL?

            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let nsURL = item as? NSURL {
                url = nsURL as URL
            } else {
                url = item as? URL ?? (item as? String).flatMap(URL.init(string:))
            }

            if let url {
                DispatchQueue.main.async {
                    onDropURL(url)
                }
            }
        }

        return true
    }
}
