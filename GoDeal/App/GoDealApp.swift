import SwiftUI
import GameKit
import UIKit

@main
struct GoDealApp: App {
    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .onAppear { authenticateGameCenter() }
                .onOpenURL { url in
                    // godeal://join?code=XKCD42
                    guard url.scheme == "godeal",
                          url.host == "join",
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                          !code.isEmpty else { return }
                    DeepLinkRouter.shared.pendingJoinCode = code.uppercased()
                }
        }
    }

    private func authenticateGameCenter() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            if let error {
                GameLogger.shared.warn("[GC] Auth failed: \(error.localizedDescription)")
            }
            // Present the Game Center sign-in sheet when GC requests it
            if let vc = viewController {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.windows.first?.rootViewController else { return }
                root.present(vc, animated: true)
            }
            // Register for incoming invites once authenticated
            if GKLocalPlayer.local.isAuthenticated {
                Task { @MainActor in
                    InviteManager.shared.register()
                }
            }
        }
    }
}
