import Foundation

struct ImageItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let filename: String
    let timestamp: Date
    var rating: Int

    var ratingURL: URL {
        url.deletingPathExtension().appendingPathExtension("fastar")
    }

    init(url: URL, rating: Int, timestamp: Date) {
        self.id = url
        self.url = url
        self.filename = url.lastPathComponent
        self.timestamp = timestamp
        self.rating = min(max(rating, 0), 5)
    }
}

struct RatingSidecar: Codable {
    let rating: Int
    let updatedAt: Date
}

enum RatingDisplay {
    static func label(for rating: Int) -> String {
        let rating = min(max(rating, 0), 5)
        return rating == 0 ? String(localized: "rating.none") : String(repeating: "★", count: rating)
    }
}

enum RatingFilter: String, CaseIterable, Identifiable {
    case all
    case zero
    case oneOrLess
    case one
    case oneOrMore
    case twoOrLess
    case two
    case twoOrMore
    case threeOrLess
    case three
    case threeOrMore
    case fourOrLess
    case four
    case fourOrMore
    case five

    var id: String { rawValue }

    static let menuOptions: [RatingFilter] = [
        .all,
        .five,
        .fourOrMore,
        .four,
        .fourOrLess,
        .threeOrMore,
        .three,
        .threeOrLess,
        .twoOrMore,
        .two,
        .twoOrLess,
        .oneOrMore,
        .one,
        .oneOrLess,
        .zero
    ]

    var localizedKey: String {
        switch self {
        case .all: "filter.all"
        case .zero: "filter.zero"
        case .oneOrLess: "filter.oneOrLess"
        case .one: "filter.one"
        case .oneOrMore: "filter.oneOrMore"
        case .twoOrLess: "filter.twoOrLess"
        case .two: "filter.two"
        case .twoOrMore: "filter.twoOrMore"
        case .threeOrLess: "filter.threeOrLess"
        case .three: "filter.three"
        case .threeOrMore: "filter.threeOrMore"
        case .fourOrLess: "filter.fourOrLess"
        case .four: "filter.four"
        case .fourOrMore: "filter.fourOrMore"
        case .five: "filter.five"
        }
    }

    func matches(_ rating: Int) -> Bool {
        switch self {
        case .all: true
        case .zero: rating == 0
        case .oneOrLess: rating <= 1
        case .one: rating == 1
        case .oneOrMore: rating >= 1
        case .twoOrLess: rating <= 2
        case .two: rating == 2
        case .twoOrMore: rating >= 2
        case .threeOrLess: rating <= 3
        case .three: rating == 3
        case .threeOrMore: rating >= 3
        case .fourOrLess: rating <= 4
        case .four: rating == 4
        case .fourOrMore: rating >= 4
        case .five: rating == 5
        }
    }
}

enum ThumbnailSort: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case timestampAscending
    case timestampDescending

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .nameAscending: "sort.nameAscending"
        case .nameDescending: "sort.nameDescending"
        case .timestampAscending: "sort.timestampAscending"
        case .timestampDescending: "sort.timestampDescending"
        }
    }

    func sorted(_ items: [ImageItem]) -> [ImageItem] {
        items.sorted(by: areInIncreasingOrder)
    }

    private func areInIncreasingOrder(_ lhs: ImageItem, _ rhs: ImageItem) -> Bool {
        switch self {
        case .nameAscending:
            return nameAscending(lhs, rhs)
        case .nameDescending:
            return nameDescending(lhs, rhs)
        case .timestampAscending:
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return nameAscending(lhs, rhs)
        case .timestampDescending:
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return nameAscending(lhs, rhs)
        }
    }

    private func nameAscending(_ lhs: ImageItem, _ rhs: ImageItem) -> Bool {
        let comparison = lhs.filename.localizedStandardCompare(rhs.filename)
        if comparison == .orderedSame {
            return lhs.url.path < rhs.url.path
        }
        return comparison == .orderedAscending
    }

    private func nameDescending(_ lhs: ImageItem, _ rhs: ImageItem) -> Bool {
        let comparison = lhs.filename.localizedStandardCompare(rhs.filename)
        if comparison == .orderedSame {
            return lhs.url.path > rhs.url.path
        }
        return comparison == .orderedDescending
    }
}

struct ImageViewport: Equatable {
    var zoom: CGFloat = 1
    var center: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var fitToWindow: Bool = true
    var fitRequestID: Int = 0

    func linkedCopy() -> ImageViewport {
        ImageViewport(zoom: zoom, center: center, fitToWindow: fitToWindow, fitRequestID: fitRequestID)
    }

    mutating func applyLinkedState(from other: ImageViewport) {
        zoom = other.zoom
        center = other.center
        fitToWindow = other.fitToWindow
        fitRequestID = other.fitRequestID
    }
}

struct ImageMetadata: Equatable {
    let filename: String
    let path: String
    let fileSizeDescription: String
    let pixelWidth: Int?
    let pixelHeight: Int?
    let colorModel: String?
    let dpiWidth: Double?
    let dpiHeight: Double?
    let rows: [MetadataRow]
}

struct MetadataRow: Identifiable, Equatable {
    let id = UUID()
    let group: String
    let key: String
    let value: String
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String
}

enum ExportRatingFormat: Int, CaseIterable {
    case none
    case xmp
    case fastar
}
