import UIKit

// MARK: - Data Structures

struct LibraryModule {
    let name: String
    let summary: String
    let importLine: String
    let items: [String]
    let example: String
    var language: String = "python"
}

struct LibrarySection {
    let name: String
    let icon: String
    let modules: [LibraryModule]
}

// MARK: - Delegate Protocol

protocol LibraryDocsDelegate: AnyObject {
    func libraryDocs(_ controller: LibraryDocsViewController, didRequestOpenCode code: String, language: String)
}

// MARK: - LibraryDocsViewController

final class LibraryDocsViewController: UIViewController {

    weak var delegate: LibraryDocsDelegate?
    var isCompactMode: Bool = false

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let searchBar = UISearchBar()
    private var allSections: [LibrarySection] = []
    private var filteredSections: [LibrarySection] = []
    private var expandedSections: Set<Int> = []

    private let bgColor = UIColor(red: 30/255, green: 30/255, blue: 46/255, alpha: 1)
    private let textColor = UIColor(red: 205/255, green: 214/255, blue: 244/255, alpha: 1)
    private let accentColor = UIColor(red: 137/255, green: 180/255, blue: 250/255, alpha: 1)
    private let surfaceColor = UIColor(red: 49/255, green: 50/255, blue: 68/255, alpha: 1)
    private let dimTextColor = UIColor(red: 147/255, green: 153/255, blue: 178/255, alpha: 1)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        allSections = Self.buildAllSections()
        filteredSections = allSections
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let sel = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: sel, animated: true)
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = bgColor
        title = "Library Docs"

        searchBar.placeholder = "Search libraries, modules, functions..."
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.barTintColor = bgColor
        searchBar.tintColor = accentColor
        if let tf = searchBar.searchTextField as UITextField? {
            tf.textColor = textColor
            tf.attributedPlaceholder = NSAttributedString(
                string: "Search libraries, modules, functions...",
                attributes: [.foregroundColor: dimTextColor]
            )
            tf.backgroundColor = surfaceColor
        }

        tableView.backgroundColor = bgColor
        tableView.separatorColor = surfaceColor.withAlphaComponent(0.5)
        tableView.indicatorStyle = .white
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ModuleCell.self, forCellReuseIdentifier: ModuleCell.id)
        tableView.register(SectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderView.id)
        tableView.sectionFooterHeight = 0
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .onDrag

        // Hero header with stats
        let headerView = buildHeroHeader()

        let stack = UIStackView(arrangedSubviews: [headerView, searchBar, tableView])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildHeroHeader() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: isCompactMode ? 0 : 110).isActive = true
        if isCompactMode { container.isHidden = true; return container }

        // Gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.14, green: 0.16, blue: 0.28, alpha: 1.0).cgColor,
            bgColor.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        container.layer.insertSublayer(gradientLayer, at: 0)
        container.clipsToBounds = true

        // Auto-resize gradient
        DispatchQueue.main.async { gradientLayer.frame = container.bounds }
        let observer = container // Will layout sublayers on bounds change

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Offline Library Reference"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = textColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.text = "All libraries run locally on-device. No internet required."
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = dimTextColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Stats row
        let totalModules = allSections.reduce(0) { $0 + $1.modules.count }
        let totalItems = allSections.flatMap(\.modules).reduce(0) { $0 + $1.items.count }
        let statsStack = UIStackView()
        statsStack.axis = .horizontal
        statsStack.spacing = 20
        statsStack.translatesAutoresizingMaskIntoConstraints = false

        func statBadge(value: String, label: String, color: UIColor) -> UIView {
            let v = UIView()
            let valLbl = UILabel()
            valLbl.text = value
            valLbl.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
            valLbl.textColor = color
            let lblLbl = UILabel()
            lblLbl.text = label
            lblLbl.font = .systemFont(ofSize: 10, weight: .medium)
            lblLbl.textColor = dimTextColor
            let stack = UIStackView(arrangedSubviews: [valLbl, lblLbl])
            stack.axis = .vertical; stack.alignment = .center; stack.spacing = 1
            stack.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
                stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
                stack.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6),
            ])
            v.backgroundColor = color.withAlphaComponent(0.1)
            v.layer.cornerRadius = 8
            return v
        }

        statsStack.addArrangedSubview(statBadge(value: "\(allSections.count)", label: "Libraries", color: accentColor))
        statsStack.addArrangedSubview(statBadge(value: "\(totalModules)", label: "Modules", color: UIColor.systemGreen))
        statsStack.addArrangedSubview(statBadge(value: "\(totalItems)+", label: "APIs", color: UIColor.systemOrange))
        statsStack.addArrangedSubview(statBadge(value: "4", label: "Languages", color: UIColor.systemPurple))

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(statsStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            statsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),
            statsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        ])

        return container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update gradient layer frames
        for sub in view.subviews {
            for v in sub.subviews {
                if let gradient = v.layer.sublayers?.first as? CAGradientLayer {
                    gradient.frame = v.bounds
                }
            }
        }
    }

    // MARK: - Filtering

    private func applyFilter(_ query: String) {
        guard !query.isEmpty else { filteredSections = allSections; tableView.reloadData(); return }
        let q = query.lowercased()
        filteredSections = allSections.compactMap { section in
            let nameMatch = section.name.lowercased().contains(q)
            let matched = section.modules.filter {
                nameMatch || $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q)
                || $0.items.contains(where: { $0.lowercased().contains(q) })
            }
            guard !matched.isEmpty else { return nil }
            return LibrarySection(name: section.name, icon: section.icon, modules: matched)
        }
        expandedSections = Set(0..<filteredSections.count)
        tableView.reloadData()
    }
}

// MARK: - UISearchBarDelegate

extension LibraryDocsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter(searchText)
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource & Delegate

extension LibraryDocsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { filteredSections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        expandedSections.contains(section) ? filteredSections[section].modules.count : 0
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderView.id) as? SectionHeaderView else { return nil }
        let s = filteredSections[section]
        let expanded = expandedSections.contains(section)
        header.configure(title: s.name, icon: s.icon, moduleCount: s.modules.count, expanded: expanded,
                         bgColor: bgColor, textColor: textColor, accentColor: accentColor, dimColor: dimTextColor)
        header.onTap = { [weak self] in self?.toggleSection(section) }
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 52 }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 4 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ModuleCell.id, for: indexPath) as! ModuleCell
        let mod = filteredSections[indexPath.section].modules[indexPath.row]
        cell.configure(module: mod, bgColor: bgColor, surfaceColor: surfaceColor,
                       textColor: textColor, dimColor: dimTextColor, accentColor: accentColor)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = filteredSections[indexPath.section]
        let mod = section.modules[indexPath.row]
        let detail = ModuleDetailViewController(
            module: mod, libraryName: section.name,
            bgColor: bgColor, surfaceColor: surfaceColor,
            textColor: textColor, dimColor: dimTextColor, accentColor: accentColor
        )
        detail.onOpenInEditor = { [weak self] code, lang in
            guard let self else { return }
            self.delegate?.libraryDocs(self, didRequestOpenCode: code, language: lang)
        }
        if isCompactMode {
            let nav = UINavigationController(rootViewController: detail)
            nav.modalPresentationStyle = .popover
            nav.preferredContentSize = CGSize(width: 500, height: 600)
            if let popover = nav.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = .any
            }
            present(nav, animated: true)
        } else {
            navigationController?.pushViewController(detail, animated: true)
        }
    }

    private func toggleSection(_ section: Int) {
        let wasExpanded = expandedSections.contains(section)
        if wasExpanded { expandedSections.remove(section) } else { expandedSections.insert(section) }
        let count = filteredSections[section].modules.count
        let paths = (0..<count).map { IndexPath(row: $0, section: section) }
        tableView.beginUpdates()
        if wasExpanded { tableView.deleteRows(at: paths, with: .fade) }
        else { tableView.insertRows(at: paths, with: .fade) }
        tableView.endUpdates()
        if let header = tableView.headerView(forSection: section) as? SectionHeaderView {
            header.setExpanded(!wasExpanded, animated: true)
        }
    }
}

// MARK: - Section Header View

private final class SectionHeaderView: UITableViewHeaderFooterView {
    static let id = "SectionHeaderView"
    var onTap: (() -> Void)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let chevron = UIImageView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        contentView.addGestureRecognizer(tap)

        for v: UIView in [iconView, titleLabel, countLabel, chevron] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        chevron.contentMode = .scaleAspectFit
        iconView.contentMode = .scaleAspectFit

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, icon: String, moduleCount: Int, expanded: Bool,
                   bgColor: UIColor, textColor: UIColor, accentColor: UIColor, dimColor: UIColor) {
        contentView.backgroundColor = bgColor
        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = accentColor
        titleLabel.text = title
        titleLabel.textColor = textColor
        countLabel.text = "\(moduleCount)"
        countLabel.textColor = dimColor
        let chevName = expanded ? "chevron.down" : "chevron.right"
        chevron.image = UIImage(systemName: chevName)
        chevron.tintColor = dimColor
        chevron.transform = .identity
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        let img = UIImage(systemName: expanded ? "chevron.down" : "chevron.right")
        if animated {
            UIView.animate(withDuration: 0.25) { self.chevron.image = img }
        } else {
            chevron.image = img
        }
    }

    @objc private func tapped() { onTap?() }
}

// MARK: - Module Cell

private final class ModuleCell: UITableViewCell {
    static let id = "ModuleCell"
    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        let stack = UIStackView(arrangedSubviews: [nameLabel, summaryLabel])
        stack.axis = .vertical; stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 50),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        nameLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.numberOfLines = 2
        accessoryType = .disclosureIndicator
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(module: LibraryModule, bgColor: UIColor, surfaceColor: UIColor,
                   textColor: UIColor, dimColor: UIColor, accentColor: UIColor) {
        backgroundColor = bgColor
        contentView.backgroundColor = bgColor
        nameLabel.text = module.name
        nameLabel.textColor = accentColor
        summaryLabel.text = module.summary
        summaryLabel.textColor = dimColor
        tintColor = dimColor
    }
}

// MARK: - Module Detail View Controller

final class ModuleDetailViewController: UIViewController {

    private let module: LibraryModule
    private let libraryName: String
    private let bgColor, surfaceColor, textColor, dimColor, accentColor: UIColor
    var onOpenInEditor: ((String, String) -> Void)?

    init(module: LibraryModule, libraryName: String,
         bgColor: UIColor, surfaceColor: UIColor,
         textColor: UIColor, dimColor: UIColor, accentColor: UIColor) {
        self.module = module; self.libraryName = libraryName
        self.bgColor = bgColor; self.surfaceColor = surfaceColor
        self.textColor = textColor; self.dimColor = dimColor; self.accentColor = accentColor
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bgColor
        title = "\(libraryName).\(module.name)"
        buildContent()
    }

    private func buildContent() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let container = UIStackView()
        container.axis = .vertical; container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -20),
            container.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40)
        ])

        // Import line
        let importBox = makeCodeBox(module.importLine)
        container.addArrangedSubview(importBox)

        // Summary
        let summaryLabel = UILabel()
        summaryLabel.text = module.summary
        summaryLabel.textColor = textColor
        summaryLabel.font = .systemFont(ofSize: 15)
        summaryLabel.numberOfLines = 0
        container.addArrangedSubview(summaryLabel)

        // Key items header
        let itemsHeader = UILabel()
        itemsHeader.text = "Key Classes & Functions"
        itemsHeader.textColor = accentColor
        itemsHeader.font = .systemFont(ofSize: 14, weight: .bold)
        container.addArrangedSubview(itemsHeader)

        // Items list
        let itemsStack = UIStackView()
        itemsStack.axis = .vertical; itemsStack.spacing = 4
        for item in module.items {
            let lbl = UILabel()
            lbl.text = "  \(item)"
            lbl.textColor = textColor
            lbl.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            itemsStack.addArrangedSubview(lbl)
        }
        container.addArrangedSubview(itemsStack)

        // Example header
        let exHeader = UILabel()
        exHeader.text = "Example"
        exHeader.textColor = accentColor
        exHeader.font = .systemFont(ofSize: 14, weight: .bold)
        container.addArrangedSubview(exHeader)

        // Example code
        let codeBox = makeCodeBox(module.example)
        container.addArrangedSubview(codeBox)

        // Buttons
        let btnStack = UIStackView()
        btnStack.axis = .horizontal; btnStack.spacing = 12; btnStack.distribution = .fillEqually
        let copyBtn = makeButton(title: "Copy Example", icon: "doc.on.doc")
        copyBtn.addTarget(self, action: #selector(copyExample), for: .touchUpInside)
        let openBtn = makeButton(title: "Open in Editor", icon: "chevron.left.forwardslash.chevron.right")
        openBtn.addTarget(self, action: #selector(openInEditor), for: .touchUpInside)
        btnStack.addArrangedSubview(copyBtn)
        btnStack.addArrangedSubview(openBtn)
        container.addArrangedSubview(btnStack)
    }

    private func makeCodeBox(_ code: String) -> UIView {
        let box = UIView()
        box.backgroundColor = surfaceColor
        box.layer.cornerRadius = 8
        let lbl = UILabel()
        lbl.text = code
        lbl.textColor = textColor
        lbl.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            lbl.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            lbl.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            lbl.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)
        ])
        return box
    }

    private func makeButton(title: String, icon: String) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 6
        cfg.baseBackgroundColor = accentColor.withAlphaComponent(0.2)
        cfg.baseForegroundColor = accentColor
        cfg.cornerStyle = .medium
        return UIButton(configuration: cfg)
    }

    @objc private func copyExample() {
        UIPasteboard.general.string = module.example
        let alert = UIAlertController(title: "Copied", message: "Example code copied to clipboard.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func openInEditor() {
        onOpenInEditor?(module.example, module.language)
        if navigationController != nil { navigationController?.popViewController(animated: true) }
        else { dismiss(animated: true) }
    }
}

// MARK: - Documentation Data

extension LibraryDocsViewController {

    static func buildAllSections() -> [LibrarySection] {
        return [
            numpySection, scipySection, sklearnSection, matplotlibSection,
            sympySection, networkxSection, pilSection, manimSection,
            mediaSection, webSection,
            cSection, cppSection, fortranSection, otherSection
        ]
    }

