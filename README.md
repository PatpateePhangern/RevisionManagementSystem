# RMS — Revision Management System

RMS (Revision Management System) is a macOS app for managing A-Level past paper practice — print tracking, exam timing, batch processing, and performance analysis.

## Requirements

- macOS 14 (Sonnet) or later
- Xcode 15 or later (to build from source)

## Features

- **New Paper** — log a new exam attempt; auto-assigns barcode and attempt number
- **Complete Logs** — full record of all attempts with PDF check-in via drag-and-drop
- **Batch Logs** — group multiple papers into a batch; print a Batch Examination Records Index List; scan completed papers back in
- **Papers Mapping** — attach Question Paper and Mark Scheme PDFs; map page ranges to each question
- **ETS (Exam Timing System)** — timed exam sessions with per-question time allocation and over-target alerts
- **DQA** — Difficult Questions Archive for extracting and re-attempting specific questions
- **Print** — double-sided print queue with LAN dispatch to a Windows PC
- **Report** — formatted PDF performance report across subjects

## Building

1. Clone this repository.
2. Open `Exam Timing System/Past Papers Tracking System.xcodeproj` in Xcode.
3. Select the **Past Papers Tracking System** scheme and your Mac as the destination.
4. Press **⌘R** to build and run.

> No external dependencies or CocoaPods are required.

## Windows Print Server

To send print jobs to a Windows PC on your local network:

1. **Download `rms_print_server.exe`** from the [latest GitHub Release](../../releases/latest).
2. Double-click `rms_print_server.exe` on the Windows PC — no installation needed.
3. Open a browser on that PC and go to `http://localhost:8999` to confirm it is running.
4. Find the Windows PC's LAN IP address by running `ipconfig` in a Command Prompt (look for **IPv4 Address**).
5. In RMS on your Mac, go to **Settings → Windows Print Server** and enter `<IP>:8999`.

### Prerequisites on the Windows PC

| Software | Purpose | Required |
|---|---|---|
| [SumatraPDF](https://www.sumatrapdfreader.org/) | Silent / Express printing | Strongly recommended |
| [Brave Browser](https://brave.com/) | Manual print with print dialog | Optional |
| pywin32 | Printer enumeration (built into the .exe) | Bundled |

> **Express Print** uses SumatraPDF for silent spooling.  
> **Manual + VNC** opens Screen Sharing so you can select a printer interactively.

### Building the exe yourself

The exe is automatically built by GitHub Actions whenever `rms_print_server.py` changes.  
To build it manually on a Windows machine:

```bat
pip install pywin32 pyinstaller
pyinstaller --onefile --noconsole --name rms_print_server rms_print_server.py
```

The output will be at `dist\rms_print_server.exe`.

## Project structure

```
Exam Timing System/
├── .github/workflows/
│   └── build-print-server.yml   # Auto-builds rms_print_server.exe on Windows
├── Exam Timing System/
│   └── Past Papers Tracking System/
│       ├── PaperTracker/         # Core app source
│       ├── rms_print_server.py   # Windows print server (source)
│       └── requirements.txt      # Python dependencies
└── Past Papers Tracking System.xcodeproj
```

## License

This project is provided for personal and educational use.
