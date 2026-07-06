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

    func show(_ state: State) {
        hideImmediately()

        let hosting = NSHostingView(rootView: OverlayView(state: state))
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

        if let screen = NSScreen.main {
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
}

/// The capsule itself: pulsing mic halo, animated waveform bars, status label.
private struct OverlayView: View {
    let state: RecordingOverlay.State
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
                WaveformBars(color: color)
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

private struct WaveformBars: View {
    let color: Color
    @State private var animating = false

    private let heights: [CGFloat] = [8, 16, 11, 20, 9]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: animating ? heights[index] : 4)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .frame(height: 22)
        .onAppear { animating = true }
    }
}
