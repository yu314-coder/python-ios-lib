import FileProvider
import UniformTypeIdentifiers

/// CodeBench's File Provider — **legacy** `NSFileProviderExtension` (the iOS-11
/// model), exposing the App Group Documents as a top-level Files Location.
///
/// ## Why legacy (the iSH model), not replicated
/// The replicated (`NSFileProviderReplicatedExtension`) model puts the system's
/// sync engine between Files and our local folder. There is no server here —
/// yet the engine still maintained a replica, re-synced it on every signal, and
/// whenever the app was actively writing (any Python run) it ground away until
/// iOS backed the domain off: the Location showed a perpetual sync badge /
/// "Sync Paused" and stopped loading. iSH ships the legacy model for the same
/// use case (a local filesystem), has none of that UI, and demonstrably works
/// on current iOS — so this now mirrors iSH: identifiers map to real paths,
/// `startProvidingItem` copies the file into the provider's document storage,
/// `itemChanged` copies edits back. No sync engine, nothing to pause.
final class FileProviderExtension: NSFileProviderExtension {

    private let fm = FileManager.default

    override init() {
        super.init()
        AppPaths.ensureWorkspace()
        AppPaths.fpLog("ext.init(legacy) appGroup=\(AppPaths.appGroupAvailable) root=\(AppPaths.fileProviderRootURL.path)")
    }

    // MARK: - Identifier ↔ real URL (App Group) ↔ storage URL

    /// The real file/folder in the App Group for an identifier.
    private func realURL(for identifier: NSFileProviderItemIdentifier) -> URL? {
        let raw = identifier == .rootContainer ? AppPaths.rootIdentifier : identifier.rawValue
        return AppPaths.url(forIdentifier: raw)
    }

    /// Where materialized copies live: `<storage>/<b64url(id)>/<filename>`.
    /// The per-item directory (like iSH) keeps names collision-free and makes
    /// the reverse mapping trivial.
    private var storageRoot: URL {
        NSFileProviderManager.default.documentStorageURL
    }

    private static func encodeID(_ raw: String) -> String {
        Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeID(_ dirName: String) -> String? {
        var b64 = dirName
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        if identifier == .rootContainer { AppPaths.ensureWorkspace() }
        guard let item = WorkspaceItem(identifier: identifier) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return item
    }

    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        guard let item = try? item(for: identifier) else { return nil }
        // Folders aren't materialized in the legacy model.
        if item.contentType == .folder { return nil }
        return storageRoot
            .appendingPathComponent(Self.encodeID(identifier.rawValue), isDirectory: true)
            .appendingPathComponent(item.filename)
    }

