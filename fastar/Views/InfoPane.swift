import SwiftUI

struct InfoPane: View {
    let item: ImageItem?
    let metadata: ImageMetadata?

    @State private var metadataFilterText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("info.title")
                    .font(.headline)

                if let item {
                    section("info.file") {
                        InfoRow(label: "info.filename", value: item.filename)
                        InfoRow(label: "info.rating", value: RatingDisplay.label(for: item.rating))
                        if let metadata {
                            InfoRow(label: "info.filesize", value: metadata.fileSizeDescription)
                            InfoRow(label: "info.path", value: metadata.path)
                        }
                    }

                    if let metadata {
                        section("info.image") {
                            if let width = metadata.pixelWidth, let height = metadata.pixelHeight {
                                InfoRow(label: "info.dimensions", value: "\(width) x \(height) px")
                            }
                            if let colorModel = metadata.colorModel {
                                InfoRow(label: "info.colorModel", value: colorModel)
                            }
                            if let dpiWidth = metadata.dpiWidth, let dpiHeight = metadata.dpiHeight {
                                InfoRow(label: "info.dpi", value: "\(Int(dpiWidth)) x \(Int(dpiHeight))")
                            }
                        }

                        if !metadata.rows.isEmpty {
                            section("info.exif") {
                                TextField("info.exifFilterPlaceholder", text: $metadataFilterText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)

                                if filteredMetadataRows.isEmpty {
                                    Text("info.exifNoMatches")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(filteredMetadataRows.prefix(80)) { row in
                                        InfoRow(label: "\(row.group) \(row.key)", value: row.value)
                                    }
                                }
                            }
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else {
                    Text("info.noSelection")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func section<Content: View>(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
            Divider()
        }
    }

    private var filteredMetadataRows: [MetadataRow] {
        guard let metadata else { return [] }

        let terms = metadataFilterText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else {
            return metadata.rows
        }

        return metadata.rows.filter { row in
            let haystack = "\(row.group) \(row.key) \(row.value)".lowercased()
            return terms.contains { haystack.contains($0) }
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
