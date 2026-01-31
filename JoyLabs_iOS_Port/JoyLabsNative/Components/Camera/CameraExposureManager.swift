import AVFoundation
import os.log

/// Manages camera exposure compensation (EV bias)
/// Handles AVCaptureDevice configuration and UserDefaults persistence
class CameraExposureManager {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CameraExposureManager")

    // MARK: - State

    private(set) var exposureBias: Float = 0.0  // -2 to +2 EV

    // Persistence key
    private let biasKey = "com.joylabs.camera.exposureBias"

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Device Configuration

    /// Configure manager with device and apply initial exposure
    func configure(with device: AVCaptureDevice) {
        applyExposure(to: device)
        logger.info("[Exposure] Device configured with bias \(self.exposureBias)")
    }

    // MARK: - Exposure Control

    /// Set exposure bias (-2 to +2 EV)
    func setExposureBias(_ bias: Float, device: AVCaptureDevice) {
        exposureBias = max(-2, min(2, bias))
        applyExposure(to: device)
        save()
    }

    private func applyExposure(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                device.setExposureTargetBias(exposureBias) { _ in }
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("[Exposure] Failed to apply exposure: \(error)")
        }
    }

    // MARK: - Persistence

    private func save() {
        UserDefaults.standard.set(exposureBias, forKey: biasKey)
    }

    private func load() {
        exposureBias = UserDefaults.standard.float(forKey: biasKey)
    }
}
