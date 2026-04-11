import UIKit
import UniformTypeIdentifiers

// MARK: - Delegate Protocol

protocol FilesBrowserDelegate: AnyObject {
    func filesBrowser(_ controller: FilesBrowserViewController, didSelectCodeFile url: URL)
    func filesBrowser(_ controller: FilesBrowserViewController, didRequestLoadModel url: URL)
}

// MARK: - File Item Model

// Defined at file scope outside @MainActor to satisfy DiffableDataSource Sendable requirement
struct FileItem: @unchecked Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date
}

extension FileItem: Hashable {
    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

// MARK: - Sort Mode

private enum SortMode: Int, CaseIterable {
    case name = 0
    case date = 1
    case size = 2

    var title: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date"
        case .size: return "Size"
        }
    }
}

// MARK: - FilesBrowserViewController

final class FilesBrowserViewController: UIViewController {

    weak var delegate: FilesBrowserDelegate?

    // MARK: - Colors

    private let bgColor = UIColor(red: 0.118, green: 0.118, blue: 0.180, alpha: 1.0)       // #1e1e2e
    private let textColor = UIColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 1.0)      // #cdd6f4
    private let subtextColor = UIColor(red: 0.604, green: 0.639, blue: 0.757, alpha: 0.7)
    private let surfaceColor = UIColor(red: 0.157, green: 0.157, blue: 0.220, alpha: 1.0)   // #282838
    private let accentColor = UIColor(red: 0.537, green: 0.706, blue: 0.980, alpha: 1.0)    // #89b4fa

    // MARK: - State

    private var rootURL: URL!
    private var currentURL: URL!
    private var sortMode: SortMode = .name
    private var pathStack: [URL] = []

    // MARK: - UI

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var breadcrumbStack: UIStackView!
    private var breadcrumbScroll: UIScrollView!
    private var sortControl: UISegmentedControl!
    private var emptyLabel: UILabel!

    private let fileManager = FileManager.default
    private let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        rootURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        currentURL = rootURL
        pathStack = [rootURL]

        view.backgroundColor = bgColor
        title = "Files"

        setupNavigationBar()
        setupSortControl()
        setupBreadcrumbs()
        setupCollectionView()
        setupEmptyLabel()
        setupDataSource()
        reloadFiles()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bgColor
        appearance.titleTextAttributes = [.foregroundColor: textColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: textColor]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance

        let newMenu = UIMenu(title: "New", children: [
            UIAction(title: "New File", image: UIImage(systemName: "doc.badge.plus")) { [weak self] _ in
                self?.promptNewFile()
            },
            UIAction(title: "New Folder", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                self?.promptNewFolder()
            }
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            menu: newMenu
        )
        navigationItem.rightBarButtonItem?.tintColor = accentColor
    }

    private func setupSortControl() {
        sortControl = UISegmentedControl(items: SortMode.allCases.map { $0.title })
        sortControl.selectedSegmentIndex = sortMode.rawValue
        sortControl.translatesAutoresizingMaskIntoConstraints = false
        sortControl.selectedSegmentTintColor = accentColor
        sortControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        sortControl.setTitleTextAttributes([.foregroundColor: textColor], for: .normal)
        sortControl.backgroundColor = surfaceColor
        sortControl.addTarget(self, action: #selector(sortChanged(_:)), for: .valueChanged)
        view.addSubview(sortControl)

        NSLayoutConstraint.activate([
            sortControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            sortControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sortControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            sortControl.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setupBreadcrumbs() {
        breadcrumbScroll = UIScrollView()
        breadcrumbScroll.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbScroll.showsHorizontalScrollIndicator = false
        breadcrumbScroll.showsVerticalScrollIndicator = false
        view.addSubview(breadcrumbScroll)

        breadcrumbStack = UIStackView()
        breadcrumbStack.axis = .horizontal
        breadcrumbStack.spacing = 4
        breadcrumbStack.alignment = .center
        breadcrumbStack.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbScroll.addSubview(breadcrumbStack)

        NSLayoutConstraint.activate([
            breadcrumbScroll.topAnchor.constraint(equalTo: sortControl.bottomAnchor, constant: 8),
            breadcrumbScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            breadcrumbScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            breadcrumbScroll.heightAnchor.constraint(equalToConstant: 36),

            breadcrumbStack.topAnchor.constraint(equalTo: breadcrumbScroll.topAnchor),
            breadcrumbStack.leadingAnchor.constraint(equalTo: breadcrumbScroll.leadingAnchor),
            breadcrumbStack.trailingAnchor.constraint(equalTo: breadcrumbScroll.trailingAnchor),
            breadcrumbStack.bottomAnchor.constraint(equalTo: breadcrumbScroll.bottomAnchor),
            breadcrumbStack.heightAnchor.constraint(equalTo: breadcrumbScroll.heightAnchor)
        ])
    }

    private func setupCollectionView() {
        let config = UICollectionLayoutListConfiguration(appearance: .plain)
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = bgColor
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: breadcrumbScroll.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel = UILabel()
        emptyLabel.text = "This folder is empty"
        emptyLabel.textColor = subtextColor
        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor)
        ])
    }

    /// Lookup from String key (URL path) to FileItem
    private var itemLookup: [String: FileItem] = [:]

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> {
            [weak self] cell, _, key in
            guard let self, let item = self.itemLookup[key] else { return }

            var content = UIListContentConfiguration.subtitleCell()
            content.text = item.name
            content.textProperties.color = self.textColor
            content.textProperties.font = .systemFont(ofSize: 16, weight: .medium)

            if item.isDirectory {
                content.secondaryText = self.dateFormatter.string(from: item.modificationDate)
            } else {
                let sizeStr = self.sizeFormatter.string(fromByteCount: item.size)
                let dateStr = self.dateFormatter.string(from: item.modificationDate)
                content.secondaryText = "\(sizeStr)  \u{2022}  \(dateStr)"
            }
            content.secondaryTextProperties.color = self.subtextColor
            content.secondaryTextProperties.font = .systemFont(ofSize: 13)

            let (iconName, iconColor) = self.iconInfo(for: item)
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            content.image = UIImage(systemName: iconName, withConfiguration: iconConfig)
            content.imageProperties.tintColor = iconColor
            content.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 32)

            cell.contentConfiguration = content

            var bg = UIBackgroundConfiguration.listPlainCell()
            bg.backgroundColor = self.bgColor
            cell.backgroundConfiguration = bg

            cell.accessories = [.disclosureIndicator(options: .init(tintColor: item.isDirectory ? self.accentColor : self.subtextColor))]
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { (cv: UICollectionView, indexPath: IndexPath, key: String) -> UICollectionViewCell? in
            cv.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: key)
        }
    }

    // MARK: - File Operations

    private func loadItems(at url: URL) -> [FileItem] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { itemURL in
            guard let resources = try? itemURL.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            ) else { return nil }

            return FileItem(
                url: itemURL,
                name: itemURL.lastPathComponent,
                isDirectory: resources.isDirectory ?? false,
                size: Int64(resources.fileSize ?? 0),
                modificationDate: resources.contentModificationDate ?? Date.distantPast
            )
        }
    }

    private func sortedItems(_ items: [FileItem]) -> [FileItem] {
        let directories = items.filter { $0.isDirectory }
        let files = items.filter { !$0.isDirectory }

        let sortBlock: (FileItem, FileItem) -> Bool
        switch sortMode {
        case .name:
            sortBlock = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .date:
            sortBlock = { $0.modificationDate > $1.modificationDate }
        case .size:
            sortBlock = { $0.size > $1.size }
        }

        return directories.sorted(by: sortBlock) + files.sorted(by: sortBlock)
    }

    func refresh() {
        reloadFiles()
    }

    private func reloadFiles() {
        let items = sortedItems(loadItems(at: currentURL))
        emptyLabel.isHidden = !items.isEmpty

        // Build lookup
        itemLookup = [:]
        var keys: [String] = []
        for item in items {
            let key = item.url.path
            itemLookup[key] = item
            keys.append(key)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(keys, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)

        updateBreadcrumbs()
    }

    // MARK: - Navigation

    private func navigateTo(_ url: URL) {
        currentURL = url

        if let idx = pathStack.firstIndex(of: url) {
            pathStack = Array(pathStack.prefix(through: idx))
        } else {
            pathStack.append(url)
        }
        reloadFiles()
    }

    // MARK: - Breadcrumbs

    private func updateBreadcrumbs() {
        breadcrumbStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, url) in pathStack.enumerated() {
            if index > 0 {
                let chevron = UILabel()
                chevron.text = "\u{203A}"
                chevron.font = .systemFont(ofSize: 18, weight: .bold)
                chevron.textColor = subtextColor
                breadcrumbStack.addArrangedSubview(chevron)
            }

            let name = (url == rootURL) ? "Documents" : url.lastPathComponent
            let isLast = (index == pathStack.count - 1)

            let btn = UIButton(type: .system)
            btn.setTitle(name, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: isLast ? .bold : .regular)
            btn.setTitleColor(isLast ? textColor : accentColor, for: .normal)
            btn.tag = index
            btn.isEnabled = !isLast
            btn.addTarget(self, action: #selector(breadcrumbTapped(_:)), for: .touchUpInside)
            breadcrumbStack.addArrangedSubview(btn)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.breadcrumbScroll.contentSize.width > self.breadcrumbScroll.bounds.width else { return }
            let offset = CGPoint(
                x: self.breadcrumbScroll.contentSize.width - self.breadcrumbScroll.bounds.width,
                y: 0
            )
            self.breadcrumbScroll.setContentOffset(offset, animated: true)
        }
    }

    // MARK: - Icon Mapping

    private func iconInfo(for item: FileItem) -> (String, UIColor) {
        if item.isDirectory {
            return ("folder.fill", UIColor.systemBlue)
        }

        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "py":
            return ("doc.text", UIColor.systemBlue)
        case "c", "cpp", "h", "hpp":
            return ("doc.text", UIColor.systemOrange)
        case "f90", "f95", "f03":
            return ("doc.text", UIColor.systemGreen)
        case "gguf":
            return ("cpu", UIColor.systemPurple)
        case "png", "jpg", "jpeg", "gif", "bmp", "webp":
            return ("photo", UIColor.systemPink)
        case "txt", "md", "json", "xml", "csv":
            return ("doc.plaintext", UIColor.systemGray)
        default:
            return ("doc", UIColor.systemGray)
        }
    }

    // MARK: - Actions

    @objc private func sortChanged(_ sender: UISegmentedControl) {
        sortMode = SortMode(rawValue: sender.selectedSegmentIndex) ?? .name
        reloadFiles()
    }

    @objc private func breadcrumbTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx < pathStack.count else { return }
        navigateTo(pathStack[idx])
    }

    // MARK: - Create

    private func promptNewFile() {
        let alert = UIAlertController(title: "New File", message: "Enter the file name:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "example.py"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self, let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            let newURL = self.currentURL.appendingPathComponent(name)
            self.fileManager.createFile(atPath: newURL.path, contents: nil)
            self.reloadFiles()
        })
        present(alert, animated: true)
    }

    private func promptNewFolder() {
        let alert = UIAlertController(title: "New Folder", message: "Enter the folder name:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "MyFolder"
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self, let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            let newURL = self.currentURL.appendingPathComponent(name)
            try? self.fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)
            self.reloadFiles()
        })
        present(alert, animated: true)
    }

    // MARK: - Context Menu Helpers

    private func renameItem(_ item: FileItem) {
        let alert = UIAlertController(title: "Rename", message: "Enter the new name:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = item.name
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let self, let newName = alert.textFields?.first?.text, !newName.isEmpty else { return }
            let dest = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            try? self.fileManager.moveItem(at: item.url, to: dest)
            self.reloadFiles()
        })
        present(alert, animated: true)
    }

    private func duplicateItem(_ item: FileItem) {
        let ext = item.url.pathExtension
        let base = item.url.deletingPathExtension().lastPathComponent
        let parent = item.url.deletingLastPathComponent()
        var destName: String
        if ext.isEmpty {
            destName = "\(base) copy"
        } else {
            destName = "\(base) copy.\(ext)"
        }

        var dest = parent.appendingPathComponent(destName)
        var counter = 2
        while fileManager.fileExists(atPath: dest.path) {
            if ext.isEmpty {
                destName = "\(base) copy \(counter)"
            } else {
                destName = "\(base) copy \(counter).\(ext)"
            }
            dest = parent.appendingPathComponent(destName)
            counter += 1
        }

        try? fileManager.copyItem(at: item.url, to: dest)
        reloadFiles()
    }

    private func deleteItem(_ item: FileItem) {
        let alert = UIAlertController(
            title: "Delete \"\(item.name)\"?",
            message: item.isDirectory ? "This folder and its contents will be permanently deleted." : "This file will be permanently deleted.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            try? self?.fileManager.removeItem(at: item.url)
            self?.reloadFiles()
        })
        present(alert, animated: true)
    }

    // MARK: - GGUF Info Popover

    private func showModelInfo(for item: FileItem, at indexPath: IndexPath) {
        let sizeStr = sizeFormatter.string(fromByteCount: item.size)
        let dateStr = dateFormatter.string(from: item.modificationDate)

        let alert = UIAlertController(
            title: item.name,
            message: "Size: \(sizeStr)\nModified: \(dateStr)\nFormat: GGUF Model",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Load Model", style: .default) { [weak self] _ in
            guard let self else { return }
            self.delegate?.filesBrowser(self, didRequestLoadModel: item.url)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController,
           let cell = collectionView.cellForItem(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }

        present(alert, animated: true)
    }

    // MARK: - Code File Check

    private static let codeExtensions: Set<String> = ["py", "c", "cpp", "h", "hpp", "f90", "f95", "f03"]

    private func isCodeFile(_ url: URL) -> Bool {
        Self.codeExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - UICollectionViewDelegate

extension FilesBrowserViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let key = dataSource.itemIdentifier(for: indexPath),
              let item = itemLookup[key] else { return }

        if item.isDirectory {
            navigateTo(item.url)
            return
        }

        if item.url.pathExtension.lowercased() == "gguf" {
            showModelInfo(for: item, at: indexPath)
            return
        }

        if isCodeFile(item.url) {
            delegate?.filesBrowser(self, didSelectCodeFile: item.url)
            return
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let key = dataSource.itemIdentifier(for: indexPath),
              let item = itemLookup[key] else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            let rename = UIAction(
                title: "Rename",
                image: UIImage(systemName: "pencil")
            ) { _ in self.renameItem(item) }

            let duplicate = UIAction(
                title: "Duplicate",
                image: UIImage(systemName: "plus.square.on.square")
            ) { _ in self.duplicateItem(item) }

            let delete = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in self.deleteItem(item) }

            return UIMenu(children: [rename, duplicate, delete])
        }
    }
}
