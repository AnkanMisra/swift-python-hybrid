import Foundation

struct Logger {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    static func log(_ message: String, level: Level = .info) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("\(timestamp) [\(level.rawValue)] \(message)")
    }
}


Logger.log("Application started", level: .info)
Logger.log("Fetching data", level: .debug)
Logger.log("Data fetched successfully", level: .info)
Logger.log("An unexpected error occurred", level: .error)

