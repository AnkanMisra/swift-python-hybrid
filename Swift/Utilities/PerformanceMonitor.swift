import Foundation
import UIKit
import os.log
import MetricKit


enum PerformanceMetricType: String, CaseIterable {
    case cpuUsage = "cpu_usage"
    case memoryUsage = "memory_usage"
    case diskUsage = "disk_usage"
    case networkLatency = "network_latency"
    case appLaunchTime = "app_launch_time"
    case screenRenderTime = "screen_render_time"
    case apiResponseTime = "api_response_time"
    case databaseQueryTime = "database_query_time"
    case imageLoadTime = "image_load_time"
    case batteryUsage = "battery_usage"
}


struct PerformanceMetric {
    let type: PerformanceMetricType
    let value: Double
    let unit: String
    let timestamp: Date
    let metadata: [String: Any]
    
    init(type: PerformanceMetricType, value: Double, unit: String, metadata: [String: Any] = [:]) {
        self.type = type
        self.value = value
        self.unit = unit
        self.timestamp = Date()
        self.metadata = metadata
    }
}


struct PerformanceThreshold {
    let metricType: PerformanceMetricType
    let warningLevel: Double
    let criticalLevel: Double
    let unit: String
    
    func checkLevel(for value: Double) -> PerformanceLevel {
        if value >= criticalLevel {
            return .critical
        } else if value >= warningLevel {
            return .warning
        } else {
            return .normal
        }
    }
}


enum PerformanceLevel: String {
    case normal = "normal"
    case warning = "warning"
    case critical = "critical"
}


protocol PerformanceAlertDelegate: AnyObject {
    func performanceAlert(metric: PerformanceMetric, level: PerformanceLevel)
    func performanceReport(metrics: [PerformanceMetric])
}


class SystemMonitor {
    private let queue = DispatchQueue(label: "system.monitor", qos: .utility)
    
    func getCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var cpuMsgCount: mach_msg_type_number_t = 0
        var ncpu: natural_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &cpuInfo, &cpuMsgCount)
        
        guard result == KERN_SUCCESS else { return 0.0 }
        
        let cpuLoadInfo = cpuInfo.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(ncpu)) { $0 }
        
        var totalUser: UInt32 = 0
        var totalSystem: UInt32 = 0
        var totalIdle: UInt32 = 0
        
        for i in 0..<Int(ncpu) {
            totalUser += cpuLoadInfo[i].cpu_ticks.0
            totalSystem += cpuLoadInfo[i].cpu_ticks.1
            totalIdle += cpuLoadInfo[i].cpu_ticks.2
        }
        
        let totalTicks = totalUser + totalSystem + totalIdle
        let usage = Double(totalUser + totalSystem) / Double(totalTicks) * 100.0
        
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(cpuMsgCount))
        
        return usage
    }
    
    func getMemoryUsage() -> (used: Double, total: Double, percentage: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return (0, 0, 0)
        }
        
        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let usedMemory = Double(info.resident_size)
        let percentage = (usedMemory / totalMemory) * 100.0
        
        return (usedMemory, totalMemory, percentage)
    }
    
    func getDiskUsage() -> (used: Double, total: Double, percentage: Double) {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            
            guard let totalCapacity = values.volumeTotalCapacity,
                  let availableCapacity = values.volumeAvailableCapacity else {
                return (0, 0, 0)
            }
            
            let usedCapacity = totalCapacity - availableCapacity
            let percentage = (Double(usedCapacity) / Double(totalCapacity)) * 100.0
            
            return (Double(usedCapacity), Double(totalCapacity), percentage)
        } catch {
            return (0, 0, 0)
        }
    }
    
    func getBatteryLevel() -> Double {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Double(UIDevice.current.batteryLevel * 100)
    }
    
    func getBatteryState() -> UIDevice.BatteryState {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryState
    }
}


class NetworkMonitor {
    private var startTime: CFAbsoluteTime = 0
    
    func measureNetworkLatency(url: URL, completion: @escaping (Double?) -> Void) {
        startTime = CFAbsoluteTimeGetCurrent()
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            let latency = (endTime - self.startTime) * 1000 
            
            if error == nil && response != nil {
                completion(latency)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    func measureDownloadSpeed(url: URL, completion: @escaping (Double?) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
            
            guard error == nil, let data = data, duration > 0 else {
                completion(nil)
                return
            }
            
            let bytesPerSecond = Double(data.count) / duration
            let megabitsPerSecond = (bytesPerSecond * 8) / 1_000_000
            
            completion(megabitsPerSecond)
        }.resume()
    }
}


class PerformanceTimer {
    private var startTime: CFAbsoluteTime = 0
    private var isRunning: Bool = false
    private let name: String
    
    init(name: String) {
        self.name = name
    }
    
