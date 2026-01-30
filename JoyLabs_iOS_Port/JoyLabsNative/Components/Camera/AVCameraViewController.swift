import UIKit
import AVFoundation
import SwiftUI
import os.log

/// Custom AVFoundation camera with manual exposure control and multi-photo capture buffer
/// Exposure bias persists across app sessions via UserDefaults
class AVCameraViewController: UIViewController {

    // MARK: - Properties

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    // Photo buffer for multi-capture
    private var capturedPhotos: [UIImage] = []

    // Photo editor state
    private var pendingEditImage: UIImage?
    private let presetManager = PhotoAdjustmentsPresetManager.shared

    // Callbacks
    var onPhotosCaptured: (([UIImage]) -> Void)?
    var onCancel: (() -> Void)?
    var contextTitle: String?

    // Capture button constraint references for orientation-based layout
    private var captureButtonBottomConstraint: NSLayoutConstraint?
    private var captureButtonCenterXConstraint: NSLayoutConstraint?
    private var captureButtonTrailingConstraint: NSLayoutConstraint?
    private var captureButtonCenterYConstraint: NSLayoutConstraint?

    // Badge constraint references for orientation-based layout
    private var badgeTrailingConstraint: NSLayoutConstraint?
    private var badgeCenterYConstraint: NSLayoutConstraint?
    private var badgeBottomConstraint: NSLayoutConstraint?
    private var badgeCenterXConstraint: NSLayoutConstraint?

    // Buffer constraint references for orientation-based layout
    private var bufferBottomToButtonConstraint: NSLayoutConstraint?
    private var bufferBottomToViewConstraint: NSLayoutConstraint?

    // Preset button constraint references for orientation-based layout
    private var presetLeadingConstraint: NSLayoutConstraint?
    private var presetCenterYConstraint: NSLayoutConstraint?
    private var presetTopConstraint: NSLayoutConstraint?
    private var presetCenterXConstraint: NSLayoutConstraint?

    // Camera configuration state
    private var isCameraConfigured = false

    // Loading indicator
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // Exposure persistence
    private let exposureBiasKey = "com.joylabs.camera.exposureBias"
    private var savedExposureBias: Float {
        get { UserDefaults.standard.float(forKey: exposureBiasKey) }
        set { UserDefaults.standard.set(newValue, forKey: exposureBiasKey) }
    }

