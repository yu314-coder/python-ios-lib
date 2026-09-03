import Foundation

// ---------------------------------------------------------------------------
// Render configuration
//
// These are the app developer's settings, not the script author's. A person
// writing Python to run *inside* the app can reach the same values through
// `manim.utils.ios_encoder.settings`, but an app embedding this package needs
// to decide them before any script runs — the memory a render may hold is a
// property of the app and the device it is on, not of the animation.
//
// The values travel to Python as environment variables, which the Python side
// reads once when `manim.utils.ios_encoder` is imported. So they have to be
// set before the interpreter imports manim; at app startup, beside the other
// bootstrap calls, is the right place.
// ---------------------------------------------------------------------------

extension ManimLib {

    /// How a manim render uses memory and which encoder it reaches for.
    ///
    /// Usage from a host app:
    ///
    ///     import Manim
    ///
    ///     var render = ManimLib.RenderConfiguration()
    ///     render.frameQueueDepth = 8          // fixed depth, 1 or more
    ///     ManimLib.renderConfiguration = render
    ///
    ///     // …then start your Python interpreter.
    ///
    /// Depth against memory is the whole trade: the queue holds finished
    /// frames waiting for the encoder, so a deeper one lets rendering and
    /// encoding overlap and costs a frame's worth of RGBA per slot. That is
    /// 8 MB at 1080p and 133 MB at 8K, which is why a fixed depth is the
    /// wrong default and `frameQueueBudgetMB` exists.
    public struct RenderConfiguration: Sendable, Equatable {

        /// Which encoder to use, instead of asking the hardware what it
        /// supports at the render's resolution.
        ///
        /// Leave this `nil` unless you have a reason. The default probe picks
        /// H.264 where Apple's hardware encoder reaches, and HEVC above it —
        /// which on an M3 or M4 is anything past 4096x2304, where
        /// `h264_videotoolbox` cannot open at all.
        public enum VideoCodec: String, Sendable {
            /// Apple's hardware H.264. No software path: fails above the
            /// media engine's ceiling rather than falling back.
            case h264 = "h264_videotoolbox"
            /// Apple's hardware HEVC. Reaches 8K on every Apple silicon
            /// media engine measured so far.
            case hevc = "hevc_videotoolbox"
            /// Software. Slow, and the output is visibly worse, but it works
            /// at any size and releases its buffers on container close.
            case mpeg4
        }

        /// A fixed number of frames the encoder queue may hold, ignoring
        /// `frameQueueBudgetMB`.
        ///
        /// One or more; `0` means unbounded, which is the desktop behaviour
        /// and will eventually be killed by jetsam on a device. `nil` — the
        /// default — derives the depth from the budget instead, which is
        /// usually what you want, because the right number of frames is
        /// different at every resolution.
        public var frameQueueDepth: Int?

        /// Memory the encoder queue may hold, in MB. Default 256.
        ///
        /// The depth in frames follows from this and the render resolution:
        /// 32 frames at 1080p, 8 at 4K, 2 at 8K.
        public var frameQueueBudgetMB: Int

        /// The fewest frames a budget may work out to. Default 2.
        ///
        /// Below two the renderer and the encoder stop overlapping and the
        /// render gets slower rather than lighter. Lower it to 1 if you would
        /// rather have the memory back.
        public var frameQueueMinimum: Int

        /// The most frames a budget may work out to. Default 32.
        ///
        /// Past this the encoder is the bottleneck and more queue buys
        /// latency rather than throughput. Raise it if you have measured
        /// otherwise on your hardware.
        public var frameQueueMaximum: Int

        /// See `VideoCodec`. `nil` asks the hardware.
        public var videoCodec: VideoCodec?

        public init(frameQueueDepth: Int? = nil,
                    frameQueueBudgetMB: Int = 256,
                    frameQueueMinimum: Int = 2,
                    frameQueueMaximum: Int = 32,
                    videoCodec: VideoCodec? = nil) {
            self.frameQueueDepth = frameQueueDepth
            self.frameQueueBudgetMB = frameQueueBudgetMB
            self.frameQueueMinimum = frameQueueMinimum
            self.frameQueueMaximum = frameQueueMaximum
            self.videoCodec = videoCodec
        }

        /// How many frames this configuration works out to at a given size,
        /// so an app can show the answer before a render rather than after.
        public func frameQueueDepth(forWidth width: Int, height: Int) -> Int {
            if let frameQueueDepth { return max(0, frameQueueDepth) }
            let frameBytes = max(width * height * 4, 1)
            let fits = (max(frameQueueBudgetMB, 0) * 1024 * 1024) / frameBytes
            return max(max(frameQueueMinimum, 1), min(max(frameQueueMaximum, 1), fits))
        }

        /// Memory the queue may hold at a given size, in bytes.
        public func frameQueueBytes(forWidth width: Int, height: Int) -> Int {
            frameQueueDepth(forWidth: width, height: height) * width * height * 4
        }

        /// Write the settings where the Python side will read them.
        ///
        /// Called for you by `ManimLib.renderConfiguration`; exposed because
        /// an app that manages its own environment may want to apply a
        /// configuration without holding it in the shared property.
        ///
        /// The Python side reads these through libc rather than `os.environ`,
        /// so applying after the interpreter has started works.
        public func apply() {
            func put(_ name: String, _ value: String?) {
                if let value {
                    setenv(name, value, 1)
                } else {
                    unsetenv(name)
                }
            }
            put("OFFLINAI_MANIM_QUEUE_FRAMES", frameQueueDepth.map(String.init))
            put("OFFLINAI_MANIM_QUEUE_MB", String(max(frameQueueBudgetMB, 0)))
            put("OFFLINAI_MANIM_QUEUE_MIN", String(max(frameQueueMinimum, 1)))
            put("OFFLINAI_MANIM_QUEUE_MAX", String(max(frameQueueMaximum, 1)))
            put("OFFLINAI_MANIM_CODEC", videoCodec?.rawValue)
        }
    }

    /// The configuration a render will use. Assigning applies it.
    ///
    /// Safe to set at any point before a render starts, including after the
    /// interpreter is running — which is the normal shape, since an app
    /// usually starts Python long before the user picks a quality.
    ///
    /// This was not always true. Applying writes the process environment, and
    /// Python's `os.environ` is a snapshot taken when `os` was imported, so a
    /// `setenv` after `Py_Initialize` was invisible to it and the whole API
    /// was a silent no-op for any app that configured late. The Python side
    /// re-reads the live environment through libc at the start of each render.
    /// A value set from Python takes precedence over one set here.
    ///
    /// Changing it will not affect a render already under way.
    ///
    ///     ManimLib.renderConfiguration.frameQueueDepth = 8
    ///
    /// Not synchronised: like the rest of app startup, it expects to be
    /// touched from one thread before anything else is running.
    public nonisolated(unsafe) static var renderConfiguration = RenderConfiguration() {
        didSet { renderConfiguration.apply() }
    }
}