    func start() {
        guard !isRunning else { return }
        startTime = CFAbsoluteTimeGetCurrent()
        isRunning = true
    }
    
    func stop() -> Double? {
        guard isRunning else { return nil }
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000 
        isRunning = false
        return duration
    }
    
    func measure<T>(_ block: () throws -> T) rethrows -> (result: T, duration: Double) {
        start()
        let result = try block()
        let duration = stop() ?? 0
        return (result, duration)
    }
    
    func measureAsync<T>(_ block: @escaping () async throws -> T) async rethrows -> (result: T, duration: Double) {
        start()
        let result = try await block()
        let duration = stop() ?? 0
        return (result, duration)
    }
}


class MemoryProfiler {
    private var allocations: [String: Int] = [:]
    private var deallocations: [String: Int] = [:]
    private var peakMemoryUsage: Double = 0
    private let queue = DispatchQueue(label: "memory.profiler", qos: .utility)
    
    func trackAllocation(object: String, size: Int) {
        queue.async {
            self.allocations[object, default: 0] += size
            self.updatePeakMemoryUsage()
        }
    }
    
    func trackDeallocation(object: String, size: Int) {
        queue.async {
            self.deallocations[object, default: 0] += size
        }
    }
    
    func getCurrentMemoryUsage() -> Double {
        let totalAllocated = allocations.values.reduce(0, +)
        let totalDeallocated = deallocations.values.reduce(0, +)
        return Double(totalAllocated - totalDeallocated)
    }
    
    func getPeakMemoryUsage() -> Double {
        return peakMemoryUsage
    }
    
    private func updatePeakMemoryUsage() {
        let current = getCurrentMemoryUsage()
        if current > peakMemoryUsage {
            peakMemoryUsage = current
        }
    }
    
    func reset() {
        queue.async {
            self.allocations.removeAll()
            self.deallocations.removeAll()
            self.peakMemoryUsage = 0
        }
    }
    
    func generateReport() -> [String: Any] {
        return [
            "allocations": allocations,
            "deallocations": deallocations,
            "current_usage": getCurrentMemoryUsage(),
            "peak_usage": peakMemoryUsage
        ]
    }
}


class CPUProfiler {
    private var samples: [Double] = []
    private var isActive: Bool = false
    private var timer: Timer?
    private let sampleInterval: TimeInterval = 1.0
    private let systemMonitor = SystemMonitor()
    
    func startProfiling() {
        guard !isActive else { return }
        isActive = true
        samples.removeAll()
        
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { _ in
            let cpuUsage = self.systemMonitor.getCPUUsage()
            self.samples.append(cpuUsage)
        }
    }
    
    func stopProfiling() -> [Double] {
        guard isActive else { return [] }
        isActive = false
        timer?.invalidate()
        timer = nil
        return samples
    }
    
    func getAverageCPUUsage() -> Double {
        guard !samples.isEmpty else { return 0.0 }
        return samples.reduce(0, +) / Double(samples.count)
    }
    
    func getPeakCPUUsage() -> Double {
        return samples.max() ?? 0.0
    }
    
    func generateReport() -> [String: Any] {
        return [
            "samples": samples,
            "average_usage": getAverageCPUUsage(),
            "peak_usage": getPeakCPUUsage(),
            "sample_count": samples.count
        ]
    }
}


class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    weak var delegate: PerformanceAlertDelegate?
    
    private let systemMonitor = SystemMonitor()
    private let networkMonitor = NetworkMonitor()
    private let memoryProfiler = MemoryProfiler()
    private let cpuProfiler = CPUProfiler()
    
    private var metrics: [PerformanceMetric] = []
    private var thresholds: [PerformanceMetricType: PerformanceThreshold] = [:]
    private var isMonitoring: Bool = false
    private var monitoringTimer: Timer?
    private let monitoringInterval: TimeInterval = 30.0
    
    private let queue = DispatchQueue(label: "performance.monitor", qos: .utility)
    private let logger = OSLog(subsystem: "com.app.performance", category: "monitor")
    
    private init() {
        setupDefaultThresholds()
    }
    
