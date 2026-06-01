# Exam Timing System for macOS

A professional macOS application for tracking time per question during exam practice with detailed performance analytics and PDF export capabilities.

## Architecture

The application follows a clean, modular architecture with clear separation of concerns:

### Core Components

#### 1. **Models** (`Models/ExamModels.swift`)
- `SessionState`: Enum defining all possible state changes (Start, Pause, Resume, Question Switch, Finish)
- `StateChangeLog`: Records each state change with timestamp and context
- `Question`: Individual question model with timing data and state history
- `ExamSession`: Complete exam session with all questions and metadata

#### 2. **Timing Engine** (`Engine/TimingEngine.swift`)
- `TimingEngine`: Observable class managing session lifecycle and timing logic
- Ensures single chronological log per question (no duplicate entries)
- Handles precise time tracking with 0.1s resolution
- Thread-safe with `@MainActor` annotation

#### 3. **Views**
- `SessionSetupView.swift`: Professional setup interface for new exam sessions
- `ActiveSessionView.swift`: Real-time tracking interface with sidebar navigation
- `PerformanceLogView.swift`: Detailed analytics with efficiency metrics
- `ContentView.swift`: Main app coordinator managing state transitions

#### 4. **Export** (`Export/PDFExporter.swift`)
- `PDFExporter`: Native PDF generation optimized for A4 paper
- Professional table layout using Core Graphics
- Includes performance metrics and complete state change log

## Features

### Timing & State Management
- ✅ Track total exam time and individual question time
- ✅ Chronological state change logging (prevents duplicates)
- ✅ Pause/Resume functionality with accurate time tracking
- ✅ Question-level time accumulation

### Navigation
- ✅ Custom keyboard shortcuts:
  - `⌘N` - New exam session
  - `⌘←` - Previous question
  - `⌘→` - Next question
  - `⌘P` - Pause/Resume
  - `⌘⇧F` - Finish exam
  - `⌘E` - Export PDF
- ✅ Click-to-jump question navigation (when not paused)

### Performance Analytics
- ✅ Time spent vs. mark allocation per question
- ✅ Efficiency bars comparing individual vs. average performance
- ✅ Time-per-mark calculations
- ✅ Color-coded efficiency indicators (Green < 80%, Orange 80-120%, Red > 120%)

### PDF Export
- ✅ Professional A4-optimized receipt
- ✅ Native table layout (no manual spacing)
- ✅ Complete session metadata
- ✅ Performance table with efficiency metrics
- ✅ Full state change log
- ✅ Generated timestamp

## Design Philosophy

### Strict Minimalist Corporate Aesthetic
The UI follows Apple's professional design language:

- **Typography**: San Francisco (system default) and SF Mono for monospaced data
- **Precision**: Uses precise numeric weights (`.regular`, `.medium`, `.semibold`)
- **Spacing**: Generous whitespace with clear visual hierarchy
- **Colors**: System colors with high contrast, minimal decoration
- **Layout**: Clean grid-based alignment, professional sectioning
- **No Playfulness**: Avoids rounded, friendly, or casual design elements

### Design Decisions
- Uppercase section headers with letter spacing for professional appearance
- Monospaced fonts for all time and numeric displays
- Subtle dividers and backgrounds using system colors
- Status indicators with clear color semantics (Green = Active, Orange = Paused)
- Corporate gray palette for secondary information

## Usage

### 1. Create New Session
1. Launch app (shows welcome screen)
2. Click "New Exam Session" or press `⌘N`
3. Configure:
   - Exam title
   - Number of questions
   - Mark allocation (uniform or individual)

### 2. Track Exam
1. Session starts automatically with Question 1
2. Navigate questions using:
   - Keyboard shortcuts (`⌘←`, `⌘→`)
   - Sidebar click (when active)
3. Pause/resume as needed (`⌘P`)
4. Finish when complete (`⌘⇧F`)

### 3. Review & Export
1. View performance log with detailed analytics
2. Review efficiency metrics and state changes
3. Export professional PDF receipt (`⌘E`)

## Technical Implementation

### State Management
- Single source of truth in `TimingEngine`
- SwiftUI's `@Published` for reactive updates
- State changes logged chronologically per question
- No duplicate log entries guaranteed by design

### Timing Accuracy
- 0.1 second update interval via `Timer`
- Separate tracking for question time and session time
- Time accumulation on question switches
- Pause-aware time calculations

### PDF Generation
- Pure Core Graphics implementation
- A4 page dimensions (595.28 × 841.89 points)
- Automatic page breaks for long sessions
- Professional typography with system fonts

### Keyboard Shortcuts
- Native SwiftUI `.keyboardShortcut()` modifiers
- Command group customization for menu bar integration
- Context-aware shortcut availability

## File Structure

```
Exam Timing System/
├── Exam_Timing_SystemApp.swift    # App entry point
├── ContentView.swift               # Main coordinator
├── Models/
│   └── ExamModels.swift           # Data structures
├── Engine/
│   └── TimingEngine.swift         # Core timing logic
├── Views/
│   ├── SessionSetupView.swift     # Session configuration
│   ├── ActiveSessionView.swift    # Live tracking interface
│   └── PerformanceLogView.swift   # Analytics display
└── Export/
    └── PDFExporter.swift          # A4 PDF generation
```

## Requirements

- macOS 14.0 or later
- Swift 5.9+
- SwiftUI
- AppKit (for PDF generation)

## Future Enhancements

Potential improvements for future versions:
- [ ] Session persistence (save/load sessions)
- [ ] Multiple session comparison
- [ ] Custom keyboard shortcut configuration
- [ ] CSV export option
- [ ] Dark mode optimization
- [ ] Session templates
- [ ] Time warnings/alerts

## License

Copyright © 2026 Patpatee Phangern. All rights reserved.

---

**Built with SwiftUI for macOS** • Professional Exam Practice Tool
