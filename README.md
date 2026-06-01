# RMS — Revision Management System

**RMS** is a macOS application built for A-Level students who want a structured, data-driven approach to past paper practice. It handles everything from printing and tracking papers to timing exam sessions, archiving difficult questions, and generating performance reports — all in one place.

---

## Why RMS?

Most students do past papers without tracking anything. They forget which papers they've done, how long they took, which questions they struggled with, and whether their scores are improving. RMS fixes that by giving every paper a barcode, every session a record, and every attempt a place in a searchable log.

---

## Features

### 📄 New Paper
Print a new past paper attempt. Enter the subject, exam series, paper component, and variant — RMS auto-assigns a barcode ID and attempt number, then prints an **Examination Records Index** sheet to attach to the front of your paper.

### 📋 Complete Logs
The full history of every paper you've printed. Drop a scanned PDF onto the log to check it in — RMS reads the barcode automatically using Vision, classifies the paper type, and files it. Each entry shows the subject, series, attempt number, score, grade, and status.

### 🗂️ Batch Logs
Group multiple papers together into a batch. When creating a batch, RMS prints a **Batch Examination Records Index List** (A4) covering all the papers in the group. When you scan each completed paper back in, its status updates automatically within the batch.

### 🗺️ Papers Mapping
Attach the original Question Paper and Mark Scheme PDF files to each exam series. Map page ranges to individual questions so you can jump directly to any question during review. Works with drag-and-drop.

### ⏱️ Exam Timing System (ETS)
Conduct a fully timed exam session. ETS allocates time proportionally across questions based on mark weighting, plays audible alerts when you are over target on a question, and plays an alarm when the exam ends. A session receipt is generated at the end showing time spent per question vs target.

### 🔍 DQA — Difficult Questions Archive
Extract specific questions from a past paper into a separate PDF for targeted re-practice. Each DQA entry tracks the source paper, question number, and attempt history so you can see whether you have improved over time.

### 🖨️ Print
A double-sided print queue for dispatching papers to a printer. Supports local macOS printing or sending jobs across the network to a Windows PC running `rms_print_server.exe`.

### 📊 Report
Generate a formatted PDF performance report for selected subjects. Shows attempt counts, score trends, grade distributions, and completion rates across all logged papers.

### 🔔 Alarm Sounds
Configurable sounds for each alert type:
- **5-Minute Warning** — plays when 5 minutes remain on the exam timer
- **Time Up** — plays when exam time runs out
- **Over Target** — plays when you exceed the target time on a question

---

## Download & Install

### Easiest way — download the app directly

1. Go to the [Releases page](../../releases/latest)
2. Download **RMS-macOS.zip**
3. Unzip it — you'll get **RMS.app**
4. Drag **RMS.app** into your **Applications** folder

> **First launch:** macOS will block the app because it is not signed by Apple.  
> To open it: **right-click RMS.app → Open → Open** (you only need to do this once).  
> After that it opens normally like any other app.

---

## Build from Source

### Requirements
- macOS 14 or later
- Xcode 15 or later

### Steps
1. Clone this repository
2. Open `Past Papers Tracking System.xcodeproj` in Xcode
3. Select the **Past Papers Tracking System** scheme and your Mac as the destination
4. Press **⌘R** to build and run

> No external dependencies or package managers are required.

---

## Windows Print Server

To send print jobs wirelessly to a Windows PC on your local network:

### Setup
1. **Download `rms_print_server.exe`** from the [Releases page](../../releases/latest)
2. **Double-click** to run it on your Windows PC — no installation needed
3. Open a browser on that PC and go to `http://localhost:8999` to confirm it is running
4. Run `ipconfig` in Command Prompt and note the **IPv4 Address**
5. In RMS → **Settings → Windows Print Server**, enter `<IP>:8999`

### Prerequisites on the Windows PC

| Software | Purpose |
|---|---|
| [SumatraPDF](https://www.sumatrapdfreader.org/) | Required for Express (silent) printing |
| [Brave Browser](https://brave.com/) | Used for Manual print with print dialog |

> **Express Print** silently spools the job to the selected printer using SumatraPDF.  
> **Manual + VNC** opens Screen Sharing on your Mac so you can select a printer interactively.

### Building the exe yourself
The exe is automatically built by GitHub Actions on every push. To build manually on Windows:
```bat
pip install pywin32 pyinstaller
pyinstaller --onefile --noconsole --name rms_print_server rms_print_server.py
```

---

## How Barcodes Work

Every paper printed by RMS gets a unique barcode in the format:

```
{SHORTCODE}-{SERIES}-ATT{N}
```

For example: `P3MATH-2025-05-ATT2` means P3 Mathematics, May/June 2025, second attempt.

When you scan a completed paper back in, RMS reads the barcode using Apple's Vision framework, matches it to the logged attempt, and marks it complete. No manual entry needed.

---

## Project Structure

```
Past Papers Tracking System/
├── PaperTracker/
│   ├── Data/           — Core Data models (AttemptMO, PaperMO, BatchMO, …)
│   ├── Documents/      — PDF generators (index sheets, batch lists, receipts)
│   ├── Engines/        — Timer engine, series normalisation, barcode parsing
│   ├── Scanning/       — Vision barcode scanner and file organisation pipeline
│   ├── Services/       — Auto-backup, LAN print routing
│   └── Views/          — All SwiftUI views
├── rms_print_server.py — Windows LAN print receiver (source)
└── requirements.txt    — Python dependencies
```

---

## License

This project is provided for personal and educational use.
