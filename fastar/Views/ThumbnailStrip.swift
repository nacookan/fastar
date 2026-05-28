import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailStrip: View {
    let items: [ImageItem]
    let totalItemCount: Int
    let selectedID: URL?
    let scrollAnchorID: URL?
    @Binding var filter: RatingFilter
    @Binding var sortOrder: ThumbnailSort
    let isLoading: Bool
    let onSelect: (ImageItem) -> Void
    let onExport: () -> Void
    var onDropFolder: ((URL) -> Void)? = nil

    @State private var visibleThumbnailIDs: Set<URL> = []
    @State private var skipNextSelectionScrollID: URL?
    @State private var pendingSelectionScrollWorkItem: DispatchWorkItem?
    @State private var isFolderDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.horizontal, 16)
                            } else if items.isEmpty {
                                Text("thumbnails.empty")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ForEach(items) { item in
                                    ThumbnailCell(
                                        item: item,
                                        isSelected: selectedID == item.id,
                                        onSelect: {
                                            skipNextSelectionScrollID = item.id
                                            onSelect(item)
                                        }
                                    )
                                    .id(item.id)
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: ThumbnailFramePreferenceKey.self,
                                                value: [item.id: proxy.frame(in: .named(thumbnailScrollCoordinateSpace))]
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .coordinateSpace(name: thumbnailScrollCoordinateSpace)
                    .onPreferenceChange(ThumbnailFramePreferenceKey.self) { frames in
                        let nextVisibleIDs = visibleIDs(in: frames, viewportWidth: geometry.size.width)
                        if visibleThumbnailIDs != nextVisibleIDs {
                            visibleThumbnailIDs = nextVisibleIDs
                        }
                        if let scrollAnchorID, nextVisibleIDs.contains(scrollAnchorID) {
                            pendingSelectionScrollWorkItem?.cancel()
                            pendingSelectionScrollWorkItem = nil
                        }
                    }
                    .onChange(of: selectedID) { _, selectedID in
                        scheduleSelectionScrollIfNeeded(scrollAnchorID ?? selectedID, with: proxy)
                    }
                    .onChange(of: scrollAnchorID) { _, scrollAnchorID in
                        scheduleSelectionScrollIfNeeded(scrollAnchorID, with: proxy)
                    }
                    .onChange(of: items.map(\.id)) { _, _ in
                        scheduleSelectionScrollIfNeeded(scrollAnchorID ?? selectedID, with: proxy)
                    }
                }
            }

            Divider()

            controlPane
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(width: 220)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isFolderDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.url.identifier],
            isTargeted: onDropFolder != nil ? $isFolderDropTargeted : nil,
            perform: onDropFolder != nil ? handleFolderDrop(providers:) : { _ in false }
        )
        .onDisappear {
            pendingSelectionScrollWorkItem?.cancel()
        }
    }

    private func handleFolderDrop(providers: [NSItemProvider]) -> Bool {
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
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists && isDir.boolValue else { return }
                DispatchQueue.main.async {
                    onDropFolder?(url)
                }
            }
        }

        return true
    }

    private func scheduleSelectionScrollIfNeeded(_ selectedID: URL?, with proxy: ScrollViewProxy) {
        pendingSelectionScrollWorkItem?.cancel()
        pendingSelectionScrollWorkItem = nil

        guard let selectedID else { return }

        if skipNextSelectionScrollID == selectedID {
            skipNextSelectionScrollID = nil
            return
        }

        guard items.contains(where: { $0.id == selectedID }) else { return }
        guard !visibleThumbnailIDs.contains(selectedID) else { return }

        let workItem = DispatchWorkItem {
            proxy.scrollTo(selectedID, anchor: .center)
        }

        pendingSelectionScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400), execute: workItem)
    }

    private func visibleIDs(in frames: [URL: CGRect], viewportWidth: CGFloat) -> Set<URL> {
        Set(frames.compactMap { id, frame in
            frame.maxX > 0 && frame.minX < viewportWidth ? id : nil
        })
    }

    private var controlPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(RatingFilter.menuOptions) { option in
                    Button {
                        filter = option
                    } label: {
                        MenuChoiceRow(
                            titleKey: option.localizedKey,
                            isSelected: filter == option
                        )
                    }
                }
            } label: {
                MenuField(titleKey: filter.localizedKey)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("filter.label")

            Menu {
                ForEach(ThumbnailSort.allCases) { option in
                    Button {
                        sortOrder = option
                    } label: {
                        MenuChoiceRow(
                            titleKey: option.localizedKey,
                            isSelected: sortOrder == option
                        )
                    }
                }
            } label: {
                MenuField(titleKey: sortOrder.localizedKey)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("sort.label")

            Text(listPositionText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: thumbnailControlWidth, alignment: .center)
                .padding(.top, 2)

            Button(action: onExport) {
                Label("button.export", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .frame(width: thumbnailControlWidth, height: 34)
            .disabled(items.isEmpty)
        }
        .frame(width: thumbnailControlWidth)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var listPositionText: String {
        guard let selectedID,
              let selectedIndex = items.firstIndex(where: { $0.id == selectedID }) else {
            return String(
                format: String(localized: "thumbnails.positionOutside"),
                items.count,
                totalItemCount
            )
        }

        let position = selectedIndex + 1

        return String(
            format: String(localized: "thumbnails.position"),
            position,
            items.count,
            totalItemCount
        )
    }
}

private let thumbnailControlWidth: CGFloat = 196
private let thumbnailScrollCoordinateSpace = "thumbnail-scroll"

private struct ThumbnailFramePreferenceKey: PreferenceKey {
    static var defaultValue: [URL: CGRect] = [:]

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct MenuField: View {
    let titleKey: String

    var body: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(titleKey))
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(width: thumbnailControlWidth, height: 34)
        .background(Color(nsColor: .controlColor), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MenuChoiceRow: View {
    let titleKey: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isSelected {
                Image(systemName: "checkmark")
            }

            Text(LocalizedStringKey(titleKey))
        }
    }
}

private struct ThumbnailCell: View {
    let item: ImageItem
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                ZStack {
                    Rectangle()
                        .fill(Color(nsColor: .underPageBackgroundColor))

                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 104, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(ratingText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.rating == 0 ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 104, height: 16, alignment: .center)
            }
            .padding(4)
            .frame(width: 114, height: 122)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(item.filename)
        .onDrag {
            let provider = NSItemProvider(object: item.url as NSURL)
            provider.suggestedName = item.filename
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                completion(item.url.dataRepresentation, nil)
                return nil
            }
            return provider
        }
        .task(id: item.id) {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: item.url)
        }
    }

    private var ratingText: String {
        RatingDisplay.label(for: item.rating)
    }
}