    // MARK: NumPy
    private static var numpySection: LibrarySection {
        LibrarySection(name: "numpy", icon: "function", modules: [
            LibraryModule(name: "array creation", summary: "Functions for creating arrays of all shapes and types",
                importLine: "import numpy as np",
                items: ["np.array", "np.zeros", "np.ones", "np.empty", "np.full", "np.zeros_like", "np.ones_like", "np.empty_like", "np.full_like", "np.arange", "np.linspace", "np.logspace", "np.geomspace", "np.eye", "np.identity", "np.diag", "np.meshgrid", "np.mgrid", "np.ogrid", "np.fromfunction", "np.fromiter", "np.frombuffer", "np.tile", "np.repeat", "np.tri", "np.tril", "np.triu", "np.vander"],
                example: "import numpy as np\nA = np.eye(3)            # 3x3 identity\nb = np.linspace(0, 1, 5) # [0, 0.25, 0.5, 0.75, 1]\nX, Y = np.meshgrid(b, b) # 5x5 coordinate grids\nprint('A shape:', A.shape, 'grid shape:', X.shape)"),
            LibraryModule(name: "array manipulation", summary: "Reshape, join, split, transpose, flip, pad arrays",
                importLine: "import numpy as np",
                items: ["np.reshape", "np.ravel", "flatten", "np.transpose", "np.swapaxes", "np.moveaxis", "np.expand_dims", "np.squeeze", "np.concatenate", "np.stack", "np.vstack", "np.hstack", "np.dstack", "np.column_stack", "np.split", "np.hsplit", "np.vsplit", "np.dsplit", "np.flip", "np.fliplr", "np.flipud", "np.rot90", "np.roll", "np.pad", "np.insert", "np.append", "np.delete", "np.unique"],
                example: "import numpy as np\na = np.arange(12).reshape(3, 4)\nprint('Original:', a.shape)\nprint('Transposed:', a.T.shape)\nprint('Flattened:', a.ravel().shape)\nb = np.flip(a, axis=1)\nprint('Flipped:', b)"),
            LibraryModule(name: "math functions", summary: "Element-wise arithmetic, trig, exponential, rounding",
                importLine: "import numpy as np",
                items: ["np.add", "np.subtract", "np.multiply", "np.divide", "np.power", "np.mod", "np.abs", "np.sqrt", "np.cbrt", "np.square", "np.exp", "np.exp2", "np.expm1", "np.log", "np.log2", "np.log10", "np.log1p", "np.maximum", "np.minimum", "np.clip", "np.round", "np.floor", "np.ceil", "np.trunc", "np.rint", "np.sign", "np.reciprocal", "np.negative", "np.sin", "np.cos", "np.tan", "np.arcsin", "np.arccos", "np.arctan", "np.arctan2", "np.sinh", "np.cosh", "np.tanh", "np.degrees", "np.radians", "np.hypot", "np.unwrap"],
                example: "import numpy as np\nx = np.linspace(0, 2*np.pi, 100)\nprint('sin range:', np.sin(x).min(), np.sin(x).max())\nprint('exp(0):', np.exp(0), 'log(e):', np.log(np.e))\nprint('clip:', np.clip([-2, 0.5, 3], 0, 1))"),
            LibraryModule(name: "aggregation", summary: "Sum, mean, std, min/max, histogram, correlation",
                importLine: "import numpy as np",
                items: ["np.sum", "np.prod", "np.cumsum", "np.cumprod", "np.diff", "np.gradient", "np.mean", "np.median", "np.average", "np.std", "np.var", "np.min", "np.max", "np.argmin", "np.argmax", "np.ptp", "np.percentile", "np.quantile", "np.nanmean", "np.nanstd", "np.nansum", "np.histogram", "np.histogram2d", "np.histogramdd", "np.bincount", "np.digitize", "np.corrcoef", "np.cov"],
                example: "import numpy as np\ndata = np.random.randn(1000)\nprint('Mean:', np.mean(data))\nprint('Std:', np.std(data))\nprint('Percentiles:', np.percentile(data, [25, 50, 75]))\nhist, edges = np.histogram(data, bins=20)"),
            LibraryModule(name: "linalg", summary: "Linear algebra: solve, decompose, eigenvalues, norms",
                importLine: "from numpy.linalg import solve, inv, eig, svd",
                items: ["np.dot", "np.matmul", "np.inner", "np.outer", "np.cross", "np.tensordot", "np.einsum", "np.linalg.solve", "np.linalg.inv", "np.linalg.det", "np.linalg.eig", "np.linalg.eigvals", "np.linalg.eigh", "np.linalg.eigvalsh", "np.linalg.svd", "np.linalg.norm", "np.linalg.qr", "np.linalg.cholesky", "np.linalg.lstsq", "np.linalg.matrix_rank", "np.linalg.matrix_power", "np.linalg.pinv", "np.linalg.cond", "np.linalg.slogdet", "np.linalg.multi_dot", "np.trace"],
                example: "import numpy as np\nA = np.array([[3, 2, -1], [2, -2, 4], [-1, 0.5, -1]])\nb = np.array([1, -2, 0])\nx = np.linalg.solve(A, b)\nprint('Solution:', x)\nvals, vecs = np.linalg.eig(A)\nprint('Eigenvalues:', vals)"),
            LibraryModule(name: "fft", summary: "Fast Fourier transforms: 1D, 2D, N-D, real, frequencies",
                importLine: "from numpy.fft import fft, ifft, fftfreq",
                items: ["np.fft.fft", "np.fft.ifft", "np.fft.rfft", "np.fft.irfft", "np.fft.fft2", "np.fft.ifft2", "np.fft.fftn", "np.fft.ifftn", "np.fft.fftfreq", "np.fft.rfftfreq", "np.fft.fftshift", "np.fft.ifftshift"],
                example: "import numpy as np\nt = np.linspace(0, 1, 256)\nsig = np.sin(2*np.pi*10*t) + np.sin(2*np.pi*20*t)\nF = np.fft.fft(sig)\nfreqs = np.fft.fftfreq(len(t), t[1]-t[0])\nprint('Dominant freq:', freqs[np.argmax(np.abs(F[1:]))+1])"),
            LibraryModule(name: "random", summary: "Random number generation: legacy API and Generator API",
                importLine: "from numpy.random import default_rng",
                items: ["np.random.default_rng", "rng.random", "rng.standard_normal", "rng.integers", "rng.choice", "rng.shuffle", "rng.normal", "rng.uniform", "np.random.rand", "np.random.randn", "np.random.randint", "np.random.choice", "np.random.shuffle", "np.random.permutation", "np.random.seed", "np.random.normal", "np.random.uniform", "np.random.binomial", "np.random.poisson", "np.random.exponential", "np.random.beta", "np.random.gamma", "np.random.multivariate_normal"],
                example: "import numpy as np\nrng = np.random.default_rng(42)\nsamples = rng.normal(loc=0, scale=1, size=1000)\nprint('Mean:', samples.mean(), 'Std:', samples.std())\nchoices = rng.choice([10, 20, 30], size=5)\nprint('Choices:', choices)"),
            LibraryModule(name: "polynomial", summary: "Polynomial fitting, evaluation, roots, and special polynomials",
                importLine: "from numpy.polynomial import polynomial as P",
                items: ["np.polyfit", "np.polyval", "np.poly1d", "np.roots", "np.polyadd", "np.polymul", "np.polyder", "np.polyint", "np.polynomial.polynomial.Polynomial", "np.polynomial.chebyshev.Chebyshev", "np.polynomial.legendre.Legendre", "np.polynomial.hermite.Hermite", "np.polynomial.laguerre.Laguerre"],
                example: "import numpy as np\nx = np.linspace(0, 1, 20)\ny = np.sin(2*np.pi*x)\ncoeffs = np.polyfit(x, y, 5)\np = np.poly1d(coeffs)\nprint('Roots:', np.roots(coeffs))\nprint('Fit at 0.5:', p(0.5))"),
            LibraryModule(name: "sorting & searching", summary: "Sort, search, partition, and conditional selection",
                importLine: "import numpy as np",
                items: ["np.sort", "np.argsort", "np.lexsort", "np.partition", "np.argpartition", "np.searchsorted", "np.where", "np.nonzero", "np.argwhere", "np.extract", "np.count_nonzero"],
                example: "import numpy as np\narr = np.array([3, 1, 4, 1, 5, 9, 2, 6])\nprint('Sorted:', np.sort(arr))\nprint('Indices:', np.argsort(arr))\nprint('Where >4:', np.where(arr > 4))"),
            LibraryModule(name: "logic & sets", summary: "Boolean tests, comparisons, set operations",
                importLine: "import numpy as np",
                items: ["np.all", "np.any", "np.isnan", "np.isinf", "np.isfinite", "np.isclose", "np.allclose", "np.array_equal", "np.logical_and", "np.logical_or", "np.logical_not", "np.logical_xor", "np.intersect1d", "np.union1d", "np.setdiff1d", "np.setxor1d", "np.in1d", "np.isin"],
                example: "import numpy as np\na = np.array([1, 2, 3, 4, 5])\nb = np.array([3, 4, 5, 6, 7])\nprint('Intersection:', np.intersect1d(a, b))\nprint('Union:', np.union1d(a, b))\nprint('Any >3:', np.any(a > 3))")
        ])
    }

    // MARK: SciPy
    private static var scipySection: LibrarySection {
        LibrarySection(name: "scipy", icon: "waveform.path.ecg", modules: [
            LibraryModule(name: "optimize", summary: "Minimization, root finding, curve fitting, linear programming",
                importLine: "from scipy.optimize import minimize, curve_fit, root, linprog",
                items: ["minimize", "minimize_scalar", "curve_fit", "root", "root_scalar", "brentq", "bisect", "newton", "fsolve", "linprog", "milp", "least_squares", "differential_evolution", "dual_annealing", "shgo", "basinhopping", "OptimizeResult", "LinearConstraint", "NonlinearConstraint", "Bounds"],
                example: "from scipy.optimize import minimize, curve_fit\nimport numpy as np\n# Minimization\nres = minimize(lambda x: (x[0]-1)**2 + (x[1]-2)**2, [0, 0], method='Nelder-Mead')\nprint('Min at:', res.x)\n# Curve fitting\nxd = np.linspace(0, 5, 50)\nyd = 2.5 * np.sin(1.5 * xd) + np.random.normal(0, 0.3, 50)\npopt, pcov = curve_fit(lambda x, a, b: a*np.sin(b*x), xd, yd, p0=[1,1])\nprint('Fit params:', popt)"),
            LibraryModule(name: "integrate", summary: "Numerical integration and ODE/IVP solvers",
                importLine: "from scipy.integrate import quad, solve_ivp, dblquad",
                items: ["quad", "dblquad", "tplquad", "nquad", "fixed_quad", "quadrature", "trapezoid", "simpson", "cumulative_trapezoid", "solve_ivp", "odeint", "OdeSolver", "OdeResult"],
                example: "from scipy.integrate import quad, solve_ivp\nimport numpy as np\n# Definite integral\nresult, err = quad(np.sin, 0, np.pi)\nprint('Integral of sin(0..pi):', result)\n# ODE: dy/dt = -2y, y(0)=1\nsol = solve_ivp(lambda t, y: -2*y, [0, 3], [1], t_eval=np.linspace(0, 3, 10))\nprint('y(3) ~=', sol.y[0, -1])"),
            LibraryModule(name: "stats (distributions)", summary: "Continuous and discrete probability distributions",
                importLine: "from scipy import stats",
                items: ["norm", "t", "chi2", "f", "uniform", "expon", "gamma", "beta", "lognorm", "weibull_min", "pareto", "cauchy", "laplace", "rayleigh", "binom", "poisson", "geom", "nbinom", "hypergeom", "bernoulli", "randint", "zipf"],
                example: "from scipy import stats\nimport numpy as np\n# Normal distribution\ndata = stats.norm.rvs(loc=5, scale=2, size=1000, random_state=42)\nprint('Mean:', np.mean(data), 'Std:', np.std(data))\n# Fit distribution\nmu, sigma = stats.norm.fit(data)\nprint('Fitted: mu=%.2f sigma=%.2f' % (mu, sigma))"),
            LibraryModule(name: "stats (tests)", summary: "Hypothesis tests: t-test, ANOVA, chi-squared, normality",
                importLine: "from scipy.stats import ttest_ind, pearsonr, kstest",
                items: ["ttest_ind", "ttest_1samp", "ttest_rel", "pearsonr", "spearmanr", "kendalltau", "kstest", "ks_2samp", "mannwhitneyu", "wilcoxon", "kruskal", "friedmanchisquare", "chi2_contingency", "fisher_exact", "shapiro", "normaltest", "anderson", "levene", "bartlett", "f_oneway", "describe", "mode", "zscore", "iqr", "sem", "trim_mean", "entropy", "differential_entropy", "linregress"],
                example: "from scipy import stats\nimport numpy as np\na = np.random.normal(5, 1, 100)\nb = np.random.normal(5.5, 1, 100)\nt_stat, p_val = stats.ttest_ind(a, b)\nprint(f't={t_stat:.3f}, p={p_val:.4f}')\nslope, intercept, r, p, se = stats.linregress(a, b)\nprint(f'r={r:.3f}')"),
            LibraryModule(name: "interpolate", summary: "1D, 2D, and N-D interpolation: splines, RBF, griddata",
                importLine: "from scipy.interpolate import CubicSpline, interp1d, griddata",
                items: ["interp1d", "CubicSpline", "UnivariateSpline", "InterpolatedUnivariateSpline", "PchipInterpolator", "Akima1DInterpolator", "BarycentricInterpolator", "KroghInterpolator", "make_interp_spline", "griddata", "RectBivariateSpline", "bisplrep", "bisplev", "BSpline", "PPoly", "RegularGridInterpolator", "LinearNDInterpolator", "NearestNDInterpolator", "CloughTocher2DInterpolator", "RBFInterpolator"],
                example: "from scipy.interpolate import CubicSpline, griddata\nimport numpy as np\n# 1D spline\nx = np.arange(10)\ny = np.sin(x)\ncs = CubicSpline(x, y)\nprint('Spline at 0.5:', cs(0.5))\n# 2D griddata\npts = np.random.rand(100, 2)\nvals = np.sin(pts[:,0]) * np.cos(pts[:,1])\nxi = np.linspace(0, 1, 20)\nXi, Yi = np.meshgrid(xi, xi)"),
            LibraryModule(name: "linalg", summary: "Full linear algebra: decompositions, matrix functions, solvers",
                importLine: "from scipy.linalg import solve, lu, expm, svd, schur",
                items: ["solve", "solve_triangular", "solve_banded", "inv", "det", "norm", "eig", "eigvals", "eigh", "eigvalsh", "svd", "svdvals", "lu", "lu_factor", "lu_solve", "cholesky", "cho_factor", "cho_solve", "qr", "schur", "hessenberg", "expm", "logm", "sqrtm", "funm", "pinv", "lstsq", "null_space", "orth", "block_diag", "toeplitz", "hankel", "hadamard", "hilbert", "invhilbert", "pascal", "kron"],
                example: "from scipy.linalg import lu, expm, solve\nimport numpy as np\nA = np.array([[1, 2], [3, 4]])\n# LU decomposition\nP, L, U = lu(A)\nprint('L:\\n', L, '\\nU:\\n', U)\n# Matrix exponential\nprint('expm(A):\\n', expm(A))"),
            LibraryModule(name: "fft", summary: "FFT, DCT, DST with multiple backends and N-D support",
                importLine: "from scipy.fft import fft, dct, dst, fftfreq",
                items: ["fft", "ifft", "rfft", "irfft", "fft2", "ifft2", "fftn", "ifftn", "rfft2", "rfftn", "dct", "idct", "dst", "idst", "fftfreq", "rfftfreq", "fftshift", "ifftshift", "next_fast_len"],
                example: "from scipy.fft import fft, dct, fftfreq\nimport numpy as np\n# FFT\nsig = np.sin(2*np.pi*10*np.linspace(0, 1, 256))\nF = fft(sig)\nfreqs = fftfreq(256, 1/256)\n# DCT\ncoeffs = dct(sig, type=2)\nprint('DCT coeffs shape:', coeffs.shape)"),
            LibraryModule(name: "signal", summary: "Signal processing: filter design, spectral analysis, peak finding",
                importLine: "from scipy.signal import butter, filtfilt, find_peaks, spectrogram",
                items: ["butter", "cheby1", "cheby2", "ellip", "bessel", "iirfilter", "firwin", "firwin2", "filtfilt", "sosfilt", "lfilter", "convolve", "correlate", "fftconvolve", "find_peaks", "peak_widths", "peak_prominences", "welch", "periodogram", "spectrogram", "stft", "istft", "hilbert", "detrend", "resample", "decimate", "savgol_filter", "medfilt", "wiener", "cwt", "chirp", "gausspulse", "square", "sawtooth", "freqz", "sosfreqz", "zpk2sos", "tf2zpk"],
                example: "from scipy.signal import butter, filtfilt, find_peaks\nimport numpy as np\n# Butterworth lowpass filter\nb, a = butter(4, 0.1)\nx = np.random.randn(500)\ny = filtfilt(b, a, x)\n# Peak detection\nt = np.linspace(0, 1, 500)\nsig = np.sin(2*np.pi*5*t) + 0.5*np.sin(2*np.pi*10*t)\npeaks, props = find_peaks(sig, height=0.5)\nprint('Peaks found:', len(peaks))"),
            LibraryModule(name: "spatial", summary: "Spatial algorithms: KD-trees, convex hulls, distances, Voronoi",
                importLine: "from scipy.spatial import KDTree, ConvexHull, Voronoi, Delaunay",
                items: ["ConvexHull", "Voronoi", "Delaunay", "cKDTree", "KDTree", "distance.euclidean", "distance.cosine", "distance.cityblock", "distance.minkowski", "distance.cdist", "distance.pdist", "distance.squareform", "distance.hamming", "distance.jaccard", "distance.chebyshev", "distance.mahalanobis", "distance.correlation", "tsearch", "procrustes", "geometric_slerp"],
                example: "from scipy.spatial import KDTree, ConvexHull\nimport numpy as np\npts = np.random.rand(200, 2)\ntree = KDTree(pts)\nd, i = tree.query([0.5, 0.5], k=5)\nprint('5 nearest distances:', d)\nhull = ConvexHull(pts)\nprint('Hull vertices:', len(hull.vertices), 'Area:', hull.volume)"),
            LibraryModule(name: "sparse", summary: "Sparse matrix formats, construction, and linear algebra",
                importLine: "from scipy.sparse import csr_matrix, lil_matrix, diags",
                items: ["csr_matrix", "csc_matrix", "coo_matrix", "lil_matrix", "dia_matrix", "bsr_matrix", "dok_matrix", "eye", "diags", "block_diag", "hstack", "vstack", "kron", "issparse", "random", "linalg.spsolve", "linalg.eigs", "linalg.eigsh", "linalg.svds", "linalg.norm", "linalg.inv", "linalg.expm", "linalg.cg", "linalg.gmres", "linalg.lgmres", "linalg.bicg", "linalg.bicgstab", "linalg.splu", "linalg.spilu", "linalg.LinearOperator"],
                example: "from scipy.sparse import csr_matrix, diags, linalg\nimport numpy as np\n# Create sparse diagonal matrix\nA = diags([1, -2, 1], [-1, 0, 1], shape=(100, 100), format='csr')\nb = np.ones(100)\nx = linalg.spsolve(A, b)\nprint('Solution norm:', np.linalg.norm(x))"),
            LibraryModule(name: "special", summary: "Special mathematical functions: Bessel, gamma, error, elliptic",
                importLine: "from scipy.special import gamma, erf, jv, softmax",
                items: ["gamma", "gammaln", "digamma", "polygamma", "beta", "betaln", "erf", "erfc", "erfinv", "erfcinv", "factorial", "comb", "perm", "binom", "zeta", "jv", "yv", "iv", "kv", "hankel1", "hankel2", "airy", "legendre", "hermite", "laguerre", "chebyc", "chebyt", "ellipj", "ellipk", "ellipe", "expn", "expi", "lambertw", "softmax", "log_softmax", "expit", "logit", "logsumexp", "rel_entr", "xlogy", "hyp2f1"],
                example: "from scipy.special import gamma, erf, softmax, expit\nimport numpy as np\nprint('Gamma(5):', gamma(5))  # 24.0\nprint('erf(1):', erf(1))\nprint('Sigmoid(0):', expit(0))  # 0.5\nx = np.array([1, 2, 3])\nprint('Softmax:', softmax(x))"),
            LibraryModule(name: "ndimage", summary: "N-dimensional image processing: filters, morphology, measurements",
                importLine: "from scipy.ndimage import gaussian_filter, label, rotate",
                items: ["gaussian_filter", "uniform_filter", "median_filter", "maximum_filter", "minimum_filter", "convolve", "correlate", "sobel", "laplace", "gaussian_laplace", "gaussian_gradient_magnitude", "binary_erosion", "binary_dilation", "binary_opening", "binary_closing", "binary_fill_holes", "label", "find_objects", "center_of_mass", "rotate", "zoom", "shift", "affine_transform", "map_coordinates", "distance_transform_edt", "generate_binary_structure"],
                example: "from scipy.ndimage import gaussian_filter, label, sobel\nimport numpy as np\nimg = np.random.rand(64, 64)\nsmoothed = gaussian_filter(img, sigma=2)\nedges = sobel(smoothed)\nbinary = smoothed > 0.5\nlabeled, n = label(binary)\nprint('Regions found:', n)"),
            LibraryModule(name: "cluster", summary: "Hierarchical clustering, dendrograms, vector quantization",
                importLine: "from scipy.cluster.hierarchy import linkage, fcluster, dendrogram",
                items: ["linkage", "fcluster", "dendrogram", "cut_tree", "cophenet", "inconsistent", "maxdists", "leaves_list", "fclusterdata", "is_valid_linkage", "optimal_leaf_ordering"],
                example: "from scipy.cluster.hierarchy import linkage, fcluster\nimport numpy as np\nX = np.random.rand(100, 3)\nZ = linkage(X, method='ward')\nlabels = fcluster(Z, t=4, criterion='maxclust')\nfor c in range(1, 5):\n    print(f'Cluster {c}: {np.sum(labels == c)} points')"),
            LibraryModule(name: "constants", summary: "Physical and mathematical constants, unit conversions",
                importLine: "from scipy import constants",
                items: ["constants.pi", "constants.golden", "constants.c", "constants.h", "constants.hbar", "constants.G", "constants.g", "constants.e", "constants.k", "constants.N_A", "constants.R", "constants.sigma", "constants.eV", "constants.m_e", "constants.m_p", "constants.epsilon_0", "constants.mu_0", "constants.physical_constants", "constants.value", "constants.find", "constants.convert_temperature"],
                example: "from scipy import constants\nprint('Speed of light:', constants.c, 'm/s')\nprint('Planck:', constants.h, 'J*s')\nprint('Avogadro:', constants.N_A)\n# Convert temperature\nprint('100 C in F:', constants.convert_temperature(100, 'C', 'F'))"),
            LibraryModule(name: "io", summary: "File I/O for MATLAB .mat files and WAV audio",
                importLine: "from scipy.io import loadmat, savemat",
                items: ["loadmat", "savemat", "whosmat", "wavfile.read", "wavfile.write"],
                example: "from scipy.io import savemat, loadmat\nimport numpy as np\n# Save and load MATLAB file\nsavemat('/tmp/test.mat', {'arr': np.eye(3)})\ndata = loadmat('/tmp/test.mat')\nprint('Loaded keys:', list(data.keys()))")
        ])
    }

