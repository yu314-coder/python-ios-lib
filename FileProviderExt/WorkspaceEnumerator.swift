import FileProvider

/// Enumerates Workspace contents for the Files app and drives live refresh.
///
/// ## Why this is shallow + paged (the "Paused" fix)
/// A File Provider extension runs with a tight memory/time budget. Building
/// thousands of `NSFileProviderItem`s in one go — which an earlier version did
/// by walking the **entire** Workspace tree for the working set — OOM-crashes
/// the extension on big folders (an extracted ISO or Android firmware is easily
/// thousands of files). When the extension keeps getting killed, the Files app
/// shows the Location as **"Paused"** and sync stalls.
///
/// So:
/// * The **working set** (`NSFileProviderItemIdentifier.workingSet`) — Apple's
///   change-notification channel — is served as a **shallow** view of the
///   Workspace *root* (its direct children), NOT a full-tree walk. That's
///   enough for the system to learn about top-level changes (a `7z`/binwalk
///   extraction drops a new folder at the root), at a fraction of the cost.
/// * Every container is enumerated in **pages** of `pageSize`, so peak memory
///   stays bounded no matter how many files a single folder holds.
/// * Folders the user opens refresh through their own enumerator (a fresh disk
///   read), so deeper contents are always current on navigation.
final class WorkspaceEnumerator: NSObject, NSFileProviderEnumerator {

    private let identifier: NSFileProviderItemIdentifier
    private var isWorkingSet: Bool { identifier == .workingSet }

    /// Items handed to the system per page — keeps the extension's peak memory
    /// bounded so a folder with thousands of files can't OOM-crash it.
    private static let pageSize = 256
    /// Backstop on how many items one container reports (bounds worst-case time).
    private static let maxItems = 10_000

    init(identifier: NSFileProviderItemIdentifier) {
        self.identifier = identifier
        super.init()
    }

    func invalidate() {}

    /// Names excluded from the **sync-anchor hash** — written frequently, so
    /// folding them into the anchor would churn it and re-trigger endless
    /// re-syncs ("Paused").
    ///   • Documents-level: shell logs + the autocomplete index.
    ///   • Container-level (the Location root is the App Group home now): the
    ///     system `Library` (its caches mutate constantly) and the File
    ///     Provider's own `.fp_snapshots` — which THIS enumerator rewrites on
    ///     every pass, so hashing it is a guaranteed feedback loop — plus
    ///     `.fp_diag` and the container metadata. None are user data.
    static let anchorVolatile: Set<String> = [
        "log.txt", "shell_bootstrap.txt", "fp_debug.log", ".symbol_index.json",
        "conversations.json",  // AI history — rewritten on every message; would churn the Documents anchor
        "Library", "File Provider Storage", ".fp_diag", ".fp_snapshots",
        ".com.apple.mobile_container_manager.metadata.plist",
        // The live run-output streams (ToolOutputs) — appended to continuously
        // for the whole duration of every Python run. Folding them into the
        // anchor/deltas re-synced the domain every ~1.2 s while any script ran,
        // which is exactly when iOS backs the provider off ("Sync Paused").
        "_stream_stdout.txt", "_stream_stderr.txt",
    ]

    /// Top-level entries HIDDEN from the Location root. The Location is rooted at
    /// the App Group container, whose `Library` holds `Caches/pycache` — Python's
    /// byte-code cache that mirrors the full bundle path
    /// (`…/CodeBench.app/{python,app_packages}`) for EVERY historical app-install
    /// UUID, i.e. thousands of files times dozens of installs. Excluding `Library`
    /// from the anchor stopped it *churning* the hash, but the replicated engine
    /// still *recursed* into it and drowned → permanent "Paused". Hiding these at
    /// the root means the engine never sees them as children, so it never walks
    /// them. Only the user's `Documents` (Workspace · ToolOutputs · Imported) and
    /// real user content remain visible — matching what people expect in Files.
    static let rootHidden: Set<String> = [
        "Library", "tmp", "SystemData", ".fp_diag", ".fp_snapshots",
        "File Provider Storage", ".com.apple.mobile_container_manager.metadata.plist",
        ".Trash",
    ]

