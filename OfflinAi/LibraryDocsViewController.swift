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

        searchBar.placeholder = "Search libraries and modules..."
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.barTintColor = bgColor
        searchBar.tintColor = accentColor
        if let tf = searchBar.searchTextField as UITextField? {
            tf.textColor = textColor
            tf.attributedPlaceholder = NSAttributedString(
                string: "Search libraries and modules...",
                attributes: [.foregroundColor: dimTextColor]
            )
            tf.backgroundColor = surfaceColor
        }

        tableView.backgroundColor = bgColor
        tableView.separatorColor = surfaceColor
        tableView.indicatorStyle = .white
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ModuleCell.self, forCellReuseIdentifier: ModuleCell.id)
        tableView.register(SectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderView.id)
        tableView.sectionFooterHeight = 0
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .onDrag

        let stack = UIStackView(arrangedSubviews: [searchBar, tableView])
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
            cSection, cppSection, fortranSection, otherSection
        ]
    }

    // MARK: NumPy
    private static var numpySection: LibrarySection {
        LibrarySection(name: "numpy", icon: "function", modules: [
            LibraryModule(name: "linalg", summary: "Linear algebra: matrix ops, decompositions, solvers",
                importLine: "from numpy.linalg import inv, eig, svd, solve",
                items: ["inv", "eig", "eigvals", "svd", "solve", "det", "norm", "qr", "cholesky", "lstsq"],
                example: "import numpy as np\nA = np.array([[1, 2], [3, 4]])\nvals, vecs = np.linalg.eig(A)\nprint('Eigenvalues:', vals)"),
            LibraryModule(name: "fft", summary: "Fast Fourier transforms for signal analysis",
                importLine: "from numpy.fft import fft, ifft, fftfreq",
                items: ["fft", "ifft", "fft2", "ifft2", "rfft", "irfft", "fftfreq", "fftshift"],
                example: "import numpy as np\nt = np.linspace(0, 1, 256)\nsig = np.sin(2*np.pi*10*t) + np.sin(2*np.pi*20*t)\nF = np.fft.fft(sig)\nfreqs = np.fft.fftfreq(len(t), t[1]-t[0])"),
            LibraryModule(name: "random", summary: "Random number generation and sampling",
                importLine: "from numpy.random import default_rng",
                items: ["default_rng", "normal", "uniform", "randint", "choice", "shuffle", "permutation", "seed"],
                example: "import numpy as np\nrng = np.random.default_rng(42)\nsamples = rng.normal(0, 1, size=1000)\nprint('Mean:', samples.mean())"),
            LibraryModule(name: "polynomial", summary: "Polynomial fitting and evaluation",
                importLine: "from numpy.polynomial import polynomial as P",
                items: ["polyfit", "polyval", "polyadd", "polymul", "Polynomial", "Chebyshev", "Legendre"],
                example: "import numpy as np\nx = np.linspace(0, 1, 20)\ny = np.sin(2*np.pi*x)\ncoeffs = np.polyfit(x, y, 5)\nprint('Coefficients:', coeffs)")
        ])
    }

    // MARK: SciPy
    private static var scipySection: LibrarySection {
        LibrarySection(name: "scipy", icon: "waveform.path.ecg", modules: [
            LibraryModule(name: "optimize", summary: "Minimization, root finding, curve fitting",
                importLine: "from scipy.optimize import minimize, curve_fit",
                items: ["minimize", "minimize_scalar", "curve_fit", "root", "linprog", "differential_evolution", "basinhopping"],
                example: "from scipy.optimize import minimize\nf = lambda x: (x - 3)**2 + 1\nres = minimize(f, x0=0)\nprint('Minimum at:', res.x)"),
            LibraryModule(name: "integrate", summary: "Numerical integration and ODE solvers",
                importLine: "from scipy.integrate import quad, solve_ivp",
                items: ["quad", "dblquad", "solve_ivp", "odeint", "trapezoid", "simpson", "cumulative_trapezoid"],
                example: "from scipy.integrate import quad\nimport numpy as np\nresult, err = quad(np.sin, 0, np.pi)\nprint('Integral of sin(0..pi):', result)"),
            LibraryModule(name: "stats", summary: "Statistical distributions, tests, and descriptive stats",
                importLine: "from scipy import stats",
                items: ["norm", "t", "chi2", "ttest_ind", "pearsonr", "kstest", "describe", "linregress", "entropy"],
                example: "from scipy import stats\ndata = stats.norm.rvs(size=100, random_state=42)\nstat, p = stats.normaltest(data)\nprint('p-value:', p)"),
            LibraryModule(name: "interpolate", summary: "Interpolation of 1D and ND data",
                importLine: "from scipy.interpolate import interp1d, CubicSpline",
                items: ["interp1d", "CubicSpline", "UnivariateSpline", "RBFInterpolator", "griddata", "BSpline"],
                example: "from scipy.interpolate import CubicSpline\nimport numpy as np\nx = np.arange(10)\ny = np.sin(x)\ncs = CubicSpline(x, y)\nprint(cs(0.5))"),
            LibraryModule(name: "linalg", summary: "Extended linear algebra beyond numpy",
                importLine: "from scipy.linalg import lu, expm, schur",
                items: ["lu", "expm", "logm", "sqrtm", "schur", "hessenberg", "polar", "solve_banded"],
                example: "from scipy.linalg import expm\nimport numpy as np\nA = np.array([[0, 1], [-1, 0]])\nprint('Matrix exp:\\n', expm(A))"),
            LibraryModule(name: "fft", summary: "FFT routines with more backends than numpy",
                importLine: "from scipy.fft import fft, dct, dst",
                items: ["fft", "ifft", "dct", "idct", "dst", "fht", "fftfreq", "next_fast_len"],
                example: "from scipy.fft import dct\nimport numpy as np\nsig = np.random.randn(64)\ncoeffs = dct(sig, type=2)\nprint('DCT coeffs shape:', coeffs.shape)"),
            LibraryModule(name: "signal", summary: "Signal processing: filtering, spectral analysis",
                importLine: "from scipy.signal import butter, filtfilt, spectrogram",
                items: ["butter", "filtfilt", "lfilter", "spectrogram", "find_peaks", "welch", "convolve", "resample"],
                example: "from scipy.signal import butter, filtfilt\nimport numpy as np\nb, a = butter(4, 0.1)\nx = np.random.randn(200)\ny = filtfilt(b, a, x)"),
            LibraryModule(name: "spatial", summary: "Spatial data structures and distance computations",
                importLine: "from scipy.spatial import KDTree, ConvexHull",
                items: ["KDTree", "ConvexHull", "Voronoi", "Delaunay", "distance_matrix", "cKDTree"],
                example: "from scipy.spatial import KDTree\nimport numpy as np\npts = np.random.rand(100, 2)\ntree = KDTree(pts)\nd, i = tree.query([0.5, 0.5], k=3)\nprint('Nearest 3 distances:', d)"),
            LibraryModule(name: "sparse", summary: "Sparse matrix formats and operations",
                importLine: "from scipy.sparse import csr_matrix, lil_matrix",
                items: ["csr_matrix", "csc_matrix", "lil_matrix", "eye", "diags", "hstack", "vstack", "linalg.spsolve"],
                example: "from scipy.sparse import csr_matrix\nimport numpy as np\nrow = [0, 0, 1, 2]\ncol = [0, 2, 1, 2]\ndata = [1, 2, 3, 4]\nA = csr_matrix((data, (row, col)), shape=(3, 3))\nprint(A.toarray())"),
            LibraryModule(name: "special", summary: "Special mathematical functions (Bessel, gamma, etc.)",
                importLine: "from scipy.special import gamma, jv, erf",
                items: ["gamma", "beta", "erf", "erfc", "jv", "yv", "legendre", "comb", "factorial"],
                example: "from scipy.special import gamma, erf\nimport numpy as np\nprint('Gamma(5):', gamma(5))\nprint('erf(1):', erf(1))"),
            LibraryModule(name: "ndimage", summary: "N-dimensional image processing",
                importLine: "from scipy.ndimage import gaussian_filter, label",
                items: ["gaussian_filter", "median_filter", "uniform_filter", "label", "binary_erosion", "rotate", "zoom"],
                example: "from scipy.ndimage import gaussian_filter\nimport numpy as np\nimg = np.random.rand(64, 64)\nsmoothed = gaussian_filter(img, sigma=2)\nprint('Smoothed shape:', smoothed.shape)"),
            LibraryModule(name: "cluster", summary: "Hierarchical clustering and vector quantization",
                importLine: "from scipy.cluster.hierarchy import linkage, fcluster",
                items: ["linkage", "fcluster", "dendrogram", "cut_tree", "vq.kmeans", "vq.whiten"],
                example: "from scipy.cluster.hierarchy import linkage, fcluster\nimport numpy as np\nX = np.random.rand(50, 2)\nZ = linkage(X, method='ward')\nlabels = fcluster(Z, t=3, criterion='maxclust')\nprint('Clusters:', np.unique(labels))")
        ])
    }

    // MARK: sklearn
    private static var sklearnSection: LibrarySection {
        LibrarySection(name: "sklearn", icon: "brain.head.profile", modules: [
            LibraryModule(name: "datasets", summary: "Built-in datasets and data generators",
                importLine: "from sklearn.datasets import load_iris, make_classification",
                items: ["load_iris", "load_digits", "load_wine", "make_classification", "make_regression", "make_blobs", "fetch_openml"],
                example: "from sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nprint('Shape:', X.shape, 'Classes:', set(y))"),
            LibraryModule(name: "model_selection", summary: "Cross-validation, hyperparameter tuning, splits",
                importLine: "from sklearn.model_selection import train_test_split, GridSearchCV",
                items: ["train_test_split", "cross_val_score", "GridSearchCV", "RandomizedSearchCV", "KFold", "StratifiedKFold"],
                example: "from sklearn.model_selection import train_test_split\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nX_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2)\nprint('Train:', X_tr.shape, 'Test:', X_te.shape)"),
            LibraryModule(name: "preprocessing", summary: "Feature scaling, encoding, and transformation",
                importLine: "from sklearn.preprocessing import StandardScaler, LabelEncoder",
                items: ["StandardScaler", "MinMaxScaler", "LabelEncoder", "OneHotEncoder", "PolynomialFeatures", "Normalizer"],
                example: "from sklearn.preprocessing import StandardScaler\nimport numpy as np\nX = np.random.rand(100, 3) * 100\nscaler = StandardScaler().fit(X)\nX_s = scaler.transform(X)\nprint('Mean:', X_s.mean(axis=0))"),
            LibraryModule(name: "linear_model", summary: "Linear, logistic, and regularized regression",
                importLine: "from sklearn.linear_model import LinearRegression, LogisticRegression",
                items: ["LinearRegression", "LogisticRegression", "Ridge", "Lasso", "ElasticNet", "SGDClassifier"],
                example: "from sklearn.linear_model import LinearRegression\nimport numpy as np\nX = np.arange(20).reshape(-1, 1)\ny = 3*X.ravel() + np.random.randn(20)\nmodel = LinearRegression().fit(X, y)\nprint('Coef:', model.coef_, 'R2:', model.score(X, y))"),
            LibraryModule(name: "ensemble", summary: "Random forests, gradient boosting, bagging",
                importLine: "from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier",
                items: ["RandomForestClassifier", "RandomForestRegressor", "GradientBoostingClassifier", "AdaBoostClassifier", "VotingClassifier", "BaggingClassifier"],
                example: "from sklearn.ensemble import RandomForestClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nclf = RandomForestClassifier(n_estimators=50).fit(X, y)\nprint('Accuracy:', clf.score(X, y))"),
            LibraryModule(name: "tree", summary: "Decision tree classifiers and regressors",
                importLine: "from sklearn.tree import DecisionTreeClassifier, export_text",
                items: ["DecisionTreeClassifier", "DecisionTreeRegressor", "export_text", "export_graphviz", "plot_tree"],
                example: "from sklearn.tree import DecisionTreeClassifier, export_text\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\ntree = DecisionTreeClassifier(max_depth=3).fit(X, y)\nprint(export_text(tree, feature_names=load_iris().feature_names))"),
            LibraryModule(name: "svm", summary: "Support vector machines for classification and regression",
                importLine: "from sklearn.svm import SVC, SVR",
                items: ["SVC", "SVR", "LinearSVC", "NuSVC", "OneClassSVM"],
                example: "from sklearn.svm import SVC\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nclf = SVC(kernel='rbf').fit(X, y)\nprint('Accuracy:', clf.score(X, y))"),
            LibraryModule(name: "neighbors", summary: "K-nearest neighbors for classification and regression",
                importLine: "from sklearn.neighbors import KNeighborsClassifier",
                items: ["KNeighborsClassifier", "KNeighborsRegressor", "RadiusNeighborsClassifier", "NearestNeighbors", "BallTree"],
                example: "from sklearn.neighbors import KNeighborsClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nknn = KNeighborsClassifier(n_neighbors=5).fit(X, y)\nprint('Accuracy:', knn.score(X, y))"),
            LibraryModule(name: "cluster", summary: "Clustering: KMeans, DBSCAN, Agglomerative, etc.",
                importLine: "from sklearn.cluster import KMeans, DBSCAN",
                items: ["KMeans", "DBSCAN", "AgglomerativeClustering", "SpectralClustering", "MeanShift", "OPTICS"],
                example: "from sklearn.cluster import KMeans\nimport numpy as np\nX = np.random.rand(200, 2)\nkm = KMeans(n_clusters=3, n_init=10).fit(X)\nprint('Centers:', km.cluster_centers_)"),
            LibraryModule(name: "decomposition", summary: "Dimensionality reduction: PCA, NMF, ICA",
                importLine: "from sklearn.decomposition import PCA, NMF",
                items: ["PCA", "NMF", "TruncatedSVD", "FastICA", "LatentDirichletAllocation", "KernelPCA"],
                example: "from sklearn.decomposition import PCA\nfrom sklearn.datasets import load_iris\nX, _ = load_iris(return_X_y=True)\npca = PCA(n_components=2).fit_transform(X)\nprint('Reduced shape:', pca.shape)"),
            LibraryModule(name: "manifold", summary: "Manifold learning: t-SNE, MDS, Isomap",
                importLine: "from sklearn.manifold import TSNE, MDS",
                items: ["TSNE", "MDS", "Isomap", "LocallyLinearEmbedding", "SpectralEmbedding"],
                example: "from sklearn.manifold import TSNE\nfrom sklearn.datasets import load_digits\nX, _ = load_digits(return_X_y=True)\nemb = TSNE(n_components=2, perplexity=30).fit_transform(X[:300])\nprint('Embedding shape:', emb.shape)"),
            LibraryModule(name: "metrics", summary: "Model evaluation: accuracy, F1, ROC, confusion matrix",
                importLine: "from sklearn.metrics import accuracy_score, f1_score, confusion_matrix",
                items: ["accuracy_score", "f1_score", "precision_score", "recall_score", "roc_auc_score", "confusion_matrix", "classification_report", "mean_squared_error"],
                example: "from sklearn.metrics import classification_report\nimport numpy as np\ny_true = [0, 1, 1, 0, 1]\ny_pred = [0, 1, 0, 0, 1]\nprint(classification_report(y_true, y_pred))"),
            LibraryModule(name: "pipeline", summary: "Chaining transforms and estimators",
                importLine: "from sklearn.pipeline import Pipeline, make_pipeline",
                items: ["Pipeline", "make_pipeline", "FeatureUnion", "ColumnTransformer"],
                example: "from sklearn.pipeline import make_pipeline\nfrom sklearn.preprocessing import StandardScaler\nfrom sklearn.svm import SVC\npipe = make_pipeline(StandardScaler(), SVC())\nprint(pipe.steps)"),
            LibraryModule(name: "neural_network", summary: "Multi-layer perceptron for classification and regression",
                importLine: "from sklearn.neural_network import MLPClassifier",
                items: ["MLPClassifier", "MLPRegressor", "BernoulliRBM"],
                example: "from sklearn.neural_network import MLPClassifier\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nmlp = MLPClassifier(hidden_layer_sizes=(50,), max_iter=500).fit(X, y)\nprint('Accuracy:', mlp.score(X, y))"),
            LibraryModule(name: "gaussian_process", summary: "Gaussian process regression and classification",
                importLine: "from sklearn.gaussian_process import GaussianProcessRegressor",
                items: ["GaussianProcessRegressor", "GaussianProcessClassifier", "kernels.RBF", "kernels.Matern"],
                example: "from sklearn.gaussian_process import GaussianProcessRegressor\nfrom sklearn.gaussian_process.kernels import RBF\nimport numpy as np\nX = np.linspace(0, 5, 20).reshape(-1, 1)\ny = np.sin(X).ravel()\ngp = GaussianProcessRegressor(kernel=RBF()).fit(X, y)\nprint('Score:', gp.score(X, y))"),
            LibraryModule(name: "naive_bayes", summary: "Naive Bayes classifiers for text and numeric data",
                importLine: "from sklearn.naive_bayes import GaussianNB, MultinomialNB",
                items: ["GaussianNB", "MultinomialNB", "BernoulliNB", "ComplementNB"],
                example: "from sklearn.naive_bayes import GaussianNB\nfrom sklearn.datasets import load_iris\nX, y = load_iris(return_X_y=True)\nclf = GaussianNB().fit(X, y)\nprint('Accuracy:', clf.score(X, y))")
        ])
    }

    // MARK: Matplotlib
    private static var matplotlibSection: LibrarySection {
        LibrarySection(name: "matplotlib", icon: "chart.xyaxis.line", modules: [
            LibraryModule(name: "pyplot", summary: "Primary plotting interface for figures and axes",
                importLine: "import matplotlib.pyplot as plt",
                items: ["plot", "scatter", "bar", "hist", "imshow", "subplot", "figure", "savefig", "show", "legend"],
                example: "import matplotlib.pyplot as plt\nimport numpy as np\nx = np.linspace(0, 2*np.pi, 100)\nplt.plot(x, np.sin(x), label='sin')\nplt.plot(x, np.cos(x), label='cos')\nplt.legend(); plt.title('Trig Functions')"),
            LibraryModule(name: "cm", summary: "Colormaps for data visualization",
                importLine: "from matplotlib import cm",
                items: ["viridis", "plasma", "inferno", "magma", "coolwarm", "ScalarMappable", "get_cmap"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib import cm\nimport numpy as np\ndata = np.random.rand(10, 10)\nplt.imshow(data, cmap=cm.viridis)\nplt.colorbar()"),
            LibraryModule(name: "colors", summary: "Color specification, normalization, colormaps",
                importLine: "from matplotlib.colors import Normalize, LogNorm",
                items: ["Normalize", "LogNorm", "BoundaryNorm", "ListedColormap", "LinearSegmentedColormap", "to_rgba"],
                example: "from matplotlib.colors import Normalize\nimport numpy as np\nnorm = Normalize(vmin=0, vmax=10)\nprint(norm(5))  # 0.5"),
            LibraryModule(name: "patches", summary: "2D shape patches for custom drawing",
                importLine: "from matplotlib.patches import Circle, Rectangle, FancyBboxPatch",
                items: ["Circle", "Rectangle", "Polygon", "Ellipse", "FancyBboxPatch", "Arrow", "PathPatch"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.patches import Circle\nfig, ax = plt.subplots()\nax.add_patch(Circle((0.5, 0.5), 0.3, color='blue', alpha=0.5))\nax.set_xlim(0, 1); ax.set_ylim(0, 1)"),
            LibraryModule(name: "ticker", summary: "Axis tick locators and formatters",
                importLine: "from matplotlib.ticker import MaxNLocator, FuncFormatter",
                items: ["MaxNLocator", "MultipleLocator", "FuncFormatter", "PercentFormatter", "LogLocator", "AutoMinorLocator"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.ticker import MaxNLocator\nfig, ax = plt.subplots()\nax.plot(range(10))\nax.xaxis.set_major_locator(MaxNLocator(integer=True))"),
            LibraryModule(name: "animation", summary: "Creating animated plots and saving to video/gif",
                importLine: "from matplotlib.animation import FuncAnimation",
                items: ["FuncAnimation", "ArtistAnimation", "PillowWriter", "FFMpegWriter"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.animation import FuncAnimation\nimport numpy as np\nfig, ax = plt.subplots()\nln, = ax.plot([], [])\ndef update(frame):\n    ln.set_data(np.linspace(0, 2*np.pi), np.sin(np.linspace(0, 2*np.pi) + frame/10))\n    return ln,"),
            LibraryModule(name: "gridspec", summary: "Complex subplot grid layouts",
                importLine: "from matplotlib.gridspec import GridSpec",
                items: ["GridSpec", "SubplotSpec", "GridSpecFromSubplotSpec"],
                example: "import matplotlib.pyplot as plt\nfrom matplotlib.gridspec import GridSpec\nfig = plt.figure()\ngs = GridSpec(2, 3, figure=fig)\nax1 = fig.add_subplot(gs[0, :])\nax2 = fig.add_subplot(gs[1, 0])\nax3 = fig.add_subplot(gs[1, 1:])"),
            LibraryModule(name: "style", summary: "Predefined plot style sheets",
                importLine: "import matplotlib.pyplot as plt\nplt.style.use('seaborn-v0_8')",
                items: ["use", "available", "context", "ggplot", "seaborn", "dark_background", "fivethirtyeight"],
                example: "import matplotlib.pyplot as plt\nprint('Available styles:', plt.style.available[:5])\nplt.style.use('dark_background')"),
            LibraryModule(name: "mpl_toolkits", summary: "3D plotting and axes helpers",
                importLine: "from mpl_toolkits.mplot3d import Axes3D",
                items: ["Axes3D", "plot_surface", "plot_wireframe", "scatter3D", "mplot3d.art3d"],
                example: "import matplotlib.pyplot as plt\nfrom mpl_toolkits.mplot3d import Axes3D\nimport numpy as np\nfig = plt.figure()\nax = fig.add_subplot(111, projection='3d')\nu = np.linspace(0, 2*np.pi, 50)\nax.plot(np.cos(u), np.sin(u), u)")
        ])
    }

    // MARK: SymPy
    private static var sympySection: LibrarySection {
        LibrarySection(name: "sympy", icon: "x.squareroot", modules: [
            LibraryModule(name: "core", summary: "Symbolic variables, expressions, simplification",
                importLine: "from sympy import symbols, simplify, expand, factor",
                items: ["symbols", "simplify", "expand", "factor", "collect", "cancel", "apart", "Rational", "pi", "E", "I", "oo"],
                example: "from sympy import symbols, expand, factor\nx = symbols('x')\nexpr = (x + 1)**3\nprint(expand(expr))\nprint(factor(expand(expr)))"),
            LibraryModule(name: "solvers", summary: "Equation solving: algebraic, differential, systems",
                importLine: "from sympy import solve, dsolve, Eq",
                items: ["solve", "solveset", "dsolve", "linsolve", "nonlinsolve", "nsolve", "Eq"],
                example: "from sympy import symbols, solve, Eq\nx = symbols('x')\nsolutions = solve(Eq(x**2 - 5*x + 6, 0), x)\nprint('Solutions:', solutions)"),
            LibraryModule(name: "integrals", summary: "Symbolic integration and transforms",
                importLine: "from sympy import integrate, oo",
                items: ["integrate", "Integral", "laplace_transform", "inverse_laplace_transform", "fourier_transform"],
                example: "from sympy import symbols, integrate, sin, oo\nx = symbols('x')\nresult = integrate(sin(x)**2, (x, 0, 2*oo))\nprint('Integral:', integrate(sin(x)**2, x))"),
            LibraryModule(name: "matrices", summary: "Symbolic matrix operations and decompositions",
                importLine: "from sympy import Matrix",
                items: ["Matrix", "eye", "zeros", "ones", "det", "inv", "eigenvals", "eigenvects", "rref", "nullspace"],
                example: "from sympy import Matrix\nM = Matrix([[1, 2], [3, 4]])\nprint('Det:', M.det())\nprint('Inverse:', M.inv())\nprint('Eigenvalues:', M.eigenvals())"),
            LibraryModule(name: "functions", summary: "Mathematical functions: trig, exponential, special",
                importLine: "from sympy import sin, cos, exp, log, sqrt, Abs",
                items: ["sin", "cos", "tan", "exp", "log", "sqrt", "Abs", "ceiling", "floor", "Piecewise", "Heaviside"],
                example: "from sympy import symbols, sin, cos, simplify\nx = symbols('x')\nexpr = sin(x)**2 + cos(x)**2\nprint(simplify(expr))  # 1"),
            LibraryModule(name: "printing", summary: "LaTeX, MathML, and pretty-print output",
                importLine: "from sympy import latex, pprint",
                items: ["latex", "pprint", "mathml", "ccode", "fcode", "pycode", "pretty"],
                example: "from sympy import symbols, latex, sqrt\nx = symbols('x')\nexpr = sqrt(x**2 + 1) / x\nprint(latex(expr))"),
            LibraryModule(name: "physics", summary: "Units, vectors, quantum mechanics, mechanics",
                importLine: "from sympy.physics.units import meter, second, kg",
                items: ["units.meter", "units.kg", "units.convert_to", "vector.CoordSys3D", "quantum", "mechanics"],
                example: "from sympy.physics.units import meter, second, convert_to\nspeed = 100 * meter / second\nprint(convert_to(speed, [meter, second]))")
        ])
    }

    // MARK: NetworkX
    private static var networkxSection: LibrarySection {
        LibrarySection(name: "networkx", icon: "point.3.connected.trianglepath.dotted", modules: [
            LibraryModule(name: "generators", summary: "Graph generators: random, classic, social network models",
                importLine: "import networkx as nx",
                items: ["complete_graph", "cycle_graph", "path_graph", "erdos_renyi_graph", "barabasi_albert_graph", "watts_strogatz_graph", "grid_2d_graph"],
                example: "import networkx as nx\nG = nx.barabasi_albert_graph(100, 3)\nprint('Nodes:', G.number_of_nodes())\nprint('Edges:', G.number_of_edges())"),
            LibraryModule(name: "algorithms", summary: "Graph algorithms: traversal, matching, flow",
                importLine: "import networkx as nx",
                items: ["bfs_edges", "dfs_edges", "topological_sort", "is_connected", "connected_components", "maximum_flow", "minimum_spanning_tree"],
                example: "import networkx as nx\nG = nx.complete_graph(5)\ntree = nx.minimum_spanning_tree(G)\nprint('MST edges:', tree.number_of_edges())"),
            LibraryModule(name: "centrality", summary: "Node centrality measures: degree, betweenness, PageRank",
                importLine: "from networkx import degree_centrality, pagerank",
                items: ["degree_centrality", "betweenness_centrality", "closeness_centrality", "eigenvector_centrality", "pagerank"],
                example: "import networkx as nx\nG = nx.karate_club_graph()\npr = nx.pagerank(G)\ntop = sorted(pr, key=pr.get, reverse=True)[:3]\nprint('Top 3 PageRank nodes:', top)"),
            LibraryModule(name: "community", summary: "Community detection algorithms",
                importLine: "from networkx.algorithms.community import greedy_modularity_communities",
                items: ["greedy_modularity_communities", "label_propagation_communities", "louvain_communities", "modularity"],
                example: "import networkx as nx\nfrom networkx.algorithms.community import greedy_modularity_communities\nG = nx.karate_club_graph()\ncommunities = list(greedy_modularity_communities(G))\nprint('Communities found:', len(communities))"),
            LibraryModule(name: "shortest_path", summary: "Shortest path algorithms: Dijkstra, A*, Bellman-Ford",
                importLine: "from networkx import shortest_path, dijkstra_path",
                items: ["shortest_path", "shortest_path_length", "dijkstra_path", "bellman_ford_path", "astar_path", "all_pairs_shortest_path"],
                example: "import networkx as nx\nG = nx.grid_2d_graph(5, 5)\npath = nx.shortest_path(G, (0,0), (4,4))\nprint('Path length:', len(path))")
        ])
    }

    // MARK: PIL
    private static var pilSection: LibrarySection {
        LibrarySection(name: "PIL", icon: "photo", modules: [
            LibraryModule(name: "Image", summary: "Core image class: open, create, resize, convert, save",
                importLine: "from PIL import Image",
                items: ["open", "new", "fromarray", "resize", "rotate", "crop", "paste", "convert", "save", "thumbnail", "transform"],
                example: "from PIL import Image\nimport numpy as np\narr = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nimg = img.resize((200, 200))\nprint('Size:', img.size)"),
            LibraryModule(name: "ImageDraw", summary: "Draw shapes, text, and lines on images",
                importLine: "from PIL import ImageDraw",
                items: ["Draw", "line", "rectangle", "ellipse", "polygon", "text", "arc", "chord"],
                example: "from PIL import Image, ImageDraw\nimg = Image.new('RGB', (200, 200), 'black')\ndraw = ImageDraw.Draw(img)\ndraw.rectangle([20, 20, 180, 180], outline='white', width=2)\ndraw.ellipse([50, 50, 150, 150], fill='blue')"),
            LibraryModule(name: "ImageFilter", summary: "Predefined and custom image filters",
                importLine: "from PIL import ImageFilter",
                items: ["BLUR", "CONTOUR", "DETAIL", "EDGE_ENHANCE", "EMBOSS", "SHARPEN", "GaussianBlur", "UnsharpMask", "Kernel"],
                example: "from PIL import Image, ImageFilter\nimport numpy as np\narr = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nblurred = img.filter(ImageFilter.GaussianBlur(radius=3))"),
            LibraryModule(name: "ImageEnhance", summary: "Adjust brightness, contrast, color, sharpness",
                importLine: "from PIL import ImageEnhance",
                items: ["Brightness", "Contrast", "Color", "Sharpness"],
                example: "from PIL import Image, ImageEnhance\nimport numpy as np\narr = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nenhancer = ImageEnhance.Contrast(img)\nimg2 = enhancer.enhance(2.0)"),
            LibraryModule(name: "ImageOps", summary: "Image operations: auto-contrast, flip, equalize",
                importLine: "from PIL import ImageOps",
                items: ["autocontrast", "equalize", "flip", "mirror", "invert", "grayscale", "pad", "fit", "contain"],
                example: "from PIL import Image, ImageOps\nimport numpy as np\narr = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8)\nimg = Image.fromarray(arr)\nimg_eq = ImageOps.equalize(img)\nimg_gray = ImageOps.grayscale(img)")
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
            LibraryModule(name: "data types", summary: "Primitive types, arrays, structs, unions, enums",
                importLine: "// Supported: int, float, double, char, _Bool, struct, union, enum",
                items: ["int", "float", "double", "char", "_Bool", "long long", "unsigned", "struct", "union", "enum", "typedef", "size_t"],
                example: "#include <stdio.h>\ntypedef struct { double x, y; } Point;\nint main() {\n    Point p = {3.0, 4.0};\n    printf(\"Point: (%.1f, %.1f)\\n\", p.x, p.y);\n    return 0;\n}", language: "c"),
            LibraryModule(name: "control flow", summary: "if/else, for, while, switch, goto",
                importLine: "// if, else, for, while, do-while, switch, break, continue, goto",
                items: ["if/else", "for", "while", "do-while", "switch/case", "break", "continue", "goto", "ternary ?:"],
                example: "#include <stdio.h>\nint main() {\n    for (int i = 0; i < 10; i++) {\n        if (i % 2 == 0) continue;\n        printf(\"%d \", i);\n    }\n    return 0;\n}", language: "c"),
            LibraryModule(name: "functions", summary: "Function declarations, prototypes, variadic args",
                importLine: "// Functions, recursion, function pointers, stdarg.h",
                items: ["declaration", "prototype", "recursion", "function pointers", "va_list", "va_start", "va_arg", "callback"],
                example: "#include <stdio.h>\nint factorial(int n) {\n    return n <= 1 ? 1 : n * factorial(n - 1);\n}\nint main() {\n    printf(\"10! = %d\\n\", factorial(10));\n    return 0;\n}", language: "c"),
            LibraryModule(name: "pointers", summary: "Pointer arithmetic, arrays, dynamic memory",
                importLine: "#include <stdlib.h>  // malloc, free, calloc, realloc",
                items: ["malloc", "calloc", "realloc", "free", "pointer arithmetic", "arrays", "void*", "NULL", "sizeof"],
                example: "#include <stdio.h>\n#include <stdlib.h>\nint main() {\n    int *arr = malloc(5 * sizeof(int));\n    for (int i = 0; i < 5; i++) arr[i] = i * i;\n    for (int i = 0; i < 5; i++) printf(\"%d \", arr[i]);\n    free(arr);\n    return 0;\n}", language: "c"),
            LibraryModule(name: "macros", summary: "Preprocessor macros, conditional compilation",
                importLine: "#define, #ifdef, #ifndef, #if, #pragma, #include",
                items: ["#define", "#ifdef/#ifndef", "#if/#elif/#else", "#include", "#pragma", "__FILE__", "__LINE__", "##", "#"],
                example: "#include <stdio.h>\n#define MAX(a,b) ((a) > (b) ? (a) : (b))\n#define PI 3.14159265\nint main() {\n    printf(\"Max: %d\\n\", MAX(3, 7));\n    printf(\"PI: %f\\n\", PI);\n    return 0;\n}", language: "c"),
            LibraryModule(name: "C23 features", summary: "Modern C features: auto, nullptr, constexpr, typeof",
                importLine: "// C23 standard features supported by the interpreter",
                items: ["auto type inference", "nullptr", "constexpr", "typeof", "static_assert", "_BitInt", "[[attributes]]", "bool/true/false"],
                example: "#include <stdio.h>\nint main() {\n    constexpr int size = 10;\n    auto x = 3.14;\n    typeof(x) y = 2.71;\n    printf(\"x=%.2f y=%.2f\\n\", x, y);\n    return 0;\n}", language: "c")
        ])
    }

    // MARK: C++ Interpreter
    private static var cppSection: LibrarySection {
        LibrarySection(name: "C++ interpreter", icon: "chevron.left.forwardslash.chevron.right", modules: [
            LibraryModule(name: "classes", summary: "Classes, inheritance, polymorphism, RAII",
                importLine: "// class, struct, virtual, override, public/private/protected",
                items: ["class", "struct", "virtual", "override", "constructor/destructor", "copy/move", "operator overloading", "friend", "RAII"],
                example: "#include <iostream>\n#include <string>\nclass Animal {\npublic:\n    virtual std::string speak() const = 0;\n    virtual ~Animal() = default;\n};\nclass Dog : public Animal {\npublic:\n    std::string speak() const override { return \"Woof!\"; }\n};\nint main() {\n    Dog d;\n    std::cout << d.speak() << std::endl;\n}", language: "cpp"),
            LibraryModule(name: "STL containers", summary: "vector, map, set, deque, unordered_map, etc.",
                importLine: "#include <vector>\n#include <map>\n#include <set>",
                items: ["vector", "map", "unordered_map", "set", "unordered_set", "deque", "list", "stack", "queue", "priority_queue", "array", "string"],
                example: "#include <iostream>\n#include <vector>\n#include <algorithm>\nint main() {\n    std::vector<int> v = {5, 2, 8, 1, 9};\n    std::sort(v.begin(), v.end());\n    for (int x : v) std::cout << x << \" \";\n    std::cout << std::endl;\n}", language: "cpp"),
            LibraryModule(name: "templates", summary: "Function/class templates, concepts, SFINAE",
                importLine: "// template<typename T>, concepts (C++20), auto parameters",
                items: ["function templates", "class templates", "template specialization", "variadic templates", "concepts", "requires", "auto", "decltype"],
                example: "#include <iostream>\ntemplate<typename T>\nT maximum(T a, T b) { return a > b ? a : b; }\nint main() {\n    std::cout << maximum(3, 7) << std::endl;\n    std::cout << maximum(3.14, 2.71) << std::endl;\n}", language: "cpp"),
            LibraryModule(name: "lambdas", summary: "Lambda expressions with captures and generic lambdas",
                importLine: "// [capture](params) -> ret { body }",
                items: ["lambda expression", "capture by value [=]", "capture by ref [&]", "generic lambda", "mutable", "constexpr lambda", "std::function"],
                example: "#include <iostream>\n#include <vector>\n#include <algorithm>\nint main() {\n    std::vector<int> v = {1, 2, 3, 4, 5};\n    int sum = 0;\n    std::for_each(v.begin(), v.end(), [&sum](int x) { sum += x; });\n    std::cout << \"Sum: \" << sum << std::endl;\n}", language: "cpp"),
            LibraryModule(name: "exceptions", summary: "Exception handling with try/catch/throw",
                importLine: "#include <stdexcept>",
                items: ["try/catch", "throw", "std::exception", "std::runtime_error", "std::logic_error", "noexcept", "std::current_exception"],
                example: "#include <iostream>\n#include <stdexcept>\ndouble divide(double a, double b) {\n    if (b == 0) throw std::runtime_error(\"Division by zero\");\n    return a / b;\n}\nint main() {\n    try { std::cout << divide(10, 0) << std::endl; }\n    catch (const std::exception& e) { std::cout << \"Error: \" << e.what() << std::endl; }\n}", language: "cpp")
        ])
    }

    // MARK: Fortran Interpreter
    private static var fortranSection: LibrarySection {
        LibrarySection(name: "Fortran interpreter", icon: "f.square", modules: [
            LibraryModule(name: "program structure", summary: "Program, modules, subprograms, use statements",
                importLine: "program main\n  implicit none\n  ! code\nend program",
                items: ["program", "module", "use", "implicit none", "contains", "interface", "block", "associate"],
                example: "program hello\n  implicit none\n  character(len=20) :: name\n  name = 'World'\n  print *, 'Hello, ', trim(name), '!'\nend program hello", language: "fortran"),
            LibraryModule(name: "arrays", summary: "Multi-dimensional arrays, slicing, allocatable",
                importLine: "integer, dimension(:,:), allocatable :: matrix",
                items: ["dimension", "allocatable", "allocate/deallocate", "reshape", "size", "shape", "slicing", "where", "forall", "pack", "spread"],
                example: "program arrays\n  implicit none\n  integer :: A(3,3), i, j\n  A = reshape([(i, i=1,9)], [3,3])\n  print *, 'Matrix:'\n  do i = 1, 3\n    print *, (A(i,j), j=1,3)\n  end do\nend program", language: "fortran"),
            LibraryModule(name: "subroutines", summary: "Subroutines and functions with intent attributes",
                importLine: "subroutine sub(x, y, result)\n  intent(in) :: x, y\n  intent(out) :: result",
                items: ["subroutine", "function", "intent(in/out/inout)", "optional", "present", "result", "recursive", "elemental", "pure"],
                example: "program demo\n  implicit none\n  real :: r\n  call circle_area(5.0, r)\n  print *, 'Area:', r\ncontains\n  subroutine circle_area(radius, area)\n    real, intent(in) :: radius\n    real, intent(out) :: area\n    area = 3.14159 * radius**2\n  end subroutine\nend program", language: "fortran"),
            LibraryModule(name: "modules", summary: "Encapsulation, derived types, operator overloading",
                importLine: "module my_types\n  implicit none\n  type :: ...\nend module",
                items: ["module", "type", "type-bound procedures", "generic", "abstract", "extends", "private/public", "operator overloading"],
                example: "module vec_mod\n  implicit none\n  type :: Vec2D\n    real :: x, y\n  contains\n    procedure :: magnitude\n  end type\ncontains\n  real function magnitude(self)\n    class(Vec2D), intent(in) :: self\n    magnitude = sqrt(self%x**2 + self%y**2)\n  end function\nend module", language: "fortran"),
            LibraryModule(name: "intrinsics", summary: "Built-in math, string, array, and system functions",
                importLine: "! Intrinsic functions are always available",
                items: ["abs", "sqrt", "sin/cos/tan", "exp/log", "mod", "min/max", "sum/product", "matmul", "dot_product", "trim/len", "random_number", "cpu_time"],
                example: "program intrinsics\n  implicit none\n  real :: A(3,3), B(3,3), C(3,3)\n  call random_number(A)\n  call random_number(B)\n  C = matmul(A, B)\n  print *, 'Sum of C:', sum(C)\nend program", language: "fortran")
        ])
    }

    // MARK: Other Libraries
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
