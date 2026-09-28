//
//  AppThemeTests.swift
//  PhotonTests
//

import SwiftUI
import Testing

@testable import Photon

@Suite("App theme")
@MainActor
struct AppThemeTests {
    @Test("Only the three appearance choices are offered")
    func supportedCases() {
        #expect(AppTheme.allCases == [.system, .light, .dark])
    }

    @Test("Every case round-trips through its stored raw value")
    func rawValueRoundTrip() {
        for theme in AppTheme.allCases {
            #expect(AppTheme(rawValue: theme.rawValue) == theme)
        }
    }

    @Test("System hands appearance to the OS and the others pin a scheme")
    func colorSchemes() {
        // `nil` is what keeps the OS in charge, including scheduled switching.
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
    }
}
