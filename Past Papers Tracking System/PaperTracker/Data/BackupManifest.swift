import Foundation

// MARK: - Top-level manifest

/// Root container for a full database export.
/// Encoded as indented ISO-8601 JSON; readable in any text editor.
struct MasterBackupManifest: Codable {
    /// Incremented when the schema changes so future importers can handle
    /// older files gracefully.
    var schemaVersion: Int = 1
    /// UTC timestamp when this export was generated.
    var exportedAt: Date
    var subjects: [SubjectBackup]
}

// MARK: - Subject

struct SubjectBackup: Codable {
    var name: String
    var papers: [PaperBackup]
}

// MARK: - Paper

struct PaperBackup: Codable {
    var rawSeriesName:    String?
    var normalizedSeries: String?
    var questionStructures: [QuestionStructureBackup]
    var attempts: [AttemptBackup]
}

// MARK: - Question structure

struct QuestionStructureBackup: Codable {
    var questionLabel: String?
    var maxMarks:      Int16
    var displayOrder:  Int16
}

// MARK: - Attempt

struct AttemptBackup: Codable {
    var id:               UUID
    var attemptNumber:    Int16
    var barcodeValue:     String?
    var paperType:        String?
    var totalScore:       Double
    var rawGrade:         String?
    var durationInSeconds: Int64
    var printTimestamp:   Date?
    var completedTimestamp: Date?
    var reviewQuestions:  String?
    var additionalNotes:  String?
    var scannedFilePath:  String?
    var eventLogs: [ETSEventLogBackup]
}

// MARK: - ETS event log

struct ETSEventLogBackup: Codable {
    var id:             UUID
    var sequenceIndex:  Int16
    var eventType:      String?
    var label:          String?
    var durationSeconds: Int64
    var marksEarned:    Double
}
