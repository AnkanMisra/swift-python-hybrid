import Foundation

struct MathUtils {
    
    
    static func factorial(_ n: Int) -> Int {
        guard n >= 0 else { return 0 }
        return n <= 1 ? 1 : n * factorial(n - 1)
    }
    
    static func fibonacci(_ n: Int) -> Int {
        guard n >= 0 else { return 0 }
        if n <= 1 { return n }
        
        var a = 0, b = 1
        for _ in 2...n {
            let temp = a + b
            a = b
            b = temp
        }
        return b
    }
    
    static func isPrime(_ number: Int) -> Bool {
        guard number > 1 else { return false }
        guard number > 3 else { return true }
        guard number % 2 != 0 && number % 3 != 0 else { return false }
        
        var i = 5
        while i * i <= number {
            if number % i == 0 || number % (i + 2) == 0 {
                return false
            }
            i += 6
        }
        return true
    }
    
    
    static func mean(_ numbers: [Double]) -> Double {
        guard !numbers.isEmpty else { return 0 }
        return numbers.reduce(0, +) / Double(numbers.count)
    }
    
    static func median(_ numbers: [Double]) -> Double {
        let sorted = numbers.sorted()
        let count = sorted.count
        
        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
        } else {
            return sorted[count/2]
        }
    }
    
    static func standardDeviation(_ numbers: [Double]) -> Double {
        let avg = mean(numbers)
        let squaredDifferences = numbers.map { pow($0 - avg, 2) }
        let variance = mean(squaredDifferences)
        return sqrt(variance)
    }
    
    
    static func circleArea(radius: Double) -> Double {
        return Double.pi * pow(radius, 2)
    }
    
    static func triangleArea(base: Double, height: Double) -> Double {
        return 0.5 * base * height
    }
    
    static func distance(from point1: (x: Double, y: Double), to point2: (x: Double, y: Double)) -> Double {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    
    static func gcd(_ a: Int, _ b: Int) -> Int {
        return b == 0 ? a : gcd(b, a % b)
    }
    
    static func lcm(_ a: Int, _ b: Int) -> Int {
        return abs(a * b) / gcd(a, b)
    }
}
