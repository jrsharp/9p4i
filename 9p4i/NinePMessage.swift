import Foundation

// 9P2000 Message Types
enum NinePMessageType: UInt8 {
    case tversion = 100
    case rversion = 101
    case tauth = 102
    case rauth = 103
    case tattach = 104
    case rattach = 105
    case terror = 106  // illegal
    case rerror = 107
    case tflush = 108
    case rflush = 109
    case twalk = 110
    case rwalk = 111
    case topen = 112
    case ropen = 113
    case tcreate = 114
    case rcreate = 115
    case tread = 116
    case rread = 117
    case twrite = 118
    case rwrite = 119
    case tclunk = 120
    case rclunk = 121
    case tremove = 122
    case rremove = 123
    case tstat = 124
    case rstat = 125
    case twstat = 126
    case rwstat = 127

    var name: String {
        String(describing: self).uppercased()
    }

    var isRequest: Bool {
        rawValue % 2 == 0
    }

    var isResponse: Bool {
        !isRequest
    }
}

// 9P Message
struct NinePMessage {
    let size: UInt32
    let type: NinePMessageType
    let tag: UInt16
    let data: Data  // Full message including header

    init?(data: Data) {
        guard data.count >= 7 else {
            print("⚠️ NinePMessage.init: data too small (\(data.count) bytes)")
            return nil
        }

        // Ensure we're working with contiguous data starting at index 0
        let contiguousData = Data(data)

        self.size = contiguousData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }

        print("🔍 NinePMessage.init: size=\(self.size), data.count=\(contiguousData.count)")

        guard contiguousData.count == Int(self.size) else {
            print("⚠️ NinePMessage.init: size mismatch (expected \(self.size), got \(contiguousData.count))")
            return nil
        }

        let typeRawValue = contiguousData[4]
        print("🔍 NinePMessage.init: type byte = \(typeRawValue)")

        guard let msgType = NinePMessageType(rawValue: typeRawValue) else {
            print("⚠️ NinePMessage.init: unknown message type \(typeRawValue)")
            return nil
        }
        self.type = msgType

        self.tag = contiguousData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 5, as: UInt16.self) }
        self.data = contiguousData

        print("✅ NinePMessage.init: type=\(msgType.name), tag=\(self.tag)")
    }

    // Parse payload (everything after size+type+tag)
    var payload: Data {
        data.count > 7 ? data.suffix(from: 7) : Data()
    }

    // Parse version message
    var versionInfo: (msize: UInt32, version: String)? {
        guard type == .tversion || type == .rversion else { return nil }
        guard payload.count >= 6 else {
            print("⚠️ versionInfo: payload too small (\(payload.count) bytes)")
            return nil
        }

        let msize = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let versionLen = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self) }

        print("📊 versionInfo: msize=\(msize), versionLen=\(versionLen), payload.count=\(payload.count)")

        guard versionLen <= 8192 else {
            print("⚠️ versionInfo: unreasonable version length \(versionLen)")
            return nil
        }

        guard payload.count >= 6 + Int(versionLen) else {
            print("⚠️ versionInfo: not enough data for version string (need \(6 + Int(versionLen)), have \(payload.count))")
            return nil
        }

        let startIndex = payload.startIndex.advanced(by: 6)
        let endIndex = startIndex.advanced(by: Int(versionLen))
        guard endIndex <= payload.endIndex else {
            print("⚠️ versionInfo: index out of range")
            return nil
        }

        let versionData = payload[startIndex..<endIndex]
        guard let version = String(data: versionData, encoding: .utf8) else {
            print("⚠️ versionInfo: version string not valid UTF-8")
            return nil
        }

        return (msize, version)
    }

    // Parse error message
    var errorString: String? {
        guard type == .rerror else { return nil }
        guard payload.count >= 2 else { return nil }

        let errorLen = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        guard payload.count >= 2 + Int(errorLen) else { return nil }

        let startIndex = payload.startIndex.advanced(by: 2)
        let endIndex = startIndex.advanced(by: Int(errorLen))
        guard endIndex <= payload.endIndex else { return nil }

        let errorData = payload[startIndex..<endIndex]
        return String(data: errorData, encoding: .utf8)
    }

    // Parse read response data
    var readData: Data? {
        guard type == .rread else { return nil }
        guard payload.count >= 4 else {
            print("⚠️ readData: payload too small (\(payload.count) bytes)")
            return nil
        }

        let dataLen = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }

        print("📊 readData: dataLen=\(dataLen), payload.count=\(payload.count)")

        guard dataLen <= 8192 else {
            print("⚠️ readData: unreasonable data length \(dataLen)")
            return nil
        }

        guard payload.count >= 4 + Int(dataLen) else {
            print("⚠️ readData: not enough data (need \(4 + Int(dataLen)), have \(payload.count))")
            return nil
        }

        let startIndex = payload.startIndex.advanced(by: 4)
        let endIndex = startIndex.advanced(by: Int(dataLen))
        guard endIndex <= payload.endIndex else {
            print("⚠️ readData: index out of range")
            return nil
        }

        return Data(payload[startIndex..<endIndex])
    }

    // Description for logging
    var description: String {
        var desc = "\(type.name) tag=\(tag) size=\(size)"

        if let (msize, version) = versionInfo {
            desc += " msize=\(msize) version=\"\(version)\""
        } else if let error = errorString {
            desc += " error=\"\(error)\""
        }

        return desc
    }
}

