# Power Analysis: L2CAP CoC vs GATT for 9P Transport

## Executive Summary

For 9P file operations over BLE, L2CAP Connection-Oriented Channels (CoC) provide significantly better power efficiency than GATT, primarily due to **larger MTU support** reducing the number of radio wake-ups needed for bulk data transfer.

**Key Takeaway:** L2CAP CoC can use 8-173x less radio time than GATT for the same data transfer, translating to proportional battery life improvements.

## Background: BLE Power Fundamentals

Both GATT and L2CAP CoC share the same underlying BLE connection, so **connection parameters dominate power consumption**:

### Connection Parameters (Affect Both Equally)

- **Connection Interval** (7.5ms - 4s): How often devices wake up to exchange data
  - Shorter interval = lower latency, **higher power**
  - Longer interval = higher latency, **lower power**

- **Slave Latency**: Number of connection events peripheral can skip
  - Higher latency = more sleep opportunities = **lower power**

- **Radio Sleep**: Between connection events, radio is off
  - **This is where 99% of power savings come from**

**Critical Insight:** For the same connection parameters, power consumption is similar. The difference is in **efficiency per connection event** - how much useful data you can transfer while the radio is awake.

## Protocol Comparison

### GATT (Generic Attribute Profile)

**Architecture:**
- ATT (Attribute Protocol) over fixed L2CAP channel (CID 0x0004)
- Request/response model (client-initiated)
- Small default MTU (23 bytes)

**MTU Characteristics:**
```
Default MTU:           23 bytes
  - L2CAP header:      4 bytes
  - ATT header:        3 bytes (opcode + handle)
  - Payload:           20 bytes

Negotiated MTU:        23-512 bytes (BLE 4.2+)
  - Common max:        247 bytes (iOS default request)
  - Theoretical max:   512 bytes (spec limit)
```

**Pros:**
- Always available (no setup)
- Simple for small, infrequent operations
- Wide device compatibility

**Cons:**
- Small MTU = many packets for bulk data
- Request/response overhead
- Client-driven only

### L2CAP CoC (Connection-Oriented Channels)

**Architecture:**
- Dedicated dynamic L2CAP channel (PSM-based)
- Bi-directional streaming
- Large negotiated MTU

**MTU Characteristics:**
```
Typical MTU:           512-4096 bytes
  - L2CAP header:      4 bytes
  - SDU length:        2 bytes (first packet only)
  - Payload:           506-4090 bytes

Common values:
  - iOS default:       2048-4096 bytes
  - Zephyr typical:    1024-2048 bytes
  - Theoretical max:   65533 bytes
```

**Pros:**
- **Large MTU** = fewer packets for bulk data
- Less protocol overhead per byte
- Bi-directional without request/response
- Better for streaming data

**Cons:**
- One-time connection setup (~20ms)
- Requires BLE 4.1+ (practical: BLE 4.2+)
- Slightly more complex implementation

## Power Impact Analysis

### The Math: Radio Active Time

Power consumption is proportional to radio-on time:

```
Radio Time = (Number of Packets) × (Time per Packet)

Where:
  Time per Packet ≈ 0.3ms (1Mbps PHY) to 2.4ms (125kbps PHY)
  Plus connection overhead ≈ 3ms per connection event
```

### Example: 64KB File Transfer

**Scenario:** Reading a 64KB file using 4KB 9P read messages (common scenario)

| Protocol | MTU | Packets Needed | Connection Events | Radio Time @ 1Mbps PHY |
|----------|-----|----------------|-------------------|----------------------|
| GATT | 23 bytes | 2,783 | 2,783 | ~8.3 seconds |
| GATT | 247 bytes | 259 | 259 | ~0.78 seconds |
| GATT | 512 bytes | 125 | 125 | ~0.375 seconds |
| L2CAP CoC | 2048 bytes | 31 | 31 | ~0.093 seconds |
| L2CAP CoC | 4096 bytes | 16 | 16 | ~0.048 seconds |

**Radio Time Savings:**
- L2CAP CoC (4KB) vs GATT (23B): **173x less radio time**
- L2CAP CoC (4KB) vs GATT (512B): **8x less radio time**
- L2CAP CoC (4KB) vs GATT (247B): **16x less radio time**

### Current Consumption During Transfer

**Typical BLE Radio Current:**
- TX (transmit): 8-15 mA
- RX (receive): 8-12 mA
- Sleep: 0.002-0.1 mA
- Deep sleep: 0.0003-0.001 mA

