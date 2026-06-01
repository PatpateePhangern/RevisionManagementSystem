# Exam Timing System - User Guide

## Welcome

The Exam Timing System is a professional macOS application designed to help you track and analyze your exam practice sessions with precision. This guide will walk you through every feature of the application.

---

## Getting Started

### Launching the Application

When you first launch the application, you'll see the **Welcome Screen** featuring:

- Application title and description
- "New Exam Session" button
- Feature overview
- Keyboard shortcut hint (⌘N)

### Creating Your First Session

1. **Start a New Session**
   - Click "New Exam Session" or press `⌘N`
   - The Session Setup window will appear

2. **Configure Your Exam**
   - **Exam Title**: Enter a descriptive name (e.g., "Mathematics Final Exam")
   - **Number of Questions**: Set how many questions you'll be practicing (1-100)
   - **Mark Allocation**: Choose between:
     - **Uniform Marks**: Same marks for all questions (default: 10)
     - **Individual Marks**: Set marks per question manually

3. **Review Summary**
   - Check the summary showing total questions and total marks
   - Click "Create Session" when ready

4. **Session Starts Automatically**
   - The timer begins immediately on Question 1
   - You're now in the Active Session view

---

## Active Session Interface

### Understanding the Layout

The Active Session interface is divided into four main areas:

#### 1. Top Bar (Status Area)
- **Left**: Exam title and session status
- **Right**: Total time elapsed for entire exam

#### 2. Question Sidebar (Left)
- List of all questions with:
  - Question number (Q1, Q2, etc.)
  - Current time spent on each question
  - Mark allocation
  - Active indicator (green dot = active, orange = paused)
- Click any question to jump to it (only when session is active)

#### 3. Main Timer Display (Center)
- Large, easy-to-read timer showing current question time
- Question number
- Mark allocation
- Status indicator (Active/Paused)
- Navigation hints at the bottom

#### 4. Control Bar (Bottom)
- **Previous**: Go to previous question (`⌘←`)
- **Next**: Go to next question (`⌘→`)
- **Pause/Resume**: Pause or resume timing (`⌘P`)
- **Finish Exam**: Complete the session (`⌘⇧F`)

---

## Working Through Your Exam

### Basic Workflow

1. **Start with Question 1**
   - Timer is already running
   - Focus on your work

2. **Navigate Between Questions**
   - Press `⌘→` to move to the next question
   - Press `⌘←` to go back to a previous question
   - Or click any question in the sidebar

3. **Taking Breaks**
   - Press `⌘P` to pause the timer
   - Do your break activities
   - Press `⌘P` again to resume

4. **Finishing Up**
   - When done with all questions, press `⌘⇧F`
   - The session ends and Performance Log appears automatically

### Important Behaviors

- **Time Accumulation**: Each question tracks total time spent, even if you switch away and return
- **Pause Behavior**: You cannot switch questions while paused (prevents accidental timing errors)
- **Auto-Save**: All state changes are logged automatically

---

## Performance Log & Analytics

After finishing your session, you'll see the **Performance Log View** with comprehensive analytics:

### Statistics Overview

Four key metrics displayed at the top:

1. **Total Time**: Complete session duration
2. **Questions**: Number of questions completed
3. **Total Marks**: Sum of all mark allocations
4. **Avg Time/Mark**: Average seconds spent per mark

### Performance Table

A detailed table showing for each question:

- **Question Number**
- **Time Spent**: Minutes and seconds
- **Marks**: Allocated marks
- **Time/Mark**: Seconds per mark
- **Efficiency**: Visual bar and percentage
  - **Green** (<80%): Faster than average (efficient)
  - **Orange** (80-120%): Near average (normal)
  - **Red** (>120%): Slower than average (needs attention)

### State Change Log

Complete chronological log of all events:
- Session start/finish
- Question switches
- Pause/resume events
- Timestamps for everything

### Using the Analytics

**Identify Patterns:**
- Which questions took longest?
- Which marks-to-time ratios were best?
- Where did you pause most?

**Plan Improvements:**
- Focus practice on inefficient question types
- Set time targets based on your averages
- Understand your work rhythm from pause patterns

---

## Exporting Your Results

### Creating a PDF Receipt

1. **From Performance Log**
   - Click "Export PDF" or press `⌘E`
   - A save dialog appears

2. **Choose Location**
   - Select where to save the PDF
   - Default filename: "[Exam Title] - [Date].pdf"

3. **Review the PDF**
   - Professional A4 format
   - Includes all session data
   - Performance table
   - Complete state change log
   - Generated timestamp

### PDF Contents

Your PDF receipt includes:

1. **Header**: Session title and report type
2. **Session Information**:
   - Exam title
   - Date and time
   - Total duration
3. **Statistics Summary**: All key metrics
4. **Performance Table**: Question-by-question breakdown
5. **State Change Log**: Complete event history
6. **Footer**: Generated date and application info

---

## Keyboard Shortcuts Reference

### Essential Shortcuts

| Action | Shortcut | Notes |
|--------|----------|-------|
| New Exam Session | `⌘N` | From welcome screen |
| Pause/Resume | `⌘P` | Toggle timer |
| Previous Question | `⌘←` | Disabled when paused |
| Next Question | `⌘→` | Disabled when paused |
| Finish Exam | `⌘⇧F` | Ends session |
| Export PDF | `⌘E` | From performance log |
| Close Window | `⌘W` | Standard macOS |
| Quit Application | `⌘Q` | Standard macOS |

### Shortcut Tips

- **Learn the Navigation Keys**: `⌘←` and `⌘→` are fastest for moving through questions
- **Quick Pause**: `⌘P` is instant for breaks
- **Don't Forget Shift**: Finish is `⌘⇧F` (Command + Shift + F)

---

## Best Practices

### Before You Start

1. **Prepare Your Environment**: Close distractions, gather materials
2. **Name Sessions Clearly**: Use descriptive titles with dates
3. **Set Realistic Marks**: Match actual exam mark allocations
4. **Plan Your Approach**: Decide if you'll do questions in order

### During Your Session

1. **Stay Focused**: The timer is running—treat it like the real exam
2. **Use Pauses Wisely**: Only pause for real breaks, not thinking time
3. **Don't Rush Navigation**: Take a moment when switching questions
4. **Check the Sidebar**: Quick glance shows progress

### After Your Session

1. **Review Immediately**: Look at performance log while fresh
2. **Identify Patterns**: Note which questions were challenging
3. **Save the PDF**: Keep records for tracking improvement
4. **Plan Next Steps**: Use data to guide future practice

---

## Tips for Different Study Modes

### Full Exam Simulation
- Set up all questions before starting
- No pauses during the session
- Time limit yourself based on real exam duration
- Export PDF for your study records

### Focused Practice
- Create sessions with specific question types
- Use individual mark allocation
- Pause between questions if reviewing answers
- Compare multiple sessions on same topics

### Speed Training
- Small sessions (3-5 questions)
- Focus on time-per-mark efficiency
- Track improvement over multiple sessions
- Goal: reduce average time while maintaining accuracy

---

## Understanding Your Data

### Time Spent
- **Total Time**: Real elapsed time (excludes pauses)
- **Question Time**: Cumulative across all visits to that question
- **Accuracy**: Within 0.1 seconds

### Efficiency Metrics
- **100% Efficiency**: Exactly at your average pace
- **Below 100%**: Faster than average (good!)
- **Above 100%**: Slower than average (review these)

### State Changes
- **Start**: Question timing begins
- **Pause**: Timer stops, no time accumulation
- **Resume**: Timer restarts from where it paused
- **Question Switch**: Moving to different question
- **Finish**: Session complete

---

## Troubleshooting

### Timer Seems Stuck
- Check if session is paused (orange indicator)
- Press `⌘P` to resume

### Cannot Switch Questions
- Ensure session is not paused
- Must resume before navigating

### PDF Won't Export
- Check you have write permissions for chosen folder
- Ensure disk has available space

### Time Looks Wrong
- Remember: time accumulates across all visits to a question
- Check state change log for pause/resume events

---

## Privacy & Data

### Data Storage
- Sessions exist only in memory during use
- No automatic saving to disk
- Export PDF manually to keep records

### What Gets Logged
- Question timing data
- State changes with timestamps
- Session metadata (title, dates)
- **Not logged**: Your actual answers or work

---

## Support & Feedback

### Getting Help
- Review this user guide
- Check the README.md for technical details
- Examine the keyboard shortcuts reference

### Suggested Improvements
- Keep notes on features you'd like
- Consider how changes fit the "corporate" design aesthetic

---

## Quick Start Checklist

For your first session:

- [ ] Launch application
- [ ] Press `⌘N` for new session
- [ ] Enter exam title
- [ ] Set number of questions
- [ ] Configure marks (uniform or individual)
- [ ] Click "Create Session"
- [ ] Practice first question
- [ ] Press `⌘→` to go to next question
- [ ] Complete all questions
- [ ] Press `⌘⇧F` to finish
- [ ] Review performance log
- [ ] Press `⌘E` to export PDF
- [ ] Save PDF for your records

---

**Happy Practicing!** 🎯

Use this tool to understand your exam performance patterns and improve your time management skills.