    private func setupDefaultThresholds() {
        thresholds[.cpuUsage] = PerformanceThreshold(metricType: .cpuUsage, warningLevel: 70.0, criticalLevel: 90.0, unit: "%")
        thresholds[.memoryUsage] = PerformanceThreshold(metricType: .memoryUsage, warningLevel: 80.0, criticalLevel: 95.0, unit: "%")
        thresholds[.diskUsage] = PerformanceThreshold(metricType: .diskUsage, warningLevel: 85.0, criticalLevel: 95.0, unit: "%")
        thresholds[.networkLatency] = PerformanceThreshold(metricType: .networkLatency, warningLevel: 500.0, criticalLevel: 1000.0, unit: "ms")
        thresholds[.appLaunchTime] = PerformanceThreshold(metricType: .appLaunchTime, warningLevel: 3000.0, criticalLevel: 5000.0, unit: "ms")
        thresholds[.screenRenderTime] = PerformanceThreshold(metricType: .screenRenderTime, warningLevel: 16.7, criticalLevel: 33.3, unit: "ms")
        thresholds[.apiResponseTime] = PerformanceThreshold(metricType: .apiResponseTime, warningLevel: 2000.0, criticalLevel: 5000.0, unit: "ms")
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        cpuProfiler.startProfiling()
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { _ in
            self.collectSystemMetrics()
        }
        
        os_log("Performance monitoring started", log: logger, type: .info)
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        let cpuSamples = cpuProfiler.stopProfiling()
        if !cpuSamples.isEmpty {
            let avgCPU = cpuSamples.reduce(0, +) / Double(cpuSamples.count)
            recordMetric(type: .cpuUsage, value: avgCPU, unit: "%")
        }
        
        os_log("Performance monitoring stopped", log: logger, type: .info)
    }
    
    private func collectSystemMetrics() {
        queue.async {
            
            let memoryInfo = self.systemMonitor.getMemoryUsage()
            self.recordMetric(type: .memoryUsage, value: memoryInfo.percentage, unit: "%", metadata: [
                "used_bytes": memoryInfo.used,
                "total_bytes": memoryInfo.total
            ])
            
            
            let diskInfo = self.systemMonitor.getDiskUsage()
            self.recordMetric(type: .diskUsage, value: diskInfo.percentage, unit: "%", metadata: [
                "used_bytes": diskInfo.used,
                "total_bytes": diskInfo.total
            ])
            
            
            let batteryLevel = self.systemMonitor.getBatteryLevel()
            self.recordMetric(type: .batteryUsage, value: batteryLevel, unit: "%")
        }
    }
    
    func recordMetric(type: PerformanceMetricType, value: Double, unit: String, metadata: [String: Any] = [:]) {
        let metric = PerformanceMetric(type: type, value: value, unit: unit, metadata: metadata)
        
        queue.async {
            self.metrics.append(metric)
            
            
            if let threshold = self.thresholds[type] {
                let level = threshold.checkLevel(for: value)
                if level != .normal {
                    DispatchQueue.main.async {
                        self.delegate?.performanceAlert(metric: metric, level: level)
                    }
                }
            }
            
            
            if self.metrics.count > 1000 {
                self.metrics.removeFirst(500)
            }
        }
        
        os_log("Recorded metric: %{public}@ = %{public}f %{public}@", log: logger, type: .debug, type.rawValue, value, unit)
    }
    
    func measureAPICall<T>(url: URL, operation: @escaping () async throws -> T) async throws -> T {
        let timer = PerformanceTimer(name: "API Call")
        let (result, duration) = try await timer.measureAsync(operation)
        
        recordMetric(type: .apiResponseTime, value: duration, unit: "ms", metadata: [
            "url": url.absoluteString
        ])
        
        return result
    }
    
    func measureScreenRender(viewController: String, operation: @escaping () -> Void) {
        let timer = PerformanceTimer(name: "Screen Render")
        let (_, duration) = timer.measure(operation)
        
        recordMetric(type: .screenRenderTime, value: duration, unit: "ms", metadata: [
            "view_controller": viewController
        ])
    }
    
    func measureImageLoad(imageURL: URL, operation: @escaping () async -> Void) async {
        let timer = PerformanceTimer(name: "Image Load")
        let (_, duration) = await timer.measureAsync(operation)
        
        recordMetric(type: .imageLoadTime, value: duration, unit: "ms", metadata: [
            "image_url": imageURL.absoluteString
        ])
    }
    
    func measureDatabaseQuery(query: String, operation: @escaping () throws -> Void) throws {
        let timer = PerformanceTimer(name: "Database Query")
        let (_, duration) = try timer.measure(operation)
        
        recordMetric(type: .databaseQueryTime, value: duration, unit: "ms", metadata: [
            "query": query
        ])
    }
    
    func measureAppLaunchTime(startTime: CFAbsoluteTime) {
        let launchTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        recordMetric(type: .appLaunchTime, value: launchTime, unit: "ms")
    }
    
    func measureNetworkLatency(to url: URL) {
        networkMonitor.measureNetworkLatency(url: url) { latency in
            if let latency = latency {
                self.recordMetric(type: .networkLatency, value: latency, unit: "ms", metadata: [
                    "url": url.absoluteString
                ])
            }
        }
    }
    
    func setThreshold(for metricType: PerformanceMetricType, warningLevel: Double, criticalLevel: Double, unit: String) {
        thresholds[metricType] = PerformanceThreshold(
            metricType: metricType,
            warningLevel: warningLevel,
            criticalLevel: criticalLevel,
            unit: unit
        )
    }
    
