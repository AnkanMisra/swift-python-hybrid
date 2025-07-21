import Foundation
import Combine


class WeatherService: ObservableObject {
    @Published var temperature: Double = 0.0
    @Published var humidity: Double = 0.0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    struct WeatherData: Codable {
        let temperature: Double
        let humidity: Double
        let location: String
        let timestamp: Date
    }
    
    func fetchWeather(for city: String) {
        isLoading = true
        errorMessage = nil
        
        
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .first()
            .map { _ in
                WeatherData(
                    temperature: Double.random(in: 15...35),
                    humidity: Double.random(in: 30...80),
                    location: city,
                    timestamp: Date()
                )
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] weatherData in
                    self?.temperature = weatherData.temperature
                    self?.humidity = weatherData.humidity
                }
            )
            .store(in: &cancellables)
    }
}


class DataStreamProcessor {
    private var cancellables = Set<AnyCancellable>()
    
    func processDataStream() {
        let numbers = PassthroughSubject<Int, Never>()
        
        
        numbers
            .filter { $0 > 0 }  
            .map { $0 * 2 }     
            .compactMap { value -> String? in
                value > 10 ? "Large: \(value)" : "Small: \(value)"
            }
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { result in
                print("Processed: \(result)")
            }
            .store(in: &cancellables)
        
        
        DispatchQueue.global().async {
            for i in 1...20 {
                numbers.send(i)
                Thread.sleep(forTimeInterval: 0.1)
            }
            numbers.send(completion: .finished)
        }
    }
}


class SearchManager: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [String] = []
    @Published var isSearching: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSearch()
    }
    
    private func setupSearch() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                self?.performSearch(query: searchText)
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        
        let mockData = [
            "Apple", "Banana", "Cherry", "Date", "Elderberry",
            "Fig", "Grape", "Honeydew", "Kiwi", "Lemon",
            "Mango", "Nectarine", "Orange", "Papaya", "Quince"
        ]
        
        Just(mockData)
            .delay(for: .milliseconds(500), scheduler: DispatchQueue.global())
            .map { fruits in
                fruits.filter { $0.lowercased().contains(query.lowercased()) }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in
                self?.searchResults = results
                self?.isSearching = false
            }
            .store(in: &cancellables)
    }
}


extension NotificationCenter {
    func publisher(for name: Notification.Name, object: AnyObject? = nil) -> AnyPublisher<Notification, Never> {
        return NotificationCenter.Publisher(center: self, name: name, object: object)
            .eraseToAnyPublisher()
    }
}


extension Publisher {
    func withLatestFrom<Other: Publisher, Result>(
        _ other: Other,
        resultSelector: @escaping (Output, Other.Output) -> Result
    ) -> Publishers.WithLatestFrom<Self, Other, Result> {
        return Publishers.WithLatestFrom(upstream: self, second: other, resultSelector: resultSelector)
    }
}

extension Publishers {
    struct WithLatestFrom<Upstream: Publisher, Other: Publisher, Output>: Publisher {
        typealias Failure = Upstream.Failure
        
        let upstream: Upstream
        let second: Other
        let resultSelector: (Upstream.Output, Other.Output) -> Output
        
        func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let subscription = WithLatestFromSubscription(
                upstream: upstream,
                second: second,
                subscriber: subscriber,
                resultSelector: resultSelector
            )
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class WithLatestFromSubscription<Upstream: Publisher, Other: Publisher, S: Subscriber, Output>: Subscription
    where S.Input == Output, S.Failure == Upstream.Failure {
        
        private var subscriber: S?
        private let resultSelector: (Upstream.Output, Other.Output) -> Output
        private var latestSecond: Other.Output?
        private var upstreamCancellable: AnyCancellable?
        private var secondCancellable: AnyCancellable?
        
        init(upstream: Upstream, second: Other, subscriber: S, resultSelector: @escaping (Upstream.Output, Other.Output) -> Output) {
            self.subscriber = subscriber
            self.resultSelector = resultSelector
            
            secondCancellable = second.sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] value in
                    self?.latestSecond = value
                }
            )
            
            upstreamCancellable = upstream.sink(
                receiveCompletion: { [weak self] completion in
                    self?.subscriber?.receive(completion: completion)
                },
                receiveValue: { [weak self] upstreamValue in
                    guard let self = self,
                          let latestSecond = self.latestSecond else { return }
                    
                    let result = self.resultSelector(upstreamValue, latestSecond)
                    _ = self.subscriber?.receive(result)
                }
            )
        }
        
        func request(_ demand: Subscribers.Demand) {}
        
        func cancel() {
            upstreamCancellable?.cancel()
            secondCancellable?.cancel()
            subscriber = nil
        }
    }
}


class ReactiveExamples {
    private var cancellables = Set<AnyCancellable>()
    
    func demonstrateUsage() {
        let weatherService = WeatherService()
        let searchManager = SearchManager()
        let dataProcessor = DataStreamProcessor()
        
        
        weatherService.$temperature
            .combineLatest(weatherService.$humidity)
            .map { temp, humidity in
                "Temperature: \(temp)°C, Humidity: \(humidity)%"
            }
            .sink { weatherInfo in
                print(weatherInfo)
            }
            .store(in: &cancellables)
        
        
        weatherService.fetchWeather(for: "San Francisco")
        
        
        searchManager.$searchResults
            .sink { results in
                print("Search results: \(results)")
            }
            .store(in: &cancellables)
        
        
        searchManager.searchText = "app"
        
        
        dataProcessor.processDataStream()
    }
}