    // MARK: sklearn
    private static var sklearnSection: LibrarySection {
        LibrarySection(name: "sklearn", icon: "brain.head.profile", modules: [
            LibraryModule(name: "linear_model", summary: "Linear, logistic, regularized, and robust regression models",
                importLine: "from sklearn.linear_model import LinearRegression, LogisticRegression, Ridge, Lasso",
                items: ["LinearRegression", "Ridge", "Lasso", "ElasticNet", "LogisticRegression", "SGDClassifier", "SGDRegressor", "RidgeClassifier", "Perceptron", "BayesianRidge", "ARDRegression", "HuberRegressor", "Lars", "LassoLars", "OrthogonalMatchingPursuit", "PoissonRegressor", "GammaRegressor", "TweedieRegressor"],
                example: "from sklearn.linear_model import LinearRegression, Ridge, LogisticRegression\nimport numpy as np\nX = np.arange(20).reshape(-1, 1)\ny = 3*X.ravel() + np.random.randn(20)\nlr = LinearRegression().fit(X, y)\nprint('Coef:', lr.coef_, 'R2:', lr.score(X, y))\nridge = Ridge(alpha=1.0).fit(X, y)\nprint('Ridge R2:', ridge.score(X, y))"),
            LibraryModule(name: "tree", summary: "Decision tree classifiers and regressors with feature importance",
                importLine: "from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor",
                items: ["DecisionTreeClassifier", "DecisionTreeRegressor", "ExtraTreeClassifier", "ExtraTreeRegressor"],
                example: "from sklearn.tree import DecisionTreeClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\ntree = DecisionTreeClassifier(max_depth=3).fit(X, y)\nprint('Accuracy:', tree.score(X, y))\nprint('Feature importances:', tree.feature_importances_)"),
            LibraryModule(name: "ensemble", summary: "Random forests, gradient boosting, bagging, stacking, voting",
                importLine: "from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier",
                items: ["RandomForestClassifier", "RandomForestRegressor", "GradientBoostingClassifier", "GradientBoostingRegressor", "AdaBoostClassifier", "AdaBoostRegressor", "BaggingClassifier", "BaggingRegressor", "ExtraTreesClassifier", "ExtraTreesRegressor", "HistGradientBoostingClassifier", "HistGradientBoostingRegressor", "IsolationForest", "VotingClassifier", "VotingRegressor", "StackingClassifier", "StackingRegressor"],
                example: "from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nrf = RandomForestClassifier(n_estimators=50).fit(X, y)\ngb = GradientBoostingClassifier(n_estimators=50, max_depth=3).fit(X, y)\nprint('RF:', rf.score(X, y), 'GB:', gb.score(X, y))"),
            LibraryModule(name: "cluster", summary: "Clustering: KMeans, DBSCAN, HDBSCAN, Agglomerative, Spectral",
                importLine: "from sklearn.cluster import KMeans, DBSCAN, AgglomerativeClustering",
                items: ["KMeans", "MiniBatchKMeans", "DBSCAN", "AgglomerativeClustering", "SpectralClustering", "MeanShift", "OPTICS", "Birch", "AffinityPropagation", "BisectingKMeans", "HDBSCAN", "FeatureAgglomeration"],
                example: "from sklearn.cluster import KMeans, DBSCAN\nimport numpy as np\nfrom sklearn.datasets import make_blobs\nX, _ = make_blobs(n_samples=300, centers=4, random_state=42)\nkm = KMeans(n_clusters=4, n_init=10).fit(X)\ndb = DBSCAN(eps=1.0, min_samples=5).fit(X)\nprint('KMeans inertia:', km.inertia_)\nprint('DBSCAN clusters:', len(set(db.labels_)) - 1)"),
            LibraryModule(name: "preprocessing", summary: "Scalers, encoders, transformers for data preparation",
                importLine: "from sklearn.preprocessing import StandardScaler, MinMaxScaler, OneHotEncoder",
                items: ["StandardScaler", "MinMaxScaler", "RobustScaler", "MaxAbsScaler", "Normalizer", "Binarizer", "LabelEncoder", "OneHotEncoder", "OrdinalEncoder", "LabelBinarizer", "PolynomialFeatures", "PowerTransformer", "QuantileTransformer", "KBinsDiscretizer", "FunctionTransformer", "SplineTransformer", "TargetEncoder"],
                example: "from sklearn.preprocessing import StandardScaler, OneHotEncoder, PolynomialFeatures\nimport numpy as np\nX = np.random.rand(100, 3) * 100\nscaler = StandardScaler().fit(X)\nX_s = scaler.transform(X)\nprint('Scaled mean:', X_s.mean(axis=0))\npoly = PolynomialFeatures(degree=2).fit_transform(X[:5, :2])\nprint('Poly features shape:', poly.shape)"),
            LibraryModule(name: "decomposition", summary: "PCA, SVD, NMF, ICA, LDA, and other factorizations",
                importLine: "from sklearn.decomposition import PCA, NMF, TruncatedSVD, FastICA",
                items: ["PCA", "TruncatedSVD", "NMF", "FastICA", "KernelPCA", "IncrementalPCA", "LatentDirichletAllocation", "SparsePCA", "FactorAnalysis", "DictionaryLearning", "MiniBatchNMF"],
                example: "from sklearn.decomposition import PCA\nfrom sklearn.datasets import load_iris\nX, _ = load_iris(return_X_y=True)\npca = PCA(n_components=2).fit(X)\nX_red = pca.transform(X)\nprint('Explained variance:', pca.explained_variance_ratio_)\nprint('Reduced shape:', X_red.shape)"),
            LibraryModule(name: "neighbors", summary: "KNN classifiers/regressors, nearest neighbors, kernel density",
                importLine: "from sklearn.neighbors import KNeighborsClassifier, KNeighborsRegressor",
                items: ["KNeighborsClassifier", "KNeighborsRegressor", "RadiusNeighborsClassifier", "RadiusNeighborsRegressor", "NearestNeighbors", "NearestCentroid", "LocalOutlierFactor", "KernelDensity"],
                example: "from sklearn.neighbors import KNeighborsClassifier, LocalOutlierFactor\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nknn = KNeighborsClassifier(n_neighbors=5).fit(X, y)\nprint('Accuracy:', knn.score(X, y))\nlof = LocalOutlierFactor(n_neighbors=20)\npreds = lof.fit_predict(X)\nprint('Outliers:', sum(preds == -1))"),
            LibraryModule(name: "svm", summary: "Support vector machines: SVC, SVR, linear, nu, one-class",
                importLine: "from sklearn.svm import SVC, SVR, LinearSVC",
                items: ["SVC", "SVR", "LinearSVC", "LinearSVR", "NuSVC", "NuSVR", "OneClassSVM"],
                example: "from sklearn.svm import SVC, LinearSVC\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nrbf = SVC(kernel='rbf', C=1.0).fit(X, y)\nlin = LinearSVC(max_iter=2000).fit(X, y)\nprint('RBF SVC:', rbf.score(X, y))\nprint('LinearSVC:', lin.score(X, y))"),
            LibraryModule(name: "naive_bayes", summary: "Gaussian, Multinomial, Bernoulli, Complement, Categorical NB",
                importLine: "from sklearn.naive_bayes import GaussianNB, MultinomialNB",
                items: ["GaussianNB", "MultinomialNB", "BernoulliNB", "ComplementNB", "CategoricalNB"],
                example: "from sklearn.naive_bayes import GaussianNB\nfrom sklearn.datasets import load_iris\nfrom sklearn.model_selection import cross_val_score\nX, y = load_iris(return_X_y=True)\nscores = cross_val_score(GaussianNB(), X, y, cv=5)\nprint('CV Accuracy: %.3f +/- %.3f' % (scores.mean(), scores.std()))"),
            LibraryModule(name: "neural_network", summary: "Multi-layer perceptron (MLP) classifier and regressor",
                importLine: "from sklearn.neural_network import MLPClassifier, MLPRegressor",
                items: ["MLPClassifier", "MLPRegressor"],
                example: "from sklearn.neural_network import MLPClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nmlp = MLPClassifier(hidden_layer_sizes=(50, 25), max_iter=500, random_state=42).fit(X, y)\nprint('Accuracy:', mlp.score(X, y))"),
            LibraryModule(name: "gaussian_process", summary: "Gaussian process regression/classification with kernel library",
                importLine: "from sklearn.gaussian_process import GaussianProcessRegressor\nfrom sklearn.gaussian_process.kernels import RBF, Matern",
                items: ["GaussianProcessClassifier", "GaussianProcessRegressor", "kernels.RBF", "kernels.Matern", "kernels.RationalQuadratic", "kernels.ExpSineSquared", "kernels.DotProduct", "kernels.WhiteKernel", "kernels.ConstantKernel"],
                example: "from sklearn.gaussian_process import GaussianProcessRegressor\nfrom sklearn.gaussian_process.kernels import RBF\nimport numpy as np\nX = np.linspace(0, 5, 20).reshape(-1, 1)\ny = np.sin(X).ravel()\ngp = GaussianProcessRegressor(kernel=RBF()).fit(X, y)\ny_pred, y_std = gp.predict(np.array([[2.5]]), return_std=True)\nprint('Pred:', y_pred, 'Std:', y_std)"),
            LibraryModule(name: "discriminant_analysis", summary: "Linear and Quadratic Discriminant Analysis",
                importLine: "from sklearn.discriminant_analysis import LinearDiscriminantAnalysis",
                items: ["LinearDiscriminantAnalysis", "QuadraticDiscriminantAnalysis"],
                example: "from sklearn.discriminant_analysis import LinearDiscriminantAnalysis\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nlda = LinearDiscriminantAnalysis(n_components=2).fit(X, y)\nX_lda = lda.transform(X)\nprint('LDA shape:', X_lda.shape, 'Accuracy:', lda.score(X, y))"),
            LibraryModule(name: "mixture", summary: "Gaussian Mixture Models: standard and Bayesian",
                importLine: "from sklearn.mixture import GaussianMixture, BayesianGaussianMixture",
                items: ["GaussianMixture", "BayesianGaussianMixture"],
                example: "from sklearn.mixture import GaussianMixture\nfrom sklearn.datasets import make_blobs\nX, _ = make_blobs(n_samples=300, centers=3, random_state=42)\ngmm = GaussianMixture(n_components=3).fit(X)\nprint('BIC:', gmm.bic(X), 'AIC:', gmm.aic(X))\nlabels = gmm.predict(X)"),
            LibraryModule(name: "model_selection", summary: "Splitting, cross-validation, grid search, learning curves",
                importLine: "from sklearn.model_selection import train_test_split, cross_val_score, GridSearchCV",
                items: ["train_test_split", "cross_val_score", "cross_validate", "learning_curve", "validation_curve", "KFold", "StratifiedKFold", "LeaveOneOut", "TimeSeriesSplit", "ShuffleSplit", "RepeatedKFold", "RepeatedStratifiedKFold", "GroupKFold", "GridSearchCV", "RandomizedSearchCV"],
                example: "from sklearn.model_selection import train_test_split, cross_val_score, GridSearchCV\nfrom sklearn.svm import SVC\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nX_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2)\nscores = cross_val_score(SVC(), X, y, cv=5)\nprint('CV:', scores.mean())"),
            LibraryModule(name: "metrics (classification)", summary: "Classification metrics: accuracy, F1, ROC, confusion matrix",
                importLine: "from sklearn.metrics import accuracy_score, f1_score, confusion_matrix",
                items: ["accuracy_score", "balanced_accuracy_score", "precision_score", "recall_score", "f1_score", "fbeta_score", "confusion_matrix", "classification_report", "roc_auc_score", "roc_curve", "precision_recall_curve", "average_precision_score", "log_loss", "brier_score_loss", "cohen_kappa_score", "matthews_corrcoef", "hamming_loss", "jaccard_score", "zero_one_loss", "hinge_loss", "top_k_accuracy_score"],
                example: "from sklearn.metrics import accuracy_score, classification_report, confusion_matrix\nimport numpy as np\ny_true = [0, 1, 1, 0, 1, 0, 1, 1]\ny_pred = [0, 1, 0, 0, 1, 1, 1, 1]\nprint('Accuracy:', accuracy_score(y_true, y_pred))\nprint(confusion_matrix(y_true, y_pred))\nprint(classification_report(y_true, y_pred))"),
            LibraryModule(name: "metrics (regression)", summary: "Regression metrics: MSE, MAE, R2, explained variance",
                importLine: "from sklearn.metrics import mean_squared_error, r2_score",
                items: ["mean_squared_error", "mean_absolute_error", "root_mean_squared_error", "median_absolute_error", "r2_score", "explained_variance_score", "max_error", "mean_absolute_percentage_error", "mean_squared_log_error", "mean_pinball_loss", "d2_pinball_score"],
                example: "from sklearn.metrics import mean_squared_error, r2_score\nimport numpy as np\ny_true = np.array([3, -0.5, 2, 7])\ny_pred = np.array([2.5, 0.0, 2, 8])\nprint('MSE:', mean_squared_error(y_true, y_pred))\nprint('R2:', r2_score(y_true, y_pred))"),
            LibraryModule(name: "metrics (clustering)", summary: "Clustering metrics: silhouette, ARI, Davies-Bouldin",
                importLine: "from sklearn.metrics import silhouette_score, adjusted_rand_score",
                items: ["silhouette_score", "silhouette_samples", "calinski_harabasz_score", "davies_bouldin_score", "adjusted_rand_score", "adjusted_mutual_info_score", "normalized_mutual_info_score", "pairwise_distances", "euclidean_distances", "cosine_similarity"],
                example: "from sklearn.metrics import silhouette_score, davies_bouldin_score\nfrom sklearn.cluster import KMeans\nfrom sklearn.datasets import make_blobs\nX, _ = make_blobs(n_samples=300, centers=4, random_state=42)\nlabels = KMeans(n_clusters=4, n_init=10).fit_predict(X)\nprint('Silhouette:', silhouette_score(X, labels))\nprint('Davies-Bouldin:', davies_bouldin_score(X, labels))"),
            LibraryModule(name: "datasets", summary: "Built-in datasets and synthetic data generators",
                importLine: "from sklearn.datasets import load_iris, make_classification",
                items: ["make_classification", "make_regression", "make_blobs", "make_moons", "make_circles", "make_swiss_roll", "make_s_curve", "make_friedman1", "make_friedman2", "make_friedman3", "load_iris", "load_digits", "load_wine", "load_breast_cancer", "load_diabetes"],
                example: "from sklearn.datasets import make_moons, load_iris\nX, y = make_moons(n_samples=200, noise=0.1, random_state=42)\nprint('Moons shape:', X.shape)\niris = load_iris()\nprint('Iris features:', iris.feature_names)\nprint('Iris targets:', iris.target_names)"),
            LibraryModule(name: "manifold", summary: "Manifold learning: t-SNE, MDS, Isomap, LLE, Spectral",
                importLine: "from sklearn.manifold import TSNE, MDS, Isomap",
                items: ["TSNE", "MDS", "Isomap", "LocallyLinearEmbedding", "SpectralEmbedding"],
                example: "from sklearn.manifold import TSNE\nfrom sklearn.datasets import load_digits\nX, y = load_digits(return_X_y=True)\nemb = TSNE(n_components=2, perplexity=30, random_state=42).fit_transform(X[:300])\nprint('Embedding shape:', emb.shape)"),
            LibraryModule(name: "pipeline", summary: "Pipeline, FeatureUnion for chaining estimators",
                importLine: "from sklearn.pipeline import Pipeline, make_pipeline, FeatureUnion",
                items: ["Pipeline", "make_pipeline", "FeatureUnion"],
                example: "from sklearn.pipeline import make_pipeline\nfrom sklearn.preprocessing import StandardScaler\nfrom sklearn.svm import SVC\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\npipe = make_pipeline(StandardScaler(), SVC())\npipe.fit(X, y)\nprint('Pipe accuracy:', pipe.score(X, y))"),
            LibraryModule(name: "compose", summary: "ColumnTransformer for heterogeneous data pipelines",
                importLine: "from sklearn.compose import ColumnTransformer, make_column_transformer",
                items: ["ColumnTransformer", "make_column_transformer", "make_column_selector", "TransformedTargetRegressor"],
                example: "from sklearn.compose import ColumnTransformer\nfrom sklearn.preprocessing import StandardScaler, OneHotEncoder\nct = ColumnTransformer([\n    ('num', StandardScaler(), [0, 1, 2]),\n    ('cat', OneHotEncoder(), [3])\n], remainder='passthrough')\nprint('Transformer:', ct)"),
            LibraryModule(name: "impute", summary: "Missing value imputation: simple, KNN, iterative",
                importLine: "from sklearn.impute import SimpleImputer, KNNImputer",
                items: ["SimpleImputer", "KNNImputer", "IterativeImputer", "MissingIndicator"],
                example: "from sklearn.impute import SimpleImputer, KNNImputer\nimport numpy as np\nX = np.array([[1, 2], [np.nan, 3], [7, 6], [np.nan, np.nan]])\nimp = SimpleImputer(strategy='mean').fit_transform(X)\nprint('Imputed:', imp)\nknn_imp = KNNImputer(n_neighbors=2).fit_transform(X)\nprint('KNN imputed:', knn_imp)"),
            LibraryModule(name: "feature_extraction", summary: "Feature extraction from dicts and text (CountVectorizer, TF-IDF)",
                importLine: "from sklearn.feature_extraction.text import CountVectorizer, TfidfVectorizer",
                items: ["DictVectorizer", "text.CountVectorizer", "text.TfidfVectorizer", "text.TfidfTransformer", "text.HashingVectorizer"],
                example: "from sklearn.feature_extraction.text import TfidfVectorizer\ncorpus = ['the cat sat on the mat', 'the dog ate my homework']\nvec = TfidfVectorizer()\nX = vec.fit_transform(corpus)\nprint('Features:', vec.get_feature_names_out())\nprint('Shape:', X.shape)"),
            LibraryModule(name: "feature_selection", summary: "Feature selection: SelectKBest, RFE, variance threshold",
                importLine: "from sklearn.feature_selection import SelectKBest, f_classif, RFE",
                items: ["SelectKBest", "SelectPercentile", "VarianceThreshold", "RFE", "RFECV", "SelectFromModel", "SequentialFeatureSelector", "f_classif", "f_regression", "chi2", "mutual_info_classif", "mutual_info_regression"],
                example: "from sklearn.feature_selection import SelectKBest, f_classif\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nselector = SelectKBest(f_classif, k=2).fit(X, y)\nX_new = selector.transform(X)\nprint('Selected shape:', X_new.shape)\nprint('Scores:', selector.scores_)"),
            LibraryModule(name: "calibration", summary: "Probability calibration for classifiers",
                importLine: "from sklearn.calibration import CalibratedClassifierCV, calibration_curve",
                items: ["CalibratedClassifierCV", "calibration_curve"],
                example: "from sklearn.calibration import CalibratedClassifierCV\nfrom sklearn.svm import LinearSVC\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\ny_binary = (y == 2).astype(int)\ncal = CalibratedClassifierCV(LinearSVC(), cv=3).fit(X, y_binary)\nprint('Proba:', cal.predict_proba(X[:3]))"),
            LibraryModule(name: "inspection", summary: "Model inspection: permutation importance, partial dependence",
                importLine: "from sklearn.inspection import permutation_importance",
                items: ["permutation_importance", "partial_dependence", "PartialDependenceDisplay"],
                example: "from sklearn.inspection import permutation_importance\nfrom sklearn.ensemble import RandomForestClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nclf = RandomForestClassifier(n_estimators=50).fit(X, y)\nresult = permutation_importance(clf, X, y, n_repeats=10)\nprint('Importances:', result.importances_mean)"),
            LibraryModule(name: "multiclass", summary: "One-vs-rest, one-vs-one, error-correcting output codes",
                importLine: "from sklearn.multiclass import OneVsRestClassifier, OneVsOneClassifier",
                items: ["OneVsRestClassifier", "OneVsOneClassifier", "OutputCodeClassifier"],
                example: "from sklearn.multiclass import OneVsRestClassifier\nfrom sklearn.svm import SVC\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\novr = OneVsRestClassifier(SVC()).fit(X, y)\nprint('Accuracy:', ovr.score(X, y))"),
            LibraryModule(name: "multioutput", summary: "Multi-target classification and regression",
                importLine: "from sklearn.multioutput import MultiOutputClassifier, MultiOutputRegressor",
                items: ["MultiOutputClassifier", "MultiOutputRegressor", "ClassifierChain", "RegressorChain"],
                example: "from sklearn.multioutput import MultiOutputRegressor\nfrom sklearn.linear_model import Ridge\nimport numpy as np\nX = np.random.rand(100, 3)\ny = np.column_stack([X[:, 0]*2 + 1, X[:, 1]*3 - 1])\nmor = MultiOutputRegressor(Ridge()).fit(X, y)\nprint('Score:', mor.score(X, y))"),
            LibraryModule(name: "semi_supervised", summary: "Semi-supervised learning: label propagation and spreading",
                importLine: "from sklearn.semi_supervised import LabelPropagation, LabelSpreading",
                items: ["LabelPropagation", "LabelSpreading", "SelfTrainingClassifier"],
                example: "from sklearn.semi_supervised import LabelSpreading\nfrom sklearn.datasets import load_iris\nimport numpy as np\nX, y = load_iris(return_X_y=True)\ny_partial = y.copy()\ny_partial[::3] = -1  # mark 1/3 as unlabeled\nls = LabelSpreading().fit(X, y_partial)\nprint('Accuracy on all:', ls.score(X, y))"),
            LibraryModule(name: "isotonic", summary: "Isotonic regression for monotonic fitting",
                importLine: "from sklearn.isotonic import IsotonicRegression",
                items: ["IsotonicRegression"],
                example: "from sklearn.isotonic import IsotonicRegression\nimport numpy as np\nx = np.arange(10).astype(float)\ny = np.array([1, 2, 1.5, 4, 3.5, 5, 5.5, 6, 7, 8])\niso = IsotonicRegression().fit(x, y)\nprint('Monotonic fit:', iso.predict(x))"),
            LibraryModule(name: "kernel_approximation", summary: "Approximate kernel maps: RBFSampler, Nystroem",
                importLine: "from sklearn.kernel_approximation import RBFSampler, Nystroem",
                items: ["RBFSampler", "Nystroem", "AdditiveChi2Sampler"],
                example: "from sklearn.kernel_approximation import RBFSampler\nfrom sklearn.linear_model import SGDClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nrbf = RBFSampler(gamma=1, n_components=100, random_state=42)\nX_feat = rbf.fit_transform(X)\nclf = SGDClassifier().fit(X_feat, y)\nprint('Accuracy:', clf.score(X_feat, y))"),
            LibraryModule(name: "cross_decomposition", summary: "Partial Least Squares and Canonical Correlation Analysis",
                importLine: "from sklearn.cross_decomposition import PLSRegression, CCA",
                items: ["PLSRegression", "PLSCanonical", "CCA"],
                example: "from sklearn.cross_decomposition import PLSRegression\nimport numpy as np\nX = np.random.rand(100, 5)\ny = X[:, 0]*2 + X[:, 1]*3 + np.random.randn(100)*0.1\npls = PLSRegression(n_components=2).fit(X, y)\nprint('R2:', pls.score(X, y))"),
            LibraryModule(name: "base", summary: "Base classes, clone, estimator API utilities",
                importLine: "from sklearn.base import BaseEstimator, clone",
                items: ["BaseEstimator", "ClassifierMixin", "RegressorMixin", "TransformerMixin", "ClusterMixin", "clone"],
                example: "from sklearn.base import clone\nfrom sklearn.tree import DecisionTreeClassifier\ndt = DecisionTreeClassifier(max_depth=3)\ndt_clone = clone(dt)\nprint('Cloned params:', dt_clone.get_params())")
        ])
    }

