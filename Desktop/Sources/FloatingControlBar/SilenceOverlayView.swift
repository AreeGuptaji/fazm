import Cocoa
import SwiftUI

/// NSViewRepresentable wrapping NSPopUpButton for reliable dropdown in borderless panels.
private struct MicPopUpButton: NSViewRepresentable {
    @ObservedObject var deviceManager: AudioDeviceManager

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 12)
        // Style for dark background
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        updateItems(button)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let currentSelection = deviceManager.selectedDeviceUID ?? ""
        updateItems(button)
        // Re-select the current device
        if currentSelection.isEmpty {
            button.selectItem(at: 0)
        } else if let index = deviceManager.devices.firstIndex(where: { $0.uid == currentSelection }) {
            button.selectItem(at: index + 1) // +1 for "System Default"
        }
    }

    private func updateItems(_ button: NSPopUpButton) {
        button.removeAllItems()
        button.addItem(withTitle: "System Default")
        for device in deviceManager.devices {
            button.addItem(withTitle: device.name)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(deviceManager: deviceManager)
    }

    class Coordinator: NSObject {
        let deviceManager: AudioDeviceManager

        init(deviceManager: AudioDeviceManager) {
            self.deviceManager = deviceManager
        }

        @MainActor @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            if index == 0 {
                deviceManager.selectedDeviceUID = nil
            } else {
                let deviceIndex = index - 1
                if deviceIndex < deviceManager.devices.count {
                    deviceManager.selectedDeviceUID = deviceManager.devices[deviceIndex].uid
                }
            }
        }
    }
}

/// Overlay shown when PTT finishes with no speech detected.
/// Displays a mic picker and live audio level so the user can verify their mic works.
struct SilenceOverlayView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))
                Text("Didn't catch that — try a different mic?")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }

            // Native NSPopUpButton for reliable dropdown in borderless panel
            MicPopUpButton(deviceManager: deviceManager)
                .frame(height: 24)

            AudioLevelBarsSettingsView(level: deviceManager.currentAudioLevel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(8)
        .onAppear { deviceManager.startLevelMonitoring() }
        .onDisappear { deviceManager.stopLevelMonitoring() }
    }
}
