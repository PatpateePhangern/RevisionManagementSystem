//
//  AppSettings.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI
import Combine
import AppKit
import AVFoundation

// MARK: - Alarm Sound Types

/// A playable macOS sound identified by its filename stem (e.g. "Tink", "Radar").
/// Encoded as a plain string for UserDefaults persistence and backward compatibility
/// with the previous enum-based storage.
struct AlarmSound: Identifiable, Hashable, Equatable, Codable {

    var name: String
    var id: String { name }
    var displayName: String { name }

    // MARK: - Codable (plain-string encoding for UserDefaults back-compat)

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        // Accepts both plain string ("Tink") and keyed struct ({"name":"Tink"})
        if let single = try? decoder.singleValueContainer(),
           let s = try? single.decode(String.self) {
            name = s
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(name)
    }

    private enum CodingKeys: String, CodingKey { case name }

    // MARK: - Sound URL

    private static let systemDir    = "/System/Library/Sounds/"
    private static let ringtoneDir  = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/"

    var soundURL: URL? {
        let exts = ["aiff", "m4r", "caf", "wav", "m4a", "aif"]
        for dir in [Self.systemDir, Self.ringtoneDir] {
            for ext in exts {
                let url = URL(filePath: "\(dir)\(name).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    // Static storage for the currently playing sound to prevent overlaps
    private static var currentlyPlayingPlayer: AVAudioPlayer?
    private static let audioQueue = DispatchQueue(label: "com.rms.audioPlayback")

    func preview() {
        guard let url = soundURL else { NSSound.beep(); return }

        Self.audioQueue.sync {
            // Stop any currently playing sound
            Self.currentlyPlayingPlayer?.stop()

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 1.0
                player.numberOfLoops = 0
                player.play()
                Self.currentlyPlayingPlayer = player
            } catch {
                NSSound.beep()
            }
        }
    }

    func play() { preview() }

    // MARK: - Curated lists

    /// All 14 short macOS system notification sounds.
    static var notificationSounds: [AlarmSound] {
        ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
         "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
            .map { AlarmSound(name: $0) }
            .filter { $0.soundURL != nil }
    }

    /// All ringtone/alarm tones from the ToneLibrary, sorted alphabetically.
    /// Falls back to notificationSounds if the framework is unavailable.
    static var alarmSounds: [AlarmSound] {
        let fm  = FileManager.default
        let dir = URL(filePath: ringtoneDir)
        let tones = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { ["m4r", "caf", "aiff"].contains($0.pathExtension.lowercased()) }
            .map    { AlarmSound(name: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            ?? []
        return tones.isEmpty ? notificationSounds : tones
    }

    // MARK: - Convenience defaults
    static let tink    = AlarmSound(name: "Tink")
    static let basso   = AlarmSound(name: "Basso")
    static let radar   = AlarmSound(name: "Radar")
    static let alarm   = AlarmSound(name: "Alarm")
}

// MARK: - Shortcut Action Types

enum ShortcutAction: String, CaseIterable, Codable {
    case newSession = "New Session"
    case pauseResume = "Pause/Resume"
    case nextQuestion = "Next Question"
    case previousQuestion = "Previous Question"
    case finishExam = "Finish Exam"
    case jumpToQuestion = "Jump to Question"
    
    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .newSession:
            return KeyboardShortcut(key: "n", modifiers: .command)
        case .pauseResume:
            return KeyboardShortcut(key: "p", modifiers: .command)
        case .nextQuestion:
            return KeyboardShortcut(key: .rightArrow, modifiers: .command)
        case .previousQuestion:
            return KeyboardShortcut(key: .leftArrow, modifiers: .command)
        case .finishExam:
            return KeyboardShortcut(key: "f", modifiers: [.command, .shift])
        case .jumpToQuestion:
            return KeyboardShortcut(key: "j", modifiers: .command)
        }
    }
}

// MARK: - Keyboard Shortcut Model

struct KeyboardShortcut: Codable {
    var key: String
    var modifiers: SwiftUI.EventModifiers
    
    init(key: String, modifiers: SwiftUI.EventModifiers) {
        self.key = key
        self.modifiers = modifiers
    }
    
    init(key: KeyEquivalent, modifiers: SwiftUI.EventModifiers) {
        self.key = String(key.character)
        self.modifiers = modifiers
    }
    
    var displayString: String {
        var result = ""
        
        if modifiers.contains(.command) { result += "⌘" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.control) { result += "⌃" }
        
        result += key.uppercased()
        return result
    }
    
    func conflicts(with other: KeyboardShortcut) -> Bool {
        return key.lowercased() == other.key.lowercased() && modifiers == other.modifiers
    }
    
    // MARK: - Codable conformance
    
    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        let rawValue = try container.decode(Int.self, forKey: .modifiers)
        modifiers = SwiftUI.EventModifiers(rawValue: rawValue)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}

// MARK: - Equatable conformance
extension KeyboardShortcut: Equatable {
    static func == (lhs: KeyboardShortcut, rhs: KeyboardShortcut) -> Bool {
        return lhs.key.lowercased() == rhs.key.lowercased() && 
               lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }
}

// MARK: - Hashable conformance
extension KeyboardShortcut: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(key.lowercased())
        hasher.combine(modifiers.rawValue)
    }
}

// MARK: - App Settings

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // Stored shortcuts
    @Published var shortcuts: [ShortcutAction: KeyboardShortcut] = [:]
    
