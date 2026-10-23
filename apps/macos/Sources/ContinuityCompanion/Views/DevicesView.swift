import SwiftUI
import CoreImage.CIFilterBuiltins
import ContinuityProtocol

public struct DevicesView: View {
    @ObservedObject var registry = DeviceRegistry.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @State private var qrImage: NSImage?
    @State private var pairingPin: String = ""
    @State private var pairingUri: String = ""
    @State private var showPairingModal = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Paired Devices")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { openPairingSheet() }) {
                    Label("Pair New Android Phone", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if registry.pairedDevices.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 54))
                        .foregroundColor(.secondary)
                    Text("No Paired Devices")
                        .font(.headline)
                    Text("Pair your Android phone securely by scanning a short-lived QR code. No Google or Apple accounts required.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)

                    Button("Pair Phone Now") {
                        openPairingSheet()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(registry.pairedDevices) { device in
                        deviceRow(device: device)
                    }
                }
            }
        }
        .sheet(isPresented: $showPairingModal) {
            pairingSheetView()
        }
    }

    private func deviceRow(device: PairedDevice) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 32))
                .foregroundColor(device.isConnected ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(device.edition == .advanced ? "Advanced Edition" : "Public Edition")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }

                HStack(spacing: 12) {
                    Text("Paired \(device.pairedAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(device.isConnected ? "Connected" : "Offline")
                        .font(.caption)
                        .foregroundColor(device.isConnected ? .green : .secondary)
                }
            }

            Spacer()

            Button("Unpair") {
                registry.removeDevice(deviceId: device.deviceId)
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
        .padding(.vertical, 8)
    }

    private func pairingSheetView() -> some View {
        VStack(spacing: 20) {
            Text("Scan QR Code to Pair")
                .font(.title2)
                .fontWeight(.bold)

            Text("Open the Continuity app on your Android phone and scan this code.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let img = qrImage {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .background(Color.white)
                    .cornerRadius(12)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                ProgressView()
                    .frame(width: 220, height: 220)
            }

            VStack(spacing: 6) {
                Text("Verification PIN")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(pairingPin)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .tracking(6)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack {
                Button("Done") {
                    showPairingModal = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 440, height: 480)
    }

    private func openPairingSheet() {
        let sessionData = agent.preparePairingSession()
        self.pairingPin = sessionData.pin
        self.pairingUri = sessionData.qrString
        self.qrImage = generateQRCode(from: sessionData.qrString)
        self.showPairingModal = true
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputCIImage = filter.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: outputCIImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
