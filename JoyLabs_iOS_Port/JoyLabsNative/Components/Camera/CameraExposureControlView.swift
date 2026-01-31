import UIKit
import AVFoundation

/// Simple exposure compensation bar with EV slider and reset button
/// Reset button positioned outside the main slider element for proper centering
class CameraExposureControlView: UIView {

    private var manager: CameraExposureManager?
    private var device: AVCaptureDevice?

    // MARK: - Orientation Support

    /// Set to true for vertical layout (iPad landscape)
    var isVertical: Bool = false {
        didSet {
            guard oldValue != isVertical else { return }
            updateLayoutForOrientation()
        }
    }

    // Constraint references for orientation switching
    private var viewWidthConstraint: NSLayoutConstraint?
    private var viewHeightConstraint: NSLayoutConstraint?
    private var sliderContainerWidthConstraint: NSLayoutConstraint?
    private var sliderContainerHeightConstraint: NSLayoutConstraint?
    private var resetButtonLeadingConstraint: NSLayoutConstraint?
    private var resetButtonCenterYConstraint: NSLayoutConstraint?
    private var resetButtonTopConstraint: NSLayoutConstraint?
    private var resetButtonCenterXConstraint: NSLayoutConstraint?

    // MARK: - UI Components

    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.layer.cornerRadius = 18
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var exposureIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "sun.max.fill"))
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return imageView
    }()

    private lazy var exposureSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = -2.0
        slider.maximumValue = 2.0
        slider.value = 0
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .gray
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(exposureSliderChanged(_:)), for: .valueChanged)
        return slider
    }()

    /// Container for slider - swaps dimensions for orientation while slider stays fixed size
    private lazy var sliderContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.clipsToBounds = false  // Allow rotated slider to be visible
        return container
    }()

    private lazy var exposureLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        label.text = "0.0"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return label
    }()

    private lazy var resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
        button.tintColor = .gray
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        button.isHidden = true  // Hidden when at default
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(backgroundView)
        addSubview(contentStack)
        addSubview(resetButton)  // Outside backgroundView

        // Slider goes inside container, container goes in stack
        sliderContainer.addSubview(exposureSlider)

        // Content stack: [icon] [sliderContainer] [label] - order changes with orientation
        contentStack.addArrangedSubview(exposureIcon)
        contentStack.addArrangedSubview(sliderContainer)
        contentStack.addArrangedSubview(exposureLabel)

        // Create dimension constraints (will update values in updateLayoutForOrientation)
        viewWidthConstraint = widthAnchor.constraint(equalToConstant: 260)
        viewHeightConstraint = heightAnchor.constraint(equalToConstant: 44)

        // Slider container constraints - swaps dimensions for orientation
        // Portrait: 140 wide × 30 tall (holds horizontal slider)
        // Landscape: 30 wide × 140 tall (holds rotated slider)
        sliderContainerWidthConstraint = sliderContainer.widthAnchor.constraint(equalToConstant: 140)
        sliderContainerHeightConstraint = sliderContainer.heightAnchor.constraint(equalToConstant: 30)

        // Reset button constraints for horizontal (portrait) - right of background
        resetButtonLeadingConstraint = resetButton.leadingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 4)
        resetButtonCenterYConstraint = resetButton.centerYAnchor.constraint(equalTo: centerYAnchor)

        // Reset button constraints for vertical (landscape) - below background
        resetButtonTopConstraint = resetButton.topAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: 4)
        resetButtonCenterXConstraint = resetButton.centerXAnchor.constraint(equalTo: centerXAnchor)

        NSLayoutConstraint.activate([
            // Background wraps just the content stack
            backgroundView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: -8),
            backgroundView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: 8),
            backgroundView.topAnchor.constraint(equalTo: contentStack.topAnchor, constant: -4),
            backgroundView.bottomAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 4),

            // Content stack centered in view
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            // View dimensions
            viewWidthConstraint!,
            viewHeightConstraint!,

            // Slider container initial dimensions
            sliderContainerWidthConstraint!,
            sliderContainerHeightConstraint!,

            // Slider always 140pt wide (track length), centered in container
            exposureSlider.widthAnchor.constraint(equalToConstant: 140),
            exposureSlider.centerXAnchor.constraint(equalTo: sliderContainer.centerXAnchor),
            exposureSlider.centerYAnchor.constraint(equalTo: sliderContainer.centerYAnchor)
        ])

        // Apply initial layout
        updateLayoutForOrientation()
    }

    private func updateLayoutForOrientation() {
        // Deactivate orientation-specific reset button constraints
        resetButtonLeadingConstraint?.isActive = false
        resetButtonCenterYConstraint?.isActive = false
        resetButtonTopConstraint?.isActive = false
        resetButtonCenterXConstraint?.isActive = false

        if isVertical {
            // Landscape: 44 wide × 260 tall, vertical stack
            viewWidthConstraint?.constant = 44
            viewHeightConstraint?.constant = 260

            // Container: 30 wide × 140 tall (holds rotated slider)
            sliderContainerWidthConstraint?.constant = 30
            sliderContainerHeightConstraint?.constant = 140

            contentStack.axis = .vertical
            contentStack.spacing = 8

            // Reorder: icon (top), sliderContainer, label (bottom)
            contentStack.removeArrangedSubview(exposureIcon)
            contentStack.removeArrangedSubview(sliderContainer)
            contentStack.removeArrangedSubview(exposureLabel)
            contentStack.addArrangedSubview(exposureIcon)
            contentStack.addArrangedSubview(sliderContainer)
            contentStack.addArrangedSubview(exposureLabel)

            // Rotate slider for vertical drag (up = increase)
            exposureSlider.transform = CGAffineTransform(rotationAngle: -.pi / 2)

            // Reset button below, centered
            resetButtonTopConstraint?.isActive = true
            resetButtonCenterXConstraint?.isActive = true
        } else {
            // Portrait: 260 wide × 44 tall, horizontal stack
            viewWidthConstraint?.constant = 260
            viewHeightConstraint?.constant = 44

            // Container: 140 wide × 30 tall (holds horizontal slider)
            sliderContainerWidthConstraint?.constant = 140
            sliderContainerHeightConstraint?.constant = 30

            contentStack.axis = .horizontal
            contentStack.spacing = 8

            // Order: icon, sliderContainer, label
            contentStack.removeArrangedSubview(exposureIcon)
            contentStack.removeArrangedSubview(sliderContainer)
            contentStack.removeArrangedSubview(exposureLabel)
            contentStack.addArrangedSubview(exposureIcon)
            contentStack.addArrangedSubview(sliderContainer)
            contentStack.addArrangedSubview(exposureLabel)

            // No rotation
            exposureSlider.transform = .identity

            // Reset button to the right
            resetButtonLeadingConstraint?.isActive = true
            resetButtonCenterYConstraint?.isActive = true
        }

        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: - Configuration

    /// Configure with manager and device
    func configure(manager: CameraExposureManager, device: AVCaptureDevice) {
        self.manager = manager
        self.device = device

        exposureSlider.value = manager.exposureBias
        updateExposureLabel(manager.exposureBias)
    }

    // MARK: - Actions

    @objc private func exposureSliderChanged(_ slider: UISlider) {
        let roundedBias = round(slider.value * 10) / 10
        slider.value = roundedBias

        updateExposureLabel(roundedBias)

        guard let manager = manager, let device = device else { return }
        manager.setExposureBias(roundedBias, device: device)
    }

    @objc private func resetTapped() {
        exposureSlider.value = 0
        updateExposureLabel(0)

        guard let manager = manager, let device = device else { return }
        manager.setExposureBias(0, device: device)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateExposureLabel(_ bias: Float) {
        // Show "0.0" for zero, otherwise show sign
        if bias == 0 {
            exposureLabel.text = "0.0"
            exposureLabel.textColor = .white
            resetButton.isHidden = true
        } else {
            exposureLabel.text = String(format: "%+.1f", bias)
            exposureLabel.textColor = .systemYellow
            resetButton.isHidden = false
        }
    }
}
