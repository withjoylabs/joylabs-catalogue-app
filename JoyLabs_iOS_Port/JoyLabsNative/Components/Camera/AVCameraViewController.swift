import UIKit
import AVFoundation
import SwiftUI
import os.log

// MARK: - Framing Guide Mode

enum FramingGuideMode: Int, CaseIterable {
    case none
    case ruleOfThirds
    case crosshair

    var next: FramingGuideMode {
        let allCases = FramingGuideMode.allCases
        let nextIndex = (rawValue + 1) % allCases.count
        return allCases[nextIndex]
    }
}

// MARK: - Zoom Preset Model

/// Zoom preset for virtual camera device (like native Camera app)
/// Uses single virtual device with zoom factor changes instead of switching physical cameras
struct ZoomPreset {
    let displayName: String
    let zoomFactor: CGFloat
}

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

    // Exposure control (extracted component)
    private let exposureManager = CameraExposureManager()
    private var exposureControlView: CameraExposureControlView?

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


    // Camera configuration state
    private var isCameraConfigured = false

    // Zoom presets (virtual device with zoom factor changes)
    private var zoomPresets: [ZoomPreset] = []
    private var currentPresetIndex: Int = 0
    private var zoomButtons: [UIButton] = []
    private var zoomButtonWidthConstraints: [NSLayoutConstraint] = []
    private var zoomButtonHeightConstraints: [NSLayoutConstraint] = []
    private var zoomSelectorStackView: UIStackView?
    private var zoomSelectorBackground: UIView?
    private var pinchStartZoom: CGFloat = 1.0

    // Zoom selector constraint references for orientation-based layout
    private var zoomSelectorCenterXConstraint: NSLayoutConstraint?
    private var zoomSelectorBottomConstraint: NSLayoutConstraint?
    private var zoomSelectorCenterYConstraint: NSLayoutConstraint?
    private var zoomSelectorTrailingConstraint: NSLayoutConstraint?

    // Exposure bar constraint references for orientation-based layout
    private var exposureBarCenterXConstraint: NSLayoutConstraint?
    private var exposureBarBottomConstraint: NSLayoutConstraint?
    private var exposureBarCenterYConstraint: NSLayoutConstraint?
    private var exposureBarTrailingConstraint: NSLayoutConstraint?

    // Framing guide state and UI
    private var framingGuideMode: FramingGuideMode = .none
    private var framingGuideLayer: CAShapeLayer?
    private var guideToggleButton: UIButton?

    // Guide toggle button constraint references for orientation-based layout
    private var guideButtonLeadingConstraint: NSLayoutConstraint?
    private var guideButtonCenterYConstraint: NSLayoutConstraint?
    private var guideButtonTopConstraint: NSLayoutConstraint?
    private var guideButtonCenterXConstraint: NSLayoutConstraint?

    // Circular action button constraint references (Cancel and Save at bottom)
    // iPhone/iPad Portrait: bottom corners
    private var cancelCircleBottomConstraint: NSLayoutConstraint?
    private var cancelCircleLeadingConstraint: NSLayoutConstraint?
    private var saveCircleBottomConstraint: NSLayoutConstraint?
    private var saveCircleTrailingConstraint: NSLayoutConstraint?
    // iPad Landscape: grouped below guide button
    private var iPadLandscapeCancelTopConstraint: NSLayoutConstraint?
    private var iPadLandscapeCancelTrailingConstraint: NSLayoutConstraint?
    private var iPadLandscapeSaveTopConstraint: NSLayoutConstraint?
    private var iPadLandscapeSaveLeadingConstraint: NSLayoutConstraint?

    // iPad-specific layout (fixed viewport size, different layouts for portrait/landscape)
    private var iPadViewportSize: CGFloat = 0
    private var isIPadLayout: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // iPad constraint references - viewport and buffer (always same size)
    private var iPadPreviewWidthConstraint: NSLayoutConstraint?
    private var iPadPreviewHeightConstraint: NSLayoutConstraint?
    private var iPadBufferWidthConstraint: NSLayoutConstraint?

    // iPad Portrait constraints (vertical stack centered)
    private var iPadPortraitPreviewCenterXConstraint: NSLayoutConstraint?
    private var iPadPortraitBufferCenterXConstraint: NSLayoutConstraint?
    private var iPadPortraitCaptureBottomConstraint: NSLayoutConstraint?
    private var iPadPortraitCaptureCenterXConstraint: NSLayoutConstraint?
    private var iPadPortraitBadgeBottomConstraint: NSLayoutConstraint?
    private var iPadPortraitBadgeCenterXConstraint: NSLayoutConstraint?
    private var iPadPortraitGuideLeadingConstraint: NSLayoutConstraint?
    private var iPadPortraitGuideCenterYConstraint: NSLayoutConstraint?

    // iPad Landscape constraints (side-by-side: viewport+buffer left, controls right)
    private var iPadLandscapePreviewLeadingConstraint: NSLayoutConstraint?
    private var iPadLandscapeBufferLeadingConstraint: NSLayoutConstraint?
    // Capture button: VERTICALLY CENTERED (anchor point)
    private var iPadLandscapeCaptureTrailingConstraint: NSLayoutConstraint?
    private var iPadLandscapeCaptureCenterYConstraint: NSLayoutConstraint?
    // Badge: above capture
    private var iPadLandscapeBadgeBottomConstraint: NSLayoutConstraint?
    private var iPadLandscapeBadgeCenterXConstraint: NSLayoutConstraint?
    // Guide: below capture
    private var iPadLandscapeGuideTopConstraint: NSLayoutConstraint?
    private var iPadLandscapeGuideCenterXConstraint: NSLayoutConstraint?

    // iPad exposure control constraints (orientation-based)
    private var iPadExposurePortraitCenterXConstraint: NSLayoutConstraint?
    private var iPadExposurePortraitBottomConstraint: NSLayoutConstraint?
    // Landscape: centerY aligned with zoom, to the left of zoom
    private var iPadExposureLandscapeCenterYConstraint: NSLayoutConstraint?
    private var iPadExposureLandscapeTrailingConstraint: NSLayoutConstraint?

    // iPad zoom selector constraints (orientation-based)
    private var iPadZoomPortraitCenterXConstraint: NSLayoutConstraint?
    private var iPadZoomPortraitBottomConstraint: NSLayoutConstraint?
    // Landscape: above badge, offset right from center
    private var iPadZoomLandscapeBottomConstraint: NSLayoutConstraint?
    private var iPadZoomLandscapeCenterXConstraint: NSLayoutConstraint?

    // Persistence keys for camera settings
    private let framingGuideKey = "com.joylabs.camera.framingGuideMode"
    private let zoomPresetKey = "com.joylabs.camera.zoomPresetIndex"

    // Loading indicator
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()


    // UI Components
    private lazy var previewView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
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

    // Circular action buttons (bottom of screen)
    private lazy var cancelCircleButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "xmark")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        )
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemGray
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var saveCircleButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.up")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        )
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemGreen
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var contextTitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.text = contextTitle ?? "Camera"
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var photoCountBadge: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemRed
        container.layer.cornerRadius = 9
        container.isHidden = true  // Hidden when count is 0

        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 999  // Tag to find label later
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            container.heightAnchor.constraint(equalToConstant: 18)
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

    private lazy var framingGuideToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "viewfinder"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(guideToggleTapped), for: .touchUpInside)
        return button
    }()

    private let logger = Logger(subsystem: "com.joylabs.native", category: "AVCameraViewController")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Load persisted framing guide mode
        if let savedMode = UserDefaults.standard.object(forKey: framingGuideKey) as? Int,
           let mode = FramingGuideMode(rawValue: savedMode) {
            framingGuideMode = mode
        }

        setupUI()
        setupLoadingIndicator()

        // Update framing guide button appearance based on loaded mode
        let isGuideActive = framingGuideMode != .none
        framingGuideToggleButton.tintColor = isGuideActive ? .systemYellow : .white

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
        // Layout updates handled by viewDidLayoutSubviews
    }

    private func updateLayoutForOrientation() {
        let isPortrait = view.bounds.height > view.bounds.width

        if isIPadLayout {
            // iPad orientation switching
            // Deactivate all iPad orientation-specific constraints
            NSLayoutConstraint.deactivate([
                // Portrait constraints
                iPadPortraitPreviewCenterXConstraint,
                iPadPortraitBufferCenterXConstraint,
                iPadPortraitCaptureBottomConstraint,
                iPadPortraitCaptureCenterXConstraint,
                iPadPortraitBadgeBottomConstraint,
                iPadPortraitBadgeCenterXConstraint,
                iPadPortraitGuideLeadingConstraint,
                iPadPortraitGuideCenterYConstraint,
                // Landscape constraints
                iPadLandscapePreviewLeadingConstraint,
                iPadLandscapeBufferLeadingConstraint,
                iPadLandscapeCaptureTrailingConstraint,
                iPadLandscapeCaptureCenterYConstraint,
                iPadLandscapeBadgeBottomConstraint,
                iPadLandscapeBadgeCenterXConstraint,
                iPadLandscapeGuideTopConstraint,
                iPadLandscapeGuideCenterXConstraint,
                // Circular button constraints (both orientations)
                cancelCircleBottomConstraint,
                cancelCircleLeadingConstraint,
                saveCircleBottomConstraint,
                saveCircleTrailingConstraint,
                iPadLandscapeCancelTopConstraint,
                iPadLandscapeCancelTrailingConstraint,
                iPadLandscapeSaveTopConstraint,
                iPadLandscapeSaveLeadingConstraint
            ].compactMap { $0 })

            if isPortrait {
                // iPad Portrait: Everything stacked vertically, centered
                // Circular buttons at bottom corners
                NSLayoutConstraint.activate([
                    iPadPortraitPreviewCenterXConstraint!,
                    iPadPortraitBufferCenterXConstraint!,
                    iPadPortraitCaptureBottomConstraint!,
                    iPadPortraitCaptureCenterXConstraint!,
                    iPadPortraitBadgeBottomConstraint!,
                    iPadPortraitBadgeCenterXConstraint!,
                    iPadPortraitGuideLeadingConstraint!,
                    iPadPortraitGuideCenterYConstraint!,
                    cancelCircleBottomConstraint!,
                    cancelCircleLeadingConstraint!,
                    saveCircleBottomConstraint!,
                    saveCircleTrailingConstraint!
                ])
            } else {
                // iPad Landscape: Viewport+buffer on left, controls vertically centered on right
                // Circular buttons grouped below guide button
                NSLayoutConstraint.activate([
                    iPadLandscapePreviewLeadingConstraint!,
                    iPadLandscapeBufferLeadingConstraint!,
                    iPadLandscapeCaptureTrailingConstraint!,
                    iPadLandscapeCaptureCenterYConstraint!,
                    iPadLandscapeBadgeBottomConstraint!,
                    iPadLandscapeBadgeCenterXConstraint!,
                    iPadLandscapeGuideTopConstraint!,
                    iPadLandscapeGuideCenterXConstraint!,
                    iPadLandscapeCancelTopConstraint!,
                    iPadLandscapeCancelTrailingConstraint!,
                    iPadLandscapeSaveTopConstraint!,
                    iPadLandscapeSaveLeadingConstraint!
                ])
            }
        } else {
            // iPhone orientation switching
            // Deactivate all iPhone orientation-specific constraints
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
                guideButtonLeadingConstraint,
                guideButtonCenterYConstraint,
                guideButtonTopConstraint,
                guideButtonCenterXConstraint
            ].compactMap { $0 })

            if isPortrait {
                // iPhone Portrait: Button at bottom center, badge to left, guide button to right
                NSLayoutConstraint.activate([
                    captureButtonBottomConstraint!,
                    captureButtonCenterXConstraint!,
                    badgeTrailingConstraint!,
                    badgeCenterYConstraint!,
                    guideButtonLeadingConstraint!,
                    guideButtonCenterYConstraint!
                ])
            } else {
                // iPhone Landscape: Button on right side vertical center, badge above, guide button below
                NSLayoutConstraint.activate([
                    captureButtonTrailingConstraint!,
                    captureButtonCenterYConstraint!,
                    badgeBottomConstraint!,
                    badgeCenterXConstraint!,
                    bufferBottomToViewConstraint!,
                    guideButtonTopConstraint!,
                    guideButtonCenterXConstraint!
                ])
            }
        }
    }

    // MARK: - Setup

    private func setupUI() {
        // Preview (square aspect ratio)
        view.addSubview(previewView)
        previewView.layer.cornerRadius = 12
        previewView.clipsToBounds = true

        // Exposure control view (Auto/Manual mode)
        let exposureControl = CameraExposureControlView()
        exposureControl.alpha = 0  // Hidden until constraints are set up
        view.addSubview(exposureControl)
        exposureControlView = exposureControl

        // Capture button
        view.addSubview(captureButton)

        // Header with centered title only
        view.addSubview(contextTitleLabel)

        // Circular action buttons (bottom of screen)
        view.addSubview(cancelCircleButton)
        view.addSubview(saveCircleButton)

        // Photo count badge on capture button
        view.addSubview(photoCountBadge)

        // Thumbnail buffer
        view.addSubview(thumbnailScrollView)
        thumbnailScrollView.addSubview(thumbnailStackView)
        view.addSubview(bufferEmptyPlaceholder)  // Add to view for proper centering

        // Framing guide toggle button
        view.addSubview(framingGuideToggleButton)
        guideToggleButton = framingGuideToggleButton

        // Common constraints for header (title spans full width)
        NSLayoutConstraint.activate([
            contextTitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            contextTitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contextTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            contextTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            // Capture button size (position set per-device)
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),

            // Guide toggle button size
            framingGuideToggleButton.widthAnchor.constraint(equalToConstant: 40),
            framingGuideToggleButton.heightAnchor.constraint(equalToConstant: 40),

            // Circular action buttons size
            cancelCircleButton.widthAnchor.constraint(equalToConstant: 50),
            cancelCircleButton.heightAnchor.constraint(equalToConstant: 50),
            saveCircleButton.widthAnchor.constraint(equalToConstant: 50),
            saveCircleButton.heightAnchor.constraint(equalToConstant: 50),

            // Buffer empty placeholder
            bufferEmptyPlaceholder.widthAnchor.constraint(equalTo: thumbnailScrollView.widthAnchor),
            bufferEmptyPlaceholder.heightAnchor.constraint(equalToConstant: 80),
            bufferEmptyPlaceholder.centerXAnchor.constraint(equalTo: thumbnailScrollView.centerXAnchor),
            bufferEmptyPlaceholder.centerYAnchor.constraint(equalTo: thumbnailScrollView.centerYAnchor),

            // Thumbnail stack inside scroll view
            thumbnailStackView.topAnchor.constraint(equalTo: thumbnailScrollView.topAnchor),
            thumbnailStackView.leadingAnchor.constraint(equalTo: thumbnailScrollView.leadingAnchor),
            thumbnailStackView.trailingAnchor.constraint(equalTo: thumbnailScrollView.trailingAnchor),
            thumbnailStackView.bottomAnchor.constraint(equalTo: thumbnailScrollView.bottomAnchor),
            thumbnailStackView.heightAnchor.constraint(equalTo: thumbnailScrollView.heightAnchor)
        ])

        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        if isIPad {
            // ===========================================
            // iPad: Two different layouts for orientations
            // - Landscape: viewport+buffer LEFT, controls RIGHT
            // - Portrait: everything stacked vertically centered
            // ===========================================

            // Calculate viewport size based on LANDSCAPE left-side layout
            // In landscape, LEFT side has: header → viewport → buffer (vertically stacked)
            // Controls go on the RIGHT side, so don't include them in height calculation
            let viewBounds = view.bounds
            let landscapeHeight = min(viewBounds.width, viewBounds.height)

            // Estimated safe area for landscape
            let estimatedSafeTop: CGFloat = 24
            let estimatedSafeBottom: CGFloat = 20

            // Left-side vertical stack in landscape (NOT including right-side controls)
            let leftSideControlsHeight: CGFloat = 50 +   // header
                                                  16 +   // header to viewport gap
                                                  16 +   // viewport to buffer gap
                                                  80 +   // buffer
                                                  20     // buffer to bottom gap
            // = 182pt (NOT 368pt!)

            let availableHeight = landscapeHeight - estimatedSafeTop - estimatedSafeBottom - leftSideControlsHeight
            iPadViewportSize = max(300, availableHeight)

            logger.info("[Camera] iPad viewport size: \(self.iPadViewportSize)pt (landscape height: \(landscapeHeight)pt)")

            // Create iPad constraints - viewport and buffer size (same for both orientations)
            iPadPreviewWidthConstraint = previewView.widthAnchor.constraint(equalToConstant: iPadViewportSize)
            iPadPreviewHeightConstraint = previewView.heightAnchor.constraint(equalToConstant: iPadViewportSize)
            iPadBufferWidthConstraint = thumbnailScrollView.widthAnchor.constraint(equalToConstant: iPadViewportSize)

            // Activate size constraints (always active)
            // Note: capture button size is already in common constraints
            NSLayoutConstraint.activate([
                previewView.topAnchor.constraint(equalTo: contextTitleLabel.bottomAnchor, constant: 16),
                iPadPreviewWidthConstraint!,
                iPadPreviewHeightConstraint!,
                thumbnailScrollView.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 16),
                iPadBufferWidthConstraint!,
                thumbnailScrollView.heightAnchor.constraint(equalToConstant: 80)
            ])

            // iPad circular button constraints
            // Portrait: grouped together at bottom-right with 15pt spacing (like ItemDetailsModal)
            saveCircleBottomConstraint = saveCircleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            saveCircleTrailingConstraint = saveCircleButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
            cancelCircleBottomConstraint = cancelCircleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            cancelCircleLeadingConstraint = cancelCircleButton.trailingAnchor.constraint(equalTo: saveCircleButton.leadingAnchor, constant: -15)

            // Landscape: stacked vertically below guide button (upload first, cancel below)
            iPadLandscapeSaveTopConstraint = saveCircleButton.topAnchor.constraint(equalTo: framingGuideToggleButton.bottomAnchor, constant: 20)
            iPadLandscapeSaveLeadingConstraint = saveCircleButton.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor)
            iPadLandscapeCancelTopConstraint = cancelCircleButton.topAnchor.constraint(equalTo: saveCircleButton.bottomAnchor, constant: 15)
            iPadLandscapeCancelTrailingConstraint = cancelCircleButton.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor)

            // iPad PORTRAIT constraints (vertical stack, centered)
            iPadPortraitPreviewCenterXConstraint = previewView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            iPadPortraitBufferCenterXConstraint = thumbnailScrollView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            iPadPortraitCaptureBottomConstraint = captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            iPadPortraitCaptureCenterXConstraint = captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            // Badge overlays upload button (top-leading, like photo editor)
            iPadPortraitBadgeBottomConstraint = photoCountBadge.topAnchor.constraint(equalTo: saveCircleButton.topAnchor, constant: -2)
            iPadPortraitBadgeCenterXConstraint = photoCountBadge.leadingAnchor.constraint(equalTo: saveCircleButton.leadingAnchor, constant: -2)
            iPadPortraitGuideLeadingConstraint = framingGuideToggleButton.leadingAnchor.constraint(equalTo: captureButton.trailingAnchor, constant: 12)
            iPadPortraitGuideCenterYConstraint = framingGuideToggleButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)

            // iPad LANDSCAPE constraints (side-by-side: viewport+buffer left, controls right)
            // ANCHOR: Capture button is VERTICALLY CENTERED on screen
            iPadLandscapePreviewLeadingConstraint = previewView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
            iPadLandscapeBufferLeadingConstraint = thumbnailScrollView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor)

            // 1. Capture button: VERTICALLY CENTERED (this is the anchor point!)
            iPadLandscapeCaptureTrailingConstraint = captureButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40)
            iPadLandscapeCaptureCenterYConstraint = captureButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)

            // 2. Guide: below capture button
            iPadLandscapeGuideTopConstraint = framingGuideToggleButton.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 12)
            iPadLandscapeGuideCenterXConstraint = framingGuideToggleButton.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor)

            // 3. Badge: overlays upload button (top-leading, like photo editor)
            iPadLandscapeBadgeBottomConstraint = photoCountBadge.topAnchor.constraint(equalTo: saveCircleButton.topAnchor, constant: -2)
            iPadLandscapeBadgeCenterXConstraint = photoCountBadge.leadingAnchor.constraint(equalTo: saveCircleButton.leadingAnchor, constant: -2)

            // Note: Sliders (exposure + zoom) positioned above badge in their setup methods

        } else {
            // ===========================================
            // iPhone: Existing dynamic layout
            // Changes based on orientation
            // ===========================================

            NSLayoutConstraint.activate([
                // Preview: full width, square aspect ratio
                previewView.topAnchor.constraint(equalTo: contextTitleLabel.bottomAnchor, constant: 16),
                previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor),

                // Buffer: below preview, edge-to-edge
                thumbnailScrollView.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 16),
                thumbnailScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                thumbnailScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                thumbnailScrollView.heightAnchor.constraint(equalToConstant: 80)
            ])

            // iPhone circular button constraints (portrait only - bottom corners)
            cancelCircleBottomConstraint = cancelCircleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            cancelCircleLeadingConstraint = cancelCircleButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20)
            saveCircleBottomConstraint = saveCircleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            saveCircleTrailingConstraint = saveCircleButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)

            // Activate for iPhone (portrait only)
            NSLayoutConstraint.activate([
                cancelCircleBottomConstraint!,
                cancelCircleLeadingConstraint!,
                saveCircleBottomConstraint!,
                saveCircleTrailingConstraint!
            ])

            // iPhone orientation-based constraints (updated in updateLayoutForOrientation)
            captureButtonBottomConstraint = captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            captureButtonCenterXConstraint = captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            captureButtonTrailingConstraint = captureButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
            captureButtonCenterYConstraint = captureButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)

            // Badge overlays upload button (top-leading, like photo editor)
            badgeTrailingConstraint = photoCountBadge.topAnchor.constraint(equalTo: saveCircleButton.topAnchor, constant: -2)
            badgeCenterYConstraint = photoCountBadge.leadingAnchor.constraint(equalTo: saveCircleButton.leadingAnchor, constant: -2)
            badgeBottomConstraint = photoCountBadge.topAnchor.constraint(equalTo: saveCircleButton.topAnchor, constant: -2)
            badgeCenterXConstraint = photoCountBadge.leadingAnchor.constraint(equalTo: saveCircleButton.leadingAnchor, constant: -2)

            bufferBottomToButtonConstraint = thumbnailScrollView.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -16)
            bufferBottomToViewConstraint = thumbnailScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            bufferBottomToViewConstraint?.priority = .defaultHigh

            // iPhone guide button constraints
            guideButtonLeadingConstraint = framingGuideToggleButton.leadingAnchor.constraint(equalTo: captureButton.trailingAnchor, constant: 12)
            guideButtonCenterYConstraint = framingGuideToggleButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
            guideButtonTopConstraint = framingGuideToggleButton.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 8)
            guideButtonCenterXConstraint = framingGuideToggleButton.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor)
        }

        // Bring UI elements to front (proper Z-order)
        view.bringSubviewToFront(thumbnailScrollView)
        view.bringSubviewToFront(captureButton)
        view.bringSubviewToFront(framingGuideToggleButton)
        view.bringSubviewToFront(contextTitleLabel)
        view.bringSubviewToFront(cancelCircleButton)
        view.bringSubviewToFront(saveCircleButton)
        view.bringSubviewToFront(photoCountBadge)  // Badge on top of upload button
        if let exposureControl = exposureControlView {
            view.bringSubviewToFront(exposureControl)
        }

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

        // Try virtual devices first (triple > dual wide > dual > wide angle)
        // Virtual devices handle automatic lens switching based on zoom factor
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )

        guard let camera = discoverySession.devices.first else {
            logger.error("Failed to get camera device")
            captureSession.commitConfiguration()
            showCameraLoading(false)
            return
        }

        logger.info("[Camera] Using device: \(camera.localizedName) (\(camera.deviceType.rawValue))")
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

            // Setup framing guide layer (on top of preview)
            self.setupFramingGuideLayer()

            // Apply persisted framing guide mode
            self.updateFramingGuide()

            // Create rotation coordinator with preview layer reference
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)

            // Set initial rotation and observe changes
            self.updatePreviewRotation()
            self.setupRotationObservation()
        }

        // Configure exposure manager with device capabilities
        exposureManager.configure(with: camera)

        // Mark as configured
        isCameraConfigured = true

        // OPTIMIZATION: Discover zoom presets and restore saved zoom BEFORE starting session
        // This prevents the visible "jump" from default zoom to saved zoom
        discoverAndRestoreZoomPresets(for: camera)

        // Start running with correct zoom already set
        if !captureSession.isRunning {
            captureSession.startRunning()
        }

        // Setup UI on main thread (after session starts with correct zoom)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setupZoomSelectorUI()
            self.setupExposureControlConstraints()
            self.setupPinchZoom()

            // Configure exposure control view with manager and device
            if let device = self.currentDevice {
                self.exposureControlView?.configure(manager: self.exposureManager, device: device)
            }
        }

        // Hide loading indicator
        showCameraLoading(false)
    }

    // MARK: - Zoom Preset Discovery (Virtual Device)

    /// Discover zoom presets and restore saved zoom BEFORE session starts (background thread)
    /// This prevents visible "jump" from default zoom to saved zoom
    private func discoverAndRestoreZoomPresets(for device: AVCaptureDevice) {
        // Get switch-over points from virtual device (where it switches physical cameras)
        let switchPoints = device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = device.maxAvailableVideoZoomFactor

        logger.info("[Camera] Device zoom range: \(minZoom) - \(maxZoom), switch points: \(switchPoints)")

        // Build zoom presets based on device capabilities
        zoomPresets = buildZoomPresets(minZoom: minZoom, maxZoom: maxZoom, switchPoints: switchPoints)

        // Determine which preset to use
        let savedIndex = UserDefaults.standard.integer(forKey: zoomPresetKey)
        let targetIndex: Int
        let targetPreset: ZoomPreset

        if savedIndex >= 0 && savedIndex < zoomPresets.count {
            // Use saved preference
            targetIndex = savedIndex
            targetPreset = zoomPresets[savedIndex]
            logger.info("[Camera] Restoring saved zoom preset: \(targetPreset.displayName)x")
        } else if let oneXIndex = zoomPresets.firstIndex(where: { $0.displayName == "1" }) {
            // Default to 1x (wide angle camera)
            targetIndex = oneXIndex
            targetPreset = zoomPresets[oneXIndex]
            logger.info("[Camera] Using default 1x zoom")
        } else {
            // Fallback to first preset
            targetIndex = 0
            targetPreset = zoomPresets[0]
            logger.info("[Camera] Using first available zoom preset")
        }

        // Set zoom BEFORE session starts (still on background thread - no UI blocking)
        currentPresetIndex = targetIndex
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = targetPreset.zoomFactor
            device.unlockForConfiguration()
        } catch {
            logger.error("[Camera] Failed to set initial zoom: \(error)")
        }

        logger.info("[Camera] Zoom presets: \(self.zoomPresets.map { $0.displayName })")
    }

    private func buildZoomPresets(minZoom: CGFloat, maxZoom: CGFloat, switchPoints: [Double]) -> [ZoomPreset] {
        var presets: [ZoomPreset] = []

        // The first switch point is the "1x" wide angle camera
        // If no switch points, device is single camera - use 1.0 as baseline
        let wideAngleZoom = switchPoints.first.map { CGFloat($0) } ?? 1.0

        // 0.5x (ultra-wide) - only if minZoom < wideAngleZoom
        if minZoom < wideAngleZoom {
            presets.append(ZoomPreset(displayName: "0.5", zoomFactor: minZoom))
        }

        // 1x (wide angle) - the first switch point
        presets.append(ZoomPreset(displayName: "1", zoomFactor: wideAngleZoom))

        // 2x = wideAngleZoom * 2
        let twoX = wideAngleZoom * 2
        if twoX <= maxZoom {
            presets.append(ZoomPreset(displayName: "2", zoomFactor: twoX))
        }

        // 4x = wideAngleZoom * 4
        let fourX = wideAngleZoom * 4
        if fourX <= maxZoom {
            presets.append(ZoomPreset(displayName: "4", zoomFactor: fourX))
        }

        // 8x = wideAngleZoom * 8
        let eightX = wideAngleZoom * 8
        if eightX <= maxZoom {
            presets.append(ZoomPreset(displayName: "8", zoomFactor: eightX))
        }

        return presets
    }

    // MARK: - Zoom Selector UI

    private func setupZoomSelectorUI() {
        // Only show selector if more than one preset
        guard zoomPresets.count > 1 else {
            logger.info("[Camera] Single zoom level, skipping zoom selector")
            return
        }

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Semi-transparent background pill
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        backgroundView.layer.cornerRadius = 18
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        // Create button for each zoom preset
        zoomButtons.removeAll()
        zoomButtonWidthConstraints.removeAll()
        zoomButtonHeightConstraints.removeAll()
        for (index, preset) in zoomPresets.enumerated() {
            let button = createZoomButton(
                title: preset.displayName,
                tag: index,
                isSelected: index == currentPresetIndex
            )
            stackView.addArrangedSubview(button)
            zoomButtons.append(button)
        }

        view.addSubview(backgroundView)
        view.addSubview(stackView)
        zoomSelectorStackView = stackView
        zoomSelectorBackground = backgroundView

        // Setup constraints
        setupZoomSelectorConstraints(backgroundView, stackView)

        // Bring to front
        view.bringSubviewToFront(backgroundView)
        view.bringSubviewToFront(stackView)
    }

    private func createZoomButton(title: String, tag: Int, isSelected: Bool) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = isSelected ? .systemYellow : .white
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: isSelected ? .bold : .regular)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)

        let button = UIButton(configuration: config)
        button.tag = tag
        button.addTarget(self, action: #selector(zoomButtonTapped(_:)), for: .touchUpInside)

        // Create size constraints (portrait: 44×36, will swap for landscape)
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: 44)
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: 36)
        widthConstraint.isActive = true
        heightConstraint.isActive = true

        // Store constraints for orientation switching
        zoomButtonWidthConstraints.append(widthConstraint)
        zoomButtonHeightConstraints.append(heightConstraint)

        return button
    }

    private func setupZoomSelectorConstraints(_ background: UIView, _ stack: UIStackView) {
        // Background hugs the stack view
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: -8),
            background.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 8),
            background.topAnchor.constraint(equalTo: stack.topAnchor, constant: -2),
            background.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 2)
        ])

        if isIPadLayout {
            // iPad: Dynamic constraints for orientation changes
            // Portrait: horizontal stack, centered, above capture button
            iPadZoomPortraitCenterXConstraint = stack.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            iPadZoomPortraitBottomConstraint = stack.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -12)

            // Landscape: vertical stack, above capture button (70pt gap), offset right from center
            iPadZoomLandscapeBottomConstraint = stack.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -70)
            iPadZoomLandscapeCenterXConstraint = stack.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor, constant: 30)

            // Apply initial layout for iPad
            updateZoomSelectorLayout()
        } else {
            // iPhone: Dynamic constraints for orientation changes
            zoomSelectorCenterXConstraint = stack.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            zoomSelectorBottomConstraint = stack.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -12)
            zoomSelectorCenterYConstraint = stack.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
            zoomSelectorTrailingConstraint = stack.trailingAnchor.constraint(equalTo: captureButton.leadingAnchor, constant: -16)

            // Apply initial layout for iPhone
            updateZoomSelectorLayout()
        }
    }

    private func updateZoomSelectorLayout() {
        let isPortrait = view.bounds.height > view.bounds.width

        if isIPadLayout {
            // iPad orientation switching
            guard let stack = zoomSelectorStackView, iPadZoomPortraitCenterXConstraint != nil else { return }

            NSLayoutConstraint.deactivate([
                iPadZoomPortraitCenterXConstraint,
                iPadZoomPortraitBottomConstraint,
                iPadZoomLandscapeBottomConstraint,
                iPadZoomLandscapeCenterXConstraint
            ].compactMap { $0 })

            if isPortrait {
                // Horizontal stack for portrait
                stack.axis = .horizontal
                // Button dimensions: 44 wide × 36 tall
                for constraint in zoomButtonWidthConstraints { constraint.constant = 44 }
                for constraint in zoomButtonHeightConstraints { constraint.constant = 36 }
                NSLayoutConstraint.activate([
                    iPadZoomPortraitCenterXConstraint!,
                    iPadZoomPortraitBottomConstraint!
                ])
            } else {
                // Vertical stack for landscape, above badge, offset right
                stack.axis = .vertical
                // Button dimensions SWAP: 36 wide × 44 tall
                for constraint in zoomButtonWidthConstraints { constraint.constant = 36 }
                for constraint in zoomButtonHeightConstraints { constraint.constant = 44 }
                NSLayoutConstraint.activate([
                    iPadZoomLandscapeBottomConstraint!,
                    iPadZoomLandscapeCenterXConstraint!
                ])
            }
        } else {
            // iPhone orientation switching
            guard zoomSelectorStackView != nil, zoomSelectorCenterXConstraint != nil else { return }

            NSLayoutConstraint.deactivate([
                zoomSelectorCenterXConstraint,
                zoomSelectorBottomConstraint,
                zoomSelectorCenterYConstraint,
                zoomSelectorTrailingConstraint
            ].compactMap { $0 })

            if isPortrait {
                NSLayoutConstraint.activate([
                    zoomSelectorCenterXConstraint!,
                    zoomSelectorBottomConstraint!
                ])
            } else {
                NSLayoutConstraint.activate([
                    zoomSelectorCenterYConstraint!,
                    zoomSelectorTrailingConstraint!
                ])
            }
        }
    }

    // MARK: - Exposure Control Constraints

    private func setupExposureControlConstraints() {
        guard let exposureControl = exposureControlView else { return }

        if isIPadLayout {
            // iPad: Dynamic constraints for orientation changes
            // Portrait: horizontal, centered, above zoom selector
            iPadExposurePortraitCenterXConstraint = exposureControl.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            if let zoomBg = zoomSelectorBackground {
                iPadExposurePortraitBottomConstraint = exposureControl.bottomAnchor.constraint(equalTo: zoomBg.topAnchor, constant: -8)
            } else {
                iPadExposurePortraitBottomConstraint = exposureControl.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -60)
            }

            // Landscape: vertical, centerY aligned with zoom selector (side by side)
            // CenterY aligns with zoom stack's centerY, trailing to zoom's leading
            if let zoomStack = zoomSelectorStackView {
                iPadExposureLandscapeCenterYConstraint = exposureControl.centerYAnchor.constraint(equalTo: zoomStack.centerYAnchor)
            } else {
                iPadExposureLandscapeCenterYConstraint = exposureControl.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
            }
            if let zoomBg = zoomSelectorBackground {
                iPadExposureLandscapeTrailingConstraint = exposureControl.trailingAnchor.constraint(equalTo: zoomBg.leadingAnchor, constant: -12)
            } else {
                // Fallback: offset left from capture center
                iPadExposureLandscapeTrailingConstraint = exposureControl.trailingAnchor.constraint(equalTo: captureButton.centerXAnchor, constant: -10)
            }

            // Apply initial layout for iPad
            updateExposureControlLayout()
        } else {
            // iPhone: Dynamic constraints for orientation changes
            exposureBarCenterXConstraint = exposureControl.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            if let zoomBg = zoomSelectorBackground {
                exposureBarBottomConstraint = exposureControl.bottomAnchor.constraint(equalTo: zoomBg.topAnchor, constant: -8)
            } else {
                exposureBarBottomConstraint = exposureControl.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20)
            }
            exposureBarCenterYConstraint = exposureControl.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor, constant: -50)
            exposureBarTrailingConstraint = exposureControl.trailingAnchor.constraint(equalTo: captureButton.leadingAnchor, constant: -16)

            // Apply initial layout for iPhone
            updateExposureControlLayout()
        }

        // Reveal now that constraints are set
        exposureControlView?.alpha = 1
    }

    private func updateExposureControlLayout() {
        let isPortrait = view.bounds.height > view.bounds.width

        if isIPadLayout {
            // iPad orientation switching
            guard iPadExposurePortraitCenterXConstraint != nil else { return }

            NSLayoutConstraint.deactivate([
                iPadExposurePortraitCenterXConstraint,
                iPadExposurePortraitBottomConstraint,
                iPadExposureLandscapeCenterYConstraint,
                iPadExposureLandscapeTrailingConstraint
            ].compactMap { $0 })

            if isPortrait {
                exposureControlView?.isVertical = false
                NSLayoutConstraint.activate([
                    iPadExposurePortraitCenterXConstraint!,
                    iPadExposurePortraitBottomConstraint!
                ])
            } else {
                exposureControlView?.isVertical = true
                NSLayoutConstraint.activate([
                    iPadExposureLandscapeCenterYConstraint!,
                    iPadExposureLandscapeTrailingConstraint!
                ])
            }
        } else {
            // iPhone orientation switching
            guard exposureBarCenterXConstraint != nil else { return }

            NSLayoutConstraint.deactivate([
                exposureBarCenterXConstraint,
                exposureBarBottomConstraint,
                exposureBarCenterYConstraint,
                exposureBarTrailingConstraint
            ].compactMap { $0 })

            if isPortrait {
                NSLayoutConstraint.activate([
                    exposureBarCenterXConstraint!,
                    exposureBarBottomConstraint!
                ])
            } else {
                NSLayoutConstraint.activate([
                    exposureBarCenterYConstraint!,
                    exposureBarTrailingConstraint!
                ])
            }
        }
    }

    // MARK: - Framing Guides

    private func setupFramingGuideLayer() {
        let guideLayer = CAShapeLayer()
        guideLayer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.7).cgColor
        guideLayer.fillColor = UIColor.clear.cgColor
        guideLayer.lineWidth = 1.0
        guideLayer.frame = previewView.bounds
        guideLayer.isHidden = true  // Hidden by default (mode = .none)
        previewView.layer.addSublayer(guideLayer)
        framingGuideLayer = guideLayer
    }

    @objc private func guideToggleTapped() {
        // Cycle to next mode
        framingGuideMode = framingGuideMode.next

        // Persist selection
        UserDefaults.standard.set(framingGuideMode.rawValue, forKey: framingGuideKey)

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Update button appearance
        let isActive = framingGuideMode != .none
        framingGuideToggleButton.tintColor = isActive ? .systemYellow : .white

        // Update guide drawing
        updateFramingGuide()

        logger.info("[Camera] Framing guide mode: \(String(describing: self.framingGuideMode))")
    }

    private func updateFramingGuide() {
        guard let guideLayer = framingGuideLayer else { return }

        let bounds = previewView.bounds

        switch framingGuideMode {
        case .none:
            guideLayer.isHidden = true
            guideLayer.path = nil

        case .ruleOfThirds:
            guideLayer.isHidden = false
            let path = UIBezierPath()

            // Vertical lines at 1/3 and 2/3
            let oneThirdX = bounds.width / 3
            let twoThirdsX = bounds.width * 2 / 3

            path.move(to: CGPoint(x: oneThirdX, y: 0))
            path.addLine(to: CGPoint(x: oneThirdX, y: bounds.height))

            path.move(to: CGPoint(x: twoThirdsX, y: 0))
            path.addLine(to: CGPoint(x: twoThirdsX, y: bounds.height))

            // Horizontal lines at 1/3 and 2/3
            let oneThirdY = bounds.height / 3
            let twoThirdsY = bounds.height * 2 / 3

            path.move(to: CGPoint(x: 0, y: oneThirdY))
            path.addLine(to: CGPoint(x: bounds.width, y: oneThirdY))

            path.move(to: CGPoint(x: 0, y: twoThirdsY))
            path.addLine(to: CGPoint(x: bounds.width, y: twoThirdsY))

            guideLayer.path = path.cgPath

        case .crosshair:
            guideLayer.isHidden = false
            let path = UIBezierPath()

            let centerX = bounds.width / 2
            let centerY = bounds.height / 2

            // Vertical center line
            path.move(to: CGPoint(x: centerX, y: 0))
            path.addLine(to: CGPoint(x: centerX, y: bounds.height))

            // Horizontal center line
            path.move(to: CGPoint(x: 0, y: centerY))
            path.addLine(to: CGPoint(x: bounds.width, y: centerY))

            // Small center circle
            let circleRadius: CGFloat = 8
            path.addArc(
                withCenter: CGPoint(x: centerX, y: centerY),
                radius: circleRadius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )

            guideLayer.path = path.cgPath
        }
    }

    // MARK: - Zoom Preset Selection

    @objc private func zoomButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < zoomPresets.count, index != currentPresetIndex else { return }

        let preset = zoomPresets[index]
        applyZoomPreset(preset, index: index)
    }

    private func applyZoomPreset(_ preset: ZoomPreset, index: Int) {
        guard let device = currentDevice else { return }

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = preset.zoomFactor
            device.unlockForConfiguration()
        } catch {
            logger.error("[Camera] Zoom preset failed: \(error)")
            return
        }

        currentPresetIndex = index
        UserDefaults.standard.set(index, forKey: zoomPresetKey)
        updateZoomButtonSelection(index)

        logger.info("[Camera] Applied \(preset.displayName)x zoom")
    }

    private func updateZoomButtonSelection(_ selectedIndex: Int) {
        for (index, button) in zoomButtons.enumerated() {
            let isSelected = index == selectedIndex
            var config = button.configuration
            config?.baseForegroundColor = isSelected ? .systemYellow : .white
            config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 15, weight: isSelected ? .bold : .regular)
                return outgoing
            }
            button.configuration = config
        }
    }

    // MARK: - Pinch-to-Zoom

    private func setupPinchZoom() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchZoom(_:)))
        previewView.addGestureRecognizer(pinchGesture)
    }

    @objc private func handlePinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard let device = currentDevice else { return }

        switch gesture.state {
        case .began:
            pinchStartZoom = device.videoZoomFactor
        case .changed:
            let newZoom = pinchStartZoom * gesture.scale
            applyZoom(newZoom)
        default:
            break
        }
    }

    private func applyZoom(_ targetZoom: CGFloat) {
        guard let device = currentDevice else { return }

        // Clamp to device limits
        let clampedZoom = min(max(device.minAvailableVideoZoomFactor, targetZoom), device.maxAvailableVideoZoomFactor)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
        } catch {
            logger.error("[Camera] Zoom failed: \(error)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Update preview layer frame to match view bounds
        previewLayer?.frame = previewView.bounds

        // Update framing guide layer frame and redraw
        framingGuideLayer?.frame = previewView.bounds
        if framingGuideMode != .none {
            updateFramingGuide()
        }

        // Update layouts for orientation (both iPad and iPhone now have orientation-based layouts)
        updateLayoutForOrientation()
        updateZoomSelectorLayout()
        updateExposureControlLayout()
    }

    // MARK: - Photo Capture

    @objc private func capturePhoto() {
        // Flash immediately on tap (non-blocking)
        flashCaptureIndicator()

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

        // Update save button state
        saveCircleButton.isEnabled = !capturedPhotos.isEmpty
        saveCircleButton.alpha = capturedPhotos.isEmpty ? 0.5 : 1.0

        // Update configuration for color change
        var config = saveCircleButton.configuration ?? UIButton.Configuration.filled()
        config.baseBackgroundColor = capturedPhotos.isEmpty ? .systemGray : .systemGreen
        saveCircleButton.configuration = config

        // Show/hide empty state placeholder
        bufferEmptyPlaceholder.isHidden = !capturedPhotos.isEmpty
    }

    /// Handle captured photo - show editor
    private func handleCapturedPhoto(_ image: UIImage) {
        // Pass viewport size to editor for iPad (nil for iPhone)
        let viewportSize: CGFloat? = isIPadLayout ? iPadViewportSize : nil

        let editorView = PhotoEditorView(
            originalImage: image,
            iPadViewportSize: viewportSize,
            bufferCount: capturedPhotos.count,
            existingBufferPhotos: capturedPhotos,
            onConfirm: { [weak self] editedImage in
                self?.dismiss(animated: true)
                self?.addPhotoToBuffer(editedImage)
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            },
            onDirectUpload: { [weak self] allPhotos in
                // Don't dismiss editor - let origin dismiss camera
                // iOS dismisses both; editor animates out since it's on top
                self?.onPhotosCaptured?(allPhotos)
            }
        )

        let hostingController = UIHostingController(rootView: editorView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    /// Flash white border around preview as capture feedback (non-blocking)
    private func flashCaptureIndicator() {
        let flashBorder = CAShapeLayer()
        flashBorder.path = UIBezierPath(roundedRect: previewView.bounds, cornerRadius: 12).cgPath
        flashBorder.strokeColor = UIColor.white.cgColor
        flashBorder.fillColor = UIColor.clear.cgColor
        flashBorder.lineWidth = 6
        flashBorder.opacity = 0
        previewView.layer.addSublayer(flashBorder)

        // Animate flash
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            flashBorder.removeFromSuperlayer()
        }

        let flashAnimation = CAKeyframeAnimation(keyPath: "opacity")
        flashAnimation.values = [0, 1, 1, 0]
        flashAnimation.keyTimes = [0, 0.1, 0.5, 1.0]
        flashAnimation.duration = 0.3
        flashAnimation.isRemovedOnCompletion = true
        flashBorder.add(flashAnimation, forKey: "flash")

        CATransaction.commit()
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
