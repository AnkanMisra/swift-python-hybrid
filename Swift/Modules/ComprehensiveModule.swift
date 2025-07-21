import UIKit
import Foundation
import CoreData


struct Product: Codable {
    let id: Int
    let name: String
    let description: String
    let price: Double
    let category: ProductCategory
    let imageURL: String?
    let inStock: Bool
    let rating: Double
    let reviewCount: Int
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case price
        case category
        case imageURL = "image_url"
        case inStock = "in_stock"
        case rating
        case reviewCount = "review_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


enum ProductCategory: String, Codable, CaseIterable {
    case electronics = "electronics"
    case clothing = "clothing"
    case books = "books"
    case home = "home"
    case sports = "sports"
    case beauty = "beauty"
    case toys = "toys"
    case automotive = "automotive"
    
    var displayName: String {
        switch self {
        case .electronics:
            return "Electronics"
        case .clothing:
            return "Clothing & Fashion"
        case .books:
            return "Books & Media"
        case .home:
            return "Home & Garden"
        case .sports:
            return "Sports & Outdoors"
        case .beauty:
            return "Beauty & Personal Care"
        case .toys:
            return "Toys & Games"
        case .automotive:
            return "Automotive"
        }
    }
    
    var icon: String {
        switch self {
        case .electronics:
            return "laptopcomputer"
        case .clothing:
            return "tshirt"
        case .books:
            return "book"
        case .home:
            return "house"
        case .sports:
            return "sportscourt"
        case .beauty:
            return "face.smiling"
        case .toys:
            return "gamecontroller"
        case .automotive:
            return "car"
        }
    }
}


struct CartItem: Codable {
    let product: Product
    var quantity: Int
    
    var totalPrice: Double {
        return product.price * Double(quantity)
    }
}


enum OrderStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case shipped = "shipped"
    case delivered = "delivered"
    case cancelled = "cancelled"
    
    var displayName: String {
        return rawValue.capitalized
    }
    
    var color: UIColor {
        switch self {
        case .pending:
            return .systemOrange
        case .processing:
            return .systemBlue
        case .shipped:
            return .systemPurple
        case .delivered:
            return .systemGreen
        case .cancelled:
            return .systemRed
        }
    }
}


struct Order: Codable {
    let id: String
    let items: [CartItem]
    let totalAmount: Double
    let status: OrderStatus
    let shippingAddress: Address
    let billingAddress: Address
    let paymentMethod: PaymentMethod
    let orderDate: Date
    let estimatedDelivery: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case items
        case totalAmount = "total_amount"
        case status
        case shippingAddress = "shipping_address"
        case billingAddress = "billing_address"
        case paymentMethod = "payment_method"
        case orderDate = "order_date"
        case estimatedDelivery = "estimated_delivery"
    }
}


struct Address: Codable {
    let street: String
    let city: String
    let state: String
    let zipCode: String
    let country: String
    
    var fullAddress: String {
        return "\(street), \(city), \(state) \(zipCode), \(country)"
    }
    
    enum CodingKeys: String, CodingKey {
        case street
        case city
        case state
        case zipCode = "zip_code"
        case country
    }
}


enum PaymentMethod: String, Codable {
    case creditCard = "credit_card"
    case debitCard = "debit_card"
    case paypal = "paypal"
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    
    var displayName: String {
        switch self {
        case .creditCard:
            return "Credit Card"
        case .debitCard:
            return "Debit Card"
        case .paypal:
            return "PayPal"
        case .applePay:
            return "Apple Pay"
        case .googlePay:
            return "Google Pay"
        }
    }
    
    var icon: String {
        switch self {
        case .creditCard, .debitCard:
            return "creditcard"
        case .paypal:
            return "p.circle"
        case .applePay:
            return "apple.logo"
        case .googlePay:
            return "g.circle"
        }
    }
}


class ShoppingCartManager: ObservableObject {
    static let shared = ShoppingCartManager()
    
