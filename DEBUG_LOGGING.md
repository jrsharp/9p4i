# Debug Logging Guide

The app now has comprehensive debug logging to help diagnose connection and protocol issues.

## How to Capture Logs

### Option 1: Run from Xcode (Easiest)

1. Open `9p4i.xcodeproj` in Xcode
2. Select "My Mac (Mac Catalyst)" as the destination
3. Press **⌘R** to run
4. Open the **Debug Area** (⌘⇧Y)
5. Watch the Console tab as you test
6. Copy/paste the output to share

### Option 2: Run from Terminal

```bash
# Build
xcodebuild -project 9p4i.xcodeproj -scheme 9p4i \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  build

# Run and capture logs
open ~/Library/Developer/Xcode/DerivedData/9p4i-*/Build/Products/Debug-maccatalyst/9p4i.app 2>&1 | tee 9p-debug.log

# Logs will be in 9p-debug.log
```

### Option 3: View macOS Console

1. Open **Console.app** (in /Applications/Utilities/)
2. Launch the 9p4i app
3. Filter by "9p4i" in the search box
4. Watch real-time logs

## What the Logs Show

### TCP Transport Layer (Blue 🔵)

```
🔧 TCP Setup...
🔧 TCP Preparing...
✅ TCP Connected - starting receive loop
📤 Sending 19 bytes: 13 00 00 00 64 00 00 00 00 20 00 06 00 39 50 32 30 30 30
✅ Sent 19 bytes successfully
📥 Received 19 bytes: 13 00 00 00 65 00 00 00 00 20 00 06 00 39 50 32 30 30 30
📦 RX Buffer now: 19 bytes
```

### RX State Machine (Magnifying Glass 🔍)

```
🔍 State: WAIT_SIZE, buffer has 19 bytes
📏 Read size field: 19 bytes
✅ Valid size, transitioning to WAIT_MSG
🔍 State: WAIT_MSG, need 19 bytes, have 19
✂️ Extracted message, 0 bytes remain in buffer
📨 Parsing message...
✅ Parsed: RVERSION tag=0 size=19
📤 Dispatching to delegate...
✅ Dispatched
🔄 Resetting to WAIT_SIZE
```

### 9P Client Layer (Green 🟢/Blue 🟦)

```
🟢 [9P Client] Starting version negotiation...
🟢 [9P Client] Sending T-version (tag=0, msize=8192)
🟦 [9P Client] Sending request with tag=0
🟦 [9P Client] Registered handler for tag=0, sending...
🟦 [9P Client] Received message: RVERSION tag=0
🟦 [9P Client] Pending requests: [0]
🟦 [9P Client] Found handler for tag=0, calling it
🟦 [9P Client] Got response for tag=0: RVERSION
🟢 [9P Client] Got response: RVERSION
🟢 [9P Client] Server msize=8192, version=9P2000, using msize=8192
✅ [9P Client] Version negotiation complete
```

## Expected Successful Flow

```
🔧 TCP Setup...
🔧 TCP Preparing...
✅ TCP Connected - starting receive loop

🟢 [9P Client] Starting version negotiation...
📤 Sending 19 bytes: 13 00 00 00 64 00 00...
✅ Sent 19 bytes successfully
📥 Received 19 bytes: 13 00 00 00 65 00 00...
✅ Parsed: RVERSION tag=0 size=19
✅ [9P Client] Version negotiation complete

🟢 [9P Client] Starting attach...
📤 Sending 28 bytes: 1c 00 00 00 68 00 00...
✅ Sent 28 bytes successfully
📥 Received 20 bytes: 14 00 00 00 69 00 00...
✅ Parsed: RATTACH tag=1 size=20
✅ [9P Client] Attach complete

[File browser should now appear]
```

## Common Problems & What to Look For

### Problem: "Hanging on connect"

**Look for:**
```
✅ TCP Connected - starting receive loop
📥 Received X bytes: ...
```

- ✅ If you see "Received" → Server is responding
- ❌ If no "Received" → Server not sending data

### Problem: "Invalid message size"

**Look for:**
```
❌ Invalid message size: XXXXXXX (must be 7-8192)
   Buffer hex: XX XX XX XX...
```

- This means the bytes don't look like a 9P message
- First 4 bytes should be message size in little-endian
- Check server is sending 9P format, not something else

### Problem: "No handler found for tag"

**Look for:**
```
⚠️ [9P Client] No handler found for tag=X!
```

- This means server sent a response for a request we didn't send
- Or tags don't match (check little-endian encoding)

### Problem: "Request timeout"

**Look for:**
```
⏰ [9P Client] Request tag=X timed out after 30s
```

- Message was sent but no response received
- Check server logs to see if it processed the request

## Sharing Logs with Me

When you hit an issue, **copy the entire console output** starting from app launch through the error. Include:

1. All TCP state changes
2. All bytes sent/received (the hex dumps)
3. All 9P client messages
4. Any error messages

Example:
```
🔧 TCP Setup...
✅ TCP Connected - starting receive loop
🟢 [9P Client] Starting version negotiation...
📤 Sending 19 bytes: 13 00 00 00 64 00 00 00 00 20 00 06 00 39 50 32 30 30 30
[... rest of output ...]
```

## Interpreting Hex Dumps

The logs show hex bytes for sent/received data. Here's how to read them:

### T-version Message
```
📤 Sending 19 bytes: 13 00 00 00 64 00 00 00 00 20 00 06 00 39 50 32 30 30 30
                     ^^^^^^^^^^ ^^    ^^^^    ^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^
                     size=19    type  tag=0   msize=8192    "9P2000" (6 bytes)
                                =100
```

### R-version Response
```
📥 Received 19 bytes: 13 00 00 00 65 00 00 00 00 20 00 06 00 39 50 32 30 30 30
                      ^^^^^^^^^^ ^^    ^^^^    ^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^
                      size=19    type  tag=0   msize=8192    "9P2000" (6 bytes)
                                 =101
```

**Key:** All multi-byte fields are **little-endian** (least significant byte first).

## Quick Verification

To quickly verify the server is sending valid 9P:

1. Look at first 4 bytes received
2. Convert to uint32 little-endian
3. Should equal total message size
4. Should be between 7-8192

Example:
```
Received: 13 00 00 00 ...
Size = 0x00000013 = 19 bytes ✅
```

Bad example:
```
Received: 00 00 00 13 ...
Size = 0x13000000 = 318767104 bytes ❌ (wrong endianness!)
```

## Next Steps After Getting Logs

Once you share the logs, I can tell you:
- ✅ If connection is establishing
- ✅ If data is being sent/received
- ✅ If messages are in correct format
- ✅ Where exactly it's failing
- ✅ What the server needs to fix

The detailed logs will show us exactly what's happening at each layer!
