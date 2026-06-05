# CodeBench File Provider — Files-app sidebar Location (like iSH)

This makes the CodeBench **Workspace** show up as a **top-level Location in the
Files app sidebar** (exactly like iSH), instead of only being reachable under
*On My iPad → BenchCode*.

All the code is written and **typechecked against the iOS 16 SDK**. What's left
is the Xcode wiring only *you* can do (adding a target + an App Group capability
both need your signing identity). Everything is gated on the App Group, so until
you finish these steps **nothing changes** — the app keeps using
`~/Documents/Workspace` exactly as today.

> **Where these files live:** `/Volumes/D/OfflinAi/FileProviderExt/` — a staging
> folder deliberately *outside* `CodeBench/`. The `CodeBench/` folder is a Xcode
> 16 *synchronized root group* (every file under it auto-compiles into the app
> target). These files `import FileProvider`, which the app target doesn't link,
> so putting them under `CodeBench/` would break the build. Add them to targets
> explicitly via Xcode (steps below).

Files in this folder:

| File | Goes in | Purpose |
|------|---------|---------|
| `AppPaths.swift` | **app + extension** | Single source of truth for the Workspace location (App Group, with fallback) |
| `FileProviderExtension.swift` | extension | The replicated File Provider extension |
| `WorkspaceItem.swift` | extension | `NSFileProviderItem` backed by a real file |
| `WorkspaceEnumerator.swift` | extension | Directory enumeration |
| `FileProviderRegistration.swift` | **app** | Registers the Location at launch (no-op without App Group) |
| `CodeBench.entitlements` | app (reference) | App Group entitlement |
| `FileProviderExt.entitlements` | extension (reference) | App Group entitlement |
| `FileProviderExt-Info.plist` | extension (reference) | `NSExtension` config |

---

## Step 1 — App Group on the app target
Project → **CodeBench** target → **Signing & Capabilities** → **+ Capability** →
**App Groups** → **+** → add exactly:

```
group.euleryu.CodeBench
```

## Step 2 — Add the File Provider Extension target
**File → New → Target… → File Provider Extension**. Name it `FileProviderExt`.
When prompted to activate the scheme, click **Activate**. (This safely creates
the target + its Info.plist + embeds it in the app — doing it by hand in
`project.pbxproj` is fragile, which is why it's a manual step.)

## Step 3 — Wire up the extension target
1. Delete the template's generated `FileProviderExtension.swift` (and any
   `FileProviderItem.swift`) — you'll use the ones here.
2. **Add to the extension target** (drag into Xcode, check *FileProviderExt* in
   the target-membership box): `FileProviderExtension.swift`, `WorkspaceItem.swift`,
   `WorkspaceEnumerator.swift`, **and `AppPaths.swift`**.
3. Extension → Signing & Capabilities → **App Groups** → add `group.euleryu.CodeBench`.
4. Extension → Info.plist → confirm it matches `FileProviderExt-Info.plist`
   (principal class `$(PRODUCT_MODULE_NAME).FileProviderExtension`, document
   group `group.euleryu.CodeBench`).

## Step 4 — Add the shared + app-side files to the **app** target
Add to the **CodeBench** target: `AppPaths.swift` (yes, it's in *both* targets)
and `FileProviderRegistration.swift`.

## Step 5 — Apply the integration patches (app target)
These switch the Workspace path to the shared helper. Each is safe because
`AppPaths.workspaceURL` falls back to the old `Documents/Workspace` until the
App Group is live.

**5a. Register the Location at launch.** In `AppDelegate` `didFinishLaunching…`
(or `SceneDelegate`), add:
```swift
FileProviderRegistration.registerIfPossible()
```

**5b. Repoint HOME so `~/Documents/Workspace` follows into the App Group.** In
`PythonRuntime.swift`, in the env-setup block (next to the other `setenv(...)`
calls, ~line 1218), add **before** Python initialises:
```swift
AppPaths.exportHomeEnvironment()   // no-op unless the App Group is provisioned
```

**5c. Replace each Workspace-path construction with `AppPaths.workspaceURL`:**

| File:line | Replace | With |
|-----------|---------|------|
| `FilesBrowserViewController.swift:115` | `let workspace = docs.appendingPathComponent("Workspace")` | `let workspace = AppPaths.workspaceURL` |
| `CodeEditorViewController.swift:3871` | `guard let workspace = docs?.appendingPathComponent("Workspace") else {` … `}` | `let workspace = AppPaths.workspaceURL` (delete the `guard`/`else`) |
| `GameViewController.swift:4732` | `let workspace = docs?.appendingPathComponent("Workspace")` | `let workspace: URL? = AppPaths.workspaceURL` |
| `GameViewController.swift:4750` | same as above | `let workspace: URL? = AppPaths.workspaceURL` |
| `GameViewController.swift:4774` | same as above | `let workspace: URL? = AppPaths.workspaceURL` |
| `GameViewController.swift:10055` | `FileManager.default.urls(for: .documentDirectory, …).first!`<br>`    .appendingPathComponent("Workspace", isDirectory: true)` | `AppPaths.workspaceURL` |
| `SettingsViewController.swift:1028` | `let workspace = "\(docs)/Workspace"` | `let workspace = AppPaths.workspaceURL.path` |
| `CommandPaletteViewController.swift:28` | `let docs = NSHomeDirectory() + "/Documents/Workspace/"` | `let docs = AppPaths.workspaceURL.path + "/"` |

(Keeping the `: URL?` annotations preserves the existing `workspace?…`
optional-chaining downstream, so nothing else needs editing.)

## Step 6 — Build, run, verify
1. Build + run on a real device (File Provider Locations don't surface under
   "Designed for iPad on Mac").
2. First launch migrates `Documents/Workspace` → the App Group automatically.
3. **Files app → sidebar** should now list **CodeBench** under *Locations*.
4. ✅ Test checklist (the relocation touches the Python side, so verify):
   - Editor opens/saves files in the Workspace.
   - Terminal: `pwd` / `ls ~/Documents/Workspace` shows your files.
   - `python` runs a script (and the Run button does too).
   - Create a file from the Files app → it appears in CodeBench, and vice-versa.

---

## Notes & troubleshooting
- **Nothing shows in the sidebar?** Confirm the App Group string matches in
  *both* targets and in `AppPaths.appGroupID`, and that
  `FileProviderRegistration.registerIfPossible()` runs (check the log for
  "registered as a Files Location").
- **Files double-up / wrong location?** A site in Step 5c was missed — every
  Workspace construction must go through `AppPaths.workspaceURL`.
- **Reverting:** remove the App Group capability; `AppPaths` falls back to
  `Documents/Workspace` and the app behaves exactly as before.
- The extension is **read-write**: create/rename/move/delete from Files map to
  filesystem ops on the shared Workspace.
