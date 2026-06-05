import Foundation

/// Single source of truth for where the user's Workspace lives — shared by the
/// CodeBench app **and** the File Provider extension (add this file to BOTH
/// targets' membership).
///
/// ## Why this exists
/// A File Provider extension runs in its own process and can only serve files
/// from a **shared App Group container** — it cannot reach the app's private
/// `Documents/`. So to expose the Workspace as a top-level Files-app Location
/// (like iSH), the Workspace must live in the App Group container.
///
/// ## Safety: fallback by default
/// Everything here is gated on the App Group being *provisioned*. If the
/// `group.euleryu.CodeBench` entitlement isn't present (e.g. before you add the
/// capability in Xcode), `containerURL(forSecurityApplicationGroupIdentifier:)`
/// returns nil and we fall back to the historical `NSHomeDirectory()` — i.e.
/// the app behaves EXACTLY as it does today. Adopting the App Group is
/// therefore incremental and reversible: nothing changes until the entitlement
/// is live, at which point `migrateWorkspaceIfNeeded()` moves the existing
/// files across so the user's Workspace follows them into the Files Location.
///
/// ## How `~` and the Files Location line up
/// `~` (the process `HOME`) is the App Group **container** — the home that holds
/// both `Library` and `Documents`. The Python runtime and seeded scripts use
/// `~/Documents/Workspace`, `~/Documents/ToolOutputs`, etc. We set `HOME` to
/// `homeBase`, so `~` resolves into the shared container and
/// `~/Documents/Workspace` == `workspaceURL` automatically. The File Provider
/// Location is rooted at the same `~`, so `cd ~` in the shell and the Files app
/// both show the same two folders (`Library` + `Documents`).
public enum AppPaths {

    /// App Group identifier. Add this exact group to BOTH the app target and
    /// the File Provider extension target under Signing & Capabilities → App
    /// Groups. Must match the value in the .entitlements files.
    public static let appGroupID = "group.euleryu.CodeBench"

    /// The File Provider domain identifier (stable across launches).
    /// File Provider domain identifier. Bumped to a new generation when the
    /// Location's root layout changes, so the system rebuilds a clean replica
    /// instead of reconciling a stale one. Superseded ids are listed in
    /// `FileProviderRegistration.legacyDomainIDs` and removed on launch.
    public static let fileProviderDomainID = "CodeBenchDocs"

