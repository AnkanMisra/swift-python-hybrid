import UIKit
import Combine
import QuartzCore


class UIViewManager: ObservableObject {
    
    
    static let shared = UIViewManager()
    
    @Published var currentTheme: AppTheme = .light
    @Published var animationsEnabled = true
    @Published var reducedMotion = false
    @Published var accessibility = AccessibilitySettings()
    
    private var animationQueue: [ViewAnimation] = []
    private var currentAnimations: [String: CAAnimation] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    
    enum AppTheme: String, CaseIterable {
        case light = "light"
        case dark = "dark"
        case auto = "auto"
        
        var colors: ThemeColors {
            switch self {
            case .light:
                return LightThemeColors()
            case .dark:
                return DarkThemeColors()
            case .auto:
                return UITraitCollection.current.userInterfaceStyle == .dark ? DarkThemeColors() : LightThemeColors()
            }
        }
    }
    
    
    private init() {
        setupThemeObserver()
        setupAccessibilityObserver()
        loadUserPreferences()
    }
    
    private func setupThemeObserver() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { _ in
                self.updateThemeIfNeeded()
            }
            .store(in: &cancellables)
    }
    
    private func setupAccessibilityObserver() {
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { _ in
                self.reducedMotion = UIAccessibility.isReduceMotionEnabled
                self.animationsEnabled = !self.reducedMotion
            }
            .store(in: &cancellables)
    }
    
    private func loadUserPreferences() {
        if let themeString = UserDefaults.standard.string(forKey: "app_theme"),
           let theme = AppTheme(rawValue: themeString) {
            currentTheme = theme
        }
        
        animationsEnabled = UserDefaults.standard.bool(forKey: "animations_enabled")
        reducedMotion = UIAccessibility.isReduceMotionEnabled
        
        loadAccessibilitySettings()
    }
    
    private func loadAccessibilitySettings() {
        accessibility = AccessibilitySettings(
            fontSize: UserDefaults.standard.double(forKey: "accessibility_font_size"),
            highContrast: UserDefaults.standard.bool(forKey: "accessibility_high_contrast"),
            voiceOverEnabled: UIAccessibility.isVoiceOverRunning,
            boldText: UIAccessibility.isBoldTextEnabled
        )
    }
    
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "app_theme")
        applyThemeToApplication()
    }
    
    private func updateThemeIfNeeded() {
        if currentTheme == .auto {
            applyThemeToApplication()
        }
    }
    
    private func applyThemeToApplication() {
        let colors = currentTheme.colors
        
        
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithOpaqueBackground()
        navigationBarAppearance.backgroundColor = colors.backgroundColor
        navigationBarAppearance.titleTextAttributes = [.foregroundColor: colors.textColor]
        
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        
        
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = colors.backgroundColor
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        
        if let window = UIApplication.shared.windows.first {
            window.tintColor = colors.accentColor
            window.overrideUserInterfaceStyle = currentTheme == .light ? .light : .dark
        }
    }
    
    
    func createGradientView(colors: [UIColor], direction: GradientDirection = .topToBottom) -> UIView {
        let gradientView = GradientView()
        gradientView.colors = colors
        gradientView.direction = direction
        return gradientView
    }
    
    func createCardView(cornerRadius: CGFloat = 12, shadowOpacity: Float = 0.1) -> UIView {
        let cardView = CardView()
        cardView.cornerRadius = cornerRadius
        cardView.shadowOpacity = shadowOpacity
        cardView.backgroundColor = currentTheme.colors.cardBackgroundColor
        return cardView
    }
    
    func createPulseView() -> UIView {
        let pulseView = PulseView()
        pulseView.pulseColor = currentTheme.colors.accentColor
        return pulseView
    }
    
    func createShimmerView() -> UIView {
        let shimmerView = ShimmerView()
        shimmerView.shimmerColor = currentTheme.colors.shimmerColor
        return shimmerView
    }
    
    func createProgressView(style: ProgressViewStyle = .circular) -> UIView {
        let progressView = CustomProgressView(style: style)
        progressView.tintColor = currentTheme.colors.accentColor
        return progressView
    }
    
    
    func animateView(
        _ view: UIView,
        animation: ViewAnimationType,
        duration: TimeInterval = 0.3,
        delay: TimeInterval = 0,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard animationsEnabled else {
            completion?(true)
            return
        }
        
        let animationBlock = {
            switch animation {
            case .fadeIn:
                view.alpha = 0
                UIView.animate(withDuration: duration, delay: delay, options: .curveEaseInOut) {
                    view.alpha = 1
                } completion: { finished in
                    completion?(finished)
                }
                
            case .fadeOut:
                UIView.animate(withDuration: duration, delay: delay, options: .curveEaseInOut) {
                    view.alpha = 0
                } completion: { finished in
                    completion?(finished)
                }
                
            case .slideInFromLeft:
                let originalTransform = view.transform
                view.transform = CGAffineTransform(translationX: -view.bounds.width, y: 0)
                UIView.animate(withDuration: duration, delay: delay, options: .curveEaseOut) {
                    view.transform = originalTransform
                } completion: { finished in
                    completion?(finished)
                }
                
            case .slideInFromRight:
                let originalTransform = view.transform
                view.transform = CGAffineTransform(translationX: view.bounds.width, y: 0)
                UIView.animate(withDuration: duration, delay: delay, options: .curveEaseOut) {
                    view.transform = originalTransform
                } completion: { finished in
                    completion?(finished)
                }
                
            case .scaleIn:
                let originalTransform = view.transform
                view.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                UIView.animate(withDuration: duration, delay: delay, options: .curveEaseOut) {
                    view.transform = originalTransform
                } completion: { finished in
                    completion?(finished)
                }
                
            case .bounce:
                UIView.animate(withDuration: duration, delay: delay, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: .curveEaseInOut) {
                    view.transform = view.transform.scaledBy(x: 1.1, y: 1.1)
                } completion: { _ in
                    UIView.animate(withDuration: duration * 0.5) {
                        view.transform = CGAffineTransform.identity
                    } completion: { finished in
                        completion?(finished)
                    }
                }
                
            case .shake:
                let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.duration = duration
                animation.values = [-20.0, 20.0, -20.0, 20.0, -10.0, 10.0, -5.0, 5.0, 0.0]
                view.layer.add(animation, forKey: "shake")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    completion?(true)
                }
                
            case .pulse:
                UIView.animate(withDuration: duration / 2, delay: delay, options: [.autoreverse, .repeat]) {
                    view.alpha = 0.5
                } completion: { finished in
                    view.alpha = 1.0
                    completion?(finished)
                }
            }
        }
        
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                animationBlock()
            }
        } else {
            animationBlock()
        }
    }
    
    func animateViews(
        _ views: [UIView],
        animation: ViewAnimationType,
        duration: TimeInterval = 0.3,
        staggerDelay: TimeInterval = 0.1,
        completion: (() -> Void)? = nil
    ) {
        var completedAnimations = 0
        let totalAnimations = views.count
        
        for (index, view) in views.enumerated() {
            let delay = staggerDelay * Double(index)
            animateView(view, animation: animation, duration: duration, delay: delay) { _ in
                completedAnimations += 1
                if completedAnimations == totalAnimations {
                    completion?()
                }
            }
        }
    }
    
    
    func performTransition(
        from fromView: UIView,
        to toView: UIView,
        in containerView: UIView,
        transition: TransitionType,
        duration: TimeInterval = 0.5,
        completion: (() -> Void)? = nil
    ) {
        guard animationsEnabled else {
            fromView.removeFromSuperview()
            containerView.addSubview(toView)
            completion?()
            return
        }
        
        containerView.addSubview(toView)
        
        switch transition {
        case .crossFade:
            toView.alpha = 0
            UIView.animate(withDuration: duration) {
                fromView.alpha = 0
                toView.alpha = 1
            } completion: { _ in
                fromView.removeFromSuperview()
                completion?()
            }
            
        case .slideLeft:
            toView.frame.origin.x = containerView.bounds.width
            UIView.animate(withDuration: duration, options: .curveEaseInOut) {
                fromView.frame.origin.x = -containerView.bounds.width
                toView.frame.origin.x = 0
            } completion: { _ in
                fromView.removeFromSuperview()
                completion?()
            }
            
        case .slideRight:
            toView.frame.origin.x = -containerView.bounds.width
            UIView.animate(withDuration: duration, options: .curveEaseInOut) {
                fromView.frame.origin.x = containerView.bounds.width
                toView.frame.origin.x = 0
            } completion: { _ in
                fromView.removeFromSuperview()
                completion?()
            }
            
        case .slideUp:
            toView.frame.origin.y = containerView.bounds.height
            UIView.animate(withDuration: duration, options: .curveEaseInOut) {
                fromView.frame.origin.y = -containerView.bounds.height
                toView.frame.origin.y = 0
            } completion: { _ in
                fromView.removeFromSuperview()
                completion?()
            }
            
        case .slideDown:
            toView.frame.origin.y = -containerView.bounds.height
            UIView.animate(withDuration: duration, options: .curveEaseInOut) {
                fromView.frame.origin.y = containerView.bounds.height
                toView.frame.origin.y = 0
            } completion: { _ in
                fromView.removeFromSuperview()
                completion?()
            }
            
        case .zoom:
            toView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            toView.alpha = 0
            UIView.animate(withDuration: duration, options: .curveEaseOut) {
                fromView.transform = CGAffineTransform(scaleX: 2.0, y: 2.0)
                fromView.alpha = 0
                toView.transform = CGAffineTransform.identity
                toView.alpha = 1
            } completion: { _ in
                fromView.removeFromSuperview()
                fromView.transform = CGAffineTransform.identity
                completion?()
            }
        }
    }
    
    
    func setupAutoLayout(for view: UIView, in containerView: UIView, constraints: LayoutConstraints) {
        containerView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        
        var activeConstraints: [NSLayoutConstraint] = []
        
        if let top = constraints.top {
            activeConstraints.append(view.topAnchor.constraint(equalTo: containerView.topAnchor, constant: top))
        }
        
        if let bottom = constraints.bottom {
            activeConstraints.append(view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -bottom))
        }
        
        if let leading = constraints.leading {
            activeConstraints.append(view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: leading))
        }
        
        if let trailing = constraints.trailing {
            activeConstraints.append(view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -trailing))
        }
        
        if let centerX = constraints.centerX {
            activeConstraints.append(view.centerXAnchor.constraint(equalTo: containerView.centerXAnchor, constant: centerX))
        }
        
        if let centerY = constraints.centerY {
            activeConstraints.append(view.centerYAnchor.constraint(equalTo: containerView.centerYAnchor, constant: centerY))
        }
        
        if let width = constraints.width {
            activeConstraints.append(view.widthAnchor.constraint(equalToConstant: width))
        }
        
        if let height = constraints.height {
            activeConstraints.append(view.heightAnchor.constraint(equalToConstant: height))
        }
        
        NSLayoutConstraint.activate(activeConstraints)
    }
    
    func createStackView(
        axis: NSLayoutConstraint.Axis,
        distribution: UIStackView.Distribution = .fill,
        alignment: UIStackView.Alignment = .fill,
        spacing: CGFloat = 8
    ) -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = axis
        stackView.distribution = distribution
        stackView.alignment = alignment
        stackView.spacing = spacing
        return stackView
    }
    
    
    func addTapGesture(to view: UIView, action: @escaping () -> Void) -> UITapGestureRecognizer {
        let tapGesture = UITapGestureRecognizer()
        tapGesture.addTarget(self, action: #selector(handleTapGesture(_:)))
        view.addGestureRecognizer(tapGesture)
        view.isUserInteractionEnabled = true
        
        
        objc_setAssociatedObject(tapGesture, &AssociatedKeys.tapAction, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        
        return tapGesture
    }
    
    func addPanGesture(to view: UIView, action: @escaping (UIPanGestureRecognizer) -> Void) -> UIPanGestureRecognizer {
        let panGesture = UIPanGestureRecognizer()
        panGesture.addTarget(self, action: #selector(handlePanGesture(_:)))
        view.addGestureRecognizer(panGesture)
        view.isUserInteractionEnabled = true
        
        objc_setAssociatedObject(panGesture, &AssociatedKeys.panAction, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        
        return panGesture
    }
    
    func addPinchGesture(to view: UIView, action: @escaping (UIPinchGestureRecognizer) -> Void) -> UIPinchGestureRecognizer {
        let pinchGesture = UIPinchGestureRecognizer()
        pinchGesture.addTarget(self, action: #selector(handlePinchGesture(_:)))
        view.addGestureRecognizer(pinchGesture)
        view.isUserInteractionEnabled = true
        
        objc_setAssociatedObject(pinchGesture, &AssociatedKeys.pinchAction, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        
        return pinchGesture
    }
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        if let action = objc_getAssociatedObject(gesture, &AssociatedKeys.tapAction) as? () -> Void {
            action()
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        if let action = objc_getAssociatedObject(gesture, &AssociatedKeys.panAction) as? (UIPanGestureRecognizer) -> Void {
            action(gesture)
        }
    }
    
    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        if let action = objc_getAssociatedObject(gesture, &AssociatedKeys.pinchAction) as? (UIPinchGestureRecognizer) -> Void {
            action(gesture)
        }
    }
    
    
    func configureAccessibility(
        for view: UIView,
        label: String? = nil,
        hint: String? = nil,
        traits: UIAccessibilityTraits = .none,
        isAccessibilityElement: Bool = true
    ) {
        view.isAccessibilityElement = isAccessibilityElement
        view.accessibilityLabel = label
        view.accessibilityHint = hint
        view.accessibilityTraits = traits
        
        if accessibility.highContrast {
            view.layer.borderWidth = 1.0
            view.layer.borderColor = currentTheme.colors.accentColor.cgColor
        }
    }
    
    func announceForAccessibility(_ text: String, priority: UIAccessibilityPriority = .default) {
        let announcement = NSAttributedString(
            string: text,
            attributes: [.accessibilitySpeechPriority: priority.rawValue]
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
    
    
    func printViewHierarchy(for view: UIView, indent: String = "") {
        print("\(indent)\(type(of: view)) - Frame: \(view.frame)")
        for subview in view.subviews {
            printViewHierarchy(for: subview, indent: indent + "  ")
        }
    }
    
    func findViews<T: UIView>(ofType type: T.Type, in view: UIView) -> [T] {
        var views: [T] = []
        
        if let matchingView = view as? T {
            views.append(matchingView)
        }
        
        for subview in view.subviews {
            views.append(contentsOf: findViews(ofType: type, in: subview))
        }
        
        return views
    }
    
    
    func optimizeViewPerformance(_ view: UIView) {
        
        view.layer.shouldRasterize = true
        view.layer.rasterizationScale = UIScreen.main.scale
        
        
        if view.layer.cornerRadius > 0 {
            view.layer.masksToBounds = true
        }
        
        
        view.layer.allowsGroupOpacity = false
    }
    
    func enableDrawRectOptimization(_ view: UIView) {
        view.contentMode = .redraw
        view.clearsContextBeforeDrawing = false
    }
}


enum ViewAnimationType {
    case fadeIn
    case fadeOut
    case slideInFromLeft
    case slideInFromRight
    case scaleIn
    case bounce
    case shake
    case pulse
}

enum TransitionType {
    case crossFade
    case slideLeft
    case slideRight
    case slideUp
    case slideDown
    case zoom
}

enum GradientDirection {
    case topToBottom
    case leftToRight
    case topLeftToBottomRight
    case topRightToBottomLeft
}

enum ProgressViewStyle {
    case circular
    case linear
    case ring
}

struct LayoutConstraints {
    let top: CGFloat?
    let bottom: CGFloat?
    let leading: CGFloat?
    let trailing: CGFloat?
    let centerX: CGFloat?
    let centerY: CGFloat?
    let width: CGFloat?
    let height: CGFloat?
    
    init(
        top: CGFloat? = nil,
        bottom: CGFloat? = nil,
        leading: CGFloat? = nil,
        trailing: CGFloat? = nil,
        centerX: CGFloat? = nil,
        centerY: CGFloat? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil
    ) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
    }
}

struct ViewAnimation {
    let view: UIView
    let type: ViewAnimationType
    let duration: TimeInterval
    let delay: TimeInterval
}

struct AccessibilitySettings {
    let fontSize: Double
    let highContrast: Bool
    let voiceOverEnabled: Bool
    let boldText: Bool
    
    init(
        fontSize: Double = 16.0,
        highContrast: Bool = false,
        voiceOverEnabled: Bool = false,
        boldText: Bool = false
    ) {
        self.fontSize = fontSize
        self.highContrast = highContrast
        self.voiceOverEnabled = voiceOverEnabled
        self.boldText = boldText
    }
}


protocol ThemeColors {
    var backgroundColor: UIColor { get }
    var textColor: UIColor { get }
    var secondaryTextColor: UIColor { get }
    var accentColor: UIColor { get }
    var cardBackgroundColor: UIColor { get }
    var separatorColor: UIColor { get }
    var shimmerColor: UIColor { get }
    var errorColor: UIColor { get }
    var successColor: UIColor { get }
    var warningColor: UIColor { get }
}

struct LightThemeColors: ThemeColors {
    let backgroundColor = UIColor.systemBackground
    let textColor = UIColor.label
    let secondaryTextColor = UIColor.secondaryLabel
    let accentColor = UIColor.systemBlue
    let cardBackgroundColor = UIColor.secondarySystemBackground
    let separatorColor = UIColor.separator
    let shimmerColor = UIColor.systemGray5
    let errorColor = UIColor.systemRed
    let successColor = UIColor.systemGreen
    let warningColor = UIColor.systemOrange
}

struct DarkThemeColors: ThemeColors {
    let backgroundColor = UIColor.systemBackground
    let textColor = UIColor.label
    let secondaryTextColor = UIColor.secondaryLabel
    let accentColor = UIColor.systemBlue
    let cardBackgroundColor = UIColor.secondarySystemBackground
    let separatorColor = UIColor.separator
    let shimmerColor = UIColor.systemGray4
    let errorColor = UIColor.systemRed
    let successColor = UIColor.systemGreen
    let warningColor = UIColor.systemOrange
}


class GradientView: UIView {
    var colors: [UIColor] = [] {
        didSet {
            updateGradient()
        }
    }
    
    var direction: GradientDirection = .topToBottom {
        didSet {
            updateGradient()
        }
    }
    
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }
    
    private var gradientLayer: CAGradientLayer {
        return layer as! CAGradientLayer
    }
    
    private func updateGradient() {
        gradientLayer.colors = colors.map { $0.cgColor }
        
        switch direction {
        case .topToBottom:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        case .leftToRight:
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        case .topLeftToBottomRight:
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        case .topRightToBottomLeft:
            gradientLayer.startPoint = CGPoint(x: 1, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0, y: 1)
        }
    }
}

class CardView: UIView {
    var cornerRadius: CGFloat = 12 {
        didSet {
            layer.cornerRadius = cornerRadius
        }
    }
    
    var shadowOpacity: Float = 0.1 {
        didSet {
            layer.shadowOpacity = shadowOpacity
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        layer.cornerRadius = cornerRadius
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = shadowOpacity
        layer.masksToBounds = false
    }
}

class PulseView: UIView {
    var pulseColor: UIColor = .systemBlue {
        didSet {
            setupPulseAnimation()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPulseAnimation()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPulseAnimation()
    }
    
    private func setupPulseAnimation() {
        backgroundColor = pulseColor
        
        let pulseAnimation = CABasicAnimation(keyPath: "opacity")
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 0.3
        pulseAnimation.duration = 1.0
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        
        layer.add(pulseAnimation, forKey: "pulse")
    }
}

class ShimmerView: UIView {
    var shimmerColor: UIColor = .systemGray5 {
        didSet {
            setupShimmerAnimation()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupShimmerAnimation()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupShimmerAnimation()
    }
    
    private func setupShimmerAnimation() {
        backgroundColor = shimmerColor
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            shimmerColor.cgColor,
            shimmerColor.withAlphaComponent(0.5).cgColor,
            shimmerColor.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 0.5, 1]
        
        let shimmerAnimation = CABasicAnimation(keyPath: "locations")
        shimmerAnimation.fromValue = [-1, -0.5, 0]
        shimmerAnimation.toValue = [1, 1.5, 2]
        shimmerAnimation.duration = 1.5
        shimmerAnimation.repeatCount = .infinity
        
        gradientLayer.add(shimmerAnimation, forKey: "shimmer")
        layer.addSublayer(gradientLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.first?.frame = bounds
    }
}

class CustomProgressView: UIView {
    private let style: ProgressViewStyle
    private var progressLayer: CAShapeLayer?
    
    var progress: Float = 0 {
        didSet {
            updateProgress()
        }
    }
    
    var tintColor: UIColor = .systemBlue {
        didSet {
            progressLayer?.strokeColor = tintColor.cgColor
        }
    }
    
    init(style: ProgressViewStyle) {
        self.style = style
        super.init(frame: .zero)
        setupProgressView()
    }
    
    required init?(coder: NSCoder) {
        self.style = .circular
        super.init(coder: coder)
        setupProgressView()
    }
    
    private func setupProgressView() {
        switch style {
        case .circular:
            setupCircularProgress()
        case .linear:
            setupLinearProgress()
        case .ring:
            setupRingProgress()
        }
    }
    
    private func setupCircularProgress() {
        let circularPath = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: min(bounds.width, bounds.height) / 2 - 10,
            startAngle: -CGFloat.pi / 2,
            endAngle: 3 * CGFloat.pi / 2,
            clockwise: true
        )
        
        progressLayer = CAShapeLayer()
        progressLayer?.path = circularPath.cgPath
        progressLayer?.fillColor = UIColor.clear.cgColor
        progressLayer?.strokeColor = tintColor.cgColor
        progressLayer?.lineWidth = 6
        progressLayer?.strokeEnd = 0
        
        layer.addSublayer(progressLayer!)
    }
    
    private func setupLinearProgress() {
        progressLayer = CAShapeLayer()
        progressLayer?.fillColor = tintColor.cgColor
        progressLayer?.frame = CGRect(x: 0, y: 0, width: 0, height: bounds.height)
        
        layer.addSublayer(progressLayer!)
    }
    
    private func setupRingProgress() {
        let ringPath = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: min(bounds.width, bounds.height) / 2 - 5,
            startAngle: 0,
            endAngle: 2 * CGFloat.pi,
            clockwise: true
        )
        
        progressLayer = CAShapeLayer()
        progressLayer?.path = ringPath.cgPath
        progressLayer?.fillColor = UIColor.clear.cgColor
        progressLayer?.strokeColor = tintColor.cgColor
        progressLayer?.lineWidth = 10
        progressLayer?.strokeEnd = 0
        
        layer.addSublayer(progressLayer!)
    }
    
    private func updateProgress() {
        let clampedProgress = CGFloat(max(0, min(1, progress)))
        
        switch style {
        case .circular, .ring:
            progressLayer?.strokeEnd = clampedProgress
        case .linear:
            progressLayer?.frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width * clampedProgress,
                height: bounds.height
            )
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setupProgressView()
        updateProgress()
    }
}


private struct AssociatedKeys {
    static var tapAction = "tapAction"
    static var panAction = "panAction"
    static var pinchAction = "pinchAction"
}
