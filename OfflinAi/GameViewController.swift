import UIKit
import UniformTypeIdentifiers
import WebKit
import llama

// MARK: - Rounded font convenience
private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

final class GameViewController: UIViewController {
    private enum ThinkingEffort: Int {
        case low = 0
        case medium = 1
        case high = 2

        var title: String {
            switch self {
            case .low:
                return "Low"
            case .medium:
                return "Medium"
            case .high:
                return "High"
            }
        }

        var instruction: String {
            switch self {
            case .low:
                return "Be concise and direct."
            case .medium:
                return "Think carefully and provide a detailed answer."
            case .high:
                return "Take your time and reason thoroughly before answering."
            }
        }

        var defaultMaxTokens: Int {
            switch self {
            case .low:
                return 8192
            case .medium:
                return 32768
            case .high:
                return 65536
            }
        }
    }

    private let runner = LlamaRunner()
    private let baseSystemPrompt = "You are a helpful assistant."
    private var conversations: [Conversation] = []
    private var currentConversationIndex: Int = 0
    private var messages: [ChatMessage] = []
    private var modelURLs: [ModelSlot: URL] = [:]
    private var isGenerating = false
    private var maxOutputTokens = 65536
    private var showThinking = false
    private var streamBuffer = ""
    private var isInThinkSection = false
    private var isInAnswerSection = false
    private var isInToolCallSection = false
    private var sawAnswerTag = false
    private var pendingStreamTokens = ""
    private var fullOutputBuffer = ""
    private var flushTimer: Timer?
    private var needsAssistantStart = false
    private let flushInterval: TimeInterval = 0.05
    private let maxReasoningChars = 4000
    private var reasoningTruncated = false
    private var currentAssistantIndex: Int?
    private var hasThinkSummary = false
    private var isSummarizingThinking = false
    private var thinkingCollapsed = false
    private var needsInitialScroll = false
    private var needsConversationReload = false
    private let autoLoadModelDefaultsKey = "model.autoload.enabled"
    private let pythonToolEnabledDefaultsKey = "tool.python.enabled"
    private let lastModelSlotDefaultsKey = "model.last.slot"
    private let lastModelPathDefaultsKey = "model.last.path"
    private var autoLoadAttempted = false
    private var didInitialConversationReload = false
    private var pythonToolsEnabled = true

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let sidebarView = UIView()
    private let sidebarBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let newChatButton = UIButton(type: .system)
    private let conversationSearchBar = UISearchBar()
    private let conversationsTable = UITableView(frame: .zero, style: .plain)
    private var filteredConversationIndices: [Int] = []
    private var conversationSearchQuery = ""
    private let conversationEmptyLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let contentView = UIView()
    private let modelLabel = UILabel()
    private let modelSelectButton = UIButton(type: .system)
    private let modelStateBadgeLabel = UILabel()
    private let modelPathLabel = UILabel()
    private let importButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private let loadButton = UIButton(type: .system)
    private let contentModeControl = UISegmentedControl(items: ["Editor", "Files", "Docs"])
    private let filesContainer = UIView()
    private var loadedModelSlot: ModelSlot?
    private var chatContainer: UIStackView?
    private var filesManagerController: ModelsManagerViewController?
    private let editorContainer = UIView()
    private let docsContainer = UIView()
    private var filesBrowserController: FilesBrowserViewController?
    private var docsController: LibraryDocsViewController?
    private var editorController: CodeEditorViewController?
    private let effortLabel = UILabel()
    private let effortSegment = UISegmentedControl(items: [ThinkingEffort.low.title, ThinkingEffort.medium.title, ThinkingEffort.high.title])
    private let thinkingToggleLabel = UILabel()
    private let thinkingToggle = UISwitch()
    private let maxTokensLabel = UILabel()
    private let maxTokensStepper = UIStepper()
    private let autoLoadLabel = UILabel()
    private let autoLoadToggle = UISwitch()
    private let pythonToolsLabel = UILabel()
    private let pythonToolsToggle = UISwitch()
    private let pythonStatusLabel = UILabel()
    private let pythonRefreshButton = UIButton(type: .system)
    private let pythonStatusIconLabel = UILabel()
    private var isRefreshingPythonStatus = false
    private let pythonLibraryProbeNames = ["numpy", "matplotlib", "plotly", "PIL", "scipy", "sklearn", "manim"]
    private var pythonLibraryStates: [String: PythonRuntime.LibraryProbe.State] = [:]
    private let chatScrollView = UIScrollView()
    private let chatStack = UIStackView()
    private var currentAssistantLabel: UITextView?
    private var currentAssistantBubble: MessageBubble?
    private var currentAssistantRow: UIView?
    private var typingRow: UIView?
    private var typingLabel: UITextView?
    private var typingTimer: Timer?
    private var typingStep = 0
    private let inputViewContainer = UIView()
    private let inputTextView = UITextView()
    private let inputPlaceholderLabel = UILabel()
    private var inputHeightConstraint: NSLayoutConstraint?
    private let sendButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let thinkingContainer = UIView()
    private let thinkingTitleLabel = UILabel()
    private let thinkingTextView = UITextView()
    private let thinkingCollapseButton = UIButton(type: .system)
    private var thinkingHeightConstraint: NSLayoutConstraint?
    private let backgroundLayer = CAGradientLayer()
    private let settingsPanel = UIView()
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var contentStackBottomConstraint: NSLayoutConstraint?
    private var selectedModelSlot: ModelSlot = .qwen35_4b
    private let gameTriggerKeyword = "game"
    private var easterGameView: UIView?
    private weak var activeGameInput: EasterGameKeyInput?
    private lazy var conversationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    private lazy var tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    private lazy var downloadSession: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
    }()
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSlot: ModelSlot?
    // Feature 8: Token stats
    private let tokenStatsLabel = UILabel()
    // Feature 9: Auto-scroll
    private let scrollToBottomButton = UIButton(type: .system)
    private var userPausedAutoScroll = false
    // Feature 16: Typing indicator dots
    private var typingDots: [UIView] = []

    // Inline thinking UI (modern style)
    private var thinkingBubbleRow: UIView?
    private var thinkingBubbleLabel: UITextView?
    private var thinkingBubbleContentStack: UIStackView?
    private var thinkingStartTime: Date?
    private var inlineThinkingText = ""
    private var thinkingPillRow: UIView?
    // Feature 14: Background task
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    // Feature 4: Share button
    private let shareButton = UIButton(type: .system)
    // Feature 11: RAG
    private var documentImporter: DocumentImporter?
    // Feature 18: Hamburger menu for compact mode
    private let hamburgerButton = UIButton(type: .system)
    private var isSidebarHidden = false
    // Feature 3: System prompt preset button
    private let presetButton = UIButton(type: .system)
    // Feature 6: Theme segment
    private let themeSegment = UISegmentedControl(items: ["System", "Light", "Dark"])
    // Feature 7: Haptics toggle
    private let hapticsToggleLabel = UILabel()
    private let hapticsToggle = UISwitch()
    private let maxTagTail = 64
    private let thinkOpenTags = ["<think>", "<thinking>", "<analysis>", "<reasoning>"]
    private let thinkCloseTags = ["</think>", "</thinking>", "</analysis>", "</reasoning>"]
    private let answerOpenTags = ["<answer>", "<final>", "<response>"]
    private let answerCloseTags = ["</answer>", "</final>", "</response>"]
    private let toolCallOpenTags = ["<tool_call>", "<|tool_call|>", "<|tool_call_start|>", "<tool>"]
    private let toolCallCloseTags = ["</tool_call>", "<|/tool_call|>", "<|tool_call_end|>", "</tool>"]
    private let controlTokens = [
        "<|assistant|>", "<|user|>", "<|system|>", "<|im_start|>", "<|im_end|>",
        "<|tools_start|>", "<|tools_end|>", "<|tool_response_start|>", "<|tool_response_end|>",
        "<tools>", "</tools>", "<tool_response>", "</tool_response>"
    ]
    private let maxToolOutputChars = 5000

    override var canBecomeFirstResponder: Bool {
        activeGameInput != nil
    }

    override var keyCommands: [UIKeyCommand]? {
        activeGameInput?.makeKeyCommands(target: self, action: #selector(handleGameKeyCommand(_:)))
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let input = activeGameInput {
            input.handlePresses(presses, isDown: true)
        } else {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let input = activeGameInput {
            input.handlePresses(presses, isDown: false)
        } else {
            super.pressesEnded(presses, with: event)
        }
    }

    @objc private func handleGameKeyCommand(_ command: UIKeyCommand) {
        activeGameInput?.handleKeyCommand(command)
    }

    private struct MessageBubble {
        let view: UIView
        let label: UITextView
        let contentStack: UIStackView
    }

    private final class LaTeXView: UIView, WKNavigationDelegate {
        private let webView: WKWebView
        private var heightConstraint: NSLayoutConstraint?

        private struct KaTeXPaths {
            let css: String
            let js: String
            let autoRender: String
        }

        override init(frame: CGRect) {
            let config = WKWebViewConfiguration()
            self.webView = WKWebView(frame: .zero, configuration: config)
            super.init(frame: frame)

            webView.navigationDelegate = self
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            heightConstraint = heightAnchor.constraint(equalToConstant: 24)
            heightConstraint?.priority = .defaultHigh
            heightConstraint?.isActive = true
        }

        required init?(coder: NSCoder) {
            return nil
        }

        @discardableResult
        func render(latex text: String, textColor: UIColor) -> Bool {
            guard let paths = Self.resolveKaTeXPaths() else {
                return false
            }
            let escaped = Self.escapeHTML(text)
            let colorHex = textColor.hexString
            let resourceBase = Bundle.main.resourceURL
            let baseURL = resourceBase
            let html = """
            <!doctype html>
            <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <link rel="stylesheet" href="\(paths.css)">
                <script defer src="\(paths.js)"></script>
                <script defer src="\(paths.autoRender)"></script>
                <style>
                  body { margin: 0; font-family: -apple-system, "Avenir Next", sans-serif; font-size: 15px; color: \(colorHex); }
                  .content { white-space: pre-wrap; line-height: 1.35; }
                </style>
              </head>
              <body>
                <div id="content" class="content">\(escaped)</div>
                <script>
                  function renderMathNow() {
                    if (typeof renderMathInElement !== "function") { return false; }
                    renderMathInElement(document.getElementById("content"), {
                      delimiters: [
                        {left: "$$", right: "$$", display: true},
                        {left: "\\\\[", right: "\\\\]", display: true},
                        {left: "\\\\(", right: "\\\\)", display: false},
                        {left: "$", right: "$", display: false}
                      ],
                      throwOnError: false
                    });
                    return true;
                  }
                  function tryRender(retries) {
                    if (renderMathNow()) { return; }
                    if (retries <= 0) { return; }
                    setTimeout(function() { tryRender(retries - 1); }, 60);
                  }
                  document.addEventListener("DOMContentLoaded", function() {
                    tryRender(8);
                  });
                  window.addEventListener("load", function() {
                    tryRender(8);
                  });
                </script>
              </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: baseURL)
            return true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("typeof renderMathNow === 'function' ? renderMathNow() : false", completionHandler: nil)
            scheduleHeightChecks()
        }

        private func scheduleHeightChecks() {
            let delays: [TimeInterval] = [0.0, 0.1, 0.3, 0.6]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.measureHeight()
                }
            }
        }

        private func measureHeight() {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let self else { return }
                if let height = result as? CGFloat {
                    self.heightConstraint?.constant = max(24, height)
                } else if let heightNumber = result as? NSNumber {
                    self.heightConstraint?.constant = max(24, CGFloat(truncating: heightNumber))
                }
            }
        }

        private static func escapeHTML(_ string: String) -> String {
            var result = string
            result = result.replacingOccurrences(of: "&", with: "&amp;")
            result = result.replacingOccurrences(of: "<", with: "&lt;")
            result = result.replacingOccurrences(of: ">", with: "&gt;")
            result = result.replacingOccurrences(of: "\"", with: "&quot;")
            result = result.replacingOccurrences(of: "'", with: "&#39;")
            result = result.replacingOccurrences(of: "\n", with: "<br>")
            return result
        }

        private static func resolveKaTeXPaths() -> KaTeXPaths? {
            let bundle = Bundle.main
            let hasFolderLayout = bundle.url(forResource: "katex.min", withExtension: "css", subdirectory: "KaTeX") != nil
                && bundle.url(forResource: "katex.min", withExtension: "js", subdirectory: "KaTeX") != nil
                && bundle.url(forResource: "auto-render.min", withExtension: "js", subdirectory: "KaTeX") != nil
            if hasFolderLayout {
                return KaTeXPaths(css: "KaTeX/katex.min.css", js: "KaTeX/katex.min.js", autoRender: "KaTeX/auto-render.min.js")
            }

            let hasFlatLayout = bundle.url(forResource: "katex.min", withExtension: "css") != nil
                && bundle.url(forResource: "katex.min", withExtension: "js") != nil
                && bundle.url(forResource: "auto-render.min", withExtension: "js") != nil
            if hasFlatLayout {
                return KaTeXPaths(css: "katex.min.css", js: "katex.min.js", autoRender: "auto-render.min.js")
            }

            return nil
        }
    }

    private enum EasterGameKind: String, CaseIterable {
        case breaker
        case snake
        case asteroids
        case tetris
        case dino
    }

    private protocol EasterGamePlayable: AnyObject {
        var onClose: (() -> Void)? { get set }
        func start()
    }

    private protocol EasterGameKeyInput: AnyObject {
        func makeKeyCommands(target: Any, action: Selector) -> [UIKeyCommand]
        func handleKeyCommand(_ command: UIKeyCommand)
        func handlePresses(_ presses: Set<UIPress>, isDown: Bool)
    }

    private final class EasterGameView: UIView, EasterGamePlayable, EasterGameKeyInput {
        private enum GameState {
            case idle
            case playing
            case ended
        }

        private struct Brick {
            var view: UIView
            var row: Int
            var col: Int
        }

        private let backgroundLayer = CAGradientLayer()
        private let starFieldView = UIImageView()
        private let hudView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        private let titleLabel = UILabel()
        private let scoreLabel = UILabel()
        private let livesLabel = UILabel()
        private let levelLabel = UILabel()
        private let closeButton = UIButton(type: .system)
        private let restartButton = UIButton(type: .system)
        private let overlayView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        private let overlayTitleLabel = UILabel()
        private let overlaySubtitleLabel = UILabel()
        private let overlayButton = UIButton(type: .system)
        private let paddleView = UIView()
        private let ballView = UIView()

        private var bricks: [Brick] = []
        private var displayLink: CADisplayLink?
        private var lastFrameTime: CFTimeInterval = 0
        private var ballVelocity = CGVector(dx: 0, dy: 0)
        private var ballSpeed: CGFloat = 420
        private var isBallLaunched = false
        private var score = 0
        private var lives = 3
        private var level = 1
        private var gameState: GameState = .idle
        private var paddleTargetX: CGFloat = 0
        private var leftPressed = false
        private var rightPressed = false
        private var parallaxOffset: CGFloat = 0
        private let bestScoreKey = "offlinai.easter.bestScore"
        private let brickRowsBase = 5
        private let brickCols = 8
        private let ballRadius: CGFloat = 7.5
        private let keyboardSpeed: CGFloat = 560

        var onClose: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            return nil
        }

        deinit {
            stopDisplayLink()
        }

        func start() {
            resetSession()
            prepareLevel()
            showOverlay(title: "Starlight Breaker",
                        subtitle: "Drag or use ← → / A D to move.\nTap or press Space to launch. Clear bricks to level up.")
            becomeFirstResponder()
        }

        private func resetSession() {
            gameState = .idle
            score = 0
            lives = 3
            level = 1
            ballSpeed = 420
            isBallLaunched = false
            updateLabels()
            restartButton.isHidden = true
        }

        private func prepareLevel() {
            clearBricks()
            createBricks(rows: brickRowsBase + min(level - 1, 2), cols: brickCols)
            isBallLaunched = false
            ballVelocity = .zero
            setNeedsLayout()
            updateLabels()
        }

        private func setupView() {
            backgroundColor = .clear
            backgroundLayer.colors = [
                UIColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1.0).cgColor,
                UIColor(red: 0.12, green: 0.18, blue: 0.32, alpha: 1.0).cgColor
            ]
            backgroundLayer.startPoint = CGPoint(x: 0, y: 0)
            backgroundLayer.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(backgroundLayer)

            starFieldView.contentMode = .scaleAspectFill
            starFieldView.alpha = 0.9
            addSubview(starFieldView)

            hudView.layer.cornerRadius = 18
            hudView.layer.masksToBounds = true
            addSubview(hudView)

            titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 16) ?? UIFont.systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textColor = UIColor.label
            titleLabel.text = "Starlight Breaker"

            scoreLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            scoreLabel.textColor = UIColor.label

            livesLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            livesLabel.textColor = UIColor.label

            levelLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            levelLabel.textColor = UIColor.label

            closeButton.setTitle("Close", for: .normal)
            closeButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

            restartButton.setTitle("Restart", for: .normal)
            restartButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            restartButton.isHidden = true
            restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)

            let hudStack = UIStackView(arrangedSubviews: [titleLabel, scoreLabel, livesLabel, levelLabel, UIView(), restartButton, closeButton])
            hudStack.axis = .horizontal
            hudStack.spacing = 10
            hudStack.alignment = .center
            hudStack.translatesAutoresizingMaskIntoConstraints = false
            hudView.contentView.addSubview(hudStack)
            NSLayoutConstraint.activate([
                hudStack.topAnchor.constraint(equalTo: hudView.contentView.topAnchor, constant: 10),
                hudStack.leadingAnchor.constraint(equalTo: hudView.contentView.leadingAnchor, constant: 12),
                hudStack.trailingAnchor.constraint(equalTo: hudView.contentView.trailingAnchor, constant: -12),
                hudStack.bottomAnchor.constraint(equalTo: hudView.contentView.bottomAnchor, constant: -10)
            ])

            paddleView.backgroundColor = UIColor.systemTeal
            paddleView.layer.cornerRadius = 8
            paddleView.layer.shadowColor = UIColor.black.withAlphaComponent(0.25).cgColor
            paddleView.layer.shadowOffset = CGSize(width: 0, height: 4)
            paddleView.layer.shadowRadius = 6
            paddleView.layer.shadowOpacity = 0.5
            addSubview(paddleView)

            ballView.backgroundColor = UIColor.white
            ballView.layer.cornerRadius = ballRadius
            ballView.layer.shadowColor = UIColor.black.withAlphaComponent(0.25).cgColor
            ballView.layer.shadowOffset = CGSize(width: 0, height: 2)
            ballView.layer.shadowRadius = 4
            ballView.layer.shadowOpacity = 0.4
            addSubview(ballView)

            overlayView.layer.cornerRadius = 20
            overlayView.layer.masksToBounds = true
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(overlayView)

            overlayTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
            overlayTitleLabel.textColor = .white
            overlayTitleLabel.textAlignment = .center

            overlaySubtitleLabel.font = UIFont(name: "AvenirNext-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
            overlaySubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            overlaySubtitleLabel.textAlignment = .center
            overlaySubtitleLabel.numberOfLines = 0

            overlayButton.setTitle("Start", for: .normal)
            overlayButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
            overlayButton.tintColor = .white
            overlayButton.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.85)
            overlayButton.layer.cornerRadius = 16
            overlayButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

            let overlayStack = UIStackView(arrangedSubviews: [overlayTitleLabel, overlaySubtitleLabel, overlayButton])
            overlayStack.axis = .vertical
            overlayStack.spacing = 12
            overlayStack.alignment = .center
            overlayStack.translatesAutoresizingMaskIntoConstraints = false
            overlayView.contentView.addSubview(overlayStack)
            NSLayoutConstraint.activate([
                overlayStack.topAnchor.constraint(equalTo: overlayView.contentView.topAnchor, constant: 20),
                overlayStack.leadingAnchor.constraint(equalTo: overlayView.contentView.leadingAnchor, constant: 20),
                overlayStack.trailingAnchor.constraint(equalTo: overlayView.contentView.trailingAnchor, constant: -20),
                overlayStack.bottomAnchor.constraint(equalTo: overlayView.contentView.bottomAnchor, constant: -20),
                overlayButton.heightAnchor.constraint(equalToConstant: 40),
                overlayButton.widthAnchor.constraint(equalToConstant: 140)
            ])

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            addGestureRecognizer(pan)
            addGestureRecognizer(tap)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            backgroundLayer.frame = bounds
            starFieldView.frame = bounds.insetBy(dx: -30, dy: -30)
            starFieldView.image = starFieldView.image ?? Self.makeStarFieldImage(size: starFieldView.bounds.size)

            let safe = safeAreaInsets
            let hudHeight: CGFloat = 60
            hudView.frame = CGRect(x: 18, y: safe.top + 12, width: bounds.width - 36, height: hudHeight)

            let overlayWidth = min(bounds.width - 40, 360)
            overlayView.frame = CGRect(x: (bounds.width - overlayWidth) / 2,
                                       y: (bounds.height - 220) / 2,
                                       width: overlayWidth,
                                       height: 220)

            layoutPaddle()
            layoutBricks()
            if !isBallLaunched {
                positionBallOnPaddle()
            }
        }

        private func showOverlay(title: String, subtitle: String) {
            overlayTitleLabel.text = title
            overlaySubtitleLabel.text = subtitle
            overlayButton.setTitle("Start", for: .normal)
            overlayView.isHidden = false
            overlayView.alpha = 1.0
            gameState = .idle
        }

        override var canBecomeFirstResponder: Bool {
            true
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                becomeFirstResponder()
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            makeKeyCommands(target: self, action: #selector(handleKeyCommandProxy(_:)))
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: true)
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: false)
            super.pressesEnded(presses, with: event)
        }

        func makeKeyCommands(target: Any, action: Selector) -> [UIKeyCommand] {
            [
                UIKeyCommand(input: " ", modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: "a", modifierFlags: [], action: action),
                UIKeyCommand(input: "d", modifierFlags: [], action: action)
            ]
        }

        @objc private func handleKeyCommandProxy(_ command: UIKeyCommand) {
            handleKeyCommand(command)
        }

        func handleKeyCommand(_ command: UIKeyCommand) {
            switch command.input {
            case " ", UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow, "a", "d":
                if command.input == " " {
                    launchBallIfNeeded()
                } else if command.input == UIKeyCommand.inputLeftArrow || command.input == "a" {
                    nudgePaddle(by: -40)
                } else {
                    nudgePaddle(by: 40)
                }
            default:
                break
            }
        }

        func handlePresses(_ presses: Set<UIPress>, isDown: Bool) {
            for press in presses {
                guard let key = press.key else { continue }
                switch key.keyCode {
                case .keyboardLeftArrow, .keyboardA:
                    leftPressed = isDown
                case .keyboardRightArrow, .keyboardD:
                    rightPressed = isDown
                case .keyboardSpacebar:
                    if isDown {
                        launchBallIfNeeded()
                    }
                default:
                    break
                }
            }
        }

        @objc private func handleKeyLaunch() {
            launchBallIfNeeded()
        }

        @objc private func handleKeyLeftTap() {
            nudgePaddle(by: -40)
        }

        @objc private func handleKeyRightTap() {
            nudgePaddle(by: 40)
        }

        private func nudgePaddle(by delta: CGFloat) {
            paddleTargetX += delta
            layoutPaddle()
            if !isBallLaunched {
                positionBallOnPaddle()
            }
        }

        @objc private func startTapped() {
            if gameState == .ended {
                resetSession()
                prepareLevel()
            }
            overlayView.isHidden = true
            restartButton.isHidden = true
            gameState = .playing
            startDisplayLink()
        }

        private func startDisplayLink() {
            stopDisplayLink()
            lastFrameTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink?.add(to: .main, forMode: .common)
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func updateLabels() {
            scoreLabel.text = "Score \(score)"
            livesLabel.text = "Lives \(lives)"
            levelLabel.text = "Level \(level)"
        }

        private func layoutPaddle() {
            let safe = safeAreaInsets
            let baseWidth = min(max(bounds.width * 0.3, 92), 180)
            let shrinkFactor = max(0.6, 1.0 - CGFloat(max(0, level - 1)) * 0.06)
            let paddleWidth = max(70, baseWidth * shrinkFactor)
            let paddleHeight: CGFloat = 16
            let y = bounds.height - safe.bottom - 70
            if paddleView.frame == .zero {
                paddleTargetX = bounds.midX
            }
            let minX = paddleWidth / 2 + 14
            let maxX = bounds.width - paddleWidth / 2 - 14
            let clampedX = min(max(paddleTargetX, minX), maxX)
            paddleView.frame = CGRect(x: clampedX - paddleWidth / 2, y: y, width: paddleWidth, height: paddleHeight)
            paddleView.layer.cornerRadius = paddleHeight / 2
        }

        private func positionBallOnPaddle() {
            let diameter = ballRadius * 2
            ballView.frame = CGRect(x: paddleView.frame.midX - ballRadius,
                                    y: paddleView.frame.minY - diameter - 6,
                                    width: diameter,
                                    height: diameter)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gameState == .playing else { return }
            launchBallIfNeeded()
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: self)
            paddleTargetX = location.x
            layoutPaddle()
            if !isBallLaunched {
                positionBallOnPaddle()
            }
        }

        private func launchBall() {
            isBallLaunched = true
            let angle = CGFloat.random(in: -0.6...0.6)
            ballVelocity = CGVector(dx: ballSpeed * sin(angle), dy: -ballSpeed * cos(angle))
        }

        private func launchBallIfNeeded() {
            guard gameState == .playing else { return }
            if !isBallLaunched {
                launchBall()
            }
        }

        @objc private func step(_ link: CADisplayLink) {
            guard gameState == .playing else { return }
            let now = link.timestamp
            let dt = min(1.0 / 30.0, now - lastFrameTime)
            lastFrameTime = now

            parallaxOffset += CGFloat(dt * 14)
            if parallaxOffset > 24 { parallaxOffset = 0 }
            starFieldView.transform = CGAffineTransform(translationX: 0, y: -parallaxOffset)

            if leftPressed != rightPressed {
                let direction: CGFloat = leftPressed ? -1 : 1
                paddleTargetX += direction * keyboardSpeed * CGFloat(dt)
                layoutPaddle()
                if !isBallLaunched {
                    positionBallOnPaddle()
                }
            }

            if !isBallLaunched {
                positionBallOnPaddle()
                return
            }

            var frame = ballView.frame
            frame.origin.x += ballVelocity.dx * CGFloat(dt)
            frame.origin.y += ballVelocity.dy * CGFloat(dt)

            let topLimit = max(hudView.frame.maxY + 16, safeAreaInsets.top + 90)
            if frame.minX <= 0 {
                frame.origin.x = 0
                ballVelocity.dx *= -1
            }
            if frame.maxX >= bounds.width {
                frame.origin.x = bounds.width - frame.width
                ballVelocity.dx *= -1
            }
            if frame.minY <= topLimit {
                frame.origin.y = topLimit
                ballVelocity.dy *= -1
            }

            if frame.intersects(paddleView.frame), ballVelocity.dy > 0 {
                frame.origin.y = paddleView.frame.minY - frame.height - 1
                let relative = (frame.midX - paddleView.frame.midX) / (paddleView.bounds.width / 2)
                let clamped = min(max(relative, -1), 1)
                let angle = clamped * (CGFloat.pi / 3)
                ballVelocity.dx = ballSpeed * sin(angle)
                ballVelocity.dy = -ballSpeed * cos(angle)
            }

            if let newFrame = handleBrickCollisions(frame: frame) {
                frame = newFrame
            }

            ballView.frame = frame

            if frame.minY > bounds.height {
                loseBall()
            }
        }

        private func handleBrickCollisions(frame: CGRect) -> CGRect? {
            guard !bricks.isEmpty else { return nil }
            let updatedFrame = frame
            var hitBrick = false

            for index in (0..<bricks.count).reversed() {
                let brick = bricks[index]
                let brickFrame = brick.view.frame
                if updatedFrame.intersects(brickFrame) {
                    hitBrick = true
                    bricks[index].view.removeFromSuperview()
                    bricks.remove(at: index)
                    score += 10 + (level - 1) * 2
                    ballSpeed = min(640, ballSpeed + 4)
                    normalizeBallVelocity()
                    let intersection = updatedFrame.intersection(brickFrame)
                    if intersection.width < intersection.height {
                        ballVelocity.dx *= -1
                    } else {
                        ballVelocity.dy *= -1
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    break
                }
            }

            if hitBrick {
                updateLabels()
                if bricks.isEmpty {
                    advanceLevel()
                }
                return updatedFrame
            }
            return nil
        }

        private func loseBall() {
            lives -= 1
            updateLabels()
            if lives <= 0 {
                endGame()
            } else {
                isBallLaunched = false
                ballVelocity = .zero
                positionBallOnPaddle()
            }
        }

        private func advanceLevel() {
            level += 1
            ballSpeed = min(640, ballSpeed + 45)
            updateLabels()
            prepareLevel()
            stopDisplayLink()
            showOverlay(title: "Level \(level)", subtitle: "Nice! Tap Start when you are ready.")
        }

        private func normalizeBallVelocity() {
            let magnitude = max(1, hypot(ballVelocity.dx, ballVelocity.dy))
            ballVelocity = CGVector(dx: ballVelocity.dx / magnitude * ballSpeed,
                                    dy: ballVelocity.dy / magnitude * ballSpeed)
        }

        private func endGame() {
            gameState = .ended
            stopDisplayLink()
            let best = max(score, UserDefaults.standard.integer(forKey: bestScoreKey))
            UserDefaults.standard.set(best, forKey: bestScoreKey)
            updateLabels()
            restartButton.isHidden = false
            overlayView.isHidden = false
            overlayTitleLabel.text = "Game over"
            overlaySubtitleLabel.text = "Score \(score)  Best \(best)\nTap Play Again to retry."
            overlayButton.setTitle("Play again", for: .normal)
        }

        @objc private func closeTapped() {
            stopDisplayLink()
            onClose?()
        }

        @objc private func restartTapped() {
            resetSession()
            prepareLevel()
            showOverlay(title: "Starlight Breaker",
                        subtitle: "Drag or use ← → / A D to move.\nTap or press Space to launch. Clear bricks to level up.")
        }

        private func createBricks(rows: Int, cols: Int) {
            guard rows > 0, cols > 0 else { return }
            let palette: [UIColor] = [
                UIColor.systemPink,
                UIColor.systemOrange,
                UIColor.systemYellow,
                UIColor.systemGreen,
                UIColor.systemTeal,
                UIColor.systemBlue
            ]
            for row in 0..<rows {
                for col in 0..<cols {
                    let brickView = UIView()
                    brickView.layer.cornerRadius = 6
                    brickView.backgroundColor = palette[row % palette.count].withAlphaComponent(0.92)
                    addSubview(brickView)
                    bricks.append(Brick(view: brickView, row: row, col: col))
                }
            }
        }

        private func layoutBricks() {
            guard !bricks.isEmpty else { return }
            let safe = safeAreaInsets
            let top = max(hudView.frame.maxY + 20, safe.top + 100)
            let sideMargin: CGFloat = 18
            let spacing: CGFloat = 8
            let totalSpacing = spacing * CGFloat(brickCols - 1)
            let availableWidth = bounds.width - sideMargin * 2 - totalSpacing
            let brickWidth = max(24, availableWidth / CGFloat(brickCols))
            let brickHeight: CGFloat = 18

            for brick in bricks {
                let x = sideMargin + CGFloat(brick.col) * (brickWidth + spacing)
                let y = top + CGFloat(brick.row) * (brickHeight + spacing)
                brick.view.frame = CGRect(x: x, y: y, width: brickWidth, height: brickHeight)
            }
        }

        private func clearBricks() {
            for brick in bricks {
                brick.view.removeFromSuperview()
            }
            bricks.removeAll()
        }

        private static func makeStarFieldImage(size: CGSize) -> UIImage? {
            guard size.width > 0, size.height > 0 else { return nil }
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let count = Int((size.width * size.height) / 2200)
                for _ in 0..<max(400, count) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let radius = CGFloat.random(in: 0.5...1.9)
                    let alpha = CGFloat.random(in: 0.35...0.9)
                    UIColor.white.withAlphaComponent(alpha).setFill()
                    ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
                }
            }
        }
    }

    private final class GamePickerView: UIView {
        private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        private let titleLabel = UILabel()
        private let subtitleLabel = UILabel()
        private let stackView = UIStackView()
        private let closeButton = UIButton(type: .system)

        var onSelect: ((EasterGameKind) -> Void)?
        var onClose: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            return nil
        }

        func start() {
            alpha = 0
            UIView.animate(withDuration: 0.2) {
                self.alpha = 1
            }
        }

        private func setupView() {
            backgroundColor = UIColor.black.withAlphaComponent(0.55)
            backgroundView.layer.cornerRadius = 22
            backgroundView.layer.masksToBounds = true
            addSubview(backgroundView)

            titleLabel.text = "Secret Arcade"
            titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.textAlignment = .center

            subtitleLabel.text = "Pick a hidden game to launch."
            subtitleLabel.font = UIFont(name: "AvenirNext-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
            subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
            subtitleLabel.textAlignment = .center

            stackView.axis = .vertical
            stackView.spacing = 10
            stackView.alignment = .fill

            let buttons: [(String, EasterGameKind)] = [
                ("Starlight Breaker", .breaker),
                ("Snake", .snake),
                ("Asteroids", .asteroids),
                ("Tetris", .tetris),
                ("Dino Dash vs AI", .dino)
            ]

            for (title, kind) in buttons {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
                button.tintColor = .white
                button.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.85)
                button.layer.cornerRadius = 14
                button.heightAnchor.constraint(equalToConstant: 44).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    self?.onSelect?(kind)
                }, for: .touchUpInside)
                stackView.addArrangedSubview(button)
            }

            closeButton.setTitle("Close", for: .normal)
            closeButton.titleLabel?.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            closeButton.tintColor = UIColor.white.withAlphaComponent(0.85)
            closeButton.addAction(UIAction { [weak self] _ in
                self?.onClose?()
            }, for: .touchUpInside)

            let contentStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, stackView, closeButton])
            contentStack.axis = .vertical
            contentStack.spacing = 14
            contentStack.alignment = .fill
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.contentView.addSubview(contentStack)

            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
                backgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),
                backgroundView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.76),

                contentStack.topAnchor.constraint(equalTo: backgroundView.contentView.topAnchor, constant: 20),
                contentStack.leadingAnchor.constraint(equalTo: backgroundView.contentView.leadingAnchor, constant: 20),
                contentStack.trailingAnchor.constraint(equalTo: backgroundView.contentView.trailingAnchor, constant: -20),
                contentStack.bottomAnchor.constraint(equalTo: backgroundView.contentView.bottomAnchor, constant: -20)
            ])
        }
    }

    private final class SnakeGameView: UIView, EasterGamePlayable, EasterGameKeyInput {
        private enum GameState {
            case idle
            case playing
            case ended
        }

        private struct GridPoint: Hashable {
            var x: Int
            var y: Int
        }

        private let backgroundLayer = CAGradientLayer()
        private let boardLayer = CAShapeLayer()
        private let foodLayer = CAShapeLayer()
        private let hudView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        private let titleLabel = UILabel()
        private let scoreLabel = UILabel()
        private let bestLabel = UILabel()
        private let speedLabel = UILabel()
        private let closeButton = UIButton(type: .system)
        private let restartButton = UIButton(type: .system)
        private let overlayView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        private let overlayTitleLabel = UILabel()
        private let overlaySubtitleLabel = UILabel()
        private let overlayButton = UIButton(type: .system)

        private var displayLink: CADisplayLink?
        private var lastFrameTime: CFTimeInterval = 0
        private var tickAccumulator: TimeInterval = 0
        private var tickInterval: TimeInterval = 0.14
        private var gridSize = 20
        private var boardRect: CGRect = .zero
        private var cellSize: CGFloat = 14
        private var snake: [GridPoint] = []
        private var direction = GridPoint(x: 1, y: 0)
        private var pendingDirection = GridPoint(x: 1, y: 0)
        private var food = GridPoint(x: 10, y: 10)
        private var score = 0
        private var best = 0
        private var gameState: GameState = .idle

        var onClose: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            return nil
        }

        deinit {
            stopDisplayLink()
        }

        func start() {
            resetGame()
            showOverlay(title: "Snake", subtitle: "Use arrows/WASD or swipe to turn.\nEat orbs and avoid walls.")
            becomeFirstResponder()
        }

        override var canBecomeFirstResponder: Bool {
            true
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                becomeFirstResponder()
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            makeKeyCommands(target: self, action: #selector(handleKeyCommandProxy(_:)))
        }

        @objc private func handleUp() { setDirection(x: 0, y: -1) }
        @objc private func handleDown() { setDirection(x: 0, y: 1) }
        @objc private func handleLeft() { setDirection(x: -1, y: 0) }
        @objc private func handleRight() { setDirection(x: 1, y: 0) }

        func makeKeyCommands(target: Any, action: Selector) -> [UIKeyCommand] {
            [
                UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: "w", modifierFlags: [], action: action),
                UIKeyCommand(input: "s", modifierFlags: [], action: action),
                UIKeyCommand(input: "a", modifierFlags: [], action: action),
                UIKeyCommand(input: "d", modifierFlags: [], action: action)
            ]
        }

        @objc private func handleKeyCommandProxy(_ command: UIKeyCommand) {
            handleKeyCommand(command)
        }

        func handleKeyCommand(_ command: UIKeyCommand) {
            switch command.input {
            case UIKeyCommand.inputUpArrow, "w":
                setDirection(x: 0, y: -1)
            case UIKeyCommand.inputDownArrow, "s":
                setDirection(x: 0, y: 1)
            case UIKeyCommand.inputLeftArrow, "a":
                setDirection(x: -1, y: 0)
            case UIKeyCommand.inputRightArrow, "d":
                setDirection(x: 1, y: 0)
            default:
                break
            }
        }

        func handlePresses(_ presses: Set<UIPress>, isDown: Bool) {
            guard isDown else { return }
            for press in presses {
                guard let key = press.key else { continue }
                switch key.keyCode {
                case .keyboardUpArrow, .keyboardW:
                    setDirection(x: 0, y: -1)
                case .keyboardDownArrow, .keyboardS:
                    setDirection(x: 0, y: 1)
                case .keyboardLeftArrow, .keyboardA:
                    setDirection(x: -1, y: 0)
                case .keyboardRightArrow, .keyboardD:
                    setDirection(x: 1, y: 0)
                default:
                    break
                }
            }
        }

        private func setDirection(x: Int, y: Int) {
            guard gameState == .playing else { return }
            if direction.x == -x && direction.y == -y { return }
            pendingDirection = GridPoint(x: x, y: y)
        }

        private func resetGame() {
            gameState = .idle
            score = 0
            best = UserDefaults.standard.integer(forKey: "offlinai.snake.best")
            tickInterval = 0.14
            direction = GridPoint(x: 1, y: 0)
            pendingDirection = direction
            snake = [GridPoint(x: 6, y: 10), GridPoint(x: 5, y: 10), GridPoint(x: 4, y: 10)]
            spawnFood()
            updateLabels()
            restartButton.isHidden = true
            renderBoard()
        }

        private func setupView() {
            backgroundColor = .clear
            backgroundLayer.colors = [
                UIColor(red: 0.05, green: 0.08, blue: 0.14, alpha: 1.0).cgColor,
                UIColor(red: 0.10, green: 0.14, blue: 0.25, alpha: 1.0).cgColor
            ]
            backgroundLayer.startPoint = CGPoint(x: 0, y: 0)
            backgroundLayer.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(backgroundLayer)

            boardLayer.fillColor = UIColor.systemTeal.withAlphaComponent(0.9).cgColor
            boardLayer.strokeColor = UIColor.clear.cgColor
            layer.addSublayer(boardLayer)

            foodLayer.fillColor = UIColor.systemPink.cgColor
            layer.addSublayer(foodLayer)

            hudView.layer.cornerRadius = 18
            hudView.layer.masksToBounds = true
            addSubview(hudView)

            titleLabel.text = "Snake"
            titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 16) ?? UIFont.systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textColor = UIColor.label

            scoreLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            bestLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            speedLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            scoreLabel.textColor = UIColor.label
            bestLabel.textColor = UIColor.label
            speedLabel.textColor = UIColor.label

            closeButton.setTitle("Close", for: .normal)
            closeButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

            restartButton.setTitle("Restart", for: .normal)
            restartButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            restartButton.isHidden = true
            restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)

            let hudStack = UIStackView(arrangedSubviews: [titleLabel, scoreLabel, bestLabel, speedLabel, UIView(), restartButton, closeButton])
            hudStack.axis = .horizontal
            hudStack.spacing = 10
            hudStack.alignment = .center
            hudStack.translatesAutoresizingMaskIntoConstraints = false
            hudView.contentView.addSubview(hudStack)
            NSLayoutConstraint.activate([
                hudStack.topAnchor.constraint(equalTo: hudView.contentView.topAnchor, constant: 10),
                hudStack.leadingAnchor.constraint(equalTo: hudView.contentView.leadingAnchor, constant: 12),
                hudStack.trailingAnchor.constraint(equalTo: hudView.contentView.trailingAnchor, constant: -12),
                hudStack.bottomAnchor.constraint(equalTo: hudView.contentView.bottomAnchor, constant: -10)
            ])

            overlayView.layer.cornerRadius = 20
            overlayView.layer.masksToBounds = true
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(overlayView)

            overlayTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
            overlayTitleLabel.textColor = .white
            overlayTitleLabel.textAlignment = .center

            overlaySubtitleLabel.font = UIFont(name: "AvenirNext-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
            overlaySubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            overlaySubtitleLabel.textAlignment = .center
            overlaySubtitleLabel.numberOfLines = 0

            overlayButton.setTitle("Start", for: .normal)
            overlayButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
            overlayButton.tintColor = .white
            overlayButton.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.85)
            overlayButton.layer.cornerRadius = 16
            overlayButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

            let overlayStack = UIStackView(arrangedSubviews: [overlayTitleLabel, overlaySubtitleLabel, overlayButton])
            overlayStack.axis = .vertical
            overlayStack.spacing = 12
            overlayStack.alignment = .center
            overlayStack.translatesAutoresizingMaskIntoConstraints = false
            overlayView.contentView.addSubview(overlayStack)
            NSLayoutConstraint.activate([
                overlayStack.topAnchor.constraint(equalTo: overlayView.contentView.topAnchor, constant: 20),
                overlayStack.leadingAnchor.constraint(equalTo: overlayView.contentView.leadingAnchor, constant: 20),
                overlayStack.trailingAnchor.constraint(equalTo: overlayView.contentView.trailingAnchor, constant: -20),
                overlayStack.bottomAnchor.constraint(equalTo: overlayView.contentView.bottomAnchor, constant: -20),
                overlayButton.heightAnchor.constraint(equalToConstant: 40),
                overlayButton.widthAnchor.constraint(equalToConstant: 140)
            ])

            let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipeUp.direction = .up
            let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipeDown.direction = .down
            let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipeLeft.direction = .left
            let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipeRight.direction = .right
            addGestureRecognizer(swipeUp)
            addGestureRecognizer(swipeDown)
            addGestureRecognizer(swipeLeft)
            addGestureRecognizer(swipeRight)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            backgroundLayer.frame = bounds
            boardLayer.frame = bounds
            foodLayer.frame = bounds
            let safe = safeAreaInsets
            let hudHeight: CGFloat = 58
            hudView.frame = CGRect(x: 18, y: safe.top + 12, width: bounds.width - 36, height: hudHeight)
            let boardTop = hudView.frame.maxY + 16
            let boardSide: CGFloat = 26
            let maxWidth = bounds.width - boardSide * 2
            let maxHeight = bounds.height - boardTop - safe.bottom - 30
            let cell = min(maxWidth / CGFloat(gridSize), maxHeight / CGFloat(gridSize))
            cellSize = max(10, cell)
            let boardWidth = cellSize * CGFloat(gridSize)
            let boardHeight = cellSize * CGFloat(gridSize)
            let boardX = (bounds.width - boardWidth) / 2
            boardRect = CGRect(x: boardX, y: boardTop, width: boardWidth, height: boardHeight)

            let overlayWidth = min(bounds.width - 40, 360)
            overlayView.frame = CGRect(x: (bounds.width - overlayWidth) / 2,
                                       y: (bounds.height - 220) / 2,
                                       width: overlayWidth,
                                       height: 220)
            renderBoard()
        }

        private func updateLabels() {
            scoreLabel.text = "Score \(score)"
            bestLabel.text = "Best \(best)"
            let speed = Int(1.0 / tickInterval)
            speedLabel.text = "Speed \(speed)"
        }

        private func showOverlay(title: String, subtitle: String) {
            overlayTitleLabel.text = title
            overlaySubtitleLabel.text = subtitle
            overlayButton.setTitle("Start", for: .normal)
            overlayView.isHidden = false
            overlayView.alpha = 1.0
            gameState = .idle
        }

        @objc private func startTapped() {
            overlayView.isHidden = true
            restartButton.isHidden = true
            gameState = .playing
            startDisplayLink()
        }

        private func startDisplayLink() {
            stopDisplayLink()
            lastFrameTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink?.add(to: .main, forMode: .common)
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard gameState == .playing else { return }
            let now = link.timestamp
            let dt = min(1.0 / 30.0, now - lastFrameTime)
            lastFrameTime = now
            tickAccumulator += dt
            while tickAccumulator >= tickInterval {
                tickAccumulator -= tickInterval
                tick()
            }
        }

        private func tick() {
            direction = pendingDirection
            guard var head = snake.first else { return }
            head.x += direction.x
            head.y += direction.y
            if head.x < 0 || head.y < 0 || head.x >= gridSize || head.y >= gridSize {
                endGame()
                return
            }
            if snake.contains(head) {
                endGame()
                return
            }
            snake.insert(head, at: 0)
            if head == food {
                score += 5
                best = max(best, score)
                UserDefaults.standard.set(best, forKey: "offlinai.snake.best")
                tickInterval = max(0.06, tickInterval * 0.965)
                spawnFood()
            } else {
                snake.removeLast()
            }
            updateLabels()
            renderBoard()
        }

        private func spawnFood() {
            var candidate = GridPoint(x: Int.random(in: 0..<gridSize), y: Int.random(in: 0..<gridSize))
            var attempts = 0
            while snake.contains(candidate) && attempts < 200 {
                candidate = GridPoint(x: Int.random(in: 0..<gridSize), y: Int.random(in: 0..<gridSize))
                attempts += 1
            }
            food = candidate
        }

        private func renderBoard() {
            let path = UIBezierPath()
            for segment in snake {
                let rect = CGRect(x: boardRect.minX + CGFloat(segment.x) * cellSize,
                                  y: boardRect.minY + CGFloat(segment.y) * cellSize,
                                  width: cellSize,
                                  height: cellSize).insetBy(dx: 1, dy: 1)
                path.append(UIBezierPath(roundedRect: rect, cornerRadius: 4))
            }
            boardLayer.path = path.cgPath

            let foodRect = CGRect(x: boardRect.minX + CGFloat(food.x) * cellSize,
                                  y: boardRect.minY + CGFloat(food.y) * cellSize,
                                  width: cellSize,
                                  height: cellSize).insetBy(dx: 2, dy: 2)
            let foodPath = UIBezierPath(ovalIn: foodRect)
            foodLayer.path = foodPath.cgPath
        }

        @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            switch gesture.direction {
            case .up:
                setDirection(x: 0, y: -1)
            case .down:
                setDirection(x: 0, y: 1)
            case .left:
                setDirection(x: -1, y: 0)
            case .right:
                setDirection(x: 1, y: 0)
            default:
                break
            }
        }

        private func endGame() {
            gameState = .ended
            stopDisplayLink()
            restartButton.isHidden = false
            overlayView.isHidden = false
            overlayTitleLabel.text = "Snake down"
            overlaySubtitleLabel.text = "Score \(score)  Best \(best)\nTap Play Again to retry."
            overlayButton.setTitle("Play again", for: .normal)
        }

        @objc private func closeTapped() {
            stopDisplayLink()
            onClose?()
        }

        @objc private func restartTapped() {
            resetGame()
            showOverlay(title: "Snake", subtitle: "Use arrows/WASD or swipe to turn.\nEat orbs and avoid walls.")
        }
    }

    private final class DinoGameView: UIView, EasterGamePlayable, EasterGameKeyInput {
        private enum GameState {
            case idle
            case playing
            case ended
        }

        private enum ObstacleKind {
            case cactus
            case bird
            case coin
        }

        private struct Obstacle {
            var view: UIImageView
            var x: CGFloat
            var y: CGFloat
            var width: CGFloat
            var height: CGFloat
            var kind: ObstacleKind
            var frameIndex: Int
            var frameTimer: TimeInterval
        }

        private let backgroundLayer = CAGradientLayer()
        private let starFieldView = UIImageView()
        private let groundStrip1 = UIImageView()
        private let groundStrip2 = UIImageView()
        private let dinoView = UIImageView()
        private let hudView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        private let scoreIconView = UIImageView()
        private let speedIconView = UIImageView()
        private let bestIconView = UIImageView()
        private let scoreLabel = UILabel()
        private let speedLabel = UILabel()
        private let bestLabel = UILabel()
        private let rivalLabel = UILabel()
        private let closeButton = UIButton(type: .system)
        private let restartButton = UIButton(type: .system)
        private let overlayView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        private let overlayTitleLabel = UILabel()
        private let overlaySubtitleLabel = UILabel()
        private let overlayButton = UIButton(type: .system)

        private var displayLink: CADisplayLink?
        private var lastFrameTime: CFTimeInterval = 0
        private var obstacles: [Obstacle] = []
        private var velocityY: CGFloat = 0
        private var isJumping = false
        private var isDucking = false
        private var score: CGFloat = 0
        private var best: CGFloat = 0
        private var speed: CGFloat = 220
        private var spawnTimer: TimeInterval = 0
        private var spawnInterval: TimeInterval = 1.3
        private var groundY: CGFloat = 0
        private var gameState: GameState = .idle
        private var dinoFrameTimer: TimeInterval = 0
        private var dinoFrameIndex = 0
        private var groundOffset: CGFloat = 0
        private var groundTileWidth: CGFloat = 0
        private var cloudViews: [UIImageView] = []
        private var cloudOffsets: [CGFloat] = []
        private var cloudSpeeds: [CGFloat] = []
        private var lastSpawnKind: ObstacleKind?
        private var rivalScore: CGFloat = 0
        private var rivalDrift: CGFloat = 0

        var onClose: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            return nil
        }

        deinit {
            stopDisplayLink()
        }

        func start() {
            resetGame()
            showOverlay(title: "Dino Dash vs AI", subtitle: "Tap or press Space to jump.\nPress ↓ to duck birds and beat the AI score.")
            becomeFirstResponder()
        }

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                becomeFirstResponder()
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            makeKeyCommands(target: self, action: #selector(handleKeyCommandProxy(_:)))
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: true)
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: false)
            super.pressesEnded(presses, with: event)
        }

        func makeKeyCommands(target: Any, action: Selector) -> [UIKeyCommand] {
            [
                UIKeyCommand(input: " ", modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: action)
            ]
        }

        @objc private func handleKeyCommandProxy(_ command: UIKeyCommand) {
            handleKeyCommand(command)
        }

        func handleKeyCommand(_ command: UIKeyCommand) {
            switch command.input {
            case " ", UIKeyCommand.inputUpArrow:
                jump()
            case UIKeyCommand.inputDownArrow:
                setDuck(true)
            default:
                break
            }
        }

        func handlePresses(_ presses: Set<UIPress>, isDown: Bool) {
            for press in presses {
                guard let key = press.key else { continue }
                if key.keyCode == .keyboardDownArrow {
                    setDuck(isDown)
                } else if key.keyCode == .keyboardSpacebar || key.keyCode == .keyboardUpArrow {
                    if isDown { jump() }
                }
            }
        }

        private func resetGame() {
            gameState = .idle
            score = 0
            speed = 220
            spawnTimer = 0
            spawnInterval = 1.3
            best = CGFloat(UserDefaults.standard.float(forKey: "offlinai.dino.best"))
            rivalScore = 0
            rivalDrift = 0
            clearObstacles()
            updateLabels()
            restartButton.isHidden = true
            isJumping = false
            isDucking = false
            velocityY = 0
            dinoFrameTimer = 0
            dinoFrameIndex = 0
            dinoView.image = Self.makeDinoRunImage(frame: 0, size: CGSize(width: 44, height: 48))
            groundOffset = 0
            for index in cloudOffsets.indices {
                cloudOffsets[index] = bounds.width * CGFloat(0.3 + 0.2 * CGFloat(index))
            }
        }

        private func setupView() {
            backgroundColor = .clear
            backgroundLayer.colors = [
                UIColor(red: 0.07, green: 0.08, blue: 0.16, alpha: 1.0).cgColor,
                UIColor(red: 0.12, green: 0.14, blue: 0.26, alpha: 1.0).cgColor
            ]
            backgroundLayer.startPoint = CGPoint(x: 0, y: 0)
            backgroundLayer.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(backgroundLayer)

            starFieldView.contentMode = .scaleAspectFill
            starFieldView.alpha = 0.8
            addSubview(starFieldView)

            if cloudViews.isEmpty {
                for index in 0..<3 {
                    let cloud = UIImageView()
                    cloud.alpha = 0.55
                    cloud.contentMode = .scaleAspectFit
                    addSubview(cloud)
                    cloudViews.append(cloud)
                    cloudOffsets.append(CGFloat(120 * index))
                    cloudSpeeds.append(8 + CGFloat(index) * 4)
                }
            }

            groundStrip1.contentMode = .scaleToFill
            groundStrip2.contentMode = .scaleToFill
            groundStrip1.layer.magnificationFilter = .nearest
            groundStrip1.layer.minificationFilter = .nearest
            groundStrip2.layer.magnificationFilter = .nearest
            groundStrip2.layer.minificationFilter = .nearest
            addSubview(groundStrip1)
            addSubview(groundStrip2)

            dinoView.contentMode = .scaleAspectFit
            dinoView.layer.magnificationFilter = .nearest
            dinoView.layer.minificationFilter = .nearest
            addSubview(dinoView)

            hudView.layer.cornerRadius = 14
            hudView.layer.masksToBounds = true
            addSubview(hudView)

            scoreIconView.contentMode = .scaleAspectFit
            speedIconView.contentMode = .scaleAspectFit
            bestIconView.contentMode = .scaleAspectFit
            scoreIconView.image = Self.makeHudIcon(type: .score)
            speedIconView.image = Self.makeHudIcon(type: .speed)
            bestIconView.image = Self.makeHudIcon(type: .best)

            let hudFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            scoreLabel.font = hudFont
            speedLabel.font = hudFont
            bestLabel.font = hudFont
            rivalLabel.font = hudFont
            scoreLabel.textColor = UIColor.label
            speedLabel.textColor = UIColor.label
            bestLabel.textColor = UIColor.label
            rivalLabel.textColor = UIColor.systemIndigo

            closeButton.setTitle("Close", for: .normal)
            closeButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

            restartButton.setTitle("Restart", for: .normal)
            restartButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            restartButton.isHidden = true
            restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)

            let scoreStack = UIStackView(arrangedSubviews: [scoreIconView, scoreLabel])
            scoreStack.axis = .horizontal
            scoreStack.spacing = 4
            let speedStack = UIStackView(arrangedSubviews: [speedIconView, speedLabel])
            speedStack.axis = .horizontal
            speedStack.spacing = 4
            let bestStack = UIStackView(arrangedSubviews: [bestIconView, bestLabel])
            bestStack.axis = .horizontal
            bestStack.spacing = 4
            let rivalStack = UIStackView(arrangedSubviews: [rivalLabel])
            rivalStack.axis = .horizontal
            rivalStack.spacing = 4

            let hudStack = UIStackView(arrangedSubviews: [scoreStack, speedStack, bestStack, rivalStack, UIView(), restartButton, closeButton])
            hudStack.axis = .horizontal
            hudStack.spacing = 10
            hudStack.alignment = .center
            hudStack.translatesAutoresizingMaskIntoConstraints = false
            hudView.contentView.addSubview(hudStack)
            NSLayoutConstraint.activate([
                hudStack.topAnchor.constraint(equalTo: hudView.contentView.topAnchor, constant: 10),
                hudStack.leadingAnchor.constraint(equalTo: hudView.contentView.leadingAnchor, constant: 12),
                hudStack.trailingAnchor.constraint(equalTo: hudView.contentView.trailingAnchor, constant: -12),
                hudStack.bottomAnchor.constraint(equalTo: hudView.contentView.bottomAnchor, constant: -10)
            ])

            overlayView.layer.cornerRadius = 20
            overlayView.layer.masksToBounds = true
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(overlayView)

            overlayTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
            overlayTitleLabel.textColor = .white
            overlayTitleLabel.textAlignment = .center

            overlaySubtitleLabel.font = UIFont(name: "AvenirNext-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
            overlaySubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            overlaySubtitleLabel.textAlignment = .center
            overlaySubtitleLabel.numberOfLines = 0

            overlayButton.setTitle("Start", for: .normal)
            overlayButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
            overlayButton.tintColor = .white
            overlayButton.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.85)
            overlayButton.layer.cornerRadius = 16
            overlayButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

            let overlayStack = UIStackView(arrangedSubviews: [overlayTitleLabel, overlaySubtitleLabel, overlayButton])
            overlayStack.axis = .vertical
            overlayStack.spacing = 12
            overlayStack.alignment = .center
            overlayStack.translatesAutoresizingMaskIntoConstraints = false
            overlayView.contentView.addSubview(overlayStack)
            NSLayoutConstraint.activate([
                overlayStack.topAnchor.constraint(equalTo: overlayView.contentView.topAnchor, constant: 20),
                overlayStack.leadingAnchor.constraint(equalTo: overlayView.contentView.leadingAnchor, constant: 20),
                overlayStack.trailingAnchor.constraint(equalTo: overlayView.contentView.trailingAnchor, constant: -20),
                overlayStack.bottomAnchor.constraint(equalTo: overlayView.contentView.bottomAnchor, constant: -20),
                overlayButton.heightAnchor.constraint(equalToConstant: 40),
                overlayButton.widthAnchor.constraint(equalToConstant: 140)
            ])

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleJump))
            addGestureRecognizer(tap)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            backgroundLayer.frame = bounds
            starFieldView.frame = bounds.insetBy(dx: -40, dy: -40)
            starFieldView.image = starFieldView.image ?? Self.makeStarFieldImage(size: starFieldView.bounds.size)
            let safe = safeAreaInsets
            let hudHeight: CGFloat = 50
            hudView.frame = CGRect(x: 18, y: safe.top + 12, width: bounds.width - 36, height: hudHeight)
            groundY = bounds.height - safe.bottom - 88
            let groundHeight: CGFloat = 12
            if groundTileWidth == 0 {
                groundTileWidth = max(220, bounds.width * 0.6)
            }
            let groundImage = Self.makeGroundStripImage(size: CGSize(width: groundTileWidth, height: groundHeight))
            groundStrip1.image = groundImage
            groundStrip2.image = groundImage
            groundStrip1.frame = CGRect(x: groundOffset, y: groundY + 40, width: groundTileWidth, height: groundHeight)
            groundStrip2.frame = CGRect(x: groundOffset + groundTileWidth, y: groundY + 40, width: groundTileWidth, height: groundHeight)

            for (index, cloud) in cloudViews.enumerated() {
                let size = CGSize(width: 90 + CGFloat(index) * 20, height: 36 + CGFloat(index) * 6)
                cloud.image = Self.makeCloudImage(size: size)
                let y = safe.top + 70 + CGFloat(index) * 40
                let x = (bounds.width * 0.2 * CGFloat(index + 1)) + cloudOffsets[index]
                cloud.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            }
            layoutDino()
            if dinoView.image == nil {
                dinoView.image = Self.makeDinoRunImage(frame: 0, size: dinoView.bounds.size)
            }

            let overlayWidth = min(bounds.width - 40, 360)
            overlayView.frame = CGRect(x: (bounds.width - overlayWidth) / 2,
                                       y: (bounds.height - 220) / 2,
                                       width: overlayWidth,
                                       height: 220)
        }

        private func layoutDino() {
            let height: CGFloat = isDucking ? 30 : 48
            let width: CGFloat = isDucking ? 56 : 44
            let baseY = groundY + 40 - height
            let currentY = isJumping ? dinoView.frame.origin.y : baseY
            dinoView.frame = CGRect(x: 80, y: currentY, width: width, height: height)
        }

        private func updateLabels() {
            scoreLabel.text = "\(Int(score))"
            speedLabel.text = "\(Int(speed))"
            bestLabel.text = "\(Int(best))"
            rivalLabel.text = "AI \(Int(rivalScore))"
        }

        private func showOverlay(title: String, subtitle: String) {
            overlayTitleLabel.text = title
            overlaySubtitleLabel.text = subtitle
            overlayButton.setTitle("Start", for: .normal)
            overlayView.isHidden = false
            overlayView.alpha = 1.0
            gameState = .idle
        }

        @objc private func startTapped() {
            overlayView.isHidden = true
            restartButton.isHidden = true
            gameState = .playing
            startDisplayLink()
        }

        private func startDisplayLink() {
            stopDisplayLink()
            lastFrameTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink?.add(to: .main, forMode: .common)
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard gameState == .playing else { return }
            let now = link.timestamp
            let dt = min(1.0 / 30.0, now - lastFrameTime)
            lastFrameTime = now

            score += CGFloat(dt * 10)
            best = max(best, score)
            UserDefaults.standard.set(best, forKey: "offlinai.dino.best")

            speed = min(430, 220 + score * 0.32)
            spawnInterval = max(0.92, 1.30 - Double(score / 220))

            rivalDrift += CGFloat.random(in: -8...8) * CGFloat(dt)
            rivalDrift = max(-18, min(18, rivalDrift))
            let pressure = obstacles.contains { $0.kind != .coin && $0.x < 170 && $0.x > 60 } ? 14.0 : 0.0
            let rivalPace = max(2.0, (speed * 0.04) + rivalDrift - pressure)
            rivalScore += rivalPace * CGFloat(dt)

            groundOffset -= speed * CGFloat(dt) * 0.6
            if groundOffset <= -groundTileWidth {
                groundOffset += groundTileWidth
            }
            groundStrip1.frame.origin.x = groundOffset
            groundStrip2.frame.origin.x = groundOffset + groundTileWidth

            for index in cloudViews.indices {
                cloudOffsets[index] -= cloudSpeeds[index] * CGFloat(dt)
                if cloudOffsets[index] < -bounds.width - 120 {
                    cloudOffsets[index] = bounds.width + 120
                }
                let cloud = cloudViews[index]
                cloud.frame.origin.x = cloudOffsets[index]
            }

            if isJumping {
                velocityY += 1520 * CGFloat(dt)
                dinoView.frame.origin.y += velocityY * CGFloat(dt)
                if dinoView.frame.maxY >= groundY + 40 {
                    dinoView.frame.origin.y = groundY + 40 - dinoView.frame.height
                    velocityY = 0
                    isJumping = false
                }
            } else {
                layoutDino()
            }

            dinoFrameTimer += dt
            if !isJumping && !isDucking, dinoFrameTimer >= 0.12 {
                dinoFrameTimer = 0
                dinoFrameIndex = (dinoFrameIndex + 1) % 2
            }
            if isDucking {
                dinoView.image = Self.makeDinoDuckImage(size: dinoView.bounds.size)
            } else {
                dinoView.image = Self.makeDinoRunImage(frame: dinoFrameIndex, size: dinoView.bounds.size)
            }

            spawnTimer += dt
            if spawnTimer >= spawnInterval, canSpawnObstacle() {
                spawnTimer = 0
                spawnObstacle()
            }

            updateObstacles(dt: dt)
            updateLabels()
        }

        private func spawnObstacle() {
            let roll = Int.random(in: 0..<100)
            var kind: ObstacleKind = .cactus
            if roll < 18 {
                kind = .coin
            } else if roll < 35 {
                kind = .bird
            }

            var width: CGFloat = 34
            var height: CGFloat = 44
            var image: UIImage?
            if kind == .cactus {
                var variant = Int.random(in: 0..<3)
                if lastSpawnKind == .bird {
                    variant = 0
                }
                switch variant {
                case 0:
                    width = 30
                    height = 38
                case 1:
                    width = 30
                    height = 54
                default:
                    width = 48
                    height = 42
                }
                image = Self.makeCactusImage(variant: variant, size: CGSize(width: width, height: height))
            } else if kind == .bird {
                width = 46
                height = 28
                image = Self.makeBirdImage(frame: 0, size: CGSize(width: width, height: height))
            } else {
                width = 24
                height = 24
                image = Self.makeCoinImage(frame: 0, size: CGSize(width: width, height: height))
            }

            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFit
            view.layer.magnificationFilter = .nearest
            view.layer.minificationFilter = .nearest
            addSubview(view)

            let y: CGFloat
            switch kind {
            case .cactus:
                y = groundY + 40 - height
            case .bird:
                let high = groundY - 18 - height
                let low = groundY + 10 - height
                y = Bool.random() ? high : low
            case .coin:
                y = groundY - 80 - height
            }

            let obstacle = Obstacle(view: view,
                                    x: bounds.width + width,
                                    y: y,
                                    width: width,
                                    height: height,
                                    kind: kind,
                                    frameIndex: 0,
                                    frameTimer: 0)
            view.frame = CGRect(x: obstacle.x, y: y, width: width, height: height)
            obstacles.append(obstacle)
            lastSpawnKind = kind
        }

        private func canSpawnObstacle() -> Bool {
            guard let nearest = obstacles.max(by: { $0.x < $1.x }) else { return true }
            let dynamicGap = max(120, speed * 0.42)
            return nearest.x < bounds.width - dynamicGap
        }

        private func updateObstacles(dt: TimeInterval) {
            var dinoHit = dinoView.frame.insetBy(dx: 6, dy: 6)
            if isDucking {
                dinoHit = dinoView.frame.insetBy(dx: 10, dy: 4)
            }
            var remaining: [Obstacle] = []
            for var obstacle in obstacles {
                obstacle.x -= speed * CGFloat(dt)
                obstacle.frameTimer += dt
                if obstacle.kind == .bird, obstacle.frameTimer >= 0.15 {
                    obstacle.frameTimer = 0
                    obstacle.frameIndex = (obstacle.frameIndex + 1) % 2
                    obstacle.view.image = Self.makeBirdImage(frame: obstacle.frameIndex, size: CGSize(width: obstacle.width, height: obstacle.height))
                } else if obstacle.kind == .coin, obstacle.frameTimer >= 0.2 {
                    obstacle.frameTimer = 0
                    obstacle.frameIndex = (obstacle.frameIndex + 1) % 2
                    obstacle.view.image = Self.makeCoinImage(frame: obstacle.frameIndex, size: CGSize(width: obstacle.width, height: obstacle.height))
                }

                obstacle.view.frame = CGRect(x: obstacle.x, y: obstacle.y, width: obstacle.width, height: obstacle.height)

                var obstacleHit = obstacle.view.frame.insetBy(dx: 4, dy: 4)
                if obstacle.kind == .bird {
                    obstacleHit = obstacleHit.insetBy(dx: 8, dy: 6)
                } else if obstacle.kind == .coin {
                    obstacleHit = obstacleHit.insetBy(dx: 6, dy: 6)
                }

                if obstacle.kind == .coin {
                    if obstacleHit.intersects(dinoHit) {
                        score += 20
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        obstacle.view.removeFromSuperview()
                        continue
                    }
                } else if obstacleHit.intersects(dinoHit) {
                    impactShake()
                    endGame()
                    return
                }
                if obstacle.x + obstacle.width > -40 {
                    remaining.append(obstacle)
                } else {
                    obstacle.view.removeFromSuperview()
                }
            }
            obstacles = remaining
        }

        private func clearObstacles() {
            for obstacle in obstacles {
                obstacle.view.removeFromSuperview()
            }
            obstacles.removeAll()
        }

        @objc private func handleJump() {
            jump()
        }

        private func jump() {
            guard gameState == .playing, !isJumping else { return }
            isJumping = true
            velocityY = -610
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        @objc private func handleDuckTap() {
            setDuck(true)
        }

        private func setDuck(_ duck: Bool) {
            guard gameState == .playing, !isJumping else { return }
            isDucking = duck
            layoutDino()
        }

        private func endGame() {
            gameState = .ended
            stopDisplayLink()
            clearObstacles()
            updateLabels()
            restartButton.isHidden = false
            overlayView.isHidden = false
            overlayTitleLabel.text = "Dino down"
            let outcome: String
            if score >= rivalScore {
                outcome = "You beat AI"
            } else {
                outcome = "AI won this run"
            }
            overlaySubtitleLabel.text = "You \(Int(score))  AI \(Int(rivalScore))  Best \(Int(best))\n\(outcome). Tap Play Again."
            overlayButton.setTitle("Play again", for: .normal)
        }

        private func impactShake() {
            let original = transform
            UIView.animate(withDuration: 0.05, animations: {
                self.transform = CGAffineTransform(translationX: 6, y: 0)
            }) { _ in
                UIView.animate(withDuration: 0.08) {
                    self.transform = original
                }
            }
        }

        @objc private func closeTapped() {
            stopDisplayLink()
            onClose?()
        }

        @objc private func restartTapped() {
            resetGame()
            showOverlay(title: "Dino Dash vs AI", subtitle: "Tap or press Space to jump.\nPress ↓ to duck birds and beat the AI score.")
        }

        private static func makeStarFieldImage(size: CGSize) -> UIImage? {
            guard size.width > 0, size.height > 0 else { return nil }
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let count = Int((size.width * size.height) / 2400)
                for _ in 0..<max(350, count) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let radius = CGFloat.random(in: 0.5...1.7)
                    let alpha = CGFloat.random(in: 0.25...0.8)
                    UIColor.white.withAlphaComponent(alpha).setFill()
                    ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
                }
            }
        }

        private enum HudIconType {
            case score
            case speed
            case best
        }

        private static var spriteCache: [String: UIImage] = [:]

        private static func cacheKey(_ name: String, size: CGSize) -> String {
            "\(name)-\(Int(size.width))x\(Int(size.height))"
        }

        private static func spriteImage(name: String, pattern: [String], palette: [UIColor], size: CGSize) -> UIImage? {
            let key = cacheKey(name, size: size)
            if let cached = spriteCache[key] { return cached }
            let rows = pattern.count
            guard rows > 0, let cols = pattern.first?.count else { return nil }
            let pixelSize = floor(min(size.width / CGFloat(cols), size.height / CGFloat(rows)))
            guard pixelSize > 0 else { return nil }
            let spriteWidth = pixelSize * CGFloat(cols)
            let spriteHeight = pixelSize * CGFloat(rows)
            let offsetX = (size.width - spriteWidth) / 2
            let offsetY = (size.height - spriteHeight) / 2
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                for (rowIndex, row) in pattern.enumerated() {
                    for (colIndex, char) in row.enumerated() {
                        if char == "." { continue }
                        guard let value = Int(String(char)), value < palette.count else { continue }
                        let color = palette[value]
                        color.setFill()
                        let rect = CGRect(x: offsetX + CGFloat(colIndex) * pixelSize,
                                          y: offsetY + CGFloat(rowIndex) * pixelSize,
                                          width: pixelSize,
                                          height: pixelSize)
                        ctx.cgContext.fill(rect)
                    }
                }
            }
            spriteCache[key] = image
            return image
        }

        private static func pixelPalette() -> [UIColor] {
            [
                UIColor.clear,
                UIColor(red: 0.80, green: 0.97, blue: 0.72, alpha: 1.0),
                UIColor(red: 0.32, green: 0.68, blue: 0.36, alpha: 1.0),
                UIColor.black.withAlphaComponent(0.85),
                UIColor(red: 0.96, green: 0.78, blue: 0.33, alpha: 1.0)
            ]
        }

        private static func makeDinoRunImage(frame: Int, size: CGSize) -> UIImage? {
            let palette = pixelPalette()
            let run1 = [
                "............",
                "..1111......",
                ".111111.....",
                ".1112111....",
                ".1111111....",
                ".111111.....",
                "..1111......",
                "..1111..2...",
                "..11.22.....",
                ".11.........",
                ".11.........",
                "............"
            ]
            let run2 = [
                "............",
                "..1111......",
                ".111111.....",
                ".1112111....",
                ".1111111....",
                ".111111.....",
                "..1111......",
                "..1111..2...",
                "..11...22...",
                ".11.........",
                "..11........",
                "............"
            ]
            let pattern = frame % 2 == 0 ? run1 : run2
            return spriteImage(name: "dino-run-\(frame % 2)", pattern: pattern, palette: palette, size: size)
        }

        private static func makeDinoDuckImage(size: CGSize) -> UIImage? {
            let palette = pixelPalette()
            let duck = [
                "............",
                "............",
                ".11111111...",
                "111121111...",
                "111111111...",
                "111111111...",
                ".1111111....",
                "..111111....",
                "............",
                "............",
                "............",
                "............"
            ]
            return spriteImage(name: "dino-duck", pattern: duck, palette: palette, size: size)
        }

        private static func makeCactusImage(variant: Int, size: CGSize) -> UIImage? {
            let palette = pixelPalette()
            let short = [
                "....11....",
                "...111....",
                "...111....",
                "..1111....",
                "..1111....",
                ".11111....",
                ".11111....",
                ".11111....",
                ".11111....",
                "..111....."
            ]
            let tall = [
                "....11....",
                "...111....",
                "...111....",
                "..1111....",
                "..1111....",
                ".11111....",
                ".11111....",
                ".11111....",
                ".11111....",
                ".11111....",
                ".11111....",
                "..111....."
            ]
            let double = [
                "..11..11..",
                ".111.111..",
                ".111.111..",
                "11111111..",
                "11111111..",
                "11111111..",
                "11111111..",
                ".111111...",
                "..1111....",
                "..1111...."
            ]
            let pattern: [String]
            switch variant {
            case 1:
                pattern = tall
            case 2:
                pattern = double
            default:
                pattern = short
            }
            return spriteImage(name: "cactus-\(variant)", pattern: pattern, palette: palette, size: size)
        }

        private static func makeBirdImage(frame: Int, size: CGSize) -> UIImage? {
            let palette = pixelPalette()
            let up = [
                "..11.....",
                ".1111....",
                "111111...",
                ".1111....",
                "..11..3.."
            ]
            let down = [
                "........",
                "..11....",
                ".1111...",
                "111111..",
                "..11.3.."
            ]
            let pattern = frame % 2 == 0 ? up : down
            return spriteImage(name: "bird-\(frame % 2)", pattern: pattern, palette: palette, size: size)
        }

        private static func makeCoinImage(frame: Int, size: CGSize) -> UIImage? {
            let palette = pixelPalette()
            let coin1 = [
                "..44..",
                ".4444.",
                "444444",
                "444444",
                ".4444.",
                "..44.."
            ]
            let coin2 = [
                "..44..",
                ".4444.",
                "44..44",
                "44..44",
                ".4444.",
                "..44.."
            ]
            let pattern = frame % 2 == 0 ? coin1 : coin2
            return spriteImage(name: "coin-\(frame % 2)", pattern: pattern, palette: palette, size: size)
        }

        private static func makeGroundStripImage(size: CGSize) -> UIImage? {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let lineColor = UIColor(red: 0.32, green: 0.68, blue: 0.36, alpha: 1.0)
                lineColor.setFill()
                let lineRect = CGRect(x: 0, y: size.height / 2, width: size.width, height: 2)
                ctx.cgContext.fill(lineRect)
                let dotColor = UIColor(red: 0.20, green: 0.55, blue: 0.26, alpha: 1.0)
                for x in stride(from: 0, to: size.width, by: 12) {
                    dotColor.setFill()
                    let dotRect = CGRect(x: x, y: size.height / 2 - 3, width: 2, height: 2)
                    ctx.cgContext.fill(dotRect)
                }
            }
        }

        private static func makeCloudImage(size: CGSize) -> UIImage? {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let color = UIColor.white.withAlphaComponent(0.35)
                color.setFill()
                let base = CGRect(x: 0, y: size.height * 0.4, width: size.width, height: size.height * 0.35)
                ctx.cgContext.fillEllipse(in: base)
                ctx.cgContext.fillEllipse(in: CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.35, height: size.height * 0.45))
                ctx.cgContext.fillEllipse(in: CGRect(x: size.width * 0.5, y: size.height * 0.1, width: size.width * 0.35, height: size.height * 0.5))
            }
        }

        private static func makeHudIcon(type: HudIconType) -> UIImage? {
            let palette = [UIColor.clear, UIColor.white]
            let pattern: [String]
            switch type {
            case .score:
                pattern = [
                    ".11.",
                    "1111",
                    "1111",
                    ".11."
                ]
            case .speed:
                pattern = [
                    "1.1.",
                    "1111",
                    ".1.1",
                    ".1.1"
                ]
            case .best:
                pattern = [
                    ".1..",
                    "111.",
                    ".1..",
                    "1111"
                ]
            }
            return spriteImage(name: "hud-\(type)", pattern: pattern, palette: palette, size: CGSize(width: 14, height: 14))
        }
    }

    private final class AsteroidsGameView: UIView, EasterGamePlayable, EasterGameKeyInput {
        private enum GameState {
            case idle
            case playing
            case ended
        }

        private struct Asteroid {
            var view: UIView
            var position: CGPoint
            var velocity: CGVector
            var radius: CGFloat
        }

        private struct Bullet {
            var view: UIView
            var position: CGPoint
            var velocity: CGVector
            var life: TimeInterval
        }

        private let backgroundLayer = CAGradientLayer()
        private let starFieldView = UIImageView()
        private let shipView = UIView()
        private let shipLayer = CAShapeLayer()
        private let hudView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        private let titleLabel = UILabel()
        private let scoreLabel = UILabel()
        private let livesLabel = UILabel()
        private let levelLabel = UILabel()
        private let closeButton = UIButton(type: .system)
        private let restartButton = UIButton(type: .system)
        private let controlsContainer = UIView()
        private let leftButton = UIButton(type: .system)
        private let rightButton = UIButton(type: .system)
        private let thrustButton = UIButton(type: .system)
        private let fireButton = UIButton(type: .system)
        private let overlayView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        private let overlayTitleLabel = UILabel()
        private let overlaySubtitleLabel = UILabel()
        private let overlayButton = UIButton(type: .system)

        private var displayLink: CADisplayLink?
        private var lastFrameTime: CFTimeInterval = 0
        private var asteroids: [Asteroid] = []
        private var bullets: [Bullet] = []
        private var shipPosition: CGPoint = .zero
        private var shipVelocity: CGVector = .zero
        private var shipAngle: CGFloat = -.pi / 2
        private var thrusting = false
        private var turningLeft = false
        private var turningRight = false
        private var score = 0
        private var lives = 3
        private var level = 1
        private var gameState: GameState = .idle
        private var lastShot: TimeInterval = 0
        private var invulnerabilityTime: TimeInterval = 0
        private let invulnerabilityDuration: TimeInterval = 1.2

        var onClose: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            return nil
        }

        deinit {
            stopDisplayLink()
        }

        func start() {
            resetGame()
            showOverlay(title: "Asteroids", subtitle: "Use ← → / A D to rotate, ↑ / W to thrust, Space to fire.\nTouch buttons also work.")
            becomeFirstResponder()
        }

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                becomeFirstResponder()
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            makeKeyCommands(target: self, action: #selector(handleKeyCommandProxy(_:)))
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: true)
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: false)
            super.pressesEnded(presses, with: event)
        }

        func makeKeyCommands(target: Any, action: Selector) -> [UIKeyCommand] {
            [
                UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: "a", modifierFlags: [], action: action),
                UIKeyCommand(input: "d", modifierFlags: [], action: action),
                UIKeyCommand(input: "w", modifierFlags: [], action: action),
                UIKeyCommand(input: " ", modifierFlags: [], action: action)
            ]
        }

        @objc private func handleKeyCommandProxy(_ command: UIKeyCommand) {
            handleKeyCommand(command)
        }

        func handleKeyCommand(_ command: UIKeyCommand) {
            switch command.input {
            case UIKeyCommand.inputLeftArrow, "a":
                handleLeftTap()
            case UIKeyCommand.inputRightArrow, "d":
                handleRightTap()
            case UIKeyCommand.inputUpArrow, "w":
                handleThrustTap()
            case " ":
                handleFire()
            default:
                break
            }
        }

        func handlePresses(_ presses: Set<UIPress>, isDown: Bool) {
            for press in presses {
                guard let key = press.key else { continue }
                switch key.keyCode {
                case .keyboardLeftArrow:
                    turningLeft = isDown
                case .keyboardRightArrow:
                    turningRight = isDown
                case .keyboardUpArrow:
                    thrusting = isDown
                case .keyboardA:
                    turningLeft = isDown
                case .keyboardD:
                    turningRight = isDown
                case .keyboardW:
                    thrusting = isDown
                case .keyboardSpacebar:
                    if isDown { fireBullet() }
                default:
                    break
                }
            }
        }

        private func resetGame() {
            gameState = .idle
            score = 0
            lives = 3
            level = 1
            shipVelocity = .zero
            shipAngle = -.pi / 2
            turningLeft = false
            turningRight = false
            thrusting = false
            invulnerabilityTime = 0
            clearEntities()
            updateLabels()
            restartButton.isHidden = true
        }

        private func setupView() {
            backgroundColor = .clear
            backgroundLayer.colors = [
                UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0).cgColor,
                UIColor(red: 0.10, green: 0.12, blue: 0.24, alpha: 1.0).cgColor
            ]
            backgroundLayer.startPoint = CGPoint(x: 0, y: 0)
            backgroundLayer.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(backgroundLayer)

            starFieldView.contentMode = .scaleAspectFill
            starFieldView.alpha = 0.8
            addSubview(starFieldView)

            shipView.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
            shipView.layer.addSublayer(shipLayer)
            shipLayer.fillColor = UIColor.systemTeal.cgColor
            addSubview(shipView)

            hudView.layer.cornerRadius = 18
            hudView.layer.masksToBounds = true
            addSubview(hudView)

            titleLabel.text = "Asteroids"
            titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 16) ?? UIFont.systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textColor = UIColor.label

            scoreLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            livesLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            levelLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            scoreLabel.textColor = UIColor.label
            livesLabel.textColor = UIColor.label
            levelLabel.textColor = UIColor.label

            closeButton.setTitle("Close", for: .normal)
            closeButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

            restartButton.setTitle("Restart", for: .normal)
            restartButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            restartButton.isHidden = true
            restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)

            let hudStack = UIStackView(arrangedSubviews: [titleLabel, scoreLabel, livesLabel, levelLabel, UIView(), restartButton, closeButton])
            hudStack.axis = .horizontal
            hudStack.spacing = 10
            hudStack.alignment = .center
            hudStack.translatesAutoresizingMaskIntoConstraints = false
            hudView.contentView.addSubview(hudStack)
            NSLayoutConstraint.activate([
                hudStack.topAnchor.constraint(equalTo: hudView.contentView.topAnchor, constant: 10),
                hudStack.leadingAnchor.constraint(equalTo: hudView.contentView.leadingAnchor, constant: 12),
                hudStack.trailingAnchor.constraint(equalTo: hudView.contentView.trailingAnchor, constant: -12),
                hudStack.bottomAnchor.constraint(equalTo: hudView.contentView.bottomAnchor, constant: -10)
            ])

            overlayView.layer.cornerRadius = 20
            overlayView.layer.masksToBounds = true
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(overlayView)

            overlayTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
            overlayTitleLabel.textColor = .white
            overlayTitleLabel.textAlignment = .center

            overlaySubtitleLabel.font = UIFont(name: "AvenirNext-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
            overlaySubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            overlaySubtitleLabel.textAlignment = .center
            overlaySubtitleLabel.numberOfLines = 0

            overlayButton.setTitle("Start", for: .normal)
            overlayButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
            overlayButton.tintColor = .white
            overlayButton.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.85)
            overlayButton.layer.cornerRadius = 16
            overlayButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

            let overlayStack = UIStackView(arrangedSubviews: [overlayTitleLabel, overlaySubtitleLabel, overlayButton])
            overlayStack.axis = .vertical
            overlayStack.spacing = 12
            overlayStack.alignment = .center
            overlayStack.translatesAutoresizingMaskIntoConstraints = false
            overlayView.contentView.addSubview(overlayStack)
            NSLayoutConstraint.activate([
                overlayStack.topAnchor.constraint(equalTo: overlayView.contentView.topAnchor, constant: 20),
                overlayStack.leadingAnchor.constraint(equalTo: overlayView.contentView.leadingAnchor, constant: 20),
                overlayStack.trailingAnchor.constraint(equalTo: overlayView.contentView.trailingAnchor, constant: -20),
                overlayStack.bottomAnchor.constraint(equalTo: overlayView.contentView.bottomAnchor, constant: -20),
                overlayButton.heightAnchor.constraint(equalToConstant: 40),
                overlayButton.widthAnchor.constraint(equalToConstant: 140)
            ])

            controlsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.18)
            controlsContainer.layer.cornerRadius = 16
            controlsContainer.layer.borderWidth = 1
            controlsContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
            controlsContainer.isUserInteractionEnabled = true
            addSubview(controlsContainer)

            func configureControlButton(_ button: UIButton, title: String) {
                button.setTitle(title, for: .normal)
                button.titleLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
                button.tintColor = .white
                button.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.8)
                button.layer.cornerRadius = 14
                button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            }

            configureControlButton(leftButton, title: "LEFT")
            configureControlButton(rightButton, title: "RIGHT")
            configureControlButton(thrustButton, title: "THRUST")
            configureControlButton(fireButton, title: "FIRE")
            leftButton.addTarget(self, action: #selector(handleLeftTap), for: .touchDown)
            rightButton.addTarget(self, action: #selector(handleRightTap), for: .touchDown)
            thrustButton.addTarget(self, action: #selector(handleThrustTap), for: .touchDown)
            fireButton.addTarget(self, action: #selector(handleFire), for: .touchDown)

            let topControls = UIStackView(arrangedSubviews: [thrustButton, fireButton])
            topControls.axis = .horizontal
            topControls.spacing = 8
            topControls.distribution = .fillEqually
            let bottomControls = UIStackView(arrangedSubviews: [leftButton, rightButton])
            bottomControls.axis = .horizontal
            bottomControls.spacing = 8
            bottomControls.distribution = .fillEqually
            let controlsStack = UIStackView(arrangedSubviews: [topControls, bottomControls])
            controlsStack.axis = .vertical
            controlsStack.spacing = 8
            controlsStack.translatesAutoresizingMaskIntoConstraints = false
            controlsContainer.addSubview(controlsStack)
            NSLayoutConstraint.activate([
                controlsStack.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 8),
                controlsStack.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 8),
                controlsStack.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -8),
                controlsStack.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -8)
            ])

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleThrustTap))
            addGestureRecognizer(tap)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            backgroundLayer.frame = bounds
            starFieldView.frame = bounds.insetBy(dx: -40, dy: -40)
            starFieldView.image = starFieldView.image ?? Self.makeStarFieldImage(size: starFieldView.bounds.size)
            let safe = safeAreaInsets
            let hudHeight: CGFloat = 58
            hudView.frame = CGRect(x: 18, y: safe.top + 12, width: bounds.width - 36, height: hudHeight)

            let overlayWidth = min(bounds.width - 40, 360)
            overlayView.frame = CGRect(x: (bounds.width - overlayWidth) / 2,
                                       y: (bounds.height - 220) / 2,
                                       width: overlayWidth,
                                       height: 220)

            let controlsWidth = min(300, bounds.width - 36)
            controlsContainer.frame = CGRect(x: (bounds.width - controlsWidth) / 2,
                                             y: bounds.height - safe.bottom - 116,
                                             width: controlsWidth,
                                             height: 96)

            updateShipView()
        }

        private func updateLabels() {
            scoreLabel.text = "Score \(score)"
            livesLabel.text = "Lives \(lives)"
            levelLabel.text = "Lv \(level)"
        }

        private func showOverlay(title: String, subtitle: String) {
            overlayTitleLabel.text = title
            overlaySubtitleLabel.text = subtitle
            overlayButton.setTitle("Start", for: .normal)
            overlayView.isHidden = false
            overlayView.alpha = 1.0
            gameState = .idle
        }

        @objc private func startTapped() {
            overlayView.isHidden = true
            restartButton.isHidden = true
            controlsContainer.alpha = 1.0
            gameState = .playing
            invulnerabilityTime = invulnerabilityDuration
            if shipPosition == .zero {
                shipPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            }
            if asteroids.isEmpty {
                spawnAsteroids(count: 3 + level)
            }
            startDisplayLink()
        }

        private func startDisplayLink() {
            stopDisplayLink()
            lastFrameTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink?.add(to: .main, forMode: .common)
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard gameState == .playing else { return }
            let now = link.timestamp
            let dt = min(1.0 / 30.0, now - lastFrameTime)
            lastFrameTime = now

            if turningLeft { shipAngle -= CGFloat(dt * 2.8) }
            if turningRight { shipAngle += CGFloat(dt * 2.8) }
            if thrusting {
                let ax = cos(shipAngle) * 300
                let ay = sin(shipAngle) * 300
                shipVelocity.dx += ax * CGFloat(dt)
                shipVelocity.dy += ay * CGFloat(dt)
            }

            let speedMagnitude = hypot(shipVelocity.dx, shipVelocity.dy)
            if speedMagnitude > 360 {
                let scale = 360 / speedMagnitude
                shipVelocity.dx *= scale
                shipVelocity.dy *= scale
            }
            shipVelocity.dx *= 0.985
            shipVelocity.dy *= 0.985

            shipPosition.x += shipVelocity.dx * CGFloat(dt)
            shipPosition.y += shipVelocity.dy * CGFloat(dt)
            wrap(&shipPosition)
            updateShipView()

            updateBullets(dt: dt)
            updateAsteroids(dt: dt)
            handleCollisions()

            if invulnerabilityTime > 0 {
                invulnerabilityTime = max(0, invulnerabilityTime - dt)
                let blink = Int((invulnerabilityTime * 12).rounded(.down)) % 2 == 0
                shipView.alpha = blink ? 0.45 : 1.0
            } else {
                shipView.alpha = 1.0
            }

            if asteroids.isEmpty {
                level += 1
                updateLabels()
                spawnAsteroids(count: 3 + level)
            }
        }

        private func updateShipView() {
            if shipPosition == .zero {
                shipPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            }
            shipView.center = shipPosition
            shipView.transform = CGAffineTransform(rotationAngle: shipAngle + .pi / 2)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 18, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 36))
            path.addLine(to: CGPoint(x: 36, y: 36))
            path.close()
            shipLayer.path = path.cgPath
        }

        private func spawnAsteroids(count: Int) {
            for _ in 0..<count {
                let radius = CGFloat.random(in: 18...36)
                let view = UIView()
                view.backgroundColor = UIColor.systemGray3
                view.layer.cornerRadius = radius
                addSubview(view)
                var position = CGPoint(x: CGFloat.random(in: 20...bounds.width - 20),
                                       y: CGFloat.random(in: 140...bounds.height - 160))
                var tries = 0
                let safeDistance: CGFloat = 180
                while tries < 12 {
                    let dx = position.x - shipPosition.x
                    let dy = position.y - shipPosition.y
                    if sqrt(dx * dx + dy * dy) >= safeDistance {
                        break
                    }
                    position = CGPoint(x: CGFloat.random(in: 20...bounds.width - 20),
                                       y: CGFloat.random(in: 140...bounds.height - 160))
                    tries += 1
                }
                let velocity = CGVector(dx: CGFloat.random(in: -80...80), dy: CGFloat.random(in: -80...80))
                let asteroid = Asteroid(view: view, position: position, velocity: velocity, radius: radius)
                view.frame = CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
                asteroids.append(asteroid)
            }
        }

        private func updateAsteroids(dt: TimeInterval) {
            for index in asteroids.indices {
                var asteroid = asteroids[index]
                asteroid.position.x += asteroid.velocity.dx * CGFloat(dt)
                asteroid.position.y += asteroid.velocity.dy * CGFloat(dt)
                wrap(&asteroid.position)
                asteroid.view.frame = CGRect(x: asteroid.position.x - asteroid.radius,
                                             y: asteroid.position.y - asteroid.radius,
                                             width: asteroid.radius * 2,
                                             height: asteroid.radius * 2)
                asteroids[index] = asteroid
            }
        }

        private func updateBullets(dt: TimeInterval) {
            var remaining: [Bullet] = []
            for var bullet in bullets {
                bullet.life -= dt
                bullet.position.x += bullet.velocity.dx * CGFloat(dt)
                bullet.position.y += bullet.velocity.dy * CGFloat(dt)
                wrap(&bullet.position)
                bullet.view.center = bullet.position
                if bullet.life > 0 {
                    remaining.append(bullet)
                } else {
                    bullet.view.removeFromSuperview()
                }
            }
            bullets = remaining
        }

        private func handleCollisions() {
            let shipRadius: CGFloat = 16
            for (index, asteroid) in asteroids.enumerated().reversed() {
                let dx = asteroid.position.x - shipPosition.x
                let dy = asteroid.position.y - shipPosition.y
                let dist = sqrt(dx * dx + dy * dy)
                if invulnerabilityTime <= 0, dist < shipRadius + asteroid.radius {
                    hitShip()
                    return
                }
                for (bIndex, bullet) in bullets.enumerated().reversed() {
                    let dxB = asteroid.position.x - bullet.position.x
                    let dyB = asteroid.position.y - bullet.position.y
                    let distB = sqrt(dxB * dxB + dyB * dyB)
                    if distB < asteroid.radius {
                        asteroid.view.removeFromSuperview()
                        bullets[bIndex].view.removeFromSuperview()
                        bullets.remove(at: bIndex)
                        spawnAsteroidFragments(from: asteroid)
                        asteroids.remove(at: index)
                        score += 15
                        updateLabels()
                        break
                    }
                }
            }
        }

        private func spawnAsteroidFragments(from asteroid: Asteroid) {
            guard asteroid.radius > 22 else { return }
            let fragmentRadius = asteroid.radius * 0.58
            for direction in [-1.0, 1.0] {
                let view = UIView()
                view.backgroundColor = UIColor.systemGray2
                view.layer.cornerRadius = fragmentRadius
                addSubview(view)
                let velocity = CGVector(dx: asteroid.velocity.dx + CGFloat(direction * 60),
                                        dy: asteroid.velocity.dy + CGFloat(direction * 45))
                let fragment = Asteroid(view: view, position: asteroid.position, velocity: velocity, radius: fragmentRadius)
                fragment.view.frame = CGRect(x: fragment.position.x - fragmentRadius,
                                             y: fragment.position.y - fragmentRadius,
                                             width: fragmentRadius * 2,
                                             height: fragmentRadius * 2)
                asteroids.append(fragment)
            }
        }

        private func hitShip() {
            lives -= 1
            updateLabels()
            shipVelocity = .zero
            shipPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            invulnerabilityTime = invulnerabilityDuration
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if lives <= 0 {
                endGame()
            }
        }

        private func wrap(_ point: inout CGPoint) {
            if point.x < -20 { point.x = bounds.width + 20 }
            if point.x > bounds.width + 20 { point.x = -20 }
            if point.y < -20 { point.y = bounds.height + 20 }
            if point.y > bounds.height + 20 { point.y = -20 }
        }

        @objc private func handleLeftTap() {
            shipAngle -= 0.15
        }

        @objc private func handleRightTap() {
            shipAngle += 0.15
        }

        @objc private func handleThrustTap() {
            thrusting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.thrusting = false
            }
        }

        @objc private func handleFire() {
            fireBullet()
        }

        private func fireBullet() {
            guard gameState == .playing else { return }
            let now = CACurrentMediaTime()
            if now - lastShot < 0.18 { return }
            lastShot = now
            let bulletView = UIView()
            bulletView.backgroundColor = UIColor.systemYellow
            bulletView.layer.cornerRadius = 3
            bulletView.frame = CGRect(x: 0, y: 0, width: 6, height: 6)
            addSubview(bulletView)
            let velocity = CGVector(dx: cos(shipAngle) * 420, dy: sin(shipAngle) * 420)
            let bullet = Bullet(view: bulletView, position: shipPosition, velocity: velocity, life: 1.4)
            bulletView.center = shipPosition
            bullets.append(bullet)
        }

        private func clearEntities() {
            for asteroid in asteroids {
                asteroid.view.removeFromSuperview()
            }
            for bullet in bullets {
                bullet.view.removeFromSuperview()
            }
            asteroids.removeAll()
            bullets.removeAll()
        }

        private func endGame() {
            gameState = .ended
            stopDisplayLink()
            clearEntities()
            updateLabels()
            restartButton.isHidden = false
            overlayView.isHidden = false
            controlsContainer.alpha = 0.55
            overlayTitleLabel.text = "Ship lost"
            overlaySubtitleLabel.text = "Score \(score)\nTap Play Again to retry."
            overlayButton.setTitle("Play again", for: .normal)
        }

        @objc private func closeTapped() {
            stopDisplayLink()
            onClose?()
        }

        @objc private func restartTapped() {
            resetGame()
            showOverlay(title: "Asteroids", subtitle: "Use ← → / A D to rotate, ↑ / W to thrust, Space to fire.\nTouch buttons also work.")
        }

        private static func makeStarFieldImage(size: CGSize) -> UIImage? {
            guard size.width > 0, size.height > 0 else { return nil }
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let count = Int((size.width * size.height) / 2400)
                for _ in 0..<max(350, count) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let radius = CGFloat.random(in: 0.5...1.8)
                    let alpha = CGFloat.random(in: 0.25...0.8)
                    UIColor.white.withAlphaComponent(alpha).setFill()
                    ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
                }
            }
        }
    }

    private final class TetrisGameView: UIView, EasterGamePlayable, EasterGameKeyInput {
        private enum GameState {
            case idle
            case playing
            case ended
        }

        private struct Tetromino {
            let rotations: [[CGPoint]]
            let color: UIColor
        }

        private let backgroundLayer = CAGradientLayer()
        private let boardLayer = CALayer()
        private let pieceLayer = CALayer()
        private let hudView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        private let titleLabel = UILabel()
        private let scoreLabel = UILabel()
        private let linesLabel = UILabel()
        private let levelLabel = UILabel()
        private let closeButton = UIButton(type: .system)
        private let restartButton = UIButton(type: .system)
        private let overlayView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        private let overlayTitleLabel = UILabel()
        private let overlaySubtitleLabel = UILabel()
        private let overlayButton = UIButton(type: .system)

        private var displayLink: CADisplayLink?
        private var lastFrameTime: CFTimeInterval = 0
        private var tickAccumulator: TimeInterval = 0
        private var dropInterval: TimeInterval = 0.65
        private let rows = 20
        private let cols = 10
        private var grid: [[UIColor?]] = []
        private var tetrominoes: [Tetromino] = []
        private var currentIndex = 0
        private var currentRotation = 0
        private var currentPosition = CGPoint(x: 3, y: 0)
        private var boardRect: CGRect = .zero
        private var cellSize: CGFloat = 14
        private var score = 0
        private var lines = 0
        private var level = 1
        private var softDrop = false
        private var gameState: GameState = .idle

        var onClose: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            return nil
        }

        deinit {
            stopDisplayLink()
        }

        func start() {
            resetGame()
            showOverlay(title: "Tetris", subtitle: "Use arrows/WASD to move, Up to rotate, Space to drop.")
            becomeFirstResponder()
        }

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                becomeFirstResponder()
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            makeKeyCommands(target: self, action: #selector(handleKeyCommandProxy(_:)))
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: true)
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            handlePresses(presses, isDown: false)
            super.pressesEnded(presses, with: event)
        }

        func makeKeyCommands(target: Any, action: Selector) -> [UIKeyCommand] {
            [
                UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: action),
                UIKeyCommand(input: "a", modifierFlags: [], action: action),
                UIKeyCommand(input: "d", modifierFlags: [], action: action),
                UIKeyCommand(input: "s", modifierFlags: [], action: action),
                UIKeyCommand(input: "w", modifierFlags: [], action: action),
                UIKeyCommand(input: " ", modifierFlags: [], action: action)
            ]
        }

        @objc private func handleKeyCommandProxy(_ command: UIKeyCommand) {
            handleKeyCommand(command)
        }

        func handleKeyCommand(_ command: UIKeyCommand) {
            switch command.input {
            case UIKeyCommand.inputLeftArrow, "a":
                moveLeft()
            case UIKeyCommand.inputRightArrow, "d":
                moveRight()
            case UIKeyCommand.inputDownArrow, "s":
                softDropTap()
            case UIKeyCommand.inputUpArrow, "w":
                rotatePiece()
            case " ":
                hardDrop()
            default:
                break
            }
        }

        func handlePresses(_ presses: Set<UIPress>, isDown: Bool) {
            for press in presses {
                guard let key = press.key else { continue }
                if key.keyCode == .keyboardDownArrow || key.keyCode == .keyboardS {
                    softDrop = isDown
                } else if key.keyCode == .keyboardSpacebar {
                    if isDown { hardDrop() }
                }
            }
        }

        private func resetGame() {
            gameState = .idle
            score = 0
            lines = 0
            level = 1
            dropInterval = 0.65
            grid = Array(repeating: Array(repeating: nil, count: cols), count: rows)
            tetrominoes = Self.makeTetrominoes()
            spawnPiece()
            updateLabels()
            restartButton.isHidden = true
            renderBoard()
        }

        private func setupView() {
            backgroundColor = .clear
            backgroundLayer.colors = [
                UIColor(red: 0.05, green: 0.06, blue: 0.14, alpha: 1.0).cgColor,
                UIColor(red: 0.10, green: 0.14, blue: 0.26, alpha: 1.0).cgColor
            ]
            backgroundLayer.startPoint = CGPoint(x: 0, y: 0)
            backgroundLayer.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(backgroundLayer)
            layer.addSublayer(boardLayer)
            layer.addSublayer(pieceLayer)

            hudView.layer.cornerRadius = 18
            hudView.layer.masksToBounds = true
            addSubview(hudView)

            titleLabel.text = "Tetris"
            titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 16) ?? UIFont.systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textColor = UIColor.label

            scoreLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            linesLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            levelLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
            scoreLabel.textColor = UIColor.label
            linesLabel.textColor = UIColor.label
            levelLabel.textColor = UIColor.label

            closeButton.setTitle("Close", for: .normal)
            closeButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

            restartButton.setTitle("Restart", for: .normal)
            restartButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
            restartButton.isHidden = true
            restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)

            let hudStack = UIStackView(arrangedSubviews: [titleLabel, scoreLabel, linesLabel, levelLabel, UIView(), restartButton, closeButton])
            hudStack.axis = .horizontal
            hudStack.spacing = 10
            hudStack.alignment = .center
            hudStack.translatesAutoresizingMaskIntoConstraints = false
            hudView.contentView.addSubview(hudStack)
            NSLayoutConstraint.activate([
                hudStack.topAnchor.constraint(equalTo: hudView.contentView.topAnchor, constant: 10),
                hudStack.leadingAnchor.constraint(equalTo: hudView.contentView.leadingAnchor, constant: 12),
                hudStack.trailingAnchor.constraint(equalTo: hudView.contentView.trailingAnchor, constant: -12),
                hudStack.bottomAnchor.constraint(equalTo: hudView.contentView.bottomAnchor, constant: -10)
            ])

            overlayView.layer.cornerRadius = 20
            overlayView.layer.masksToBounds = true
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(overlayView)

            overlayTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
            overlayTitleLabel.textColor = .white
            overlayTitleLabel.textAlignment = .center

            overlaySubtitleLabel.font = UIFont(name: "AvenirNext-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
            overlaySubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            overlaySubtitleLabel.textAlignment = .center
            overlaySubtitleLabel.numberOfLines = 0

            overlayButton.setTitle("Start", for: .normal)
            overlayButton.titleLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
            overlayButton.tintColor = .white
            overlayButton.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.85)
            overlayButton.layer.cornerRadius = 16
            overlayButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

            let overlayStack = UIStackView(arrangedSubviews: [overlayTitleLabel, overlaySubtitleLabel, overlayButton])
            overlayStack.axis = .vertical
            overlayStack.spacing = 12
            overlayStack.alignment = .center
            overlayStack.translatesAutoresizingMaskIntoConstraints = false
            overlayView.contentView.addSubview(overlayStack)
            NSLayoutConstraint.activate([
                overlayStack.topAnchor.constraint(equalTo: overlayView.contentView.topAnchor, constant: 20),
                overlayStack.leadingAnchor.constraint(equalTo: overlayView.contentView.leadingAnchor, constant: 20),
                overlayStack.trailingAnchor.constraint(equalTo: overlayView.contentView.trailingAnchor, constant: -20),
                overlayStack.bottomAnchor.constraint(equalTo: overlayView.contentView.bottomAnchor, constant: -20),
                overlayButton.heightAnchor.constraint(equalToConstant: 40),
                overlayButton.widthAnchor.constraint(equalToConstant: 140)
            ])

            let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(moveLeft))
            swipeLeft.direction = .left
            let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(moveRight))
            swipeRight.direction = .right
            let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(softDropTap))
            swipeDown.direction = .down
            let tap = UITapGestureRecognizer(target: self, action: #selector(rotatePiece))
            addGestureRecognizer(swipeLeft)
            addGestureRecognizer(swipeRight)
            addGestureRecognizer(swipeDown)
            addGestureRecognizer(tap)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            backgroundLayer.frame = bounds
            let safe = safeAreaInsets
            let hudHeight: CGFloat = 58
            hudView.frame = CGRect(x: 18, y: safe.top + 12, width: bounds.width - 36, height: hudHeight)
            let boardTop = hudView.frame.maxY + 16
            let boardSide: CGFloat = 26
            let maxWidth = bounds.width - boardSide * 2
            let maxHeight = bounds.height - boardTop - safe.bottom - 40
            let cell = min(maxWidth / CGFloat(cols), maxHeight / CGFloat(rows))
            cellSize = max(12, cell)
            let boardWidth = cellSize * CGFloat(cols)
            let boardHeight = cellSize * CGFloat(rows)
            let boardX = (bounds.width - boardWidth) / 2
            boardRect = CGRect(x: boardX, y: boardTop, width: boardWidth, height: boardHeight)
            boardLayer.frame = bounds
            pieceLayer.frame = bounds

            let overlayWidth = min(bounds.width - 40, 360)
            overlayView.frame = CGRect(x: (bounds.width - overlayWidth) / 2,
                                       y: (bounds.height - 220) / 2,
                                       width: overlayWidth,
                                       height: 220)
            renderBoard()
        }

        private func updateLabels() {
            scoreLabel.text = "Score \(score)"
            linesLabel.text = "Lines \(lines)"
            levelLabel.text = "Lv \(level)"
        }

        private func showOverlay(title: String, subtitle: String) {
            overlayTitleLabel.text = title
            overlaySubtitleLabel.text = subtitle
            overlayButton.setTitle("Start", for: .normal)
            overlayView.isHidden = false
            overlayView.alpha = 1.0
            gameState = .idle
        }

        @objc private func startTapped() {
            overlayView.isHidden = true
            restartButton.isHidden = true
            gameState = .playing
            startDisplayLink()
        }

        private func startDisplayLink() {
            stopDisplayLink()
            lastFrameTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink?.add(to: .main, forMode: .common)
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard gameState == .playing else { return }
            let now = link.timestamp
            let dt = min(1.0 / 30.0, now - lastFrameTime)
            lastFrameTime = now
            tickAccumulator += dt
            let interval = softDrop ? dropInterval * 0.2 : dropInterval
            if tickAccumulator >= interval {
                tickAccumulator = 0
                if !movePiece(dx: 0, dy: 1) {
                    lockPiece()
                }
            }
        }

        private func spawnPiece() {
            currentIndex = Int.random(in: 0..<tetrominoes.count)
            currentRotation = 0
            currentPosition = CGPoint(x: 3, y: 0)
            if collides(at: currentPosition, rotation: currentRotation) {
                endGame()
            }
            renderBoard()
        }

        @objc private func moveLeft() { _ = movePiece(dx: -1, dy: 0) }
        @objc private func moveRight() { _ = movePiece(dx: 1, dy: 0) }
        @objc private func softDropTap() { _ = movePiece(dx: 0, dy: 1) }

        @objc private func rotatePiece() {
            guard gameState == .playing else { return }
            let next = (currentRotation + 1) % tetrominoes[currentIndex].rotations.count
            if !collides(at: currentPosition, rotation: next) {
                currentRotation = next
                renderBoard()
            }
        }

        @objc private func hardDrop() {
            guard gameState == .playing else { return }
            while movePiece(dx: 0, dy: 1) {}
            lockPiece()
        }

        private func movePiece(dx: Int, dy: Int) -> Bool {
            guard gameState == .playing else { return false }
            let nextPos = CGPoint(x: currentPosition.x + CGFloat(dx), y: currentPosition.y + CGFloat(dy))
            if !collides(at: nextPos, rotation: currentRotation) {
                currentPosition = nextPos
                renderBoard()
                return true
            }
            return false
        }

        private func collides(at position: CGPoint, rotation: Int) -> Bool {
            let blocks = tetrominoes[currentIndex].rotations[rotation]
            for block in blocks {
                let x = Int(position.x) + Int(block.x)
                let y = Int(position.y) + Int(block.y)
                if x < 0 || x >= cols || y >= rows { return true }
                if y >= 0, grid[y][x] != nil { return true }
            }
            return false
        }

        private func lockPiece() {
            let blocks = tetrominoes[currentIndex].rotations[currentRotation]
            for block in blocks {
                let x = Int(currentPosition.x) + Int(block.x)
                let y = Int(currentPosition.y) + Int(block.y)
                if y >= 0 && y < rows && x >= 0 && x < cols {
                    grid[y][x] = tetrominoes[currentIndex].color
                }
            }
            clearLines()
            spawnPiece()
        }

        private func clearLines() {
            var cleared = 0
            for row in (0..<rows).reversed() {
                if grid[row].allSatisfy({ $0 != nil }) {
                    grid.remove(at: row)
                    grid.insert(Array(repeating: nil, count: cols), at: 0)
                    cleared += 1
                }
            }
            if cleared > 0 {
                lines += cleared
                score += cleared * 100
                level = 1 + lines / 10
                dropInterval = max(0.18, 0.65 - Double(level - 1) * 0.04)
                updateLabels()
            }
        }

        private func renderBoard() {
            boardLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            pieceLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

            for row in 0..<rows {
                for col in 0..<cols {
                    if let color = grid[row][col] {
                        let layer = CALayer()
                        layer.backgroundColor = color.cgColor
                        layer.cornerRadius = 4
                        layer.frame = CGRect(x: boardRect.minX + CGFloat(col) * cellSize,
                                             y: boardRect.minY + CGFloat(row) * cellSize,
                                             width: cellSize - 1,
                                             height: cellSize - 1)
                        boardLayer.addSublayer(layer)
                    }
                }
            }

            let blocks = tetrominoes[currentIndex].rotations[currentRotation]
            for block in blocks {
                let x = Int(currentPosition.x) + Int(block.x)
                let y = Int(currentPosition.y) + Int(block.y)
                if y >= 0 {
                    let layer = CALayer()
                    layer.backgroundColor = tetrominoes[currentIndex].color.cgColor
                    layer.cornerRadius = 4
                    layer.frame = CGRect(x: boardRect.minX + CGFloat(x) * cellSize,
                                         y: boardRect.minY + CGFloat(y) * cellSize,
                                         width: cellSize - 1,
                                         height: cellSize - 1)
                    pieceLayer.addSublayer(layer)
                }
            }
        }

        private static func makeTetrominoes() -> [Tetromino] {
            let i = Tetromino(rotations: [
                [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 3, y: 1)],
                [CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 2, y: 3)]
            ], color: UIColor.systemTeal)
            let o = Tetromino(rotations: [
                [CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1)]
            ], color: UIColor.systemYellow)
            let t = Tetromino(rotations: [
                [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1)],
                [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 1, y: 2)],
                [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 1, y: 2)],
                [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2)]
            ], color: UIColor.systemPurple)
            let l = Tetromino(rotations: [
                [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1)],
                [CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2)],
                [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 2, y: 2)],
                [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 2), CGPoint(x: 1, y: 2)]
            ], color: UIColor.systemOrange)
            let j = Tetromino(rotations: [
                [CGPoint(x: 2, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1)],
                [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2), CGPoint(x: 2, y: 2)],
                [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 0, y: 2)],
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2)]
            ], color: UIColor.systemBlue)
            let s = Tetromino(rotations: [
                [CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)],
                [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 2, y: 2)]
            ], color: UIColor.systemGreen)
            let z = Tetromino(rotations: [
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1)],
                [CGPoint(x: 2, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 1, y: 2)]
            ], color: UIColor.systemRed)
            return [i, o, t, l, j, s, z]
        }

        private func endGame() {
            gameState = .ended
            stopDisplayLink()
            updateLabels()
            restartButton.isHidden = false
            overlayView.isHidden = false
            overlayTitleLabel.text = "Game over"
            overlaySubtitleLabel.text = "Score \(score)\nTap Play Again to retry."
            overlayButton.setTitle("Play again", for: .normal)
        }

        @objc private func closeTapped() {
            stopDisplayLink()
            onClose?()
        }

        @objc private func restartTapped() {
            resetGame()
            showOverlay(title: "Tetris", subtitle: "Use arrows/WASD to move, Up to rotate, Space to drop.")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground

        configureUI()
        configureBackground()
        registerKeyboardObservers()
        loadSavedModelPaths()
        loadToolSettings()
        refreshPythonLibraryStatusIfNeeded(force: true)
        applyLastModelSelection()
        loadConversations()
        updateModelUI()
        updateContentMode()

        // Feature 6: Theme change observer
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.themeDidChangeNotification, object: nil)

        // Handle app background/foreground — iOS kills GPU access in background
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func handleDidEnterBackground() {
        // iOS suspends Metal GPU access in background — cancel any active generation
        // to prevent the "Insufficient Permission to submit GPU work" error
        if isGenerating {
            print("[app] Entering background during generation — cancelling to avoid GPU error")
            runner.cancelGeneration()
            // Don't clean up UI here — let the completion handler handle it
            // The generation will complete with partial output
        }
    }

    @objc private func handleWillEnterForeground() {
        // App returning to foreground — GPU is available again
        print("[app] Returning to foreground")
        // If generation was cancelled by background, the UI should already be in a clean state
        // If the model was loaded, it should still work for new generations
    }

    @objc private func handleThemeChange() {
        refreshTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if ThemeManager.shared.mode == .system,
           traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            refreshTheme()
        }
    }

    private func refreshTheme() {
        // Refresh gradient background
        backgroundLayer.colors = WorkspaceStyle.gradientColors
        // Refresh sidebar
        sidebarBackground.effect = UIBlurEffect(style: WorkspaceStyle.sidebarBlurStyle)
        sidebarView.layer.borderColor = WorkspaceStyle.glassStroke.cgColor
        // Refresh title/status colors
        titleLabel.textColor = WorkspaceStyle.primaryText
        statusLabel.textColor = WorkspaceStyle.mutedText
        modelLabel.textColor = WorkspaceStyle.primaryText
        modelPathLabel.textColor = WorkspaceStyle.mutedText
        // Refresh input
        inputTextView.textColor = WorkspaceStyle.primaryText
        inputTextView.backgroundColor = WorkspaceStyle.glassFill
        inputViewContainer.backgroundColor = WorkspaceStyle.glassFill
        inputViewContainer.layer.borderColor = WorkspaceStyle.glassStroke.cgColor
        // Refresh token stats
        tokenStatsLabel.textColor = WorkspaceStyle.mutedText
        view.setNeedsLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Editor is default tab — set it up immediately
        if editorController == nil {
            setupEditorController()
        }
        if !didInitialConversationReload {
            didInitialConversationReload = true
            reloadConversationList()
        }
        if needsConversationReload {
            reloadConversationList()
        }
        if needsInitialScroll {
            needsInitialScroll = false
            scrollChatToBottom()
        }
        autoLoadLastModelIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundLayer.frame = contentView.bounds
        let w = view.bounds.width
        if w < 500 {
            // Compact: hide sidebar, show hamburger
            if !isSidebarHidden {
                isSidebarHidden = true
                sidebarWidthConstraint?.constant = 0
                sidebarView.isHidden = true
                hamburgerButton.isHidden = false
            }
        } else {
            if isSidebarHidden {
                isSidebarHidden = false
                sidebarView.isHidden = false
                hamburgerButton.isHidden = true
            }
            sidebarWidthConstraint?.constant = w < 900 ? 220 : (w < 1100 ? 250 : 300)
        }
        updateComposerUI()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.view.layoutIfNeeded()
        })
    }

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleKeyboardFrameChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleKeyboardFrameChange(_:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }

    @objc private func handleKeyboardFrameChange(_ note: Notification) {
        guard let userInfo = note.userInfo else { return }
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let curve = UIView.AnimationOptions(rawValue: curveRaw << 16)

        let overlap: CGFloat
        if note.name == UIResponder.keyboardWillHideNotification {
            overlap = 0
        } else if let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let converted = view.convert(frame, from: nil)
            let rawOverlap = max(0, view.bounds.maxY - converted.minY - view.safeAreaInsets.bottom)
            // Ignore tiny keyboard frame changes that happen with external keyboards.
            overlap = rawOverlap < 56 ? 0 : rawOverlap
        } else {
            overlap = 0
        }

        contentStackBottomConstraint?.constant = -(WorkspaceStyle.spacing16 + overlap)
        UIView.animate(withDuration: duration, delay: 0, options: [curve, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
        }
    }

    private func configureBackground() {
        // ChatGPT-style: flat solid background, no gradients
        contentView.backgroundColor = WorkspaceStyle.solidBackground
    }

    private func configureUI() {
        configureControlStyles()

        let rootStack = UIStackView(arrangedSubviews: [sidebarView, contentView])
        rootStack.axis = .horizontal
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        let sidebarStack = buildSidebarSection()
        let chatSection = buildChatSection()
        let contentStack = buildFilesContainerSection(chatContainer: chatSection)
        buildSettingsPanel()

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            sidebarStack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: WorkspaceStyle.spacing20),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: WorkspaceStyle.spacing16),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -WorkspaceStyle.spacing16),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -WorkspaceStyle.spacing16),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: WorkspaceStyle.spacing16),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            chatScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            filesContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),

            settingsPanel.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 12),
            settingsPanel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            settingsPanel.widthAnchor.constraint(equalToConstant: 360),
            settingsPanel.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        contentStackBottomConstraint = contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -WorkspaceStyle.spacing16)
        contentStackBottomConstraint?.isActive = true

        sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: 280)
        sidebarWidthConstraint?.isActive = true

        configureFilesManager()
        updateStatus(statusLabel.text ?? "")
        updateComposerUI()
    }

    private func configureControlStyles() {
        // ── Title ──
        titleLabel.text = "OfflinAi"
        titleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold).rounded
        titleLabel.textColor = UIColor.label

        // ── Status ──
        statusLabel.text = "Select and load a model."
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium).rounded
        statusLabel.textColor = WorkspaceStyle.mutedText
        statusLabel.numberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingTail

        // ── Model label ──
        modelLabel.text = "Model"
        modelLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold).rounded
        modelLabel.textColor = WorkspaceStyle.mutedText

        // ── Model state badge ──
        modelStateBadgeLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold).rounded
        modelStateBadgeLabel.textColor = WorkspaceStyle.accent
        modelStateBadgeLabel.backgroundColor = WorkspaceStyle.accent.withAlphaComponent(0.10)
        modelStateBadgeLabel.layer.cornerRadius = 8
        modelStateBadgeLabel.layer.cornerCurve = .continuous
        modelStateBadgeLabel.layer.masksToBounds = true
        modelStateBadgeLabel.textAlignment = .center
        modelStateBadgeLabel.text = "  Idle  "

        // ── Model selector (glass pill) ──
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = selectedModelSlot.title
            config.image = UIImage(systemName: "chevron.down")
            config.imagePlacement = .trailing
            config.imagePadding = 6
            config.baseBackgroundColor = UIColor(white: 1.0, alpha: 0.55)
            config.baseForegroundColor = WorkspaceStyle.accent
            config.cornerStyle = .capsule
            config.background.strokeColor = WorkspaceStyle.glassStroke
            config.background.strokeWidth = 0.5
            modelSelectButton.configuration = config
        } else {
            modelSelectButton.setTitle(selectedModelSlot.title, for: .normal)
        }
        modelSelectButton.showsMenuAsPrimaryAction = true
        modelSelectButton.menu = makeModelMenu()

        modelPathLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular).rounded
        modelPathLabel.textColor = WorkspaceStyle.mutedText
        modelPathLabel.numberOfLines = 2

        // ── Action buttons (glass filled) ──
        importButton.addTarget(self, action: #selector(importModelTapped), for: .touchUpInside)
        downloadButton.addTarget(self, action: #selector(downloadModelTapped), for: .touchUpInside)
        loadButton.addTarget(self, action: #selector(loadModelTapped), for: .touchUpInside)

        if #available(iOS 15.0, *) {
            func applyGlassAction(_ button: UIButton, title: String, systemImage: String, bg: UIColor) {
                var config = UIButton.Configuration.filled()
                config.title = title
                config.image = UIImage(systemName: systemImage)
                config.imagePadding = 6
                config.baseBackgroundColor = bg
                config.baseForegroundColor = UIColor.white
                config.cornerStyle = .capsule
                button.configuration = config
            }
            applyGlassAction(importButton, title: "Import", systemImage: "square.and.arrow.down", bg: WorkspaceStyle.accent.withAlphaComponent(0.85))
            applyGlassAction(downloadButton, title: "Download", systemImage: "arrow.down.circle", bg: WorkspaceStyle.accent)
            applyGlassAction(loadButton, title: "Load", systemImage: "play.fill", bg: UIColor.systemGreen.withAlphaComponent(0.85))
        } else {
            importButton.setTitle("Import", for: .normal)
            downloadButton.setTitle("Download", for: .normal)
            loadButton.setTitle("Load", for: .normal)
        }

        // ── Segment controls (glass) ──
        contentModeControl.selectedSegmentIndex = 0
        contentModeControl.addTarget(self, action: #selector(contentModeChanged), for: .valueChanged)
        contentModeControl.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        contentModeControl.layer.cornerRadius = WorkspaceStyle.radiusMedium
        contentModeControl.layer.cornerCurve = .continuous
        if #available(iOS 13.0, *) {
            contentModeControl.selectedSegmentTintColor = UIColor(white: 1.0, alpha: 0.7)
        }

        // ── Thinking effort ──
        effortLabel.text = "Thinking effort"
        effortLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold).rounded
        effortLabel.textColor = WorkspaceStyle.mutedText
        effortSegment.selectedSegmentIndex = ThinkingEffort.high.rawValue
        effortSegment.addTarget(self, action: #selector(effortChanged), for: .valueChanged)
        effortSegment.backgroundColor = UIColor(white: 1.0, alpha: 0.3)
        if #available(iOS 13.0, *) {
            effortSegment.selectedSegmentTintColor = UIColor(white: 1.0, alpha: 0.65)
        }

        // ── Show reasoning toggle ──
        thinkingToggleLabel.text = "Show reasoning"
        thinkingToggleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold).rounded
        thinkingToggleLabel.textColor = WorkspaceStyle.mutedText
        thinkingToggle.isOn = true
        showThinking = true
        thinkingToggle.onTintColor = WorkspaceStyle.accent
        thinkingToggle.addTarget(self, action: #selector(thinkingToggleChanged), for: .valueChanged)

        // ── Max tokens ──
        maxTokensLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold).rounded
        maxTokensLabel.textColor = WorkspaceStyle.mutedText
        maxTokensStepper.minimumValue = 128
        maxTokensStepper.maximumValue = 1_048_576
        maxTokensStepper.stepValue = 512
        maxTokensStepper.value = Double(maxOutputTokens)
        maxTokensStepper.addTarget(self, action: #selector(maxTokensChanged), for: .valueChanged)
        updateMaxTokensLabel()
        updateSystemPrompt()

        // ── Auto-load ──
        autoLoadLabel.text = "Auto-load last model"
        autoLoadLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium).rounded
        autoLoadLabel.textColor = WorkspaceStyle.mutedText
        autoLoadToggle.onTintColor = WorkspaceStyle.accent
        autoLoadToggle.addTarget(self, action: #selector(autoLoadChanged), for: .valueChanged)

        // ── Python tools ──
        pythonToolsLabel.text = "Enable Python tool"
        pythonToolsLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium).rounded
        pythonToolsLabel.textColor = WorkspaceStyle.mutedText
        pythonToolsToggle.isOn = true
        pythonToolsToggle.onTintColor = WorkspaceStyle.accent
        pythonToolsToggle.addTarget(self, action: #selector(pythonToolsToggleChanged), for: .valueChanged)

        pythonStatusIconLabel.text = "PY"
        pythonStatusIconLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold).rounded
        pythonStatusIconLabel.textColor = UIColor.white
        pythonStatusIconLabel.backgroundColor = WorkspaceStyle.accent
        pythonStatusIconLabel.textAlignment = .center
        pythonStatusIconLabel.layer.cornerRadius = 8
        pythonStatusIconLabel.layer.cornerCurve = .continuous
        pythonStatusIconLabel.layer.masksToBounds = true
        pythonStatusIconLabel.translatesAutoresizingMaskIntoConstraints = false

        pythonStatusLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular).rounded
        pythonStatusLabel.textColor = WorkspaceStyle.mutedText
        pythonStatusLabel.numberOfLines = 0
        pythonStatusLabel.text = "Library status not checked."

        pythonRefreshButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold).rounded
        pythonRefreshButton.addTarget(self, action: #selector(refreshPythonLibraryStatusTapped), for: .touchUpInside)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.tinted()
            config.title = "Refresh"
            config.image = UIImage(systemName: "arrow.clockwise")
            config.imagePadding = 4
            config.baseForegroundColor = WorkspaceStyle.accent
            config.baseBackgroundColor = WorkspaceStyle.accent.withAlphaComponent(0.10)
            config.cornerStyle = .capsule
            pythonRefreshButton.configuration = config
        } else {
            pythonRefreshButton.setTitle("Refresh", for: .normal)
            pythonRefreshButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        }

        // ── Chat scroll ──
        chatScrollView.backgroundColor = UIColor.clear
        chatScrollView.alwaysBounceVertical = true
        chatScrollView.showsVerticalScrollIndicator = false
        chatScrollView.keyboardDismissMode = .interactive
        chatStack.axis = .vertical
        chatStack.spacing = WorkspaceStyle.spacing16
        chatStack.alignment = .fill

        // ── Input container (glass) ──
        inputViewContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.50)
        inputViewContainer.layer.cornerRadius = 24
        inputViewContainer.layer.cornerCurve = .continuous
        inputViewContainer.layer.borderWidth = WorkspaceStyle.borderWidth
        inputViewContainer.layer.borderColor = WorkspaceStyle.glassStroke.cgColor
        inputViewContainer.layer.shadowColor = WorkspaceStyle.accent.withAlphaComponent(0.15).cgColor
        inputViewContainer.layer.shadowOpacity = 0.10
        inputViewContainer.layer.shadowRadius = 16
        inputViewContainer.layer.shadowOffset = CGSize(width: 0, height: 4)

        inputTextView.font = UIFont.systemFont(ofSize: 16, weight: .regular).rounded
        inputTextView.textColor = UIColor.label
        inputTextView.backgroundColor = .clear
        inputTextView.textContainerInset = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        inputTextView.delegate = self
        inputTextView.returnKeyType = .send
        inputTextView.enablesReturnKeyAutomatically = true
        inputTextView.smartQuotesType = .no
        inputTextView.smartDashesType = .no
        inputTextView.autocorrectionType = .default

        // ── Send button (accent capsule) ──
        if #available(iOS 15.0, *) {
            var sendConfig = UIButton.Configuration.filled()
            sendConfig.image = UIImage(systemName: "arrow.up.circle.fill")
            sendConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            sendConfig.baseBackgroundColor = WorkspaceStyle.accent
            sendConfig.baseForegroundColor = UIColor.white
            sendConfig.cornerStyle = .capsule
            sendConfig.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            sendButton.configuration = sendConfig
        } else {
            sendButton.setTitle("Send", for: .normal)
        }
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = WorkspaceStyle.accent

        // ── Thinking container (glass) ──
        // Thinking UI is now inline in chat bubbles

        // ── New Chat button (glass accent) ──
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = "New Chat"
            config.image = UIImage(systemName: "plus.bubble")
            config.imagePadding = 8
            config.baseBackgroundColor = WorkspaceStyle.accent
            config.baseForegroundColor = UIColor.white
            config.cornerStyle = .capsule
            newChatButton.configuration = config
        } else {
            newChatButton.setTitle("New Chat", for: .normal)
            newChatButton.setImage(UIImage(systemName: "plus"), for: .normal)
            newChatButton.tintColor = UIColor.white
        }

        // ── Conversation search ──
        conversationSearchBar.placeholder = "Search chats"
        conversationSearchBar.searchBarStyle = .minimal
        conversationSearchBar.autocapitalizationType = .none
        conversationSearchBar.autocorrectionType = .no
        conversationSearchBar.delegate = self
        conversationSearchBar.returnKeyType = .done

        // ── Conversations table ──
        conversationsTable.backgroundColor = .clear
        conversationsTable.separatorStyle = .none
        conversationsTable.dataSource = self
        conversationsTable.delegate = self
        conversationsTable.rowHeight = 60
        conversationsTable.contentInset = UIEdgeInsets(top: WorkspaceStyle.spacing4, left: 0, bottom: WorkspaceStyle.spacing8, right: 0)
        conversationsTable.showsVerticalScrollIndicator = false
        conversationEmptyLabel.text = "No conversations yet"
        conversationEmptyLabel.textColor = WorkspaceStyle.mutedText.withAlphaComponent(0.6)
        conversationEmptyLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        conversationEmptyLabel.textAlignment = .center
        conversationEmptyLabel.numberOfLines = 0
        conversationEmptyLabel.isHidden = true
        conversationsTable.backgroundView = conversationEmptyLabel

        // ── Settings button (glass) ──
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.tinted()
            config.title = "Settings"
            config.image = UIImage(systemName: "slider.horizontal.3")
            config.imagePadding = 6
            config.baseForegroundColor = WorkspaceStyle.accent
            config.baseBackgroundColor = UIColor(white: 1.0, alpha: 0.35)
            config.cornerStyle = .capsule
            config.background.strokeColor = WorkspaceStyle.glassStroke
            config.background.strokeWidth = 0.5
            settingsButton.configuration = config
        } else {
            settingsButton.setTitle("Settings", for: .normal)
            settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
            settingsButton.tintColor = WorkspaceStyle.accent
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissSettingsPanel))
        tapGesture.cancelsTouchesInView = false
        contentView.addGestureRecognizer(tapGesture)
    }

    private func buildSidebarSection() -> UIStackView {
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.backgroundColor = UIColor(white: 1.0, alpha: 0.25)
        sidebarView.layer.borderWidth = 0
        sidebarView.layer.shadowColor = UIColor.black.withAlphaComponent(0.12).cgColor
        sidebarView.layer.shadowOpacity = 0.1
        sidebarView.layer.shadowRadius = 20
        sidebarView.layer.shadowOffset = CGSize(width: 4, height: 0)

        // Glass blur background
        let sidebarBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        sidebarBlur.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(sidebarBlur)
        NSLayoutConstraint.activate([
            sidebarBlur.topAnchor.constraint(equalTo: sidebarView.topAnchor),
            sidebarBlur.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            sidebarBlur.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            sidebarBlur.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor)
        ])

        sidebarBackground.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(sidebarBackground)
        NSLayoutConstraint.activate([
            sidebarBackground.topAnchor.constraint(equalTo: sidebarView.topAnchor),
            sidebarBackground.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            sidebarBackground.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            sidebarBackground.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor)
        ])

        // Library docs sidebar (replaces conversation history)
        let sidebarTitle = UILabel()
        sidebarTitle.text = "Libraries"
        sidebarTitle.font = UIFont.systemFont(ofSize: 20, weight: .bold).rounded
        sidebarTitle.textColor = .label

        let sidebarHeader = UIStackView(arrangedSubviews: [sidebarTitle, settingsButton])
        sidebarHeader.axis = .horizontal
        sidebarHeader.distribution = .equalSpacing

        // Embed compact library docs
        let sidebarDocsVC = LibraryDocsViewController()
        sidebarDocsVC.isCompactMode = true
        sidebarDocsVC.delegate = self
        sidebarDocsVC.view.translatesAutoresizingMaskIntoConstraints = false

        let sidebarStack = UIStackView(arrangedSubviews: [sidebarHeader, sidebarDocsVC.view])
        sidebarStack.axis = .vertical
        sidebarStack.spacing = WorkspaceStyle.spacing12
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(sidebarStack)

        // Keep VC alive
        addChild(sidebarDocsVC)
        sidebarDocsVC.didMove(toParent: self)

        return sidebarStack
    }

    private func buildComposerSection() -> UIStackView {
        let inputRow = UIStackView(arrangedSubviews: [inputViewContainer, sendButton])
        inputRow.axis = .horizontal
        inputRow.spacing = WorkspaceStyle.spacing12
        inputRow.alignment = .bottom

        inputViewContainer.translatesAutoresizingMaskIntoConstraints = false
        inputViewContainer.addSubview(inputTextView)
        inputViewContainer.addSubview(inputPlaceholderLabel)
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        inputPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        inputPlaceholderLabel.text = "Message the model..."
        inputPlaceholderLabel.textColor = WorkspaceStyle.mutedText
        inputPlaceholderLabel.font = UIFont(name: "AvenirNext-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        NSLayoutConstraint.activate([
            inputTextView.topAnchor.constraint(equalTo: inputViewContainer.topAnchor),
            inputTextView.leadingAnchor.constraint(equalTo: inputViewContainer.leadingAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: inputViewContainer.trailingAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: inputViewContainer.bottomAnchor),
            inputPlaceholderLabel.leadingAnchor.constraint(equalTo: inputViewContainer.leadingAnchor, constant: 17),
            inputPlaceholderLabel.topAnchor.constraint(equalTo: inputViewContainer.topAnchor, constant: 11)
        ])
        inputHeightConstraint = inputTextView.heightAnchor.constraint(equalToConstant: 90)
        inputHeightConstraint?.isActive = true
        return inputRow
    }

    private func buildChatSection() -> UIStackView {
        let modelButtons = UIStackView(arrangedSubviews: [importButton, downloadButton, loadButton])
        modelButtons.axis = .horizontal
        modelButtons.spacing = WorkspaceStyle.spacing8
        modelButtons.distribution = .fillEqually

        let topHeaderRow = UIStackView(arrangedSubviews: [modelLabel, modelSelectButton, modelStateBadgeLabel, statusLabel])
        topHeaderRow.axis = .horizontal
        topHeaderRow.alignment = .center
        topHeaderRow.spacing = WorkspaceStyle.spacing8
        modelLabel.setContentHuggingPriority(.required, for: .horizontal)
        modelSelectButton.setContentHuggingPriority(.required, for: .horizontal)
        modelStateBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let modelHeaderStack = UIStackView(arrangedSubviews: [topHeaderRow, modelPathLabel, modelButtons])
        modelHeaderStack.axis = .vertical
        modelHeaderStack.spacing = WorkspaceStyle.spacing8

        let modelCard = UIView()
        styleCard(modelCard, tint: WorkspaceStyle.accent)
        modelCard.translatesAutoresizingMaskIntoConstraints = false
        modelHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        modelCard.addSubview(modelHeaderStack)
        NSLayoutConstraint.activate([
            modelHeaderStack.topAnchor.constraint(equalTo: modelCard.topAnchor, constant: WorkspaceStyle.spacing12),
            modelHeaderStack.leadingAnchor.constraint(equalTo: modelCard.leadingAnchor, constant: WorkspaceStyle.spacing12),
            modelHeaderStack.trailingAnchor.constraint(equalTo: modelCard.trailingAnchor, constant: -WorkspaceStyle.spacing12),
            modelHeaderStack.bottomAnchor.constraint(equalTo: modelCard.bottomAnchor, constant: -WorkspaceStyle.spacing12)
        ])

        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        chatStack.translatesAutoresizingMaskIntoConstraints = false
        chatScrollView.addSubview(chatStack)
        NSLayoutConstraint.activate([
            chatStack.topAnchor.constraint(equalTo: chatScrollView.contentLayoutGuide.topAnchor),
            chatStack.leadingAnchor.constraint(equalTo: chatScrollView.contentLayoutGuide.leadingAnchor),
            chatStack.trailingAnchor.constraint(equalTo: chatScrollView.contentLayoutGuide.trailingAnchor),
            chatStack.bottomAnchor.constraint(equalTo: chatScrollView.contentLayoutGuide.bottomAnchor),
            chatStack.widthAnchor.constraint(equalTo: chatScrollView.frameLayoutGuide.widthAnchor)
        ])

        // Thinking header/layout removed — now inline in chat bubbles

        let inputRow = buildComposerSection()

        let container = UIStackView(arrangedSubviews: [modelCard, chatScrollView, inputRow, activityIndicator])
        container.axis = .vertical
        container.spacing = WorkspaceStyle.spacing16
        container.translatesAutoresizingMaskIntoConstraints = false
        self.chatContainer = container
        return container
    }

    private func buildFilesContainerSection(chatContainer: UIStackView) -> UIStackView {
        styleCard(filesContainer, tint: UIColor.systemIndigo)
        filesContainer.translatesAutoresizingMaskIntoConstraints = false
        filesContainer.isHidden = true

        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        // Editor is now index 0 — shown by default
        editorContainer.isHidden = false

        docsContainer.translatesAutoresizingMaskIntoConstraints = false
        docsContainer.isHidden = true

        // Editor first (index 0), then Files (1), Docs (2). chatContainer kept for compatibility but hidden.
        let contentStack = UIStackView(arrangedSubviews: [contentModeControl, editorContainer, filesContainer, docsContainer, chatContainer])
        contentStack.axis = .vertical
        contentStack.spacing = WorkspaceStyle.spacing16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)
        return contentStack
    }

    private func buildSettingsPanel() {
        // ── Header ──────────────────────────────────
        let settingsTitle = UILabel()
        settingsTitle.text = "Settings"
        settingsTitle.font = UIFont.systemFont(ofSize: 24, weight: .bold).rounded
        settingsTitle.textColor = .label

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.secondaryLabel, UIColor.secondarySystemFill]))), for: .normal)
        closeBtn.addTarget(self, action: #selector(dismissSettingsPanel), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [settingsTitle, UIView(), closeBtn])
        headerRow.axis = .horizontal; headerRow.alignment = .center

        // ── 1. Model Info Card (NEW) ────────────────
        let modelNameLbl = UILabel()
        modelNameLbl.text = selectedModelSlot.title
        modelNameLbl.font = UIFont.systemFont(ofSize: 18, weight: .bold).rounded
        modelNameLbl.textColor = .label

        let modelSubtitleLbl = UILabel()
        modelSubtitleLbl.text = selectedModelSlot.subtitle
        modelSubtitleLbl.font = UIFont.systemFont(ofSize: 13, weight: .regular).rounded
        modelSubtitleLbl.textColor = .secondaryLabel

        // Stats row
        let ctxSize = preferredContextSize()
        let statChips: [(String, String, UIColor)] = [
            ("memorychip", "\(ctxSize) ctx", .systemBlue),
            ("internaldrive", selectedModelSlot.subtitle.components(separatedBy: "~").last?.trimmingCharacters(in: .whitespaces) ?? "?", .systemPurple),
            ("bolt.fill", loadedModelSlot != nil ? "Ready" : "Not loaded", loadedModelSlot != nil ? .systemGreen : .systemOrange)
        ]
        let statsRow = UIStackView()
        statsRow.axis = .horizontal; statsRow.spacing = 8; statsRow.distribution = .fillEqually
        for (icon, text, color) in statChips {
            let chip = makeStatChip(icon: icon, text: text, color: color)
            statsRow.addArrangedSubview(chip)
        }

        var changeModelCfg = UIButton.Configuration.filled()
        changeModelCfg.title = "Change Model"
        changeModelCfg.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        changeModelCfg.imagePadding = 6
        changeModelCfg.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        changeModelCfg.baseForegroundColor = .systemBlue
        changeModelCfg.cornerStyle = .capsule
        changeModelCfg.buttonSize = .small
        changeModelCfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let changeModelBtn = UIButton(type: .system)
        changeModelBtn.configuration = changeModelCfg
        changeModelBtn.addTarget(self, action: #selector(dismissSettingsPanel), for: .touchUpInside)

        let modelContentStack = UIStackView(arrangedSubviews: [modelNameLbl, modelSubtitleLbl, statsRow, changeModelBtn])
        modelContentStack.axis = .vertical; modelContentStack.spacing = 10
        modelContentStack.setCustomSpacing(4, after: modelNameLbl)
        let modelCard = makeSettingsCard(header: "Model", icon: "cpu", tint: .systemBlue, content: modelContentStack)

        // ── 2. Persona Card ─────────────────────────
        var presetBtnConfig = UIButton.Configuration.filled()
        presetBtnConfig.title = SystemPromptPresetsManager.shared.activePresetName
        presetBtnConfig.baseBackgroundColor = UIColor.systemPurple.withAlphaComponent(0.12)
        presetBtnConfig.baseForegroundColor = .systemPurple
        presetBtnConfig.cornerStyle = .capsule
        presetBtnConfig.image = UIImage(systemName: "person.fill")
        presetBtnConfig.imagePadding = 8
        presetBtnConfig.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        presetButton.configuration = presetBtnConfig
        presetButton.showsMenuAsPrimaryAction = true

        let presetMenuActions = SystemPromptPresetsManager.builtInPresets.map { preset in
            UIAction(title: preset.name, image: UIImage(systemName: preset.icon)) { [weak self] _ in
                SystemPromptPresetsManager.shared.selectPreset(preset)
                self?.presetButton.configuration?.title = preset.name
                self?.updateSystemPrompt()
                HapticService.shared.tapLight()
            }
        }
        let customPresetAction = UIAction(title: "Custom\u{2026}", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
            guard let self else { return }
            let alert = UIAlertController(title: "Custom System Prompt", message: nil, preferredStyle: .alert)
            alert.addTextField { $0.text = SystemPromptPresetsManager.shared.customPromptText; $0.placeholder = "Enter system prompt\u{2026}" }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                if let t = alert.textFields?.first?.text, !t.isEmpty {
                    SystemPromptPresetsManager.shared.setCustomPrompt(t)
                    self.presetButton.configuration?.title = "Custom"
                    self.updateSystemPrompt()
                }
            })
            self.present(alert, animated: true)
        }
        presetButton.menu = UIMenu(children: presetMenuActions + [customPresetAction])

        let personaDesc = UILabel()
        personaDesc.text = "Choose a personality preset for the AI assistant."
        personaDesc.font = UIFont.systemFont(ofSize: 12, weight: .regular).rounded
        personaDesc.textColor = .tertiaryLabel
        personaDesc.numberOfLines = 0

        let personaContentStack = UIStackView(arrangedSubviews: [presetButton, personaDesc])
        personaContentStack.axis = .vertical; personaContentStack.spacing = 8
        let personaCard = makeSettingsCard(header: "Persona", icon: "person.crop.circle.fill", tint: .systemPurple, content: personaContentStack)

        // ── 3. Generation Card ──────────────────────
        effortLabel.textColor = .label
        effortLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        let effortStack = UIStackView(arrangedSubviews: [effortLabel, effortSegment])
        effortStack.axis = .vertical; effortStack.spacing = 8

        let thinkSep = makeSettingsSeparator()

        thinkingToggleLabel.textColor = .label
        thinkingToggleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        let thinkDesc = UILabel()
        thinkDesc.text = "Display the model's chain-of-thought reasoning steps."
        thinkDesc.font = UIFont.systemFont(ofSize: 12, weight: .regular).rounded
        thinkDesc.textColor = .tertiaryLabel
        thinkDesc.numberOfLines = 0
        let thinkLabelStack = UIStackView(arrangedSubviews: [thinkingToggleLabel, thinkDesc])
        thinkLabelStack.axis = .vertical; thinkLabelStack.spacing = 2
        let thinkRow = UIStackView(arrangedSubviews: [thinkLabelStack, UIView(), thinkingToggle])
        thinkRow.axis = .horizontal; thinkRow.alignment = .center

        let maxSep = makeSettingsSeparator()

        maxTokensLabel.textColor = .label
        maxTokensLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        let maxRow = UIStackView(arrangedSubviews: [maxTokensLabel, UIView(), maxTokensStepper])
        maxRow.axis = .horizontal; maxRow.alignment = .center

        let genContentStack = UIStackView(arrangedSubviews: [effortStack, thinkSep, thinkRow, maxSep, maxRow])
        genContentStack.axis = .vertical; genContentStack.spacing = 12
        let genCard = makeSettingsCard(header: "Generation", icon: "bolt.fill", tint: .systemTeal, content: genContentStack)

        // ── 4. Appearance Card ──────────────────────
        themeSegment.selectedSegmentIndex = ThemeManager.shared.mode.rawValue
        themeSegment.addTarget(self, action: #selector(themeSegmentChanged(_:)), for: .valueChanged)

        let themeLabel = UILabel()
        themeLabel.text = "Theme"
        themeLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        themeLabel.textColor = .label
        let themeRow = UIStackView(arrangedSubviews: [themeLabel, UIView(), themeSegment])
        themeRow.axis = .horizontal; themeRow.alignment = .center

        let appearSep = makeSettingsSeparator()

        hapticsToggleLabel.text = "Haptic Feedback"
        hapticsToggleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        hapticsToggleLabel.textColor = .label
        hapticsToggle.isOn = HapticService.shared.enabled
        hapticsToggle.onTintColor = WorkspaceStyle.accent
        hapticsToggle.addTarget(self, action: #selector(hapticsToggleChanged(_:)), for: .valueChanged)
        let hapticRow = UIStackView(arrangedSubviews: [hapticsToggleLabel, UIView(), hapticsToggle])
        hapticRow.axis = .horizontal; hapticRow.alignment = .center

        let appearContentStack = UIStackView(arrangedSubviews: [themeRow, appearSep, hapticRow])
        appearContentStack.axis = .vertical; appearContentStack.spacing = 12
        let appearCard = makeSettingsCard(header: "Appearance", icon: "paintbrush.fill", tint: .systemPink, content: appearContentStack)

        // ── 5. Tools Card ───────────────────────────
        autoLoadLabel.textColor = .label
        autoLoadLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        let autoRow = UIStackView(arrangedSubviews: [autoLoadLabel, UIView(), autoLoadToggle])
        autoRow.axis = .horizontal; autoRow.alignment = .center

        let toolsSep1 = makeSettingsSeparator()

        pythonToolsLabel.textColor = .label
        pythonToolsLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium).rounded
        let pyRow = UIStackView(arrangedSubviews: [pythonToolsLabel, UIView(), pythonToolsToggle])
        pyRow.axis = .horizontal; pyRow.alignment = .center

        let toolsSep2 = makeSettingsSeparator()

        // Python runtime header
        let pyHeaderLabel = UILabel()
        pyHeaderLabel.text = "Runtime"
        pyHeaderLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold).rounded
        pyHeaderLabel.textColor = .secondaryLabel
        let pyHeaderRow = UIStackView(arrangedSubviews: [pythonStatusIconLabel, pyHeaderLabel, UIView(), pythonRefreshButton])
        pyHeaderRow.axis = .horizontal; pyHeaderRow.alignment = .center; pyHeaderRow.spacing = 6

        // Library chips flow layout
        let libraryChipsView = makeLibraryChipsView()

        pythonStatusLabel.textColor = .secondaryLabel
        pythonStatusLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular).rounded
        pythonStatusLabel.numberOfLines = 0

        let toolsContentStack = UIStackView(arrangedSubviews: [autoRow, toolsSep1, pyRow, toolsSep2, pyHeaderRow, libraryChipsView, pythonStatusLabel])
        toolsContentStack.axis = .vertical; toolsContentStack.spacing = 12
        let toolsCard = makeSettingsCard(header: "Tools", icon: "wrench.and.screwdriver.fill", tint: .systemIndigo, content: toolsContentStack)

        // ── 6. Knowledge Base Card ──────────────────
        let ragDocCount = RAGEngine.shared.documents.count
        let ragChunkCount = RAGEngine.shared.totalChunkCount

        let ragIconRow = UIStackView()
        ragIconRow.axis = .horizontal; ragIconRow.spacing = 16; ragIconRow.alignment = .center
        let docStatView = makeStatBadge(value: "\(ragDocCount)", label: "Documents", color: .systemGreen)
        let chunkStatView = makeStatBadge(value: "\(ragChunkCount)", label: "Chunks", color: .systemMint)
        ragIconRow.addArrangedSubview(docStatView)
        ragIconRow.addArrangedSubview(chunkStatView)
        ragIconRow.addArrangedSubview(UIView()) // spacer

        let ragImportBtn = UIButton(type: .system)
        var ragBtnCfg = UIButton.Configuration.filled()
        ragBtnCfg.title = "Import Document"
        ragBtnCfg.image = UIImage(systemName: "doc.badge.plus")
        ragBtnCfg.imagePadding = 6
        ragBtnCfg.baseBackgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        ragBtnCfg.baseForegroundColor = .systemGreen
        ragBtnCfg.cornerStyle = .capsule
        ragBtnCfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        ragImportBtn.configuration = ragBtnCfg
        ragImportBtn.addTarget(self, action: #selector(ragImportTapped), for: .touchUpInside)

        let ragContentStack = UIStackView(arrangedSubviews: [ragIconRow, ragImportBtn])
        ragContentStack.axis = .vertical; ragContentStack.spacing = 12
        let ragCard = makeSettingsCard(header: "Knowledge Base", icon: "book.closed.fill", tint: .systemGreen, content: ragContentStack)

        // ── 7. Actions Card ─────────────────────────
        let cmpBtn = UIButton(type: .system)
        var cmpCfg = UIButton.Configuration.filled()
        cmpCfg.title = "Compare Models"
        cmpCfg.image = UIImage(systemName: "arrow.left.arrow.right")
        cmpCfg.imagePadding = 8
        cmpCfg.baseBackgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        cmpCfg.baseForegroundColor = .systemOrange
        cmpCfg.cornerStyle = .capsule
        cmpCfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        cmpBtn.configuration = cmpCfg
        cmpBtn.addTarget(self, action: #selector(compareModelsTapped), for: .touchUpInside)

        let exportBtn = UIButton(type: .system)
        var exportCfg = UIButton.Configuration.filled()
        exportCfg.title = "Export Conversation"
        exportCfg.image = UIImage(systemName: "square.and.arrow.up")
        exportCfg.imagePadding = 8
        exportCfg.baseBackgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        exportCfg.baseForegroundColor = .systemOrange
        exportCfg.cornerStyle = .capsule
        exportCfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        exportBtn.configuration = exportCfg
        exportBtn.addTarget(self, action: #selector(settingsExportConversationTapped), for: .touchUpInside)

        let actionsContentStack = UIStackView(arrangedSubviews: [cmpBtn, exportBtn])
        actionsContentStack.axis = .vertical; actionsContentStack.spacing = 10
        let actionsCard = makeSettingsCard(header: "Actions", icon: "sparkle", tint: .systemOrange, content: actionsContentStack)

        // ── 8. About Card (NEW) ─────────────────────
        let versionLbl = UILabel()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        versionLbl.text = "Version \(appVersion) (\(buildNumber))"
        versionLbl.font = UIFont.systemFont(ofSize: 14, weight: .semibold).rounded
        versionLbl.textColor = .label

        let madeWithLbl = UILabel()
        madeWithLbl.text = "Made with \u{2764}\u{FE0F} and llama.cpp"
        madeWithLbl.font = UIFont.systemFont(ofSize: 13, weight: .regular).rounded
        madeWithLbl.textColor = .secondaryLabel

        let libCountLbl = UILabel()
        libCountLbl.text = "35+ Python packages bundled"
        libCountLbl.font = UIFont.systemFont(ofSize: 12, weight: .regular).rounded
        libCountLbl.textColor = .tertiaryLabel

        let aboutContentStack = UIStackView(arrangedSubviews: [versionLbl, madeWithLbl, libCountLbl])
        aboutContentStack.axis = .vertical; aboutContentStack.spacing = 4
        let aboutCard = makeSettingsCard(header: "About", icon: "info.circle.fill", tint: .systemGray, content: aboutContentStack)

        // ── ASSEMBLY ────────────────────────────────
        let allSections = UIStackView(arrangedSubviews: [
            headerRow,
            modelCard,
            personaCard,
            genCard,
            appearCard,
            toolsCard,
            ragCard,
            actionsCard,
            aboutCard
        ])
        allSections.axis = .vertical
        allSections.spacing = 16
        allSections.translatesAutoresizingMaskIntoConstraints = false
        allSections.setCustomSpacing(20, after: headerRow)
        allSections.setCustomSpacing(24, after: actionsCard)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.addSubview(allSections)

        settingsPanel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        settingsPanel.layer.cornerRadius = WorkspaceStyle.radiusLarge
        settingsPanel.layer.cornerCurve = .continuous
        settingsPanel.layer.borderWidth = 0.5
        settingsPanel.layer.borderColor = UIColor.separator.cgColor
        settingsPanel.layer.shadowColor = UIColor.black.cgColor
        settingsPanel.layer.shadowOpacity = 0.15
        settingsPanel.layer.shadowRadius = 20
        settingsPanel.layer.shadowOffset = CGSize(width: 0, height: 8)
        settingsPanel.layer.zPosition = 5
        settingsPanel.isHidden = true
        settingsPanel.clipsToBounds = true
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false

        // Add blur behind
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = WorkspaceStyle.radiusLarge
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        settingsPanel.addSubview(blur)
        settingsPanel.addSubview(scrollView)
        contentView.addSubview(settingsPanel)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: settingsPanel.topAnchor),
            blur.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: settingsPanel.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: settingsPanel.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: settingsPanel.bottomAnchor, constant: -20),

            allSections.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            allSections.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            allSections.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            allSections.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            allSections.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    // MARK: - Settings Card Helpers

    private func makeSettingsCard(header: String, icon: String, tint: UIColor, content: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        // Header
        let iconBg = UIView()
        iconBg.backgroundColor = tint.withAlphaComponent(0.15)
        iconBg.layer.cornerRadius = 8
        iconBg.layer.cornerCurve = .continuous
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconBg.widthAnchor.constraint(equalToConstant: 28),
            iconBg.heightAnchor.constraint(equalToConstant: 28)
        ])

        let iconImg = UIImageView(image: UIImage(systemName: icon)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        iconImg.tintColor = tint
        iconImg.contentMode = .center
        iconImg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconImg)
        NSLayoutConstraint.activate([
            iconImg.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconImg.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor)
        ])

        let headerLabel = UILabel()
        headerLabel.text = header
        headerLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold).rounded
        headerLabel.textColor = .label

        let headerStack = UIStackView(arrangedSubviews: [iconBg, headerLabel])
        headerStack.axis = .horizontal; headerStack.spacing = 10; headerStack.alignment = .center

        // Separator under header
        let sep = UIView()
        sep.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

        let outerStack = UIStackView(arrangedSubviews: [headerStack, sep, content])
        outerStack.axis = .vertical
        outerStack.spacing = 12
        outerStack.setCustomSpacing(10, after: headerStack)
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.isLayoutMarginsRelativeArrangement = true
        outerStack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        container.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: container.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeStatChip(icon: String, text: String, color: UIColor) -> UIView {
        let container = UIView()
        container.backgroundColor = color.withAlphaComponent(0.1)
        container.layer.cornerRadius = 10
        container.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: icon)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
        iconView.tintColor = color
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold).rounded
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal; stack.spacing = 4; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
        ])

        return container
    }

    private func makeStatBadge(value: String, label: String, color: UIColor) -> UIView {
        let container = UIView()

        let valueLbl = UILabel()
        valueLbl.text = value
        valueLbl.font = UIFont.systemFont(ofSize: 22, weight: .bold).rounded
        valueLbl.textColor = color

        let labelLbl = UILabel()
        labelLbl.text = label
        labelLbl.font = UIFont.systemFont(ofSize: 11, weight: .medium).rounded
        labelLbl.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [valueLbl, labelLbl])
        stack.axis = .vertical; stack.spacing = 2; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    private func makeSettingsSeparator() -> UIView {
        let sep = UIView()
        sep.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return sep
    }

    private func makeLibraryChipsView() -> UIView {
        let libraries: [(String, Bool)] = pythonLibraryProbeNames.map { name in
            let state = pythonLibraryStates[name.lowercased()]
            let installed: Bool
            switch state {
            case .installed, .shim: installed = true
            default: installed = false
            }
            return (name, installed)
        }

        // Use a simple wrapping layout via nested horizontal stacks
        let wrapContainer = UIView()
        wrapContainer.translatesAutoresizingMaskIntoConstraints = false

        let flowStack = UIStackView()
        flowStack.axis = .vertical
        flowStack.spacing = 6
        flowStack.alignment = .leading
        flowStack.translatesAutoresizingMaskIntoConstraints = false

        // Create chip views
        var currentRow = UIStackView()
        currentRow.axis = .horizontal; currentRow.spacing = 6
        var rowWidth: CGFloat = 0
        let maxWidth: CGFloat = 260 // approximate max row width

        for (name, installed) in libraries {
            let chip = UIView()
            let chipColor: UIColor = installed ? .systemGreen : .systemRed
            chip.backgroundColor = chipColor.withAlphaComponent(0.12)
            chip.layer.cornerRadius = 10
            chip.layer.cornerCurve = .continuous

            let dot = UIView()
            dot.backgroundColor = chipColor
            dot.layer.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 6), dot.heightAnchor.constraint(equalToConstant: 6)])

            let lbl = UILabel()
            lbl.text = name
            lbl.font = UIFont.systemFont(ofSize: 11, weight: .semibold).rounded
            lbl.textColor = chipColor

            let chipStack = UIStackView(arrangedSubviews: [dot, lbl])
            chipStack.axis = .horizontal; chipStack.spacing = 4; chipStack.alignment = .center
            chipStack.translatesAutoresizingMaskIntoConstraints = false

            chip.addSubview(chipStack)
            NSLayoutConstraint.activate([
                chipStack.topAnchor.constraint(equalTo: chip.topAnchor, constant: 5),
                chipStack.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -5),
                chipStack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
                chipStack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8)
            ])

            let estimatedWidth = CGFloat(name.count) * 7.5 + 26
            if rowWidth + estimatedWidth > maxWidth && rowWidth > 0 {
                flowStack.addArrangedSubview(currentRow)
                currentRow = UIStackView()
                currentRow.axis = .horizontal; currentRow.spacing = 6
                rowWidth = 0
            }
            currentRow.addArrangedSubview(chip)
            rowWidth += estimatedWidth + 6
        }
        if currentRow.arrangedSubviews.count > 0 {
            flowStack.addArrangedSubview(currentRow)
        }

        wrapContainer.addSubview(flowStack)
        NSLayoutConstraint.activate([
            flowStack.topAnchor.constraint(equalTo: wrapContainer.topAnchor),
            flowStack.leadingAnchor.constraint(equalTo: wrapContainer.leadingAnchor),
            flowStack.trailingAnchor.constraint(lessThanOrEqualTo: wrapContainer.trailingAnchor),
            flowStack.bottomAnchor.constraint(equalTo: wrapContainer.bottomAnchor)
        ])

        return wrapContainer
    }

    @objc private func settingsExportConversationTapped() {
        guard conversations.indices.contains(currentConversationIndex) else { return }
        let conversation = conversations[currentConversationIndex]
        dismissSettingsPanel()
        showExportSheet(for: conversation)
    }

    private func makeSettingSectionLabel(_ title: String, icon: String, tint: UIColor) -> UIStackView {
        let img = UIImageView(image: UIImage(systemName: icon)?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        img.tintColor = tint
        img.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([img.widthAnchor.constraint(equalToConstant: 18), img.heightAnchor.constraint(equalToConstant: 18)])
        let lbl = UILabel()
        lbl.text = title
        lbl.font = UIFont.systemFont(ofSize: 11, weight: .bold).rounded
        lbl.textColor = tint
        let stack = UIStackView(arrangedSubviews: [img, lbl])
        stack.axis = .horizontal; stack.spacing = 6; stack.alignment = .center
        return stack
    }

    private func styleCard(_ view: UIView, tint: UIColor) {
        view.backgroundColor = WorkspaceStyle.glassFill
        view.layer.cornerRadius = WorkspaceStyle.radiusLarge
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = WorkspaceStyle.borderWidth
        view.layer.borderColor = WorkspaceStyle.glassStroke.cgColor
        view.layer.shadowColor = tint.withAlphaComponent(0.22).cgColor
        view.layer.shadowOpacity = Float(WorkspaceStyle.shadowOpacity)
        view.layer.shadowRadius = WorkspaceStyle.shadowRadius
        view.layer.shadowOffset = WorkspaceStyle.shadowOffset

        // Inner blur backdrop
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: WorkspaceStyle.glassBlurStyle))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.isUserInteractionEnabled = false
        blur.layer.cornerRadius = WorkspaceStyle.radiusLarge
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        view.insertSubview(blur, at: 0)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: view.topAnchor),
            blur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateComposerUI() {
        let text = inputTextView.text ?? ""
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        inputPlaceholderLabel.isHidden = hasText
        let fitting = inputTextView.sizeThatFits(CGSize(width: inputTextView.bounds.width, height: .greatestFiniteMagnitude))
        let clamped = min(180, max(52, fitting.height))
        inputHeightConstraint?.constant = clamped
        sendButton.alpha = sendButton.isEnabled ? 1.0 : 0.55
    }

    private func configureFilesManager() {
        let manager = ModelsManagerViewController()
        manager.isEmbedded = true
        manager.delegate = self
        addChild(manager)
        filesContainer.addSubview(manager.view)
        manager.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            manager.view.topAnchor.constraint(equalTo: filesContainer.topAnchor),
            manager.view.leadingAnchor.constraint(equalTo: filesContainer.leadingAnchor),
            manager.view.trailingAnchor.constraint(equalTo: filesContainer.trailingAnchor),
            manager.view.bottomAnchor.constraint(equalTo: filesContainer.bottomAnchor)
        ])
        manager.didMove(toParent: self)
        filesManagerController = manager
    }

    private func currentSlot() -> ModelSlot {
        selectedModelSlot
    }

    private func currentEffort() -> ThinkingEffort {
        ThinkingEffort(rawValue: effortSegment.selectedSegmentIndex) ?? .medium
    }

    @objc private func contentModeChanged() {
        updateContentMode()
    }

    private func updateContentMode() {
        let selected = contentModeControl.selectedSegmentIndex
        let showingEditor = selected == 0
        let showingFiles = selected == 1
        let showingDocs = selected == 2
        UIView.transition(with: contentView, duration: 0.18, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.editorContainer.isHidden = !showingEditor
            self.filesContainer.isHidden = !showingFiles
            self.docsContainer.isHidden = !showingDocs
            self.chatContainer?.isHidden = true  // Chat tab removed
        }
        if showingEditor && editorController == nil {
            setupEditorController()
        }
        if showingFiles {
            if filesBrowserController == nil {
                setupFilesBrowser()
            }
            filesBrowserController?.refresh()
        }
        if showingDocs && docsController == nil {
            setupDocsController()
        }
        settingsPanel.isHidden = true
    }

    private func setupFilesBrowser() {
        let fb = FilesBrowserViewController()
        fb.delegate = self
        addChild(fb)
        fb.view.translatesAutoresizingMaskIntoConstraints = false
        filesContainer.addSubview(fb.view)
        NSLayoutConstraint.activate([
            fb.view.topAnchor.constraint(equalTo: filesContainer.topAnchor),
            fb.view.leadingAnchor.constraint(equalTo: filesContainer.leadingAnchor),
            fb.view.trailingAnchor.constraint(equalTo: filesContainer.trailingAnchor),
            fb.view.bottomAnchor.constraint(equalTo: filesContainer.bottomAnchor),
        ])
        fb.didMove(toParent: self)
        filesBrowserController = fb
    }

    private func setupDocsController() {
        let dc = LibraryDocsViewController()
        dc.isCompactMode = false
        dc.delegate = self
        addChild(dc)
        dc.view.translatesAutoresizingMaskIntoConstraints = false
        docsContainer.addSubview(dc.view)
        NSLayoutConstraint.activate([
            dc.view.topAnchor.constraint(equalTo: docsContainer.topAnchor),
            dc.view.leadingAnchor.constraint(equalTo: docsContainer.leadingAnchor),
            dc.view.trailingAnchor.constraint(equalTo: docsContainer.trailingAnchor),
            dc.view.bottomAnchor.constraint(equalTo: docsContainer.bottomAnchor),
        ])
        dc.didMove(toParent: self)
        docsController = dc
    }

    private func setupEditorController() {
        let ec = CodeEditorViewController()
        ec.llamaRunner = runner
        addChild(ec)
        ec.view.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.addSubview(ec.view)
        NSLayoutConstraint.activate([
            ec.view.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            ec.view.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            ec.view.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            ec.view.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor)
        ])
        ec.didMove(toParent: self)
        ec.onModelSelected = { [weak self] slot in
            guard let self else { return }
            self.selectedModelSlot = slot
            self.loadModel(for: slot)
        }
        // Show currently loaded model name (or selected slot name)
        if let loaded = loadedModelSlot {
            ec.updateModelName(loaded.title)
        } else {
            ec.updateModelName(selectedModelSlot.title + " (not loaded)")
        }
        editorController = ec
    }

    private func preferredContextSize() -> Int32 {
        let memBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let memGB = memBytes / 1_073_741_824.0

        // 9B hybrid model needs smaller context to fit in 8GB
        if selectedModelSlot == .qwen35_9b {
            if memGB <= 10.0 { return 2048 }
            if memGB <= 16.0 { return 4096 }
            return 8192
        }

        if memGB <= 7.5 {
            return 4096
        } else if memGB <= 10.0 {
            return 8192
        } else if memGB <= 16.0 {
            return 16384
        } else {
            return 32768
        }
    }

    private func preferredBatchSize(for context: Int32) -> Int32 {
        return min(512, max(128, context / 8))
    }

    private func formattedFileSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func modelFileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    private func findExistingModelFile(for slot: ModelSlot) -> URL? {
        guard let modelsDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Models", isDirectory: true) else {
            return nil
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return contents.first(where: { url in
            url.pathExtension.lowercased() == "gguf"
                && url.lastPathComponent.lowercased().hasPrefix(slot.filePrefix.lowercased())
        })
    }

    private func conversationsFileURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("conversations.json")
    }

    private func loadConversations() {
        let url = conversationsFileURL()
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([Conversation].self, from: data), !decoded.isEmpty {
                conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
                currentConversationIndex = 0
                messages = conversations[0].messages
                updateSystemPrompt()
                reloadChatStack()
                return
            }
        }

        let initialConversation = Conversation(id: UUID(),
                                               title: "New chat",
                                               messages: [ChatMessage(role: .system, content: systemPromptText())],
                                               updatedAt: Date())
        conversations = [initialConversation]
        currentConversationIndex = 0
        messages = initialConversation.messages
        saveConversations()
    }

    private func saveConversations() {
        let url = conversationsFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(conversations) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func syncCurrentConversation() {
        guard conversations.indices.contains(currentConversationIndex) else { return }
        conversations[currentConversationIndex].messages = messages
        conversations[currentConversationIndex].updatedAt = Date()
        saveConversations()
    }

    private func reloadConversationList() {
        guard conversationsTable.window != nil else {
            needsConversationReload = true
            refreshFilteredConversationIndices()
            return
        }
        needsConversationReload = false
        let currentId = conversations.indices.contains(currentConversationIndex) ? conversations[currentConversationIndex].id : nil
        conversations.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        if let currentId, let current = conversations.firstIndex(where: { $0.id == currentId }) {
            currentConversationIndex = current
        } else {
            currentConversationIndex = 0
        }
        refreshFilteredConversationIndices()
        conversationsTable.reloadData()
        if let visibleRow = filteredConversationIndices.firstIndex(of: currentConversationIndex) {
            let indexPath = IndexPath(row: visibleRow, section: 0)
            conversationsTable.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else {
            conversationsTable.indexPathsForSelectedRows?.forEach {
                conversationsTable.deselectRow(at: $0, animated: false)
            }
        }
    }

    private func refreshFilteredConversationIndices() {
        let query = conversationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredConversationIndices = Array(conversations.indices)
        } else {
            filteredConversationIndices = conversations.indices.filter { idx in
                let conversation = conversations[idx]
                if conversation.title.lowercased().contains(query) {
                    return true
                }
                if conversation.messages.contains(where: { message in
                    message.role != .system && message.content.lowercased().contains(query)
                }) {
                    return true
                }
                return false
            }
        }
        conversationEmptyLabel.isHidden = !filteredConversationIndices.isEmpty
    }

    private func selectConversation(at index: Int) {
        guard conversations.indices.contains(index) else { return }
        if isGenerating {
            return
        }
        syncCurrentConversation()
        currentConversationIndex = index
        messages = conversations[index].messages
        updateSystemPrompt()
        reloadChatStack()
        if let visibleRow = filteredConversationIndices.firstIndex(of: index) {
            conversationsTable.selectRow(at: IndexPath(row: visibleRow, section: 0), animated: true, scrollPosition: .none)
        }
    }

    private func reloadChatStack() {
        chatStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                addUserMessage(message.content, shouldScroll: false)
            case .assistant:
                addAssistantMessage(message.content, shouldScroll: false)
            case .system:
                break
            }
        }
        scrollChatToBottom()
    }

    private func loadSavedModelPaths() {
        let defaults = UserDefaults.standard
        for slot in ModelSlot.allCases {
            if let path = defaults.string(forKey: slot.storageKey) {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    modelURLs[slot] = url
                    continue
                }
                defaults.removeObject(forKey: slot.storageKey)
                if let saved = modelURLs[slot], saved == url {
                    modelURLs.removeValue(forKey: slot)
                }
            }
            if let discovered = findExistingModelFile(for: slot) {
                modelURLs[slot] = discovered
                defaults.set(discovered.path, forKey: slot.storageKey)
            }
        }
    }

    private func loadToolSettings() {
        let defaults = UserDefaults.standard
        if let autoLoadEnabled = defaults.object(forKey: autoLoadModelDefaultsKey) as? Bool {
            autoLoadToggle.isOn = autoLoadEnabled
        } else {
            autoLoadToggle.isOn = true
        }
        if let pythonEnabled = defaults.object(forKey: pythonToolEnabledDefaultsKey) as? Bool {
            pythonToolsEnabled = pythonEnabled
            pythonToolsToggle.isOn = pythonEnabled
        } else {
            pythonToolsEnabled = true
            pythonToolsToggle.isOn = true
        }
    }

    private func applyLastModelSelection() {
        let defaults = UserDefaults.standard
        if let lastPath = defaults.string(forKey: lastModelPathDefaultsKey) {
            let lower = lastPath.lowercased()
            if lower.contains("nemotron")
                || lower.contains("llama-3.1")
                || lower.contains("llama3")
                || (lower.contains("deepseek") && (lower.contains("8b") || lower.contains("qwen3-8b") || lower.contains("llama-8b"))) {
                defaults.removeObject(forKey: lastModelSlotDefaultsKey)
                defaults.removeObject(forKey: lastModelPathDefaultsKey)
            }
        }
        if let rawSlot = defaults.object(forKey: lastModelSlotDefaultsKey) as? Int,
           let slot = ModelSlot(rawValue: rawSlot) {
            selectedModelSlot = slot
        }
        if let lastPath = defaults.string(forKey: lastModelPathDefaultsKey),
           let slot = ModelSlot(rawValue: selectedModelSlot.rawValue) {
            let url = URL(fileURLWithPath: lastPath)
            if FileManager.default.fileExists(atPath: url.path) {
                modelURLs[slot] = url
            }
        }
        updateModelSelectorUI()
    }

    private func autoLoadLastModelIfNeeded() {
        guard !autoLoadAttempted, autoLoadToggle.isOn else { return }
        autoLoadAttempted = true
        let slot = currentSlot()
        guard let url = modelURLs[slot], FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        loadModel(at: url, slot: slot, completion: nil)
    }

    private func updateModelUI() {
        let slot = currentSlot()
        if let url = modelURLs[slot] {
            modelPathLabel.text = "Model: \(url.lastPathComponent)"
        } else {
            modelPathLabel.text = "Model: not set"
        }
    }

    private func updateModelSelectorUI() {
        if #available(iOS 15.0, *) {
            var config = modelSelectButton.configuration ?? UIButton.Configuration.filled()
            config.title = selectedModelSlot.title
            config.image = UIImage(systemName: "chevron.down")
            config.imagePlacement = .trailing
            config.imagePadding = 6
            config.baseBackgroundColor = UIColor(white: 1.0, alpha: 0.55)
            config.baseForegroundColor = WorkspaceStyle.accent
            config.cornerStyle = .capsule
            config.background.strokeColor = WorkspaceStyle.glassStroke
            config.background.strokeWidth = 0.5
            modelSelectButton.configuration = config
        } else {
            modelSelectButton.setTitle(selectedModelSlot.title, for: .normal)
        }
        modelSelectButton.menu = makeModelMenu()
    }

    private func makeModelMenu() -> UIMenu {
        let actions = ModelSlot.allCases.map { slot in
            UIAction(title: slot.title, state: slot == selectedModelSlot ? .on : .off) { [weak self] _ in
                self?.selectModel(slot)
            }
        }
        return UIMenu(title: "Select model", children: actions)
    }

    private func selectModel(_ slot: ModelSlot) {
        selectedModelSlot = slot
        UserDefaults.standard.set(slot.rawValue, forKey: lastModelSlotDefaultsKey)
        updateModelSelectorUI()
        updateModelUI()
    }

    private func updateStatus(_ text: String) {
        statusLabel.text = text
        let lower = text.lowercased()
        if lower.contains("failed") || lower.contains("error") {
            statusLabel.textColor = UIColor.systemRed
            modelStateBadgeLabel.text = "  Error  "
            modelStateBadgeLabel.textColor = UIColor.white
            modelStateBadgeLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
        } else if lower.contains("loading") || lower.contains("downloading") || lower.contains("generating") {
            statusLabel.textColor = UIColor.systemOrange
            modelStateBadgeLabel.text = "  Busy  "
            modelStateBadgeLabel.textColor = UIColor.white
            modelStateBadgeLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.75)
        } else if lower.contains("ready") || lower.contains("loaded") {
            statusLabel.textColor = UIColor.systemGreen
            modelStateBadgeLabel.text = "  Ready  "
            modelStateBadgeLabel.textColor = UIColor.white
            modelStateBadgeLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.75)
        } else {
            statusLabel.textColor = WorkspaceStyle.mutedText
            modelStateBadgeLabel.text = "  Idle  "
            modelStateBadgeLabel.textColor = WorkspaceStyle.accent
            modelStateBadgeLabel.backgroundColor = WorkspaceStyle.accent.withAlphaComponent(0.10)
        }
    }

    private func updateMaxTokensLabel() {
        let formatted = tokenFormatter.string(from: NSNumber(value: maxOutputTokens)) ?? "\(maxOutputTokens)"
        maxTokensLabel.text = "Max output tokens (capped by context): \(formatted)"
    }

    private func updateSystemPrompt() {
        let prompt = systemPromptText()
        if messages.isEmpty || messages[0].role != .system {
            messages.insert(ChatMessage(role: .system, content: prompt), at: 0)
        } else {
            messages[0].content = prompt
        }
        syncCurrentConversation()
    }

    private func systemPromptText() -> String {
        let effort = currentEffort()
        let thinkingInstruction: String
        if showThinking {
            thinkingInstruction = """
Respond with a <think>...</think> block containing your full reasoning, then provide the final answer wrapped in <answer>...</answer>.
Do not include any text outside the <answer> block.
If the user input is a greeting or very short, keep <think> to one short sentence and answer briefly.
"""
        } else {
            thinkingInstruction = "Provide only the final answer."
        }
        let toolInstruction: String
        if pythonToolsEnabled {
            toolInstruction = """
IMPORTANT: You have a local Python runtime. When asked to calculate, compute, graph, or code:
- DO NOT describe what you would do. DO NOT explain the code first.
- IMMEDIATELY output a ```python code block with COMPLETE runnable code.
- The code WILL be executed automatically and the output shown to the user.
- Your message must contain ONLY the code block, nothing else before or after it.

For calculations:
```python
import math
result = math.sqrt(144)
print(f"Square root of 144 = {result}")
```

For graphs/charts, use matplotlib.pyplot (it works on this device):
```python
import numpy as np
import matplotlib.pyplot as plt

# Example: y = f(x) curve
x = np.linspace(-5, 5, 200)
y = np.where(x != 0, 1.0/x, np.nan)
plt.plot(x, y, label='y=1/x')
plt.title('y = 1/x')
plt.xlabel('x')
plt.ylabel('y')
plt.grid(True)
plt.legend()
plt.show()
```

CRITICAL GRAPHING RULES:
1. x and y arrays in plt.plot(x, y) MUST have the SAME length.
2. For y=f(x): use ONE linspace for x, compute y from x. Both have same length.
3. For implicit equations like x²+y²=1, use PARAMETRIC form:
```python
t = np.linspace(0, 2*np.pi, 200)
x = np.cos(t)
y = np.sin(t)
plt.plot(x, y)
plt.axis('equal')
plt.show()
```
4. For 2D heatmaps/contours, ALWAYS use meshgrid:
```python
x = np.linspace(-2, 2, 100)
y = np.linspace(-2, 2, 100)
X, Y = np.meshgrid(x, y)  # REQUIRED for 2D
Z = X**2 + Y**2
plt.contour(X, Y, Z, levels=[1])
plt.axis('equal')
plt.show()
```
5. NEVER do arithmetic between arrays of different lengths.
6. NEVER use numpy arrays in if/and/or. Use np.where() instead:
   BAD:  if arr > 0:  or  mask = (a > 0) and (b < 1)
   GOOD: mask = (a > 0) & (b < 1)  then  result = arr[mask]
   GOOD: y = np.where(condition, value_if_true, value_if_false)
7. For piecewise/conditional: ALWAYS use np.where or boolean indexing:
```python
x = np.linspace(-2, 2, 200)
y = np.where(x >= 0, np.sqrt(x), np.nan)  # sqrt only for x>=0
```
8. For implicit curves like x²+y³=1, prefer PARAMETRIC or CONTOUR:
```python
# Contour approach (works for ANY implicit equation):
x = np.linspace(-2, 2, 300)
y = np.linspace(-2, 2, 300)
X, Y = np.meshgrid(x, y)
plt.contour(X, Y, X**2 + Y**3, levels=[1])
plt.show()
```

9. For 3D surfaces like x²+y²+z²=1, use PARAMETRIC with plot_surface:
```python
fig = plt.figure()
ax = fig.add_subplot(111, projection='3d')
u = np.linspace(0, 2*np.pi, 50)
v = np.linspace(0, np.pi, 50)
X = np.outer(np.cos(u), np.sin(v))
Y = np.outer(np.sin(u), np.sin(v))
Z = np.outer(np.ones_like(u), np.cos(v))
ax.plot_surface(X, Y, Z, cmap='viridis', alpha=0.8)
plt.title('Unit Sphere')
plt.show()
```

More examples:
- Bar: plt.bar(categories, values)
- Scatter: plt.scatter(x, y)
- Histogram: plt.hist(data, bins=20)
- Multiple: call plt.plot() multiple times before plt.show()
- Subplots: fig, ax = plt.subplots(); ax.plot(x, y)
- 3D scatter: ax.scatter3D(x, y, z, c=z, cmap='plasma')
- 3D wireframe: ax.plot_wireframe(X, Y, Z)

For calculations (ALWAYS use print() to output results):
- Big numbers: print(2**100), print(math.factorial(100))
- Fractions: from fractions import Fraction; print(Fraction(1,3) + Fraction(1,6))
- Matrix: A = np.array([[1,2],[3,4]]); print(np.linalg.inv(A)); print(np.linalg.det(A)); print(np.linalg.eig(A))
- Solve linear Ax=b: print(np.linalg.solve(A, b))
- Polynomial roots: print(np.roots([1, 0, -1]))  # x²-1=0
- Numerical ODE (Euler method): loop with y += f(x,y)*dx, no scipy needed
- Numerical integration (trapezoidal): np.trapz(y, x)
- Statistics: np.mean(x), np.std(x), np.median(x), np.percentile(x, 95)

Rules:
- ALWAYS use print() to show computed results. Without print(), the user sees nothing.
- For graphs: use matplotlib.pyplot with plt.show() at the end.
AVAILABLE TOOLS & LIBRARIES:

═══ PYTHON (all installed, all working) ═══
numpy, scipy, sympy, sklearn (scikit-learn 1.8), matplotlib, plotly, networkx, PIL (Pillow), bs4, yaml, jsonschema, click, tqdm, rich, pygments, svgelements, isosurfaces, mapbox_earcut, pathops, pycairo, manimpango, av (PyAV), audioop, pydub, mpmath, math, cmath, fractions, decimal, statistics, itertools, collections, functools.
NOT installed: pandas, tensorflow, torch, opencv, seaborn.

Quick reference for key libraries:

scipy: optimize (minimize, curve_fit, root, minimize_scalar, linprog), integrate (quad, dblquad, odeint, solve_ivp), stats (norm, t, chi2, binom, poisson, pearsonr, spearmanr, ttest_ind, ttest_1samp, ks_2samp, describe), interpolate (interp1d, CubicSpline, griddata, splrep, splev), linalg (solve, inv, det, eig, svd, lu, cholesky, qr), fft (rfft, rfftfreq, fft, ifft), signal (butter, filtfilt, find_peaks, welch, savgol_filter, spectrogram), spatial (ConvexHull, Voronoi, Delaunay, cKDTree, distance), sparse (csr_matrix, csc_matrix, eye, diags), sparse.linalg (spsolve, eigs, svds), cluster.hierarchy (linkage, fcluster, dendrogram), ndimage (gaussian_filter, label, binary_dilation), special (gamma, erf, beta, comb, factorial)

sympy: symbols, solve, diff, integrate, sin, cos, exp, log, pi, oo, series, limit, Matrix, simplify, factor, expand, Eq, sqrt, Rational, Sum, Product, FiniteSet, Interval, latex, pprint, lambdify, Piecewise, DiracDelta, Heaviside

sklearn modules (all importable with full API):
  datasets: make_classification, make_regression, make_blobs, make_moons, make_circles, make_swiss_roll, make_s_curve, make_friedman1/2/3, load_iris, load_digits, load_wine, load_breast_cancer, load_diabetes
  model_selection: train_test_split, cross_val_score, cross_validate, KFold, StratifiedKFold, LeaveOneOut, TimeSeriesSplit, GridSearchCV, RandomizedSearchCV, learning_curve, validation_curve
  preprocessing: StandardScaler, MinMaxScaler, RobustScaler, MaxAbsScaler, Normalizer, Binarizer, LabelEncoder, OneHotEncoder, OrdinalEncoder, LabelBinarizer, PolynomialFeatures, PowerTransformer, QuantileTransformer, KBinsDiscretizer, FunctionTransformer, SplineTransformer, TargetEncoder
  feature_extraction: CountVectorizer, TfidfVectorizer, DictVectorizer, TfidfTransformer
  feature_selection: SelectKBest, SelectPercentile, VarianceThreshold
  ensemble: RandomForestClassifier/Regressor, GradientBoostingClassifier/Regressor, HistGradientBoostingClassifier/Regressor, AdaBoostClassifier/Regressor, BaggingClassifier/Regressor, ExtraTreesClassifier/Regressor, IsolationForest, VotingClassifier/Regressor, StackingClassifier/Regressor
  linear_model: LinearRegression, LogisticRegression, Ridge, Lasso, ElasticNet, SGDClassifier/Regressor, RidgeClassifier, Perceptron, BayesianRidge, ARDRegression, HuberRegressor, Lars, LassoLars, PoissonRegressor, GammaRegressor
  tree: DecisionTreeClassifier/Regressor, ExtraTreeClassifier/Regressor
  svm: SVC, SVR, LinearSVC, LinearSVR, NuSVC, NuSVR, OneClassSVM
  neighbors: KNeighborsClassifier/Regressor, RadiusNeighborsClassifier/Regressor, NearestNeighbors, NearestCentroid, LocalOutlierFactor, KernelDensity
  cluster: KMeans, MiniBatchKMeans, DBSCAN, AgglomerativeClustering, SpectralClustering, MeanShift, OPTICS, Birch, AffinityPropagation, BisectingKMeans, HDBSCAN, FeatureAgglomeration
  decomposition: PCA, TruncatedSVD, NMF, FastICA, KernelPCA, IncrementalPCA, LatentDirichletAllocation, SparsePCA, FactorAnalysis, DictionaryLearning
  manifold: TSNE, MDS, Isomap, LocallyLinearEmbedding, SpectralEmbedding
  naive_bayes: GaussianNB, MultinomialNB, BernoulliNB
  neural_network: MLPClassifier, MLPRegressor
  gaussian_process: GaussianProcessClassifier, GaussianProcessRegressor
  discriminant_analysis: LinearDiscriminantAnalysis, QuadraticDiscriminantAnalysis
  mixture: GaussianMixture, BayesianGaussianMixture
  metrics: accuracy_score, confusion_matrix, classification_report, r2_score, roc_auc_score, roc_curve, log_loss, precision_recall_curve, f1_score, precision_score, recall_score, balanced_accuracy_score, matthews_corrcoef, cohen_kappa_score, silhouette_score, calinski_harabasz_score, davies_bouldin_score, pairwise_distances, adjusted_rand_score, mean_squared_error, mean_absolute_error
  pipeline: Pipeline, make_pipeline
  compose: ColumnTransformer
  impute: SimpleImputer, KNNImputer
  inspection: permutation_importance, partial_dependence
  calibration: CalibratedClassifierCV

matplotlib 3D:
```python
fig = plt.figure()
ax = fig.add_subplot(111, projection='3d')
ax.plot_surface(X, Y, Z, cmap='viridis')  # or ax.scatter3D, ax.plot_wireframe
plt.show()
```
plt.cm.viridis/plasma/jet/etc. are callable colormaps: color = plt.cm.plasma(0.5)
All matplotlib modules available: cm, colors, patches, ticker, animation, gridspec, widgets, dates, etc.

networkx: import networkx as nx; G = nx.erdos_renyi_graph(20, 0.3); nx.shortest_path(G, 0, 5); nx.pagerank(G); nx.betweenness_centrality(G); nx.community.greedy_modularity_communities(G)

═══ C INTERPRETER (C89/C99/C23, native, local) ═══
When asked to write/run C code, output a ```c code block. It auto-executes.
Supports: int, long long, float, double, char, arrays (1D/2D), structs, unions, enums, real pointers, pointer arithmetic, #define (object & function-like macros), #ifdef/#ifndef/#endif, #warning, typedef, printf (with width/padding/format specifiers), scanf, malloc/free, math.h, string.h, stdlib.h, switch/case, for/while/do-while, functions, recursion, bitwise ops, compound assignments, goto/labels, static variables, function pointers, compound literals, designated initializers, _Static_assert, _Generic, typeof, auto type inference, constexpr, binary literals (0b1010), digit separators (1'000), [[attributes]].

═══ C++ INTERPRETER (C++17, native, local) ═══
When asked to write/run C++ code, output a ```cpp code block. It auto-executes.
Supports: classes (fields, methods, constructors/destructors), inheritance, access specifiers, new/delete, references, this, operator overloading, namespaces, using namespace std, std::cout/cin, std::string/vector/map/pair/set, std::sort/find/count/min_element/max_element, auto, range-for, lambdas, basic templates, try/catch/throw, static_cast/dynamic_cast.

═══ FORTRAN INTERPRETER (Fortran 90/95/2003, native, local) ═══
When asked to write/run Fortran code, output a ```fortran code block. It auto-executes.
Supports: PROGRAM/END PROGRAM, INTEGER/REAL/DOUBLE PRECISION/CHARACTER/LOGICAL/COMPLEX, DO/DO WHILE/EXIT/CYCLE, IF/THEN/ELSE IF/ELSE/END IF, SELECT CASE, SUBROUTINE/FUNCTION/MODULE, arrays up to 7D, ALLOCATABLE/ALLOCATE/DEALLOCATE, WRITE/PRINT with format descriptors (A/Iw/Fw.d/Ew.d/Lw), 45+ intrinsics (SIN/COS/SQRT/ABS/MOD/MATMUL/DOT_PRODUCT/SUM/PRODUCT/MAXVAL/MINVAL/TRANSPOSE/RESHAPE/SIZE/SHAPE/TRIM/LEN_TRIM/INDEX/ADJUSTL/ADJUSTR), case-insensitive, dot-operators (.AND./.OR./.NOT./.EQ./.NE./.LT./.GT./.LE./.GE.).

═══ MANIM (math animations) ═══
manim IS available. Use Cairo renderer (auto-configured). Output is a PNG image of the last frame.
IMPORTANT: Do NOT use Tex() or MathTex() — LaTeX is not available on iOS. Use Text() for all text.

```python
from manim import *

class MyScene(Scene):
    def construct(self):
        circle = Circle(color=BLUE)
        square = Square(color=RED)
        self.play(Create(circle))
        self.play(Transform(circle, square))
        self.play(FadeOut(circle))

scene = MyScene()
scene.render()
```

Available mobjects: Circle, Square, Rectangle, Triangle, Arrow, Line, Dot, Arc, Annulus, Polygon, RegularPolygon, Star, Text (NOT Tex), NumberPlane, Axes, BarChart, Graph, VGroup, VMobject, etc.
Available animations: Create, FadeIn, FadeOut, Transform, ReplacementTransform, Write, GrowFromCenter, GrowArrow, Rotate, MoveToTarget, ApplyMethod, Indicate, Flash, ShowPassingFlash, AnimationGroup, Succession, LaggedStart, etc.
Available: UP, DOWN, LEFT, RIGHT, ORIGIN, PI, TAU, RED, BLUE, GREEN, YELLOW, WHITE, etc.

═══ RULES ═══
- ALWAYS use print()/printf() to show results.
- For graphs: use matplotlib.pyplot with plt.show() at the end.
- For animations: use manim Scene with scene.render() at the end.
- Write COMPLETE runnable code. Never just import libraries.
"""
        } else {
            toolInstruction = """
You can use local tools when needed.
Tool call format (exact, no markdown code fences):
<tool_call>{"tool":"latex","content":"<latex expression or block>"}</tool_call>
Compatible alternative (also accepted):
<tool_call>{"name":"latex","arguments":{"content":"<latex expression or block>"}}</tool_call>
Rules:
- Emit only one tool_call block in a message.
- If you emit a tool_call, output only the tool_call block and nothing else.
- Python tool is disabled in settings; do not emit python tool calls.
- Use latex to format equations for display in the chat.
- If you call a tool, provide a valid JSON object inside <tool_call>...</tool_call>.
- If no tool is needed, answer directly in the normal answer format.
"""
        }
        let activePrompt = SystemPromptPresetsManager.shared.activePrompt
        let formatInstruction = """
Output format rules:
- Use standard Markdown for formatting: **bold**, *italic*, `code`, ```code blocks```, headings (#), lists (- or 1.), > blockquotes.
- NEVER output raw HTML tags (<div>, <span>, <p>, <br>, <b>, <i>, <pre>, <code>, <html>, <ul>, <li>, etc.).
- NEVER output raw LaTeX markup tags (<latex>, <minipage>, \\textbf{}, \\texttt{}, etc.) outside of tool_call blocks.
- NEVER wrap content in <ex> tags.
- For math/equations, use standard $...$ or $$...$$ notation, or use the latex tool.
"""
        return "\(activePrompt)\n\(effort.instruction)\n\(formatInstruction)\n\(thinkingInstruction)\n\(toolInstruction)"
    }

    private func pythonLibraryGuidanceText() -> String {
        let knownLibraries: [(name: String, label: String)] = [
            ("numpy", "numpy"),
            ("matplotlib", "matplotlib"),
            ("scipy", "scipy"),
            ("sklearn", "scikit-learn (sklearn)"),
            ("sympy", "sympy"),
            ("plotly", "plotly"),
            ("networkx", "networkx"),
            ("PIL", "Pillow (PIL)"),
            ("bs4", "BeautifulSoup (bs4)"),
            ("yaml", "PyYAML"),
            ("rich", "rich"),
            ("tqdm", "tqdm"),
            ("manim", "manim")
        ]

        var available: [String] = []
        var unavailable: [String] = []

        for entry in knownLibraries {
            let state = pythonLibraryStates[entry.name]
            switch state {
            case .installed?:
                available.append(entry.label)
            case .shim?:
                available.append("\(entry.label) (compatibility layer)")
            case .missing?, .error?:
                unavailable.append(entry.label)
            case nil:
                // Safe defaults before runtime probing completes.
                if entry.name == "numpy" || entry.name == "matplotlib" {
                    available.append("\(entry.label) (compatibility layer)")
                } else {
                    unavailable.append(entry.label)
                }
            }
        }

        let availableText = available.isEmpty ? "none" : available.joined(separator: ", ")
        let unavailableText = unavailable.isEmpty ? "none" : unavailable.joined(separator: ", ")
        return "- available: \(availableText)\n- unavailable: \(unavailableText)"
    }


    private func resetGenerationBuffers() {
        streamBuffer = ""
        isInThinkSection = false
        isInAnswerSection = false
        isInToolCallSection = false
        sawAnswerTag = false
        inlineThinkingText = ""
        thinkingStartTime = nil
        hasThinkSummary = false
        isSummarizingThinking = false
        reasoningTruncated = false
        fullOutputBuffer = ""
        resetStreamingBuffers()
    }

    private func appendFinalText(_ text: String) {
        guard !text.isEmpty else { return }
        if currentAssistantLabel == nil {
            stopTypingIndicator()
            startAssistantMessage(placeholder: "…")
        }
        if let index = currentAssistantIndex, index < messages.count {
            messages[index].content.append(text)
        }
        appendAssistantText(text)
    }

    private func appendThinkingText(_ text: String) {
        guard !text.isEmpty else { return }
        hasThinkSummary = true
        // Start inline thinking bubble if not started
        if thinkingBubbleRow == nil {
            startInlineThinking()
        }
        appendInlineThinkingText(text)
    }

    private enum StreamTagKind {
        case thinkOpen
        case thinkClose
        case answerOpen
        case answerClose
        case toolCallOpen
        case toolCallClose
        case control
    }

    private func nextTagMatch(in text: String) -> (Range<String.Index>, StreamTagKind)? {
        var bestRange: Range<String.Index>?
        var bestKind: StreamTagKind?

        func consider(_ range: Range<String.Index>, _ kind: StreamTagKind) {
            guard let current = bestRange else {
                bestRange = range
                bestKind = kind
                return
            }
            if range.lowerBound < current.lowerBound {
                bestRange = range
                bestKind = kind
            }
        }

        for tag in thinkOpenTags {
            if let range = text.range(of: tag, options: .caseInsensitive) {
                consider(range, .thinkOpen)
            }
        }
        for tag in thinkCloseTags {
            if let range = text.range(of: tag, options: .caseInsensitive) {
                consider(range, .thinkClose)
            }
        }
        for tag in answerOpenTags {
            if let range = text.range(of: tag, options: .caseInsensitive) {
                consider(range, .answerOpen)
            }
        }
        for tag in answerCloseTags {
            if let range = text.range(of: tag, options: .caseInsensitive) {
                consider(range, .answerClose)
            }
        }
        for tag in toolCallOpenTags {
            if let range = text.range(of: tag, options: .caseInsensitive) {
                consider(range, .toolCallOpen)
            }
        }
        for tag in toolCallCloseTags {
            if let range = text.range(of: tag, options: .caseInsensitive) {
                consider(range, .toolCallClose)
            }
        }
        for token in controlTokens {
            if let range = text.range(of: token, options: .caseInsensitive) {
                consider(range, .control)
            }
        }

        guard let range = bestRange, let kind = bestKind else {
            return nil
        }
        return (range, kind)
    }

    private func appendStreamText(_ text: String) {
        guard !text.isEmpty else { return }
        if isInToolCallSection {
            return
        }
        if isInThinkSection {
            if showThinking {
                appendThinkingText(text)
            }
            return
        }
        if sawAnswerTag && !isInAnswerSection {
            return
        }
        appendFinalText(text)
    }

    private func resetAssistantOutputForAnswerTag() {
        guard let assistantIndex = currentAssistantIndex, assistantIndex < messages.count else { return }
        messages[assistantIndex].content = ""
        currentAssistantLabel?.text = ""
    }

    private func handleStreamTag(_ kind: StreamTagKind) {
        switch kind {
        case .thinkOpen:
            isInThinkSection = true
        case .thinkClose:
            isInThinkSection = false
        case .answerOpen:
            if !sawAnswerTag {
                sawAnswerTag = true
                resetAssistantOutputForAnswerTag()
            }
            isInThinkSection = false
            isInAnswerSection = true
        case .answerClose:
            sawAnswerTag = true
            isInThinkSection = false
            isInAnswerSection = false
        case .toolCallOpen:
            isInToolCallSection = true
        case .toolCallClose:
            isInToolCallSection = false
        case .control:
            break
        }
    }

    private func processStreamBuffer() {
        while true {
            guard let match = nextTagMatch(in: streamBuffer) else {
                flushStreamTail()
                break
            }

            let chunk = String(streamBuffer[..<match.0.lowerBound])
            appendStreamText(chunk)
            streamBuffer = String(streamBuffer[match.0.upperBound...])
            handleStreamTag(match.1)
        }
    }

    private func flushStreamTail() {
        guard streamBuffer.count > maxTagTail else { return }
        let cutIndex = streamBuffer.index(streamBuffer.endIndex, offsetBy: -maxTagTail)
        let chunk = String(streamBuffer[..<cutIndex])
        streamBuffer = String(streamBuffer[cutIndex...])
        appendStreamText(chunk)
    }

    private func flushRemainingStream() {
        appendStreamText(streamBuffer)
        streamBuffer = ""
    }

    private func generateThinkingSummary(question: String, answer: String) {
        guard !isSummarizingThinking else { return }
        isSummarizingThinking = true

        let summaryMessages = [
            ChatMessage(role: .system, content: "Summarize the reasoning at a high level in 3-5 bullet points. Do not reveal chain-of-thought. Keep it concise."),
            ChatMessage(role: .user, content: "Question: \(question)\nAnswer: \(answer)")
        ]

        updateStatus("Generating reasoning summary...")
        runner.generate(messages: summaryMessages, maxTokens: 256, onToken: { [weak self] token in
            self?.appendThinkingText(token)
        }, completion: { [weak self] result in
            guard let self else { return }
            self.isSummarizingThinking = false
            switch result {
            case .success:
                self.updateStatus("Ready.")
            case .failure(let error):
                self.updateStatus("Summary failed: \(error.localizedDescription)")
            }
        })
    }

    private func enqueueUserMessage(_ text: String) {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        addUserMessage(text)
        if conversations.indices.contains(currentConversationIndex),
           conversations[currentConversationIndex].title == "New chat" {
            conversations[currentConversationIndex].title = String(text.prefix(48))
        }
        syncCurrentConversation()
        reloadConversationList()
    }

    // MARK: - Auto-Compact Context

    /// Rough token estimate: ~4 chars per token for English
    private func estimateTokenCount(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + ($1.content.count / 4) + 4 } // +4 for role/template overhead per message
    }

    /// Auto-compact conversation if it's approaching the context limit.
    /// Keeps: system prompt + a summary of old messages + last N recent messages.
    private func autoCompactIfNeeded() {
        let contextSize = Int(preferredContextSize())
        let threshold = contextSize * 3 / 4  // compact at 75% usage
        let estimated = estimateTokenCount(messages)

        guard estimated > threshold else { return }

        print("[compact] Context ~\(estimated) tokens exceeds \(threshold) threshold (ctx=\(contextSize)). Compacting...")

        // Keep system prompt (index 0)
        guard messages.count > 4, messages[0].role == .system else { return }

        // Keep the last 4 messages (2 user + 2 assistant turns)
        let keepRecent = 4
        let recentStart = max(1, messages.count - keepRecent)
        let recentMessages = Array(messages[recentStart...])
        let oldMessages = Array(messages[1..<recentStart])

        guard !oldMessages.isEmpty else { return }

        // Build a summary of old messages
        var summaryParts: [String] = []
        for msg in oldMessages {
            let role = msg.role == .user ? "User" : "Assistant"
            // Keep first 150 chars of each message
            let preview = String(msg.content.prefix(150))
            let truncated = msg.content.count > 150 ? "..." : ""
            summaryParts.append("[\(role)] \(preview)\(truncated)")
        }

        let summaryText = """
        [Context compacted — \(oldMessages.count) earlier messages summarized]
        \(summaryParts.joined(separator: "\n"))
        [End of summary — recent messages follow]
        """

        // Rebuild messages: system + summary + recent
        let compactedSummary = ChatMessage(role: .assistant, content: summaryText)
        messages = [messages[0], compactedSummary] + recentMessages

        let newEstimate = estimateTokenCount(messages)
        print("[compact] Compacted: \(oldMessages.count) old messages → summary. \(estimated) → \(newEstimate) tokens (\(messages.count) messages)")

        // Update UI
        syncCurrentConversation()
        updateStatus("Context compacted (\(estimated)→\(newEstimate) tokens)")
    }

    private func startGeneration(userText: String) {
        // Auto-compact if conversation is too long for context
        autoCompactIfNeeded()

        // Feature 14: Background task
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }

        // Feature 11: RAG context injection
        if RAGEngine.shared.isEnabled {
            let ragChunks = RAGEngine.shared.query(userText, topK: 3)
            if !ragChunks.isEmpty {
                let ragContext = ragChunks.joined(separator: "\n---\n")
                let injection = "\n\nRelevant context from user's documents:\n---\n\(ragContext)\n---\nUse this context to inform your answer if relevant."
                if !messages.isEmpty, messages[0].role == .system {
                    messages[0].content += injection
                }
            }
        }

        // Feature 15: Image generation prompt augmentation
        if ImageGenerationService.detectImageRequest(userText) {
            if !messages.isEmpty, messages[0].role == .system {
                messages[0].content += "\n\n" + ImageGenerationService.imagePromptAugmentation()
            }
        }

        // Feature 8: Reset token stats label
        tokenStatsLabel.text = ""
        tokenStatsLabel.isHidden = true

        updateSystemPrompt()
        resetGenerationBuffers()
        // Inline thinking resets
        stopInlineThinking()
        thinkingPillRow?.removeFromSuperview()
        thinkingPillRow = nil
        settingsPanel.isHidden = true

        let assistantIndex = messages.count
        messages.append(ChatMessage(role: .assistant, content: ""))
        currentAssistantIndex = assistantIndex
        currentAssistantLabel = nil
        startTypingIndicator()

        isGenerating = true
        setGenerationEnabled(false)
        updateStatus("Generating...")
        activityIndicator.startAnimating()

        let stopSequences = showThinking ? answerCloseTags : []
        runner.generate(messages: messages, maxTokens: maxOutputTokens, grammar: nil, stopSequences: stopSequences, onToken: { [weak self] token in
            guard let self else { return }
            self.fullOutputBuffer.append(token)
            self.pendingStreamTokens.append(token)
            if self.currentAssistantLabel == nil || self.typingRow != nil {
                self.needsAssistantStart = true
            }
            self.scheduleFlush()
        }, completion: { [weak self] result in
            guard let self else { return }
            self.isGenerating = false
            self.stopTypingIndicator()
            self.cancelFlushTimer()
            self.flushPendingTokens(force: true)
            self.currentAssistantIndex = nil
            switch result {
            case .success(let generatedOutput):
                if self.fullOutputBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !generatedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.fullOutputBuffer = generatedOutput
                }
                var resolvedAssistantText = ""
                if self.showThinking, let parsed = self.parseThinkSections(from: self.fullOutputBuffer) {
                    let thinkText = self.stripThinkTags(from: parsed.think)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !thinkText.isEmpty {
                        self.hasThinkSummary = true
                    }
                    let finalText = self.stripThinkTags(from: parsed.final)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalText.isEmpty {
                        resolvedAssistantText = finalText
                    } else if assistantIndex < self.messages.count,
                              self.messages[assistantIndex].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let fallback = self.stripThinkTags(from: self.fullOutputBuffer)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if thinkText.isEmpty, !fallback.isEmpty, !self.sawAnswerTag {
                            resolvedAssistantText = fallback
                        }
                    }
                } else {
                    resolvedAssistantText = self.stripThinkTags(from: self.fullOutputBuffer)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                resolvedAssistantText = self.sanitizeToolCallText(resolvedAssistantText)
                if self.isToolOnlyPlaceholderText(resolvedAssistantText) {
                    resolvedAssistantText = ""
                }

                let toolCall = self.extractToolCall(from: self.fullOutputBuffer)

                // If there's a tool call, execute it on a background thread to avoid blocking UI
                if let toolCall {
                    self.updateStatus("Running \(toolCall.tool)...")
                    self.appendToolStatusToThinking("Running \(toolCall.tool.capitalized)...")
                    let lang = toolCall.tool == "c" ? "c" : "python"

                    // ── Execute tool with auto-fix retry loop (up to 3 attempts) ──
                    self.executeToolWithRetry(
                        toolCall: toolCall, lang: lang, assistantIndex: assistantIndex,
                        attempt: 1, maxAttempts: 3, previousCode: toolCall.payload
                    )
                    if self.showThinking && self.thinkingBubbleRow != nil {
                        self.stopInlineThinking()
                    }
                    return // the retry method handles everything including finishToolCleanup
                }

                var toolCallRequest: ToolCallRequest? = nil
                var toolFormattedOutput: String? = nil

                var didSetAssistantText = false
                func commitAssistantText(_ text: String) {
                    self.setAssistantFinalText(text, assistantIndex: assistantIndex)
                    didSetAssistantText = true
                }

                if !resolvedAssistantText.isEmpty {
                    if let toolFormattedOutput, !toolFormattedOutput.isEmpty {
                        let combined = "\(resolvedAssistantText)\n\n\(toolFormattedOutput)"
                        commitAssistantText(combined)
                    } else {
                        commitAssistantText(resolvedAssistantText)
                    }
                } else if let toolFormattedOutput, !toolFormattedOutput.isEmpty {
                    if let toolCallRequest {
                        let toolOnly = self.toolOnlyAssistantText(for: toolCallRequest, formattedOutput: toolFormattedOutput)
                        commitAssistantText(toolOnly.isEmpty ? toolFormattedOutput : toolOnly)
                    } else {
                        commitAssistantText(toolFormattedOutput)
                    }
                } else {
                    let plainFallback = self.sanitizeToolCallText(
                        self.stripThinkTags(from: self.fullOutputBuffer)
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !plainFallback.isEmpty {
                        commitAssistantText(plainFallback)
                    }
                }

                if !didSetAssistantText {
                    let rawFallback = self.stripThinkTags(from: self.fullOutputBuffer)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rawFallback.isEmpty {
                        commitAssistantText(rawFallback)
                    }
                }

                if !didSetAssistantText {
                    commitAssistantText("Model returned an empty response. Try again.")
                }

                if assistantIndex < self.messages.count {
                    let existing = self.messages[assistantIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleaned = self.sanitizeToolCallText(existing)
                    if !cleaned.isEmpty, cleaned != existing {
                        self.setAssistantFinalText(cleaned, assistantIndex: assistantIndex)
                    }
                }

                if assistantIndex < self.messages.count {
                    let answerText = self.messages[assistantIndex].content
                    self.applyLatexRenderingIfNeeded(for: answerText, bubble: self.currentAssistantBubble)
                }
                // Finalize inline thinking
                if self.showThinking && self.thinkingBubbleRow != nil {
                    self.stopInlineThinking()
                }
                self.currentAssistantLabel = nil
                self.currentAssistantBubble = nil
                self.currentAssistantRow = nil
                self.activityIndicator.stopAnimating()
                self.setGenerationEnabled(true)
                self.updateStatus("Ready.")
                HapticService.shared.success()
                // Feature 9: Reset auto-scroll
                self.userPausedAutoScroll = false
                self.scrollToBottomButton.isHidden = true
            case .failure(let error):
                self.activityIndicator.stopAnimating()
                self.setGenerationEnabled(true)
                self.updateStatus("Generation failed: \(error.localizedDescription)")
                HapticService.shared.error()
                self.userPausedAutoScroll = false
                self.scrollToBottomButton.isHidden = true
            }
            // Feature 14: End background task
            if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
            self.tokenStatsLabel.isHidden = true
            self.syncCurrentConversation()
            self.reloadConversationList()
        })
    }

    private func scheduleFlush() {
        guard flushTimer == nil else { return }
        let timer = Timer(timeInterval: flushInterval, target: self, selector: #selector(handleFlushTimer), userInfo: nil, repeats: false)
        flushTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resetStreamingBuffers() {
        pendingStreamTokens = ""
        needsAssistantStart = false
        cancelFlushTimer()
    }

    private func cancelFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    @objc private func handleFlushTimer() {
        flushTimer = nil
        flushPendingTokens()
    }

    private func flushPendingTokens(force: Bool = false) {
        guard !pendingStreamTokens.isEmpty || force else { return }
        if needsAssistantStart {
            stopTypingIndicator()
            if currentAssistantLabel == nil {
                startAssistantMessage(placeholder: "…")
            }
            needsAssistantStart = false
        }

        let chunk = pendingStreamTokens
        pendingStreamTokens = ""

        if !chunk.isEmpty {
            streamBuffer.append(chunk)
            processStreamBuffer()
        }

        if force {
            flushRemainingStream()
        }

        // Feature 8: Update token stats during generation
        if isGenerating {
            let stats = runner.currentStats
            let tps = stats.tokensPerSecond
            if tps > 0 {
                tokenStatsLabel.text = String(format: "%.1f tok/s • %d tokens", tps, stats.generatedTokenCount)
                tokenStatsLabel.isHidden = false
            }
        }

        if shouldAutoScroll() {
            scrollChatToBottom()
        }

        if !pendingStreamTokens.isEmpty {
            scheduleFlush()
        }
    }

    private func shouldAutoScroll() -> Bool {
        return !userPausedAutoScroll && !chatScrollView.isDragging && !chatScrollView.isDecelerating
    }

    private func addUserMessage(_ text: String, shouldScroll: Bool = true) {
        let bubble = makeBubble(text: text, isUser: true, renderLatex: false)
        let row = makeBubbleRow(bubble: bubble.view, isUser: true)
        chatStack.addArrangedSubview(row)
        if shouldScroll {
            scrollChatToBottom()
        }
    }

    private func addAssistantMessage(_ text: String, shouldScroll: Bool = true) {
        // Extract chart path marker if present: <!-- chart:/path/to/file.html -->
        var chartPath: String?
        var displayText = text
        if let range = text.range(of: "<!-- chart:") {
            let afterMarker = text[range.upperBound...]
            if let endRange = afterMarker.range(of: " -->") {
                chartPath = String(afterMarker[..<endRange.lowerBound])
                // Remove the marker from display text
                displayText = text.replacingCharacters(in: range.lowerBound..<endRange.upperBound, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let cleaned = stripJunkTags(from: displayText)
        let bubble = makeBubble(text: cleaned, isUser: false, renderLatex: shouldRenderLatex(for: cleaned))
        // Render stored assistant messages with markdown + tag cleanup
        let rendered = MarkdownRenderer.render(cleaned, textColor: .label)
        bubble.label.attributedText = rendered

        // Re-attach chart/image if the file still exists
        if let path = chartPath, FileManager.default.fileExists(atPath: path) {
            attachToolImage(path: path, to: bubble)
        }

        let row = makeBubbleRow(bubble: bubble.view, isUser: false)
        chatStack.addArrangedSubview(row)
        if shouldScroll {
            scrollChatToBottom()
        }
    }

    private func startAssistantMessage(placeholder: String? = nil) {
        let bubble = makeBubble(text: placeholder ?? "", isUser: false, renderLatex: false)
        let row = makeBubbleRow(bubble: bubble.view, isUser: false)
        chatStack.addArrangedSubview(row)
        currentAssistantLabel = bubble.label
        currentAssistantBubble = bubble
        currentAssistantRow = row
        if shouldAutoScroll() {
            scrollChatToBottom()
        }
    }

    private var rawAssistantStreamBuffer = ""

    private func appendAssistantText(_ text: String) {
        guard let label = currentAssistantLabel else { return }
        if label.text == "…" {
            rawAssistantStreamBuffer = ""
            label.text = ""
        }
        rawAssistantStreamBuffer += text
        // Use plain text during streaming for performance — markdown renders on completion
        label.text = rawAssistantStreamBuffer
    }

    private func shouldRenderLatex(for text: String) -> Bool {
        let pattern = "(\\$\\$.*?\\$\\$)|(\\$[^\\$\\n]+\\$)|(\\\\\\[.*?\\\\\\])|(\\\\\\(.*?\\\\\\))|(\\\\begin\\{.*?\\})"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: (text as NSString).length)
        if regex?.firstMatch(in: text, options: [], range: range) != nil {
            return true
        }
        let lower = text.lowercased()
        return lower.contains("\\frac")
            || lower.contains("\\sqrt")
            || lower.contains("\\sum")
            || lower.contains("\\int")
            || lower.contains("\\alpha")
    }

    private func parseThinkSections(from text: String) -> (think: String, final: String)? {
        guard let thinkOpen = findFirstTag(in: text, tags: thinkOpenTags, range: nil) else {
            return nil
        }
        let searchRange = thinkOpen.upperBound..<text.endIndex
        let thinkClose = findFirstTag(in: text, tags: thinkCloseTags, range: searchRange)
        let answerOpen = findFirstTag(in: text, tags: answerOpenTags, range: searchRange)

        if let answerOpen, thinkClose == nil || answerOpen.lowerBound < thinkClose!.lowerBound {
            let thinkText = String(text[thinkOpen.upperBound..<answerOpen.lowerBound])
            let finalText = extractAnswerText(from: text, answerOpen: answerOpen)
            return (think: thinkText, final: finalText)
        }

        if let thinkClose {
            let thinkText = String(text[thinkOpen.upperBound..<thinkClose.lowerBound])
            if let answerOpenAfter = findFirstTag(in: text, tags: answerOpenTags, range: thinkClose.upperBound..<text.endIndex) {
                let finalText = extractAnswerText(from: text, answerOpen: answerOpenAfter)
                return (think: thinkText, final: finalText)
            }
            let finalText = String(text[thinkClose.upperBound...])
            return (think: thinkText, final: finalText)
        }

        let thinkText = String(text[thinkOpen.upperBound...])
        return (think: thinkText, final: "")
    }

    private func extractAnswerText(from text: String, answerOpen: Range<String.Index>) -> String {
        let rangeAfter = answerOpen.upperBound..<text.endIndex
        if let answerClose = findFirstTag(in: text, tags: answerCloseTags, range: rangeAfter) {
            return String(text[answerOpen.upperBound..<answerClose.lowerBound])
        }
        return String(text[answerOpen.upperBound...])
    }

    private func findFirstTag(in text: String, tags: [String], range: Range<String.Index>?) -> Range<String.Index>? {
        let searchRange = range ?? text.startIndex..<text.endIndex
        var bestRange: Range<String.Index>?
        for tag in tags {
            if let found = text.range(of: tag, options: .caseInsensitive, range: searchRange) {
                if let best = bestRange {
                    if found.lowerBound < best.lowerBound {
                        bestRange = found
                    }
                } else {
                    bestRange = found
                }
            }
        }
        return bestRange
    }

    private func stripThinkTags(from text: String) -> String {
        let tags = thinkOpenTags + thinkCloseTags + answerOpenTags + answerCloseTags + toolCallOpenTags + toolCallCloseTags + controlTokens
        return removingTags(from: removeToolCallBlocks(from: text), tags: tags)
    }

    private func removingTags(from text: String, tags: [String]) -> String {
        var result = text
        for tag in tags {
            while let range = result.range(of: tag, options: .caseInsensitive) {
                result.removeSubrange(range)
            }
        }
        return result
    }

    private struct ToolCallRequest {
        let tool: String
        let payload: String
    }

    private struct ToolExecutionResult {
        let text: String
        let imagePath: String?

        init(text: String, imagePath: String? = nil) {
            self.text = text
            self.imagePath = imagePath
        }

        init(text: String) {
            self.text = text
            self.imagePath = nil
        }
    }

    private func normalizedToolName(_ name: String?) -> String? {
        guard let name else { return nil }
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "python", "python3", "py", "code_interpreter", "matplotlib", "plot", "chart":
            return "python"
        case "c", "c99", "c89", "c11", "gcc", "clang":
            return "c"
        case "latex", "tex", "katex":
            return "latex"
        default:
            if lowered.contains("python") || lowered.contains("interpreter") || lowered.contains("code") {
                return "python"
            }
            if lowered.contains("latex") || lowered.contains("katex") || lowered == "math" {
                return "latex"
            }
            return nil
        }
    }

    private func inferToolName(from dict: [String: Any], function: [String: Any]?) -> String? {
        if let functionName = function?["name"] as? String, let normalized = normalizedToolName(functionName) {
            return normalized
        }
        if dict["code"] != nil || dict["script"] != nil {
            return "python"
        }
        if dict["latex"] != nil || dict["tex"] != nil || dict["content"] != nil {
            return "latex"
        }
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let lower = text.lowercased()
        if lower.contains("python") || lower.contains("\"code\"") || lower.contains("\"script\"") || lower.contains("matplotlib") {
            return "python"
        }
        if lower.contains("latex") || lower.contains("katex") || lower.contains("\"tex\"") {
            return "latex"
        }
        return nil
    }

    private func stripCodeFence(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count >= 6 else {
            return trimmed
        }
        trimmed.removeFirst(3)
        trimmed.removeLast(3)
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            let firstLine = trimmed[..<firstNewline].lowercased()
            if firstLine == "python" || firstLine == "py" || firstLine == "json" || firstLine == "latex" {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmed
    }

    private func extractPayload(from object: Any, tool: String) -> String? {
        func firstString(keys: [String], in dict: [String: Any]) -> String? {
            for key in keys {
                if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            return nil
        }

        if let dict = object as? [String: Any] {
            let directKeys: [String]
            if tool == "python" {
                directKeys = ["code", "input", "script", "expression", "query"]
            } else {
                directKeys = ["content", "input", "latex", "tex", "expression"]
            }

            if let direct = firstString(keys: directKeys, in: dict) {
                return direct
            }

            let nestedCandidates = [dict["arguments"], dict["args"], dict["parameters"]]
            for candidate in nestedCandidates {
                if let candidate, let payload = extractPayload(from: candidate, tool: tool) {
                    return payload
                }
            }

            if let function = dict["function"] as? [String: Any] {
                if let payload = extractPayload(from: function, tool: tool) {
                    return payload
                }
            }
            return nil
        }

        if let raw = object as? String {
            let stripped = stripCodeFence(from: raw)
            guard !stripped.isEmpty else { return nil }
            if let data = stripped.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data),
               let payload = extractPayload(from: parsed, tool: tool) {
                return payload
            }
            return stripped
        }

        if let array = object as? [Any] {
            for entry in array {
                if let payload = extractPayload(from: entry, tool: tool) {
                    return payload
                }
            }
        }

        return nil
    }

    private func parseToolCall(fromJSONObject object: Any) -> ToolCallRequest? {
        if let array = object as? [Any] {
            for entry in array {
                if let request = parseToolCall(fromJSONObject: entry) {
                    return request
                }
            }
            return nil
        }

        guard let dict = object as? [String: Any] else {
            return nil
        }

        let function = dict["function"] as? [String: Any]
        let rawToolName = dict["tool"] as? String
            ?? dict["name"] as? String
            ?? function?["name"] as? String

        guard let tool = normalizedToolName(rawToolName) ?? inferToolName(from: dict, function: function) else {
            return nil
        }

        let payload = extractPayload(from: dict, tool: tool)
            ?? extractPayload(from: function as Any, tool: tool)
            ?? ""
        return ToolCallRequest(tool: tool, payload: payload)
    }

    private func parseToolCallFromJSON(_ raw: String) -> ToolCallRequest? {
        let stripped = stripCodeFence(from: raw)
        var candidates: [String] = [stripped]
        if let firstBrace = stripped.firstIndex(of: "{"), let lastBrace = stripped.lastIndex(of: "}") {
            candidates.append(String(stripped[firstBrace...lastBrace]))
        }
        if let firstBracket = stripped.firstIndex(of: "["), let lastBracket = stripped.lastIndex(of: "]") {
            candidates.append(String(stripped[firstBracket...lastBracket]))
        }

        var seen = Set<String>()
        for candidate in candidates where !candidate.isEmpty {
            if seen.contains(candidate) {
                continue
            }
            seen.insert(candidate)
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            if let request = parseToolCall(fromJSONObject: object) {
                return request
            }
        }
        return nil
    }

    private func likelyToolCallSnippets(in text: String) -> [String] {
        var snippets: [String] = []

        if let regex = try? NSRegularExpression(pattern: "```(?:json|tool_call|tool|python|latex)?\\s*([\\s\\S]*?)```", options: [.caseInsensitive]) {
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, options: [], range: range)
            for match in matches where match.numberOfRanges > 1 {
                let capture = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = capture.lowercased()
                if (lower.contains("\"tool\"") || lower.contains("\"name\"") || lower.contains("\"function\""))
                    && (lower.contains("python") || lower.contains("latex") || lower.contains("katex") || lower.contains("\"py\"") || lower.contains("\"tex\"")) {
                    snippets.append(capture)
                }
            }
        }

        let characters = Array(text)
        var startIndex: Int?
        var depth = 0
        var inString = false
        var escaped = false

        for index in characters.indices {
            let ch = characters[index]
            if startIndex == nil {
                if ch == "{" {
                    startIndex = index
                    depth = 1
                    inString = false
                    escaped = false
                }
                continue
            }

            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }

            if ch == "\"" {
                inString = true
                continue
            }
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start = startIndex {
                    let snippet = String(characters[start...index])
                    let lower = snippet.lowercased()
                    if (lower.contains("\"tool\"") || lower.contains("\"name\"") || lower.contains("\"function\""))
                        && (lower.contains("python") || lower.contains("latex") || lower.contains("katex") || lower.contains("\"py\"") || lower.contains("\"tex\"")) {
                        snippets.append(snippet)
                    }
                    self.resetSnippetScanState(startIndex: &startIndex, depth: &depth, inString: &inString, escaped: &escaped)
                }
            }

            if let start = startIndex, index - start > 32000 {
                self.resetSnippetScanState(startIndex: &startIndex, depth: &depth, inString: &inString, escaped: &escaped)
            }
        }

        var seen = Set<String>()
        var unique: [String] = []
        for snippet in snippets where !snippet.isEmpty {
            if seen.insert(snippet).inserted {
                unique.append(snippet)
            }
        }
        return unique
    }

    private func resetSnippetScanState(startIndex: inout Int?, depth: inout Int, inString: inout Bool, escaped: inout Bool) {
        startIndex = nil
        depth = 0
        inString = false
        escaped = false
    }

    private func parseSimpleToolCallLine(from text: String) -> ToolCallRequest? {
        guard let regex = try? NSRegularExpression(pattern: "(?im)^\\s*(python3|python|py|matplotlib|plot|chart|latex|tex|katex)\\s*:\\s*(.+)$", options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 2 else {
            return nil
        }
        let rawName = nsText.substring(with: match.range(at: 1))
        let payload = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tool = normalizedToolName(rawName), !payload.isEmpty else { return nil }
        return ToolCallRequest(tool: tool, payload: payload)
    }

    /// Fallback: detect ```python code blocks in model output and treat as tool call
    private func parsePythonCodeBlock(from text: String) -> ToolCallRequest? {
        guard pythonToolsEnabled else { return nil }
        // Match ```python\n...\n``` or ```py\n...\n```
        let patterns = [
            "```python\\s*\\n([\\s\\S]*?)```",
            "```py\\s*\\n([\\s\\S]*?)```"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 {
                let code = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty && code.count > 5 {
                    // Only treat as tool call if it looks executable (has print, import, =, etc.)
                    let lower = code.lowercased()
                    let looksExecutable = lower.contains("print") || lower.contains("import") || lower.contains("=")
                        || lower.contains("for ") || lower.contains("def ") || lower.contains("plt.")
                        || lower.contains("range(") || lower.contains("math.")
                    if looksExecutable {
                        return ToolCallRequest(tool: "python", payload: code)
                    }
                }
            }
        }
        // Also detect ```c code blocks
        let cPatterns = ["```c\\s*\\n([\\s\\S]*?)```"]
        for pattern in cPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 {
                let code = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty && code.count > 5 {
                    let lower = code.lowercased()
                    let looksExecutable = lower.contains("printf") || lower.contains("int main")
                        || lower.contains("#include") || lower.contains("return")
                        || lower.contains("scanf") || lower.contains("for (")
                        || lower.contains("while (")
                    if looksExecutable {
                        return ToolCallRequest(tool: "c", payload: code)
                    }
                }
            }
        }
        return nil
    }

    private func parseLoosePythonToolCall(from text: String) -> ToolCallRequest? {
        let lower = text.lowercased()
        guard lower.contains("python")
                || lower.contains("matplotlib")
                || lower.contains("\"code\"")
                || lower.contains("\"script\"")
                || lower.contains("\"input\"") else {
            return nil
        }

        let keys = ["code", "script", "input", "expression", "query"]
        for key in keys {
            if let value = extractLooseJSONValue(for: key, in: text),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ToolCallRequest(tool: "python", payload: value)
            }
        }

        if let simple = parseSimpleToolCallLine(from: text), simple.tool == "python" {
            return simple
        }
        return nil
    }

    private func extractLooseJSONValue(for key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\"\(key)\"", options: [.caseInsensitive]) else {
            return nil
        }
        guard let colon = text.range(of: ":", range: keyRange.upperBound..<text.endIndex)?.lowerBound else {
            return nil
        }

        var index = text.index(after: colon)
        while index < text.endIndex,
              String(text[index]).rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            index = text.index(after: index)
        }
        guard index < text.endIndex else {
            return nil
        }

        if text[index] == "\"" {
            var cursor = text.index(after: index)
            var escaped = false
            var raw = ""
            while cursor < text.endIndex {
                let ch = text[cursor]
                if escaped {
                    raw.append(ch)
                    escaped = false
                    cursor = text.index(after: cursor)
                    continue
                }
                if ch == "\\" {
                    escaped = true
                    cursor = text.index(after: cursor)
                    continue
                }
                if ch == "\"" {
                    return decodeLooseJSONString(raw)
                }
                raw.append(ch)
                cursor = text.index(after: cursor)
            }
            // Malformed JSON from smaller models: keep what we recovered.
            return decodeLooseJSONString(raw)
        }

        let tail = text[index...]
        let terminators = ["\n", "}", "]", ","]
        var end = tail.endIndex
        for token in terminators {
            if let range = tail.range(of: token), range.lowerBound < end {
                end = range.lowerBound
            }
        }
        let value = String(tail[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func decodeLooseJSONString(_ raw: String) -> String {
        var value = raw
        let replacements: [(String, String)] = [
            ("\\\\", "\\"),
            ("\\n", "\n"),
            ("\\r", "\r"),
            ("\\t", "\t"),
            ("\\\"", "\"")
        ]
        for (escaped, unescaped) in replacements {
            value = value.replacingOccurrences(of: escaped, with: unescaped)
        }
        return value
    }

    private func parseToolCallFromSnippets(_ text: String) -> ToolCallRequest? {
        for snippet in likelyToolCallSnippets(in: text) {
            if let request = parseToolCallFromJSON(snippet) {
                return request
            }
        }
        if let loose = parseLoosePythonToolCall(from: text) {
            return loose
        }
        if let request = parseFunctionArgsToolCall(from: text) {
            return request
        }
        return nil
    }

    private func parseFunctionArgsToolCall(from text: String) -> ToolCallRequest? {
        guard let regex = try? NSRegularExpression(
            pattern: "(?is)FUNCTION\\s*[:\u{FF1A}]\\s*([^\\n\\r]+).*?ARGS\\s*[:\u{FF1A}]\\s*(.*?)(?:RESULT\\s*[:\u{FF1A}]|RETURN\\s*[:\u{FF1A}]|$)",
            options: []
        ) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 2 else {
            return nil
        }
        let rawName = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tool = normalizedToolName(rawName) else {
            return nil
        }
        let rawArgs = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawArgs.isEmpty else { return nil }

        if let data = rawArgs.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let payload = extractPayload(from: object, tool: tool),
           !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolCallRequest(tool: tool, payload: payload)
        }

        return ToolCallRequest(tool: tool, payload: rawArgs)
    }

    private func sanitizeToolCallText(_ text: String) -> String {
        var output = removeToolCallBlocks(from: text)
        output = stripJunkTags(from: output)
        for snippet in likelyToolCallSnippets(in: output) {
            while let range = output.range(of: snippet) {
                output.removeSubrange(range)
            }
        }
        let cleanedLines = output
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed != "{" && trimmed != "}" && trimmed != "[" && trimmed != "]"
            }
        return cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips raw markup tags the model sometimes emits: <latex>, <ex>, <code>, <html>, etc.
    /// Keeps the inner content — only the tag wrappers are removed.
    private func stripJunkTags(from text: String) -> String {
        // Tags whose content should be KEPT (just strip the wrapper tags)
        let keepContentTags = ["latex", "ex", "code", "html", "pre", "p", "br", "div", "span",
                               "b", "i", "u", "em", "strong", "h1", "h2", "h3", "h4",
                               "ul", "ol", "li", "blockquote", "minipage", "textbf", "texttt"]
        var output = text
        for tag in keepContentTags {
            // Remove opening tags (with optional attributes): <tag ...>
            if let regex = try? NSRegularExpression(pattern: "<\(tag)(\\s[^>]*)?>", options: .caseInsensitive) {
                output = regex.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "")
            }
            // Remove closing tags: </tag>
            output = output.replacingOccurrences(of: "</\(tag)>", with: "", options: .caseInsensitive)
        }
        // Strip escaped newlines \n that show up as literal text
        output = output.replacingOccurrences(of: "\\n", with: "\n")
        // Collapse excessive whitespace
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return output
    }

    private func extractToolCall(from text: String) -> ToolCallRequest? {
        guard let open = findFirstTag(in: text, tags: toolCallOpenTags, range: nil) else {
            return parseToolCallFromSnippets(text)
                ?? parseToolCallFromJSON(text)
                ?? parseFunctionArgsToolCall(from: text)
                ?? parseLoosePythonToolCall(from: text)
                ?? parseSimpleToolCallLine(from: text)
                ?? parsePythonCodeBlock(from: text)
        }
        let raw: String
        if let close = findFirstTag(in: text, tags: toolCallCloseTags, range: open.upperBound..<text.endIndex) {
            raw = String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Some models stop mid-tool block; still try to recover a call from remaining text.
            raw = String(text[open.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !raw.isEmpty else { return nil }

        if let request = parseToolCallFromJSON(raw) {
            return request
        }
        if let request = parseToolCallFromSnippets(raw) {
            return request
        }
        if let request = parseLoosePythonToolCall(from: raw) {
            return request
        }

        // Fallback: allow "<tool_call>python: ...</tool_call>".
        if let split = raw.firstIndex(of: ":") {
            let tool = normalizedToolName(String(raw[..<split]))
            let payload = raw[raw.index(after: split)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let tool {
                return ToolCallRequest(tool: tool, payload: String(payload))
            }
        }
        return parseSimpleToolCallLine(from: raw)
    }

    private func removeToolCallBlocks(from text: String) -> String {
        var output = text
        var removed = true
        while removed {
            removed = false
            for openTag in toolCallOpenTags {
                guard let open = output.range(of: openTag, options: .caseInsensitive) else {
                    continue
                }
                guard let close = findFirstTag(in: output, tags: toolCallCloseTags, range: open.upperBound..<output.endIndex) else {
                    continue
                }
                output.removeSubrange(open.lowerBound..<close.upperBound)
                removed = true
                break
            }
        }
        return output
    }

    /// Execute a tool call with automatic error detection and retry (up to maxAttempts).
    /// All intermediate status (running, errors, fixes) goes into the thinking section.
    /// Only the final clean result is shown to the user.
    private func executeToolWithRetry(
        toolCall: ToolCallRequest, lang: String, assistantIndex: Int,
        attempt: Int, maxAttempts: Int, previousCode: String
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let toolOutput = self.executeToolCall(toolCall)
            let toolImagePath = toolOutput.imagePath
            let hasPlot = toolImagePath != nil
            let cleanOutput = toolOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasError = cleanOutput.contains("Traceback") || cleanOutput.contains("Error:") || cleanOutput.contains("stderr:")

            DispatchQueue.main.async {
                if hasError && attempt < maxAttempts {
                    // ── Error: fix and retry, all inside thinking ──
                    self.appendToolStatusToThinking("Attempt \(attempt) failed, fixing... (\(attempt)/\(maxAttempts))")
                    self.appendToolErrorToThinking(String(cleanOutput.prefix(300)))

                    // Include original code + error in fix prompt so model has full context
                    let fixPrompt: String
                    if attempt == 1 {
                        fixPrompt = "The \(lang) code had an error:\n```\(lang)\n\(toolCall.payload)\n```\nError:\n```\n\(String(cleanOutput.prefix(500)))\n```\nAnalyze the error carefully. Fix the code so it runs without errors. Output ONLY a corrected ```\(lang) code block."
                    } else {
                        fixPrompt = "The fixed \(lang) code still has an error:\n```\n\(String(cleanOutput.prefix(500)))\n```\nThe previous code was:\n```\(lang)\n\(toolCall.payload.prefix(400))\n```\nWrite a completely different approach if needed. Output ONLY a corrected ```\(lang) code block."
                    }

                    self.messages.append(ChatMessage(role: .user, content: fixPrompt))
                    self.messages.append(ChatMessage(role: .assistant, content: ""))
                    let retryMsgIndex = self.messages.count - 1
                    self.fullOutputBuffer = ""
                    self.updateStatus("Fixing code (attempt \(attempt + 1))...")

                    self.runner.generate(messages: self.messages, maxTokens: 1024, onToken: { [weak self] token in
                        self?.fullOutputBuffer.append(token)
                    }, completion: { [weak self] result in
                        guard let self else { return }
                        DispatchQueue.main.async {
                            let retryText: String
                            switch result {
                            case .success(let t): retryText = t
                            case .failure: retryText = ""
                            }
                            if let retryCall = self.parsePythonCodeBlock(from: retryText) ?? self.extractToolCall(from: retryText) {
                                // Check if the "fix" is actually different code
                                let newCode = retryCall.payload.trimmingCharacters(in: .whitespacesAndNewlines)
                                let oldCode = previousCode.trimmingCharacters(in: .whitespacesAndNewlines)
                                if newCode == oldCode {
                                    // Model generated the same code — don't retry, show error
                                    self.appendToolStatusToThinking("Model generated same code, stopping retry.")
                                    self.setAssistantFinalText("The code could not be fixed automatically. See thinking for details.", assistantIndex: retryMsgIndex)
                                    self.finishToolCleanup()
                                    return
                                }
                                self.appendToolStatusToThinking("Re-running fixed code...")
                                // Recurse with the new code
                                self.executeToolWithRetry(
                                    toolCall: retryCall, lang: lang, assistantIndex: retryMsgIndex,
                                    attempt: attempt + 1, maxAttempts: maxAttempts, previousCode: newCode
                                )
                            } else {
                                // Model didn't produce code — show what we have
                                self.appendToolStatusToThinking("Model could not produce fixed code.")
                                let display = self.stripJunkTags(from: self.stripThinkTags(from: retryText)).trimmingCharacters(in: .whitespacesAndNewlines)
                                self.setAssistantFinalText(display.isEmpty ? "Code execution failed. See thinking for error details." : display, assistantIndex: retryMsgIndex)
                                self.finishToolCleanup()
                            }
                        }
                    })
                } else if hasError {
                    // ── Max retries exhausted ──
                    self.appendToolStatusToThinking("All \(maxAttempts) attempts failed.")
                    self.appendToolErrorToThinking(String(cleanOutput.prefix(300)))
                    self.setAssistantFinalText("The code could not run successfully after \(maxAttempts) attempts. Expand thinking to see details.", assistantIndex: assistantIndex)
                    self.finishToolCleanup()
                } else {
                    // ── Success! Show clean result ──
                    self.appendToolStatusToThinking("Done ✓")
                    if let imgPath = toolImagePath, let bubble = self.currentAssistantBubble {
                        self.attachToolImage(path: imgPath, to: bubble)
                    }
                    let formattedOutput = self.formatPythonOutput(cleanOutput)
                    // Store code + result in history
                    if assistantIndex < self.messages.count {
                        let codeBlock = "```\(lang)\n\(toolCall.payload)\n```"
                        var fullMsg = formattedOutput.isEmpty ? codeBlock : "\(codeBlock)\n\n\(formattedOutput)"
                        if let imgPath = toolImagePath {
                            fullMsg += "\n<!-- chart:\(imgPath) -->"
                        }
                        self.messages[assistantIndex].content = fullMsg
                    }
                    let displayText = formattedOutput.isEmpty ? "Done." : formattedOutput
                    self.setAssistantFinalText(displayText, assistantIndex: assistantIndex)
                    self.applyLatexRenderingIfNeeded(for: displayText, bubble: self.currentAssistantBubble)
                    self.finishToolCleanup()
                }
            }
        }
    }

    private func executeToolCall(_ request: ToolCallRequest) -> ToolExecutionResult {
        switch request.tool {
        case "python":
            guard pythonToolsEnabled else {
                return ToolExecutionResult(text: "Python tool is disabled in Settings.")
            }
            return executePythonTool(request.payload)
        case "c":
            return executeCTool(request.payload)
        case "latex":
            return executeLatexTool(request.payload)
        default:
            return ToolExecutionResult(text: "Unsupported tool: \(request.tool)")
        }
    }

    private func executeCTool(_ code: String) -> ToolExecutionResult {
        print("[c] Executing C code (\(code.count) chars)")
        let result = CRuntime.shared.execute(code)
        if !result.success {
            let errMsg = result.error ?? "Unknown error"
            print("[c] Error: \(errMsg)")
            return ToolExecutionResult(text: "stderr:\n\(errMsg)\n\(result.output)")
        }
        print("[c] Output: \(result.output.prefix(200))")
        return ToolExecutionResult(text: result.output)
    }

    private func formattedToolResult(_ request: ToolCallRequest, output: ToolExecutionResult) -> String {
        let cleaned = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return ""
        }
        let clipped: String
        if cleaned.count > maxToolOutputChars {
            let end = cleaned.index(cleaned.startIndex, offsetBy: maxToolOutputChars)
            clipped = String(cleaned[..<end]) + "\n\n(output truncated)"
        } else {
            clipped = cleaned
        }
        if request.tool == "latex" {
            return clipped
        }
        return clipped
    }

    private func toolOnlyAssistantText(for request: ToolCallRequest, formattedOutput: String) -> String {
        _ = request
        return formattedOutput
    }

    private func executePythonTool(_ code: String) -> ToolExecutionResult {
        guard pythonToolsEnabled else {
            return ToolExecutionResult(text: "Python tool is disabled in Settings.")
        }
        var trimmed = stripCodeFence(from: code)
        // Unescape literal \n, \t, \\ from JSON tool_call payloads
        trimmed = trimmed.replacingOccurrences(of: "\\n", with: "\n")
        trimmed = trimmed.replacingOccurrences(of: "\\t", with: "\t")
        trimmed = trimmed.replacingOccurrences(of: "\\\\", with: "\\")
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolExecutionResult(text: "Python tool error: empty code.")
        }
        print("[python] Executing code (\(trimmed.count) chars):\n\(trimmed.prefix(300))")
        let startTime = Date()
        let result = PythonRuntime.shared.execute(code: trimmed)
        let elapsed = Date().timeIntervalSince(startTime)
        print("[python] Execution completed in \(String(format: "%.2f", elapsed))s, output: \(result.output.prefix(200))")
        let cleanedText = sanitizePythonToolOutput(result.output)
        return ToolExecutionResult(text: cleanedText, imagePath: result.imagePath)
    }

    private func executeLatexTool(_ content: String) -> ToolExecutionResult {
        let trimmed = stripCodeFence(from: content)
        guard !trimmed.isEmpty else {
            return ToolExecutionResult(text: "LaTeX tool error: empty content.")
        }
        if trimmed.contains("$$") || trimmed.contains("\\(") || trimmed.contains("\\[") {
            return ToolExecutionResult(text: trimmed)
        }
        return ToolExecutionResult(text: "$$\(trimmed)$$")
    }

    private func evaluateSimpleMath(from text: String) -> String? {
        var expressionText = text
        if text.hasPrefix("print("), text.hasSuffix(")") {
            let start = text.index(text.startIndex, offsetBy: 6)
            let end = text.index(before: text.endIndex)
            expressionText = String(text[start..<end])
        }
        let allowed = CharacterSet(charactersIn: "0123456789+-*/().,% \t\n")
        guard expressionText.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        let expression = NSExpression(format: expressionText)
        guard let value = expression.expressionValue(with: nil, context: nil) else {
            return nil
        }
        if let number = value as? NSNumber {
            if floor(number.doubleValue) == number.doubleValue {
                return String(Int(number.doubleValue))
            }
            return String(number.doubleValue)
        }
        return "\(value)"
    }

    private func evaluateSimpleStats(from text: String) -> String? {
        guard let listRange = text.range(of: "\\[[-0-9.,\\s]+\\]", options: .regularExpression) else {
            return nil
        }
        let rawList = String(text[listRange]).dropFirst().dropLast()
        let numbers = rawList
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard !numbers.isEmpty else { return nil }

        let lower = text.lowercased()
        if lower.contains("mean") || lower.contains("avg") {
            let mean = numbers.reduce(0, +) / Double(numbers.count)
            return "mean = \(mean)"
        }
        if lower.contains("sum") {
            return "sum = \(numbers.reduce(0, +))"
        }
        if lower.contains("min") {
            return "min = \(numbers.min() ?? 0)"
        }
        if lower.contains("max") {
            return "max = \(numbers.max() ?? 0)"
        }
        if lower.contains("median") {
            let sorted = numbers.sorted()
            let mid = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
            return "median = \(median)"
        }
        return nil
    }

    private func sanitizePythonToolOutput(_ text: String) -> String {
        if text.isEmpty {
            return text
        }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line == "plt.show()" { return false }
                if line.hasPrefix("[plot saved]") { return false }
                if line == "Using built-in numpy compatibility layer." { return false }
                if line == "Using built-in matplotlib compatibility layer." { return false }
                return true
            }
        return lines.joined(separator: "\n")
    }

    private func unsupportedPythonLibraries(in code: String) -> [String] {
        let trackedLibraries = Set(["numpy", "matplotlib", "scipy", "sklearn", "manim"])
        let imported = extractImportedPythonModules(from: code)
        let trackedImports = imported.filter { trackedLibraries.contains($0) }
        guard !trackedImports.isEmpty else { return [] }

        var unsupported: [String] = []
        for module in trackedImports.sorted() {
            let state = pythonLibraryStates[module]
            let isSupported: Bool
            switch state {
            case .installed?, .shim?:
                isSupported = true
            case .missing?, .error?:
                isSupported = false
            case nil:
                // Safe fallback before probe: numpy/matplotlib have compatibility layers.
                isSupported = (module == "numpy" || module == "matplotlib")
            }
            if !isSupported {
                unsupported.append(displayPythonLibraryName(module))
            }
        }
        return unsupported
    }

    private func extractImportedPythonModules(from code: String) -> Set<String> {
        var modules = Set<String>()
        let ns = code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        if let fromRegex = try? NSRegularExpression(pattern: "(?m)^\\s*from\\s+([A-Za-z_][A-Za-z0-9_\\.]*)\\s+import\\s+", options: []) {
            for match in fromRegex.matches(in: code, options: [], range: fullRange) where match.numberOfRanges > 1 {
                let value = ns.substring(with: match.range(at: 1))
                if let module = normalizePythonImportModule(value) {
                    modules.insert(module)
                }
            }
        }

        if let importRegex = try? NSRegularExpression(pattern: "(?m)^\\s*import\\s+([^\\n#]+)", options: []) {
            for match in importRegex.matches(in: code, options: [], range: fullRange) where match.numberOfRanges > 1 {
                let clause = ns.substring(with: match.range(at: 1))
                let parts = clause.split(separator: ",")
                for rawPart in parts {
                    let part = String(rawPart).trimmingCharacters(in: .whitespacesAndNewlines)
                    let base = part.components(separatedBy: " as ").first ?? part
                    if let module = normalizePythonImportModule(base) {
                        modules.insert(module)
                    }
                }
            }
        }
        return modules
    }

    private func normalizePythonImportModule(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let base = trimmed.split(separator: ".").first.map(String.init) ?? trimmed
        if base == "scikit" || base == "scikitlearn" || base == "scikit_learn" {
            return "sklearn"
        }
        return base
    }

    private func displayPythonLibraryName(_ module: String) -> String {
        switch module {
        case "sklearn":
            return "scikit-learn (sklearn)"
        default:
            return module
        }
    }

    private func isToolOnlyPlaceholderText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        let lowered = trimmed.lowercased()
        let placeholders = [
            "no final answer provided by model.",
            "final answer:",
            "answer:",
            "tool call:",
            "using tool:",
            "{}",
            "}",
            "]"
        ]
        if placeholders.contains(lowered) {
            return true
        }
        return lowered.hasPrefix("no final answer")
    }

    private var lastCodeBlocks: [MarkdownRenderer.CodeBlock] = []

    private func setAssistantFinalText(_ text: String, assistantIndex: Int) {
        let cleaned = stripJunkTags(from: text)
        if assistantIndex < messages.count {
            messages[assistantIndex].content = cleaned
        }
        if currentAssistantLabel == nil {
            startAssistantMessage(placeholder: cleaned)
        }
        guard let label = currentAssistantLabel else { return }
        // Set plain text first to stop any pending text system operations
        label.text = cleaned
        // Then render markdown after a short delay to avoid accumulator crash
        DispatchQueue.main.async { [weak label] in
            guard let label else { return }
            let renderResult = MarkdownRenderer.renderFull(cleaned, textColor: .label)
            label.attributedText = renderResult.attributedString
            self.lastCodeBlocks = renderResult.codeBlocks
        }
        rawAssistantStreamBuffer = ""
    }

    /// Format raw Python output into clean readable markdown
    private func formatPythonOutput(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }

        // Remove [plot saved] lines
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("[plot saved]") && !$0.hasPrefix("[py-exec]") }
        let cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "" }

        // If it's a single short line (simple result), show it as bold result
        let trimmedLines = cleaned.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if trimmedLines.count == 1 && trimmedLines[0].count < 200 {
            return "**Result:** `\(trimmedLines[0])`"
        }

        // Multiple lines — wrap in a code block for clean display
        if trimmedLines.count <= 20 {
            return "**Result:**\n```\n\(cleaned)\n```"
        }

        // Long output — truncate
        let truncated = trimmedLines.prefix(20).joined(separator: "\n")
        return "**Result:**\n```\n\(truncated)\n```\n*(\(trimmedLines.count - 20) more lines...)*"
    }

    /// Quick finish for tool execution — set text and clean up
    private func finishToolExecution(assistantIndex: Int, text: String) {
        setAssistantFinalText(text, assistantIndex: assistantIndex)
        applyLatexRenderingIfNeeded(for: text, bubble: currentAssistantBubble)
        finishToolCleanup()
    }

    /// Clean up UI state after tool execution completes
    private func finishToolCleanup() {
        currentAssistantLabel = nil
        currentAssistantBubble = nil
        currentAssistantRow = nil
        activityIndicator.stopAnimating()
        setGenerationEnabled(true)
        updateStatus("Ready.")
        HapticService.shared.success()
        userPausedAutoScroll = false
        scrollToBottomButton.isHidden = true
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        tokenStatsLabel.isHidden = true
        syncCurrentConversation()
        reloadConversationList()
    }

    private func attachToolImage(path: String, to bubble: MessageBubble) {
        if path.hasSuffix(".html") {
            // Interactive plotly chart — render in WKWebView
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.preferences.javaScriptEnabled = true
            if #available(iOS 17.0, *) {
                config.preferences.isElementFullscreenEnabled = false
            }
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.isOpaque = true
            webView.backgroundColor = .white
            webView.scrollView.backgroundColor = .white
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.layer.cornerRadius = 12
            webView.layer.cornerCurve = .continuous
            webView.clipsToBounds = true

            let chartHeight: CGFloat = 420
            NSLayoutConstraint.activate([
                webView.heightAnchor.constraint(equalToConstant: chartHeight),
            ])

            // Load plotly HTML directly — the chart size is set in the figure layout
            let url = URL(fileURLWithPath: path)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            bubble.contentStack.addArrangedSubview(webView)

            // Force the bubble to expand to full width so the chart isn't squeezed
            if let bubbleSuperview = bubble.view.superview {
                // Remove the lessThanOrEqual width and replace with a wider one
                for c in bubbleSuperview.constraints where c.firstItem as? UIView == bubble.view && c.firstAttribute == .width {
                    c.isActive = false
                }
                bubble.view.widthAnchor.constraint(equalTo: bubbleSuperview.widthAnchor, multiplier: 0.95).isActive = true
            }
            print("[python] Chart displayed: \(path)")
        } else if let image = UIImage(contentsOfFile: path) {
            // Static image (PNG from matplotlib shim)
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 12
            imageView.layer.cornerCurve = .continuous
            imageView.backgroundColor = .white
            imageView.translatesAutoresizingMaskIntoConstraints = false

            // Fill bubble width, constrain height proportionally
            let aspectRatio = image.size.height / max(1, image.size.width)
            let maxH: CGFloat = min(500, max(200, aspectRatio * 600))
            NSLayoutConstraint.activate([
                imageView.heightAnchor.constraint(equalToConstant: maxH),
            ])

            bubble.contentStack.addArrangedSubview(imageView)
            print("[python] Image displayed: \(Int(image.size.width))x\(Int(image.size.height))")
        } else {
            print("[python] Failed to load image at: \(path)")
        }
        if shouldAutoScroll() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.scrollChatToBottom()
            }
        }
    }

    private func applyLatexRenderingIfNeeded(for message: String, bubble: MessageBubble?) {
        guard let bubble, shouldRenderLatex(for: message) else { return }
        bubble.contentStack.arrangedSubviews
            .filter { $0 is LaTeXView }
            .forEach { view in
                bubble.contentStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        let latexView = LaTeXView()
        guard latexView.render(latex: message, textColor: UIColor.label) else {
            return
        }
        // Keep the raw text visible so users can still select and copy it.
        bubble.label.isHidden = false
        bubble.contentStack.insertArrangedSubview(latexView, at: 0)
        if shouldAutoScroll() {
            scrollChatToBottom()
        }
    }

    private func scrollChatToBottom() {
        guard view.window != nil else {
            needsInitialScroll = true
            return
        }
        view.layoutIfNeeded()
        let bottomOffset = CGPoint(x: 0, y: max(0, chatScrollView.contentSize.height - chatScrollView.bounds.height))
        chatScrollView.setContentOffset(bottomOffset, animated: false)
    }

    private func makeBubble(text: String, isUser: Bool, renderLatex: Bool) -> MessageBubble {
        let label = UITextView()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .label  // ChatGPT-style: .label for both roles
        label.backgroundColor = .clear
        label.isEditable = false
        label.isSelectable = true
        label.isScrollEnabled = false
        label.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        label.textContainer.lineFragmentPadding = 0
        label.dataDetectorTypes = isUser ? [] : [.link]
        label.linkTextAttributes = [
            .foregroundColor: WorkspaceStyle.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(label)

        let bubbleView = UIView()
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        if isUser {
            // ChatGPT-style: gray pill for user
            bubbleView.backgroundColor = WorkspaceStyle.userBubbleBg
            bubbleView.layer.cornerRadius = 18
            bubbleView.layer.cornerCurve = .continuous
        } else {
            // ChatGPT-style: no background, no blur, no border for assistant
            bubbleView.backgroundColor = .clear
            bubbleView.layer.cornerRadius = 0
        }
        // No border, no shadow for either
        bubbleView.layer.borderWidth = 0
        bubbleView.layer.shadowOpacity = 0
        bubbleView.addSubview(contentStack)
        let vPad: CGFloat = isUser ? 10 : 4
        let hPad: CGFloat = isUser ? 14 : 2
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: vPad),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: hPad),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -hPad),
            contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -vPad)
        ])

        // Add copy button for assistant messages
        if !isUser {
            let actionBar = UIStackView()
            actionBar.axis = .horizontal
            actionBar.spacing = 8
            actionBar.alignment = .center
            actionBar.translatesAutoresizingMaskIntoConstraints = false

            let copyBtn = UIButton(type: .system)
            copyBtn.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
            copyBtn.tintColor = .tertiaryLabel
            copyBtn.addAction(UIAction { [weak label] _ in
                UIPasteboard.general.string = label?.text
                copyBtn.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
                copyBtn.tintColor = .systemGreen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copyBtn.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
                    copyBtn.tintColor = .tertiaryLabel
                }
            }, for: .touchUpInside)
            actionBar.addArrangedSubview(copyBtn)
            actionBar.addArrangedSubview(UIView()) // spacer
            contentStack.addArrangedSubview(actionBar)
        }

        let bubble = MessageBubble(view: bubbleView, label: label, contentStack: contentStack)
        if renderLatex && !isUser {
            applyLatexRenderingIfNeeded(for: text, bubble: bubble)
        }
        return bubble
    }

    private func makeBubbleRow(bubble: UIView, isUser: Bool) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false

        let leadingConstraint = bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor)
        let trailingConstraint = bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor)
        // ChatGPT-style: assistant near full-width, user 75%
        let maxWidth: CGFloat = isUser ? 0.75 : 0.95
        let widthConstraint = bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: maxWidth)

        if isUser {
            trailingConstraint.isActive = true
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 40).isActive = true
        } else {
            leadingConstraint.isActive = true
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8).isActive = true
        }

        NSLayoutConstraint.activate([
            widthConstraint,
            bubble.topAnchor.constraint(equalTo: row.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        return row
    }

    // MARK: - Inline Thinking (modern ChatGPT/Claude style)

    private func startInlineThinking() {
        stopInlineThinking()
        thinkingStartTime = Date()
        inlineThinkingText = ""

        // ChatGPT-style: create the assistant bubble FIRST, then embed thinking at index 0
        if currentAssistantLabel == nil {
            stopTypingIndicator()
            startAssistantMessage(placeholder: "")
        }
        guard let bubble = currentAssistantBubble else { return }

        // Header: spinning indicator + "Thinking..."
        let spinner = UIActivityIndicatorView(style: UIActivityIndicatorView.Style.medium)
        spinner.color = UIColor.secondaryLabel
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let thinkLabel = UILabel()
        thinkLabel.text = "Thinking..."
        thinkLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        thinkLabel.textColor = UIColor.secondaryLabel
        thinkLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = UIStackView(arrangedSubviews: [spinner, thinkLabel])
        headerStack.axis = NSLayoutConstraint.Axis.horizontal
        headerStack.spacing = 6
        headerStack.alignment = UIStackView.Alignment.center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // Thinking text preview (shows streaming thinking text, muted and smaller)
        let thinkTV = UITextView()
        thinkTV.isEditable = false
        thinkTV.isScrollEnabled = false
        thinkTV.isSelectable = true
        thinkTV.backgroundColor = .clear
        thinkTV.font = UIFont.systemFont(ofSize: 13)
        thinkTV.textColor = UIColor.secondaryLabel
        thinkTV.textContainerInset = .zero
        thinkTV.textContainer.lineFragmentPadding = 0
        thinkTV.translatesAutoresizingMaskIntoConstraints = false
        thinkTV.setContentHuggingPriority(.defaultHigh, for: .vertical)
        thinkTV.setContentCompressionResistancePriority(.required, for: .vertical)

        // Wrap thinking UI in a container so we can swap it with the pill later
        let thinkingContainer = UIStackView(arrangedSubviews: [headerStack, thinkTV])
        thinkingContainer.axis = .vertical
        thinkingContainer.spacing = 4
        thinkingContainer.translatesAutoresizingMaskIntoConstraints = false
        thinkingContainer.tag = 9901  // Tag to find it later

        // Insert thinking at index 0 (above the label which is already at index 0)
        bubble.contentStack.insertArrangedSubview(thinkingContainer, at: 0)

        thinkingBubbleRow = currentAssistantRow
        thinkingBubbleLabel = thinkTV
        thinkingBubbleContentStack = bubble.contentStack

        if shouldAutoScroll() { scrollChatToBottom() }
    }

    private func appendInlineThinkingText(_ text: String) {
        inlineThinkingText += text
        // Show last ~500 chars of thinking to keep it responsive
        let display = inlineThinkingText.count > 500
            ? "..." + String(inlineThinkingText.suffix(500))
            : inlineThinkingText
        thinkingBubbleLabel?.text = display
        if shouldAutoScroll() { scrollChatToBottom() }
    }

    private func stopInlineThinking() {
        // Replace the streaming thinking section with a collapsible pill IN PLACE
        guard let contentStack = thinkingBubbleContentStack else { return }

        let elapsed = thinkingStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
        let thinkText = inlineThinkingText

        // Remove the streaming thinking container (tag 9901) from contentStack
        if let thinkingContainer = contentStack.arrangedSubviews.first(where: { $0.tag == 9901 }) {
            thinkingContainer.removeFromSuperview()
        }

        thinkingBubbleLabel = nil
        // Do NOT remove thinkingBubbleRow or thinkingBubbleContentStack -- they are the assistant bubble

        guard !thinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            thinkingBubbleRow = nil
            thinkingBubbleContentStack = nil
            return
        }

        // Create a ChatGPT-style collapsible thinking section
        // Style: "Thought for 19s >" — plain text, no pill background, chevron on trailing side
        let pillButton = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        config.imagePadding = 4
        config.imagePlacement = .trailing  // chevron on right like ChatGPT ">"
        config.title = elapsed > 0 ? "Thought for \(elapsed)s" : "Thought"
        config.baseForegroundColor = UIColor.tertiaryLabel
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming; out.font = UIFont.systemFont(ofSize: 14, weight: .regular); return out
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
        pillButton.configuration = config
        pillButton.backgroundColor = .clear  // no background — just text like ChatGPT
        pillButton.translatesAutoresizingMaskIntoConstraints = false
        pillButton.contentHorizontalAlignment = .leading

        // Expanded thinking text — liquid glass frosted panel
        let thinkWrapper = UIView()
        thinkWrapper.translatesAutoresizingMaskIntoConstraints = false
        thinkWrapper.isHidden = true
        thinkWrapper.layer.cornerRadius = 12
        thinkWrapper.layer.cornerCurve = .continuous
        thinkWrapper.clipsToBounds = true

        // Liquid glass blur effect
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        thinkWrapper.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: thinkWrapper.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: thinkWrapper.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: thinkWrapper.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: thinkWrapper.bottomAnchor),
        ])

        // Subtle border
        thinkWrapper.layer.borderWidth = 0.5
        thinkWrapper.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor

        let thinkTV = UITextView()
        thinkTV.isEditable = false
        thinkTV.isScrollEnabled = false
        thinkTV.isSelectable = true
        thinkTV.backgroundColor = .clear
        thinkTV.font = UIFont.systemFont(ofSize: 13)
        thinkTV.textColor = UIColor.secondaryLabel
        thinkTV.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        thinkTV.textContainer.lineFragmentPadding = 0
        thinkTV.text = thinkText
        thinkTV.translatesAutoresizingMaskIntoConstraints = false
        thinkTV.setContentHuggingPriority(.defaultHigh, for: .vertical)

        thinkWrapper.addSubview(thinkTV)
        NSLayoutConstraint.activate([
            thinkTV.topAnchor.constraint(equalTo: thinkWrapper.topAnchor),
            thinkTV.leadingAnchor.constraint(equalTo: thinkWrapper.leadingAnchor),
            thinkTV.trailingAnchor.constraint(equalTo: thinkWrapper.trailingAnchor),
            thinkTV.bottomAnchor.constraint(equalTo: thinkWrapper.bottomAnchor),
        ])

        let pillStack = UIStackView(arrangedSubviews: [pillButton, thinkWrapper])
        pillStack.axis = .vertical
        pillStack.spacing = 4
        pillStack.alignment = .fill
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillStack.tag = 9902

        // Toggle action
        pillButton.addAction(UIAction { [weak thinkWrapper, weak pillButton] _ in
            guard let wrapper = thinkWrapper, let btn = pillButton else { return }
            let willExpand = wrapper.isHidden
            UIView.animate(withDuration: 0.25) {
                wrapper.isHidden = !willExpand
                wrapper.alpha = willExpand ? 1 : 0
                var c = btn.configuration
                c?.image = UIImage(systemName: willExpand ? "chevron.down" : "chevron.right",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
                btn.configuration = c
            }
            HapticService.shared.tapLight()
        }, for: .touchUpInside)

        // Insert pill at index 0 of contentStack (above the answer label)
        contentStack.insertArrangedSubview(pillStack, at: 0)

        thinkingPillRow = pillStack  // keep reference (now it's inside the bubble, not a separate row)
        thinkingBubbleRow = nil
        thinkingBubbleContentStack = nil
    }

    /// Phase 4: Append tool error info to the thinking text (hidden unless user expands pill)
    /// Append a status line to the thinking section (e.g. "Running Python...", "Error, fixing...")
    private func appendToolStatusToThinking(_ status: String) {
        inlineThinkingText += "\n\(status)"
        // Update the thinking text view if the pill already exists
        if let pillStack = thinkingPillRow as? UIStackView,
           let wrapper = pillStack.arrangedSubviews.last,
           let thinkTV = wrapper.subviews.compactMap({ $0 as? UITextView }).first {
            thinkTV.text = inlineThinkingText
            // Auto-expand the thinking section while tool is running
            if wrapper.isHidden {
                wrapper.isHidden = false
                wrapper.alpha = 1
                if let btn = pillStack.arrangedSubviews.first as? UIButton {
                    var c = btn.configuration
                    c?.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
                    btn.configuration = c
                }
            }
        }
        // Also update the streaming thinking text view if still active
        if let streamTV = thinkingBubbleLabel {
            streamTV.text = inlineThinkingText
        }
    }

    private func appendToolErrorToThinking(_ errorText: String) {
        inlineThinkingText += "\n[Tool Error]\n\(errorText)\n"
        // If the pill already exists, update its text view
        if let pillStack = thinkingPillRow as? UIStackView,
           let wrapper = pillStack.arrangedSubviews.last,
           let thinkTV = wrapper.subviews.compactMap({ $0 as? UITextView }).first {
            thinkTV.text = inlineThinkingText
        }
    }

    /// Phase 4: Insert or update a small tool card in the assistant bubble
    private func insertToolCard(in bubble: MessageBubble?, text: String, success: Bool = false) {
        guard let contentStack = bubble?.contentStack else { return }
        let tag = 9903  // tool card tag
        // Remove existing tool card if present
        if let existing = contentStack.arrangedSubviews.first(where: { $0.tag == tag }) {
            existing.removeFromSuperview()
        }
        let card = UILabel()
        card.text = success ? "\u{2713} \(text)" : "\u{2699}\u{FE0F} \(text)"
        card.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        card.textColor = success ? UIColor.systemGreen : UIColor.secondaryLabel
        card.backgroundColor = UIColor.secondarySystemFill
        card.layer.cornerRadius = 8
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.textAlignment = .left
        card.translatesAutoresizingMaskIntoConstraints = false
        card.tag = tag

        // Add padding via a wrapper
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.tag = tag
        wrapper.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -8),
            card.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -4)
        ])
        wrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true

        // Insert before the label (which is the last subview typically)
        let insertIndex = max(0, contentStack.arrangedSubviews.count - 1)
        contentStack.insertArrangedSubview(wrapper, at: insertIndex)
    }

    private func startTypingIndicator() {
        stopTypingIndicator()
        let bubble = makeBubble(text: "", isUser: false, renderLatex: false)
        bubble.label.isHidden = true

        // Create 3 pulsing dots
        let dotStack = UIStackView()
        dotStack.axis = .horizontal
        dotStack.spacing = 6
        dotStack.alignment = .center
        dotStack.translatesAutoresizingMaskIntoConstraints = false

        typingDots = (0..<3).map { _ in
            let dot = UIView()
            dot.backgroundColor = WorkspaceStyle.accent
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8)
            ])
            dot.alpha = 0.3
            dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            return dot
        }
        typingDots.forEach { dotStack.addArrangedSubview($0) }
        bubble.contentStack.addArrangedSubview(dotStack)
        NSLayoutConstraint.activate([
            dotStack.heightAnchor.constraint(equalToConstant: 16)
        ])

        let row = makeBubbleRow(bubble: bubble.view, isUser: false)
        chatStack.addArrangedSubview(row)
        typingRow = row

        // Staggered animations
        for (i, dot) in typingDots.enumerated() {
            UIView.animate(withDuration: 0.5, delay: Double(i) * 0.15, options: [.repeat, .autoreverse, .curveEaseInOut]) {
                dot.alpha = 1.0
                dot.transform = .identity
            }
        }

        scrollChatToBottom()
    }

    private func stopTypingIndicator() {
        typingTimer?.invalidate()
        typingTimer = nil
        typingDots.forEach { $0.layer.removeAllAnimations() }
        typingDots.removeAll()
        typingRow?.removeFromSuperview()
        typingRow = nil
        typingLabel = nil
        typingStep = 0
    }

    @objc private func advanceTypingIndicator() {
        // No longer used — dots animate via UIView.animate
    }

    // MARK: - Feature Action Handlers

    @objc private func themeSegmentChanged(_ sender: UISegmentedControl) {
        if let mode = ThemeManager.Mode(rawValue: sender.selectedSegmentIndex) {
            ThemeManager.shared.mode = mode
            HapticService.shared.tapLight()
        }
    }

    @objc private func hapticsToggleChanged(_ sender: UISwitch) {
        HapticService.shared.enabled = sender.isOn
    }

    @objc private func ragImportTapped() {
        documentImporter = DocumentImporter(presenter: self)
        documentImporter?.delegate = self
        documentImporter?.presentPicker()
    }

    @objc private func compareModelsTapped() {
        let comparisonVC = ComparisonViewController(runner: runner, modelURLs: modelURLs)
        present(comparisonVC, animated: true)
        HapticService.shared.tapMedium()
    }

    @objc private func shareButtonTapped() {
        guard conversations.indices.contains(currentConversationIndex) else { return }
        showExportSheet(for: conversations[currentConversationIndex])
    }

    @objc private func scrollToBottomTapped() {
        userPausedAutoScroll = false
        scrollToBottomButton.isHidden = true
        scrollChatToBottom()
        HapticService.shared.tapLight()
    }

    @objc private func hamburgerTapped() {
        isSidebarHidden.toggle()
        UIView.animate(withDuration: 0.3) {
            self.sidebarView.isHidden = self.isSidebarHidden
            self.sidebarWidthConstraint?.constant = self.isSidebarHidden ? 0 : 250
            self.view.layoutIfNeeded()
        }
        HapticService.shared.tapLight()
    }

    @objc private func newChatTapped() {
        if isGenerating {
            return
        }
        syncCurrentConversation()
        let conversation = Conversation(id: UUID(),
                                        title: "New chat",
                                        messages: [ChatMessage(role: .system, content: systemPromptText())],
                                        updatedAt: Date())
        conversations.insert(conversation, at: 0)
        currentConversationIndex = 0
        messages = conversation.messages
        reloadChatStack()
        reloadConversationList()
    }

    @objc private func settingsTapped() {
        let shouldShow = settingsPanel.isHidden
        if shouldShow {
            settingsPanel.alpha = 0
            settingsPanel.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.settingsPanel.alpha = 1
            }
            refreshPythonLibraryStatusIfNeeded(force: false)
        } else {
            dismissSettingsPanel()
        }
    }

    @objc private func dismissSettingsPanel() {
        guard !settingsPanel.isHidden else { return }
        UIView.animate(withDuration: 0.18, animations: {
            self.settingsPanel.alpha = 0
        }, completion: { _ in
            self.settingsPanel.isHidden = true
            self.settingsPanel.alpha = 1
        })
    }

    @objc private func thinkingToggleChanged() {
        showThinking = thinkingToggle.isOn
        thinkingPillRow?.removeFromSuperview()
        thinkingPillRow = nil
        updateSystemPrompt()
    }

    @objc private func autoLoadChanged() {
        UserDefaults.standard.set(autoLoadToggle.isOn, forKey: autoLoadModelDefaultsKey)
        if autoLoadToggle.isOn {
            autoLoadLastModelIfNeeded()
        }
    }

    @objc private func pythonToolsToggleChanged() {
        pythonToolsEnabled = pythonToolsToggle.isOn
        UserDefaults.standard.set(pythonToolsEnabled, forKey: pythonToolEnabledDefaultsKey)
        updateSystemPrompt()
        if pythonToolsEnabled {
            updateStatus("Python tool enabled.")
        } else {
            updateStatus("Python tool disabled.")
        }
        refreshPythonLibraryStatusIfNeeded(force: true)
    }

    @objc private func refreshPythonLibraryStatusTapped() {
        refreshPythonLibraryStatusIfNeeded(force: true)
    }

    private func refreshPythonLibraryStatusIfNeeded(force: Bool) {
        if !pythonToolsEnabled {
            pythonStatusLabel.text = "Python tool is disabled."
            pythonStatusLabel.textColor = WorkspaceStyle.mutedText
            pythonRefreshButton.isEnabled = true
            return
        }
        if isRefreshingPythonStatus {
            return
        }
        if !force,
           let text = pythonStatusLabel.text,
           text != "Library status not checked.",
           !text.isEmpty {
            return
        }

        isRefreshingPythonStatus = true
        pythonStatusLabel.text = "Checking installed libraries..."
        pythonStatusLabel.textColor = WorkspaceStyle.mutedText
        pythonRefreshButton.isEnabled = false

        DispatchQueue.global(qos: .utility).async {
            let results = PythonRuntime.shared.probeLibraries(self.pythonLibraryProbeNames)
            DispatchQueue.main.async {
                self.isRefreshingPythonStatus = false
                self.pythonRefreshButton.isEnabled = true
                self.renderPythonLibraryStatus(results)
            }
        }
    }

    private func renderPythonLibraryStatus(_ probes: [PythonRuntime.LibraryProbe]) {
        guard !probes.isEmpty else {
            pythonStatusLabel.text = "No library status available."
            pythonStatusLabel.textColor = WorkspaceStyle.mutedText
            return
        }

        pythonLibraryStates.removeAll(keepingCapacity: true)
        var lines: [String] = []
        var hasMissing = false
        for probe in probes {
            pythonLibraryStates[probe.name.lowercased()] = probe.state
            let stateText: String
            switch probe.state {
            case .installed:
                stateText = "installed"
            case .shim:
                stateText = "compatibility layer"
            case .missing:
                stateText = "missing"
                hasMissing = true
            case .error:
                stateText = "error"
                hasMissing = true
            }
            lines.append("\(probe.name): \(stateText)")
        }
        pythonStatusLabel.text = lines.joined(separator: "\n")
        pythonStatusLabel.textColor = hasMissing ? UIColor.systemOrange : WorkspaceStyle.mutedText
        updateSystemPrompt()
    }

    @objc private func toggleThinkingPanel() {
        // No longer used — thinking is inline in chat bubbles
    }

    @objc private func effortChanged() {
        let effort = currentEffort()
        maxOutputTokens = effort.defaultMaxTokens
        maxTokensStepper.value = Double(maxOutputTokens)
        updateMaxTokensLabel()
        updateSystemPrompt()
    }

    @objc private func maxTokensChanged() {
        maxOutputTokens = Int(maxTokensStepper.value)
        updateMaxTokensLabel()
    }

    @objc private func importModelTapped() {
        let ggufType = UTType(filenameExtension: "gguf") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [ggufType], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func downloadModelTapped() {
        guard downloadTask == nil else { return }
        startDownload(for: currentSlot())
    }

    @objc private func loadModelTapped() {
        loadModel(for: currentSlot())
    }

    private func startDownload(for slot: ModelSlot) {
        guard downloadTask == nil else { return }

        // Check if model exists AND is a valid GGUF file (not a partial download)
        if let url = modelURLs[slot], FileManager.default.fileExists(atPath: url.path) {
            if isValidGgufFile(at: url) {
                updateStatus("Model already downloaded for \(slot.title).")
                return
            } else {
                // Partial/corrupt file — remove it and re-download
                print("[download] Removing corrupt/partial file: \(url.lastPathComponent)")
                try? FileManager.default.removeItem(at: url)
                modelURLs[slot] = nil
                UserDefaults.standard.removeObject(forKey: slot.storageKey)
            }
        }
        if let existing = findExistingModelFile(for: slot) {
            if isValidGgufFile(at: existing) {
                persistModelURL(existing, for: slot)
                updateStatus("Model already downloaded for \(slot.title).")
                return
            } else {
                // Partial/corrupt file — remove it
                print("[download] Removing corrupt/partial file: \(existing.lastPathComponent)")
                try? FileManager.default.removeItem(at: existing)
            }
        }

        let downloadURL = slot.downloadURL
        let task = downloadSession.downloadTask(with: downloadURL)
        downloadTask = task
        downloadSlot = slot
        setLoadingState(true, message: "Downloading \(downloadURL.lastPathComponent)...")
        task.resume()
    }

    private func loadModel(for slot: ModelSlot) {
        guard let url = modelURLs[slot] else {
            updateStatus("Select a GGUF file for \(slot.title) first.")
            return
        }
        loadModel(at: url, slot: slot, completion: nil)
    }

    private func loadModel(at url: URL, slot: ModelSlot, completion: ((Result<Void, Error>) -> Void)?) {
        let context = preferredContextSize()

        let batch = preferredBatchSize(for: context)
        let gpuLayers: Int32 = 99

        let modeNote = ""
        let sizeNote: String
        if let size = modelFileSize(at: url) {
            sizeNote = " \(formattedFileSize(bytes: size))"
        } else {
            sizeNote = ""
        }

        guard isValidGgufFile(at: url) else {
            let header = readFileHeader(at: url)
            setLoadingState(false, message: "Load failed: not a GGUF file. Header: \(header)")
            completion?(.failure(NSError(domain: "OfflinAi", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Not a GGUF file."])))
            return
        }

        setLoadingState(true, message: "Loading \(url.lastPathComponent)\(sizeNote)...\(modeNote)")

        // 9B hybrid (DeltaNet) needs kvUnified=true and Q8_0 KV to save memory
        let is9B = selectedModelSlot == .qwen35_9b
        let config = LlamaRunner.Config(contextSize: context,
                                        batchSize: is9B ? min(batch, 128) : batch,
                                        gpuLayers: gpuLayers,
                                        offloadKQV: true,
                                        opOffload: true,
                                        kvUnified: is9B,
                                        typeK: is9B ? GGML_TYPE_Q8_0 : GGML_TYPE_F16,
                                        typeV: is9B ? GGML_TYPE_Q8_0 : GGML_TYPE_F16,
                                        temperature: 0.7,
                                        topP: 0.9,
                                        topK: 50,
                                        repeatLastN: 64,
                                        repeatPenalty: 1.10,
                                        frequencyPenalty: 0.0,
                                        presencePenalty: 0.0)

        runner.loadModel(at: url, config: config) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                UserDefaults.standard.set(slot.rawValue, forKey: self.lastModelSlotDefaultsKey)
                UserDefaults.standard.set(url.path, forKey: self.lastModelPathDefaultsKey)
                self.loadedModelSlot = slot

                // Update editor with loaded model
                self.editorController?.llamaRunner = self.runner
                self.editorController?.updateModelName(slot.title)

                self.setLoadingState(false, message: "Loaded \(slot.title) (ctx \(context), batch \(batch)).")
                completion?(.success(()))
            case .failure(let error):
                var message = "Load failed: \(error.localizedDescription)"
                let log = self.runner.lastLogExcerpt
                if !log.isEmpty {
                    message += "\n\(log)"
                }
                // Helpful hint for memory issues
                let memGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
                message += "\n\nDevice RAM: \(String(format: "%.1f", memGB)) GB. Try closing other apps or a smaller model."
                self.loadedModelSlot = nil

                self.setLoadingState(false, message: message)
                completion?(.failure(error))
            }
        }
    }

    @objc private func sendTapped() {
        let trimmed = inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if handleEasterGameTrigger(trimmed) {
            inputTextView.text = ""
            updateComposerUI()
            return
        }

        guard !isGenerating else {
            updateStatus("Wait for the current response to finish.")
            return
        }

        HapticService.shared.send()
        inputTextView.text = ""
        updateComposerUI()
        enqueueUserMessage(trimmed)

        startGeneration(userText: trimmed)
    }

    private func handleEasterGameTrigger(_ input: String) -> Bool {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == gameTriggerKeyword else { return false }
        if isGenerating {
            updateStatus("Finish generation to open game.")
            return true
        }
        presentEasterGamePicker()
        return true
    }

    private func presentEasterGamePicker() {
        guard easterGameView == nil else { return }
        view.endEditing(true)
        let picker = GamePickerView()
        picker.onSelect = { [weak self] kind in
            self?.dismissEasterGame()
            self?.presentEasterGame(kind: kind)
        }
        picker.onClose = { [weak self] in
            self?.dismissEasterGame()
        }
        showGameOverlay(picker)
    }

    private func presentEasterGame(kind: EasterGameKind) {
        guard easterGameView == nil else { return }
        view.endEditing(true)
        let gameView: (UIView & EasterGamePlayable)
        switch kind {
        case .breaker:
            gameView = EasterGameView()
        case .snake:
            gameView = SnakeGameView()
        case .asteroids:
            gameView = AsteroidsGameView()
        case .tetris:
            gameView = TetrisGameView()
        case .dino:
            gameView = DinoGameView()
        }
        gameView.onClose = { [weak self] in
            self?.dismissEasterGame()
        }
        showGameOverlay(gameView)
    }

    private func showGameOverlay(_ viewToShow: UIView) {
        viewToShow.translatesAutoresizingMaskIntoConstraints = false
        let host: UIView
        if let window = view.window {
            host = window
        } else {
            host = view
        }
        host.addSubview(viewToShow)
        NSLayoutConstraint.activate([
            viewToShow.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            viewToShow.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            viewToShow.topAnchor.constraint(equalTo: host.topAnchor),
            viewToShow.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        easterGameView = viewToShow
        viewToShow.isUserInteractionEnabled = true
        viewToShow.accessibilityViewIsModal = true
        viewToShow.alpha = 0
        if let playable = viewToShow as? EasterGamePlayable {
            playable.start()
        } else if let picker = viewToShow as? GamePickerView {
            picker.start()
        }
        if let input = viewToShow as? EasterGameKeyInput {
            activeGameInput = input
            becomeFirstResponder()
            DispatchQueue.main.async { [weak self] in
                _ = self?.becomeFirstResponder()
            }
        } else {
            activeGameInput = nil
        }
        host.bringSubviewToFront(viewToShow)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            viewToShow.alpha = 1
        }
    }

    private func dismissEasterGame() {
        easterGameView?.removeFromSuperview()
        easterGameView = nil
        activeGameInput = nil
        resignFirstResponder()
        view.endEditing(false)
    }

    // OCR / image processing removed



    private func setLoadingState(_ isLoading: Bool, message: String) {
        importButton.isEnabled = !isLoading
        downloadButton.isEnabled = !isLoading
        loadButton.isEnabled = !isLoading
        modelSelectButton.isEnabled = !isLoading
        effortSegment.isEnabled = !isLoading && !isGenerating
        thinkingToggle.isEnabled = !isLoading && !isGenerating
        maxTokensStepper.isEnabled = !isLoading && !isGenerating
        autoLoadToggle.isEnabled = !isLoading && !isGenerating
        pythonToolsToggle.isEnabled = !isLoading && !isGenerating
        sendButton.isEnabled = !isLoading && !isGenerating
        conversationsTable.isUserInteractionEnabled = !isLoading && !isGenerating
        newChatButton.isEnabled = !isLoading && !isGenerating
        settingsButton.isEnabled = !isLoading && !isGenerating
        updateComposerUI()
        updateStatus(message)
        if isLoading {
            activityIndicator.startAnimating()
        } else if !isGenerating {
            activityIndicator.stopAnimating()
        }
    }

    private func setGenerationEnabled(_ enabled: Bool) {
        let allowSend = enabled || isGenerating
        sendButton.isEnabled = allowSend
        effortSegment.isEnabled = enabled
        thinkingToggle.isEnabled = enabled
        maxTokensStepper.isEnabled = enabled
        importButton.isEnabled = enabled
        downloadButton.isEnabled = enabled
        loadButton.isEnabled = enabled
        modelSelectButton.isEnabled = enabled
        autoLoadToggle.isEnabled = enabled
        pythonToolsToggle.isEnabled = enabled
        conversationsTable.isUserInteractionEnabled = enabled
        newChatButton.isEnabled = enabled
        settingsButton.isEnabled = enabled
        updateComposerUI()
    }

    private func persistModelURL(_ url: URL, for slot: ModelSlot) {
        UserDefaults.standard.set(url.path, forKey: slot.storageKey)
        UserDefaults.standard.set(slot.rawValue, forKey: lastModelSlotDefaultsKey)
        UserDefaults.standard.set(url.path, forKey: lastModelPathDefaultsKey)
        modelURLs[slot] = url
        updateModelUI()
    }
}

extension GameViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        conversationSearchQuery = searchText
        refreshFilteredConversationIndices()
        conversationsTable.reloadData()
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        conversationSearchQuery = ""
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.resignFirstResponder()
        refreshFilteredConversationIndices()
        conversationsTable.reloadData()
    }
}

extension GameViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard textView === inputTextView else { return }
        updateComposerUI()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard textView === inputTextView else { return true }
        if text == "\n" {
            sendTapped()
            return false
        }
        return true
    }
}

extension GameViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredConversationIndices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseId = "ConversationCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseId)
        guard indexPath.row < filteredConversationIndices.count else { return cell }
        let conversation = conversations[filteredConversationIndices[indexPath.row]]
        let pinPrefix = conversation.isPinned ? "📌 " : ""
        cell.textLabel?.text = pinPrefix + conversation.title
        cell.textLabel?.font = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .semibold)
        cell.textLabel?.textColor = UIColor.label
        let lastPreview = conversation.messages.reversed().first(where: { $0.role != .system })?.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = lastPreview.isEmpty ? "No messages yet" : String(lastPreview.prefix(42))
        cell.detailTextLabel?.text = "\(preview)  •  \(conversationDateFormatter.string(from: conversation.updatedAt))"
        cell.detailTextLabel?.font = UIFont(name: "AvenirNext-Regular", size: 11) ?? UIFont.systemFont(ofSize: 11)
        cell.detailTextLabel?.textColor = UIColor.tertiaryLabel
        cell.backgroundColor = .clear
        let isActive = filteredConversationIndices[indexPath.row] == currentConversationIndex
        let selectedView = UIView()
        selectedView.backgroundColor = WorkspaceStyle.accent.withAlphaComponent(0.12)
        selectedView.layer.cornerRadius = 12
        cell.selectedBackgroundView = selectedView
        if isActive {
            cell.backgroundColor = WorkspaceStyle.accent.withAlphaComponent(0.06)
        }
        cell.layer.cornerRadius = 12
        cell.layer.masksToBounds = true
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < filteredConversationIndices.count else { return }
        selectConversation(at: filteredConversationIndices[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isGenerating else { return nil }
        guard indexPath.row < filteredConversationIndices.count else { return nil }
        let actualIndex = filteredConversationIndices[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let deletingCurrent = actualIndex == self.currentConversationIndex
            self.conversations.remove(at: actualIndex)

            if self.conversations.isEmpty {
                let conversation = Conversation(id: UUID(),
                                                title: "New chat",
                                                messages: [ChatMessage(role: .system, content: self.systemPromptText())],
                                                updatedAt: Date())
                self.conversations = [conversation]
                self.currentConversationIndex = 0
                self.messages = conversation.messages
                self.reloadChatStack()
            } else {
                if deletingCurrent {
                    self.currentConversationIndex = min(actualIndex, self.conversations.count - 1)
                    self.messages = self.conversations[self.currentConversationIndex].messages
                    self.reloadChatStack()
                } else if actualIndex < self.currentConversationIndex {
                    self.currentConversationIndex -= 1
                }
            }

            self.saveConversations()
            self.reloadConversationList()
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.row < filteredConversationIndices.count else { return nil }
        let actualIndex = filteredConversationIndices[indexPath.row]
        let conversation = conversations[actualIndex]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
                guard let self else { return }
                let alert = UIAlertController(title: "Rename Conversation", message: nil, preferredStyle: .alert)
                alert.addTextField { field in
                    field.text = conversation.title
                    field.clearButtonMode = .whileEditing
                }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
                    guard let self, let newTitle = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !newTitle.isEmpty else { return }
                    self.conversations[actualIndex].title = newTitle
                    self.saveConversations()
                    self.reloadConversationList()
                    HapticService.shared.tapLight()
                })
                self.present(alert, animated: true)
            }

            let pinTitle = conversation.isPinned ? "Unpin" : "Pin"
            let pinImage = conversation.isPinned ? "pin.slash" : "pin.fill"
            let pinAction = UIAction(title: pinTitle, image: UIImage(systemName: pinImage)) { [weak self] _ in
                guard let self else { return }
                self.conversations[actualIndex].isPinned.toggle()
                self.saveConversations()
                self.reloadConversationList()
                HapticService.shared.tapLight()
            }

            let exportAction = UIAction(title: "Export", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }
                self.showExportSheet(for: conversation)
            }

            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                let alert = UIAlertController(title: "Delete Conversation?", message: "This cannot be undone.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                    guard let self else { return }
                    self.deleteConversation(at: actualIndex)
                })
                self.present(alert, animated: true)
            }

            return UIMenu(children: [renameAction, pinAction, exportAction, deleteAction])
        }
    }

    private func showExportSheet(for conversation: Conversation) {
        let alert = UIAlertController(title: "Export As", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Markdown", style: .default) { [weak self] _ in
            let md = ConversationExporter.markdownString(from: conversation.messages, title: conversation.title)
            self?.presentShareSheet(items: [md])
        })
        alert.addAction(UIAlertAction(title: "Plain Text", style: .default) { [weak self] _ in
            let txt = ConversationExporter.plainTextString(from: conversation.messages, title: conversation.title)
            self?.presentShareSheet(items: [txt])
        })
        alert.addAction(UIAlertAction(title: "PDF", style: .default) { [weak self] _ in
            let data = ConversationExporter.pdfData(from: conversation.messages, title: conversation.title)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(conversation.title).pdf")
            try? data.write(to: tmpURL)
            self?.presentShareSheet(items: [tmpURL])
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = shareButton
        present(alert, animated: true)
    }

    private func presentShareSheet(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = shareButton
        present(vc, animated: true)
    }

    private func deleteConversation(at index: Int) {
        let deletingCurrent = index == currentConversationIndex
        conversations.remove(at: index)
        if conversations.isEmpty {
            let c = Conversation(id: UUID(), title: "New chat", messages: [ChatMessage(role: .system, content: systemPromptText())], updatedAt: Date())
            conversations = [c]
            currentConversationIndex = 0
            messages = c.messages
            reloadChatStack()
        } else if deletingCurrent {
            currentConversationIndex = min(index, conversations.count - 1)
            messages = conversations[currentConversationIndex].messages
            reloadChatStack()
        } else if index < currentConversationIndex {
            currentConversationIndex -= 1
        }
        saveConversations()
        reloadConversationList()
    }
}

extension GameViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === chatScrollView, isGenerating else { return }
        let distanceFromBottom = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
        if distanceFromBottom > 100 {
            if !userPausedAutoScroll {
                userPausedAutoScroll = true
                scrollToBottomButton.isHidden = false
                UIView.animate(withDuration: 0.2) { self.scrollToBottomButton.alpha = 1 }
            }
        } else if distanceFromBottom < 50 {
            userPausedAutoScroll = false
            scrollToBottomButton.isHidden = true
        }
    }
}

extension GameViewController: DocumentImporterDelegate {
    func documentImporter(_ importer: DocumentImporter, didImportText text: String, filename: String) {
        let success = RAGEngine.shared.importDocument(text: text, filename: filename)
        if success {
            updateStatus("Imported \(filename) (\(RAGEngine.shared.totalChunkCount) chunks)")
            HapticService.shared.success()
        } else {
            updateStatus("Import failed: chunk limit reached")
            HapticService.shared.error()
        }
    }

    func documentImporter(_ importer: DocumentImporter, didFailWith error: String) {
        updateStatus("Import error: \(error)")
        HapticService.shared.error()
    }
}

extension GameViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let sourceURL = urls.first else { return }
        let slot = currentSlot()
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let modelsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Models", isDirectory: true)
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

            let fileName = "\(slot.filePrefix)-\(sourceURL.lastPathComponent)"
            let destinationURL = modelsDirectory.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            persistModelURL(destinationURL, for: slot)
            updateStatus("Imported \(destinationURL.lastPathComponent).")
        } catch {
            updateStatus("Import failed: \(error.localizedDescription)")
        }
    }
}

// PHPickerViewControllerDelegate removed (OCR removed)

extension GameViewController: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let slot = downloadSlot else { return }
        do {
            let modelsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Models", isDirectory: true)
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

            if !isValidGgufFile(at: location) {
                let snippet = readFileHeader(at: location)
                setLoadingState(false, message: "Download failed: not a GGUF file. Header: \(snippet)")
                try? FileManager.default.removeItem(at: location)
                self.downloadTask = nil
                self.downloadSlot = nil
                return
            }

            let baseName = downloadTask.response?.suggestedFilename
                ?? downloadTask.originalRequest?.url?.lastPathComponent
                ?? "model.gguf"
            let normalizedPrefix = slot.filePrefix.lowercased()
            var fileName: String
            if baseName.lowercased().hasPrefix(normalizedPrefix) {
                fileName = baseName
            } else {
                fileName = "\(slot.filePrefix)-\(baseName)"
            }
            if !fileName.lowercased().hasSuffix(".gguf") {
                fileName += ".gguf"
            }
            let destinationURL = modelsDirectory.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            persistModelURL(destinationURL, for: slot)
            setLoadingState(false, message: "Downloaded \(destinationURL.lastPathComponent).")
            filesManagerController?.reloadEntries()
        } catch {
            setLoadingState(false, message: "Download failed: \(error.localizedDescription)")
        }

        self.downloadTask = nil
        self.downloadSlot = nil
    }

    private func isValidGgufFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 4)
        return String(data: data, encoding: .ascii) == "GGUF"
    }

    private func readFileHeader(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "(unreadable)" }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 16)
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(empty)" : trimmed
        }
        return "(binary)"
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let percent = Int(progress * 100)
        updateStatus("Downloading... \(percent)%")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        setLoadingState(false, message: "Download failed: \(error.localizedDescription)")
        self.downloadTask = nil
        self.downloadSlot = nil
    }
}

extension GameViewController: ModelsManagerDelegate {
    func modelsManagerDidUpdateModels(_ controller: ModelsManagerViewController) {
        loadSavedModelPaths()
        let defaults = UserDefaults.standard
        if let lastPath = defaults.string(forKey: lastModelPathDefaultsKey),
           !FileManager.default.fileExists(atPath: lastPath) {
            defaults.removeObject(forKey: lastModelPathDefaultsKey)
        }
        updateModelUI()
        updateModelSelectorUI()
        if modelURLs[currentSlot()] == nil {
            updateStatus("Selected model was deleted. Choose another model.")
        }
        filesManagerController?.reloadEntries()
    }

    func modelsManager(_ controller: ModelsManagerViewController, requestDownloadFor slot: ModelSlot) {
        selectModel(slot)
        startDownload(for: slot)
    }

    func modelsManager(_ controller: ModelsManagerViewController, requestLoadFor slot: ModelSlot) {
        selectModel(slot)
        loadModel(for: slot)
    }

}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

private extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = Int(red * 255.0)
        let g = Int(green * 255.0)
        let b = Int(blue * 255.0)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - FilesBrowserDelegate

extension GameViewController: FilesBrowserDelegate {
    func filesBrowser(_ controller: FilesBrowserViewController, didSelectCodeFile url: URL) {
        // Switch to Editor tab and load the file
        contentModeControl.selectedSegmentIndex = 0
        updateContentMode()
        editorController?.loadFile(url: url)
    }

    func filesBrowser(_ controller: FilesBrowserViewController, didRequestLoadModel url: URL) {
        // Find matching ModelSlot or load directly
        for (slot, existingURL) in modelURLs {
            if existingURL == url {
                loadModel(for: slot)
                return
            }
        }
        // Load as the currently selected slot
        loadModel(at: url, slot: selectedModelSlot, completion: nil)
    }
}

// MARK: - LibraryDocsDelegate

extension GameViewController: LibraryDocsDelegate {
    func libraryDocs(_ controller: LibraryDocsViewController, didRequestOpenCode code: String, language: String) {
        // Switch to Editor tab and insert the code
        contentModeControl.selectedSegmentIndex = 0
        updateContentMode()
        editorController?.insertCode(code, language: language)
    }
}
