import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageMetadataReader {
    static func isSupportedImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png"].contains(ext)
    }

    static func loadDisplayImage(url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return NSImage(contentsOf: url)
            }

            return NSImage(
                cgImage: cgImage,
                size: CGSize(width: cgImage.width, height: cgImage.height)
            )
        }.value
    }

    static func readMetadata(url: URL) async -> ImageMetadata {
        await Task.detached(priority: .utility) {
            metadata(url: url)
        }.value
    }

    private static func metadata(url: URL) -> ImageMetadata {
        let fileSize = fileSizeDescription(url: url)
        var pixelWidth: Int?
        var pixelHeight: Int?
        var colorModel: String?
        var dpiWidth: Double?
        var dpiHeight: Double?
        var rows: [MetadataRow] = []

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int
            pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
            colorModel = properties[kCGImagePropertyColorModel] as? String
            dpiWidth = number(properties[kCGImagePropertyDPIWidth])
            dpiHeight = number(properties[kCGImagePropertyDPIHeight])

            rows.append(contentsOf: rowsFromTopLevelProperties(properties))
            rows.append(contentsOf: rowsFromDictionary(properties[kCGImagePropertyExifDictionary], group: "EXIF"))
            rows.append(contentsOf: rowsFromDictionary(properties[kCGImagePropertyTIFFDictionary], group: "TIFF"))
            rows.append(contentsOf: rowsFromDictionary(properties[kCGImagePropertyGPSDictionary], group: "GPS"))
            rows.append(contentsOf: rowsFromDictionary(properties[kCGImagePropertyIPTCDictionary], group: "IPTC"))
            rows.append(contentsOf: rowsFromDictionary(properties[kCGImagePropertyPNGDictionary], group: "PNG"))
        }

        return ImageMetadata(
            filename: url.lastPathComponent,
            path: url.path,
            fileSizeDescription: fileSize,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            colorModel: colorModel,
            dpiWidth: dpiWidth,
            dpiHeight: dpiHeight,
            rows: rows
        )
    }

    private static func rowsFromTopLevelProperties(_ properties: [CFString: Any]) -> [MetadataRow] {
        let keys: [(CFString, String)] = [
            (kCGImagePropertyProfileName, "Profile"),
            (kCGImagePropertyOrientation, "Orientation"),
            (kCGImagePropertyDepth, "Depth")
        ]

        return keys.compactMap { key, label in
            guard let value = properties[key] else { return nil }
            return MetadataRow(group: "Image", key: label, value: valueDescription(value))
        }
    }

    private static func rowsFromDictionary(_ value: Any?, group: String) -> [MetadataRow] {
        guard let dictionary = value as? [AnyHashable: Any] else { return [] }

        return dictionary.keys
            .sorted { String(describing: $0) < String(describing: $1) }
            .compactMap { key in
                guard let value = dictionary[key] else { return nil }
                if value is [AnyHashable: Any] {
                    return nil
                }
                return MetadataRow(
                    group: group,
                    key: cleanKey(String(describing: key)),
                    value: valueDescription(value)
                )
            }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func valueDescription(_ value: Any) -> String {
        if let date = value as? Date {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
        }

        if let array = value as? [Any] {
            return array.map { valueDescription($0) }.joined(separator: ", ")
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return String(describing: value)
    }

    private static func cleanKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "{Exif}", with: "")
            .replacingOccurrences(of: "{TIFF}", with: "")
            .replacingOccurrences(of: "{GPS}", with: "")
            .replacingOccurrences(of: "{PNG}", with: "")
            .replacingOccurrences(of: "{IPTC}", with: "")
    }

    private static func fileSizeDescription(url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values?.fileSize else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}
