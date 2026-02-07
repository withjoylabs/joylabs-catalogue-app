import AVFoundation
import os.log

/// Manages camera exposure compensation (EV bias), point-of-interest metering, and exposure lock.
/// Handles AVCaptureDevice configuration and UserDefaults persistence.
class CameraExposureManager {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CameraExposureManager")

    // MARK: - State

    private(set) var exposureBias: Float = 0.0  // -2 to +2 EV
    private(set) var isExposureLocked: Bool = false

    // Persistence keys
    private let biasKey = "com.joylabs.camera.exposureBias"
    private let lockKey = "com.joylabs.camera.exposureLocked"

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Device Configuration

    /// Configure manager with device and apply initial exposure settings
    func configure(with device: AVCaptureDevice) {
        applyExposureMode(to: device)
        logger.info("[Exposure] Device configured with bias \(self.exposureBias), locked: \(self.isExposureLocked)")
    }

    // MARK: - Exposure Control

    /// Set exposure bias (-2 to +2 EV)
    func setExposureBias(_ bias: Float, device: AVCaptureDevice) {
        exposureBias = max(-2, min(2, bias))
        applyBias(to: device)
        save()
    }

    // MARK: - Point-of-Interest Metering

    /// Meter exposure from a specific point (device coordinates, 0-1 range)
    func setExposurePoint(_ point: CGPoint, device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }

            // One-shot auto-expose at the tapped point — let it meter cleanly
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()

            logger.info("[Exposure] Metering at point (\(String(format: "%.2f", point.x)), \(String(format: "%.2f", point.y)))")

            // After metering settles, apply bias and the correct follow-up mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.applyBias(to: device)
                if self.isExposureLocked {
                    self.applyLockedMode(to: device)
                } else {
                    self.applyContinuousMode(to: device)
                }
            }
        } catch {
            logger.error("[Exposure] Failed to set exposure point: \(error)")
        }
    }

    // MARK: - Exposure Lock

    /// Toggle exposure lock on/off
    func toggleLock(device: AVCaptureDevice) {
        isExposureLocked.toggle()
        applyExposureMode(to: device)
        saveLock()
        logger.info("[Exposure] Lock toggled: \(self.isExposureLocked)")
    }

    /// Set exposure lock state explicitly
    func setLocked(_ locked: Bool, device: AVCaptureDevice) {
        isExposureLocked = locked
        applyExposureMode(to: device)
        saveLock()
    }

    // MARK: - Apply Exposure

    /// Apply only the EV bias without changing the exposure mode.
    /// Used by the slider to avoid resetting the auto-exposure algorithm on every tick.
    private func applyBias(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(exposureBias) { _ in }
            device.unlockForConfiguration()
        } catch {
            logger.error("[Exposure] Failed to apply bias: \(error)")
        }
    }

    /// Apply the full exposure mode (locked or continuous) and bias.
    /// Used by lock toggle and initial configuration — NOT by the slider.
    private func applyExposureMode(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if isExposureLocked {
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }

            device.setExposureTargetBias(exposureBias) { _ in }
            device.unlockForConfiguration()
        } catch {
            logger.error("[Exposure] Failed to apply exposure mode: \(error)")
        }
    }

    private func applyLockedMode(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("[Exposure] Failed to apply locked mode: \(error)")
        }
    }

    private func applyContinuousMode(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("[Exposure] Failed to restore continuous auto-exposure: \(error)")
        }
    }

    // MARK: - Persistence

    private func save() {
        UserDefaults.standard.set(exposureBias, forKey: biasKey)
    }

    private func saveLock() {
        UserDefaults.standard.set(isExposureLocked, forKey: lockKey)
    }

    private func load() {
        exposureBias = UserDefaults.standard.float(forKey: biasKey)
        isExposureLocked = UserDefaults.standard.bool(forKey: lockKey)
    }
}
