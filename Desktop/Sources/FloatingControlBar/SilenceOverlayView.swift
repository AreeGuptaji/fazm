import SwiftUI

/// Overlay shown on the floating bar when PTT finishes with no speech detected.
/// Displays a mic picker so the user can switch to a working input device.
struct SilenceOverlayView: View {
    @EnvironmentObject var state: FloatingControlBarState
    @ObservedObject private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))
                Text("No speech detected")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    state.dismissSilenceOverlay()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }

            if !deviceManager.devices.isEmpty {
                Picker("Microphone", selection: Binding(
                    get: { deviceManager.selectedDeviceUID ?? "" },
                    set: { deviceManager.selectedDeviceUID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default")
                        .tag("")
                    ForEach(deviceManager.devices) { device in
                        Text(device.name)
                            .tag(device.uid)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .scaledFont(size: 12)
            }
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
    }
}
