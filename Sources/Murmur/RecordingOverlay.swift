import SwiftUI
import AppKit

/// Floating on-screen indicator shown while the push-to-talk key is held.
///
/// A borderless, non-activating, click-through panel that floats above every
/// app and space, bottom-center of the screen. Green + waveform = recording;
/// orange = the key was pressed while the pipeline wasn't ready (model still
/// loading or a previous dictation still processing).
@MainActor
final class RecordingOverlay {
    enum State {
        case listening
        case notReady
    }

    private var panel: NSPanel?

    /// - Parameter level: live microphone level (0…1) source, sampled every
    ///   frame by the flowing waveform. Only meaningful for `.listening`.
    func show(_ state: State, level: @escaping () -> Float = { 0 }) {
        hideImmediately()

        let hosting = NSHostingView(rootView: OverlayView(state: state, level: level))
        let size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting

        if let screen = Self.activeScreen {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 100
            ))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func hideImmediately() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// The screen the user is actually working on. For a menu-bar app,
    /// NSScreen.main follows the key window (which we never have), so on
    /// multi-display setups it can be the wrong monitor. The pointer's screen
    /// is the best proxy for where the focused text field is.
    private static var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
    }
}

/// The capsule itself: pulsing mic halo, animated waveform bars, status label.
private struct OverlayView: View {
    let state: RecordingOverlay.State
    let level: () -> Float
    @State private var pulsing = false

    private var color: Color { state == .listening ? .green : .orange }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulsing ? 1.5 : 0.9)
                    .opacity(pulsing ? 0.15 : 0.6)
                Image(systemName: state == .listening ? "mic.fill" : "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            if state == .listening {
                FlowingWaveform(color: color, level: level)
            }

            Text(state == .listening ? "Listening…" : "Not ready yet…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(16) // breathing room so the shadow isn't clipped by the panel edge
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

/// Siri-style flowing waveform: overlapping sine waves that drift at different
/// speeds and swell with the live microphone level. Rendered every frame via
/// `TimelineView(.animation)` + `Canvas` so the motion is continuous and smooth
/// rather than a stepped implicit animation.
private struct FlowingWaveform: View {
    let color: Color
    let level: () -> Float

    // Frame-to-frame smoothing state; a reference type so mutating it during
    // Canvas rendering doesn't invalidate SwiftUI state every frame.
    @State private var display = LevelBox()

    // Per-wave parameters: (relative speed, wavelength, amplitude scale, opacity).
    private let waves: [(speed: Double, wavelength: Double, amp: CGFloat, opacity: Double)] = [
        (2.2, 22, 1.00, 1.00),
        (1.5, 30, 0.75, 0.55),
        (3.1, 16, 0.55, 0.35),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let dt = display.lastTime == 0 ? 0 : now - display.lastTime
                display.lastTime = now
                // ~90ms time constant.
                let k = Float(1 - exp(-dt / 0.09))
                display.value += (level() - display.value) * k

                // A little idle breathing so it never looks frozen in silence,
                // plus the voice-driven swell on top.
                let idle = 0.12 + 0.05 * sin(now * 1.6)
                let strength = CGFloat(idle) + CGFloat(display.value)
                let maxAmp = size.height / 2 - 1

                for wave in waves {
                    let amp = min(maxAmp, maxAmp * wave.amp * strength)
                    let path = wavePath(size: size, time: now, wave: wave, amplitude: amp)
                    // Per-wave opacity is folded into the gradient colours since a
                    // GraphicsContext stroke returns no chainable view modifier.
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                color.opacity(0.15 * wave.opacity),
                                color.opacity(wave.opacity),
                                color.opacity(0.15 * wave.opacity),
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        lineWidth: 2
                    )
                }
            }
        }
        .frame(width: 62, height: 22)
    }

    private func wavePath(
        size: CGSize,
        time: Double,
        wave: (speed: Double, wavelength: Double, amp: CGFloat, opacity: Double),
        amplitude: CGFloat
    ) -> Path {
        var path = Path()
        let midY = size.height / 2
        let step: CGFloat = 1.5
        var x: CGFloat = 0
        while x <= size.width {
            let rel = Double(x / size.width)
            // Envelope tapers both ends to the midline, so the waves appear to
            // emanate from the centre the way Siri's do.
            let envelope = sin(rel * .pi)
            let y = Double(midY) + sin(Double(x) / wave.wavelength - time * wave.speed)
                * Double(amplitude) * envelope
            let point = CGPoint(x: x, y: y)
            if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
            x += step
        }
        return path
    }
}

/// Reference-type scratch space for the waveform's frame-to-frame smoothing.
/// A class so `Canvas` can mutate it during rendering without triggering a
/// SwiftUI state invalidation each frame.
private final class LevelBox {
    var value: Float = 0
    var lastTime: TimeInterval = 0
}