    override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
        let dirName = url.deletingLastPathComponent().lastPathComponent
        guard let raw = Self.decodeID(dirName) else { return nil }
        return raw == AppPaths.rootIdentifier ? .rootContainer : NSFileProviderItemIdentifier(raw)
    }

    // MARK: - Placeholders + content

    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = persistentIdentifierForItem(at: url),
              let item = try? item(for: identifier) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try NSFileProviderManager.writePlaceholder(
                at: NSFileProviderManager.placeholderURL(for: url),
                withMetadata: item)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = persistentIdentifierForItem(at: url),
              let real = realURL(for: identifier),
              fm.fileExists(atPath: real.path) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            // Refresh a stale copy: replace when the real file is newer or sizes differ.
            if fm.fileExists(atPath: url.path) {
                let a = try? fm.attributesOfItem(atPath: url.path)
                let b = try? fm.attributesOfItem(atPath: real.path)
                let copyM = (a?[.modificationDate] as? Date) ?? .distantPast
                let realM = (b?[.modificationDate] as? Date) ?? .distantPast
                let same = copyM >= realM
                    && (a?[.size] as? NSNumber) == (b?[.size] as? NSNumber)
                if !same { try fm.removeItem(at: url); try fm.copyItem(at: real, to: url) }
            } else {
                try fm.copyItem(at: real, to: url)
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func itemChanged(at url: URL) {
        // The user edited the materialized copy in another app → write it back.
        guard let identifier = persistentIdentifierForItem(at: url),
              let real = realURL(for: identifier) else { return }
        do {
            if fm.fileExists(atPath: real.path) { try fm.removeItem(at: real) }
            try fm.copyItem(at: url, to: real)
            AppPaths.fpLog("ext.itemChanged wrote back \(real.lastPathComponent)")
        } catch {
            AppPaths.fpLog("ext.itemChanged FAILED \(real.lastPathComponent): \(error.localizedDescription)")
        }
    }

    override func stopProvidingItem(at url: URL) {
        // Persist any pending edit, drop the copy, and leave a placeholder.
        itemChanged(at: url)
        try? fm.removeItem(at: url)
        providePlaceholder(at: url) { _ in }
    }

    // MARK: - Actions (Files toolbar/context menu)

    override func createDirectory(withName directoryName: String,
                                  inParentItemIdentifier parentItemIdentifier: NSFileProviderItemIdentifier,
                                  completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        guard let parent = realURL(for: parentItemIdentifier) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem)); return
        }
        let dest = parent.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            completionHandler(WorkspaceItem(url: dest), nil)
        } catch { completionHandler(nil, error) }
    }

    override func importDocument(at fileURL: URL,
                                 toParentItemIdentifier parentItemIdentifier: NSFileProviderItemIdentifier,
                                 completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        guard let parent = realURL(for: parentItemIdentifier) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem)); return
        }
        let stop = fileURL.startAccessingSecurityScopedResource()
        defer { if stop { fileURL.stopAccessingSecurityScopedResource() } }
        var dest = parent.appendingPathComponent(fileURL.lastPathComponent)
        // De-dupe "name.ext" → "name 2.ext" like Files does.
        var n = 2
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        while fm.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            dest = parent.appendingPathComponent(name)
            n += 1
        }
        do {
            try fm.copyItem(at: fileURL, to: dest)
            completionHandler(WorkspaceItem(url: dest), nil)
        } catch { completionHandler(nil, error) }
    }

    override func renameItem(withIdentifier itemIdentifier: NSFileProviderItemIdentifier,
                             toName itemName: String,
                             completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        guard let src = realURL(for: itemIdentifier), !isProtected(src) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem)); return
        }
        let dest = src.deletingLastPathComponent().appendingPathComponent(itemName)
        do {
            try fm.moveItem(at: src, to: dest)
            completionHandler(WorkspaceItem(url: dest), nil)
        } catch { completionHandler(nil, error) }
    }

    override func reparentItem(withIdentifier itemIdentifier: NSFileProviderItemIdentifier,
                               toParentItemWithIdentifier parentItemIdentifier: NSFileProviderItemIdentifier,
                               newName: String?,
                               completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        guard let src = realURL(for: itemIdentifier), !isProtected(src),
              let parent = realURL(for: parentItemIdentifier) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem)); return
        }
        let dest = parent.appendingPathComponent(newName ?? src.lastPathComponent)
        do {
            try fm.moveItem(at: src, to: dest)
            completionHandler(WorkspaceItem(url: dest), nil)
        } catch { completionHandler(nil, error) }
    }

    override func deleteItem(withIdentifier itemIdentifier: NSFileProviderItemIdentifier,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let url = realURL(for: itemIdentifier), !isProtected(url) else {
            completionHandler(NSFileProviderError(.noSuchItem)); return
        }
        do {
            try fm.removeItem(at: url)
            completionHandler(nil)
        } catch { completionHandler(error) }
    }

    // MARK: - Enumeration

    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        AppPaths.fpLog("ext.enumerator \(containerItemIdentifier == .rootContainer ? "<root>" : containerItemIdentifier.rawValue)")
        return WorkspaceEnumerator(identifier: containerItemIdentifier)
    }

    // MARK: - Helpers

    /// The structural folders (root, Workspace, ToolOutputs, Imported,
    /// site-packages) must not be deletable/renamable via Files.
    private func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return [AppPaths.fileProviderRootURL, AppPaths.workspaceURL, AppPaths.toolOutputsURL,
                AppPaths.importedURL, AppPaths.userSitePackagesURL]
            .map { $0.standardizedFileURL.path }.contains(p)
    }
}
