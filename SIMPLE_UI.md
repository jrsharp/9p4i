# 9P File Browser - Simple, Consumer-Friendly UI

## The Vision

A **dead-simple iOS app** that demonstrates how easy it is to browse files on an embedded device using 9P. No hex dumps, no protocol details, no developer jargon—just "connect → browse → read."

Perfect for demos and showing off how accessible embedded systems can be with the right protocol.

## User Experience Flow

```
┌─────────────────────┐
│   Launch App        │
│                     │
│  "9P File Browser"  │
│                     │
│  [Bluetooth|Network]│ ← Simple picker
│                     │
│  [Scan for Devices] │
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│  Device List        │
│  • ESP32 Board      │ ← Tap to connect
│  • Zephyr Device    │
│  • My Sensor        │
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│  Files              │
│  / ▸ logs ▸         │ ← Breadcrumb navigation
│                     │
│  📁 config          │ ← Folders
│  📁 data            │
│  📄 status.txt      │ ← Files with size
│  📄 README.md       │
└─────────────────────┘
          │
          ▼  (tap file)
┌─────────────────────┐
│  status.txt         │
│                     │
│  Temperature: 23.5°C│ ← Simple text viewer
│  Uptime: 42 hours   │
│  Status: OK         │
│                     │
└─────────────────────┘
```

## Screen-by-Screen Breakdown

### 1. Connection Screen

**Purpose:** Let user choose how to connect (Bluetooth or Network)

**What the user sees:**
- Large, friendly app icon
- "9P File Browser" title
- Subtitle: "Browse files on embedded devices"
- Segmented control: `Bluetooth | Network`
- Device list (BT) or IP/port fields (Network)
- Big blue "Connect" button

**What happens:**
- BT mode: Scan → show devices → tap to connect
- Network mode: Enter IP:port → connect
- Progress indicator during connection
- Error message if connection fails

**Design goals:**
- **Zero learning curve** - looks like any other iOS app
- **One decision** - BT or Network?
- **Visual feedback** - scanning animation, connection status

### 2. File Browser Screen

**Purpose:** Navigate folder hierarchy and select files

**What the user sees:**
- Navigation bar with "Files" title
- Breadcrumb path (e.g., `/` → `logs` → `sensors`)
- List of folders (📁) and files (📄)
- File sizes for files
- Chevron (›) for folders

**What happens:**
- Tap folder → navigate into it
- Tap file → open viewer
- Tap breadcrumb → jump to that folder
- Pull to refresh (TODO)

**Design goals:**
- **Familiar** - works exactly like iOS Files app
- **Fast** - async loading, shows spinner while loading
- **Clear hierarchy** - breadcrumbs show where you are

### 3. File Viewer Screen

**Purpose:** Display text file contents

**What the user sees:**
- File name in nav bar
- Scrollable text content (monospaced font)
- "Done" button to go back

**What happens:**
- Loads file contents via 9P
- Displays as UTF-8 text
- Shows error if file isn't text

**Design goals:**
- **Simple** - just show the text
- **Readable** - monospaced font for config files, logs, etc.
- **No editing** - read-only for now (keeps it simple)

## Implementation Architecture

### Component Structure

```
ContentView
├── showingConnection? → ConnectionView
└── !showingConnection? → FileBrowserView
                          └── selectedFile? → FileViewerView
```

### Key Classes

**NinePClient** - High-level 9P client
- `connect(transport:)` - Negotiate version, attach to root
- `listDirectory(path:)` - Return array of FileEntry
- `readFile(path:)` - Return file contents as Data

**L2CAPTransport** - Bluetooth L2CAP transport
- Implements `NinePTransport` protocol
- Handles BLE scanning, connection, L2CAP channel
- Message framing (RX state machine)

**NinePMessage** - Protocol message parsing/building
- Parse 9P messages (version, attach, walk, open, read, etc.)
- Build 9P requests
- Extract payloads (version info, read data, errors)

**FileEntry** - File/folder metadata
- `name`, `isDirectory`, `size`, `mode`
- Parsed from 9P stat structures
- Provides icon and size formatting

### Data Flow Example: Reading a File

```
User taps "status.txt"
    ↓
FileViewerView.loadFile()
    ↓
client.readFile(path: "/status.txt")
    ↓
1. Walk to file (T-walk → R-walk)
2. Open file (T-open → R-open)
3. Read in chunks (T-read → R-read × N)
4. Clunk when done (T-clunk → R-clunk)
    ↓
Returns Data
    ↓
Convert to String (UTF-8)
    ↓
Display in scrollable text view
```

