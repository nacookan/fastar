import AppKit
import Foundation

@MainActor
final class ImageLibraryStore: ObservableObject {
    @Published var folderURL: URL?
    @Published var items: [ImageItem] = []
    @Published private(set) var filteredItems: [ImageItem] = []
    @Published private(set) var thumbnailAnchorID: URL?
    @Published var selectedID: URL? {
        didSet {
            updateThumbnailAnchor()
        }
    }
    @Published var filter: RatingFilter = .all {
        didSet {
            rebuildFilteredItems()
            ensureSelectionExists()
        }
    }
    @Published var sortOrder: ThumbnailSort = .timestampAscending {
        didSet {
            rebuildFilteredItems()
            ensureSelectionExists()
        }
    }
    @Published var currentImage: NSImage?
    @Published var currentMetadata: ImageMetadata?
    @Published var isLoadingFolder = false
    @Published var presentedError: AppError?

    private var selectionTask: Task<Void, Never>?

    var selectedItem: ImageItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    func openFolder(_ url: URL) async {
        selectionTask?.cancel()
        isLoadingFolder = true
        folderURL = url
        currentImage = nil
        currentMetadata = nil
        selectedID = nil
        items = []
        filteredItems = []
        thumbnailAnchorID = nil

        let result = await Task.detached(priority: .userInitiated) {
            loadItems(in: url)
        }.value

        isLoadingFolder = false

        switch result {
        case .success(let loadedItems):
            items = loadedItems
            rebuildFilteredItems()
            selectedID = filteredItems.first?.id
            loadSelectedImage()
        case .failure(let error):
            items = []
            filteredItems = []
            thumbnailAnchorID = nil
            presentedError = AppError(message: error.localizedDescription)
        }
    }

    func select(_ item: ImageItem) {
        selectedID = item.id
        loadSelectedImage()
    }

    func selectNext() {
        selectRelative(offset: 1)
    }

    func selectPrevious() {
        selectRelative(offset: -1)
    }

    func setRating(_ rating: Int) {
        guard let selectedID,
              let index = items.firstIndex(where: { $0.id == selectedID }) else { return }

        let sanitizedRating = min(max(rating, 0), 5)
        var updatedItem = items[index]
        updatedItem.rating = sanitizedRating
        items[index] = updatedItem
        rebuildFilteredItems()
        saveRating(for: updatedItem)

        if !filter.matches(sanitizedRating) {
            selectNearestVisible(around: index)
        }
    }

    func exportFilteredImages(to destination: URL) async {
        let files = filteredItems
        guard !files.isEmpty else {
            presentedError = AppError(message: String(localized: "error.noFilesToExport"))
            return
        }

        let result = await Task.detached(priority: .userInitiated) {
            export(files: files, to: destination)
        }.value

        switch result {
        case .success(let count):
            presentedError = AppError(message: String(format: String(localized: "export.completed"), count))
        case .failure(let error):
            presentedError = AppError(message: error.localizedDescription)
        }
    }

    private func rebuildFilteredItems() {
        filteredItems = sortOrder.sorted(items.filter { filter.matches($0.rating) })
        updateThumbnailAnchor()
    }

    private func updateThumbnailAnchor() {
        guard !filteredItems.isEmpty else {
            thumbnailAnchorID = nil
            return
        }

        guard let selectedID else {
            thumbnailAnchorID = filteredItems.first?.id
            return
        }

        if filteredItems.contains(where: { $0.id == selectedID }) {
            thumbnailAnchorID = selectedID
            return
        }

        let sortedItems = sortOrder.sorted(items)
        guard let selectedIndex = sortedItems.firstIndex(where: { $0.id == selectedID }) else {
            thumbnailAnchorID = filteredItems.first?.id
            return
        }

        let sortedIndexesByID = Dictionary(
            uniqueKeysWithValues: sortedItems.enumerated().map { ($0.element.id, $0.offset) }
        )

        thumbnailAnchorID = filteredItems.min { lhs, rhs in
            let lhsDistance = abs((sortedIndexesByID[lhs.id] ?? 0) - selectedIndex)
            let rhsDistance = abs((sortedIndexesByID[rhs.id] ?? 0) - selectedIndex)
            if lhsDistance == rhsDistance {
                return (sortedIndexesByID[lhs.id] ?? 0) < (sortedIndexesByID[rhs.id] ?? 0)
            }
            return lhsDistance < rhsDistance
        }?.id
    }

