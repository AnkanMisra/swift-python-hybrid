import UIKit

struct AnimationHelper {
    
    
    static func fadeIn(_ view: UIView, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        view.alpha = 0
        UIView.animate(withDuration: duration) {
            view.alpha = 1
        } completion: { _ in
            completion?()
        }
    }
    
    static func fadeOut(_ view: UIView, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration) {
            view.alpha = 0
        } completion: { _ in
            completion?()
        }
    }
    
    
    static func scaleUp(_ view: UIView, scale: CGFloat = 1.2, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            view.transform = CGAffineTransform(scaleX: scale, y: scale)
        } completion: { _ in
            completion?()
        }
    }
    
    static func scaleDown(_ view: UIView, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            view.transform = .identity
        } completion: { _ in
            completion?()
        }
    }
    
    
    static func slideInFromLeft(_ view: UIView, distance: CGFloat = 300, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        view.transform = CGAffineTransform(translationX: -distance, y: 0)
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            view.transform = .identity
        } completion: { _ in
            completion?()
        }
    }
    
    static func slideInFromRight(_ view: UIView, distance: CGFloat = 300, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        view.transform = CGAffineTransform(translationX: distance, y: 0)
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            view.transform = .identity
        } completion: { _ in
            completion?()
        }
    }
    
    static func slideInFromTop(_ view: UIView, distance: CGFloat = 300, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        view.transform = CGAffineTransform(translationX: 0, y: -distance)
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            view.transform = .identity
        } completion: { _ in
            completion?()
        }
    }
    
    static func slideInFromBottom(_ view: UIView, distance: CGFloat = 300, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        view.transform = CGAffineTransform(translationX: 0, y: distance)
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            view.transform = .identity
        } completion: { _ in
            completion?()
        }
    }
    
    
    static func rotate(_ view: UIView, angle: CGFloat, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration) {
            view.transform = CGAffineTransform(rotationAngle: angle)
        } completion: { _ in
            completion?()
        }
    }
    
    static func spinOnce(_ view: UIView, duration: TimeInterval = 1.0, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration) {
            view.transform = CGAffineTransform(rotationAngle: .pi * 2)
        } completion: { _ in
            view.transform = .identity
            completion?()
        }
    }
    
    
    static func bounce(_ view: UIView, completion: (() -> Void)? = nil) {
        let originalTransform = view.transform
        
        UIView.animate(withDuration: 0.15) {
            view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.3, initialSpringVelocity: 0.8) {
                view.transform = originalTransform
            } completion: { _ in
                completion?()
            }
        }
    }
    
    
    static func pulse(_ view: UIView, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2) {
            view.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        } completion: { _ in
            UIView.animate(withDuration: 0.2) {
                view.transform = .identity
            } completion: { _ in
                completion?()
            }
        }
    }
    
    
    static func shake(_ view: UIView, completion: (() -> Void)? = nil) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        animation.duration = 0.6
        animation.values = [-20.0, 20.0, -20.0, 20.0, -10.0, 10.0, -5.0, 5.0, 0.0]
        view.layer.add(animation, forKey: "shake")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            completion?()
        }
    }
}
