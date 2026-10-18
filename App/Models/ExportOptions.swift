//
//  ExportOptions.swift
//  Photon
//

import Foundation

/// How an export is encoded, apart from where it is written.
nonisolated struct ExportOptions: Equatable, Sendable {
    /// The quality range the encoder understands.
    static let qualityRange: ClosedRange<Double> = 0...1

    /// What a slider the user has never touched asks for.
    static let defaultQuality = 0.85

    var format: ExportFormat

    /// Compression quality, meaningless for the lossless formats.
    var quality: Double

    /// Whether the GPS dictionary is left out.
    var removeLocation: Bool

    init(
        format: ExportFormat = .jpeg,
        quality: Double = Self.defaultQuality,
        removeLocation: Bool = false
    ) {
        self.format = format
        self.quality = quality.clamped(to: Self.qualityRange)
        self.removeLocation = removeLocation
    }
}
