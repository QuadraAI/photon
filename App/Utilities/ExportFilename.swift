//
//  ExportFilename.swift
//  Photon
//

import Foundation

/// The name an exported file gets, and the rules that keep it from colliding.
///
/// Pure arithmetic over strings and URLs, so the awkward cases — a pasted
/// extension, a name that is only slashes, a destination that is the original
/// photo — are testable without writing anything.
nonisolated enum ExportFilename {
    /// What a photo is called when the user has not typed anything else.
    static func defaultBaseName(for photo: PhotoItem) -> String {
        "\(photo.baseName)-edit"
    }

    /// `raw` as a file-system-safe base name, with no extension.
    ///
    /// Removes path separators, the Finder's colon, control newlines, and
    /// leading/trailing dots and whitespace. A pasted image extension is
    /// dropped so "photo.jpg" becomes "photo.avif", not "photo.jpg.avif".
    static func normalizedBaseName(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\n", with: "-")
            .replacingOccurrences(of: "\r", with: "-")
            .trimmingCharacters(in: trimmedCharacters)

        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let extensionName = name[name.index(after: dot)...].lowercased()
            if knownExtensions.contains(extensionName) {
                name = String(name[..<dot]).trimmingCharacters(in: trimmedCharacters)
            }
        }

        return String(name.prefix(maxLength))
    }

    /// The complete file name, or nil when the base name is empty.
    static func fileName(baseName: String, format: ExportFormat) -> String? {
        let name = normalizedBaseName(baseName)
        guard !name.isEmpty else { return nil }
        return "\(name).\(format.fileExtension)"
    }

    /// The first file name in `folder` that neither exists nor names the source.
    ///
    /// A collision becomes "name 2.ext", then "name 3.ext", and so on. The
    /// source is compared case-insensitively because the default APFS volume
    /// is, so exporting "IMG_0001" as a JPEG over "IMG_0001.jpg" would otherwise
    /// be offered as an overwrite.
    static func destinationURL(
        in folder: URL,
        baseName: String,
        format: ExportFormat,
        sourceURL: URL? = nil,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    ) -> URL? {
        guard let name = fileName(baseName: baseName, format: format) else { return nil }

        let pathExtension = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension

        for index in 1...999 {
            let candidateName = index == 1 ? name : "\(stem) \(index).\(pathExtension)"
            let candidate = folder.appending(path: candidateName)

            if let sourceURL, isSamePath(candidate, sourceURL) { continue }
            if exists(candidate) { continue }
            return candidate
        }

        // A folder with a thousand "name 2"s in it is not a real workflow, but
        // returning nil there would be a worse failure than a long name.
        return folder.appending(path: "\(stem) \(UUID().uuidString).\(pathExtension)")
    }

    // MARK: - Internals

    private static let maxLength = 200

    /// Whitespace and the dots a name may neither begin nor end with.
    private static let trimmedCharacters = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "."))

    /// Extensions that may be pasted along with a name. `.jpeg` and `.tif` are
    /// accepted even though Photon writes the shorter spellings.
    private static let knownExtensions: Set<String> = Set(
        ExportFormat.allCases.map(\.fileExtension) + ["jpeg", "tif"]
    )

    private static func isSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path.caseInsensitiveCompare(rhs.standardizedFileURL.path) == .orderedSame
    }
}