**Average Current During Active Transfer:**

Assuming 100ms connection interval, 10mA radio active, 0.01mA sleep:

| Protocol | Radio Active % | Average Current |
|----------|---------------|-----------------|
| GATT (23B) | ~8.3% | ~0.84 mA |
| GATT (512B) | ~0.4% | ~0.05 mA |
| L2CAP CoC (4KB) | ~0.05% | ~0.006 mA |

### Battery Life Impact

**Assumptions:**
- CR2032 battery: 220 mAh
- Workload: Transfer 1MB/day
- Connection interval: 100ms during transfer
- Idle power: 0.01 mA (connection maintained)

**Transfer Time per Day:**

| Protocol | Transfer Time/Day | Active Current | Idle Time | Total Daily mAh |
|----------|------------------|----------------|-----------|----------------|
| GATT (23B) | ~130 sec (~2 min) | 0.84 mA | 23h 58min @ 0.01mA | 0.030 + 0.24 = **0.27 mAh/day** |
| GATT (512B) | ~6 sec | 0.05 mA | 23h 59min @ 0.01mA | 0.00008 + 0.24 = **0.24 mAh/day** |
| L2CAP CoC (4KB) | ~0.75 sec | 0.006 mA | 23h 59min @ 0.01mA | 0.000001 + 0.24 = **0.24 mAh/day** |

**Battery Life:**
- GATT (23B): ~815 days (**2.2 years**)
- GATT (512B): ~917 days (**2.5 years**)
- L2CAP CoC (4KB): ~917 days (**2.5 years**)

**Note:** At 1MB/day, idle power dominates. The difference becomes significant with higher transfer volumes.

### High-Throughput Scenario

**Workload:** Transfer 10MB/day (e.g., logging, sensor data)

| Protocol | Transfer Time/Day | Daily mAh | Battery Life |
|----------|------------------|-----------|--------------|
| GATT (23B) | ~21 min | 0.30 + 0.24 = **0.54 mAh/day** | **407 days** (1.1 years) |
| GATT (512B) | ~60 sec | 0.0008 + 0.24 = **0.24 mAh/day** | **917 days** (2.5 years) |
| L2CAP CoC (4KB) | ~7.5 sec | 0.00001 + 0.24 = **0.24 mAh/day** | **917 days** (2.5 years) |

**Power Savings:**
- L2CAP CoC: 2.25x battery life improvement over GATT (23B)
- L2CAP CoC: Similar to GATT with large MTU

## 9P-Specific Considerations

### 9P Message Patterns

9P protocol involves request/response pairs:
```
T-version (23 bytes) → R-version (23 bytes)
T-attach (40 bytes)  → R-attach (20 bytes)
T-walk (50 bytes)    → R-walk (150 bytes)
T-open (20 bytes)    → R-open (20 bytes)
T-read (23 bytes)    → R-read (4KB+ data)
T-clunk (15 bytes)   → R-clunk (15 bytes)
```

**Key Pattern:** Most power consumed in **R-read** responses with large data payloads.

### Packet Count Comparison

Reading a 64KB file (16× 4KB reads):

**GATT (23-byte MTU):**
```
Setup messages:        ~10 packets
16× T-read:            16 packets
16× R-read (4KB each): 16 × 178 = 2,848 packets
Total:                 ~2,874 packets
```

**GATT (512-byte MTU):**
```
Setup messages:        ~10 packets
16× T-read:            16 packets
16× R-read (4KB each): 16 × 8 = 128 packets
Total:                 ~154 packets
```

**L2CAP CoC (4KB MTU):**
```
Setup messages:        ~10 packets
16× T-read:            16 packets
16× R-read (4KB each): 16 × 1 = 16 packets
Total:                 ~42 packets
```

**Result:** L2CAP CoC needs **68x fewer packets** than GATT (23B) and **3.7x fewer** than GATT (512B).

## Optimization Strategies

### Dynamic Connection Parameters

**Recommended Approach:**
```
Idle (no file operations):
  - Connection interval: 1-4 seconds
  - Slave latency: 4-10
  - Power: ~0.01-0.05 mA

Active (file transfers):
  - Connection interval: 30-100ms
  - Slave latency: 0
  - Power: varies with throughput

Transition:
  - Detect file operation start
  - Request faster interval
  - Return to slow interval after ~5s idle
```

**Power Impact:**
- Idle 99% of time: Dominated by slow-interval sleep
- Active 1% of time: Large MTU minimizes radio-on time
- **Best of both worlds**

