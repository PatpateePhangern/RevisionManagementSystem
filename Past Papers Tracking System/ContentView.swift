//
//  ContentView.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI

enum AppState {
    case welcome
    case activeSession
    case performanceLog
}

struct ContentView: View {
    @StateObject private var timingEngine = TimingEngine()
    @State private var appState: AppState = .welcome
    @State private var showSessionSetup = false
    @State private var showSettings = false
    @State private var completedSession: ExamSession?
    
    var body: some View {
        Group {
            switch appState {
            case .welcome:
                welcomeView
            case .activeSession:
                if timingEngine.session != nil {
                    ActiveSessionView(engine: timingEngine) {
                        handleSessionFinish()
                    }
                }
            case .performanceLog:
                if let session = completedSession {
                    PerformanceLogView(
                        session: session,
                        onExportPDF: {
                            exportPDF(session: session)
                        },
                        onClose: {
                            resetToWelcome()
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showSessionSetup) {
            SessionSetupView(isPresented: $showSessionSetup) { title, count, marks, times in
                createAndStartSession(title: title, count: count, marks: marks, times: times)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showSettings = true
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
    
    // MARK: - Welcome View
    
    private var welcomeView: some View {
        let settings = AppSettings.shared
        
        return VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // App Icon
                Image(systemName: "timer.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                
                // Title
                VStack(spacing: 8) {
                    Text("Revision Management System")
                        .font(.system(size: 32, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                    
                    Text("Professional question-level performance tracking")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
                
                // Primary Action
                Button(action: {
                    showSessionSetup = true
                }) {
                    Label("New Exam Session", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(
                    KeyEquivalent(settings.getShortcut(for: .newSession).key.first ?? "n"),
                    modifiers: settings.getShortcut(for: .newSession).modifiers
                )
                .padding(.top, 16)
                
                // Features
                VStack(alignment: .leading, spacing: 12) {
                    featureRow(icon: "timer.circle.fill", text: "Countdown timers for each question")
                    featureRow(icon: "keyboard", text: "Navigate with custom keyboard shortcuts")
                    featureRow(icon: "chart.bar.fill", text: "Generate detailed performance analytics")
                    featureRow(icon: "doc.text.fill", text: "Export professional A4 PDF reports")
                }
                .padding(.top, 32)
            }
            
            Spacer()
            
            // Footer
            Text("Press \(settings.getShortcut(for: .newSession).displayString) to create a new session")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundColor(.secondary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func createAndStartSession(title: String, count: Int, marks: [Int], times: [TimeInterval]) {
        timingEngine.createSession(title: title, questionCount: count, markAllocations: marks, timeAllocations: times)
        timingEngine.startSession()
        appState = .activeSession
    }
    
    private func handleSessionFinish() {
        completedSession = timingEngine.session
        appState = .performanceLog
    }
    
    private func exportPDF(session: ExamSession) {
        if let pdfDocument = PDFExporter.generateSessionReceipt(for: session) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let fileName = "\(session.title) - \(dateString).pdf"
            
            PDFExporter.saveReceipt(pdfDocument, defaultName: fileName)
        }
    }
    
    private func resetToWelcome() {
        completedSession = nil
        appState = .welcome
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}
