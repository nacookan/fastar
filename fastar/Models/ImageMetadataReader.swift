import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageMetadataReader {
    private static let supportedExtensions: Set<String> = {
        guard let utis = CGImageSourceCopyTypeIdentifiers() as? [String] else { return [] }
        var extensions = Set<String>()
        for utiString in utis {
            if let uti = UTType(utiString) {
                for ext in uti.tags[.filenameExtension] ?? [] {
                    extensions.insert(ext.lowercased())
                }
            }
        }
        return extensions
    }()

    static func isSupportedImageURL(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func loadEmbeddedThumbnail(url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

            // まず埋め込みサムネを試みる（RAWの埋め込みJPEGは高速）
            let embeddedOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
            ]
            let embedded = CGImageSourceCreateThumbnailAtIndex(source, 0, embeddedOpts as CFDictionary)
            let embeddedIsUsable = embedded.map { min($0.width, $0.height) >= 600 } ?? false

            // 埋め込みサムネがない・小さすぎる場合はイメージから直接デコード（JPEGは高速）
            let cgImage: CGImage?
            if embeddedIsUsable {
                cgImage = embedded
            } else {
                let decodeOpts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048
                ]
                cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOpts as CFDictionary)
            }

            guard let cgImage, min(cgImage.width, cgImage.height) >= 600 else { return nil }

            // NSImage.size をフル解像度の視覚的寸法に合わせることで、
            // ズーム倍率の計算をフル画像と一致させる
            let displaySize: CGSize
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let pw = props[kCGImagePropertyPixelWidth] as? CGFloat,
               let ph = props[kCGImagePropertyPixelHeight] as? CGFloat {
                let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
                let isRotated90 = (5...8).contains(orientation)
                displaySize = isRotated90 ? CGSize(width: ph, height: pw) : CGSize(width: pw, height: ph)
            } else {
                displaySize = CGSize(width: cgImage.width, height: cgImage.height)
            }

            return NSImage(cgImage: cgImage, size: displaySize)
        }.value
    }

    static func loadDisplayImage(url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return NSImage(contentsOf: url)
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 65536
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return NSImage(contentsOf: url)
            }

            return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
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
