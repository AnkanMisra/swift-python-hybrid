import Foundation


struct Stack<T> {
    private var elements: [T] = []
    
    var isEmpty: Bool {
        return elements.isEmpty
    }
    
    var count: Int {
        return elements.count
    }
    
    var top: T? {
        return elements.last
    }
    
    mutating func push(_ element: T) {
        elements.append(element)
    }
    
    @discardableResult
    mutating func pop() -> T? {
        return elements.popLast()
    }
    
    func peek() -> T? {
        return elements.last
    }
}


struct Queue<T> {
    private var elements: [T] = []
    
    var isEmpty: Bool {
        return elements.isEmpty
    }
    
    var count: Int {
        return elements.count
    }
    
    var front: T? {
        return elements.first
    }
    
    mutating func enqueue(_ element: T) {
        elements.append(element)
    }
    
    @discardableResult
    mutating func dequeue() -> T? {
        return isEmpty ? nil : elements.removeFirst()
    }
    
    func peek() -> T? {
        return elements.first
    }
}


class TreeNode<T: Comparable> {
    var value: T
    var left: TreeNode?
    var right: TreeNode?
    
    init(_ value: T) {
        self.value = value
    }
    
    func insert(_ newValue: T) {
        if newValue < value {
            if let left = left {
                left.insert(newValue)
            } else {
                left = TreeNode(newValue)
            }
        } else {
            if let right = right {
                right.insert(newValue)
            } else {
                right = TreeNode(newValue)
            }
        }
    }
    
    func contains(_ searchValue: T) -> Bool {
        if searchValue == value {
            return true
        } else if searchValue < value {
            return left?.contains(searchValue) ?? false
        } else {
            return right?.contains(searchValue) ?? false
        }
    }
    
    func inOrderTraversal() -> [T] {
        var result: [T] = []
        left?.inOrderTraversal().forEach { result.append($0) }
        result.append(value)
        right?.inOrderTraversal().forEach { result.append($0) }
        return result
    }
}


extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
    
    func removeDuplicates<T: Hashable>() -> [Element] where Element == T {
        var seen = Set<T>()
        return filter { seen.insert($0).inserted }
    }
    
    func binarySearch<T: Comparable>(_ target: T) -> Int? where Element == T {
        var left = 0
        var right = count - 1
        
        while left <= right {
            let mid = (left + right) / 2
            if self[mid] == target {
                return mid
            } else if self[mid] < target {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        return nil
    }
}


extension String {
    func isPalindrome() -> Bool {
        let cleaned = self.lowercased().filter { $0.isLetter }
        return cleaned == String(cleaned.reversed())
    }
    
    func wordCount() -> Int {
        return components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    func characterFrequency() -> [Character: Int] {
        var frequency: [Character: Int] = [:]
        for char in self {
            frequency[char, default: 0] += 1
        }
        return frequency
    }
}
