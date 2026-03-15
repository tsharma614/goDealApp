import Foundation

/// Lightweight singleton to propagate deep link join codes from GoDealApp to MainMenuView.
@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    var pendingJoinCode: String? = nil
    private init() {}
}