// 9P Message Builder
struct NinePMessageBuilder {
    static func buildVersion(tag: UInt16, msize: UInt32, version: String) -> Data {
        var data = Data()

        let versionData = version.data(using: .utf8) ?? Data()
        let size: UInt32 = 4 + 1 + 2 + 4 + 2 + UInt32(versionData.count)

        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian, Array.init))
        data.append(NinePMessageType.tversion.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: tag.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: msize.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(versionData.count).littleEndian, Array.init))
        data.append(versionData)

        return data
    }

    static func buildAttach(tag: UInt16, fid: UInt32, afid: UInt32, uname: String, aname: String) -> Data {
        var data = Data()

        let unameData = uname.data(using: .utf8) ?? Data()
        let anameData = aname.data(using: .utf8) ?? Data()
        let size: UInt32 = 4 + 1 + 2 + 4 + 4 + 2 + UInt32(unameData.count) + 2 + UInt32(anameData.count)

        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian, Array.init))
        data.append(NinePMessageType.tattach.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: tag.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: fid.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: afid.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(unameData.count).littleEndian, Array.init))
        data.append(unameData)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(anameData.count).littleEndian, Array.init))
        data.append(anameData)

        return data
    }

    static func buildClunk(tag: UInt16, fid: UInt32) -> Data {
        var data = Data()
        let size: UInt32 = 4 + 1 + 2 + 4

        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian, Array.init))
        data.append(NinePMessageType.tclunk.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: tag.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: fid.littleEndian, Array.init))

        return data
    }

    static func buildWalk(tag: UInt16, fid: UInt32, newFid: UInt32, wnames: [String]) -> Data {
        var data = Data()

        // Calculate size
        var wnamesSize: UInt32 = 0
        for name in wnames {
            wnamesSize += 2 + UInt32((name.data(using: .utf8) ?? Data()).count)
        }

        let size: UInt32 = 4 + 1 + 2 + 4 + 4 + 2 + wnamesSize

        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian, Array.init))
        data.append(NinePMessageType.twalk.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: tag.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: fid.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: newFid.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(wnames.count).littleEndian, Array.init))

        for name in wnames {
            let nameData = name.data(using: .utf8) ?? Data()
            data.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian, Array.init))
            data.append(nameData)
        }

        return data
    }

    static func buildOpen(tag: UInt16, fid: UInt32, mode: UInt8) -> Data {
        var data = Data()
        let size: UInt32 = 4 + 1 + 2 + 4 + 1

        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian, Array.init))
        data.append(NinePMessageType.topen.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: tag.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: fid.littleEndian, Array.init))
        data.append(mode)

        return data
    }

    static func buildRead(tag: UInt16, fid: UInt32, offset: UInt64, count: UInt32) -> Data {
        var data = Data()
        let size: UInt32 = 4 + 1 + 2 + 4 + 8 + 4

        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian, Array.init))
        data.append(NinePMessageType.tread.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: tag.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: fid.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: offset.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: count.littleEndian, Array.init))

        return data
    }
}
