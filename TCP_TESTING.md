# Testing 9P over TCP

Now that TCP transport is implemented, you can test the iOS app with your Zephyr device over WiFi!

## Quick Start

### On Your Zephyr Device (9p4z):

```c
// Configure your 9P server to listen on TCP port 564 (or any port you choose)
// Default 9P port is 564

// Start TCP server
ninep_server_init();
tcp_transport_start(564);  // Port 564

// Make sure your device is on the same WiFi network as your Mac/iOS device
```

### On iOS/Mac App:

1. **Launch the app**
2. **Select "Network"** (not Bluetooth)
3. **Enter connection details:**
   - IP Address: `192.168.1.xxx` (your Zephyr device's IP)
   - Port: `564` (or whatever port your 9P server is using)
4. **Tap "Connect"**
5. **Browse files!**

## Connection Flow

```
iOS App (9P Client)          Zephyr Device (9P Server)
        │                              │
        ├─── TCP Connect ─────────────►│
        │◄── TCP Accept ───────────────┤
        │                              │
        ├─── T-version ───────────────►│
        │◄── R-version ────────────────┤
        │                              │
        ├─── T-attach ────────────────►│
        │◄── R-attach ─────────────────┤
        │                              │
        ├─── T-walk ──────────────────►│
        │◄── R-walk ───────────────────┤
        │                              │
        ├─── T-open ──────────────────►│
        │◄── R-open ───────────────────┤
        │                              │
        ├─── T-read ──────────────────►│
        │◄── R-read ───────────────────┤
        │    (file contents)            │
```

## Testing with a Simple 9P Server

If you want to test before your Zephyr implementation is ready, you can use an existing 9P server:

### Option 1: Plan 9 from User Space (p9p)

```bash
# Install p9p (you may already have this)
# See: https://9fans.github.io/plan9port/

# Serve a directory
9p serve 'tcp!*!564' /path/to/directory
```

### Option 2: diod (9P server for Linux)

```bash
# Install diod
sudo apt-get install diod

# Configure and start
sudo diod -f -n -d 1 -e /tmp -l 0.0.0.0:564
```

### Option 3: Python test server

```python
#!/usr/bin/env python3
# Simple 9P test server (minimal implementation)

import socket
import struct

def handle_version(data):
    # Parse T-version
    tag = struct.unpack('<H', data[5:7])[0]
    msize = struct.unpack('<I', data[7:11])[0]

    # Send R-version
    version = b'9P2000'
    size = 4 + 1 + 2 + 4 + 2 + len(version)
    response = struct.pack('<IBHIH', size, 101, tag, min(msize, 8192), len(version))
    response += version
    return response

# Minimal server that responds to version
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('0.0.0.0', 564))
sock.listen(1)

print("Listening on port 564...")
while True:
    conn, addr = sock.accept()
    print(f"Connection from {addr}")

    # Read message
    size_bytes = conn.recv(4)
    if not size_bytes:
        break

    size = struct.unpack('<I', size_bytes)[0]
    msg = size_bytes + conn.recv(size - 4)

    msg_type = msg[4]
    print(f"Received message type: {msg_type}")

    if msg_type == 100:  # T-version
        response = handle_version(msg)
        conn.sendall(response)
        print("Sent R-version")

    conn.close()
```

## Common Issues

### Connection Refused

**Problem:** "Connection refused" error

**Solutions:**
- Check the IP address is correct
- Verify the 9P server is running
- Check firewall isn't blocking the port
- Make sure devices are on the same network

### Connection Timeout

**Problem:** Connection times out

**Solutions:**
- Ping the device to verify network connectivity
- Check if the server is listening: `netstat -an | grep 564`
- Verify port number matches

### "Protocol Error" After Connect

**Problem:** Connects but then fails with protocol error

**Solutions:**
- Check server is sending proper 9P messages
- Verify little-endian byte order
- Check message size field is correct
- Use Wireshark to inspect traffic

## Debugging Tips

### 1. Enable Verbose Logging

Add print statements to `TCPTransport.swift`:

```swift
private func handleStateChange(_ state: NWConnection.State) {
    print("TCP State: \(state)")  // Add this
    // ... rest of function
}

private func processRxBuffer() {
    print("RX Buffer: \(rxBuffer.count) bytes")  // Add this
    // ... rest of function
}
```

### 2. Wireshark Capture

```bash
# Capture 9P traffic
sudo tcpdump -i any port 564 -w 9p-capture.pcap

# View in Wireshark
wireshark 9p-capture.pcap
```

### 3. Test with netcat

```bash
# Verify server is listening
nc -zv 192.168.1.100 564

# Manual connection test
nc 192.168.1.100 564
```

## Expected Behavior

### Successful Connection:

1. App shows "Connecting..."
2. Connection succeeds → "Connected"
3. Version negotiation happens automatically
4. File browser appears with root directory
5. Navigate folders by tapping
6. View files by tapping

### Failed Connection:

- Shows error message in red
- Returns to connection screen
- Error description helps diagnose issue

## Next Steps

Once TCP is working:
1. Test file browsing
2. Test reading different file types
3. Test nested directories
4. Verify error handling (disconnect, read errors, etc.)
5. Then move to L2CAP for Bluetooth testing!

## Performance Notes

**TCP Advantages:**
- Easier to debug (Wireshark, tcpdump)
- Works over WiFi/Ethernet
- Longer range than Bluetooth
- Higher throughput potential

**TCP vs L2CAP:**
- TCP adds ~40 bytes overhead per packet (IP+TCP headers)
- L2CAP has ~4-8 bytes overhead
- TCP has better tooling for debugging
- L2CAP has lower latency (no network stack)

## Zephyr Configuration

Your 9p4z Kconfig for TCP:

```kconfig
CONFIG_NINEP_TRANSPORT_TCP=y
CONFIG_NINEP_TCP_PORT=564
CONFIG_NET_TCP=y
CONFIG_NET_SOCKETS=y
CONFIG_NET_IPV4=y
```

Sample Zephyr code:

```c
// In your main.c or wherever you initialize 9P

#include <zephyr/net/socket.h>
#include <ninep/server.h>
#include <ninep/transport/tcp.h>

void main(void) {
    // Initialize networking
    // (Your existing WiFi/Ethernet setup)

    // Start 9P server on TCP
    struct ninep_transport *transport = tcp_transport_create(564);
    ninep_server_start(transport);

    printk("9P server listening on port 564\n");
}
```

## Success Criteria

✅ App connects to server
✅ Version negotiation succeeds
✅ Root directory appears
✅ Can navigate into folders
✅ Can read text files
✅ Disconnect works cleanly

Once all these work over TCP, you'll have confidence that the 9P protocol implementation is correct, and then L2CAP will be straightforward (just a different transport layer)!

## Questions?

The TCP transport implementation is in `TCPTransport.swift`. It uses Apple's `Network.framework` for modern, async networking. The framing logic (RX state machine) is identical to L2CAP, so once it works over TCP, it should work over Bluetooth too!
