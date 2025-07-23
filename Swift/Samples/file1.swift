import Foundation
import UIKit

class WeatherService {
    private let apiKey = "demo-api-key"
    private let baseURL = "https://api.openweathermap.org/data/2.5"
    
    func fetchWeatherData(for city: String, completion: @escaping (Result<WeatherData, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/weather?q=\(city)&appid=\(apiKey)&units=metric") else {
            completion(.failure(WeatherError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(WeatherError.noData))
                return
            }
            
            do {
                let weatherData = try JSONDecoder().decode(WeatherData.self, from: data)
                completion(.success(weatherData))
            } catch {
                completion(.failure(WeatherError.decodingError))
            }
        }.resume()
    }
    
    func getForecast(for city: String, days: Int = 5) async throws -> ForecastData {
        guard let url = URL(string: "\(baseURL)/forecast?q=\(city)&appid=\(apiKey)&units=metric&cnt=\(days * 8)") else {
            throw WeatherError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ForecastData.self, from: data)
    }
}

struct WeatherData: Codable {
    let name: String
    let main: MainWeather
    let weather: [Weather]
    let wind: Wind
    let sys: SystemInfo
    
    struct MainWeather: Codable {
        let temp: Double
        let feelsLike: Double
        let tempMin: Double
        let tempMax: Double
        let pressure: Int
        let humidity: Int
        
        enum CodingKeys: String, CodingKey {
            case temp
            case feelsLike = "feels_like"
            case tempMin = "temp_min"
            case tempMax = "temp_max"
            case pressure
            case humidity
        }
    }
    
    struct Weather: Codable {
        let id: Int
        let main: String
        let description: String
        let icon: String
    }
    
    struct Wind: Codable {
        let speed: Double
        let deg: Int
    }
    
    struct SystemInfo: Codable {
        let country: String
        let sunrise: Int
        let sunset: Int
    }
}

struct ForecastData: Codable {
    let list: [ForecastItem]
    let city: City
    
    struct ForecastItem: Codable {
        let dt: Int
        let main: WeatherData.MainWeather
        let weather: [WeatherData.Weather]
        let wind: WeatherData.Wind
        let dtTxt: String
        
        enum CodingKeys: String, CodingKey {
            case dt
            case main
            case weather
            case wind
            case dtTxt = "dt_txt"
        }
    }
    
    struct City: Codable {
        let id: Int
        let name: String
        let country: String
        let coord: Coordinate
        
        struct Coordinate: Codable {
            let lat: Double
            let lon: Double
        }
    }
}

enum WeatherError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .noData:
            return "No data received from server"
        case .decodingError:
            return "Failed to decode weather data"
        case .networkError:
            return "Network connection error"
        }
    }
}

