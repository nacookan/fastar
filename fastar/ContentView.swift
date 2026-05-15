import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var library = ImageLibraryStore()

    @State private var splitEnabled = false
    @State private var linkedViewports = false
    @State private var mainViewport = ImageViewport()
    @State private var comparisonViewport = ImageViewport()
    @State private var comparisonImage: NSImage?
    @State private var comparisonURL: URL?
    @State private var isSynchronizingViewport = false
    @State private var ratingToastText: String?
    @State private var ratingToastTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                imageWorkspace
                    .frame(minWidth: 560)

                InfoPane(item: library.selectedItem, metadata: library.currentMetadata)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            }

            Divider()

            ThumbnailStrip(
                items: library.filteredItems,
                totalItemCount: library.items.count,
                selectedID: library.selectedID,
                scrollAnchorID: library.thumbnailAnchorID,
                filter: $library.filter,
                sortOrder: $library.sortOrder,
                isLoading: library.isLoadingFolder,
                onSelect: library.select,
                onExport: exportFilteredImages
            )
            .frame(height: 150)
        }
        .toolbar {
            toolbarContent
        }
        .background(
            KeyCaptureView { event in
                handleKey(event)
            }
        )
        .background(WindowConfigurator())
        .overlay(alignment: .top) {
            if let ratingToastText {
                Text(ratingToastText)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: ratingToastText)
        .alert(item: $library.presentedError) { error in
            Alert(
                title: Text("alert.error"),
                message: Text(error.message),
                dismissButton: .default(Text("button.ok"))
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarOpenFolder)) { _ in
            openFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarZoomFit)) { _ in
            fitMainImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarZoom100)) { _ in
            setMainZoom(1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarZoom400)) { _ in
            setMainZoom(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarZoom800)) { _ in
            setMainZoom(8)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarToggleSplit)) { _ in
            splitEnabled.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarToggleLink)) { _ in
            if splitEnabled {
                linkedViewports.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastarSetRating)) { notification in
            if let rating = notification.object as? Int {
                applyRating(rating)
            }
        }
        .onDisappear {
            ratingToastTask?.cancel()
        }
        .onChange(of: splitEnabled) { _, enabled in
            if !enabled {
                linkedViewports = false
            } else if linkedViewports {
                synchronizeComparisonFromMain()
            }
        }
        .onChange(of: linkedViewports) { _, enabled in
            guard enabled, splitEnabled else { return }
            synchronizeComparisonFromMain()
        }
        .onChange(of: mainViewport) { _, _ in
            guard splitEnabled, linkedViewports, !isSynchronizingViewport else { return }
            isSynchronizingViewport = true
            let nextViewport = mainViewport.linkedCopy()
            if comparisonViewport != nextViewport {
                comparisonViewport = nextViewport
            }
            isSynchronizingViewport = false
        }
        .onChange(of: comparisonViewport) { _, _ in
            guard splitEnabled, linkedViewports, !isSynchronizingViewport else { return }
            isSynchronizingViewport = true
            let nextViewport = comparisonViewport.linkedCopy()
            if mainViewport != nextViewport {
                mainViewport = nextViewport
            }
            isSynchronizingViewport = false
        }
    }

    private var imageWorkspace: some View {
        Group {
            if splitEnabled {
                HSplitView {
                    ImageViewerPanel(
                        title: comparisonURL?.lastPathComponent ?? String(localized: "viewer.compare"),
                        subtitle: String(localized: "viewer.dropCompare"),
                        image: comparisonImage,
                        viewport: $comparisonViewport,
                        acceptsDrop: true,
                        onDropURL: loadComparisonImage
                    )
                    .frame(minWidth: 280)

                    ImageViewerPanel(
                        title: library.selectedItem?.filename ?? String(localized: "viewer.main"),
                        subtitle: library.folderURL == nil ? String(localized: "viewer.openFolderPrompt") : String(localized: "viewer.noImage"),
                        image: library.currentImage,
                        viewport: $mainViewport,
                        acceptsDrop: false,
                        onDropURL: { _ in }
                    )
                    .frame(minWidth: 360)
                }
            } else {
                ImageViewerPanel(
                    title: library.selectedItem?.filename ?? String(localized: "viewer.main"),
                    subtitle: library.folderURL == nil ? String(localized: "viewer.openFolderPrompt") : String(localized: "viewer.noImage"),
                    image: library.currentImage,
                    viewport: $mainViewport,
                    acceptsDrop: false,
                    onDropURL: { _ in }
                )
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: openFolder) {
                Label("toolbar.openFolder", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .help("toolbar.openFolder")
        }

        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
                Toggle(isOn: $splitEnabled) {
                    Label("toolbar.split", systemImage: "rectangle.split.2x1")
                }
                .toggleStyle(.button)
                .help("toolbar.split")

                Toggle(isOn: $linkedViewports) {
                    Label("toolbar.link", systemImage: "link")
                }
                .toggleStyle(.button)
                .disabled(!splitEnabled)
                .help("toolbar.link")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 10) {
                Button("toolbar.fit") {
                    fitMainImage()
                }
                .buttonStyle(.borderless)
                .help("toolbar.fit")

                Button("100%") {
                    setMainZoom(1)
                }
                .buttonStyle(.borderless)
                .help("toolbar.zoom100")

                Button("400%") {
                    setMainZoom(4)
                }
                .buttonStyle(.borderless)
                .help("toolbar.zoom400")

                Button("800%") {
                    setMainZoom(8)
                }
                .buttonStyle(.borderless)
                .help("toolbar.zoom800")

                Divider()
                    .frame(height: 20)

                Slider(
                    value: Binding(
                        get: { Double(mainViewport.zoom) },
                        set: { setMainZoom(CGFloat($0)) }
                    ),
                    in: 0.05...8
                )
                .frame(width: 190)
                .help("toolbar.zoomSlider")

                Text("\(Int((mainViewport.zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 48, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "button.open")
        panel.message = String(localized: "openPanel.message")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await library.openFolder(url)
            mainViewport = ImageViewport()
            fitMainImage()
        }
    }

    private func exportFilteredImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "button.export")
        panel.message = String(localized: "exportPanel.message")

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task {
            await library.exportFilteredImages(to: destination)
        }
    }

    private func loadComparisonImage(_ url: URL) {
        guard ImageMetadataReader.isSupportedImageURL(url) else { return }

        Task {
            let image = await ImageMetadataReader.loadDisplayImage(url: url)
            await MainActor.run {
                comparisonURL = url
                comparisonImage = image
                comparisonViewport = linkedViewports ? mainViewport.linkedCopy() : ImageViewport(fitToWindow: true)
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }

        switch event.keyCode {
        case 123:
            library.selectPrevious()
            return true
        case 124:
            library.selectNext()
            return true
        default:
            if let characters = event.charactersIgnoringModifiers,
               characters.count == 1,
               let rating = Int(characters),
               (0...5).contains(rating) {
                applyRating(rating)
                return true
            }
        }

        return false
    }

    private func setMainZoom(_ zoom: CGFloat) {
        mainViewport.fitToWindow = false
        mainViewport.zoom = min(max(zoom, 0.05), 8)
    }

    private func fitMainImage() {
        mainViewport.fitToWindow = true
        mainViewport.fitRequestID += 1
    }

    private func applyRating(_ rating: Int) {
        guard library.selectedID != nil else { return }

        let sanitizedRating = min(max(rating, 0), 5)
        library.setRating(sanitizedRating)
        showRatingToast(for: sanitizedRating)
    }

    private func showRatingToast(for rating: Int) {
        ratingToastTask?.cancel()
        ratingToastText = String(format: String(localized: "toast.rating"), RatingDisplay.label(for: rating))

        ratingToastTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                ratingToastText = nil
                ratingToastTask = nil
            }
        }
    }

    private func synchronizeComparisonFromMain() {
        isSynchronizingViewport = true
        let nextViewport = mainViewport.linkedCopy()
        if comparisonViewport != nextViewport {
            comparisonViewport = nextViewport
        }
        isSynchronizingViewport = false
    }
}
