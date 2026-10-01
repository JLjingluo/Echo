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

enum AppLinks {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
