import SwiftUI
import Combine


struct CustomButton: View {
    let title: String
    let action: () -> Void
    let style: ButtonStyle
    let isLoading: Bool
    let isEnabled: Bool
    
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case ghost
        case link
        
        var backgroundColor: Color {
            switch self {
            case .primary:
                return .blue
            case .secondary:
                return .gray
            case .destructive:
                return .red
            case .ghost:
                return .clear
            case .link:
                return .clear
            }
        }
        
        var textColor: Color {
            switch self {
            case .primary, .secondary, .destructive:
                return .white
            case .ghost:
                return .primary
            case .link:
                return .blue
            }
        }
        
        var borderColor: Color {
            switch self {
            case .primary:
                return .blue
            case .secondary:
                return .gray
            case .destructive:
                return .red
            case .ghost:
                return .gray
            case .link:
                return .clear
            }
        }
    }
    
    init(title: String, style: ButtonStyle = .primary, isLoading: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: style.textColor))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(style.textColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(style.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style.borderColor, lineWidth: 1)
            )
            .cornerRadius(8)
            .opacity(isEnabled ? 1.0 : 0.6)
        }
        .disabled(!isEnabled || isLoading)
    }
}

struct CustomTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    let keyboardType: UIKeyboardType
    let autocapitalizationType: UITextAutocapitalizationType
    let isRequired: Bool
    let validationMessage: String?
    
    @State private var isEditing = false
    @State private var showPassword = false
    
    init(title: String, placeholder: String = "", text: Binding<String>, isSecure: Bool = false, keyboardType: UIKeyboardType = .default, autocapitalizationType: UITextAutocapitalizationType = .sentences, isRequired: Bool = false, validationMessage: String? = nil) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.autocapitalizationType = autocapitalizationType
        self.isRequired = isRequired
        self.validationMessage = validationMessage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if isRequired {
                    Text("*")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            
            ZStack(alignment: .trailing) {
                Group {
                    if isSecure && !showPassword {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .autocapitalization(autocapitalizationType)
                    }
                }
                .textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
                .onTapGesture {
                    isEditing = true
                }
                
                if isSecure {
                    Button(action: {
                        showPassword.toggle()
                    }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .padding(.trailing, 12)
                }
            }
            
            if let validationMessage = validationMessage {
                Text(validationMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.leading, 4)
            }
        }
    }
    
    private var borderColor: Color {
        if let validationMessage = validationMessage {
            return .red
        }
        return isEditing ? .blue : .gray.opacity(0.3)
    }
}

struct CustomCard: View {
    let content: AnyView
    let padding: EdgeInsets
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let backgroundColor: Color
    
    init<Content: View>(padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), cornerRadius: CGFloat = 12, shadowRadius: CGFloat = 2, backgroundColor: Color = .white, @ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.backgroundColor = backgroundColor
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
            .shadow(color: .gray.opacity(0.2), radius: shadowRadius, x: 0, y: 2)
    }
}

struct LoadingView: View {
    let message: String
    let size: CGFloat
    