    // MARK: Matplotlib
    private static var matplotlibSection: LibrarySection {
        LibrarySection(name: "matplotlib", icon: "chart.xyaxis.line", modules: [
            LibraryModule(name: "pyplot (2D plots)", summary: "Line, scatter, bar, histogram, contour, polar, and more",
                importLine: "import matplotlib.pyplot as plt",
                items: ["plt.plot", "plt.scatter", "plt.bar", "plt.barh", "plt.hist", "plt.hist2d", "plt.pie", "plt.fill_between", "plt.fill_betweenx", "plt.stem", "plt.step", "plt.errorbar", "plt.boxplot", "plt.violinplot", "plt.imshow", "plt.matshow", "plt.pcolormesh", "plt.contour", "plt.contourf", "plt.polar", "plt.stackplot", "plt.hexbin", "plt.hlines", "plt.vlines", "plt.quiver", "plt.streamplot", "plt.tricontour", "plt.tricontourf", "plt.tripcolor", "plt.spy", "plt.eventplot", "plt.broken_barh"],
                example: "import matplotlib.pyplot as plt\nimport numpy as np\nx = np.linspace(0, 2*np.pi, 200)\nplt.plot(x, np.sin(x), label='sin(x)')\nplt.plot(x, np.cos(x), '--', label='cos(x)')\nplt.fill_between(x, np.sin(x), alpha=0.3)\nplt.legend(); plt.title('Trig Functions'); plt.grid(True)\nplt.show()"),
            LibraryModule(name: "pyplot (3D plots)", summary: "3D surface, wireframe, scatter, bar, and contour plots",
                importLine: "import matplotlib.pyplot as plt\nfig = plt.figure()\nax = fig.add_subplot(111, projection='3d')",
                items: ["plt.plot_surface", "plt.plot_wireframe", "plt.scatter3D", "plt.plot3D", "plt.bar3d", "plt.plot_trisurf", "ax.contour3D", "ax.contourf3D", "ax.set_zlabel", "ax.set_zlim", "ax.view_init"],
                example: "import matplotlib.pyplot as plt\nimport numpy as np\nfig = plt.figure(figsize=(10, 7))\nax = fig.add_subplot(111, projection='3d')\nu = np.linspace(0, 2*np.pi, 50)\nv = np.linspace(0, np.pi, 50)\nX = np.outer(np.cos(u), np.sin(v))\nY = np.outer(np.sin(u), np.sin(v))\nZ = np.outer(np.ones_like(u), np.cos(v))\nax.plot_surface(X, Y, Z, cmap='viridis', alpha=0.8)\nplt.show()"),
            LibraryModule(name: "pyplot (figure/axes)", summary: "Figure creation, subplots, axes management, output",
                importLine: "import matplotlib.pyplot as plt",
                items: ["plt.figure", "plt.subplots", "plt.subplot", "plt.subplot2grid", "plt.axes", "plt.gca", "plt.gcf", "plt.cla", "plt.clf", "plt.close", "ax.twinx", "ax.twiny", "fig.add_subplot", "plt.title", "plt.suptitle", "plt.xlabel", "plt.ylabel", "plt.text", "plt.annotate", "plt.xlim", "plt.ylim", "plt.xscale", "plt.yscale", "plt.xticks", "plt.yticks", "plt.grid", "plt.legend", "plt.colorbar", "plt.axis", "plt.tight_layout", "plt.margins", "plt.axhline", "plt.axvline", "plt.axhspan", "plt.axvspan", "plt.show", "plt.savefig"],
                example: "import matplotlib.pyplot as plt\nimport numpy as np\nfig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))\nx = np.linspace(0, 10, 100)\nax1.plot(x, np.sin(x)); ax1.set_title('Sine')\nax2.plot(x, np.exp(-x/5)*np.cos(x)); ax2.set_title('Damped Cosine')\nplt.tight_layout(); plt.show()"),
            LibraryModule(name: "cm", summary: "50+ colormaps: sequential, diverging, cyclic, qualitative",
                importLine: "from matplotlib import cm",
                items: ["cm.viridis", "cm.plasma", "cm.inferno", "cm.magma", "cm.cividis", "cm.turbo", "cm.hot", "cm.cool", "cm.coolwarm", "cm.RdBu", "cm.RdYlGn", "cm.Spectral", "cm.seismic", "cm.twilight", "cm.hsv", "cm.tab10", "cm.tab20", "cm.Set1", "cm.Set2", "cm.Paired", "cm.jet", "cm.rainbow", "cm.terrain", "cm.ocean", "cm.get_cmap"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib import cm\nimport numpy as np\ndata = np.random.rand(20, 20)\nfig, axes = plt.subplots(1, 3, figsize=(15, 4))\nfor ax, cmap in zip(axes, ['viridis', 'coolwarm', 'RdYlGn']):\n    ax.imshow(data, cmap=cmap)\n    ax.set_title(cmap)\nplt.tight_layout(); plt.show()"),
            LibraryModule(name: "colors", summary: "Color conversion, normalization, custom colormaps",
                importLine: "from matplotlib.colors import Normalize, LogNorm, ListedColormap",
                items: ["to_rgba", "to_hex", "to_rgb", "Normalize", "LogNorm", "SymLogNorm", "PowerNorm", "BoundaryNorm", "TwoSlopeNorm", "Colormap", "ListedColormap", "LinearSegmentedColormap", "LinearSegmentedColormap.from_list", "CSS4_COLORS", "TABLEAU_COLORS", "BASE_COLORS", "XKCD_COLORS"],
                example: "from matplotlib.colors import to_rgba, ListedColormap, Normalize\nprint('Red:', to_rgba('red'))\nprint('Hex:', to_rgba('#ff8800'))\ncustom = ListedColormap(['red', 'green', 'blue', 'yellow'])\nnorm = Normalize(vmin=0, vmax=100)\nprint('Normalized 50:', norm(50))"),
            LibraryModule(name: "ticker", summary: "Tick locators and formatters for axis customization",
                importLine: "from matplotlib.ticker import MaxNLocator, FuncFormatter, PercentFormatter",
                items: ["AutoLocator", "MaxNLocator", "MultipleLocator", "FixedLocator", "IndexLocator", "LinearLocator", "LogLocator", "SymmetricalLogLocator", "NullLocator", "AutoMinorLocator", "ScalarFormatter", "FuncFormatter", "FormatStrFormatter", "StrMethodFormatter", "FixedFormatter", "PercentFormatter", "LogFormatter", "LogFormatterMathtext", "NullFormatter", "EngFormatter"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.ticker import FuncFormatter, MultipleLocator\nimport numpy as np\nfig, ax = plt.subplots()\nax.plot(np.random.rand(20) * 100)\nax.yaxis.set_major_formatter(FuncFormatter(lambda y, _: f'${y:.0f}'))\nax.xaxis.set_major_locator(MultipleLocator(5))\nplt.show()"),
            LibraryModule(name: "patches", summary: "2D shape patches: rectangles, circles, polygons, arrows",
                importLine: "from matplotlib.patches import Rectangle, Circle, Ellipse, Polygon",
                items: ["Rectangle", "Circle", "Ellipse", "FancyBboxPatch", "Polygon", "RegularPolygon", "Arc", "Wedge", "Arrow", "FancyArrow", "FancyArrowPatch", "PathPatch", "ConnectionPatch", "BoxStyle", "ArrowStyle"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.patches import Circle, Rectangle, FancyBboxPatch\nfig, ax = plt.subplots(figsize=(8, 6))\nax.add_patch(Rectangle((0.1, 0.1), 0.3, 0.3, color='blue', alpha=0.5))\nax.add_patch(Circle((0.7, 0.5), 0.2, color='red', alpha=0.5))\nax.add_patch(FancyBboxPatch((0.3, 0.6), 0.3, 0.2, boxstyle='round,pad=0.05', color='green', alpha=0.5))\nax.set_xlim(0, 1); ax.set_ylim(0, 1); plt.show()"),
            LibraryModule(name: "animation", summary: "Frame-by-frame and artist-based animation",
                importLine: "from matplotlib.animation import FuncAnimation, ArtistAnimation",
                items: ["FuncAnimation", "ArtistAnimation"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.animation import FuncAnimation\nimport numpy as np\nfig, ax = plt.subplots()\nx = np.linspace(0, 2*np.pi, 100)\nln, = ax.plot(x, np.sin(x))\ndef update(frame):\n    ln.set_ydata(np.sin(x + frame/10))\n    return ln,\nanim = FuncAnimation(fig, update, frames=100, interval=50)"),
            LibraryModule(name: "gridspec", summary: "Flexible subplot grid layouts with spanning",
                importLine: "from matplotlib.gridspec import GridSpec",
                items: ["GridSpec", "SubplotSpec", "GridSpecFromSubplotSpec"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.gridspec import GridSpec\nimport numpy as np\nfig = plt.figure(figsize=(12, 8))\ngs = GridSpec(2, 3, width_ratios=[1, 2, 1], height_ratios=[2, 1])\nax1 = fig.add_subplot(gs[0, :])  # top row, all cols\nax2 = fig.add_subplot(gs[1, 0])  # bottom-left\nax3 = fig.add_subplot(gs[1, 1:]) # bottom-right\nax1.plot(np.random.randn(100).cumsum())\nplt.tight_layout(); plt.show()"),
            LibraryModule(name: "dates", summary: "Date formatting, locators, and conversion for time-series",
                importLine: "from matplotlib.dates import DateFormatter, AutoDateLocator",
                items: ["DateFormatter", "AutoDateLocator", "DayLocator", "MonthLocator", "YearLocator", "HourLocator", "MinuteLocator", "date2num", "num2date", "datestr2num"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.dates import DateFormatter, MonthLocator\nimport numpy as np\n# Use with datetime x-axis\nplt.gca().xaxis.set_major_formatter(DateFormatter('%Y-%m'))\nplt.gca().xaxis.set_major_locator(MonthLocator())"),
            LibraryModule(name: "style", summary: "Predefined style sheets: ggplot, seaborn, dark, etc.",
                importLine: "import matplotlib.pyplot as plt\nplt.style.use('ggplot')",
                items: ["plt.style.use", "plt.style.available", "plt.style.context", "default", "classic", "ggplot", "seaborn-v0_8", "bmh", "dark_background", "fivethirtyeight", "grayscale", "Solarize_Light2", "tableau-colorblind10"],
                example: "import matplotlib.pyplot as plt\nimport numpy as np\nprint('Styles:', plt.style.available)\nplt.style.use('ggplot')\nx = np.linspace(0, 10, 100)\nplt.plot(x, np.sin(x))\nplt.title('ggplot style'); plt.show()"),
            LibraryModule(name: "collections", summary: "Efficient batch drawing: lines, patches, polygons",
                importLine: "from matplotlib.collections import LineCollection, PatchCollection",
                items: ["PathCollection", "LineCollection", "PatchCollection", "PolyCollection", "QuadMesh", "EventCollection"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.collections import LineCollection\nimport numpy as np\nsegs = [np.column_stack([np.linspace(0, 1, 20), np.random.rand(20)*i/5]) for i in range(5)]\nlc = LineCollection(segs, linewidths=2)\nfig, ax = plt.subplots()\nax.add_collection(lc); ax.autoscale(); plt.show()"),
            LibraryModule(name: "image", summary: "Image I/O: read, save, display numpy arrays as images",
                importLine: "from matplotlib.image import imread, imsave",
                items: ["imread", "imsave", "AxesImage"],
                example: "import matplotlib.pyplot as plt\nimport numpy as np\n# Create and display a random image\nimg = np.random.rand(100, 100, 3)\nplt.imshow(img)\nplt.axis('off'); plt.title('Random Image'); plt.show()"),
            LibraryModule(name: "mplot3d", summary: "3D axes: surface, wireframe, scatter, bar, contour",
                importLine: "from mpl_toolkits.mplot3d import Axes3D",
                items: ["Axes3D", "ax.plot_surface", "ax.plot_wireframe", "ax.scatter", "ax.plot", "ax.bar3d", "ax.plot_trisurf", "ax.contour", "ax.contourf", "ax.set_zlabel", "ax.set_zlim", "ax.view_init", "ax.dist"],
                example: "import matplotlib.pyplot as plt\nimport numpy as np\nfig = plt.figure(figsize=(10, 7))\nax = fig.add_subplot(111, projection='3d')\nt = np.linspace(0, 4*np.pi, 200)\nax.plot(np.cos(t), np.sin(t), t, 'b-', linewidth=2)\nax.set_xlabel('X'); ax.set_ylabel('Y'); ax.set_zlabel('Z')\nplt.show()")
        ])
    }

    // MARK: SymPy
    private static var sympySection: LibrarySection {
        LibrarySection(name: "sympy", icon: "x.squareroot", modules: [
            LibraryModule(name: "core", summary: "Symbols, constants, expression manipulation, simplification",
                importLine: "from sympy import symbols, simplify, expand, factor, Rational, pi, E, I, oo",
                items: ["symbols", "Symbol", "Rational", "Integer", "Float", "pi", "E", "I", "oo", "zoo", "nan", "S.Half", "S.One", "S.Zero", "GoldenRatio", "EulerGamma", "Catalan", "simplify", "expand", "factor", "collect", "cancel", "apart", "together", "radsimp", "powsimp", "trigsimp", "logcombine", "nsimplify", "cse", "subs", "evalf", "N", "rewrite", "as_numer_denom", "coeff", "degree", "Poly"],
                example: "from sympy import symbols, simplify, expand, factor, Rational, pi\nx, y = symbols('x y')\nexpr = (x + y)**3\nprint('Expanded:', expand(expr))\nprint('Factored:', factor(x**3 - 1))\nprint('Simplified:', simplify(x**2/x))\nprint('pi to 50 digits:', pi.evalf(50))"),
            LibraryModule(name: "solvers", summary: "Solve equations, systems, ODEs, PDEs, inequalities",
                importLine: "from sympy import solve, solveset, dsolve, Eq, linsolve",
                items: ["solve", "solveset", "linsolve", "nonlinsolve", "nsolve", "roots", "real_roots", "dsolve", "pdsolve", "checkodesol", "reduce_inequalities", "diophantine", "Eq"],
                example: "from sympy import symbols, solve, Eq, dsolve, Function\nx, y = symbols('x y')\n# Algebraic equations\nprint('Quadratic:', solve(x**2 - 5*x + 6, x))\nprint('System:', solve([x + y - 5, x - y - 1], [x, y]))\n# ODE: y'' + y = 0\nf = Function('f')\node_sol = dsolve(f(x).diff(x, 2) + f(x), f(x))\nprint('ODE:', ode_sol)"),
            LibraryModule(name: "calculus", summary: "Derivatives, integrals, limits, series, summation",
                importLine: "from sympy import diff, integrate, limit, series, summation, oo",
                items: ["diff", "Derivative", "integrate", "Integral", "limit", "series", "summation", "product", "sequence", "fourier_series", "singularities", "is_increasing", "is_decreasing", "minimum", "maximum"],
                example: "from sympy import symbols, diff, integrate, limit, series, sin, oo\nx = symbols('x')\nprint('d/dx sin(x):', diff(sin(x), x))\nprint('Integral:', integrate(sin(x)**2, x))\nprint('Definite:', integrate(sin(x), (x, 0, oo)))\nprint('Limit:', limit(sin(x)/x, x, 0))\nprint('Series:', series(sin(x), x, 0, n=6))"),
            LibraryModule(name: "matrices", summary: "Symbolic matrices: det, inverse, eigenvalues, decompositions",
                importLine: "from sympy import Matrix, eye, zeros, ones, diag",
                items: ["Matrix", "eye", "zeros", "ones", "diag", "M.det", "M.inv", "M.transpose", "M.adjugate", "M.cofactor", "M.eigenvals", "M.eigenvects", "M.diagonalize", "M.jordan_form", "M.rref", "M.rank", "M.nullspace", "M.columnspace", "M.rowspace", "M.norm", "M.trace", "M.cholesky", "M.LUdecomposition", "M.QRdecomposition", "M.singular_values", "M.condition_number", "M.exp", "M.applyfunc", "M.cross", "M.dot"],
                example: "from sympy import Matrix, symbols\nx = symbols('x')\nM = Matrix([[1, 2], [3, 4]])\nprint('Det:', M.det())\nprint('Inv:', M.inv())\nprint('Eigenvals:', M.eigenvals())\nprint('RREF:', M.rref())\nprint('Nullspace:', M.nullspace())\n# Symbolic matrix\nA = Matrix([[x, 1], [0, x]])\nprint('Char poly:', A.charpoly(x))"),
            LibraryModule(name: "functions", summary: "Trig, exponential, combinatorial, special functions, piecewise",
                importLine: "from sympy import sin, cos, exp, log, sqrt, gamma, factorial, Piecewise",
                items: ["sin", "cos", "tan", "cot", "sec", "csc", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "exp", "log", "ln", "LambertW", "sqrt", "cbrt", "root", "Abs", "sign", "factorial", "binomial", "fibonacci", "lucas", "harmonic", "bernoulli", "euler", "catalan", "bell", "stirling", "gamma", "loggamma", "digamma", "beta", "zeta", "erf", "erfc", "besselj", "bessely", "legendreP", "hermite", "laguerre", "chebyshevt", "hyper", "Piecewise", "Heaviside", "DiracDelta", "floor", "ceiling", "Min", "Max", "re", "im", "conjugate"],
                example: "from sympy import symbols, sin, cos, simplify, factorial, gamma, Piecewise\nx = symbols('x')\nprint('Trig identity:', simplify(sin(x)**2 + cos(x)**2))\nprint('10!:', factorial(10))\nprint('Gamma(5):', gamma(5))\nf = Piecewise((x**2, x < 0), (x, True))\nprint('Piecewise at -2:', f.subs(x, -2))"),
            LibraryModule(name: "number theory", summary: "Primes, factorization, divisors, modular arithmetic",
                importLine: "from sympy import isprime, factorint, divisors, totient, nextprime",
                items: ["isprime", "nextprime", "prevprime", "prime", "primerange", "primepi", "factorint", "divisors", "divisor_count", "divisor_sigma", "totient", "reduced_totient", "mobius", "gcd", "lcm", "mod_inverse", "is_quad_residue", "legendre_symbol", "jacobi_symbol", "discrete_log", "continued_fraction_periodic", "egyptian_fraction", "npartitions"],
                example: "from sympy import isprime, factorint, divisors, totient, primerange\nprint('Is 97 prime?', isprime(97))\nprint('Factor 360:', factorint(360))\nprint('Divisors of 60:', divisors(60))\nprint('Totient(12):', totient(12))\nprint('Primes 1-50:', list(primerange(1, 50)))"),
            LibraryModule(name: "geometry", summary: "2D/3D geometric objects: points, lines, circles, polygons",
                importLine: "from sympy.geometry import Point, Line, Circle, Triangle, Polygon",
                items: ["Point", "Point3D", "Line", "Ray", "Segment", "Circle", "Ellipse", "Triangle", "Polygon", "RegularPolygon", "Curve", "Plane"],
                example: "from sympy.geometry import Point, Triangle, Circle\nt = Triangle(Point(0, 0), Point(4, 0), Point(2, 3))\nprint('Area:', t.area)\nprint('Perimeter:', t.perimeter)\nprint('Centroid:', t.centroid)\nc = Circle(Point(0, 0), 5)\nprint('Circle area:', c.area)"),
            LibraryModule(name: "combinatorics", summary: "Permutations, groups, partitions, Gray codes",
                importLine: "from sympy.combinatorics import Permutation, SymmetricGroup",
                items: ["Permutation", "PermutationGroup", "SymmetricGroup", "CyclicGroup", "DihedralGroup", "AlternatingGroup", "Partition", "IntegerPartition", "Subset", "GrayCode"],
                example: "from sympy.combinatorics import Permutation, SymmetricGroup\np = Permutation([1, 0, 3, 2])\nprint('Cycles:', p.cyclic_form)\nprint('Order:', p.order())\nS3 = SymmetricGroup(3)\nprint('S3 order:', S3.order())"),
            LibraryModule(name: "stats", summary: "Symbolic random variables: distributions, expectation, variance",
                importLine: "from sympy.stats import Normal, E, variance, P, density",
                items: ["Normal", "Uniform", "Exponential", "Poisson", "Bernoulli", "Binomial", "Beta", "Gamma", "P", "E", "variance", "std", "covariance", "density", "cdf", "moment", "median", "sample"],
                example: "from sympy.stats import Normal, E, variance, P\nfrom sympy import symbols\nX = Normal('X', 0, 1)  # standard normal\nprint('E[X]:', E(X))\nprint('Var(X):', variance(X))\nprint('P(X > 1):', P(X > 1))"),
            LibraryModule(name: "logic", summary: "Boolean logic: And, Or, Not, satisfiability, truth tables",
                importLine: "from sympy.logic.boolalg import And, Or, Not, satisfiable",
                items: ["And", "Or", "Not", "Implies", "Equivalent", "Xor", "satisfiable", "simplify_logic", "SOPform", "POSform", "truth_table"],
                example: "from sympy import symbols\nfrom sympy.logic.boolalg import And, Or, Not, satisfiable, simplify_logic\na, b, c = symbols('a b c')\nexpr = And(Or(a, b), Not(And(a, b)))\nprint('Simplified:', simplify_logic(expr))\nprint('Satisfiable:', satisfiable(expr))"),
            LibraryModule(name: "sets", summary: "Symbolic sets: intervals, finite sets, unions, intersections",
                importLine: "from sympy import FiniteSet, Interval, S, Union, Intersection",
                items: ["FiniteSet", "Interval", "Interval.open", "S.Reals", "S.Integers", "S.Naturals", "S.Naturals0", "S.Complexes", "S.EmptySet", "S.UniversalSet", "Union", "Intersection", "Complement", "SymmetricDifference", "ProductSet", "ImageSet", "ConditionSet"],
                example: "from sympy import FiniteSet, Interval, S, Union, Intersection\nA = FiniteSet(1, 2, 3, 4, 5)\nB = Interval(3, 7)\nprint('A & B:', Intersection(A, B))\nprint('A | [0,2]:', Union(A, Interval(0, 2)))\nprint('Reals \\\\ Integers:', S.Reals - S.Integers)"),
            LibraryModule(name: "printing", summary: "LaTeX, MathML, C/Fortran/JS code generation",
                importLine: "from sympy import latex, pretty, ccode, fcode",
                items: ["latex", "pretty", "mathml", "srepr", "ccode", "fcode", "jscode", "python"],
                example: "from sympy import symbols, latex, sqrt, sin\nx = symbols('x')\nexpr = sqrt(x**2 + 1) / sin(x)\nprint('LaTeX:', latex(expr))\nprint('Pretty:', expr)"),
            LibraryModule(name: "physics", summary: "Units, mechanics, quantum, optics, vector algebra",
                importLine: "from sympy.physics.units import meter, second, kg, convert_to",
                items: ["physics.units", "physics.mechanics", "physics.quantum", "physics.optics", "physics.vector", "physics.hydrogen", "physics.paulialgebra", "physics.wigner"],
                example: "from sympy.physics.units import meter, second, convert_to, kg\nspeed = 100 * meter / second\nprint(convert_to(speed, [meter, second]))\nforce = 10 * kg * meter / second**2\nprint('Force:', force)")
        ])
    }

    // MARK: NetworkX
    private static var networkxSection: LibrarySection {
        LibrarySection(name: "networkx", icon: "point.3.connected.trianglepath.dotted", modules: [
            LibraryModule(name: "graph types", summary: "Graph, DiGraph, MultiGraph, MultiDiGraph",
                importLine: "import networkx as nx",
                items: ["nx.Graph", "nx.DiGraph", "nx.MultiGraph", "nx.MultiDiGraph", "G.add_node", "G.add_nodes_from", "G.add_edge", "G.add_edges_from", "G.add_weighted_edges_from", "G.nodes", "G.edges", "G.degree", "G.neighbors", "G.has_node", "G.has_edge", "G.successors", "G.predecessors", "G.in_degree", "G.out_degree"],
                example: "import networkx as nx\nG = nx.Graph()\nG.add_nodes_from([1, 2, 3, 4])\nG.add_weighted_edges_from([(1, 2, 3.5), (2, 3, 1.0), (3, 4, 2.0)])\nprint('Nodes:', G.number_of_nodes(), 'Edges:', G.number_of_edges())\nprint('Degree of 2:', G.degree(2))"),
            LibraryModule(name: "classic generators", summary: "Complete, cycle, path, star, grid, platonic, and named graphs",
                importLine: "import networkx as nx",
                items: ["nx.complete_graph", "nx.cycle_graph", "nx.path_graph", "nx.star_graph", "nx.wheel_graph", "nx.grid_2d_graph", "nx.grid_graph", "nx.hypercube_graph", "nx.complete_bipartite_graph", "nx.circular_ladder_graph", "nx.ladder_graph", "nx.petersen_graph", "nx.tutte_graph", "nx.dodecahedral_graph", "nx.icosahedral_graph", "nx.octahedral_graph", "nx.cubical_graph", "nx.karate_club_graph", "nx.les_miserables_graph", "nx.balanced_tree", "nx.full_rary_tree", "nx.binomial_tree"],
                example: "import networkx as nx\nG = nx.karate_club_graph()\nprint('Karate club: nodes=%d edges=%d' % (G.number_of_nodes(), G.number_of_edges()))\ngrid = nx.grid_2d_graph(10, 10)\nprint('10x10 grid: nodes=%d edges=%d' % (grid.number_of_nodes(), grid.number_of_edges()))"),
            LibraryModule(name: "random generators", summary: "Erdos-Renyi, Barabasi-Albert, Watts-Strogatz, and more",
                importLine: "import networkx as nx",
                items: ["nx.erdos_renyi_graph", "nx.gnm_random_graph", "nx.barabasi_albert_graph", "nx.watts_strogatz_graph", "nx.newman_watts_strogatz_graph", "nx.powerlaw_cluster_graph", "nx.random_regular_graph", "nx.random_geometric_graph", "nx.stochastic_block_model", "nx.random_tree", "nx.random_lobster"],
                example: "import networkx as nx\n# Scale-free network\nba = nx.barabasi_albert_graph(500, 3, seed=42)\nprint('BA: nodes=%d, edges=%d' % (ba.number_of_nodes(), ba.number_of_edges()))\n# Small-world\nws = nx.watts_strogatz_graph(500, 6, 0.3, seed=42)\nprint('WS clustering:', nx.average_clustering(ws))"),
            LibraryModule(name: "shortest paths", summary: "Dijkstra, Bellman-Ford, Floyd-Warshall, A* algorithms",
                importLine: "import networkx as nx",
                items: ["nx.shortest_path", "nx.shortest_path_length", "nx.all_shortest_paths", "nx.all_pairs_shortest_path", "nx.all_pairs_shortest_path_length", "nx.dijkstra_path", "nx.dijkstra_path_length", "nx.bellman_ford_path", "nx.floyd_warshall", "nx.astar_path", "nx.average_shortest_path_length", "nx.has_path"],
                example: "import networkx as nx\nG = nx.grid_2d_graph(10, 10)\npath = nx.shortest_path(G, (0,0), (9,9))\nprint('Path length:', len(path))\nprint('Dijkstra dist:', nx.dijkstra_path_length(G, (0,0), (9,9)))\nprint('Has path:', nx.has_path(G, (0,0), (9,9)))"),
            LibraryModule(name: "connectivity", summary: "Connected components, bridges, articulation points, cuts",
                importLine: "import networkx as nx",
                items: ["nx.is_connected", "nx.connected_components", "nx.number_connected_components", "nx.node_connectivity", "nx.edge_connectivity", "nx.is_strongly_connected", "nx.strongly_connected_components", "nx.is_weakly_connected", "nx.weakly_connected_components", "nx.is_biconnected", "nx.articulation_points", "nx.bridges", "nx.minimum_node_cut", "nx.minimum_edge_cut"],
                example: "import networkx as nx\nG = nx.erdos_renyi_graph(100, 0.05, seed=42)\nprint('Connected:', nx.is_connected(G))\ncomps = list(nx.connected_components(G))\nprint('Components:', len(comps))\nprint('Largest component:', max(len(c) for c in comps))"),
            LibraryModule(name: "centrality", summary: "Degree, betweenness, closeness, eigenvector, PageRank, HITS",
                importLine: "import networkx as nx",
                items: ["nx.degree_centrality", "nx.in_degree_centrality", "nx.out_degree_centrality", "nx.betweenness_centrality", "nx.edge_betweenness_centrality", "nx.closeness_centrality", "nx.eigenvector_centrality", "nx.katz_centrality", "nx.pagerank", "nx.hits", "nx.harmonic_centrality", "nx.load_centrality", "nx.percolation_centrality", "nx.current_flow_betweenness_centrality", "nx.information_centrality"],
                example: "import networkx as nx\nG = nx.karate_club_graph()\npr = nx.pagerank(G, alpha=0.85)\nbc = nx.betweenness_centrality(G)\ntop_pr = sorted(pr, key=pr.get, reverse=True)[:5]\ntop_bc = sorted(bc, key=bc.get, reverse=True)[:5]\nprint('Top PageRank:', top_pr)\nprint('Top Betweenness:', top_bc)"),
            LibraryModule(name: "clustering & structure", summary: "Clustering coefficients, diameter, planarity, cliques, DAG",
                importLine: "import networkx as nx",
                items: ["nx.clustering", "nx.average_clustering", "nx.transitivity", "nx.triangles", "nx.square_clustering", "nx.diameter", "nx.radius", "nx.eccentricity", "nx.center", "nx.periphery", "nx.density", "nx.is_eulerian", "nx.is_tree", "nx.is_forest", "nx.is_planar", "nx.is_bipartite", "nx.is_directed_acyclic_graph", "nx.degree_histogram", "nx.degree_assortativity_coefficient", "nx.k_core", "nx.rich_club_coefficient", "nx.find_cliques"],
                example: "import networkx as nx\nG = nx.erdos_renyi_graph(50, 0.3, seed=42)\nprint('Clustering:', nx.average_clustering(G))\nprint('Density:', nx.density(G))\nprint('Diameter:', nx.diameter(G))\nprint('Planar:', nx.is_planar(G))\ncliques = list(nx.find_cliques(G))\nprint('Max clique size:', max(len(c) for c in cliques))"),
            LibraryModule(name: "community", summary: "Community detection: Louvain, Girvan-Newman, label propagation",
                importLine: "from networkx.community import louvain_communities, greedy_modularity_communities",
                items: ["nx.community.greedy_modularity_communities", "nx.community.louvain_communities", "nx.community.label_propagation_communities", "nx.community.asyn_lpa_communities", "nx.community.girvan_newman", "nx.community.kernighan_lin_bisection", "nx.community.modularity"],
                example: "import networkx as nx\nG = nx.karate_club_graph()\ncomms = list(nx.community.louvain_communities(G, seed=42))\nprint('Communities:', len(comms))\nmod = nx.community.modularity(G, comms)\nprint('Modularity:', mod)"),
            LibraryModule(name: "spanning trees & flows", summary: "MST, max flow, min cut, matching",
                importLine: "import networkx as nx",
                items: ["nx.minimum_spanning_tree", "nx.maximum_spanning_tree", "nx.minimum_spanning_edges", "nx.maximum_flow", "nx.maximum_flow_value", "nx.minimum_cut", "nx.minimum_cut_value", "nx.cost_of_flow", "nx.max_weight_matching"],
                example: "import networkx as nx\nG = nx.complete_graph(10)\nfor u, v in G.edges():\n    G[u][v]['weight'] = abs(u - v)\nmst = nx.minimum_spanning_tree(G)\nprint('MST edges:', mst.number_of_edges())\nprint('MST weight:', sum(d['weight'] for _, _, d in mst.edges(data=True)))"),
            LibraryModule(name: "traversal", summary: "BFS, DFS, topological sort, ancestors, descendants",
                importLine: "import networkx as nx",
                items: ["nx.bfs_tree", "nx.bfs_edges", "nx.bfs_layers", "nx.dfs_tree", "nx.dfs_edges", "nx.dfs_preorder_nodes", "nx.dfs_postorder_nodes", "nx.topological_sort", "nx.topological_generations", "nx.all_topological_sorts", "nx.ancestors", "nx.descendants"],
                example: "import networkx as nx\nG = nx.DiGraph([(1,2), (1,3), (2,4), (3,4), (4,5)])\nprint('Topo sort:', list(nx.topological_sort(G)))\nprint('BFS from 1:', list(nx.bfs_edges(G, 1)))\nprint('Descendants of 1:', nx.descendants(G, 1))"),
            LibraryModule(name: "graph operations", summary: "Union, intersection, complement, product, relabel",
                importLine: "import networkx as nx",
                items: ["nx.compose", "nx.union", "nx.disjoint_union", "nx.intersection", "nx.difference", "nx.symmetric_difference", "nx.cartesian_product", "nx.tensor_product", "nx.complement", "nx.reverse", "nx.subgraph", "nx.line_graph", "nx.power", "nx.relabel_nodes", "nx.convert_node_labels_to_integers", "G.to_directed", "G.to_undirected", "nx.freeze"],
                example: "import networkx as nx\nG1 = nx.cycle_graph(5)\nG2 = nx.path_graph(5)\nG_comp = nx.compose(G1, G2)\nprint('Composed: nodes=%d edges=%d' % (G_comp.number_of_nodes(), G_comp.number_of_edges()))\nG_compl = nx.complement(G1)\nprint('Complement edges:', G_compl.number_of_edges())"),
            LibraryModule(name: "link prediction", summary: "PageRank, HITS, SimRank, Jaccard, Adamic-Adar",
                importLine: "import networkx as nx",
                items: ["nx.pagerank", "nx.hits", "nx.simrank_similarity", "nx.jaccard_coefficient", "nx.adamic_adar_index", "nx.preferential_attachment", "nx.resource_allocation_index", "nx.common_neighbor_centrality"],
                example: "import networkx as nx\nG = nx.karate_club_graph()\npreds = list(nx.jaccard_coefficient(G, [(0, 33)]))\nfor u, v, p in preds:\n    print(f'Jaccard({u},{v}) = {p:.3f}')\nhubs, auth = nx.hits(G)\nprint('Top hub:', max(hubs, key=hubs.get))"),
            LibraryModule(name: "I/O & conversion", summary: "Convert to/from numpy, edge lists, adjacency, Laplacian",
                importLine: "import networkx as nx",
                items: ["nx.to_numpy_array", "nx.from_numpy_array", "nx.to_dict_of_lists", "nx.from_dict_of_lists", "nx.to_edgelist", "nx.from_edgelist", "nx.adjacency_matrix", "nx.incidence_matrix", "nx.laplacian_matrix", "nx.normalized_laplacian_matrix", "nx.algebraic_connectivity"],
                example: "import networkx as nx\nimport numpy as np\nG = nx.cycle_graph(5)\nA = nx.to_numpy_array(G)\nprint('Adjacency:\\n', A)\nL = nx.laplacian_matrix(G).toarray()\nprint('Laplacian:\\n', L)\nprint('Algebraic connectivity:', nx.algebraic_connectivity(G))")
        ])
    }

    // MARK: PIL
    private static var pilSection: LibrarySection {
        LibrarySection(name: "PIL", icon: "photo", modules: [
            LibraryModule(name: "Image (creation & I/O)", summary: "Create, open, save, blend, composite images",
                importLine: "from PIL import Image",
                items: ["Image.new", "Image.open", "img.save", "img.copy", "Image.fromarray", "Image.frombytes", "Image.merge", "Image.blend", "Image.composite", "Image.alpha_composite", "Image.eval"],
                example: "from PIL import Image\nimport numpy as np\n# Create from numpy array\narr = np.random.randint(0, 255, (200, 300, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nprint('Mode:', img.mode, 'Size:', img.size)\nimg.save('/tmp/test.png')\n# Blend two images\nimg2 = Image.new('RGB', (300, 200), 'blue')\nblended = Image.blend(img, img2, alpha=0.5)"),
            LibraryModule(name: "Image (transforms)", summary: "Resize, crop, rotate, transpose, paste, affine transform",
                importLine: "from PIL import Image",
                items: ["img.resize", "img.thumbnail", "img.crop", "img.rotate", "img.transpose", "img.transform", "img.paste", "img.offset", "img.convert", "img.split", "img.getchannel", "img.point", "img.quantize", "img.putpalette"],
                example: "from PIL import Image\nimport numpy as np\narr = np.random.randint(0, 255, (200, 300, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\ncropped = img.crop((50, 50, 250, 150))  # (left, top, right, bottom)\nrotated = img.rotate(45, expand=True)\nflipped = img.transpose(Image.FLIP_LEFT_RIGHT)\nresized = img.resize((100, 100), Image.LANCZOS)\nprint('Cropped:', cropped.size, 'Rotated:', rotated.size)"),
            LibraryModule(name: "Image (pixel access)", summary: "Get/set pixels, histogram, bounding box, properties",
                importLine: "from PIL import Image",
                items: ["img.getpixel", "img.putpixel", "img.load", "img.tobytes", "img.getdata", "img.putdata", "img.histogram", "img.getextrema", "img.getbbox", "img.size", "img.width", "img.height", "img.mode", "img.format", "img.info"],
                example: "from PIL import Image\nimport numpy as np\narr = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\npx = img.getpixel((50, 50))\nprint('Pixel at (50,50):', px)\nhist = img.histogram()\nprint('Histogram length:', len(hist))\nprint('Extrema:', img.getextrema())"),
            LibraryModule(name: "ImageDraw", summary: "Draw shapes, text, lines, polygons, flood fill",
                importLine: "from PIL import Image, ImageDraw",
                items: ["ImageDraw.Draw", "draw.line", "draw.rectangle", "draw.rounded_rectangle", "draw.ellipse", "draw.polygon", "draw.regular_polygon", "draw.arc", "draw.chord", "draw.pieslice", "draw.point", "draw.text", "draw.multiline_text", "draw.textbbox", "draw.textlength", "draw.bitmap", "draw.floodfill"],
                example: "from PIL import Image, ImageDraw\nimg = Image.new('RGB', (400, 300), 'white')\ndraw = ImageDraw.Draw(img)\ndraw.rectangle([50, 50, 350, 250], outline='blue', width=3)\ndraw.ellipse([100, 75, 300, 225], fill='lightblue', outline='navy')\ndraw.polygon([(200, 60), (350, 200), (50, 200)], fill='rgba(255,0,0,128)', outline='red')\ndraw.text((150, 130), 'Hello!', fill='black')\nimg.save('/tmp/shapes.png')"),
            LibraryModule(name: "ImageFilter", summary: "Blur, sharpen, edge detect, emboss, median, custom kernels",
                importLine: "from PIL import ImageFilter",
                items: ["BLUR", "CONTOUR", "DETAIL", "EDGE_ENHANCE", "EDGE_ENHANCE_MORE", "EMBOSS", "FIND_EDGES", "SHARPEN", "SMOOTH", "SMOOTH_MORE", "GaussianBlur", "BoxBlur", "UnsharpMask", "MedianFilter", "MinFilter", "MaxFilter", "ModeFilter", "RankFilter", "Kernel"],
                example: "from PIL import Image, ImageFilter\nimport numpy as np\narr = np.random.randint(0, 255, (200, 200, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nblurred = img.filter(ImageFilter.GaussianBlur(5))\nedges = img.filter(ImageFilter.FIND_EDGES)\nsharp = img.filter(ImageFilter.UnsharpMask(radius=2, percent=150, threshold=3))\n# Custom kernel\ncustom = img.filter(ImageFilter.Kernel((3,3), [-1,-1,-1,-1,9,-1,-1,-1,-1], scale=1))"),
            LibraryModule(name: "ImageEnhance", summary: "Adjust brightness, contrast, color saturation, sharpness",
                importLine: "from PIL import ImageEnhance",
                items: ["ImageEnhance.Brightness", "ImageEnhance.Contrast", "ImageEnhance.Color", "ImageEnhance.Sharpness"],
                example: "from PIL import Image, ImageEnhance\nimport numpy as np\narr = np.random.randint(0, 255, (200, 200, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nbright = ImageEnhance.Brightness(img).enhance(1.5)\ncontrast = ImageEnhance.Contrast(img).enhance(2.0)\ncolor = ImageEnhance.Color(img).enhance(0.0)  # grayscale\nsharp = ImageEnhance.Sharpness(img).enhance(3.0)"),
            LibraryModule(name: "ImageOps", summary: "Auto-contrast, equalize, flip, mirror, pad, fit, colorize",
                importLine: "from PIL import ImageOps",
                items: ["ImageOps.autocontrast", "ImageOps.equalize", "ImageOps.flip", "ImageOps.mirror", "ImageOps.invert", "ImageOps.grayscale", "ImageOps.posterize", "ImageOps.solarize", "ImageOps.colorize", "ImageOps.pad", "ImageOps.fit", "ImageOps.contain", "ImageOps.expand", "ImageOps.crop", "ImageOps.exif_transpose"],
                example: "from PIL import Image, ImageOps\nimport numpy as np\narr = np.random.randint(0, 255, (200, 300, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nimg_eq = ImageOps.equalize(img)\nimg_gray = ImageOps.grayscale(img)\nimg_poster = ImageOps.posterize(img, bits=2)\nimg_padded = ImageOps.pad(img, (400, 400), color='red')"),
            LibraryModule(name: "ImageChops", summary: "Channel operations: add, subtract, multiply, screen, difference",
                importLine: "from PIL import ImageChops",
                items: ["ImageChops.add", "ImageChops.subtract", "ImageChops.multiply", "ImageChops.screen", "ImageChops.difference", "ImageChops.lighter", "ImageChops.darker", "ImageChops.invert", "ImageChops.offset", "ImageChops.overlay"],
                example: "from PIL import Image, ImageChops\nimport numpy as np\narr1 = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\narr2 = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\nim1, im2 = Image.fromarray(arr1), Image.fromarray(arr2)\ndiff = ImageChops.difference(im1, im2)\nscreen = ImageChops.screen(im1, im2)\nprint('Diff extrema:', diff.getextrema())"),
            LibraryModule(name: "ImageFont & Color & Stat", summary: "Font loading, color names, image statistics",
                importLine: "from PIL import ImageFont, ImageColor, ImageStat",
                items: ["ImageFont.truetype", "ImageFont.load_default", "ImageColor.getrgb", "ImageStat.Stat", "stat.mean", "stat.median", "stat.stddev", "stat.extrema", "stat.count", "stat.sum", "stat.var"],
                example: "from PIL import Image, ImageStat, ImageColor\nimport numpy as np\narr = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nstat = ImageStat.Stat(img)\nprint('Mean per band:', stat.mean)\nprint('Std per band:', stat.stddev)\nprint('Red RGB:', ImageColor.getrgb('red'))\nprint('Hex:', ImageColor.getrgb('#ff8800'))")
        ])
    }

    // MARK: Manim
    private static var manimSection: LibrarySection {
        LibrarySection(name: "manim", icon: "film", modules: [
            LibraryModule(name: "Scene", summary: "Base class for all animations, manages timeline",
                importLine: "from manim import Scene",
                items: ["Scene", "construct", "play", "wait", "add", "remove", "clear", "ThreeDScene", "MovingCameraScene"],
                example: "from manim import *\nclass MyScene(Scene):\n    def construct(self):\n        circle = Circle(color=BLUE)\n        self.play(Create(circle))\n        self.play(circle.animate.shift(RIGHT*2))\n        self.wait()"),
            LibraryModule(name: "Mobject", summary: "Mathematical objects: shapes, text, groups",
                importLine: "from manim import Circle, Square, VGroup, MathTex",
                items: ["Circle", "Square", "Line", "Arrow", "Dot", "VGroup", "MathTex", "Text", "Axes", "NumberPlane", "Graph"],
                example: "from manim import *\nclass Shapes(Scene):\n    def construct(self):\n        shapes = VGroup(\n            Circle(color=RED),\n            Square(color=GREEN),\n            Triangle(color=BLUE)\n        ).arrange(RIGHT, buff=1)\n        self.play(Create(shapes))"),
            LibraryModule(name: "Animation", summary: "Built-in animation types: Create, Transform, Fade",
                importLine: "from manim import Create, Transform, FadeIn, FadeOut",
                items: ["Create", "Uncreate", "Transform", "ReplacementTransform", "FadeIn", "FadeOut", "Write", "GrowFromCenter", "Indicate", "Rotate"],
                example: "from manim import *\nclass Transforms(Scene):\n    def construct(self):\n        sq = Square()\n        ci = Circle()\n        self.play(Create(sq))\n        self.play(Transform(sq, ci))\n        self.play(FadeOut(sq))"),
            LibraryModule(name: "Camera", summary: "Camera control for panning, zooming, 3D views",
                importLine: "from manim import MovingCameraScene, ThreeDScene",
                items: ["MovingCameraScene", "ThreeDScene", "set_camera_orientation", "begin_ambient_camera_rotation", "move_camera"],
                example: "from manim import *\nclass CamScene(MovingCameraScene):\n    def construct(self):\n        sq = Square()\n        self.play(Create(sq))\n        self.play(self.camera.frame.animate.scale(0.5).move_to(sq))"),
            LibraryModule(name: "Text", summary: "Text rendering with fonts, LaTeX math, markup",
                importLine: "from manim import Text, MathTex, Tex",
                items: ["Text", "MathTex", "Tex", "MarkupText", "Title", "BulletedList", "Code"],
                example: "from manim import *\nclass TextDemo(Scene):\n    def construct(self):\n        title = Text('Hello Manim', font_size=48)\n        eq = MathTex(r'e^{i\\pi} + 1 = 0')\n        VGroup(title, eq).arrange(DOWN)\n        self.play(Write(title), Write(eq))")
        ])
    }

    // MARK: C Interpreter
    private static var cSection: LibrarySection {
        LibrarySection(name: "C interpreter", icon: "c.square", modules: [
            LibraryModule(name: "data types", summary: "int, float, double, char, struct, union, enum, pointers, arrays",
                importLine: "// Supported: int, float, double, char, _Bool, struct, union, enum, pointers, 2D arrays",
                items: ["int", "long", "long long", "short", "unsigned", "float", "double", "char", "void", "_Bool", "int[]", "int[][]", "struct", "union", "enum", "typedef", "int *", "int (*)(int,int)"],
                example: "#include <stdio.h>\n#include <math.h>\nstruct Point { double x; double y; };\ndouble distance(struct Point a, struct Point b) {\n    double dx = a.x - b.x, dy = a.y - b.y;\n    return sqrt(dx*dx + dy*dy);\n}\nint main() {\n    struct Point p1 = {3.0, 4.0};\n    struct Point p2 = (struct Point){7.0, 1.0};\n    printf(\"Distance: %.4f\\n\", distance(p1, p2));\n    return 0;\n}", language: "c"),
            LibraryModule(name: "operators (48)", summary: "Arithmetic, comparison, logical, bitwise, assignment, ternary",
                importLine: "// 48 operators including compound assignment and bitwise",
                items: ["+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=", "&&", "||", "!", "&", "|", "^", "~", "<<", ">>", "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", "++", "--", "?:", "sizeof", "(type)", "[]", ".", "->", ","],
                example: "#include <stdio.h>\nint main() {\n    int a = 10, b = 3;\n    printf(\"a/b=%d a%%b=%d\\n\", a/b, a%b);\n    printf(\"a&b=%d a|b=%d a^b=%d\\n\", a&b, a|b, a^b);\n    printf(\"a<<2=%d a>>1=%d\\n\", a<<2, a>>1);\n    int x = (a > b) ? a : b;\n    printf(\"max=%d sizeof(int)=%lu\\n\", x, sizeof(int));\n    return 0;\n}", language: "c"),
            LibraryModule(name: "control flow", summary: "if/else, for, while, do-while, switch, goto, break, continue",
                importLine: "// Full control flow with 1M iteration limits on loops",
                items: ["if/else if/else", "for", "while", "do-while", "switch/case/default", "break", "continue", "return", "goto", "label:"],
                example: "#include <stdio.h>\nint main() {\n    // Switch with fall-through\n    int x = 2;\n    switch (x) {\n        case 1: printf(\"one\\n\"); break;\n        case 2: printf(\"two\\n\"); break;\n        default: printf(\"other\\n\");\n    }\n    // Goto for cleanup\n    int *data = malloc(100);\n    if (!data) goto error;\n    free(data);\n    return 0;\nerror:\n    printf(\"alloc failed\\n\");\n    return 1;\n}", language: "c"),
            LibraryModule(name: "functions & pointers", summary: "Functions, recursion, function pointers, callbacks, static vars",
                importLine: "// Functions, recursion, function pointers, static variables",
                items: ["function declaration", "recursion", "function pointers", "callbacks", "forward reference", "output parameters", "static variables", "void functions"],
                example: "#include <stdio.h>\nint add(int a, int b) { return a + b; }\nint sub(int a, int b) { return a - b; }\nint counter() {\n    static int n = 0;\n    return ++n;\n}\nint main() {\n    int (*op)(int, int) = add;\n    printf(\"%d\\n\", op(10, 3));  // 13\n    op = sub;\n    printf(\"%d\\n\", op(10, 3));  // 7\n    for (int i = 0; i < 3; i++) printf(\"%d \", counter()); // 1 2 3\n    return 0;\n}", language: "c"),
            LibraryModule(name: "pointers & memory", summary: "Virtual memory pointers, malloc/free, pointer arithmetic, 2D arrays",
                importLine: "#include <stdlib.h>  // malloc, calloc, realloc, free",
                items: ["&x", "*p", "pointer arithmetic", "malloc", "calloc", "realloc", "free", "NULL", "sizeof", "swap via pointers", "array decay", "2D arrays", "compound assignment on 2D"],
                example: "#include <stdio.h>\n#include <stdlib.h>\nvoid swap(int *a, int *b) { int t = *a; *a = *b; *b = t; }\nint main() {\n    int a = 1, b = 2;\n    swap(&a, &b);\n    printf(\"a=%d b=%d\\n\", a, b);  // 2, 1\n    // 2D matrix multiply\n    int A[2][2] = {1,2,3,4}, B[2][2] = {5,6,7,8}, C[2][2] = {0};\n    for (int i=0;i<2;i++) for (int j=0;j<2;j++) for (int k=0;k<2;k++)\n        C[i][j] += A[i][k]*B[k][j];\n    printf(\"%d %d %d %d\\n\", C[0][0], C[0][1], C[1][0], C[1][1]);\n    return 0;\n}", language: "c"),
            LibraryModule(name: "preprocessor", summary: "Object/function macros, conditional compilation, #ifdef/#if",
                importLine: "#define, #ifdef, #ifndef, #if, #elif, #else, #endif, #undef",
                items: ["#define VALUE", "#define F(x) expr", "#undef", "#ifdef", "#ifndef", "#if EXPR", "#elif", "#else", "#endif", "#include", "#warning"],
                example: "#include <stdio.h>\n#define SQUARE(x) ((x)*(x))\n#define MAX(a,b) ((a)>(b)?(a):(b))\n#define DEBUG\nint main() {\n    printf(\"%d\\n\", SQUARE(5));    // 25\n    printf(\"%d\\n\", MAX(10, 20)); // 20\n    #ifdef DEBUG\n    printf(\"debug mode\\n\");\n    #endif\n    return 0;\n}", language: "c"),
            LibraryModule(name: "stdio & math", summary: "printf/sprintf, math.h functions, string.h, ctype.h",
                importLine: "#include <stdio.h>\n#include <math.h>\n#include <string.h>",
                items: ["printf", "fprintf", "sprintf", "snprintf", "puts", "putchar", "scanf", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "exp", "log", "log2", "log10", "sqrt", "cbrt", "pow", "fabs", "ceil", "floor", "round", "fmod", "fmax", "fmin", "strlen", "strcmp", "strcpy", "strcat", "strstr", "strchr", "strdup", "strtok", "memcmp", "isdigit", "isalpha", "toupper", "tolower", "atoi", "atof", "strtol", "strtod", "rand", "srand", "time", "clock", "qsort", "assert"],
                example: "#include <stdio.h>\n#include <math.h>\n#include <string.h>\nint main() {\n    printf(\"sin(pi/2)=%.4f\\n\", sin(M_PI/2));\n    printf(\"exp(1)=%.4f\\n\", exp(1.0));\n    char buf[100];\n    sprintf(buf, \"x=%d pi=%.2f\", 42, M_PI);\n    printf(\"%s (len=%lu)\\n\", buf, strlen(buf));\n    return 0;\n}", language: "c"),
            LibraryModule(name: "C23 features", summary: "auto, constexpr, typeof, _Static_assert, _Generic, binary literals",
                importLine: "// C23 features supported by the interpreter",
                items: ["auto type inference", "constexpr", "typeof", "_Static_assert", "_Generic", "binary literals (0b)", "digit separators", "[[attributes]]", "bool/true/false"],
                example: "#include <stdio.h>\nint main() {\n    constexpr int SIZE = 10;\n    auto x = 3.14;\n    typeof(x) y = 2.71;\n    int bin = 0b1010'1100;  // binary + digit separator\n    printf(\"x=%.2f y=%.2f bin=%d\\n\", x, y, bin);\n    _Static_assert(sizeof(int) >= 4, \"int too small\");\n    return 0;\n}", language: "c")
        ])
    }

    // MARK: C++ Interpreter
    private static var cppSection: LibrarySection {
        LibrarySection(name: "C++ interpreter", icon: "chevron.left.forwardslash.chevron.right", modules: [
            LibraryModule(name: "classes & OOP", summary: "Classes, inheritance, virtual, constructors, operator overloading",
                importLine: "// class, struct, virtual, override, public/private/protected",
                items: ["class", "struct", "public", "private", "protected", "constructor", "destructor", "copy constructor", "initializer list", "virtual", "pure virtual (=0)", "override", "const member", "this pointer", "friend", "operator+", "operator==", "operator<<", "operator[]", "operator()", "operator++", "operator="],
                example: "#include <iostream>\n#include <cmath>\nclass Point {\n    double x, y;\npublic:\n    Point(double x, double y) : x(x), y(y) {}\n    double dist(const Point& o) const {\n        return sqrt((x-o.x)*(x-o.x) + (y-o.y)*(y-o.y));\n    }\n    Point operator+(const Point& o) const { return Point(x+o.x, y+o.y); }\n    friend std::ostream& operator<<(std::ostream& os, const Point& p) {\n        return os << \"(\" << p.x << \", \" << p.y << \")\";\n    }\n};\nint main() {\n    Point a(3,4), b(7,1);\n    std::cout << \"a+b=\" << (a+b) << \" dist=\" << a.dist(b) << std::endl;\n}", language: "cpp"),
            LibraryModule(name: "inheritance & polymorphism", summary: "Single inheritance, virtual dispatch, abstract classes",
                importLine: "// class Derived : public Base { ... };",
                items: ["public inheritance", "protected inheritance", "virtual functions", "pure virtual", "abstract class", "override", "dynamic dispatch", "base class constructor"],
                example: "#include <iostream>\n#include <string>\n#include <vector>\nclass Shape {\npublic:\n    virtual double area() const = 0;\n    virtual std::string name() const = 0;\n    virtual ~Shape() {}\n};\nclass Circle : public Shape {\n    double r;\npublic:\n    Circle(double r) : r(r) {}\n    double area() const override { return 3.14159*r*r; }\n    std::string name() const override { return \"Circle\"; }\n};\nclass Rect : public Shape {\n    double w, h;\npublic:\n    Rect(double w, double h) : w(w), h(h) {}\n    double area() const override { return w*h; }\n    std::string name() const override { return \"Rect\"; }\n};\nint main() {\n    std::vector<Shape*> shapes = {new Circle(5), new Rect(3,4)};\n    for (auto s : shapes) {\n        std::cout << s->name() << \": \" << s->area() << std::endl;\n        delete s;\n    }\n}", language: "cpp"),
            LibraryModule(name: "STL containers", summary: "string, vector, map, set, pair with full method support",
                importLine: "#include <vector>\n#include <map>\n#include <set>\n#include <string>",
                items: ["std::string", "s.length", "s.substr", "s.find", "s.replace", "s.append", "to_string", "stoi", "stod", "std::vector", "v.push_back", "v.pop_back", "v.size", "v.empty", "v.begin", "v.end", "v.insert", "v.erase", "v.clear", "v.resize", "std::map", "m[key]", "m.find", "m.count", "m.erase", "std::set", "s.insert", "s.count", "s.find", "std::pair", "make_pair"],
                example: "#include <iostream>\n#include <vector>\n#include <map>\n#include <string>\nusing namespace std;\nint main() {\n    vector<int> v = {5, 2, 8, 1, 9};\n    sort(v.begin(), v.end());\n    for (int x : v) cout << x << \" \";\n    cout << endl;\n    map<string, int> m = {{\"Alice\", 95}, {\"Bob\", 87}};\n    for (auto& [k, val] : m) cout << k << \"=\" << val << endl;\n}", language: "cpp"),
            LibraryModule(name: "STL algorithms", summary: "sort, find, count, accumulate, binary_search, transform",
                importLine: "#include <algorithm>\n#include <numeric>",
                items: ["sort", "reverse", "find", "count", "min_element", "max_element", "accumulate", "binary_search", "lower_bound", "upper_bound", "unique", "fill", "copy", "swap", "next_permutation", "for_each", "transform", "remove_if"],
                example: "#include <iostream>\n#include <vector>\n#include <algorithm>\n#include <numeric>\nusing namespace std;\nint main() {\n    vector<int> v = {3, 1, 4, 1, 5, 9, 2, 6};\n    sort(v.begin(), v.end());\n    cout << \"Sum: \" << accumulate(v.begin(), v.end(), 0) << endl;\n    cout << \"Min: \" << *min_element(v.begin(), v.end()) << endl;\n    cout << \"Has 5: \" << binary_search(v.begin(), v.end(), 5) << endl;\n}", language: "cpp"),
            LibraryModule(name: "templates", summary: "Function/class templates with type deduction",
                importLine: "// template<typename T>",
                items: ["function templates", "class templates", "template specialization", "auto type deduction"],
                example: "#include <iostream>\n#include <vector>\nusing namespace std;\ntemplate<typename T>\nclass Stack {\n    vector<T> data;\npublic:\n    void push(T val) { data.push_back(val); }\n    T pop() { T v = data.back(); data.pop_back(); return v; }\n    bool empty() const { return data.empty(); }\n};\nint main() {\n    Stack<int> s;\n    s.push(1); s.push(2); s.push(3);\n    while (!s.empty()) cout << s.pop() << \" \"; // 3 2 1\n    cout << endl;\n}", language: "cpp"),
            LibraryModule(name: "lambdas & modern C++", summary: "Lambdas, auto, range-for, structured bindings, constexpr",
                importLine: "// [capture](params) { body }",
                items: ["lambda []()", "capture by value [=]", "capture by ref [&]", "specific captures", "mutable lambda", "auto type deduction", "range-based for", "structured bindings [key, val]", "constexpr"],
                example: "#include <iostream>\n#include <vector>\n#include <algorithm>\nusing namespace std;\nint main() {\n    vector<int> v = {5, 2, 8, 1, 9};\n    // Lambda sort descending\n    sort(v.begin(), v.end(), [](int a, int b) { return a > b; });\n    // Capture by reference\n    int total = 0;\n    for_each(v.begin(), v.end(), [&total](int x) { total += x; });\n    cout << \"Total: \" << total << endl;\n    // Range-based for\n    for (auto x : v) cout << x << \" \";\n    cout << endl;\n}", language: "cpp"),
            LibraryModule(name: "memory & references", summary: "new/delete, references, namespaces, I/O manipulators",
                importLine: "#include <iostream>\n#include <iomanip>",
                items: ["new T(args)", "new T[n]", "delete ptr", "delete[] arr", "T& ref", "const T&", "pass by reference", "namespace", "using namespace", "cout", "cin", "endl", "setw", "setprecision", "fixed", "scientific", "hex", "oct", "boolalpha"],
                example: "#include <iostream>\n#include <iomanip>\nusing namespace std;\nnamespace Math {\n    constexpr double PI = 3.14159265358979;\n    double area(double r) { return PI * r * r; }\n}\nint main() {\n    cout << fixed << setprecision(4);\n    cout << \"Area(5): \" << Math::area(5.0) << endl;\n    // References\n    int x = 42;\n    int& ref = x;\n    ref = 100;\n    cout << \"x = \" << x << endl;  // 100\n}", language: "cpp"),
            LibraryModule(name: "exceptions", summary: "try/catch/throw, custom exceptions, noexcept",
                importLine: "#include <stdexcept>",
                items: ["try/catch", "throw", "std::exception", "std::runtime_error", "std::logic_error", "catch (...)", "noexcept", "custom exception class"],
                example: "#include <iostream>\n#include <stdexcept>\nusing namespace std;\nclass MyError : public exception {\n    string msg;\npublic:\n    MyError(string m) : msg(m) {}\n    const char* what() const noexcept override { return msg.c_str(); }\n};\nint main() {\n    try {\n        throw MyError(\"custom error\");\n    } catch (const exception& e) {\n        cout << \"Caught: \" << e.what() << endl;\n    }\n}", language: "cpp")
        ])
    }

    // MARK: Fortran Interpreter
    private static var fortranSection: LibrarySection {
        LibrarySection(name: "Fortran interpreter", icon: "f.square", modules: [
            LibraryModule(name: "data types", summary: "INTEGER, REAL, DOUBLE PRECISION, COMPLEX, LOGICAL, CHARACTER",
                importLine: "program main\n  implicit none\n  ! declarations here",
                items: ["INTEGER", "REAL", "DOUBLE PRECISION", "COMPLEX", "LOGICAL", "CHARACTER", "CHARACTER(LEN=n)", "PARAMETER", "INTENT(IN)", "INTENT(OUT)", "INTENT(INOUT)", "ALLOCATABLE", "DIMENSION", "SAVE", "IMPLICIT NONE"],
                example: "program types\n  implicit none\n  integer :: n = 42\n  real :: x = 3.14\n  double precision :: d = 3.14159265358979D0\n  complex :: z = (1.0, 2.0)\n  logical :: flag = .TRUE.\n  character(len=20) :: name = 'Fortran'\n  real, parameter :: PI = 3.14159265358979\n  write(*, '(A,I0,A,F6.2)') 'n=', n, ' x=', x\n  write(*, *) 'z=', z, 'flag=', flag\nend program", language: "fortran"),
            LibraryModule(name: "program structure", summary: "Program, modules, subroutines, functions, USE, CONTAINS",
                importLine: "program main\n  use my_module\n  implicit none\ncontains\n  ...\nend program",
                items: ["PROGRAM", "MODULE", "USE", "IMPLICIT NONE", "CONTAINS", "SUBROUTINE", "FUNCTION", "RESULT", "RECURSIVE", "END PROGRAM", "END MODULE", "END SUBROUTINE", "END FUNCTION", "CALL"],
                example: "module constants\n  implicit none\n  real, parameter :: PI = 3.14159\nend module\nmodule geometry\n  use constants\n  implicit none\ncontains\n  function circle_area(r) result(a)\n    real, intent(in) :: r\n    real :: a\n    a = PI * r * r\n  end function\nend module\nprogram main\n  use geometry\n  implicit none\n  write(*, *) 'Area:', circle_area(5.0)\nend program", language: "fortran"),
            LibraryModule(name: "arrays (up to 7D)", summary: "Static, allocatable, slicing, WHERE, whole-array operations",
                importLine: "integer, dimension(:,:), allocatable :: matrix",
                items: ["DIMENSION(n)", "ALLOCATABLE", "ALLOCATE", "DEALLOCATE", "ALLOCATED", "array slicing a(1:3)", "stride a(::2)", "WHERE/ELSEWHERE", "array initializer [/...//]", "implied DO [(i, i=1,n)]", "whole-array +", "whole-array *", "whole-array **"],
                example: "program arrays\n  implicit none\n  real :: a(5) = [1.0, 2.0, 3.0, 4.0, 5.0]\n  real :: b(5), c(5)\n  real, allocatable :: grid(:,:)\n  b = a ** 2            ! element-wise square\n  where (a > 3.0)\n    c = a\n  elsewhere\n    c = 0.0\n  end where\n  allocate(grid(10, 10))\n  call random_number(grid)\n  write(*, *) 'Sum:', sum(grid)\n  deallocate(grid)\nend program", language: "fortran"),
            LibraryModule(name: "array intrinsics", summary: "SIZE, SHAPE, SUM, MATMUL, DOT_PRODUCT, TRANSPOSE, RESHAPE",
                importLine: "! Array intrinsics are always available",
                items: ["SIZE", "SHAPE", "LBOUND", "UBOUND", "SUM", "PRODUCT", "MAXVAL", "MINVAL", "MAXLOC", "MINLOC", "COUNT", "ANY", "ALL", "MATMUL", "DOT_PRODUCT", "TRANSPOSE", "RESHAPE", "MERGE", "PACK", "UNPACK", "SPREAD", "CSHIFT", "EOSHIFT"],
                example: "program array_ops\n  implicit none\n  real :: A(3,3), B(3,3), C(3,3)\n  integer :: i\n  call random_number(A)\n  call random_number(B)\n  C = matmul(A, B)\n  write(*, *) 'Shape:', shape(C)\n  write(*, *) 'Sum:', sum(C)\n  write(*, *) 'Max:', maxval(C), 'at', maxloc(C)\n  write(*, *) 'Trace:', sum([(C(i,i), i=1,3)])\nend program", language: "fortran"),
            LibraryModule(name: "control flow", summary: "IF/THEN/ELSE, DO loops, DO WHILE, SELECT CASE, EXIT, CYCLE",
                importLine: "! Full control flow with named constructs",
                items: ["IF/THEN/ELSE IF/ELSE/END IF", "DO i = start, stop, step", "DO WHILE (cond)", "DO (infinite)", "EXIT", "CYCLE", "SELECT CASE", "CASE", "CASE DEFAULT", "named DO", "one-line IF"],
                example: "program control\n  implicit none\n  integer :: i, n\n  ! Named DO with CYCLE and EXIT\n  n = 1\n  outer: do i = 1, 100\n    if (mod(i, 3) == 0) cycle outer\n    n = n + i\n    if (n > 100) exit outer\n  end do outer\n  write(*, *) 'n =', n\n  ! SELECT CASE\n  select case (n)\n    case (1:50);   write(*, *) 'Small'\n    case (51:100); write(*, *) 'Medium'\n    case default;  write(*, *) 'Large'\n  end select\nend program", language: "fortran"),
            LibraryModule(name: "subroutines & functions", summary: "SUBROUTINE, FUNCTION, RESULT, RECURSIVE, INTENT, CONTAINS",
                importLine: "subroutine name(args)\n  implicit none\n  ...\nend subroutine",
                items: ["SUBROUTINE", "FUNCTION", "RESULT clause", "RECURSIVE", "INTENT(IN)", "INTENT(OUT)", "INTENT(INOUT)", "CONTAINS", "internal subprograms", "CALL"],
                example: "program funcs\n  implicit none\n  integer :: q, r\n  call divmod(17, 5, q, r)\n  write(*, *) '17/5 =', q, 'rem', r\n  write(*, *) '10! =', factorial(10)\ncontains\n  subroutine divmod(a, b, quot, rem)\n    integer, intent(in) :: a, b\n    integer, intent(out) :: quot, rem\n    quot = a / b\n    rem = mod(a, b)\n  end subroutine\n  recursive function factorial(n) result(f)\n    integer, intent(in) :: n\n    integer :: f\n    if (n <= 1) then; f = 1\n    else; f = n * factorial(n-1)\n    end if\n  end function\nend program", language: "fortran"),
            LibraryModule(name: "I/O & format", summary: "WRITE, PRINT, format descriptors: I, F, E, ES, A, X, /",
                importLine: "write(*, '(A, I0, A, F8.3)') 'n=', n, ' x=', x",
                items: ["WRITE(*,*)", "PRINT *", "format string '(...)'", "I (integer)", "F (fixed float)", "E (scientific)", "ES (engineering)", "G (general)", "A (string)", "L (logical)", "X (spaces)", "/ (newline)", "T (tab)", "repeat count", "grouped format"],
                example: "program io_demo\n  implicit none\n  integer :: i\n  real :: x = 3.14159\n  write(*, '(A)')         'Hello Fortran!'\n  write(*, '(A, F10.4)')  'Pi = ', x\n  write(*, '(A, ES12.4)') 'Sci = ', 12345.6\n  write(*, '(3I5)')       1, 2, 3\n  do i = 1, 5\n    write(*, '(A, I0, A, F6.2)') 'i=', i, ' val=', real(i)**1.5\n  end do\nend program", language: "fortran"),
            LibraryModule(name: "math intrinsics", summary: "ABS, SQRT, SIN/COS/TAN, EXP/LOG, MOD, MIN/MAX, and more",
                importLine: "! All intrinsic functions are always available",
                items: ["ABS", "SQRT", "EXP", "LOG", "LOG10", "SIN", "COS", "TAN", "ASIN", "ACOS", "ATAN", "ATAN2", "SINH", "COSH", "TANH", "MOD", "MODULO", "SIGN", "MAX", "MIN", "DIM", "CEILING", "FLOOR", "NINT", "INT", "REAL", "DBLE", "CMPLX", "CONJG", "AIMAG"],
                example: "program math\n  implicit none\n  real :: x = 2.5\n  write(*, *) 'sqrt:', sqrt(x)\n  write(*, *) 'sin:', sin(x), 'cos:', cos(x)\n  write(*, *) 'exp:', exp(x), 'log:', log(x)\n  write(*, *) 'mod(17,5):', mod(17, 5)\n  write(*, *) 'max:', max(3.0, 7.0, 1.0)\n  write(*, *) 'floor:', floor(3.7), 'ceil:', ceiling(3.2)\nend program", language: "fortran"),
            LibraryModule(name: "string & character", summary: "LEN, TRIM, INDEX, REPEAT, CHAR/ICHAR, concatenation //",
                importLine: "character(len=50) :: s",
                items: ["LEN", "LEN_TRIM", "TRIM", "ADJUSTL", "ADJUSTR", "INDEX", "SCAN", "VERIFY", "REPEAT", "CHAR", "ICHAR", "ACHAR", "IACHAR", "LGE", "LGT", "LLE", "LLT", "// (concatenation)"],
                example: "program strings\n  implicit none\n  character(len=50) :: s, t\n  s = 'Hello'\n  t = 'World'\n  write(*, *) trim(s) // ', ' // trim(t) // '!'\n  write(*, *) 'Length:', len_trim(s)\n  write(*, *) 'Index:', index('abcdef', 'cd')\n  write(*, *) 'Repeat:', repeat('ab', 5)\nend program", language: "fortran"),
            LibraryModule(name: "derived types & system", summary: "TYPE, nested types, RANDOM_NUMBER, CPU_TIME, bit operations",
                importLine: "type :: MyType\n  ...\nend type",
                items: ["TYPE", "END TYPE", "type constructor", "% field access", "nested types", "RANDOM_NUMBER", "RANDOM_SEED", "SYSTEM_CLOCK", "CPU_TIME", "DATE_AND_TIME", "IAND", "IOR", "IEOR", "NOT", "ISHFT", "BTEST", "IBSET", "IBCLR", "KIND", "HUGE", "TINY", "EPSILON"],
                example: "program derived\n  implicit none\n  type :: Vec2D\n    real :: x, y\n  end type\n  type(Vec2D) :: v1, v2\n  real :: t1, t2\n  v1 = Vec2D(3.0, 4.0)\n  v2 = Vec2D(1.0, 2.0)\n  write(*, *) 'v1:', v1%x, v1%y\n  call cpu_time(t1)\n  ! ... computation ...\n  call cpu_time(t2)\n  write(*, '(A,F8.6,A)') 'Time: ', t2-t1, ' seconds'\nend program", language: "fortran")
        ])
    }

    // MARK: Other Libraries
    // MARK: Media (PyAV, Cairo, FFmpeg)
    private static var mediaSection: LibrarySection {
        LibrarySection(name: "Media & Rendering", icon: "play.rectangle", modules: [
            LibraryModule(name: "av (PyAV)", summary: "FFmpeg bindings for video/audio encoding and decoding",
                importLine: "import av",
                items: ["av.open", "av.OutputContainer", "av.InputContainer", "av.CodecContext", "av.VideoFrame", "av.AudioFrame", "av.Stream", "av.Packet", "container.add_stream", "stream.encode", "container.mux"],
                example: "import av\nimport numpy as np\n# Create a 2-second test video\ncontainer = av.open('/tmp/test.mp4', mode='w')\nstream = container.add_stream('h264_videotoolbox', rate=30)\nstream.width = 640\nstream.height = 480\nfor i in range(60):\n    img = np.zeros((480, 640, 3), dtype=np.uint8)\n    img[:, :, 0] = int(255 * i / 60)  # fade red\n    frame = av.VideoFrame.from_ndarray(img, format='rgb24')\n    for pkt in stream.encode(frame):\n        container.mux(pkt)\nfor pkt in stream.encode():\n    container.mux(pkt)\ncontainer.close()\nprint('Video created!')"),
            LibraryModule(name: "cairo", summary: "2D vector graphics: SVG, PNG, paths, text rendering",
                importLine: "import cairo",
                items: ["cairo.SVGSurface", "cairo.ImageSurface", "cairo.Context", "ctx.move_to", "ctx.line_to", "ctx.arc", "ctx.curve_to", "ctx.text_path", "ctx.fill", "ctx.stroke", "ctx.set_source_rgb", "ctx.set_line_width", "ctx.save", "ctx.restore"],
                example: "import cairo\n# Create SVG with shapes\nsurf = cairo.SVGSurface('/tmp/drawing.svg', 200, 200)\nctx = cairo.Context(surf)\nctx.set_source_rgb(0.2, 0.4, 0.8)\nctx.arc(100, 100, 80, 0, 2 * 3.14159)\nctx.fill()\nctx.set_source_rgb(1, 1, 1)\nctx.select_font_face('sans-serif')\nctx.set_font_size(24)\nctx.move_to(55, 107)\nctx.text_path('Cairo!')\nctx.fill()\nsurf.finish()\nprint('SVG created')"),
            LibraryModule(name: "offlinai_latex", summary: "Local LaTeX rendering via pdftex — no internet needed",
                importLine: "from offlinai_latex import tex_to_svg",
                items: ["tex_to_svg", "compile_tex", "_load_pdftex", "_render_with_cairo"],
                example: "from offlinai_latex import tex_to_svg\n# Render a LaTeX equation to SVG\nsvg_path = tex_to_svg(r'E = mc^2')\nprint(f'SVG at: {svg_path}')\n\n# More complex equation\nsvg2 = tex_to_svg(r'\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}')\nprint(f'Integral SVG at: {svg2}')"),
            LibraryModule(name: "svgelements", summary: "Parse, manipulate, and generate SVG files in pure Python",
                importLine: "from svgelements import SVG, Path, Circle, Rect",
                items: ["SVG", "Path", "Circle", "Rect", "Line", "Polyline", "Polygon", "Text", "Group", "Matrix", "Color", "parse"],
                example: "from svgelements import SVG\nsvg = SVG()\nprint('SVG parsing ready')\n# Use with manim for SVG path manipulation"),
            LibraryModule(name: "PIL (Pillow)", summary: "Image processing: open, resize, filter, draw, convert",
                importLine: "from PIL import Image, ImageDraw, ImageFilter",
                items: ["Image.open", "Image.new", "img.resize", "img.crop", "img.rotate", "img.filter", "img.convert", "ImageDraw.Draw", "draw.rectangle", "draw.ellipse", "draw.text", "ImageFilter.BLUR", "ImageFilter.SHARPEN", "img.save"],
                example: "from PIL import Image, ImageDraw\n# Create a gradient image\nimg = Image.new('RGB', (200, 200))\ndraw = ImageDraw.Draw(img)\nfor y in range(200):\n    r = int(255 * y / 200)\n    draw.line([(0, y), (200, y)], fill=(r, 100, 255-r))\ndraw.ellipse([50, 50, 150, 150], fill='white', outline='black')\nimg.save('/tmp/gradient.png')\nprint(f'Image: {img.size}')")
        ])
    }

    // MARK: Web & Networking
    private static var webSection: LibrarySection {
        LibrarySection(name: "Web & Data", icon: "globe", modules: [
            LibraryModule(name: "requests", summary: "HTTP client: GET, POST, sessions, auth, JSON",
                importLine: "import requests",
                items: ["requests.get", "requests.post", "requests.put", "requests.delete", "requests.head", "requests.Session", "Response.json()", "Response.text", "Response.status_code", "Response.headers", "HTTPBasicAuth"],
                example: "import requests\n# GET request\nresp = requests.get('https://httpbin.org/get')\nprint(resp.status_code)\nprint(resp.json())\n\n# POST with JSON\nresp = requests.post('https://httpbin.org/post',\n    json={'name': 'OfflinAi', 'version': 1})\nprint(resp.json()['json'])"),
            LibraryModule(name: "bs4 (BeautifulSoup)", summary: "HTML/XML parsing and web scraping",
                importLine: "from bs4 import BeautifulSoup",
                items: ["BeautifulSoup", "find", "find_all", "select", "select_one", "get_text", "Tag", "NavigableString", "prettify", "children", "parents", "attrs"],
                example: "from bs4 import BeautifulSoup\nhtml = '''<html><body>\n<h1>Title</h1>\n<ul><li class=\"item\">One</li><li class=\"item\">Two</li></ul>\n</body></html>'''\nsoup = BeautifulSoup(html, 'html.parser')\nfor li in soup.select('li.item'):\n    print(li.get_text())"),
            LibraryModule(name: "json / yaml", summary: "Data serialization: JSON, YAML, CSV parsing",
                importLine: "import json\nimport yaml\nimport csv",
                items: ["json.loads", "json.dumps", "json.load", "json.dump", "yaml.safe_load", "yaml.safe_dump", "csv.reader", "csv.writer", "csv.DictReader", "csv.DictWriter"],
                example: "import json, yaml\ndata = {'name': 'OfflinAi', 'libs': ['numpy', 'scipy', 'manim']}\n\n# JSON\nj = json.dumps(data, indent=2)\nprint(j)\n\n# YAML\ny = yaml.safe_dump(data)\nprint(y)"),
            LibraryModule(name: "jsonschema", summary: "Validate JSON data against schemas (Draft 7)",
                importLine: "import jsonschema",
                items: ["jsonschema.validate", "jsonschema.Draft7Validator", "jsonschema.ValidationError", "jsonschema.SchemaError", "FormatChecker"],
                example: "import jsonschema\nschema = {\n    'type': 'object',\n    'properties': {\n        'name': {'type': 'string'},\n        'age': {'type': 'integer', 'minimum': 0}\n    },\n    'required': ['name']\n}\njsonschema.validate({'name': 'Alice', 'age': 30}, schema)\nprint('Schema validation passed!')"),
            LibraryModule(name: "packaging", summary: "Version parsing and specifier matching (PEP 440)",
                importLine: "from packaging.version import Version\nfrom packaging.specifiers import SpecifierSet",
                items: ["Version", "SpecifierSet", "Requirement", "parse", "version.major", "version.minor", "version.micro"],
                example: "from packaging.version import Version\nv1 = Version('1.2.3')\nv2 = Version('2.0.0')\nprint(f'{v1} < {v2}: {v1 < v2}')\nfrom packaging.specifiers import SpecifierSet\nspec = SpecifierSet('>=1.0,<3.0')\nprint(f'{v1} in spec: {v1 in spec}')")
        ])
    }

    private static var otherSection: LibrarySection {
        LibrarySection(name: "Other", icon: "shippingbox", modules: [
            LibraryModule(name: "plotly", summary: "Interactive plotting: scatter, bar, 3D, maps",
                importLine: "import plotly.graph_objects as go\nimport plotly.express as px",
                items: ["go.Figure", "go.Scatter", "go.Bar", "go.Heatmap", "go.Surface", "px.scatter", "px.line", "px.bar", "px.histogram"],
                example: "import plotly.express as px\nimport numpy as np\nx = np.linspace(0, 10, 100)\nfig = px.line(x=x, y=np.sin(x), title='Sine Wave')\nfig.show()"),
            LibraryModule(name: "mpmath", summary: "Arbitrary precision arithmetic and special functions",
                importLine: "import mpmath",
                items: ["mp.dps", "mpf", "mpc", "pi", "e", "quad", "taylor", "zeta", "gamma", "hyper", "matrix"],
                example: "import mpmath\nmpmath.mp.dps = 50\nprint(mpmath.pi)\nprint(mpmath.quad(mpmath.sin, [0, mpmath.pi]))"),
            LibraryModule(name: "bs4", summary: "HTML/XML parsing with BeautifulSoup",
                importLine: "from bs4 import BeautifulSoup",
                items: ["BeautifulSoup", "find", "find_all", "select", "get_text", "Tag", "NavigableString", "prettify"],
                example: "from bs4 import BeautifulSoup\nhtml = '<html><body><h1>Title</h1><p>Hello</p></body></html>'\nsoup = BeautifulSoup(html, 'html.parser')\nprint(soup.h1.get_text())"),
            LibraryModule(name: "yaml", summary: "YAML parsing and serialization",
                importLine: "import yaml",
                items: ["safe_load", "safe_dump", "load_all", "dump_all", "SafeLoader", "SafeDumper", "YAMLError"],
                example: "import yaml\ndata = {'name': 'OfflinAi', 'version': 1.0, 'features': ['numpy', 'scipy']}\ntext = yaml.safe_dump(data)\nprint(text)\nparsed = yaml.safe_load(text)\nprint(parsed)"),
            LibraryModule(name: "tqdm", summary: "Progress bars for loops and iterables",
                importLine: "from tqdm import tqdm",
                items: ["tqdm", "trange", "tqdm.write", "set_description", "set_postfix", "update", "tqdm.pandas"],
                example: "from tqdm import tqdm\nimport time\nfor i in tqdm(range(100), desc='Processing'):\n    time.sleep(0.01)"),
            LibraryModule(name: "rich", summary: "Rich text, tables, progress bars in the terminal",
                importLine: "from rich.console import Console\nfrom rich.table import Table",
                items: ["Console", "Table", "Panel", "Tree", "Markdown", "Syntax", "Progress", "print", "inspect"],
                example: "from rich.console import Console\nfrom rich.table import Table\nconsole = Console()\ntable = Table(title='Results')\ntable.add_column('Name')\ntable.add_column('Score')\ntable.add_row('Alice', '95')\ntable.add_row('Bob', '87')\nconsole.print(table)"),
            LibraryModule(name: "click", summary: "CLI framework with decorators for commands and options",
                importLine: "import click",
                items: ["command", "option", "argument", "group", "echo", "prompt", "confirm", "Choice", "Path"],
                example: "import click\n@click.command()\n@click.option('--name', default='World', help='Who to greet')\ndef hello(name):\n    click.echo(f'Hello, {name}!')\n# hello()  # invoke from CLI"),
            LibraryModule(name: "jsonschema", summary: "JSON Schema validation for Python objects",
                importLine: "import jsonschema",
                items: ["validate", "Draft7Validator", "ValidationError", "SchemaError", "FormatChecker", "RefResolver"],
                example: "import jsonschema\nschema = {'type': 'object', 'properties': {'name': {'type': 'string'}, 'age': {'type': 'integer', 'minimum': 0}}, 'required': ['name']}\njsonschema.validate({'name': 'Alice', 'age': 30}, schema)\nprint('Valid!')"),
            LibraryModule(name: "pydub", summary: "Audio manipulation: slice, concatenate, convert, effects",
                importLine: "from pydub import AudioSegment",
                items: ["AudioSegment", "from_file", "export", "overlay", "concatenate", "fade_in", "fade_out", "speedup", "normalize", "split_on_silence"],
                example: "from pydub import AudioSegment\n# audio = AudioSegment.from_file('input.mp3')\n# louder = audio + 6  # increase volume by 6dB\n# louder.export('output.mp3', format='mp3')\nprint('pydub ready for audio processing')")
        ])
    }
}
