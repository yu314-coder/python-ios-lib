import FileProvider
import UniformTypeIdentifiers

/// An `NSFileProviderItem` backed by a real file/folder in the shared
/// Workspace. Identifiers are paths relative to the Workspace root.
final class WorkspaceItem: NSObject, NSFileProviderItem {

    let url: URL
    private let ident: NSFileProviderItemIdentifier
    private let attrs: [FileAttributeKey: Any]

    init?(identifier: NSFileProviderItemIdentifier) {
        let raw = identifier == .rootContainer ? AppPaths.rootIdentifier : identifier.rawValue
        guard let u = AppPaths.url(forIdentifier: raw),
              // The identifier must map to a real file/folder. Rejecting stale
              // identifiers (and special sentinels like the working-set
              // container, which isn't a concrete item) makes `item(for:)`
              // return `.noSuchItem` cleanly instead of a bogus placeholder —
              // a common cause of the error badge on the domain.
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        self.url = u
        self.ident = identifier
        self.attrs = (try? FileManager.default.attributesOfItem(atPath: u.path)) ?? [:]
        super.init()
    }

    init(url: URL) {
        self.url = url
        let id = AppPaths.identifier(forURL: url)
        self.ident = (id == AppPaths.rootIdentifier) ? .rootContainer
                                                      : NSFileProviderItemIdentifier(id)
        self.attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        super.init()
    }

    private var isDirectory: Bool {
        (attrs[.type] as? FileAttributeType) == .typeDirectory
    }

    // MARK: NSFileProviderItem (required)

    var itemIdentifier: NSFileProviderItemIdentifier { ident }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if ident == .rootContainer { return .rootContainer }
        let parent = url.deletingLastPathComponent()
        return WorkspaceItem(url: parent).itemIdentifier
    }

    var filename: String {
        ident == .rootContainer ? "CodeBench" : url.lastPathComponent
    }

    var capabilities: NSFileProviderItemCapabilities {
        [.allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting,
         .allowsDeleting, .allowsContentEnumerating]
    }

    var contentType: UTType {
        if isDirectory { return .folder }
        return UTType(filenameExtension: url.pathExtension) ?? .data
    }

    // Replicated extensions key invalidation off this version. Derive it from
    // the file's mtime + size so external edits are picked up.
    var itemVersion: NSFileProviderItemVersion {
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let tag = Data("\(mtime)-\(size)".utf8)
        return NSFileProviderItemVersion(contentVersion: tag, metadataVersion: tag)
    }

    // MARK: NSFileProviderItem (optional, but nice to have)

    var documentSize: NSNumber? {
        isDirectory ? nil : (attrs[.size] as? NSNumber)
    }

    var creationDate: Date? {
        attrs[.creationDate] as? Date
    }

    var contentModificationDate: Date? {
        attrs[.modificationDate] as? Date
    }
}
