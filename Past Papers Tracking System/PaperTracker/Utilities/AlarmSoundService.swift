import Foundation
import AVFoundation
import AppKit

/// Service for playing alarm sounds from macOS Clock app.
/// Available alarms: Alarm, Beacon, Bells, Chime, Ping, Radar, Ringing, Siren
final class AlarmSoundService {

    static let shared = AlarmSoundService()

    private var audioPlayer: AVAudioPlayer?
    private let dispatchQueue = DispatchQueue(label: "com.examtimingsystem.alarmSound")

    private init() {}

    /// Plays one of the standard macOS Clock app alarm sounds.
    /// - Parameter alarm: Name of the alarm tone (e.g., "Alarm", "Beacon", "Bells", "Chime", "Ping", "Radar", "Ringing", "Siren")
    func playAlarm(_ alarm: String = "Alarm") {
        dispatchQueue.async { [weak self] in
            self?.playAlarmInternal(alarm)
        }
    }

    private func playAlarmInternal(_ alarm: String) {
        // Try to load from /System/Library/Sounds/
        let soundPath = "/System/Library/Sounds/\(alarm).aiff"
        let url = URL(filePath: soundPath)

        guard FileManager.default.fileExists(atPath: soundPath) else {
            print("Alarm sound not found: \(soundPath)")
            // Fallback to system beep
            NSSound.beep()
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0  // Play once
            player.volume = 1.0

            DispatchQueue.main.async { [weak self] in
                // Stop any currently playing sound
                self?.audioPlayer?.stop()
                self?.audioPlayer = player
                player.play()
            }
        } catch {
            print("Error playing alarm: \(error)")
            NSSound.beep()
        }
    }

    /// List of available Clock app alarm tones.
    static var availableAlarms: [String] {
        ["Alarm", "Beacon", "Bells", "Chime", "Ping", "Radar", "Ringing", "Siren"]
    }
}
