import Foundation
import Network

@MainActor
@Observable
final class Reachability {
    static let shared = Reachability()
    private(set) var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.online = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
}
