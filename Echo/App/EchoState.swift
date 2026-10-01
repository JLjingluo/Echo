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

enum AppLinks {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
