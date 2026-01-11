import UIKit
import AVFoundation
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

    // Callbacks
    var onPhotosCaptured: (([UIImage]) -> Void)?
    var onCancel: (() -> Void)?
    var contextTitle: String?

    // Preview constraint references for dynamic sizing
    private var previewWidthConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?

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
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
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

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24)
        ])

        return container
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
        // Width: slider thumb width + padding = 60pt
        return container
    }()

    private let logger = Logger(subsystem: "com.joylabs.native", category: "AVCameraViewController")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemGroupedBackground

        setupUI()
        setupCamera()
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
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
            bufferBottomToViewConstraint
        ].compactMap { $0 })

        if isPortrait {
            // Portrait mode: Button at bottom center, badge to left, buffer above button
            NSLayoutConstraint.activate([
                captureButtonBottomConstraint!,
                captureButtonCenterXConstraint!,
                badgeTrailingConstraint!,
                badgeCenterYConstraint!,
                bufferBottomToButtonConstraint!
            ])
        } else {
            // Landscape mode: Button on right side vertical center, badge above, buffer at bottom
            NSLayoutConstraint.activate([
                captureButtonTrailingConstraint!,
                captureButtonCenterYConstraint!,
                badgeBottomConstraint!,
                badgeCenterXConstraint!,
                bufferBottomToViewConstraint!
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
        thumbnailScrollView.addSubview(bufferEmptyPlaceholder)

        // Store preview constraints for dynamic updates
        previewWidthConstraint = previewView.widthAnchor.constraint(equalToConstant: 100)
        previewWidthConstraint?.priority = .defaultHigh  // Allow breaking if needed

        previewHeightConstraint = previewView.heightAnchor.constraint(equalToConstant: 100)
        previewHeightConstraint?.priority = .defaultHigh  // Allow breaking if needed

        NSLayoutConstraint.activate([
            // Preview - square (size updated in viewDidLayoutSubviews)
            previewView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            previewWidthConstraint!,
            previewHeightConstraint!,

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
            contextTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 16),
            contextTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -16),

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

            // Buffer empty placeholder - centered in scrollview
            bufferEmptyPlaceholder.topAnchor.constraint(equalTo: thumbnailScrollView.topAnchor),
            bufferEmptyPlaceholder.leadingAnchor.constraint(equalTo: thumbnailScrollView.leadingAnchor),
            bufferEmptyPlaceholder.trailingAnchor.constraint(equalTo: thumbnailScrollView.trailingAnchor),
            bufferEmptyPlaceholder.bottomAnchor.constraint(equalTo: thumbnailScrollView.bottomAnchor),

            // Exposure controls container - background for all exposure controls
            exposureControlsContainer.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 8),
            exposureControlsContainer.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            exposureControlsContainer.widthAnchor.constraint(equalToConstant: 60),
            exposureControlsContainer.heightAnchor.constraint(equalToConstant: 264),

            // Exposure controls - grouped near slider on left edge
            // Icon positioned above slider (rotated slider extends ±100pt from center)
            exposureIcon.bottomAnchor.constraint(equalTo: exposureSlider.centerYAnchor, constant: -110),
            exposureIcon.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 16),
            exposureIcon.widthAnchor.constraint(equalToConstant: 24),
            exposureIcon.heightAnchor.constraint(equalToConstant: 24),

            exposureValueLabel.topAnchor.constraint(equalTo: exposureIcon.bottomAnchor, constant: 4),
            exposureValueLabel.centerXAnchor.constraint(equalTo: exposureIcon.centerXAnchor),
            exposureValueLabel.widthAnchor.constraint(equalToConstant: 50),

            // Slider vertically centered on preview
            exposureSlider.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            exposureSlider.centerXAnchor.constraint(equalTo: exposureIcon.centerXAnchor),
            exposureSlider.widthAnchor.constraint(equalToConstant: 200)
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

        // Set initial orientation layout
        updateLayoutForOrientation()
        updateBufferCount()
    }

    private func setupCamera() {
        // Check camera authorization
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.configureCamera()
                    }
                } else {
                    self?.logger.error("Camera access denied")
                }
            }
        default:
            logger.error("Camera access denied or restricted")
        }
    }

    private func configureCamera() {
        captureSession.beginConfiguration()

        // Set session preset
        captureSession.sessionPreset = .photo

        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            logger.error("Failed to get camera device")
            return
        }

        currentDevice = camera

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            logger.error("Failed to create camera input: \(error.localizedDescription)")
            return
        }

        // Add photo output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()

        // Setup preview layer first
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = previewView.bounds
        previewView.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        // Create rotation coordinator with preview layer reference
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)

        // Set initial rotation and observe changes
        updatePreviewRotation()
        setupRotationObservation()

        // Apply saved exposure bias
        applyExposureBias(savedExposureBias)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Only update if bounds are valid
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }

        // Calculate square viewport size based on available space (orientation-aware)
        let isPortrait = view.bounds.height > view.bounds.width
        let headerHeight: CGFloat = 60
        let bufferHeight: CGFloat = 80
        let buttonSize: CGFloat = 90  // Button + spacing
        let spacing: CGFloat = 60

        let squareSize: CGFloat
        if isPortrait {
            // Portrait: Button at bottom (uses vertical space)
            let availableHeight = view.bounds.height - headerHeight - bufferHeight - buttonSize - spacing
            let availableWidth = view.bounds.width
            squareSize = min(availableWidth, availableHeight)
        } else {
            // Landscape: Button on right side (uses horizontal space)
            let availableHeight = view.bounds.height - headerHeight - bufferHeight - spacing
            let availableWidth = view.bounds.width - buttonSize - spacing
            squareSize = min(availableWidth, availableHeight)
        }

        // Only update constraints if size actually changed
        if previewWidthConstraint?.constant != squareSize {
            previewWidthConstraint?.constant = squareSize
            previewHeightConstraint?.constant = squareSize
            view.layoutIfNeeded()
        }

        // Update preview layer to fill preview view
        previewLayer?.frame = previewView.bounds
        previewLayer?.videoGravity = .resizeAspectFill

        // Update button/badge layout for orientation
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

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailContainer.addSubview(imageView)

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

            // Update tags for remaining thumbnails
            for (newIndex, view) in thumbnailStackView.arrangedSubviews.enumerated() {
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
            self.addPhotoToBuffer(croppedImage)
            self.logger.info("Photo captured, cropped to square, and added to buffer (total: \(self.capturedPhotos.count))")
        }
    }

    /// Crop image to square aspect ratio using shorter dimension (no data loss)
    private func cropToSquare(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let size = image.size
        let squareSize = min(size.width, size.height)

        // Calculate center crop rect in image coordinates
        let x = (size.width - squareSize) / 2
        let y = (size.height - squareSize) / 2
        let cropRect = CGRect(x: x * image.scale, y: y * image.scale, width: squareSize * image.scale, height: squareSize * image.scale)

        // Crop using CGImage
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            logger.warning("Failed to crop image, returning original")
            return image
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
