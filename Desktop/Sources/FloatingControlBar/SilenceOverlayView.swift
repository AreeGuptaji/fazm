import SwiftUI

/// Overlay shown when PTT finishes with no speech detected.
/// Displays a mic picker and live audio level so the user can verify their mic works.
struct SilenceOverlayView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared
    var onDismiss: () -> Void

    private var selectedDeviceName: String {
        if let uid = deviceManager.selectedDeviceUID,
           let device = deviceManager.devices.first(where: { $0.uid == uid }) {
            return device.name
        }
        return "System Default"
    }

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

            if !deviceManager.devices.isEmpty {
                Menu {
                    Button("System Default") {
                        deviceManager.selectedDeviceUID = nil
                    }
                    Divider()
                    ForEach(deviceManager.devices) { device in
                        Button(device.name) {
                            deviceManager.selectedDeviceUID = device.uid
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10))
                        Text(selectedDeviceName)
                            .scaledFont(size: 12)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
            }

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
