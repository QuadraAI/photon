//
//  StubPhotoLibrary.swift
//  PhotonTests
//

import Foundation
import Synchronization

@testable import Photon

/// Scriptable ``PhotoLibraryLoading`` that never touches the file system.
final class StubPhotoLibrary: PhotoLibraryLoading, Sendable {
    private let storage: Mutex<[PhotoItem]>
    private let failure: Mutex<PhotoLibraryError?>
    private let scans = Mutex(0)

    init(photos: [PhotoItem] = [], failure: PhotoLibraryError? = nil) {
        storage = Mutex(photos)
        self.failure = Mutex(failure)
    }

    /// How many times the folder has been scanned, so tests can prove a repeat
    /// `load` for the same folder does not hit the disk again.
    var scanCount: Int {
        scans.withLock { $0 }
    }

    func photos(in folder: URL) async throws(PhotoLibraryError) -> [PhotoItem] {
        scans.withLock { $0 += 1 }
        if let failure = failure.withLock({ $0 }) { throw failure }
        return storage.withLock { $0 }
    }
}
