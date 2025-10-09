# 9P4i - 9P for iOS L2CAP Test App

iOS application for testing L2CAP Bluetooth transport with 9P servers.

## Features

- **BLE Peripheral Scanning**: Discover nearby Bluetooth Low Energy devices
- **L2CAP Channel Connection**: Connect directly to L2CAP PSM (no GATT required)
- **Data Send/Receive**: Send hex-formatted data and receive responses
- **Real-time Logging**: Monitor all Bluetooth events and data transfers
- **Quick Test Buttons**: Pre-configured 9P protocol messages (Version, Attach)

## Requirements

- iOS 15.0 or later
- Physical iOS device with Bluetooth LE support
- Xcode 15.0 or later (for building)

## Building

1. Open `9p4i.xcodeproj` in Xcode
2. Select your development team in project settings
3. Connect your iOS device
4. Build and run (⌘R)

## Usage

### 1. Scanning for Devices

- Tap **Start Scanning** to discover BLE peripherals
- Discovered devices will appear in the list
- Tap **Stop Scanning** to halt discovery

### 2. Connecting to a Peripheral

- Tap on a device in the list to connect
- The status indicator will turn green when connected
- The app will show device information

### 3. Opening L2CAP Channel

- Enter the L2CAP PSM in hex format (e.g., `0080` for PSM 128)
- Tap **Open L2CAP Channel**
- Status will change to "Ready" when the channel is open
- The log will show channel details including MTU

### 4. Sending Data

**Manual Send:**
- Enter hex data in the text field (spaces optional)
- Example: `64 00 00 00 00 00 00 64 00 00 19 00 06 39 50 32 30 30 30 00 00 20 00 00`
- Tap the send button (paper plane icon)

**Quick Send Buttons:**
- **Version**: Sends a 9P version request (T-version)
- **Attach**: Sends a 9P attach request (T-attach)

### 5. Receiving Data

- All received data appears in the log view
- Data is displayed in hex format
- Tap the log icon (top right) to show/hide logs

### 6. Logs

- Real-time event logging with timestamps
- Color-coded by severity (info, success, warning, error)
- Tap **Clear** to clear all logs
- Auto-scrolls to latest entry

## Architecture

### L2CAPManager.swift

Core Bluetooth manager handling:
- CBCentralManager for scanning and connection
- CBPeripheral delegation for L2CAP channel operations
- Stream handling for bidirectional data transfer
- Published properties for SwiftUI binding

Key methods:
- `startScanning()` / `stopScanning()`: Peripheral discovery
- `connect(to:)`: Establish connection to peripheral
- `openL2CAPChannel(psm:)`: Open L2CAP channel on specified PSM
- `send(data:)`: Write data to L2CAP output stream
- Stream delegate receives incoming data

### ContentView.swift

SwiftUI interface with three main views:
- **Scan View**: List of discovered peripherals
- **Connected View**: Connection management and data I/O
- **Log View**: Collapsible event log

## 9P Protocol Testing

The app includes pre-configured 9P protocol messages:

**T-version** (tag=100, msize=8192, version="9P2000"):
```
64 00 00 00 00 00 00 64 00 00 19 00 06 39 50 32 30 30 30 00 00 20 00 00
```

**T-attach** (tag=101, fid=0xFFFFFFFF, afid=NOFID, uname="jsharp"):
```
74 00 00 00 00 00 00 65 FF FF FF FF 00 05 6a 73 68 61 72 70 00 00
```

Expected responses from the server will appear in the logs.

## Troubleshooting

### Bluetooth Permission Issues
- Check Settings → Privacy → Bluetooth
- Ensure the app has Bluetooth permission enabled

### Cannot Find Devices
- Ensure the peripheral is advertising
- Verify Bluetooth is enabled on iOS device
- Some peripherals may have pairing requirements

### L2CAP Channel Fails to Open
- Verify the PSM value is correct (typically 0x0080 for testing)
- Ensure the peripheral supports L2CAP
- Check that the PSM is published in the peripheral's GATT attributes

### No Data Received
- Verify the L2CAP channel is in "Ready" state
- Check that the server is sending responses
- Monitor the log for stream errors

## Testing with 9p4z

To test with your Zephyr-based 9P server:

1. Build and run your 9p4z peripheral on the target device
2. Configure it to advertise with L2CAP support
3. Note the PSM value the server is using
4. Use this iOS app to connect and send 9P messages

## Development Notes

- The app uses CoreBluetooth's direct L2CAP API (iOS 11+)
- No GATT service discovery is required for L2CAP connections
- Stream-based I/O provides efficient bidirectional communication
- All Bluetooth operations are logged for debugging

## License

This is a testing tool for the 9p4z project.
