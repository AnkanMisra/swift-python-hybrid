import Foundation

struct ValidationHelper {
    
    
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailTest.evaluate(with: email)
    }
    
    
    static func isValidPassword(_ password: String) -> Bool {
        return password.count >= 8
    }
    
    static func isStrongPassword(_ password: String) -> Bool {
        
        let minLength = 8
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecialChar = password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
        
        return password.count >= minLength && hasUppercase && hasLowercase && hasDigit && hasSpecialChar
    }
    
    
    static func isValidPhoneNumber(_ phoneNumber: String) -> Bool {
        
        let phoneRegex = "^[\\+]?[1-9]?[0-9]{7,12}$"
        let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phoneTest.evaluate(with: phoneNumber)
    }
    
    
    static func isValidName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.count >= 2 && trimmedName.count <= 50
    }
    
    
    static func isValidAge(_ age: Int) -> Bool {
        return age >= 0 && age <= 150
    }
    
    
    static func isValidURL(_ urlString: String) -> Bool {
        if let url = URL(string: urlString) {
            return UIApplication.shared.canOpenURL(url)
        }
        return false
    }
    
    
    static func isValidCreditCard(_ cardNumber: String) -> Bool {
        let cleanNumber = cardNumber.replacingOccurrences(of: " ", with: "")
        
        
        guard cleanNumber.allSatisfy({ $0.isNumber }) else { return false }
        
        
        guard cleanNumber.count >= 13 && cleanNumber.count <= 19 else { return false }
        
        
        return luhnCheck(cleanNumber)
    }
    
    private static func luhnCheck(_ cardNumber: String) -> Bool {
        let digits = cardNumber.compactMap { Int(String($0)) }
        var sum = 0
        
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        
        return sum % 10 == 0
    }
    
    
    static func isValidDateOfBirth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        
        guard date <= now else { return false }
        
        
        if let years = calendar.dateComponents([.year], from: date, to: now).year {
            return years <= 150
        }
        
        return false
    }
    
    
    static func isNotEmpty(_ string: String) -> Bool {
        return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    static func hasMinLength(_ string: String, minLength: Int) -> Bool {
        return string.count >= minLength
    }
    
    static func hasMaxLength(_ string: String, maxLength: Int) -> Bool {
        return string.count <= maxLength
    }
    
    static func isWithinRange(_ string: String, minLength: Int, maxLength: Int) -> Bool {
        return string.count >= minLength && string.count <= maxLength
    }
}