    @Published var cartItems: [CartItem] = []
    @Published var totalItems: Int = 0
    @Published var totalAmount: Double = 0.0
    
    private init() {
        loadCartFromStorage()
        updateTotals()
    }
    
    func addToCart(product: Product, quantity: Int = 1) {
        if let index = cartItems.firstIndex(where: { $0.product.id == product.id }) {
            cartItems[index].quantity += quantity
        } else {
            let newItem = CartItem(product: product, quantity: quantity)
            cartItems.append(newItem)
        }
        updateTotals()
        saveCartToStorage()
    }
    
    func removeFromCart(product: Product) {
        cartItems.removeAll { $0.product.id == product.id }
        updateTotals()
        saveCartToStorage()
    }
    
    func updateQuantity(for product: Product, quantity: Int) {
        if let index = cartItems.firstIndex(where: { $0.product.id == product.id }) {
            if quantity > 0 {
                cartItems[index].quantity = quantity
            } else {
                cartItems.remove(at: index)
            }
        }
        updateTotals()
        saveCartToStorage()
    }
    
    func clearCart() {
        cartItems.removeAll()
        updateTotals()
        saveCartToStorage()
    }
    
    private func updateTotals() {
        totalItems = cartItems.reduce(0) { $0 + $1.quantity }
        totalAmount = cartItems.reduce(0) { $0 + $1.totalPrice }
    }
    
    private func saveCartToStorage() {
        do {
            let data = try JSONEncoder().encode(cartItems)
            UserDefaults.standard.set(data, forKey: "shopping_cart")
        } catch {
            print("Failed to save cart: \(error)")
        }
    }
    
    private func loadCartFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: "shopping_cart") else { return }
        
        do {
            cartItems = try JSONDecoder().decode([CartItem].self, from: data)
        } catch {
            print("Failed to load cart: \(error)")
            cartItems = []
        }
    }
}


class ProductService {
    static let shared = ProductService()
    
    private let baseURL = "https://api.ecommerce.com"
    private let session = URLSession.shared
    
    private init() {}
    
    func fetchProducts(category: ProductCategory? = nil, page: Int = 1, limit: Int = 20) async throws -> [Product] {
        var urlComponents = URLComponents(string: "\(baseURL)/products")!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }
        
        do {
            let products = try JSONDecoder().decode([Product].self, from: data)
            return products
        } catch {
            throw NetworkError.decodingError
        }
    }
    
    func searchProducts(query: String, page: Int = 1, limit: Int = 20) async throws -> [Product] {
        var urlComponents = URLComponents(string: "\(baseURL)/products/search")!
        
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }
        
        do {
            let products = try JSONDecoder().decode([Product].self, from: data)
            return products
        } catch {
            throw NetworkError.decodingError
        }
    }
    
    func fetchProduct(by id: Int) async throws -> Product {
        guard let url = URL(string: "\(baseURL)/products/\(id)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }
        
        do {
            let product = try JSONDecoder().decode(Product.self, from: data)
            return product
        } catch {
            throw NetworkError.decodingError
        }
    }
}


class OrderService {
    static let shared = OrderService()
    
    private let baseURL = "https://api.ecommerce.com"
    private let session = URLSession.shared
    
    private init() {}
    
    func createOrder(items: [CartItem], shippingAddress: Address, billingAddress: Address, paymentMethod: PaymentMethod) async throws -> Order {
        guard let url = URL(string: "\(baseURL)/orders") else {
            throw NetworkError.invalidURL
        }
        
        let orderRequest = CreateOrderRequest(
            items: items,
            shippingAddress: shippingAddress,
            billingAddress: billingAddress,
            paymentMethod: paymentMethod
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(orderRequest)
        } catch {
            throw NetworkError.encodingError
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }
        
        do {
            let order = try JSONDecoder().decode(Order.self, from: data)
            return order
        } catch {
            throw NetworkError.decodingError
        }
    }
    
