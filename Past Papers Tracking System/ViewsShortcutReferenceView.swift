//
//  ShortcutReferenceView.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI

struct ShortcutReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                    
                    Text("Quick reference guide")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Shortcuts List
            ScrollView {
                VStack(spacing: 24) {
                    shortcutSection(
                        title: "Session Management",
                        shortcuts: [
                            ("New Exam Session", "⌘N"),
                            ("Pause Session", "⌘P"),
                            ("Resume Session", "⌘P"),
                            ("Finish Exam", "⌘⇧F")
                        ]
                    )
                    
                    shortcutSection(
                        title: "Question Navigation",
                        shortcuts: [
                            ("Previous Question", "⌘←"),
                            ("Next Question", "⌘→"),
                            ("Jump to Question", "Click in sidebar")
                        ]
                    )
                    
                    shortcutSection(
                        title: "Export & Reports",
                        shortcuts: [
                            ("Export PDF Receipt", "⌘E")
                        ]
                    )
                    
                    shortcutSection(
                        title: "General",
                        shortcuts: [
                            ("Close Window", "⌘W"),
                            ("Quit Application", "⌘Q")
                        ]
                    )
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 400, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func shortcutSection(title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .textCase(.uppercase)
                .tracking(0.8)
            
            VStack(spacing: 8) {
                ForEach(shortcuts, id: \.0) { shortcut in
                    HStack {
                        Text(shortcut.0)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(shortcut.1)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ShortcutReferenceView()
}
