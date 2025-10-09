9P for iOS
====

**Simple, friendly file browser for embedded devices using 9P over Bluetooth L2CAP or TCP.**

Browse files on your Zephyr board (or any 9P server) as easily as browsing iCloud Drive. No configuration, no custom protocols, just connect and browse.

## What Is This?

An iOS app that makes embedded systems feel like modern cloud services:

- **Connect** via Bluetooth (or TCP/IP)
- **Browse** folders and files with familiar iOS UI
- **Read** configuration files, sensor logs, status files
- **Zero learning curve** - works exactly like Files.app

Perfect for:
- Demos
- Product pilots
- Debugging embedded systems
- Showing off how simple 9P makes device access

## Screenshot Flow

```
[Connection Screen]       [File Browser]          [File Viewer]
   "Scan Devices"    →    📁 logs           →      Temperature: 23.5°C
   • ESP32 Board           📁 config                Uptime: 42 hours
   • Zephyr Device         📄 status.txt            Status: OK
   [Connect]               📄 README.md
```

## Features

### Simple Connection
- Scan for Bluetooth devices
- One-tap connect
- TCP/IP support (WiFi/Ethernet)
- Automatic 9P version negotiation

### Familiar File Browser
- Navigate folder hierarchies
- Breadcrumb navigation (Home → logs → sensors)
- File icons and sizes
- Tap folders to navigate
- Tap files to view

### Text File Viewer
- Clean, scrollable text display
- Monospaced font for config files
- UTF-8 text files
- Easy to read logs and status

## How It Works

### Under the Hood:
1. **L2CAP Connection** - Direct Bluetooth channel (no GATT overhead)
2. **9P Protocol** - Standard file protocol from Plan 9
3. **Async Operations** - Fast, non-blocking file access
4. **Auto Framing** - Handles message boundaries automatically

### For Users:
1. Scan for devices
2. Tap to connect
3. Browse folders
4. Read files

**That's it!**

## Use Cases

### Sensor Platforms
```
/sensors/
  temperature.txt  →  "23.5°C"
  humidity.txt     →  "45%"
  pressure.txt     →  "1013 hPa"
```

### Configuration Management
```
/config/
  wifi.conf        →  Edit network settings
  device.conf      →  View device parameters
  update.log       →  Check update status
```

### Logging and Diagnostics
```
/logs/
  system.log       →  System events
  error.log        →  Error messages
  metrics.csv      →  Performance data
```

### IoT Device Management
```
/
  📁 sensors/
  📁 config/
  📁 logs/
  📄 status.txt    →  Quick device status
  📄 version.txt   →  Firmware version
```

## Building

### Requirements:
- Xcode 15.0+
- iOS 15.0+ device (Bluetooth requires real hardware)
- Development team for code signing

### Steps:
1. Open `9p4i.xcodeproj` in Xcode
2. Select your team in project settings
3. Connect your iPhone/iPad
4. Build and run (⌘R)

## Testing with 9p4z

### Zephyr Setup (your other project):
```c
// Enable L2CAP transport
CONFIG_BT_L2CAP_DYNAMIC_CHANNEL=y
CONFIG_NINEP_TRANSPORT_L2CAP=y
CONFIG_NINEP_L2CAP_PSM=0x0080

// Start 9P server
ninep_server_init();
l2cap_transport_start(0x0080);
```

### iOS App:
1. Launch app
2. Tap "Bluetooth"
3. Tap "Scan for Devices"
4. Select your Zephyr board
5. Wait for connection
6. Browse your embedded filesystem!

## Architecture

### Clean Separation of Concerns:

```
UI Layer (SwiftUI)
├── ConnectionView      # Device selection
├── FileBrowserView     # Folder navigation
└── FileViewerView      # Text display

Client Layer
└── NinePClient         # High-level 9P operations

Transport Layer
├── L2CAPTransport      # Bluetooth implementation
└── TCPTransport        # TCP/IP (coming soon)

Protocol Layer
└── NinePMessage        # Message parsing/building
```

### Key Features:
- **Async/await** throughout - Modern Swift concurrency
- **Protocol-based** transport - Easy to add new transports
- **SwiftUI** - Declarative, reactive UI
- **Published properties** - Automatic UI updates

## Why 9P?

### Traditional Approach:
```
Device ─[Custom Protocol]→ Custom App
         ↓
   Requires app update for every device change
   Different UI for each product
   Complex protocol implementation
```

### 9P Approach:
```
Device ─[9P Protocol]→ Universal File Browser
        ↓
  One app for all 9P devices
  Familiar file interface
  Standard, proven protocol
```

**9P gives you:** File-based device access with zero app changes per device.

## Documentation

- **[SIMPLE_UI.md](SIMPLE_UI.md)** - UI design philosophy and user flow
- **[TCP_TESTING.md](TCP_TESTING.md)** - How to test with TCP/WiFi (start here!)
- **[L2CAP_TRANSPORT_DESIGN.md](L2CAP_TRANSPORT_DESIGN.md)** - Technical transport design
- **[POWER_ANALYSIS.md](POWER_ANALYSIS.md)** - L2CAP vs GATT power comparison
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Implementation details
- **[USAGE.md](USAGE.md)** - Original usage guide (developer-oriented)

## Current Status

### ✅ Implemented:
- Bluetooth L2CAP connection
- **TCP/IP transport (WiFi/Ethernet)**
- 9P client (version, attach, walk, open, read, clunk)
- File browser UI with navigation
- Text file viewer
- Directory listing
- Error handling
- Mac Catalyst support (test on Mac!)

### 🚧 Future:
- Pull-to-refresh
- Connection history

### 💡 Future:
- File editing
- Binary file preview
- File download to iOS
- Search
- Multiple connections

## Demo Pitch

*"This is a file browser for embedded devices. No custom app needed—just connect via Bluetooth and browse files like you would on iCloud. Configuration, logs, sensor data—all accessible with zero configuration."*

**[Tap Bluetooth] → [Scan] → [Connect] → [Browse Files]**

*"That's it. This is how simple embedded systems should be."*

## Contributing

This is a reference implementation for the 9p4z project. Feel free to:
- Add features
- Fix bugs
- Improve UI
- Add transports (USB, BLE GATT, etc.)
- Create forks for specific devices

## License

Part of the 9p4z project ecosystem.

## Credits

Built to demonstrate how simple embedded system access can be with 9P over L2CAP.

Pairs with: [9p4z](https://github.com/jrsharp/9p4z) - 9P library for Zephyr RTOS
