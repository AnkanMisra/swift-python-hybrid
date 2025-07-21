import Foundation

struct JSONHandler {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    static func encode<T: Codable>(_ object: T) -> Data? {
        do {
            return try encoder.encode(object)
        } catch {
            print("Encoding error: \(error)")
            return nil
        }
    }
    
    static func decode<T: Codable>(_ type: T.Type, from data: Data) -> T? {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            print("Decoding error: \(error)")
            return nil
        }
    }
    
    static func saveToFile<T: Codable>(_ object: T, to url: URL) -> Bool {
        guard let data = encode(object) else { return false }
        
        do {
            try data.write(to: url)
            return true
        } catch {
            print("File write error: \(error)")
            return false
        }
    }
    
    static func loadFromFile<T: Codable>(_ type: T.Type, from url: URL) -> T? {
        do {
            let data = try Data(contentsOf: url)
            return decode(type, from: data)
        } catch {
            print("File read error: \(error)")
            return nil
        }
    }
}


struct Person: Codable {
    let id: UUID
    let firstName: String
    let lastName: String
    let email: String
    let dateOfBirth: Date
    let address: Address
    let phoneNumbers: [PhoneNumber]
    
    var fullName: String {
        return "\(firstName) \(lastName)"
    }
    
    struct Address: Codable {
        let street: String
        let city: String
        let state: String
        let zipCode: String
        let country: String
    }
    
    struct PhoneNumber: Codable {
        let type: PhoneType
        let number: String
        
        enum PhoneType: String, Codable, CaseIterable {
            case home = "home"
            case work = "work"
            case mobile = "mobile"
        }
    }
}

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: T?
    let timestamp: Date
    let version: String
    
    init(success: Bool, message: String? = nil, data: T? = nil, version: String = "1.0") {
        self.success = success
        self.message = message
        self.data = data
        self.timestamp = Date()
        self.version = version
    }
}


extension String {
    func toJSON<T: Codable>(_ type: T.Type) -> T? {
        guard let data = self.data(using: .utf8) else { return nil }
        return JSONHandler.decode(type, from: data)
    }
}

extension Codable {
    func toJSONString() -> String? {
        guard let data = JSONHandler.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    func toDictionary() -> [String: Any]? {
        guard let data = JSONHandler.encode(self) else { return nil }
        
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            print("Dictionary conversion error: \(error)")
            return nil
        }
    }
}


class JSONExamples {
    static func demonstrateUsage() {
        
        let address = Person.Address(
            street: "123 Main St",
            city: "San Francisco",
            state: "CA",
            zipCode: "94102",
            country: "USA"
        )
        
        let phoneNumbers = [
            Person.PhoneNumber(type: .mobile, number: "+1-555-0123"),
            Person.PhoneNumber(type: .work, number: "+1-555-0456")
        ]
        
        let person = Person(
            id: UUID(),
            firstName: "John",
            lastName: "Doe",
            email: "john.doe@example.com",
            dateOfBirth: Date(timeIntervalSince1970: 631152000), 
            address: address,
            phoneNumbers: phoneNumbers
        )
        
        
        if let jsonString = person.toJSONString() {
            print("Person JSON:\n\(jsonString)")
        }
        
        
        let response = APIResponse(success: true, message: "User retrieved successfully", data: person)
        
        if let responseJSON = response.toJSONString() {
            print("API Response JSON:\n\(responseJSON)")
        }
    }
}