    /// The shared App Group container, or nil when the entitlement isn't
    /// present (capability not added yet / running an old build).
    public static var appGroupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// The base directory that `~` should resolve to. App Group container when
    /// available; the app's sandbox home otherwise (current behaviour).
    public static var homeBase: URL {
        appGroupContainer ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `homeBase/Documents` — kept named "Documents" so the long-standing
    /// `~/Documents/Workspace` convention (Python side, seeded scripts) still
    /// points at the right place after HOME is repointed at homeBase.
    public static var documentsURL: URL {
        homeBase.appendingPathComponent("Documents", isDirectory: true)
    }

    /// THE Workspace directory. Every Swift call site and the File Provider
    /// extension should use this instead of building `Documents/Workspace` by
    /// hand, so they all agree.
    public static var workspaceURL: URL {
        documentsURL.appendingPathComponent("Workspace", isDirectory: true)
    }

    /// Ensure the Workspace exists, returning it.
    @discardableResult
    public static func ensureWorkspace() -> URL {
        let ws = workspaceURL
        try? FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        return ws
    }

    /// True once the App Group is provisioned (i.e. the Location is possible).
    public static var appGroupAvailable: Bool { appGroupContainer != nil }

    // MARK: - Canonical sub-locations
    //
    // These centralise the dirs that used to be built ad-hoc from
    // `FileManager.urls(for:.documentDirectory)` (the *sandbox* Documents,
    // which the File Provider can't reach). Routing them through `homeBase`
    // puts them in the App Group when provisioned — so the Python side (HOME
    // is repointed here) and the Files-app Location agree.

    /// The directory the **File Provider domain is rooted at** — the App Group
    /// **container** (`homeBase`), i.e. the very same `~` the shell sees. The
    /// Files Location therefore shows the home's real top level: the `Library`
    /// and `Documents` folders. The user's files live one level in
    /// (`Documents/Workspace`, `Documents/ToolOutputs`, …), exactly as `cd ~`
    /// then `ls` shows in the terminal — terminal and Files app are identical.
    ///
    /// (An earlier build rooted this at `Documents` so the Location jumped
    /// straight to the user's files — but then the terminal's `~` (the
    /// container, holding `Library` + `Documents`) and the Files app disagreed.
    /// Rooting at the container keeps the two in lock-step.)
    public static var fileProviderRootURL: URL { homeBase }

    /// Rendered tool output (matplotlib / manim / plotly). A **sibling** of the
    /// Workspace under Documents — its own top-level folder in the Location,
    /// NOT nested inside Workspace. Chart detection keys off the `/ToolOutputs/`
    /// path substring, which still holds here.
    public static var toolOutputsURL: URL {
        documentsURL.appendingPathComponent("ToolOutputs", isDirectory: true)
    }

    /// Files opened from other apps. A **sibling** of the Workspace under
    /// Documents (its own top-level folder in the Location).
    public static var importedURL: URL {
        documentsURL.appendingPathComponent("Imported", isDirectory: true)
    }

    /// User `pip` installs. Under Documents in the App Group so this path equals
    /// `~/Documents/site-packages` (HOME is repointed) — exactly where pip
    /// injects its `--target`. Keeping PYTHONPATH, pip's target and Python's
    /// USER_SITE all equal here is what makes pip "suitable". (Hidden from the
    /// Location's *root* listing as internal infrastructure.)
    public static var userSitePackagesURL: URL {
        documentsURL.appendingPathComponent("site-packages", isDirectory: true)
    }

    // MARK: - Diagnostics

    /// Append a line to a shared debug log the app **and** the File Provider
    /// extension both write to, at `<App Group>/.fp_diag/fp_debug.log`. Read it
    /// from the CodeBench terminal with `cat ~/.fp_diag/fp_debug.log` (HOME is
    /// the App Group).
    ///
    /// CRITICAL: this lives at the App Group **root**, NOT under `Documents/` —
    /// because Documents is the File Provider's synced root. Writing a file
    /// inside it on every enumeration changes the sync-anchor hash, which makes
    /// the replicated engine re-enumerate forever → permanent "Paused". Keeping
    /// the log outside Documents breaks that loop.
    public static func fpLog(_ message: String) {
        let base = appGroupContainer ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent(".fp_diag", isDirectory: true)
        let url = dir.appendingPathComponent("fp_debug.log")
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = "[\(Date())] \(message)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Migration

    /// One-time, idempotent: when the App Group is newly available and still
    /// holds no Workspace, move the legacy sandbox `Documents/Workspace` into
    /// the shared container so the user's files follow them into the Files
    /// Location. Safe to call on every launch. No-op without the App Group.
    public static func migrateWorkspaceIfNeeded() {
        guard appGroupContainer != nil else { return }
        let fm = FileManager.default
        let sandboxDocs = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)

        // The user's working files.
        migrateTree(from: sandboxDocs.appendingPathComponent("Workspace", isDirectory: true),
                    to: workspaceURL, fm: fm)
        // pip-installed packages → App Group sibling of the Workspace, so they
        // stay importable now that PYTHONPATH + pip's --target both resolve here.
        migrateTree(from: sandboxDocs.appendingPathComponent("site-packages", isDirectory: true),
                    to: userSitePackagesURL, fm: fm)
        // Rendered outputs + imported files → App Group Documents, as SIBLINGS
        // of the Workspace (each its own top-level folder in the Location).
        // Migrate from the old sandbox path AND from inside the Workspace (an
        // earlier build briefly nested them there — undo that).
        migrateTree(from: sandboxDocs.appendingPathComponent("ToolOutputs", isDirectory: true), to: toolOutputsURL, fm: fm)
        migrateTree(from: workspaceURL.appendingPathComponent("ToolOutputs", isDirectory: true), to: toolOutputsURL, fm: fm)
        migrateTree(from: sandboxDocs.appendingPathComponent("Imported", isDirectory: true), to: importedURL, fm: fm)
        migrateTree(from: workspaceURL.appendingPathComponent("Imported", isDirectory: true), to: importedURL, fm: fm)

        // Make the structural folders exist so the Location shows a clean
        // multi-folder layout (Workspace · ToolOutputs · Imported) right away,
        // even before the user runs a render or imports a file.
        ensureWorkspace()
        try? fm.createDirectory(at: toolOutputsURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: importedURL, withIntermediateDirectories: true)
    }

    /// Move one legacy sandbox tree into its App Group home. Idempotent and
    /// loss-safe: a clean move when the destination is empty, else a merge of
    /// anything the destination is missing — and the legacy is deleted ONLY
    /// when every file made it across (otherwise the leftover lingers rather
    /// than risking data loss).
    private static func migrateTree(from legacy: URL, to shared: URL, fm: FileManager) {
        guard fm.fileExists(atPath: legacy.path) else { return }          // nothing to move
        if legacy.standardizedFileURL.path == shared.standardizedFileURL.path { return }
        try? fm.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)

        if !fm.fileExists(atPath: shared.path) {
            do {
                try fm.moveItem(at: legacy, to: shared)
            } catch {
                // Cross-container moves can fail → recursive copy, then remove
                // the legacy so it stops showing under "On My iPad".
                if (try? fm.copyItem(at: legacy, to: shared)) != nil {
                    try? fm.removeItem(at: legacy)
                }
            }
        } else if mergeMissing(from: legacy, into: shared, fm: fm) {
            try? fm.removeItem(at: legacy)
        }
    }

