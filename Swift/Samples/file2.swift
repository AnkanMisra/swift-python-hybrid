import Foundation
import UIKit
import Combine

class TaskManager: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var completedTasks: [Task] = []
    @Published var isLoading: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadSampleTasks()
    }
    
    func addTask(title: String, description: String = "", priority: Task.Priority = .medium) {
        let newTask = Task(title: title, description: description, priority: priority)
        tasks.append(newTask)
        saveTasks()
    }
    
    func completeTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        var completedTask = tasks.remove(at: index)
        completedTask.isCompleted = true
        completedTask.completedAt = Date()
        
        completedTasks.append(completedTask)
        saveTasks()
    }
    
    func deleteTask(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
        completedTasks.removeAll { $0.id == task.id }
        saveTasks()
    }
    
    func updateTask(_ task: Task, title: String, description: String, priority: Task.Priority) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        tasks[index].title = title
        tasks[index].description = description
        tasks[index].priority = priority
        tasks[index].updatedAt = Date()
        
        saveTasks()
    }
    
    func filterTasks(by priority: Task.Priority) -> [Task] {
        return tasks.filter { $0.priority == priority }
    }
    
    func searchTasks(query: String) -> [Task] {
        guard !query.isEmpty else { return tasks }
        
        return tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query) ||
            task.description.localizedCaseInsensitiveContains(query)
        }
    }
    
    private func saveTasks() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let tasksData = try encoder.encode(tasks)
            let completedTasksData = try encoder.encode(completedTasks)
            
            UserDefaults.standard.set(tasksData, forKey: "saved_tasks")
            UserDefaults.standard.set(completedTasksData, forKey: "completed_tasks")
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }
    
    private func loadTasks() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let tasksData = UserDefaults.standard.data(forKey: "saved_tasks"),
           let loadedTasks = try? decoder.decode([Task].self, from: tasksData) {
            self.tasks = loadedTasks
        }
        
        if let completedTasksData = UserDefaults.standard.data(forKey: "completed_tasks"),
           let loadedCompletedTasks = try? decoder.decode([Task].self, from: completedTasksData) {
            self.completedTasks = loadedCompletedTasks
        }
    }
    
    private func loadSampleTasks() {
        let sampleTasks = [
            Task(title: "Complete iOS Project", description: "Finish the weather app UI", priority: .high),
            Task(title: "Review Code", description: "Review pull requests from team", priority: .medium),
            Task(title: "Update Documentation", description: "Update API documentation", priority: .low),
            Task(title: "Plan Sprint", description: "Prepare for next sprint planning", priority: .high)
        ]
        
        self.tasks = sampleTasks
    }
}

struct Task: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var priority: Priority
    var isCompleted: Bool
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    
    enum Priority: String, CaseIterable, Codable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case urgent = "Urgent"
        
        var color: UIColor {
            switch self {
            case .low: return .systemGreen
            case .medium: return .systemOrange
            case .high: return .systemRed
            case .urgent: return .systemPurple
            }
        }
        
        var sortOrder: Int {
            switch self {
            case .urgent: return 0
            case .high: return 1
            case .medium: return 2
            case .low: return 3
            }
        }
    }
    
    init(title: String, description: String = "", priority: Priority = .medium) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.priority = priority
        self.isCompleted = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.completedAt = nil
    }
    
    static func == (lhs: Task, rhs: Task) -> Bool {
        return lhs.id == rhs.id
    }
}

class TaskAnalytics {
    static func generateReport(for tasks: [Task], completedTasks: [Task]) -> TaskReport {
        let totalTasks = tasks.count + completedTasks.count
        let completionRate = totalTasks > 0 ? Double(completedTasks.count) / Double(totalTasks) : 0.0
        
        let priorityDistribution = Dictionary(grouping: tasks + completedTasks) { $0.priority }
            .mapValues { $0.count }
        
        let averageCompletionTime = calculateAverageCompletionTime(completedTasks)
        
        return TaskReport(
            totalTasks: totalTasks,
            activeTasks: tasks.count,
            completedTasks: completedTasks.count,
            completionRate: completionRate,
            priorityDistribution: priorityDistribution,
            averageCompletionTime: averageCompletionTime
        )
    }
    
    private static func calculateAverageCompletionTime(_ completedTasks: [Task]) -> TimeInterval {
        let completionTimes = completedTasks.compactMap { task -> TimeInterval? in
            guard let completedAt = task.completedAt else { return nil }
            return completedAt.timeIntervalSince(task.createdAt)
        }
        
        guard !completionTimes.isEmpty else { return 0 }
        return completionTimes.reduce(0, +) / Double(completionTimes.count)
    }
}

struct TaskReport {
    let totalTasks: Int
    let activeTasks: Int
    let completedTasks: Int
    let completionRate: Double
    let priorityDistribution: [Task.Priority: Int]
    let averageCompletionTime: TimeInterval
    
    var formattedCompletionRate: String {
        return String(format: "%.1f%%", completionRate * 100)
    }
    
    var formattedAverageCompletionTime: String {
        let days = Int(averageCompletionTime) / 86400
        let hours = Int(averageCompletionTime) % 86400 / 3600
        return "\(days)d \(hours)h"
    }
}

