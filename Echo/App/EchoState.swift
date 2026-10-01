import Foundation
import UIKit
import SwiftData

enum EchoState {
    static var storeDegraded = false
}

enum EchoSecrets {
    static var searchKey: String {
        get { KeychainStore.get("search.api") }
        set { KeychainStore.set(newValue, account: "search.api") }
    }
}

enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.10"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    static var text: String { "\(short) · b\(build)" }
}

enum Device {
    @MainActor private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    @MainActor static var topInset: CGFloat {
        max(keyWindow?.safeAreaInsets.top ?? 0, 20)
    }

    @MainActor static var bottomInset: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }
}

enum AppLinks {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