    private func selectRelative(offset: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else { return }

        guard let selectedID,
              let currentVisibleIndex = visible.firstIndex(where: { $0.id == selectedID }) else {
            select(visible[0])
            return
        }

        let nextIndex = min(max(currentVisibleIndex + offset, 0), visible.count - 1)
        select(visible[nextIndex])
    }

    private func ensureSelectionExists() {
        guard selectedID == nil else { return }
        self.selectedID = filteredItems.first?.id
        loadSelectedImage()
    }

    private func selectNearestVisible(around itemIndex: Int) {
        let candidateIDs = items.enumerated()
            .filter { filter.matches($0.element.rating) }
            .map { ($0.offset, $0.element.id) }

        guard !candidateIDs.isEmpty else {
            selectedID = nil
            currentImage = nil
            currentMetadata = nil
            return
        }

        let nearest = candidateIDs.min { lhs, rhs in
            abs(lhs.0 - itemIndex) < abs(rhs.0 - itemIndex)
        }

        selectedID = nearest?.1
        loadSelectedImage()
    }

    private func loadSelectedImage() {
        selectionTask?.cancel()
        currentMetadata = nil

        guard let selectedItem else {
            currentImage = nil
            return
        }
        let url = selectedItem.url

        selectionTask = Task {
            let loadedImage = await ImageMetadataReader.loadDisplayImage(url: url)
            guard !Task.isCancelled else { return }
            currentImage = loadedImage

            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }

            let loadedMetadata = await ImageMetadataReader.readMetadata(url: url)
            guard !Task.isCancelled else { return }
            currentMetadata = loadedMetadata
        }
    }

    private func saveRating(for item: ImageItem) {
        let sidecar = RatingSidecar(rating: item.rating, updatedAt: Date())

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sidecar)
            try data.write(to: item.ratingURL, options: .atomic)
        } catch {
            presentedError = AppError(message: error.localizedDescription)
        }
    }
}

private func loadItems(in folderURL: URL) -> Result<[ImageItem], Error> {
    do {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let items = urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && ImageMetadataReader.isSupportedImageURL(url)
            }
            .map { url in
                ImageItem(url: url, rating: loadRating(for: url), timestamp: fileTimestamp(for: url))
            }

        return .success(items)
    } catch {
        return .failure(error)
    }
}

private func fileTimestamp(for imageURL: URL) -> Date {
    let values = try? imageURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
    return values?.contentModificationDate ?? values?.creationDate ?? .distantPast
}

private func loadRating(for imageURL: URL) -> Int {
    let ratingURL = imageURL.deletingPathExtension().appendingPathExtension("fastar")
    guard let data = try? Data(contentsOf: ratingURL) else { return 0 }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let sidecar = try? decoder.decode(RatingSidecar.self, from: data) {
        return min(max(sidecar.rating, 0), 5)
    }

    if let rawValue = String(data: data, encoding: .utf8),
       let rating = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return min(max(rating, 0), 5)
    }

    return 0
}

private func export(files: [ImageItem], to destination: URL) -> Result<Int, Error> {
    do {
        var copied = 0

        for item in files {
            let imageDestination = uniqueDestinationURL(for: item.url.lastPathComponent, in: destination)
            try FileManager.default.copyItem(at: item.url, to: imageDestination)
            copied += 1

            if FileManager.default.fileExists(atPath: item.ratingURL.path) {
                let sidecarDestination = imageDestination.deletingPathExtension().appendingPathExtension("fastar")
                try? FileManager.default.copyItem(at: item.ratingURL, to: sidecarDestination)
            }
        }

        return .success(copied)
    } catch {
        return .failure(error)
    }
}

private func uniqueDestinationURL(for filename: String, in folder: URL) -> URL {
    let base = folder.appendingPathComponent(filename)
    guard FileManager.default.fileExists(atPath: base.path) else {
        return base
    }

    let stem = base.deletingPathExtension().lastPathComponent
    let ext = base.pathExtension

    for index in 1...999 {
        let candidateName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
        let candidate = folder.appendingPathComponent(candidateName)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    return folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
}
