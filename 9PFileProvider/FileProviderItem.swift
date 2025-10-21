import FileProvider
import UniformTypeIdentifiers

class FileProviderItem: NSObject, NSFileProviderItem {

    let identifier: NSFileProviderItemIdentifier
    let path: String
    let isDirectory: Bool
    var fileSize: Int64 = 0
    var modificationDate: Date = Date()

    init(identifier: NSFileProviderItemIdentifier, path: String, isDirectory: Bool) {
        self.identifier = identifier
        self.path = path
        self.isDirectory = isDirectory
        super.init()
    }

    convenience init(from entry: FileEntry, parentPath: String) {
        let fullPath = parentPath == "/" ? "/\(entry.name)" : "\(parentPath)/\(entry.name)"
        let identifier = NSFileProviderItemIdentifier(fullPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fullPath)

        self.init(identifier: identifier, path: fullPath, isDirectory: entry.isDirectory)
        self.fileSize = Int64(entry.size)
    }

    // MARK: - NSFileProviderItem Protocol

    var itemIdentifier: NSFileProviderItemIdentifier {
        identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if path == "/" {
            return .rootContainer
        }

        let parentPath = (path as NSString).deletingLastPathComponent
        if parentPath.isEmpty || parentPath == "/" {
            return .rootContainer
        }

        return NSFileProviderItemIdentifier(parentPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? parentPath)
    }

    var filename: String {
        if path == "/" {
            return "9P Server"
        }
        return (path as NSString).lastPathComponent
    }

    var contentType: UTType {
        if isDirectory {
            return .folder
        }

        // Determine type from extension
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log":
            return .plainText
        case "json":
            return .json
        case "xml":
            return .xml
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        case "pdf":
            return .pdf
        case "sh":
            return .shellScript
        default:
            return .data
        }
    }

    var capabilities: NSFileProviderItemCapabilities {
        var caps: NSFileProviderItemCapabilities = [.allowsReading]

        if !isDirectory {
            caps.insert(.allowsWriting)
        }

        caps.insert(.allowsRenaming)
        caps.insert(.allowsDeleting)

        if isDirectory {
            caps.insert(.allowsContentEnumerating)
            caps.insert(.allowsAddingSubItems)
        }

        return caps
    }

    var documentSize: NSNumber? {
        isDirectory ? nil : NSNumber(value: fileSize)
    }

    var contentModificationDate: Date? {
        modificationDate
    }

    var creationDate: Date? {
        modificationDate
    }
}
