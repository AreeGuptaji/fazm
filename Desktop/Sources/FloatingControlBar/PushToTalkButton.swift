import SwiftUI

/// A press-and-hold microphone button that triggers PushToTalkManager.
/// Uses an NSView overlay to reliably capture mouseDown/mouseUp events.
/// Passes the owning view's FloatingControlBarState so transcript syncs
/// to the correct window (floating bar or detached chat).
struct PushToTalkButton: View {
    @EnvironmentObject var state: FloatingControlBarState
    var isListening: Bool
    var iconSize: CGFloat = 18
    var frameSize: CGFloat = 28

    var body: some View {
        Image(systemName: isListening ? "mic.fill" : "mic")
            .scaledFont(size: iconSize)
            .foregroundColor(isListening ? .red : .secondary)
            .frame(width: frameSize, height: frameSize)
            .contentShape(Rectangle())
            .scaleEffect(isListening ? 1.15 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isListening)
            .overlay(PushToTalkMouseHandler(targetState: state))
            .help("Hold to talk")
    }
}

/// NSViewRepresentable that captures mouseDown/mouseUp for press-and-hold PTT.
private struct PushToTalkMouseHandler: NSViewRepresentable {
    let targetState: FloatingControlBarState

    func makeNSView(context: Context) -> PushToTalkMouseView {
        let view = PushToTalkMouseView()
        view.targetState = targetState
        return view
    }

    func updateNSView(_ nsView: PushToTalkMouseView, context: Context) {
        nsView.targetState = targetState
    }
}

/// Custom NSView that forwards mouse press/release to PushToTalkManager.
final class PushToTalkMouseView: NSView {
    var targetState: FloatingControlBarState?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let state = targetState
        Task { @MainActor in
            PushToTalkManager.shared.startUIListening(targetState: state)
        }
    }

    override func mouseUp(with event: NSEvent) {
        Task { @MainActor in
            PushToTalkManager.shared.finalizeUIListening()
        }
    }
}