    // Sound preferences (Exam timer)
    @Published var fiveMinuteWarningSound: AlarmSound = .tink
    @Published var timeUpSound: AlarmSound = .basso
    // Question notifications
    @Published var etsOverTargetSound: AlarmSound = .tink
    
    // Known system shortcuts for conflict detection
    private let systemShortcuts: [KeyboardShortcut] = [
        KeyboardShortcut(key: "q", modifiers: .command),       // Quit
        KeyboardShortcut(key: "w", modifiers: .command),       // Close Window
        KeyboardShortcut(key: "m", modifiers: .command),       // Minimize
        KeyboardShortcut(key: "h", modifiers: .command),       // Hide
        KeyboardShortcut(key: "tab", modifiers: .command),     // Switch Apps
        KeyboardShortcut(key: ",", modifiers: .command),       // Preferences
        KeyboardShortcut(key: "c", modifiers: .command),       // Copy
        KeyboardShortcut(key: "v", modifiers: .command),       // Paste
        KeyboardShortcut(key: "x", modifiers: .command),       // Cut
        KeyboardShortcut(key: "z", modifiers: .command),       // Undo
        KeyboardShortcut(key: "z", modifiers: [.command, .shift]), // Redo
        KeyboardShortcut(key: "a", modifiers: .command),       // Select All
        KeyboardShortcut(key: "s", modifiers: .command),       // Save
    ]
    
    private let defaults = UserDefaults.standard
    private let shortcutsKey = "app.shortcuts"
    private let fiveMinuteWarningSoundKey = "app.fiveMinuteWarningSound"
    private let timeUpSoundKey = "app.timeUpSound"
    private let etsOverTargetSoundKey = "app.etsOverTargetSound"
    
    private init() {
        loadShortcuts()
        loadSoundPreferences()
    }
    
    // MARK: - Persistence
    
    func loadShortcuts() {
        if let data = defaults.data(forKey: shortcutsKey),
           let decoded = try? JSONDecoder().decode([String: KeyboardShortcut].self, from: data) {
            shortcuts = decoded.reduce(into: [:]) { result, pair in
                if let action = ShortcutAction(rawValue: pair.key) {
                    result[action] = pair.value
                }
            }
        } else {
            // Load defaults
            resetToDefaults()
        }
    }
    
    func saveShortcuts() {
        let encoded = shortcuts.reduce(into: [String: KeyboardShortcut]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
        
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: shortcutsKey)
        }
    }
    
    func resetToDefaults() {
        shortcuts = ShortcutAction.allCases.reduce(into: [:]) { result, action in
            result[action] = action.defaultShortcut
        }
        saveShortcuts()
    }
    
    // MARK: - Sound Preferences
    
    func loadSoundPreferences() {
        if let warningData = defaults.data(forKey: fiveMinuteWarningSoundKey),
           let warningSound = try? JSONDecoder().decode(AlarmSound.self, from: warningData) {
            fiveMinuteWarningSound = warningSound
        }

        if let timeUpData = defaults.data(forKey: timeUpSoundKey),
           let timeUpSoundValue = try? JSONDecoder().decode(AlarmSound.self, from: timeUpData) {
            timeUpSound = timeUpSoundValue
        }

        if let d = defaults.data(forKey: etsOverTargetSoundKey),
           let v = try? JSONDecoder().decode(AlarmSound.self, from: d) {
            etsOverTargetSound = v
        }
    }
    
    func saveSoundPreferences() {
        if let warningData = try? JSONEncoder().encode(fiveMinuteWarningSound) {
            defaults.set(warningData, forKey: fiveMinuteWarningSoundKey)
        }

        if let timeUpData = try? JSONEncoder().encode(timeUpSound) {
            defaults.set(timeUpData, forKey: timeUpSoundKey)
        }

        if let d = try? JSONEncoder().encode(etsOverTargetSound) {
            defaults.set(d, forKey: etsOverTargetSoundKey)
        }
    }
    
    func updateFiveMinuteWarningSound(_ sound: AlarmSound) {
        fiveMinuteWarningSound = sound
        saveSoundPreferences()
    }
    
    func updateTimeUpSound(_ sound: AlarmSound) {
        timeUpSound = sound
        saveSoundPreferences()
    }

    func updateETSOverTargetSound(_ sound: AlarmSound) {
        etsOverTargetSound = sound
        saveSoundPreferences()
    }
    
    // MARK: - Conflict Detection
    
    func checkConflicts(for action: ShortcutAction, with shortcut: KeyboardShortcut) -> ShortcutConflict? {
        // Check system shortcuts
        if systemShortcuts.contains(where: { $0.conflicts(with: shortcut) }) {
            return .system
        }
        
        // Check other app shortcuts
        for (otherAction, otherShortcut) in shortcuts {
            if otherAction != action && otherShortcut.conflicts(with: shortcut) {
                return .app(otherAction)
            }
        }
        
        return nil
    }
    
    func updateShortcut(for action: ShortcutAction, to shortcut: KeyboardShortcut) {
        shortcuts[action] = shortcut
        saveShortcuts()
    }
    
    func getShortcut(for action: ShortcutAction) -> KeyboardShortcut {
        return shortcuts[action] ?? action.defaultShortcut
    }
}

// MARK: - Conflict Types

enum ShortcutConflict {
    case system
    case app(ShortcutAction)
    
    var description: String {
        switch self {
        case .system:
            return "This shortcut conflicts with a system shortcut"
        case .app(let action):
            return "This shortcut conflicts with '\(action.rawValue)'"
        }
    }
}