    // UI Components
    private lazy var previewView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var exposureSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = -2.0
        slider.maximumValue = 2.0
        slider.value = savedExposureBias
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(exposureSliderChanged(_:)), for: .valueChanged)
        return slider
    }()

    private lazy var exposureIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "sun.max.fill"))
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var exposureValueLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(format: "%+.1f", savedExposureBias)
        return label
    }()

    private lazy var captureButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Outer ring (white stroke)
        let outerRing = CAShapeLayer()
        outerRing.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 70, height: 70)).cgPath
        outerRing.strokeColor = UIColor.white.cgColor
        outerRing.fillColor = UIColor.clear.cgColor
        outerRing.lineWidth = 3
        button.layer.addSublayer(outerRing)

        // Inner circle (white fill)
        let innerCircle = CAShapeLayer()
        innerCircle.path = UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 60, height: 60)).cgPath
        innerCircle.fillColor = UIColor.white.cgColor
        button.layer.addSublayer(innerCircle)

        // Shadow for depth
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4

        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        return button
    }()

    private lazy var doneButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Upload"
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.cornerStyle = .medium

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var contextTitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.text = contextTitle ?? "Camera"
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        return label
    }()

    private lazy var photoCountBadge: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemRed
        container.layer.cornerRadius = 12
        container.isHidden = true  // Hidden when count is 0

        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 999  // Tag to find label later
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            container.heightAnchor.constraint(equalToConstant: 24)
        ])

        return container
    }()

    private lazy var thumbnailScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.8)
        scrollView.layer.cornerRadius = 8
        scrollView.layer.borderWidth = 1
        scrollView.layer.borderColor = UIColor.systemGray4.cgColor
        return scrollView
    }()

    private lazy var thumbnailStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var bufferEmptyPlaceholder: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "photo.stack"))
        icon.tintColor = .secondaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Photos appear here"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false

        // Vertical stack for better centering
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32)
        ])

        return container
    }()

    private lazy var presetIndicatorButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "wand.and.stars")
        config.title = "Preset"
        config.imagePadding = 4
        config.baseForegroundColor = .white
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            return outgoing
        }

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(presetIndicatorTapped), for: .touchUpInside)
        return button
    }()

    private lazy var headerBackgroundView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let effectView = UIVisualEffectView(effect: blurEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = 12
        effectView.clipsToBounds = true
        return effectView
    }()

    private lazy var exposureControlsContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.6)
        container.layer.cornerRadius = 8
        // Size: icon(24) + spacing(4) + label(20) + spacing(8) + sliderHeight(200) + spacing(8) = 264pt height
        // Width: 64pt to encompass label (50pt centered at +28, spans +3 to +53) with padding
        return container
    }()

    private let logger = Logger(subsystem: "com.joylabs.native", category: "AVCameraViewController")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemGroupedBackground

        setupUI()
        setupLoadingIndicator()

        // Configure camera asynchronously to avoid blocking UI presentation
        showCameraLoading(true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupCamera()
        }
    }

    private func setupLoadingIndicator() {
        previewView.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: previewView.centerYAnchor)
        ])
    }

    private func showCameraLoading(_ show: Bool) {
        DispatchQueue.main.async { [weak self] in
            if show {
                self?.loadingIndicator.startAnimating()
                self?.captureButton.isEnabled = false
                self?.captureButton.alpha = 0.5
            } else {
                self?.loadingIndicator.stopAnimating()
                self?.captureButton.isEnabled = true
                self?.captureButton.alpha = 1.0
            }
        }
    }

    deinit {
        rotationObservation?.invalidate()
    }

    private func updatePreviewRotation() {
        guard let connection = previewLayer?.connection,
              let coordinator = rotationCoordinator else { return }

        let rotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        connection.videoRotationAngle = rotationAngle
    }

    private func setupRotationObservation() {
        guard let coordinator = rotationCoordinator else { return }

        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updatePreviewRotation()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Only start if configured and not already running
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.isCameraConfigured, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Stop synchronously to ensure clean state before next open
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Disable slider during rotation to prevent tracking warnings
        exposureSlider.isUserInteractionEnabled = false
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.exposureSlider.isUserInteractionEnabled = true
        }
    }

    private func updateLayoutForOrientation() {
        let isPortrait = view.bounds.height > view.bounds.width

        // Deactivate all orientation-specific constraints
        NSLayoutConstraint.deactivate([
            captureButtonBottomConstraint,
            captureButtonCenterXConstraint,
            captureButtonTrailingConstraint,
            captureButtonCenterYConstraint,
            badgeTrailingConstraint,
            badgeCenterYConstraint,
            badgeBottomConstraint,
            badgeCenterXConstraint,
            bufferBottomToButtonConstraint,
            bufferBottomToViewConstraint,
            presetLeadingConstraint,
            presetCenterYConstraint,
            presetTopConstraint,
            presetCenterXConstraint
        ].compactMap { $0 })

        if isPortrait {
            // Portrait mode: Button at bottom center, badge to left, preset to right
            NSLayoutConstraint.activate([
                captureButtonBottomConstraint!,
                captureButtonCenterXConstraint!,
                badgeTrailingConstraint!,
                badgeCenterYConstraint!,
                presetLeadingConstraint!,
                presetCenterYConstraint!
            ])
        } else {
            // Landscape mode: Button on right side vertical center, badge above, preset below
            NSLayoutConstraint.activate([
                captureButtonTrailingConstraint!,
                captureButtonCenterYConstraint!,
                badgeBottomConstraint!,
                badgeCenterXConstraint!,
                bufferBottomToViewConstraint!,
                presetTopConstraint!,
                presetCenterXConstraint!
            ])
        }
    }

    // MARK: - Setup

    private func setupUI() {
        // Preview (square aspect ratio)
        view.addSubview(previewView)
        previewView.layer.cornerRadius = 12
        previewView.clipsToBounds = true

        // Exposure controls container (background)
        view.addSubview(exposureControlsContainer)

        // Exposure slider with icon and value label
        view.addSubview(exposureIcon)
        view.addSubview(exposureValueLabel)
        view.addSubview(exposureSlider)

        // Capture button
        view.addSubview(captureButton)

        // Header background
        view.addSubview(headerBackgroundView)

        // Top bar with cancel, title, done
        view.addSubview(cancelButton)
        view.addSubview(contextTitleLabel)
        view.addSubview(doneButton)

        // Photo count badge on capture button
        view.addSubview(photoCountBadge)

        // Thumbnail buffer
        view.addSubview(thumbnailScrollView)
        thumbnailScrollView.addSubview(thumbnailStackView)
        view.addSubview(bufferEmptyPlaceholder)  // Add to view for proper centering

        // Preset indicator
        view.addSubview(presetIndicatorButton)

        // Calculate FIXED viewport size that fits BOTH iPad orientations
        // Use connected scenes to get screen bounds (iOS 26+ compatible)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let screenBounds = windowScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 768, height: 1024)
        let shortDimension = min(screenBounds.width, screenBounds.height)
        let viewportSize: CGFloat

        if isPhone {
            // iPhone: Always portrait, use screen width
            viewportSize = shortDimension - 32
        } else {
            // iPad: Must fit in BOTH portrait AND landscape
            // Portrait: limited by width
            let portraitLimit = shortDimension - 32
            // Landscape: limited by height (short dimension minus UI elements)
            // UI = header(60) + bufferSpacing(16) + buffer(80) + bottom(20) + safeArea(~40) = 216
            let landscapeLimit = shortDimension - 216
            viewportSize = min(portraitLimit, landscapeLimit)
        }

        NSLayoutConstraint.activate([
            // Preview - FIXED square viewport (never changes on rotation)
            previewView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            previewView.widthAnchor.constraint(equalToConstant: viewportSize),
            previewView.heightAnchor.constraint(equalToConstant: viewportSize),

            // Header background
            headerBackgroundView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            headerBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            headerBackgroundView.heightAnchor.constraint(equalToConstant: 50),

            // Top bar
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            contextTitleLabel.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            contextTitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contextTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 8),
            contextTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -4),

            doneButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // Capture button - size only (position set dynamically based on orientation)
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),

            // Thumbnail buffer - edge-to-edge (bottom constraint set dynamically based on orientation)
            thumbnailScrollView.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 16),
            thumbnailScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailScrollView.heightAnchor.constraint(equalToConstant: 80),

            thumbnailStackView.topAnchor.constraint(equalTo: thumbnailScrollView.topAnchor),
            thumbnailStackView.leadingAnchor.constraint(equalTo: thumbnailScrollView.leadingAnchor),
            thumbnailStackView.trailingAnchor.constraint(equalTo: thumbnailScrollView.trailingAnchor),
            thumbnailStackView.bottomAnchor.constraint(equalTo: thumbnailScrollView.bottomAnchor),
            thumbnailStackView.heightAnchor.constraint(equalTo: thumbnailScrollView.heightAnchor),

            // Buffer empty placeholder - centered using view anchors (not scrollview content)
            bufferEmptyPlaceholder.widthAnchor.constraint(equalTo: view.widthAnchor),
            bufferEmptyPlaceholder.heightAnchor.constraint(equalToConstant: 80),
            bufferEmptyPlaceholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bufferEmptyPlaceholder.centerYAnchor.constraint(equalTo: thumbnailScrollView.centerYAnchor),

            // Exposure controls container - overlaid on LEFT side of viewport
            exposureControlsContainer.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            exposureControlsContainer.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            exposureControlsContainer.widthAnchor.constraint(equalToConstant: 64),
            exposureControlsContainer.heightAnchor.constraint(equalToConstant: 300),

            // Exposure controls - all positioned relative to container (self-contained)
            exposureIcon.bottomAnchor.constraint(equalTo: exposureSlider.centerYAnchor, constant: -120),
            exposureIcon.centerXAnchor.constraint(equalTo: exposureControlsContainer.centerXAnchor),
            exposureIcon.widthAnchor.constraint(equalToConstant: 24),
            exposureIcon.heightAnchor.constraint(equalToConstant: 24),

            exposureValueLabel.topAnchor.constraint(equalTo: exposureIcon.bottomAnchor, constant: 4),
            exposureValueLabel.centerXAnchor.constraint(equalTo: exposureControlsContainer.centerXAnchor),
            exposureValueLabel.widthAnchor.constraint(equalToConstant: 50),

            // Slider centered in container (offset down slightly for icon/value above)
            exposureSlider.centerYAnchor.constraint(equalTo: exposureControlsContainer.centerYAnchor, constant: 20),
            exposureSlider.centerXAnchor.constraint(equalTo: exposureControlsContainer.centerXAnchor),
            exposureSlider.widthAnchor.constraint(equalToConstant: 200),

            // Preset indicator - height only, width determined by content (position set dynamically)
            presetIndicatorButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Setup orientation-based constraints (updated dynamically in updateLayoutForOrientation)
        captureButtonBottomConstraint = captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        captureButtonCenterXConstraint = captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        captureButtonTrailingConstraint = captureButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        captureButtonCenterYConstraint = captureButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)

        badgeTrailingConstraint = photoCountBadge.trailingAnchor.constraint(equalTo: captureButton.leadingAnchor, constant: -12)
        badgeCenterYConstraint = photoCountBadge.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
        badgeBottomConstraint = photoCountBadge.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -8)
        badgeCenterXConstraint = photoCountBadge.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor)

        bufferBottomToButtonConstraint = thumbnailScrollView.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -16)
        bufferBottomToViewConstraint = thumbnailScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        // Lower priority to avoid conflicts during rotation (viewport height is fixed)
        bufferBottomToViewConstraint?.priority = .defaultHigh

        // Preset button constraints - next to capture button
        // Portrait: to the right of capture button
        presetLeadingConstraint = presetIndicatorButton.leadingAnchor.constraint(equalTo: captureButton.trailingAnchor, constant: 12)
        presetCenterYConstraint = presetIndicatorButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
        // Landscape: below capture button
        presetTopConstraint = presetIndicatorButton.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 8)
        presetCenterXConstraint = presetIndicatorButton.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor)

        // Rotate exposure slider vertically
        exposureSlider.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)

        // Bring UI elements to front (proper Z-order)
        view.bringSubviewToFront(thumbnailScrollView)
        view.bringSubviewToFront(captureButton)
        view.bringSubviewToFront(photoCountBadge)
        view.bringSubviewToFront(headerBackgroundView)
        view.bringSubviewToFront(cancelButton)
        view.bringSubviewToFront(contextTitleLabel)
        view.bringSubviewToFront(doneButton)
        view.bringSubviewToFront(exposureControlsContainer)
        view.bringSubviewToFront(exposureIcon)
        view.bringSubviewToFront(exposureValueLabel)
        view.bringSubviewToFront(exposureSlider)
        view.bringSubviewToFront(presetIndicatorButton)

        // Set initial orientation layout
        updateLayoutForOrientation()
        updateBufferCount()
        updatePresetIndicator()
    }

    private func setupCamera() {
        // Check camera authorization
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    // Stay on background thread for configuration
                    self?.configureCamera()
                } else {
                    self?.logger.error("Camera access denied")
                    self?.showCameraLoading(false)
                }
            }
        default:
            logger.error("Camera access denied or restricted")
            showCameraLoading(false)
        }
    }

    private func configureCamera() {
        // Guard against re-configuration
        guard !isCameraConfigured else {
            showCameraLoading(false)
            return
        }

        captureSession.beginConfiguration()

        // Set session preset
        captureSession.sessionPreset = .photo

        // Add camera input (guard against re-adding)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            logger.error("Failed to get camera device")
            captureSession.commitConfiguration()
            showCameraLoading(false)
            return
        }

        currentDevice = camera

        // Only add input if not already added
        if captureSession.inputs.isEmpty {
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
            } catch {
                logger.error("Failed to create camera input: \(error.localizedDescription)")
                captureSession.commitConfiguration()
                showCameraLoading(false)
                return
            }
        }

        // Only add output if not already added
        if captureSession.outputs.isEmpty {
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
        }

        captureSession.commitConfiguration()

        // Setup preview layer on main thread (UI operation)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = self.previewView.bounds
            self.previewView.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer

            // Create rotation coordinator with preview layer reference
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)

            // Set initial rotation and observe changes
            self.updatePreviewRotation()
            self.setupRotationObservation()
        }

        // Apply saved exposure bias
        applyExposureBias(savedExposureBias)

        // Mark as configured and start session
        isCameraConfigured = true

        // Start running immediately after configuration
        if !captureSession.isRunning {
            captureSession.startRunning()
        }

        // Hide loading indicator
        showCameraLoading(false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Update preview layer frame
        previewLayer?.frame = previewView.bounds

        // Update button/badge layout for orientation (iPad only uses this)
        updateLayoutForOrientation()
    }

    // MARK: - Exposure Control

    @objc private func exposureSliderChanged(_ slider: UISlider) {
        // Snap to 0.1 increments
        let roundedBias = round(slider.value * 10) / 10
        slider.value = roundedBias // Update slider to snapped value

        // Update exposure value label
        exposureValueLabel.text = String(format: "%+.1f", roundedBias)

        applyExposureBias(roundedBias)
        savedExposureBias = roundedBias // Persist immediately
    }

    private func applyExposureBias(_ bias: Float) {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.setExposureTargetBias(bias) { _ in }
            }

            device.unlockForConfiguration()
            logger.info("Applied exposure bias: \(bias)")
        } catch {
            logger.error("Failed to set exposure: \(error.localizedDescription)")
        }
    }

    // MARK: - Photo Capture

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()

        // iOS 17+ standard: Set rotation angle on photo output connection for correct orientation
        if let photoConnection = photoOutput.connection(with: .video),
           let coordinator = rotationCoordinator {
            let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            photoConnection.videoRotationAngle = captureAngle
            logger.info("[Camera] Set capture rotation angle: \(captureAngle)°")
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func addPhotoToBuffer(_ image: UIImage) {
        capturedPhotos.append(image)
        updateBufferCount()
        addThumbnail(image)
    }

    private func addThumbnail(_ image: UIImage) {
        let thumbnailContainer = UIView()
        thumbnailContainer.translatesAutoresizingMaskIntoConstraints = false
        thumbnailContainer.widthAnchor.constraint(equalToConstant: 80).isActive = true
        thumbnailContainer.heightAnchor.constraint(equalToConstant: 80).isActive = true
        thumbnailContainer.tag = capturedPhotos.count - 1  // Track index for tap

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        thumbnailContainer.addSubview(imageView)

        // Tap gesture for fullscreen preview
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(thumbnailTapped(_:)))
        imageView.addGestureRecognizer(tapGesture)

        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        deleteButton.tintColor = .white
        deleteButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        deleteButton.layer.cornerRadius = 12
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.tag = capturedPhotos.count - 1 // Track index
        deleteButton.addTarget(self, action: #selector(deleteThumbnail(_:)), for: .touchUpInside)
        thumbnailContainer.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: thumbnailContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: thumbnailContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: thumbnailContainer.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: thumbnailContainer.bottomAnchor),

            deleteButton.topAnchor.constraint(equalTo: thumbnailContainer.topAnchor, constant: 4),
            deleteButton.trailingAnchor.constraint(equalTo: thumbnailContainer.trailingAnchor, constant: -4),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        thumbnailStackView.addArrangedSubview(thumbnailContainer)

        // Scroll to show new thumbnail
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let rightEdge = self.thumbnailScrollView.contentSize.width - self.thumbnailScrollView.bounds.width
            self.thumbnailScrollView.setContentOffset(CGPoint(x: max(0, rightEdge), y: 0), animated: true)
        }
    }

    @objc private func thumbnailTapped(_ gesture: UITapGestureRecognizer) {
        guard let imageView = gesture.view,
              let container = imageView.superview,
              container.tag < capturedPhotos.count else { return }

        let image = capturedPhotos[container.tag]
        let previewVC = PhotoPreviewViewController(image: image)
        present(previewVC, animated: true)
    }

    @objc private func deleteThumbnail(_ button: UIButton) {
        let index = button.tag
        guard index < capturedPhotos.count else { return }

        // Remove from data
        capturedPhotos.remove(at: index)

        // Remove thumbnail view
        if index < thumbnailStackView.arrangedSubviews.count {
            let thumbnailView = thumbnailStackView.arrangedSubviews[index]
            thumbnailStackView.removeArrangedSubview(thumbnailView)
            thumbnailView.removeFromSuperview()

            // Update tags for remaining thumbnails (both container and delete button)
            for (newIndex, view) in thumbnailStackView.arrangedSubviews.enumerated() {
                view.tag = newIndex  // Container tag for tap gesture
                if let deleteBtn = view.subviews.compactMap({ $0 as? UIButton }).first {
                    deleteBtn.tag = newIndex
                }
            }
        }

        updateBufferCount()
    }

    private func updateBufferCount() {
        let count = capturedPhotos.count

        // Update badge
        if let badgeLabel = photoCountBadge.viewWithTag(999) as? UILabel {
            badgeLabel.text = "\(count)"
        }
        photoCountBadge.isHidden = count == 0

        // Update done button
        doneButton.isEnabled = !capturedPhotos.isEmpty
        doneButton.alpha = capturedPhotos.isEmpty ? 0.5 : 1.0

        // Update configuration for color change
        var config = doneButton.configuration ?? UIButton.Configuration.filled()
        config.baseBackgroundColor = capturedPhotos.isEmpty ? .systemGray : .systemBlue
        doneButton.configuration = config

        // Show/hide empty state placeholder
        bufferEmptyPlaceholder.isHidden = !capturedPhotos.isEmpty
    }

    // MARK: - Preset Management

    private func updatePresetIndicator() {
        let hasPreset = presetManager.hasPreset
        var config = presetIndicatorButton.configuration
        config?.baseForegroundColor = hasPreset ? .systemYellow : .white
        presetIndicatorButton.configuration = config
    }

    @objc private func presetIndicatorTapped() {
        if presetManager.hasPreset {
            // Show action sheet to manage preset
            let alert = UIAlertController(title: "Photo Preset", message: "A filter preset is saved and will be applied to photos automatically.", preferredStyle: .actionSheet)

            alert.addAction(UIAlertAction(title: "Edit Preset", style: .default) { [weak self] _ in
                self?.showPresetEditor()
            })

            alert.addAction(UIAlertAction(title: "Clear Preset", style: .destructive) { [weak self] _ in
                self?.presetManager.clearPreset()
                self?.updatePresetIndicator()
            })

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

            // For iPad, set the popover source
            if let popover = alert.popoverPresentationController {
                popover.sourceView = presetIndicatorButton
                popover.sourceRect = presetIndicatorButton.bounds
            }

            present(alert, animated: true)
        } else {
            // No preset - show info
            let alert = UIAlertController(title: "No Preset Saved", message: "Take a photo and enable 'Apply to future photos' in the editor to save a preset.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func showPresetEditor() {
        // Create a sample image to show in editor (use last captured or a placeholder)
        let sampleImage = capturedPhotos.last ?? createPlaceholderImage()

        let editorView = PhotoEditorView(
            originalImage: sampleImage,
            onConfirm: { [weak self] _ in
                // Preset is saved inside the editor when "Apply to future" is enabled
                self?.dismiss(animated: true)
                self?.updatePresetIndicator()
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )

        let hostingController = UIHostingController(rootView: editorView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    private func createPlaceholderImage() -> UIImage {
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let text = "Preview"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .medium),
                .foregroundColor: UIColor.lightGray
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }

    /// Handle captured photo - either auto-apply preset or show editor
    private func handleCapturedPhoto(_ image: UIImage) {
        if let preset = presetManager.savedPreset, !preset.isDefault {
            // Auto-apply saved preset (synchronous - Metal GPU makes this fast)
            logger.info("[Camera] Auto-applying saved preset to photo")
            let processed = PhotoFilterService.shared.apply(preset, to: image)
            addPhotoToBuffer(processed)
            logger.info("[Camera] Photo processed with preset and added to buffer")
        } else {
            // Show editor for manual adjustment
            showPhotoEditor(for: image)
        }
    }

    private func showPhotoEditor(for image: UIImage) {
        let editorView = PhotoEditorView(
            originalImage: image,
            onConfirm: { [weak self] editedImage in
                self?.dismiss(animated: true)
                self?.addPhotoToBuffer(editedImage)
                self?.updatePresetIndicator()
                self?.logger.info("[Camera] Photo edited and added to buffer")
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
                // Discard the photo if user cancels editing
                self?.logger.info("[Camera] Photo editing cancelled, photo discarded")
            }
        )

        let hostingController = UIHostingController(rootView: editorView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    // MARK: - Actions

    @objc private func doneButtonTapped() {
        guard !capturedPhotos.isEmpty else { return }
        onPhotosCaptured?(capturedPhotos)
    }

    @objc private func cancelButtonTapped() {
        onCancel?()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

// MARK: - Photo Preview Controller (Fullscreen with Pinch-to-Zoom)

class PhotoPreviewViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupScrollView()
        setupImageView()
        setupGestures()
        setupCloseButton()
    }

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupImageView() {
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    private func setupGestures() {
        // Double tap to zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap to dismiss
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(dismissPreview))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
    }

    private func setupCloseButton() {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(dismissPreview), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.0 {
            scrollView.setZoomScale(1.0, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let zoomRect = CGRect(
                x: point.x - 50,
                y: point.y - 50,
                width: 100,
                height: 100
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func dismissPreview() {
        dismiss(animated: true)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

extension AVCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            logger.error("Photo capture error: \(error.localizedDescription)")
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            logger.error("Failed to create image from photo data")
            return
        }

        // Crop to square using shorter dimension
        let croppedImage = cropToSquare(image)

        DispatchQueue.main.async {
            // Route through editor or auto-apply preset
            self.handleCapturedPhoto(croppedImage)
        }
    }

    /// Crop image to square aspect ratio using shorter dimension (center crop)
    /// CRITICAL: Normalizes orientation FIRST because CGImage.cropping operates on raw pixels
    private func cropToSquare(_ image: UIImage) -> UIImage {
        // Normalize orientation first - CGImage.cropping ignores orientation metadata
        let normalizedImage = image.fixedOrientation()

        guard let cgImage = normalizedImage.cgImage else { return image }

        // Use CGImage dimensions (raw pixels) not UIImage.size (logical)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let squareSize = min(width, height)

        // Calculate center crop rect in pixel coordinates
        let x = (width - squareSize) / 2
        let y = (height - squareSize) / 2
        let cropRect = CGRect(x: x, y: y, width: squareSize, height: squareSize)

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            logger.warning("Failed to crop image, returning original")
            return image
        }

        // Return with .up orientation (already normalized)
        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }
}
