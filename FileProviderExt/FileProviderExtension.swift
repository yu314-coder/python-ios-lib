import FileProvider
import UniformTypeIdentifiers

/// CodeBench's File Provider — **replicated** `NSFileProviderReplicatedExtension`
/// (iOS 16+), exposing the App Group Documents as a top-level Files Location.
///
/// ## Why replicated (again), on iOS 26
/// On iOS 26 the *legacy* `NSFileProviderExtension` crashes the moment the Files
/// app connects to it — an Apple bug in `xpc_connection_copy_bundle_id`
/// (`EXC_GUARD`), confirmed from a device/sim crash report, entirely in system
/// code. The **replicated** model uses the modern File Provider XPC path, does
/// NOT hit that bug, and demonstrably *ran and listed files* on iOS 26. Its only
/// problem before was "Paused", which was caused by the old whole-tree working
/// set OOM-ing the extension — now fixed: `WorkspaceEnumerator` is shallow +
/// paged, so there's nothing to crash and back off from.
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    private let domain: NSFileProviderDomain
    private let fm = FileManager.default

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        AppPaths.ensureWorkspace()
        AppPaths.fpLog("ext.init(replicated) appGroup=\(AppPaths.appGroupAvailable) root=\(AppPaths.fileProviderRootURL.path)")
    }

    func invalidate() {}

    // MARK: - Metadata

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        if identifier == .rootContainer { AppPaths.ensureWorkspace() }   // root must always resolve
        if let item = WorkspaceItem(identifier: identifier) {
            completionHandler(item, nil)
        } else {
            AppPaths.fpLog("ext.item MISS \(identifier == .rootContainer ? "<root>" : identifier.rawValue)")
            completionHandler(nil, NSFileProviderError(.noSuchItem))
        }
        return Progress()
    }

    // MARK: - Content download (local: hand the system a private temp copy)

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        guard let item = WorkspaceItem(identifier: itemIdentifier) else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tmp = tmpDir.appendingPathComponent(item.filename)
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            try fm.copyItem(at: item.url, to: tmp)
            completionHandler(tmp, item, nil)
        } catch {
            completionHandler(nil, nil, error)
        }
        return Progress()
    }

    // MARK: - Create

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        guard let parentURL = containerURL(itemTemplate.parentItemIdentifier) else {
            completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        let dest = parentURL.appendingPathComponent(itemTemplate.filename)
        do {
            let isFolder = itemTemplate.contentType == .folder
                || (itemTemplate.contentType?.conforms(to: .folder) ?? false)
            if isFolder {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if let src = url {
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                try fm.copyItem(at: src, to: dest)
            } else {
                fm.createFile(atPath: dest.path, contents: Data())
            }
            completionHandler(WorkspaceItem(url: dest), [], false, nil)
        } catch {
            completionHandler(nil, [], false, error)
        }
        return Progress()
    }

    // MARK: - Modify (rename / move / write contents)

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let raw = item.itemIdentifier == .rootContainer ? AppPaths.rootIdentifier : item.itemIdentifier.rawValue
        guard var currentURL = AppPaths.url(forIdentifier: raw), !isProtected(currentURL) else {
            completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        do {
            if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                let parentURL = containerURL(item.parentItemIdentifier) ?? currentURL.deletingLastPathComponent()
                let dest = parentURL.appendingPathComponent(item.filename)
                if dest.standardizedFileURL.path != currentURL.standardizedFileURL.path {
                    if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                    try fm.moveItem(at: currentURL, to: dest)
                    currentURL = dest
                }
            }
            if changedFields.contains(.contents), let src = newContents {
                if fm.fileExists(atPath: currentURL.path) { try? fm.removeItem(at: currentURL) }
                try fm.copyItem(at: src, to: currentURL)
            }
            completionHandler(WorkspaceItem(url: currentURL), [], false, nil)
        } catch {
            completionHandler(nil, [], false, error)
        }
        return Progress()
    }

    // MARK: - Delete

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        let raw = identifier == .rootContainer ? AppPaths.rootIdentifier : identifier.rawValue
        guard let url = AppPaths.url(forIdentifier: raw), !isProtected(url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return Progress()
        }
        do {
            try fm.removeItem(at: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
        return Progress()
    }

    // MARK: - Enumeration

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        AppPaths.fpLog("ext.enumerator \(containerItemIdentifier == .rootContainer ? "<root>" : containerItemIdentifier.rawValue)")
        return WorkspaceEnumerator(identifier: containerItemIdentifier)
    }

    // MARK: - Helpers

    private func containerURL(_ identifier: NSFileProviderItemIdentifier) -> URL? {
        let raw = identifier == .rootContainer ? AppPaths.rootIdentifier : identifier.rawValue
        return AppPaths.url(forIdentifier: raw)
    }

    /// The structural folders (root, Workspace, ToolOutputs, Imported,
    /// site-packages) must not be deletable/renamable via Files.
    private func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return [AppPaths.fileProviderRootURL, AppPaths.workspaceURL, AppPaths.toolOutputsURL,
                AppPaths.importedURL, AppPaths.userSitePackagesURL]
            .map { $0.standardizedFileURL.path }.contains(p)
    }
}
