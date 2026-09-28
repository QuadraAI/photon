//
//  WelcomeNotice+Presentation.swift
//  Photon
//

import SwiftUI

extension WelcomeNotice {
    /// What the banner tells the user.
    ///
    /// Every notice is forgettable, because every one of them is about a
    /// remembered folder that did not open.
    var message: LocalizedStringKey {
        switch self {
        case .rememberedFolderUnavailable: "welcome.notice.rememberedUnavailable"
        }
    }
}