    init(message: String = "Loading...", size: CGFloat = 50) {
        self.message = message
        self.size = size
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(size / 50)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let imageName: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(title: String, subtitle: String, imageName: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.imageName = imageName
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: imageName)
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle = actionTitle, let action = action {
                CustomButton(title: actionTitle, style: .primary, action: action)
                    .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

struct ErrorView: View {
    let error: Error
    let retryAction: (() -> Void)?
    
    init(error: Error, retryAction: (() -> Void)? = nil) {
        self.error = error
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(error.localizedDescription)
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            if let retryAction = retryAction {
                CustomButton(title: "Try Again", style: .primary, action: retryAction)
                    .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}


class BaseViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var alertMessage: String?
    
    protected var cancellables = Set<AnyCancellable>()
    
    func showAlert(message: String) {
        alertMessage = message
    }
    
    func clearAlert() {
        alertMessage = nil
    }
    
    func handleError(_ error: Error) {
        self.error = error
        Logger.shared.error("Error occurred: \(error.localizedDescription)")
    }
    
    func clearError() {
        error = nil
    }
    
    deinit {
        cancellables.removeAll()
    }
}

class UserListViewModel: BaseViewModel {
    @Published var users: [User] = []
    @Published var filteredUsers: [User] = []
    @Published var searchText = ""
    @Published var selectedUser: User?
    
    private let userRepository = UserRepository()
    
    override init() {
        super.init()
        setupSearchObserver()
        loadUsers()
    }
    
    private func setupSearchObserver() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                self?.filterUsers(searchText: searchText)
            }
            .store(in: &cancellables)
    }
    
    private func filterUsers(searchText: String) {
        if searchText.isEmpty {
            filteredUsers = users
        } else {
            filteredUsers = users.filter { user in
                user.name.localizedCaseInsensitiveContains(searchText) ||
                user.email.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    func loadUsers() {
        isLoading = true
        clearError()
        
        userRepository.list()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] users in
                    self?.users = users
                    self?.filteredUsers = users
                }
            )
            .store(in: &cancellables)
    }
    
    func deleteUser(_ user: User) {
        userRepository.delete(id: user.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.users.removeAll { $0.id == user.id }
                        self?.filteredUsers.removeAll { $0.id == user.id }
                        self?.showAlert(message: "User deleted successfully")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func selectUser(_ user: User) {
        selectedUser = user
    }
}

class UserDetailViewModel: BaseViewModel {
    @Published var user: User?
    @Published var posts: [Post] = []
    @Published var isEditMode = false
    @Published var editedUser: User?
    
    private let userRepository = UserRepository()
    private let postRepository = PostRepository()
    
    func loadUser(id: UUID) {
        isLoading = true
        clearError()
        
        userRepository.read(id: id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] user in
                    self?.user = user
                    self?.editedUser = user
                    if let user = user {
                        self?.loadUserPosts(authorId: user.id)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadUserPosts(authorId: UUID) {
        postRepository.listByAuthor(authorId: authorId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] posts in
                    self?.posts = posts
                }
            )
            .store(in: &cancellables)
    }
    
    func toggleEditMode() {
        isEditMode.toggle()
        if !isEditMode {
            editedUser = user
        }
    }
    
    func saveChanges() {
        guard let editedUser = editedUser else { return }
        
        let validation = Validator.validateUser(editedUser)
        if !validation.isValid {
            showAlert(message: validation.errors.joined(separator: "\n"))
            return
        }
        
        isLoading = true
        
        userRepository.update(editedUser)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] user in
                    self?.user = user
                    self?.editedUser = user
                    self?.isEditMode = false
                    self?.showAlert(message: "User updated successfully")
                }
            )
            .store(in: &cancellables)
    }
    
    func updateEditedUser(name: String? = nil, email: String? = nil) {
        guard let editedUser = editedUser else { return }
        
        self.editedUser = User(
            id: editedUser.id,
            name: name ?? editedUser.name,
            email: email ?? editedUser.email,
            avatar: editedUser.avatar
        )
    }
}

class PostListViewModel: BaseViewModel {
    @Published var posts: [Post] = []
    @Published var filteredPosts: [Post] = []
    @Published var searchText = ""
    @Published var selectedTag: String?
    @Published var availableTags: [String] = []
    
    private let postRepository = PostRepository()
    
    override init() {
        super.init()
        setupSearchObserver()
        loadPosts()
    }
    
    private func setupSearchObserver() {
        Publishers.CombineLatest($searchText, $selectedTag)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] searchText, selectedTag in
                self?.filterPosts(searchText: searchText, selectedTag: selectedTag)
            }
            .store(in: &cancellables)
    }
    
    private func filterPosts(searchText: String, selectedTag: String?) {
        var filtered = posts
        
        if !searchText.isEmpty {
            filtered = filtered.filter { post in
                post.title.localizedCaseInsensitiveContains(searchText) ||
                post.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let selectedTag = selectedTag {
            filtered = filtered.filter { post in
                post.tags.contains(selectedTag)
            }
        }
        
        filteredPosts = filtered
    }
    
    func loadPosts() {
        isLoading = true
        clearError()
        
        postRepository.list()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] posts in
                    self?.posts = posts
                    self?.filteredPosts = posts
                    self?.updateAvailableTags()
                }
            )
            .store(in: &cancellables)
    }
    
    private func updateAvailableTags() {
        let allTags = posts.flatMap { $0.tags }
        availableTags = Array(Set(allTags)).sorted()
    }
    
    func selectTag(_ tag: String?) {
        selectedTag = tag
    }
    
    func deletePost(_ post: Post) {
        postRepository.delete(id: post.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.posts.removeAll { $0.id == post.id }
                        self?.filteredPosts.removeAll { $0.id == post.id }
                        self?.updateAvailableTags()
                        self?.showAlert(message: "Post deleted successfully")
                    }
                }
            )
            .store(in: &cancellables)
    }
}


extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}


struct AlertKey: EnvironmentKey {
    static let defaultValue: Binding<String?> = .constant(nil)
}

extension EnvironmentValues {
    var alertMessage: Binding<String?> {
        get { self[AlertKey.self] }
        set { self[AlertKey.self] = newValue }
    }
}


struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}


struct CardModifier: ViewModifier {
    let backgroundColor: Color
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
            .shadow(color: .gray.opacity(0.2), radius: shadowRadius, x: 0, y: 2)
    }
}

extension View {
    func cardStyle(backgroundColor: Color = .white, cornerRadius: CGFloat = 12, shadowRadius: CGFloat = 2) -> some View {
        modifier(CardModifier(backgroundColor: backgroundColor, cornerRadius: cornerRadius, shadowRadius: shadowRadius))
    }
}

struct NavigationBarModifier: ViewModifier {
    let title: String
    let backgroundColor: Color
    let foregroundColor: Color
    
    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }
}

extension View {
    func customNavigationBar(title: String, backgroundColor: Color = .blue, foregroundColor: Color = .white) -> some View {
        modifier(NavigationBarModifier(title: title, backgroundColor: backgroundColor, foregroundColor: foregroundColor))
    }
}