    func getMetrics(for type: PerformanceMetricType? = nil, since: Date? = nil) -> [PerformanceMetric] {
        return queue.sync {
            var filteredMetrics = metrics
            
            if let type = type {
                filteredMetrics = filteredMetrics.filter { $0.type == type }
            }
            
            if let since = since {
                filteredMetrics = filteredMetrics.filter { $0.timestamp >= since }
            }
            
            return filteredMetrics
        }
    }
    
    func getAverageMetric(for type: PerformanceMetricType, since: Date? = nil) -> Double? {
        let metrics = getMetrics(for: type, since: since)
        guard !metrics.isEmpty else { return nil }
        
        let sum = metrics.map { $0.value }.reduce(0, +)
        return sum / Double(metrics.count)
    }
    
    func getPeakMetric(for type: PerformanceMetricType, since: Date? = nil) -> Double? {
        let metrics = getMetrics(for: type, since: since)
        return metrics.map { $0.value }.max()
    }
    
    func generatePerformanceReport(since: Date? = nil) -> [String: Any] {
        let reportMetrics = getMetrics(since: since)
        
        var report: [String: Any] = [
            "timestamp": Date(),
            "total_metrics": reportMetrics.count,
            "monitoring_active": isMonitoring
        ]
        
        
        var metricsByType: [String: [Double]] = [:]
        for metric in reportMetrics {
            if metricsByType[metric.type.rawValue] == nil {
                metricsByType[metric.type.rawValue] = []
            }
            metricsByType[metric.type.rawValue]?.append(metric.value)
        }
        
        
        var statistics: [String: [String: Double]] = [:]
        for (type, values) in metricsByType {
            guard !values.isEmpty else { continue }
            
            let sum = values.reduce(0, +)
            let average = sum / Double(values.count)
            let min = values.min() ?? 0
            let max = values.max() ?? 0
            
            statistics[type] = [
                "average": average,
                "min": min,
                "max": max,
                "count": Double(values.count)
            ]
        }
        
        report["statistics"] = statistics
        report["memory_profiler"] = memoryProfiler.generateReport()
        report["cpu_profiler"] = cpuProfiler.generateReport()
        
        return report
    }
    
    func exportMetrics(to url: URL) throws {
        let report = generatePerformanceReport()
        let data = try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
        try data.write(to: url)
    }
    
    func clearMetrics() {
        queue.async {
            self.metrics.removeAll()
            self.memoryProfiler.reset()
        }
    }
}


extension PerformanceMonitor {
    func trackMemoryAllocation(object: AnyObject, size: Int) {
        let className = String(describing: type(of: object))
        memoryProfiler.trackAllocation(object: className, size: size)
    }
    
    func trackMemoryDeallocation(object: AnyObject, size: Int) {
        let className = String(describing: type(of: object))
        memoryProfiler.trackDeallocation(object: className, size: size)
    }
}


extension UIView {
    func measureLayoutTime() -> Double {
        let timer = PerformanceTimer(name: "Layout")
        let (_, duration) = timer.measure {
            setNeedsLayout()
            layoutIfNeeded()
        }
        return duration
    }
    
    func measureRenderTime() -> Double {
        let timer = PerformanceTimer(name: "Render")
        return timer.measure {
            layer.setNeedsDisplay()
            layer.displayIfNeeded()
        }.duration
    }
}


extension URLSession {
    func performanceDataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?, Double) -> Void) -> URLSessionDataTask {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        return dataTask(with: url) { data, response, error in
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            completionHandler(data, response, error, duration)
        }
    }
}


class PerformanceBenchmark {
    static func runCPUBenchmark(iterations: Int = 1000000) -> Double {
        let timer = PerformanceTimer(name: "CPU Benchmark")
        
        return timer.measure {
            var result = 0.0
            for i in 0..<iterations {
                result += sin(Double(i)) * cos(Double(i))
            }
        }.duration
    }
    
    static func runMemoryBenchmark(arraySize: Int = 1000000) -> Double {
        let timer = PerformanceTimer(name: "Memory Benchmark")
        
        return timer.measure {
            var array = Array<Int>()
            array.reserveCapacity(arraySize)
            
            for i in 0..<arraySize {
                array.append(i)
            }
            
            array.removeAll()
        }.duration
    }
    
    static func runDiskBenchmark() -> Double {
        let timer = PerformanceTimer(name: "Disk Benchmark")
        
        return timer.measure {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let testFile = documentsPath.appendingPathComponent("benchmark_test.txt")
            
            let testData = String(repeating: "Test data ", count: 10000).data(using: .utf8)!
            
            try? testData.write(to: testFile)
            _ = try? Data(contentsOf: testFile)
            try? FileManager.default.removeItem(at: testFile)
        }.duration
    }
}