## What Makes It Simple?

### For End Users:

1. **No configuration** - just tap and browse
2. **Familiar UI** - looks like Files.app
3. **No jargon** - no "PSM", "MTU", "fids", just files and folders
4. **Instant feedback** - shows what's happening (scanning, loading, etc.)

### For Developers:

1. **Clean separation** - transport ↔ client ↔ UI
2. **Async/await** - modern Swift concurrency
3. **SwiftUI** - declarative, reactive UI
4. **Protocol-based** - easy to add TCP transport later

## Comparison: Old vs New UI

### Old UI (Developer Tool)

```
✗ Hex data entry fields
✗ Raw 9P message logging
✗ Manual PSM configuration
✗ Quick-send buttons for T-version, T-attach
✗ Connection state machine display
✗ Requires understanding of 9P protocol
```

**Use case:** Testing 9P implementation, debugging protocol

### New UI (Consumer App)

```
✓ File browser (folders & files)
✓ Text file viewer
✓ Simple BT device picker
✓ Breadcrumb navigation
✓ No protocol knowledge required
✓ Looks like a normal iOS app
```

**Use case:** Demonstrating 9P ease of use, actual file access

## What's Still Missing?

### Essential (For TCP Support):

- [ ] TCP/IP transport implementation
- [ ] Network reachability checking
- [ ] Connection timeout handling

### Nice-to-Have:

- [ ] Pull-to-refresh on directory view
- [ ] Search within files
- [ ] Binary file preview (hex dump)
- [ ] File download (save to iOS Files app)
- [ ] Remember recent connections
- [ ] Dark mode optimization
- [ ] iPad split-view support

### Future Enhancements:

- [ ] Write support (edit files)
- [ ] File upload
- [ ] Multiple connections (tabs?)
- [ ] Share files via iOS share sheet
- [ ] Background file transfer
- [ ] Offline caching

## Demo Script

**Perfect for showing off 9p4z:**

1. **Launch app** - "This is a simple file browser for embedded devices"
2. **Tap Bluetooth** - "No cables, no network setup needed"
3. **Scan** - "Here's my Zephyr board running 9p4z"
4. **Tap device** - "Just tap to connect..."
5. **Files appear** - "And now I can browse its filesystem"
6. **Navigate folders** - "Navigate just like on iOS"
7. **Tap a file** - "Read a config file or sensor log"
8. **Show content** - "That's it! Remote file access, zero configuration"

**The pitch:** "This is how simple embedded system access can be with 9P. No custom app for each device, no web server overhead, just files."

## Building and Running

### Requirements:
- Xcode 15+
- iOS 15+ device (Bluetooth L2CAP requires real hardware)
- Zephyr board running 9p4z with L2CAP transport

### Quick Start:
1. Open `9p4i.xcodeproj` in Xcode
2. Select your development team
3. Build to iOS device
4. Launch, tap Bluetooth, scan, connect!

### First Connection:
1. Make sure your Zephyr board is advertising
2. L2CAP PSM should be 0x0080 (default)
3. App will handle version negotiation automatically
4. Root filesystem appears in browser

## Files Overview

```
9p4i/
├── App.swift                    # App entry point
├── ContentView.swift            # Main coordinator + all UI views
├── NinePClient.swift            # High-level 9P client
├── NinePMessage.swift           # Protocol parsing/building
├── L2CAPTransport.swift         # Bluetooth L2CAP transport
├── Info.plist                   # Bluetooth permissions
└── Assets.xcassets/             # Icons and colors
```

**Total:** ~900 lines of Swift for a complete 9P file browser!

## Design Principles

1. **Simplicity over features** - Do one thing well
2. **Familiar patterns** - Use iOS conventions
3. **No surprises** - Behave like users expect
4. **Progressive disclosure** - Hide complexity
5. **Immediate feedback** - Always show what's happening

## Conclusion

This isn't a developer tool anymore—it's a **proof of concept that embedded systems can be as easy to access as any cloud service**, just by using the right protocol (9P) and making a thoughtful UI.

Perfect for:
- ✓ Product demos
- ✓ Trade show displays
- ✓ Customer pilots
- ✓ Convincing management to use 9P
- ✓ Your own debugging (it's actually useful!)

The message: **"This is the future of embedded system UX."**