    /// The directory this enumerator lists. The working set maps to the File
    /// Provider root (the App Group Documents); shallow — see the type doc.
    private var dirURL: URL? {
        if isWorkingSet { return AppPaths.fileProviderRootURL }
        let raw = identifier == .rootContainer ? AppPaths.rootIdentifier : identifier.rawValue
        return AppPaths.url(forIdentifier: raw)
    }

    /// Direct children, sorted by name (stable order across pages), capped.
    private func childURLs() -> [URL] {
        guard let dir = dirURL else { return [] }
        var entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
        // At the Location ROOT (the App Group container, also what the working
        // set maps to), drop the system/cache dirs in `rootHidden`. Otherwise
        // the replicated engine recurses into `Library/Caches/pycache` — a
        // byte-code cache mirroring every app-install's bundle path — and
        // drowns into a permanent "Paused". Deeper folders are listed in full.
        if dir.standardizedFileURL.path == AppPaths.fileProviderRootURL.standardizedFileURL.path {
            entries = entries.filter { !Self.rootHidden.contains($0.lastPathComponent) }
        }
        entries.sort { $0.lastPathComponent < $1.lastPathComponent }
        if entries.count > Self.maxItems {
            NSLog("[FileProvider] %ld items in %@ exceeds cap %d — listing first %d",
                  entries.count, dir.lastPathComponent, Self.maxItems, Self.maxItems)
            entries = Array(entries.prefix(Self.maxItems))
        }
        return entries
    }

    // MARK: - Paging (offset carried in the opaque page as a small string)

    private static func decodeOffset(_ page: NSFileProviderPage) -> Int {
        guard let s = String(data: page.rawValue, encoding: .utf8),
              s.hasPrefix("off:"), let n = Int(s.dropFirst(4)) else { return 0 }  // initial page → 0
        return n
    }
    private static func encodeOffset(_ off: Int) -> NSFileProviderPage {
        NSFileProviderPage(Data("off:\(off)".utf8))
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {
        guard isWorkingSet || dirURL != nil else {
            observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem))
            return
        }
        let all = childURLs()
        AppPaths.fpLog("enum.items \(isWorkingSet ? "<ws>" : (identifier == .rootContainer ? "<root>" : identifier.rawValue)) count=\(all.count)")
        let offset = Self.decodeOffset(page)
        let end = min(offset + Self.pageSize, all.count)
        if offset < end {
            observer.didEnumerate(all[offset..<end].map { WorkspaceItem(url: $0) })
        }
        if end < all.count {
            observer.finishEnumerating(upTo: Self.encodeOffset(end))      // more pages to come
        } else {
            WorkspaceSnapshot.save(container: identifier,
                                   entries: all.map { (AppPaths.identifier(forURL: $0),
                                                       Self.signature(of: $0)) })
            observer.finishEnumerating(upTo: nil)                         // done
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from anchor: NSFileProviderSyncAnchor) {
        guard isWorkingSet || dirURL != nil else {
            observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
            return
        }
        // Fast path: nothing user-visible changed since the caller's anchor →
        // finish without reporting a single item. The app signals every ~1.2 s
        // during an active Python run; the old code re-reported EVERY child as
        // updated on EVERY pass, and files being actively written got a fresh
        // contentVersion each time — the sync engine ground away until iOS
        // backed the domain off ("Sync Paused" whenever the app was in use).
        let current = NSFileProviderSyncAnchor(WorkspaceSnapshot.anchor(container: identifier))
        if current.rawValue == anchor.rawValue {
            observer.finishEnumeratingChanges(upTo: current, moreComing: false)
            return
        }
        let all = childURLs()
        let previous = WorkspaceSnapshot.signatures(container: identifier)
        var currentEntries: [(id: String, sig: String)] = []
        currentEntries.reserveCapacity(all.count)
        // Only report items that are new or whose mtime/size actually changed —
        // never the volatile internals (live streams, logs), whose churn is
        // invisible to the user but re-syncs the world.
        var changed: [WorkspaceItem] = []
        for u in all {
            let id = AppPaths.identifier(forURL: u)
            let sig = Self.signature(of: u)
            currentEntries.append((id, sig))
            if Self.anchorVolatile.contains(u.lastPathComponent) { continue }
            if previous[id] != sig { changed.append(WorkspaceItem(url: u)) }
        }
        // Bounded batches so a big folder can't spike memory.
        var i = 0
        while i < changed.count {
            let end = min(i + Self.pageSize, changed.count)
            observer.didUpdate(Array(changed[i..<end]))
            i = end
        }
        let deleted = WorkspaceSnapshot.deletions(container: identifier,
                                                  current: currentEntries.map { $0.id })
        if !deleted.isEmpty {
            observer.didDeleteItems(withIdentifiers: deleted.map { NSFileProviderItemIdentifier($0) })
        }
        WorkspaceSnapshot.save(container: identifier, entries: currentEntries)
        observer.finishEnumeratingChanges(upTo: current, moreComing: false)
    }

