import UIKit
import Foundation
import CoreData
import CoreLocation
import AVFoundation
import Photos


struct UserProfile: Codable {
    let id: String
    let username: String
    let email: String
    let fullName: String
    let bio: String?
    let profileImageURL: String?
    let coverImageURL: String?
    let followerCount: Int
    let followingCount: Int
    let postCount: Int
    let isVerified: Bool
    let isPrivate: Bool
    let location: String?
    let website: String?
    let dateOfBirth: Date?
    let joinedDate: Date
    let lastActiveDate: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case fullName = "full_name"
        case bio
        case profileImageURL = "profile_image_url"
        case coverImageURL = "cover_image_url"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case postCount = "post_count"
        case isVerified = "is_verified"
        case isPrivate = "is_private"
        case location
        case website
        case dateOfBirth = "date_of_birth"
        case joinedDate = "joined_date"
        case lastActiveDate = "last_active_date"
    }
}


struct Post: Codable, Identifiable {
    let id: String
    let authorId: String
    let author: UserProfile
    let content: String
    let mediaItems: [MediaItem]
    let hashtags: [String]
    let mentions: [String]
    let location: LocationData?
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let isLiked: Bool
    let isBookmarked: Bool
    let visibility: PostVisibility
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case author
        case content
        case mediaItems = "media_items"
        case hashtags
        case mentions
        case location
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
        case isLiked = "is_liked"
        case isBookmarked = "is_bookmarked"
        case visibility
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


struct MediaItem: Codable {
    let id: String
    let type: MediaType
    let url: String
    let thumbnailURL: String?
    let width: Int
    let height: Int
    let duration: TimeInterval?
    let size: Int
    let altText: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case url
        case thumbnailURL = "thumbnail_url"
        case width
        case height
        case duration
        case size
        case altText = "alt_text"
    }
}


enum MediaType: String, Codable {
    case image = "image"
    case video = "video"
    case gif = "gif"
    case audio = "audio"
    
    var displayName: String {
        switch self {
        case .image:
            return "Photo"
        case .video:
            return "Video"
        case .gif:
            return "GIF"
        case .audio:
            return "Audio"
        }
    }
    
    var icon: String {
        switch self {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .gif:
            return "livephoto"
        case .audio:
            return "waveform"
        }
    }
}


enum PostVisibility: String, Codable {
    case public = "public"
    case followers = "followers"
    case friends = "friends"
    case private = "private"
    
    var displayName: String {
        switch self {
        case .public:
            return "Public"
        case .followers:
            return "Followers"
        case .friends:
            return "Friends"
        case .private:
            return "Only Me"
        }
    }
    
    var icon: String {
        switch self {
        case .public:
            return "globe"
        case .followers:
            return "person.2"
        case .friends:
            return "heart"
        case .private:
            return "lock"
        }
    }
}


struct LocationData: Codable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let placeId: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case address
        case latitude
        case longitude
        case placeId = "place_id"
    }
}


struct Comment: Codable, Identifiable {
    let id: String
    let postId: String
    let authorId: String
    let author: UserProfile
    let content: String
    let parentCommentId: String?
    let replies: [Comment]?
    let likeCount: Int
    let isLiked: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case authorId = "author_id"
        case author
        case content
        case parentCommentId = "parent_comment_id"
        case replies
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


struct Story: Codable, Identifiable {
    let id: String
    let authorId: String
    let author: UserProfile
    let mediaItem: MediaItem
    let text: String?
    let backgroundColor: String?
    let viewCount: Int
    let isViewed: Bool
    let expiresAt: Date
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case author
        case mediaItem = "media_item"
        case text
        case backgroundColor = "background_color"
        case viewCount = "view_count"
        case isViewed = "is_viewed"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}


struct ChatMessage: Codable, Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let sender: UserProfile
    let content: String
    let messageType: MessageType
    let mediaItem: MediaItem?
    let replyToMessageId: String?
    let isRead: Bool
    let isDelivered: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case sender
        case content
        case messageType = "message_type"
        case mediaItem = "media_item"
        case replyToMessageId = "reply_to_message_id"
        case isRead = "is_read"
        case isDelivered = "is_delivered"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


enum MessageType: String, Codable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case file = "file"
    case location = "location"
    case sticker = "sticker"
    
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .image:
            return "Photo"
        case .video:
            return "Video"
        case .audio:
            return "Voice Message"
        case .file:
            return "File"
        case .location:
            return "Location"
        case .sticker:
            return "Sticker"
        }
    }
}