    func fetchOrders() async throws -> [Order] {
        guard let url = URL(string: "\(baseURL)/orders") else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }
        
        do {
            let orders = try JSONDecoder().decode([Order].self, from: data)
            return orders
        } catch {
            throw NetworkError.decodingError
        }
    }
    
    func updateOrderStatus(orderId: String, status: OrderStatus) async throws -> Order {
        guard let url = URL(string: "\(baseURL)/orders/\(orderId)/status") else {
            throw NetworkError.invalidURL
        }
        
        let statusUpdate = ["status": status.rawValue]
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: statusUpdate)
        } catch {
            throw NetworkError.encodingError
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }
        
        do {
            let order = try JSONDecoder().decode(Order.self, from: data)
            return order
        } catch {
            throw NetworkError.decodingError
        }
    }
}


struct CreateOrderRequest: Codable {
    let items: [CartItem]
    let shippingAddress: Address
    let billingAddress: Address
    let paymentMethod: PaymentMethod
    
    enum CodingKeys: String, CodingKey {
        case items
        case shippingAddress = "shipping_address"
        case billingAddress = "billing_address"
        case paymentMethod = "payment_method"
    }
}


enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    case encodingError
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Failed to decode response data"
        case .encodingError:
            return "Failed to encode request data"
        case .networkUnavailable:
            return "Network is unavailable"
        }
    }
}


struct ProductFilters {
    var category: ProductCategory?
    var minPrice: Double?
    var maxPrice: Double?
    var minRating: Double?
    var inStockOnly: Bool = false
    var sortBy: SortOption = .name
    var sortOrder: SortOrder = .ascending
    
    enum SortOption: String, CaseIterable {
        case name = "name"
        case price = "price"
        case rating = "rating"
        case newest = "newest"
        case popularity = "popularity"
        
        var displayName: String {
            switch self {
            case .name:
                return "Name"
            case .price:
                return "Price"
            case .rating:
                return "Rating"
            case .newest:
                return "Newest"
            case .popularity:
                return "Popularity"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case ascending = "asc"
        case descending = "desc"
        
        var displayName: String {
            switch self {
            case .ascending:
                return "Low to High"
            case .descending:
                return "High to Low"
            }
        }
    }
}


class WishlistManager: ObservableObject {
    static let shared = WishlistManager()
    
    @Published var wishlistItems: [Product] = []
    
    private init() {
        loadWishlistFromStorage()
    }
    
    func addToWishlist(_ product: Product) {
        if !wishlistItems.contains(where: { $0.id == product.id }) {
            wishlistItems.append(product)
            saveWishlistToStorage()
        }
    }
    
    func removeFromWishlist(_ product: Product) {
        wishlistItems.removeAll { $0.id == product.id }
        saveWishlistToStorage()
    }
    
    func isInWishlist(_ product: Product) -> Bool {
        return wishlistItems.contains { $0.id == product.id }
    }
    
    func clearWishlist() {
        wishlistItems.removeAll()
        saveWishlistToStorage()
    }
    
    private func saveWishlistToStorage() {
        do {
            let data = try JSONEncoder().encode(wishlistItems)
            UserDefaults.standard.set(data, forKey: "wishlist")
        } catch {
            print("Failed to save wishlist: \(error)")
        }
    }
    
    private func loadWishlistFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: "wishlist") else { return }
        
        do {
            wishlistItems = try JSONDecoder().decode([Product].self, from: data)
        } catch {
            print("Failed to load wishlist: \(error)")
            wishlistItems = []
        }
    }
}


class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private let cache = NSCache<NSString, UIImage>()
    private let session = URLSession.shared
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 
    }
    
    func loadImage(from urlString: String) async -> UIImage? {
        let cacheKey = NSString(string: urlString)
        
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            
            cache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            print("Failed to load image: \(error)")
            return nil
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}