### MTU Negotiation

**iOS Behavior:**
- GATT MTU: Requests 185-247 bytes (varies by iOS version)
- L2CAP CoC MTU: Offers 2048-4096 bytes

**Zephyr Strategy:**
```c
// Request maximum practical MTU
CONFIG_BT_L2CAP_TX_MTU=4096
CONFIG_BT_BUF_ACL_RX_SIZE=4096

// 9P msize should match or be smaller
CONFIG_NINEP_MAX_MSG_SIZE=4096
```

### 9P Message Sizing

**Optimal Strategy:**
```
// Align 9P read size with MTU
msize = negotiated_mtu - overhead
read_size = msize - header_size

Example:
  MTU = 4096
  9P overhead = ~23 bytes (header + framing)
  Optimal read size = 4073 bytes

Use: 4096 for clean power-of-2
```

## Practical Recommendations

### For 9P4z (Your Use Case)

**Use L2CAP CoC because:**

1. **File operations = bulk data**
   - Large MTU provides 8-173x radio time reduction
   - Directly translates to battery savings

2. **Bi-directional protocol**
   - 9P is request/response in both directions
   - L2CAP CoC supports this naturally

3. **Connection-oriented workload**
   - File access implies persistent session
   - L2CAP connection setup cost amortized

4. **Power optimization potential**
   - Can use slow connection intervals when idle
   - Fast intervals only during active transfers
   - Large MTU minimizes radio time during transfers

**Implementation:**
- Use PSM 0x0080 (fixed, simple)
- Negotiate maximum MTU (2048-4096)
- Set 9P msize to match MTU
- Implement dynamic connection interval adjustment
- Sleep aggressively when idle

### When GATT Might Be Better

**Use GATT if:**
- Very small, infrequent reads (e.g., single sensor value)
- No persistent session needed
- Must support BLE 4.0 devices
- Don't want connection setup complexity

**Example GATT Use Case:**
```
Read temperature sensor every 60 seconds:
  - Wake up
  - Read 4-byte value via GATT
  - Sleep for 60 seconds

Power: Dominated by sleep time, MTU irrelevant
```

## Measurement Recommendations

To validate these estimates in your actual implementation:

### Zephyr Side

```c
// Enable power profiling
CONFIG_PM=y
CONFIG_PM_DEVICE=y

// Measure current with:
// - Nordic PPK2 (Power Profiler Kit)
// - Oscilloscope + current sense resistor
// - Joulescope (if available)

// Log radio events
CONFIG_BT_DEBUG_LOG=y
```

### iOS Side

```swift
// Monitor connection parameters
func peripheral(_ peripheral: CBPeripheral,
                didUpdateValueFor characteristic: CBCharacteristic) {
    // Log timestamp, byte count
    // Calculate throughput
}

// Instruments.app:
// - Bluetooth template
// - Energy log template
```

### Test Cases

1. **Baseline:** Idle connection (no data)
2. **Small transfer:** 1KB file
3. **Medium transfer:** 64KB file
4. **Large transfer:** 1MB file
5. **Sustained:** Continuous transfers for 1 minute

Compare power profiles for GATT vs L2CAP CoC.

## Conclusion

For 9P over BLE, **L2CAP Connection-Oriented Channels provide superior power efficiency** compared to GATT, primarily through:

1. **Larger MTU** (4KB vs 23-512 bytes) → Fewer packets
2. **Fewer radio wake-ups** → Less active time
3. **Better bulk transfer efficiency** → Lower average current

The power difference is most significant for:
- Large file transfers
- High-throughput applications
- Frequent 9P operations

For low-throughput scenarios (< 1MB/day), both approaches are acceptable, with idle power dominating battery life.

**Recommendation:** Implement L2CAP CoC for 9p4z, with dynamic connection parameter adjustment for optimal power/performance balance.

## References

- [BLE Power Consumption Basics](https://www.bluetooth.com/blog/the-basics-of-bluetooth-low-energy-power-consumption/)
- [iOS CoreBluetooth Energy Best Practices](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/OptimizeBluetoothCommunication.html)
- [Nordic BLE Power Profiling](https://infocenter.nordicsemi.com/index.jsp?topic=%2Fug_ppk2%2FUG%2Fppk%2FPPK_user_guide_Intro.html)
- [Zephyr Bluetooth Power Management](https://docs.zephyrproject.org/latest/services/pm/index.html)
