import SwiftUI
import Combine


class ProductViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var error: Error?
    @Published var isLoading = false
    private var cancellables = Set<AnyCancellable>()
    private let productService = ProductService()
    
    func loadProducts() {
        isLoading = true
        productService.fetchProducts()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.error = error
                }
            }, receiveValue: { [weak self] products in
                self?.products = products
            })
            .store(in: &cancellables)
    }
}


class ProductService {
    func fetchProducts() -> AnyPublisher<[Product], Error> {
        let url = URL(string: "https://api.example.com/products")!
        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [Product].self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
}


struct Product: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let price: Double
    let imageUrl: URL?

    init(id: UUID = UUID(), name: String, description: String, price: Double, imageUrl: URL? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.price = price
        self.imageUrl = imageUrl
    }
}


struct ProductListView: View {
    @ObservedObject var viewModel = ProductViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.products) { product in
                ProductRow(product: product)
            }
            .navigationBarTitle("Products")
            .onAppear {
                viewModel.loadProducts()
            }
        }
    }
}

struct ProductRow: View {
    let product: Product
    
    var body: some View {
        HStack {
            if let imageUrl = product.imageUrl {
                AsyncImage(url: imageUrl) { image in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 50, height: 50)
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text(product.name)
                    .font(.headline)
                Text(product.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("$\(product.price, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
    }
}


struct PriceBadge: ViewModifier {
    let price: Double
    
    func body(content: Content) -> some View {
        HStack {
            content
            Spacer()
            Text("$\(price, specifier: "%.2f")")
                .padding(6)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }
}

extension View {
    func priceBadge(price: Double) -> some View {
        modifier(PriceBadge(price: price))
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ProductListView()
    }
}


struct AsyncImage<Placeholder: View>: View {
    @State private var phase = AsyncImagePhase.empty
    let url: URL
    let content: (Image) -> Image
    let placeholder: () -> Placeholder
    var body: some View {
        ZStack {
            switch phase {
            case .empty:
                placeholder()
                    .onAppear {
                        loadImageFromURL(url)
                    }
            case .success(let image):
                content(image)
            case .failure:
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            }
        }
    }
    private func loadImageFromURL(_ url: URL) {
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    phase = .success(Image(uiImage: uiImage))
                }
            } else {
                DispatchQueue.main.async {
                    phase = .failure
                }
            }
        }
        task.resume()
    }
}

@frozen enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure
}
