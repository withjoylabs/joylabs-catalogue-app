import UIKit
import AVFoundation

/// Simple exposure compensation bar with EV slider and reset button
/// Reset button positioned outside the main slider element for proper centering
class CameraExposureControlView: UIView {

    private var manager: CameraExposureManager?
    private var device: AVCaptureDevice?

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

        // Content stack: [icon] [slider] [label] - centered
        contentStack.addArrangedSubview(exposureIcon)
        contentStack.addArrangedSubview(exposureSlider)
        contentStack.addArrangedSubview(exposureLabel)

        NSLayoutConstraint.activate([
            // Background wraps just the content stack
            backgroundView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: -8),
            backgroundView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: 8),
            backgroundView.topAnchor.constraint(equalTo: contentStack.topAnchor, constant: -4),
            backgroundView.bottomAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 4),

            // Content stack centered in view
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Slider fixed width
            exposureSlider.widthAnchor.constraint(equalToConstant: 140),

            // Reset button outside to the right of background
            resetButton.leadingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 4),
            resetButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // View height
            heightAnchor.constraint(equalToConstant: 44)
        ])
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