    /// Recursively copy anything in `src` that's absent from `dst` (used to
    /// fold a leftover legacy Workspace into the shared one before deleting it).
    /// Returns true only if every needed copy succeeded.
    @discardableResult
    private static func mergeMissing(from src: URL, into dst: URL, fm: FileManager) -> Bool {
        guard let items = try? fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return false }
        var ok = true
        for item in items {
            let target = dst.appendingPathComponent(item.lastPathComponent)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir == true {
                if fm.fileExists(atPath: target.path) {
                    ok = mergeMissing(from: item, into: target, fm: fm) && ok
                } else {
                    do { try fm.copyItem(at: item, to: target) } catch { ok = false }
                }
            } else if !fm.fileExists(atPath: target.path) {
                do { try fm.copyItem(at: item, to: target) } catch { ok = false }
            }
        }
        return ok
    }

    /// Repoint the process HOME at `homeBase` so `~/Documents/Workspace`
    /// resolves into the shared container. Call ONCE, before the Python
    /// runtime initialises. No-op (HOME stays the sandbox home) without the
    /// App Group, so existing behaviour is preserved.
    public static func exportHomeEnvironment() {
        guard appGroupAvailable else { return }
        setenv("HOME", homeBase.path, 1)
        // Keep CFFIXED_USER_HOME in sync so CoreFoundation agrees with libc.
        setenv("CFFIXED_USER_HOME", homeBase.path, 1)
    }

    // MARK: - File Provider identifier <-> URL mapping
    //
    // An item's identifier IS its path relative to `fileProviderRootURL` (the
    // App Group Documents). The root container is represented by
    // `rootIdentifier`. (Kept String-based so this file has no FileProvider
    // dependency and can live in the app target.)

    /// Sentinel the extension maps to `NSFileProviderItemIdentifier.rootContainer`.
    public static let rootIdentifier = "_codebench_root_"

    /// Resolve an item identifier to a URL under the File Provider root (nil if
    /// it would escape the root — path-traversal guard).
    public static func url(forIdentifier id: String) -> URL? {
        if id == rootIdentifier || id.isEmpty {
            return fileProviderRootURL
        }
        let candidate = fileProviderRootURL.appendingPathComponent(id).standardizedFileURL
        let root = fileProviderRootURL.standardizedFileURL.path
        guard candidate.path == root || candidate.path.hasPrefix(root + "/") else {
            return nil
        }
        return candidate
    }

    /// Map a URL under the File Provider root back to an item identifier.
    public static func identifier(forURL url: URL) -> String {
        let root = fileProviderRootURL.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        if p == root { return rootIdentifier }
        if p.hasPrefix(root + "/") { return String(p.dropFirst(root.count + 1)) }
        return p
    }
}
