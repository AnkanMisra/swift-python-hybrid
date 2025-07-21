import Foundation
import UIKit

struct Constants {
    
    
    struct API {
        static let baseURL = "https://api.example.com"
        static let timeout: TimeInterval = 30.0
    }
    
    
    struct Colors {
        static let primary = UIColor.systemBlue
        static let secondary = UIColor.systemGray
        static let background = UIColor.systemBackground
        static let text = UIColor.label
    }
    
    
    struct Fonts {
        static let title = UIFont.systemFont(ofSize: 24, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 18, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 16, weight: .regular)
        static let caption = UIFont.systemFont(ofSize: 14, weight: .light)
    }
    
    
    struct Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    
    struct Animation {
        static let duration: TimeInterval = 0.3
        static let springDamping: CGFloat = 0.8
        static let springVelocity: CGFloat = 0.5
    }
}
