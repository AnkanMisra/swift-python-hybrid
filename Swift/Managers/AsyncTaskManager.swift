import Foundation
import Combine

actor AsyncTaskManager {
    static let shared = AsyncTaskManager()
    
    private var activeTasks: [UUID: Task<Any, Error>] = [:]
    private var taskResults: [UUID: TaskResult] = [:]
    private var taskQueue: [QueuedTask] = []
    private var maxConcurrentTasks: Int
    private var isProcessingQueue = false
    
    private init(maxConcurrentTasks: Int = 10) {
        self.maxConcurrentTasks = maxConcurrentTasks
    }
    
    func executeTask<T>(
        id: UUID = UUID(),
        priority: TaskPriority = .medium,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        if activeTasks.count >= maxConcurrentTasks {
            return try await queueTask(id: id, priority: priority, operation: operation)
        }
        
        return try await performTask(id: id, operation: operation)
    }
    
    private func performTask<T>(
        id: UUID,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let task = Task {
            try await operation()
        }
        
        activeTasks[id] = task
        
        do {
            let result = try await task.value
            taskResults[id] = .success(result)
            activeTasks.removeValue(forKey: id)
            await processNextQueuedTask()
            return result
        } catch {
            taskResults[id] = .failure(error)
            activeTasks.removeValue(forKey: id)
            await processNextQueuedTask()
            throw error
        }
    }
    
    private func queueTask<T>(
        id: UUID,
        priority: TaskPriority,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let queuedTask = QueuedTask(
                id: id,
                priority: priority,
                operation: {
                    do {
                        let result = try await operation()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            )
            
            insertTaskInQueue(queuedTask)
        }
    }
    
    private func insertTaskInQueue(_ task: QueuedTask) {
        let insertIndex = taskQueue.firstIndex { $0.priority.rawValue < task.priority.rawValue } ?? taskQueue.count
        taskQueue.insert(task, at: insertIndex)
    }
    
    private func processNextQueuedTask() async {
        guard !isProcessingQueue, !taskQueue.isEmpty, activeTasks.count < maxConcurrentTasks else { return }
        
        isProcessingQueue = true
        let nextTask = taskQueue.removeFirst()
        isProcessingQueue = false
        
        await nextTask.operation()
    }
    
    func cancelTask(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        taskQueue.removeAll { $0.id == id }
    }
    
    func cancelAllTasks() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        taskQueue.removeAll()
    }
    
    func getTaskStatus(id: UUID) -> TaskStatus {
        if activeTasks[id] != nil {
            return .running
        } else if let result = taskResults[id] {
            switch result {
            case .success:
                return .completed
            case .failure:
                return .failed
            }
        } else if taskQueue.contains(where: { $0.id == id }) {
            return .queued
        }
        return .notFound
    }
    
    func getActiveTaskCount() -> Int {
        activeTasks.count
    }
    
    func getQueuedTaskCount() -> Int {
        taskQueue.count
    }
    
    func updateMaxConcurrentTasks(_ count: Int) {
        maxConcurrentTasks = max(1, count)
    }
    
    func executeTaskGroup<T>(
        tasks: [(UUID, () async throws -> T)],
        failurePolicy: GroupFailurePolicy = .continueOnFailure
    ) async -> [TaskGroupResult<T>] {
        await withTaskGroup(of: TaskGroupResult<T>.self) { group in
            for (id, operation) in tasks {
                group.addTask {
                    do {
                        let result = try await self.executeTask(id: id, operation: operation)
                        return .success(id: id, result: result)
                    } catch {
                        return .failure(id: id, error: error)
                    }
                }
            }
            
            var results: [TaskGroupResult<T>] = []
            for await result in group {
                results.append(result)
                
                if case .failure = result, failurePolicy == .failFast {
                    group.cancelAll()
                    break
                }
            }
            
            return results
        }
    }
    
    func executeWithTimeout<T>(
        timeout: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TaskError.timeout
            }
            
            guard let result = try await group.next() else {
                throw TaskError.unknown
            }
            
            group.cancelAll()
            return result
        }
    }
    
    func executeWithRetry<T>(
        maxRetries: Int = 3,
        delay: TimeInterval = 1.0,
        backoffMultiplier: Double = 2.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var currentDelay = delay
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                    currentDelay *= backoffMultiplier
                }
            }
        }
        
        throw lastError ?? TaskError.unknown
    }
    
    func batchExecute<T, R>(
        items: [T],
        batchSize: Int = 10,
        operation: @escaping (T) async throws -> R
    ) async -> [BatchResult<R>] {
        var results: [BatchResult<R>] = []
        
        for batch in items.chunked(into: batchSize) {
            let batchResults = await executeTaskGroup(
                tasks: batch.enumerated().map { (UUID(), { try await operation($0.element) }) }
            )
            
            results.append(contentsOf: batchResults.map { groupResult in
                switch groupResult {
                case .success(_, let result):
                    return .success(result)
                case .failure(_, let error):
                    return .failure(error)
                }
            })
        }
        
        return results
    }
}

struct QueuedTask {
    let id: UUID
    let priority: TaskPriority
    let operation: () async -> Void
}

enum TaskResult {
    case success(Any)
    case failure(Error)
}

enum TaskStatus {
    case running
    case queued
    case completed
    case failed
    case notFound
}

enum TaskGroupResult<T> {
    case success(id: UUID, result: T)
    case failure(id: UUID, error: Error)
}

enum BatchResult<T> {
    case success(T)
    case failure(Error)
}

enum GroupFailurePolicy {
    case continueOnFailure
    case failFast
}

enum TaskError: Error, LocalizedError {
    case timeout
    case cancelled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Task timed out"
        case .cancelled:
            return "Task was cancelled"
        case .unknown:
            return "Unknown task error"
        }
    }
}

extension TaskPriority {
    var rawValue: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        case .userInitiated:
            return 4
        @unknown default:
            return 2
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

class AsyncTaskManagerObservable: ObservableObject {
    @Published var activeTaskCount: Int = 0
    @Published var queuedTaskCount: Int = 0
    @Published var taskStatuses: [UUID: TaskStatus] = [:]
    
    private let taskManager = AsyncTaskManager.shared
    private var updateTimer: Timer?
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task {
                await self.updateCounts()
            }
        }
    }
    
    private func updateCounts() async {
        let activeCount = await taskManager.getActiveTaskCount()
        let queuedCount = await taskManager.getQueuedTaskCount()
        
        DispatchQueue.main.async {
            self.activeTaskCount = activeCount
            self.queuedTaskCount = queuedCount
        }
    }
    
    func executeTask<T>(
        id: UUID = UUID(),
        priority: TaskPriority = .medium,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await taskManager.executeTask(id: id, priority: priority, operation: operation)
    }
    
    func cancelTask(id: UUID) async {
        await taskManager.cancelTask(id: id)
    }
    
    func cancelAllTasks() async {
        await taskManager.cancelAllTasks()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}