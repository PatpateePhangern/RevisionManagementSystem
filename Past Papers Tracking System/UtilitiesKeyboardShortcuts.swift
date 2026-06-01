//
//  KeyboardShortcuts.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI

/// Centralized keyboard shortcut configuration
/// Allows for easy customization of all app shortcuts
struct AppKeyboardShortcuts {
    
    // MARK: - Session Management
    
    static let newSession = KeyEquivalent("n")
    static let newSessionModifiers = EventModifiers.command
    
    static let pauseResume = KeyEquivalent("p")
    static let pauseResumeModifiers = EventModifiers.command
    
    static let finishExam = KeyEquivalent("f")
    static let finishExamModifiers = EventModifiers([.command, .shift])
    
    // MARK: - Navigation
    
    static let previousQuestion = KeyEquivalent.leftArrow
    static let previousQuestionModifiers = EventModifiers.command
    
    static let nextQuestion = KeyEquivalent.rightArrow
    static let nextQuestionModifiers = EventModifiers.command
    
    // MARK: - Export & Actions
    
    static let exportPDF = KeyEquivalent("e")
    static let exportPDFModifiers = EventModifiers.command
    
    // MARK: - Helper Text
    
    static func shortcutText(_ key: KeyEquivalent, modifiers: EventModifiers) -> String {
        var text = ""
        
        if modifiers.contains(.command) { text += "⌘" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.control) { text += "⌃" }
        
        switch key {
        case .leftArrow: text += "←"
        case .rightArrow: text += "→"
        case .upArrow: text += "↑"
        case .downArrow: text += "↓"
        default: text += "\(key)".uppercased()
        }
        
        return text
    }
    
    // MARK: - Formatted Shortcut Strings
    
    static var newSessionText: String {
        shortcutText(newSession, modifiers: newSessionModifiers)
    }
    
    static var pauseResumeText: String {
        shortcutText(pauseResume, modifiers: pauseResumeModifiers)
    }
    
    static var finishExamText: String {
        shortcutText(finishExam, modifiers: finishExamModifiers)
    }
    
    static var previousQuestionText: String {
        shortcutText(previousQuestion, modifiers: previousQuestionModifiers)
    }
    
    static var nextQuestionText: String {
        shortcutText(nextQuestion, modifiers: nextQuestionModifiers)
    }
    
    static var exportPDFText: String {
        shortcutText(exportPDF, modifiers: exportPDFModifiers)
    }
}

// MARK: - View Extension for Consistent Shortcut Application

extension View {
    func appShortcut(_ type: AppShortcutType) -> some View {
        switch type {
        case .newSession:
            return AnyView(self.keyboardShortcut(AppKeyboardShortcuts.newSession, modifiers: AppKeyboardShortcuts.newSessionModifiers))
        case .pauseResume:
            return AnyView(self.keyboardShortcut(AppKeyboardShortcuts.pauseResume, modifiers: AppKeyboardShortcuts.pauseResumeModifiers))
        case .finishExam:
            return AnyView(self.keyboardShortcut(AppKeyboardShortcuts.finishExam, modifiers: AppKeyboardShortcuts.finishExamModifiers))
        case .previousQuestion:
            return AnyView(self.keyboardShortcut(AppKeyboardShortcuts.previousQuestion, modifiers: AppKeyboardShortcuts.previousQuestionModifiers))
        case .nextQuestion:
            return AnyView(self.keyboardShortcut(AppKeyboardShortcuts.nextQuestion, modifiers: AppKeyboardShortcuts.nextQuestionModifiers))
        case .exportPDF:
            return AnyView(self.keyboardShortcut(AppKeyboardShortcuts.exportPDF, modifiers: AppKeyboardShortcuts.exportPDFModifiers))
        }
    }
}

enum AppShortcutType {
    case newSession
    case pauseResume
    case finishExam
    case previousQuestion
    case nextQuestion
    case exportPDF
}