struct Conversation: Codable, Identifiable {
    let id: String
    let participants: [UserProfile]
    let lastMessage: ChatMessage?
    let unreadCount: Int
    let isGroup: Bool
    let groupName: String?
    let groupImageURL: String?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case participants
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case isGroup = "is_group"
        case groupName = "group_name"
        case groupImageURL = "group_image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


struct NotificationItem: Codable, Identifiable {
    let id: String
    let type: NotificationType
    let title: String
    let message: String
    let actionUserId: String?
    let actionUser: UserProfile?
    let relatedPostId: String?
    let relatedPost: Post?
    let isRead: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case message
        case actionUserId = "action_user_id"
        case actionUser = "action_user"
        case relatedPostId = "related_post_id"
        case relatedPost = "related_post"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}


enum NotificationType: String, Codable {
    case like = "like"
    case comment = "comment"
    case follow = "follow"
    case mention = "mention"
    case share = "share"
    case message = "message"
    case story = "story"
    
    var displayName: String {
        switch self {
        case .like:
            return "Like"
        case .comment:
            return "Comment"
        case .follow:
            return "Follow"
        case .mention:
            return "Mention"
        case .share:
            return "Share"
        case .message:
            return "Message"
        case .story:
            return "Story"
        }
    }
    
    var icon: String {
        switch self {
        case .like:
            return "heart.fill"
        case .comment:
            return "bubble.left"
        case .follow:
            return "person.badge.plus"
        case .mention:
            return "at"
        case .share:
            return "square.and.arrow.up"
        case .message:
            return "message"
        case .story:
            return "circle"
        }
    }
    
    var color: UIColor {
        switch self {
        case .like:
            return .systemRed
        case .comment:
            return .systemBlue
        case .follow:
            return .systemGreen
        case .mention:
            return .systemOrange
        case .share:
            return .systemPurple
        case .message:
            return .systemTeal
        case .story:
            return .systemPink
        }
    }
}


class SocialMediaService {
    static let shared = SocialMediaService()
    
    private let baseURL = "https://api.socialmedia.com"
    private let session = URLSession.shared
    
