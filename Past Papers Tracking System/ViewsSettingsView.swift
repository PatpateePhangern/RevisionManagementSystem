//
//  SettingsView.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI

struct SettingsView: View { 
    @ObservedObject var settings = AppSettings.shared
    @State private var editingAction: ShortcutAction?
    @State private var tempShortcut: KeyboardShortcut?
    @State private var conflictMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                
                Text("Customize keyboard shortcuts")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Keyboard Shortcuts Section
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .padding(.top, 20)
                    
                    VStack(spacing: 1) {
                        ForEach(ShortcutAction.allCases, id: \.self) { action in
                            shortcutRow(for: action)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    
                    if let message = conflictMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(message)
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundColor(.orange)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            settings.resetToDefaults()
                            conflictMessage = nil
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(.top, 8)
                    
                    // Alarm Sounds Section
                    Text("Alarm Sounds")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .padding(.top, 24)
                    
                    VStack(spacing: 1) {
                        soundSelectionRow(
                            title: "5-Minute Warning",
                            description: "Plays when 5 minutes remain",
                            selectedSound: $settings.fiveMinuteWarningSound,
                            sounds: AlarmSound.alarmSounds,
                            onSoundChanged: { sound in
                                settings.updateFiveMinuteWarningSound(sound)
                            }
                        )

                        Divider()
                            .padding(.leading, 16)

                        soundSelectionRow(
                            title: "Time Up",
                            description: "Plays when time runs out",
                            selectedSound: $settings.timeUpSound,
                            sounds: AlarmSound.alarmSounds,
                            onSoundChanged: { sound in
                                settings.updateTimeUpSound(sound)
                            }
                        )
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // ── Over Target Notifications ──────────────────────────────
                    Text("Question Notifications")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .padding(.top, 24)

                    VStack(spacing: 1) {
                        soundSelectionRow(
                            title: "Over Target",
                            description: "Notification when a question exceeds its target time",
                            selectedSound: $settings.etsOverTargetSound,
                            sounds: AlarmSound.notificationSounds,
                            onSoundChanged: { settings.updateETSOverTargetSound($0) }
                        )
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 600)
    }
    
    @ViewBuilder
    private func shortcutRow(for action: ShortcutAction) -> some View {
        HStack(spacing: 16) {
            // Action name
            Text(action.rawValue)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Shortcut display/editor
            if editingAction == action {
                ShortcutRecorderView(
                    shortcut: Binding(
                        get: { tempShortcut ?? settings.getShortcut(for: action) },
                        set: { newValue in
                            tempShortcut = newValue
                            checkAndUpdateShortcut(for: action, with: newValue)
                        }
                    ),
                    onCancel: {
                        editingAction = nil
                        tempShortcut = nil
                        conflictMessage = nil
                    },
                    onConfirm: {
                        if let shortcut = tempShortcut {
                            settings.updateShortcut(for: action, to: shortcut)
                        }
                        editingAction = nil
                        tempShortcut = nil
                        conflictMessage = nil
                    }
                )
            } else {
                Button(action: {
                    editingAction = action
                    tempShortcut = settings.getShortcut(for: action)
                }) {
                    HStack(spacing: 4) {
                        Text(settings.getShortcut(for: action).displayString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func checkAndUpdateShortcut(for action: ShortcutAction, with shortcut: KeyboardShortcut) {
        if let conflict = settings.checkConflicts(for: action, with: shortcut) {
            conflictMessage = conflict.description
        } else {
            conflictMessage = nil
        }
    }
    
    @ViewBuilder
    private func soundSelectionRow(
        title: String,
        description: String,
        selectedSound: Binding<AlarmSound>,
        sounds: [AlarmSound] = AlarmSound.notificationSounds + AlarmSound.alarmSounds,
        onSoundChanged: @escaping (AlarmSound) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                // Title and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Sound picker
                Menu {
                    ForEach(sounds) { sound in
                        Button(action: {
                            selectedSound.wrappedValue = sound
                            onSoundChanged(sound)
                            sound.preview()
                        }) {
                            HStack {
                                Text(sound.displayName)
                                if selectedSound.wrappedValue == sound {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedSound.wrappedValue.displayName)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .focusEffectDisabled()
                .fixedSize()

                // Preview button
                Button(action: {
                    selectedSound.wrappedValue.preview()
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .focusEffectDisabled()
                .help("Preview sound")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Shortcut Recorder View

struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    @State private var isRecording = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Text(shortcut.displayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
                .focusable()
                .focused($isFocused)
                .onKeyPress { keyPress in
                    return handleKeyPress(keyPress)
                }
            
            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [])
            
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        var modifiers = SwiftUI.EventModifiers()
        
        if keyPress.modifiers.contains(.command) { modifiers.insert(.command) }
        if keyPress.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if keyPress.modifiers.contains(.option) { modifiers.insert(.option) }
        if keyPress.modifiers.contains(.control) { modifiers.insert(.control) }
        
        let key = String(keyPress.characters)
        
        // Don't allow single modifier keys
        if !modifiers.isEmpty && !key.isEmpty {
            shortcut = KeyboardShortcut(key: key, modifiers: modifiers)
        }
        
        return .handled
    }
}

#Preview {
    SettingsView()
}