    /// mtime+size signature — same derivation as `WorkspaceItem.itemVersion`,
    /// so "signature changed" ⇔ "the sync engine would see a new version".
    private static func signature(of url: URL) -> String {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return "\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)-\(v?.fileSize ?? 0)"
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(WorkspaceSnapshot.anchor(container: identifier)))
    }
}

/// App-Group-backed persistence so the enumerator can (a) emit a *content-based*
/// sync anchor that changes only when the relevant folder's direct children
/// change, and (b) detect deletions between change enumerations.
enum WorkspaceSnapshot {

    private static func key(_ container: NSFileProviderItemIdentifier) -> String {
        if container == .rootContainer { return "_root_" }
        if container == .workingSet    { return "_workingset_" }
        return container.rawValue
    }

    private static func storeURL(_ container: NSFileProviderItemIdentifier) -> URL? {
        guard let base = AppPaths.appGroupContainer else { return nil }
        let dir = base.appendingPathComponent(".fp_snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(key(container).replacingOccurrences(of: "/", with: "_") + ".txt")
    }

    /// One line per child: `id<TAB>mtime-size`. Old snapshots (id-only lines)
    /// still parse — their signature reads as "", so each item reports changed
    /// exactly once and the snapshot converges to the new format.
    static func save(container: NSFileProviderItemIdentifier, entries: [(id: String, sig: String)]) {
        guard let u = storeURL(container) else { return }
        let body = entries.sorted { $0.id < $1.id }
            .map { "\($0.id)\t\($0.sig)" }
            .joined(separator: "\n")
        try? Data(body.utf8).write(to: u)
    }

    /// `id → mtime-size` from the previous pass (empty sig for old-format lines).
    static func signatures(container: NSFileProviderItemIdentifier) -> [String: String] {
        guard let u = storeURL(container),
              let prev = try? String(contentsOf: u, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in prev.split(separator: "\n") {
            if let tab = line.firstIndex(of: "\t") {
                out[String(line[..<tab])] = String(line[line.index(after: tab)...])
            } else {
                out[String(line)] = ""
            }
        }
        return out
    }

    static func deletions(container: NSFileProviderItemIdentifier, current: [String]) -> [String] {
        let prevIds = Set(signatures(container: container).keys)
        return Array(prevIds.subtracting(current))
    }

    /// Cheap, content-based digest of the **direct children** of the relevant
    /// directory (the Workspace root for the working set). Shallow on purpose —
    /// equal content → equal bytes, so iOS only re-syncs on a real change and we
    /// never walk the whole tree.
    static func anchor(container: NSFileProviderItemIdentifier) -> Data {
        let dir: URL?
        if container == .workingSet {
            dir = AppPaths.fileProviderRootURL
        } else {
            let raw = container == .rootContainer ? AppPaths.rootIdentifier : container.rawValue
            dir = AppPaths.url(forIdentifier: raw)
        }
        guard let dir = dir,
              var entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: []) else {
            return Data("empty".utf8)
        }
        // Exclude the volatile internal entries from the hash at EVERY level so a
        // log/index/cache write — or the provider's own .fp_snapshots rewrite —
        // can't churn the anchor and re-trigger an endless sync ("Paused"). The
        // set spans both the container root (Library, .fp_snapshots, …) and the
        // Documents subfolder (log.txt, .symbol_index.json, …); none is hashed.
        entries = entries.filter { !WorkspaceEnumerator.anchorVolatile.contains($0.lastPathComponent) }
        let parts = entries.map { url -> String in
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(url.lastPathComponent):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(v?.fileSize ?? 0)"
        }.sorted()
        var h: UInt64 = 1469598103934665603                  // FNV-1a, deterministic
        for b in parts.joined(separator: "|").utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return withUnsafeBytes(of: h.littleEndian) { Data($0) }
    }
}