    private init() {}
    
    
    func fetchUserProfile(userId: String) async throws -> UserProfile {
        guard let url = URL(string: "\(baseURL)/users/\(userId)") else {
            throw SocialMediaError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let user = try JSONDecoder().decode(UserProfile.self, from: data)
            return user
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
        guard let url = URL(string: "\(baseURL)/users/\(profile.id)") else {
            throw SocialMediaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(profile)
        } catch {
            throw SocialMediaError.encodingError
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let updatedProfile = try JSONDecoder().decode(UserProfile.self, from: data)
            return updatedProfile
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    func searchUsers(query: String, page: Int = 1, limit: Int = 20) async throws -> [UserProfile] {
        var urlComponents = URLComponents(string: "\(baseURL)/users/search")!
        
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = urlComponents.url else {
            throw SocialMediaError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let users = try JSONDecoder().decode([UserProfile].self, from: data)
            return users
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    
    func fetchFeed(page: Int = 1, limit: Int = 20) async throws -> [Post] {
        var urlComponents = URLComponents(string: "\(baseURL)/posts/feed")!
        
        urlComponents.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = urlComponents.url else {
            throw SocialMediaError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let posts = try JSONDecoder().decode([Post].self, from: data)
            return posts
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    func createPost(content: String, mediaItems: [MediaItem], visibility: PostVisibility, location: LocationData?) async throws -> Post {
        guard let url = URL(string: "\(baseURL)/posts") else {
            throw SocialMediaError.invalidURL
        }
        
        let createPostRequest = CreatePostRequest(
            content: content,
            mediaItems: mediaItems,
            visibility: visibility,
            location: location
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(createPostRequest)
        } catch {
            throw SocialMediaError.encodingError
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let post = try JSONDecoder().decode(Post.self, from: data)
            return post
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    func likePost(postId: String) async throws {
        guard let url = URL(string: "\(baseURL)/posts/\(postId)/like") else {
            throw SocialMediaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
    }
    
    func unlikePost(postId: String) async throws {
        guard let url = URL(string: "\(baseURL)/posts/\(postId)/like") else {
            throw SocialMediaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
    }
    
    
    func fetchComments(postId: String, page: Int = 1, limit: Int = 20) async throws -> [Comment] {
        var urlComponents = URLComponents(string: "\(baseURL)/posts/\(postId)/comments")!
        
        urlComponents.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = urlComponents.url else {
            throw SocialMediaError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let comments = try JSONDecoder().decode([Comment].self, from: data)
            return comments
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    func createComment(postId: String, content: String, parentCommentId: String?) async throws -> Comment {
        guard let url = URL(string: "\(baseURL)/posts/\(postId)/comments") else {
            throw SocialMediaError.invalidURL
        }
        
        let createCommentRequest = CreateCommentRequest(
            content: content,
            parentCommentId: parentCommentId
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(createCommentRequest)
        } catch {
            throw SocialMediaError.encodingError
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let comment = try JSONDecoder().decode(Comment.self, from: data)
            return comment
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    
    func fetchStories(page: Int = 1, limit: Int = 20) async throws -> [Story] {
        var urlComponents = URLComponents(string: "\(baseURL)/stories")!
        
        urlComponents.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = urlComponents.url else {
            throw SocialMediaError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let stories = try JSONDecoder().decode([Story].self, from: data)
            return stories
        } catch {
            throw SocialMediaError.decodingError
        }
    }
    
    func createStory(mediaItem: MediaItem, text: String?, backgroundColor: String?) async throws -> Story {
        guard let url = URL(string: "\(baseURL)/stories") else {
            throw SocialMediaError.invalidURL
        }
        
        let createStoryRequest = CreateStoryRequest(
            mediaItem: mediaItem,
            text: text,
            backgroundColor: backgroundColor
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(createStoryRequest)
        } catch {
            throw SocialMediaError.encodingError
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SocialMediaError.invalidResponse
        }
        
        do {
            let story = try JSONDecoder().decode(Story.self, from: data)
            return story
        } catch {
            throw SocialMediaError.decodingError
        }
    }
}


struct CreatePostRequest: Codable {
    let content: String
    let mediaItems: [MediaItem]
    let visibility: PostVisibility
    let location: LocationData?
    
    enum CodingKeys: String, CodingKey {
        case content
        case mediaItems = "media_items"
        case visibility
        case location
    }
}

struct CreateCommentRequest: Codable {
    let content: String
    let parentCommentId: String?
    
    enum CodingKeys: String, CodingKey {
        case content
        case parentCommentId = "parent_comment_id"
    }
}

struct CreateStoryRequest: Codable {
    let mediaItem: MediaItem
    let text: String?
    let backgroundColor: String?
    
    enum CodingKeys: String, CodingKey {
        case mediaItem = "media_item"
        case text
        case backgroundColor = "background_color"
    }
}


enum SocialMediaError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    case encodingError
    case networkUnavailable
    case unauthorized
    case forbidden
    case notFound
    case serverError
    
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
        case .unauthorized:
            return "Unauthorized access"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .serverError:
            return "Internal server error"
        }
    }
}


class PostManager: ObservableObject {
    static let shared = PostManager()
    
    @Published var feedPosts: [Post] = []
    @Published var userPosts: [Post] = []
    @Published var bookmarkedPosts: [Post] = []
    @Published var isLoading = false
    @Published var hasMorePosts = true
    
    private let service = SocialMediaService.shared
    private var currentPage = 1
    
    private init() {}
    
    func loadFeed(refresh: Bool = false) async {
        if refresh {
            currentPage = 1
            hasMorePosts = true
        }
        
        guard !isLoading && hasMorePosts else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let posts = try await service.fetchFeed(page: currentPage, limit: 20)
            
            await MainActor.run {
                if refresh {
                    feedPosts = posts
                } else {
                    feedPosts.append(contentsOf: posts)
                }
                
                currentPage += 1
                hasMorePosts = posts.count == 20
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("Failed to load feed: \(error)")
        }
    }
    
    func likePost(_ post: Post) async {
        guard let index = feedPosts.firstIndex(where: { $0.id == post.id }) else { return }
        
        
        await MainActor.run {
            feedPosts[index] = Post(
                id: post.id,
                authorId: post.authorId,
                author: post.author,
                content: post.content,
                mediaItems: post.mediaItems,
                hashtags: post.hashtags,
                mentions: post.mentions,
                location: post.location,
                likeCount: post.isLiked ? post.likeCount - 1 : post.likeCount + 1,
                commentCount: post.commentCount,
                shareCount: post.shareCount,
                isLiked: !post.isLiked,
                isBookmarked: post.isBookmarked,
                visibility: post.visibility,
                createdAt: post.createdAt,
                updatedAt: post.updatedAt
            )
        }
        
        do {
            if post.isLiked {
                try await service.unlikePost(postId: post.id)
            } else {
                try await service.likePost(postId: post.id)
            }
        } catch {
            
            await MainActor.run {
                feedPosts[index] = post
            }
            print("Failed to update like status: \(error)")
        }
    }
    
    func createPost(content: String, mediaItems: [MediaItem], visibility: PostVisibility, location: LocationData?) async {
        do {
            let newPost = try await service.createPost(
                content: content,
                mediaItems: mediaItems,
                visibility: visibility,
                location: location
            )
            
            await MainActor.run {
                feedPosts.insert(newPost, at: 0)
            }
        } catch {
            print("Failed to create post: \(error)")
        }
    }
}


class StoryManager: ObservableObject {
    static let shared = StoryManager()
    
    @Published var stories: [Story] = []
    @Published var isLoading = false
    
    private let service = SocialMediaService.shared
    
    private init() {}
    
    func loadStories() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let stories = try await service.fetchStories()
            
            await MainActor.run {
                self.stories = stories
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("Failed to load stories: \(error)")
        }
    }
    
    func createStory(mediaItem: MediaItem, text: String?, backgroundColor: String?) async {
        do {
            let newStory = try await service.createStory(
                mediaItem: mediaItem,
                text: text,
                backgroundColor: backgroundColor
            )
            
            await MainActor.run {
                stories.insert(newStory, at: 0)
            }
        } catch {
            print("Failed to create story: \(error)")
        }
    }
}


class UserManager: ObservableObject {
    static let shared = UserManager()
    
    @Published var currentUser: UserProfile?
    @Published var followingUsers: [UserProfile] = []
    @Published var followers: [UserProfile] = []
    @Published var searchResults: [UserProfile] = []
    @Published var isLoading = false
    
    private let service = SocialMediaService.shared
    
    private init() {}
    
    func loadCurrentUser() async {
        guard let userId = getCurrentUserId() else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let user = try await service.fetchUserProfile(userId: userId)
            
            await MainActor.run {
                currentUser = user
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("Failed to load current user: \(error)")
        }
    }
    
    func searchUsers(query: String) async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let users = try await service.searchUsers(query: query)
            
            await MainActor.run {
                searchResults = users
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("Failed to search users: \(error)")
        }
    }
    
    private func getCurrentUserId() -> String? {
        return UserDefaults.standard.string(forKey: "current_user_id")
    }
}


class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [NotificationItem] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    
    private init() {
        loadNotifications()
    }
    
    func loadNotifications() {
        
        notifications = generateMockNotifications()
        unreadCount = notifications.filter { !$0.isRead }.count
    }
    
    func markAsRead(_ notification: NotificationItem) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index] = NotificationItem(
                id: notification.id,
                type: notification.type,
                title: notification.title,
                message: notification.message,
                actionUserId: notification.actionUserId,
                actionUser: notification.actionUser,
                relatedPostId: notification.relatedPostId,
                relatedPost: notification.relatedPost,
                isRead: true,
                createdAt: notification.createdAt
            )
            updateUnreadCount()
        }
    }
    
    func markAllAsRead() {
        notifications = notifications.map { notification in
            NotificationItem(
                id: notification.id,
                type: notification.type,
                title: notification.title,
                message: notification.message,
                actionUserId: notification.actionUserId,
                actionUser: notification.actionUser,
                relatedPostId: notification.relatedPostId,
                relatedPost: notification.relatedPost,
                isRead: true,
                createdAt: notification.createdAt
            )
        }
        updateUnreadCount()
    }
    
    private func updateUnreadCount() {
        unreadCount = notifications.filter { !$0.isRead }.count
    }
    
    private func generateMockNotifications() -> [NotificationItem] {
        return [
            NotificationItem(
                id: "1",
                type: .like,
                title: "New Like",
                message: "John liked your post",
                actionUserId: "user_1",
                actionUser: nil,
                relatedPostId: "post_1",
                relatedPost: nil,
                isRead: false,
                createdAt: Date().addingTimeInterval(-3600)
            ),
            NotificationItem(
                id: "2",
                type: .comment,
                title: "New Comment",
                message: "Sarah commented on your post",
                actionUserId: "user_2",
                actionUser: nil,
                relatedPostId: "post_2",
                relatedPost: nil,
                isRead: false,
                createdAt: Date().addingTimeInterval(-7200)
            ),
            NotificationItem(
                id: "3",
                type: .follow,
                title: "New Follower",
                message: "Mike started following you",
                actionUserId: "user_3",
                actionUser: nil,
                relatedPostId: nil,
                relatedPost: nil,
                isRead: true,
                createdAt: Date().addingTimeInterval(-10800)
            )
        ]
    }
}


class MediaUploadManager {
    static let shared = MediaUploadManager()
    
    private let session = URLSession.shared
    
    private init() {}
    
    func uploadImage(_ image: UIImage, compressionQuality: CGFloat = 0.8) async throws -> MediaItem {
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            throw MediaUploadError.invalidImageData
        }
        
        let uploadURL = URL(string: "https://api.socialmedia.com/media/upload")!
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let httpBody = createMultipartBody(imageData: imageData, boundary: boundary)
        request.httpBody = httpBody
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw MediaUploadError.uploadFailed
        }
        
        do {
            let mediaItem = try JSONDecoder().decode(MediaItem.self, from: data)
            return mediaItem
        } catch {
            throw MediaUploadError.decodingError
        }
    }
    
    private func createMultipartBody(imageData: Data, boundary: String) -> Data {
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}


enum MediaUploadError: Error, LocalizedError {
    case invalidImageData
    case uploadFailed
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data"
        case .uploadFailed:
            return "Failed to upload media"
        case .decodingError:
            return "Failed to decode upload response"
        }
    }
}


class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}


class SocialMediaCacheManager {
    static let shared = SocialMediaCacheManager()
    
    private let imageCache = NSCache<NSString, UIImage>()
    private let postCache = NSCache<NSString, NSData>()
    
    private init() {
        imageCache.countLimit = 200
        imageCache.totalCostLimit = 100 * 1024 * 1024 
        
        postCache.countLimit = 100
        postCache.totalCostLimit = 50 * 1024 * 1024 
    }
    
    func cacheImage(_ image: UIImage, forKey key: String) {
        imageCache.setObject(image, forKey: NSString(string: key))
    }
    
    func getCachedImage(forKey key: String) -> UIImage? {
        return imageCache.object(forKey: NSString(string: key))
    }
    
    func cachePosts(_ posts: [Post], forKey key: String) {
        do {
            let data = try JSONEncoder().encode(posts)
            postCache.setObject(data as NSData, forKey: NSString(string: key))
        } catch {
            print("Failed to cache posts: \(error)")
        }
    }
    
    func getCachedPosts(forKey key: String) -> [Post]? {
        guard let data = postCache.object(forKey: NSString(string: key)) as Data? else { return nil }
        
        do {
            return try JSONDecoder().decode([Post].self, from: data)
        } catch {
            print("Failed to decode cached posts: \(error)")
            return nil
        }
    }
    
    func clearCache() {
        imageCache.removeAllObjects()
        postCache.removeAllObjects()
    }
}
