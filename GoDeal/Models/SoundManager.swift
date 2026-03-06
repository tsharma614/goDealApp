import AudioToolbox
import UIKit

// MARK: - Sound Manager
// Plays system sounds and haptics for key game events.
// Uses AudioToolbox system sounds — no bundled audio files needed.

@MainActor
enum SoundManager {

    // MARK: - System Sound IDs
    // These are built-in iOS system sounds that work without any audio files.

    /// Card shuffle / draw — keyboard click
    private static let drawSoundID: SystemSoundID = 1104

    /// Cha-ching for banking — payment sent
    private static let bankSoundID: SystemSoundID = 1394

    /// Slam / steal — lock sound
    private static let stealSoundID: SystemSoundID = 1305

    /// No Deal block — swoosh
    private static let blockSoundID: SystemSoundID = 1306

    /// Collect rent — register sound
    private static let rentSoundID: SystemSoundID = 1057

    /// Win — fanfare-like
    private static let winSoundID: SystemSoundID = 1025

    /// Lose — low tone
    private static let loseSoundID: SystemSoundID = 1073

    /// Card tap / select
    private static let selectSoundID: SystemSoundID = 1104

    /// Place property — soft tick
    private static let placeSoundID: SystemSoundID = 1103

    // MARK: - Public API

    static func cardDraw() {
        AudioServicesPlaySystemSound(drawSoundID)
        Haptics.impact(.light)
    }

    static func bankCard() {
        AudioServicesPlaySystemSound(bankSoundID)
        Haptics.impact(.medium)
    }

    static func placeProperty() {
        AudioServicesPlaySystemSound(placeSoundID)
        Haptics.impact(.light)
    }

    static func steal() {
        AudioServicesPlaySystemSound(stealSoundID)
        Haptics.notification(.error)
    }

    static func noDealBlock() {
        AudioServicesPlaySystemSound(blockSoundID)
        Haptics.notification(.success)
    }

    static func collectRent() {
        AudioServicesPlaySystemSound(rentSoundID)
        Haptics.impact(.medium)
    }

    static func win() {
        AudioServicesPlaySystemSound(winSoundID)
        Haptics.notification(.success)
    }

    static func lose() {
        AudioServicesPlaySystemSound(loseSoundID)
        Haptics.notification(.error)
    }

    static func cardSelect() {
        Haptics.selection()
    }

    static func endTurn() {
        Haptics.impact(.light)
    }

    static func paymentDue() {
        Haptics.notification(.warning)
    }
}
