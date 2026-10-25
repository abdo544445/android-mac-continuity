import SwiftUI
import AppKit
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
        .onAppear {
            if agent.isPairingSheetVisible {
                openPairingSheet()
            }
        }
        .onChange(of: agent.isPairingSheetVisible) { newValue in
            if newValue && !showPairingModal {
                openPairingSheet()
            } else if !newValue && showPairingModal {
                showPairingModal = false
            }
        }
        .sheet(isPresented: $showPairingModal, onDismiss: {
            agent.isPairingSheetVisible = false
        }) {
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
        VStack(spacing: 16) {
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
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                ProgressView()
                    .frame(width: 220, height: 220)
            }

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Verification PIN")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pairingPin)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .tracking(4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                VStack(spacing: 4) {
                    Text("Mac IP & Port")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(agent.getLocalIPAddress()):52400")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            HStack(spacing: 12) {
                Button("Copy Pairing URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pairingUri, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    showPairingModal = false
                    agent.isPairingSheetVisible = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 460, height: 500)
    }

    private func openPairingSheet() {
        let sessionData = agent.preparePairingSession()
        self.pairingPin = sessionData.pin
        self.pairingUri = sessionData.qrString
        self.qrImage = generateQRCode(from: sessionData.qrString)
        self.showPairingModal = true
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputCIImage = filter.outputImage else { return nil }
        // Scale up 10x with nearest-neighbor so QR modules are razor-sharp for phone cameras
        let transformed = outputCIImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}
