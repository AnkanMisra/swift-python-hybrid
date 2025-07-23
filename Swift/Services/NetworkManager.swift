import Foundation
import Combine
import SystemConfiguration


class NetworkManager: ObservableObject {
    
    
    static let shared = NetworkManager()
    
    private let session: URLSession
    private let baseURL: URL
    private let apiKey: String
    private let timeout: TimeInterval
    private let maxRetries: Int
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isLoading = false
    @Published var connectionStatus: NetworkStatus = .connected
    @Published var requestQueue: [NetworkRequest] = []
    
    
    private init() {
        self.baseURL = URL(string: "https://api.example.com")!
        self.apiKey = "default-api-key"
        self.timeout = 30.0
        self.maxRetries = 3
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.allowsCellularAccess = true
        configuration.waitsForConnectivity = true
        
        self.session = URLSession(configuration: configuration)
        
        setupNetworkMonitoring()
    }
    
    
    private func setupNetworkMonitoring() {
        
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.checkNetworkStatus()
            }
            .store(in: &cancellables)
    }
    
    private func checkNetworkStatus() {
        var flags = SCNetworkReachabilityFlags()
        let reachability = SCNetworkReachabilityCreateWithName(nil, "www.apple.com")
        
        if let reachability = reachability,
           SCNetworkReachabilityGetFlags(reachability, &flags) {
            
            let isReachable = flags.contains(.reachable)
            let requiresConnection = flags.contains(.connectionRequired)
            let isConnected = isReachable && !requiresConnection
            
            DispatchQueue.main.async {
                self.connectionStatus = isConnected ? .connected : .disconnected
                if isConnected {
                    self.processQueuedRequests()
                }
            }
        }
    }
    
    
    func performRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        responseType: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        
        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        
        if let parameters = parameters {
            do {
                switch method {
                case .GET:
                    if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                        var components = urlComponents
                        components.queryItems = parameters.map { key, value in
                            URLQueryItem(name: key, value: "\(value)")
                        }
                        request.url = components.url
                    }
                case .POST, .PUT, .PATCH:
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                case .DELETE:
                    break
                }
            } catch {
                return Fail(error: NetworkError.encodingError)
                    .eraseToAnyPublisher()
            }
        }
        
        return performRequestWithRetry(request: request, responseType: responseType, retryCount: 0)
    }
    
    private func performRequestWithRetry<T: Codable>(
        request: URLRequest,
        responseType: T.Type,
        retryCount: Int
    ) -> AnyPublisher<T, NetworkError> {
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                guard 200...299 ~= httpResponse.statusCode else {
                    throw NetworkError.httpError(httpResponse.statusCode)
                }
                
                return data
            }
            .decode(type: responseType, decoder: JSONDecoder())
            .mapError { error in
                if error is DecodingError {
                    return NetworkError.decodingError
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    return NetworkError.unknown(error.localizedDescription)
                }
            }
            .catch { error -> AnyPublisher<T, NetworkError> in
                if retryCount < self.maxRetries {
                    return self.performRequestWithRetry(
                        request: request,
                        responseType: responseType,
                        retryCount: retryCount + 1
                    )
                    .delay(for: .seconds(pow(2.0, Double(retryCount))), scheduler: DispatchQueue.global())
                    .eraseToAnyPublisher()
                } else {
                    return Fail(error: error)
                        .eraseToAnyPublisher()
                }
            }
            .handleEvents(
                receiveOutput: { _ in
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                },
                receiveCompletion: { _ in
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    
    func uploadData(
        _ data: Data,
        to endpoint: String,
        fileName: String,
        mimeType: String,
        parameters: [String: String]? = nil
    ) -> AnyPublisher<Data, NetworkError> {
        
        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var body = Data()
        
        
        if let parameters = parameters {
            for (key, value) in parameters {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
        }
        
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                guard 200...299 ~= httpResponse.statusCode else {
                    throw NetworkError.httpError(httpResponse.statusCode)
                }
                
                return data
            }
            .mapError { error in
                if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    return NetworkError.unknown(error.localizedDescription)
                }
            }
            .eraseToAnyPublisher()
    }
    
    
    func downloadFile(from url: URL) -> AnyPublisher<URL, NetworkError> {
        return session.downloadTaskPublisher(for: url)
            .tryMap { url, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                guard 200...299 ~= httpResponse.statusCode else {
                    throw NetworkError.httpError(httpResponse.statusCode)
                }
                
                return url
            }
            .mapError { error in
                if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    return NetworkError.unknown(error.localizedDescription)
                }
            }
            .eraseToAnyPublisher()
    }
    
    
    private func processQueuedRequests() {
        guard !requestQueue.isEmpty else { return }
        
        let requestsToProcess = requestQueue
        requestQueue.removeAll()
        
        for request in requestsToProcess {
            performQueuedRequest(request)
        }
    }
    
    private func performQueuedRequest(_ networkRequest: NetworkRequest) {
        
        
    }
    
    
    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
    }
    
    func getCacheSize() -> Int {
        return URLCache.shared.currentDiskUsage
    }
    
    
    func updateApiKey(_ newKey: String) {
        let oldKey = self.apiKey
        
        let newManager = NetworkManager()
        newManager.apiKey = newKey
        
        Logger.shared.info("API key updated from \(oldKey.prefix(4))... to \(newKey.prefix(4))...")
    }
    
    func refreshToken() -> AnyPublisher<String, NetworkError> {
        
        return Just("new-token")
            .setFailureType(to: NetworkError.self)
            .eraseToAnyPublisher()
    }
}


enum NetworkStatus {
    case connected
    case disconnected
    case connecting
}

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case encodingError
    case decodingError
    case httpError(Int)
    case noData
    case timeout
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .encodingError:
            return "Encoding error"
        case .decodingError:
            return "Decoding error"
        case .httpError(let code):
            return "HTTP error with code: \(code)"
        case .noData:
            return "No data received"
        case .timeout:
            return "Request timed out"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

struct NetworkRequest {
    let id: UUID
    let url: URL
    let method: HTTPMethod
    let headers: [String: String]?
    let body: Data?
    let timestamp: Date
    
    init(url: URL, method: HTTPMethod, headers: [String: String]? = nil, body: Data? = nil) {
        self.id = UUID()
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timestamp = Date()
    }
}


extension URLSession {
    func downloadTaskPublisher(for url: URL) -> AnyPublisher<(URL, URLResponse), URLError> {
        return Future { promise in
            let task = self.downloadTask(with: url) { url, response, error in
                if let error = error as? URLError {
                    promise(.failure(error))
                } else if let url = url, let response = response {
                    promise(.success((url, response)))
                } else {
                    promise(.failure(URLError(.unknown)))
                }
            }
            task.resume()
        }
        .eraseToAnyPublisher()
    }
}
