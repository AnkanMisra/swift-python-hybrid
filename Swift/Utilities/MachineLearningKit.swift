import Foundation
import CoreML
import Vision
import CreateML
import Accelerate


enum MLError: Error, LocalizedError {
    case modelNotFound
    case invalidInput
    case predictionFailed
    case trainingFailed
    case dataPreprocessingFailed
    case modelLoadingFailed
    case incompatibleModel
    case insufficientData
    case featureExtractionFailed
    case validationFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Machine learning model not found"
        case .invalidInput:
            return "Invalid input provided to model"
        case .predictionFailed:
            return "Model prediction failed"
        case .trainingFailed:
            return "Model training failed"
        case .dataPreprocessingFailed:
            return "Data preprocessing failed"
        case .modelLoadingFailed:
            return "Failed to load machine learning model"
        case .incompatibleModel:
            return "Model is incompatible with the current version"
        case .insufficientData:
            return "Insufficient data for training"
        case .featureExtractionFailed:
            return "Feature extraction failed"
        case .validationFailed:
            return "Model validation failed"
        }
    }
}


struct MLFeature {
    let name: String
    let value: Double
    let type: FeatureType
    
    enum FeatureType {
        case numerical
        case categorical
        case binary
        case text
        case image
    }
}

struct MLSample {
    let features: [MLFeature]
    let label: String?
    let weight: Double
    
    init(features: [MLFeature], label: String? = nil, weight: Double = 1.0) {
        self.features = features
        self.label = label
        self.weight = weight
    }
}

struct MLDataset {
    let samples: [MLSample]
    let featureNames: [String]
    let labelName: String?
    
    var count: Int { samples.count }
    var isEmpty: Bool { samples.isEmpty }
    
    func split(ratio: Double) -> (training: MLDataset, validation: MLDataset) {
        let shuffled = samples.shuffled()
        let splitIndex = Int(Double(shuffled.count) * ratio)
        
        let trainingSamples = Array(shuffled[0..<splitIndex])
        let validationSamples = Array(shuffled[splitIndex..<shuffled.count])
        
        let trainingDataset = MLDataset(samples: trainingSamples, featureNames: featureNames, labelName: labelName)
        let validationDataset = MLDataset(samples: validationSamples, featureNames: featureNames, labelName: labelName)
        
        return (trainingDataset, validationDataset)
    }
    
    func normalize() -> MLDataset {
        guard !samples.isEmpty else { return self }
        
        var featureStats: [String: (min: Double, max: Double)] = [:]
        
        
        for featureName in featureNames {
            let values = samples.compactMap { sample in
                sample.features.first { $0.name == featureName }?.value
            }
            
            if !values.isEmpty {
                featureStats[featureName] = (min: values.min()!, max: values.max()!)
            }
        }
        
        
        let normalizedSamples = samples.map { sample in
            let normalizedFeatures = sample.features.map { feature in
                guard let stats = featureStats[feature.name],
                      stats.max != stats.min else {
                    return feature
                }
                
                let normalizedValue = (feature.value - stats.min) / (stats.max - stats.min)
                return MLFeature(name: feature.name, value: normalizedValue, type: feature.type)
            }
            
            return MLSample(features: normalizedFeatures, label: sample.label, weight: sample.weight)
        }
        
        return MLDataset(samples: normalizedSamples, featureNames: featureNames, labelName: labelName)
    }
}


struct MLPrediction {
    let label: String
    let confidence: Double
    let probabilities: [String: Double]
    let processingTime: TimeInterval
    
    init(label: String, confidence: Double, probabilities: [String: Double] = [:], processingTime: TimeInterval = 0) {
        self.label = label
        self.confidence = confidence
        self.probabilities = probabilities
        self.processingTime = processingTime
    }
}


protocol MLModel {
    var name: String { get }
    var version: String { get }
    var inputFeatures: [String] { get }
    var outputFeatures: [String] { get }
    
    func predict(features: [MLFeature]) throws -> MLPrediction
    func batchPredict(samples: [MLSample]) throws -> [MLPrediction]
    func save(to url: URL) throws
}


class CoreMLModelWrapper: MLModel {
    let name: String
    let version: String
    let inputFeatures: [String]
    let outputFeatures: [String]
    
    private let model: MLModel
    
    init(modelURL: URL) throws {
        guard let mlModel = try? MLModel(contentsOf: modelURL) else {
            throw MLError.modelLoadingFailed
        }
        
        self.model = mlModel
        self.name = modelURL.lastPathComponent
        self.version = "1.0"
        
        let description = mlModel.modelDescription
        self.inputFeatures = description.inputDescriptionsByName.keys.map { String($0) }
        self.outputFeatures = description.outputDescriptionsByName.keys.map { String($0) }
    }
    
    func predict(features: [MLFeature]) throws -> MLPrediction {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        
        var featureDict: [String: Any] = [:]
        for feature in features {
            featureDict[feature.name] = feature.value
        }
        
        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let prediction = try model.prediction(from: provider)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let processingTime = endTime - startTime
        
        
        let outputFeature = outputFeatures.first ?? "output"
        
        if let labelValue = prediction.featureValue(for: outputFeature) {
            var label = ""
            var confidence = 0.0
            var probabilities: [String: Double] = [:]
            
            switch labelValue.type {
            case .string:
                label = labelValue.stringValue
                confidence = 1.0
            case .int64:
                label = String(labelValue.int64Value)
                confidence = 1.0
            case .double:
                label = String(labelValue.doubleValue)
                confidence = 1.0
            case .dictionary:
                if let probs = labelValue.dictionaryValue as? [String: Double] {
                    probabilities = probs
                    if let maxEntry = probs.max(by: { $0.value < $1.value }) {
                        label = maxEntry.key
                        confidence = maxEntry.value
                    }
                }
            default:
                throw MLError.predictionFailed
            }
            
            return MLPrediction(
                label: label,
                confidence: confidence,
                probabilities: probabilities,
                processingTime: processingTime
            )
        }
        
        throw MLError.predictionFailed
    }
    
    func batchPredict(samples: [MLSample]) throws -> [MLPrediction] {
        var predictions: [MLPrediction] = []
        
        for sample in samples {
            let prediction = try predict(features: sample.features)
            predictions.append(prediction)
        }
        
        return predictions
    }
    
    func save(to url: URL) throws {
        
        throw MLError.incompatibleModel
    }
}


class LinearRegressionModel: MLModel {
    let name: String = "Linear Regression"
    let version: String = "1.0"
    let inputFeatures: [String]
    let outputFeatures: [String] = ["prediction"]
    
    private var weights: [Double] = []
    private var bias: Double = 0.0
    private var isTrained: Bool = false
    
    init(inputFeatures: [String]) {
        self.inputFeatures = inputFeatures
        self.weights = Array(repeating: 0.0, count: inputFeatures.count)
    }
    
    func train(dataset: MLDataset, learningRate: Double = 0.01, epochs: Int = 1000) throws {
        guard !dataset.isEmpty else {
            throw MLError.insufficientData
        }
        
        let normalizedDataset = dataset.normalize()
        
        for _ in 0..<epochs {
            var gradientWeights = Array(repeating: 0.0, count: weights.count)
            var gradientBias = 0.0
            
            for sample in normalizedDataset.samples {
                guard let labelString = sample.label,
                      let target = Double(labelString) else {
                    continue
                }
                
                let prediction = predict(sample: sample)
                let error = prediction - target
                
                for (i, feature) in sample.features.enumerated() {
                    if i < gradientWeights.count {
                        gradientWeights[i] += error * feature.value
                    }
                }
                gradientBias += error
            }
            
            let sampleCount = Double(normalizedDataset.samples.count)
            
            for i in 0..<weights.count {
                weights[i] -= learningRate * (gradientWeights[i] / sampleCount)
            }
            bias -= learningRate * (gradientBias / sampleCount)
        }
        
        isTrained = true
    }
    
    private func predict(sample: MLSample) -> Double {
        var prediction = bias
        
        for (i, feature) in sample.features.enumerated() {
            if i < weights.count {
                prediction += weights[i] * feature.value
            }
        }
        
        return prediction
    }
    
    func predict(features: [MLFeature]) throws -> MLPrediction {
        guard isTrained else {
            throw MLError.predictionFailed
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let sample = MLSample(features: features)
        let predictionValue = predict(sample: sample)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let processingTime = endTime - startTime
        
        return MLPrediction(
            label: String(predictionValue),
            confidence: 1.0,
            processingTime: processingTime
        )
    }
    
    func batchPredict(samples: [MLSample]) throws -> [MLPrediction] {
        guard isTrained else {
            throw MLError.predictionFailed
        }
        
        return try samples.map { sample in
            try predict(features: sample.features)
        }
    }
    
    func save(to url: URL) throws {
        let modelData = [
            "weights": weights,
            "bias": bias,
            "inputFeatures": inputFeatures,
            "isTrained": isTrained
        ] as [String: Any]
        
        let data = try JSONSerialization.data(withJSONObject: modelData)
        try data.write(to: url)
    }
    
    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let modelData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MLError.modelLoadingFailed
        }
        
        guard let weights = modelData["weights"] as? [Double],
              let bias = modelData["bias"] as? Double,
              let isTrained = modelData["isTrained"] as? Bool else {
            throw MLError.modelLoadingFailed
        }
        
        self.weights = weights
        self.bias = bias
        self.isTrained = isTrained
    }
}


class KMeansClusteringModel: MLModel {
    let name: String = "K-Means Clustering"
    let version: String = "1.0"
    let inputFeatures: [String]
    let outputFeatures: [String] = ["cluster"]
    
    private var centroids: [[Double]] = []
    private let k: Int
    private var isTrained: Bool = false
    
    init(inputFeatures: [String], k: Int) {
        self.inputFeatures = inputFeatures
        self.k = k
    }
    
    func train(dataset: MLDataset, maxIterations: Int = 100) throws {
        guard !dataset.isEmpty else {
            throw MLError.insufficientData
        }
        
        let normalizedDataset = dataset.normalize()
        let featureCount = inputFeatures.count
        
        
        centroids = (0..<k).map { _ in
            (0..<featureCount).map { _ in Double.random(in: 0...1) }
        }
        
        for _ in 0..<maxIterations {
            var newCentroids = Array(repeating: Array(repeating: 0.0, count: featureCount), count: k)
            var clusterCounts = Array(repeating: 0, count: k)
            
            
            for sample in normalizedDataset.samples {
                let clusterIndex = findNearestCluster(sample: sample)
                clusterCounts[clusterIndex] += 1
                
                for (i, feature) in sample.features.enumerated() {
                    if i < featureCount {
                        newCentroids[clusterIndex][i] += feature.value
                    }
                }
            }
            
            
            var hasChanged = false
            for i in 0..<k {
                if clusterCounts[i] > 0 {
                    for j in 0..<featureCount {
                        let newValue = newCentroids[i][j] / Double(clusterCounts[i])
                        if abs(newValue - centroids[i][j]) > 1e-6 {
                            hasChanged = true
                        }
                        centroids[i][j] = newValue
                    }
                }
            }
            
            if !hasChanged {
                break
            }
        }
        
        isTrained = true
    }
    
    private func findNearestCluster(sample: MLSample) -> Int {
        var minDistance = Double.infinity
        var nearestCluster = 0
        
        for (i, centroid) in centroids.enumerated() {
            let distance = calculateDistance(sample: sample, centroid: centroid)
            if distance < minDistance {
                minDistance = distance
                nearestCluster = i
            }
        }
        
        return nearestCluster
    }
    
    private func calculateDistance(sample: MLSample, centroid: [Double]) -> Double {
        var sum = 0.0
        
        for (i, feature) in sample.features.enumerated() {
            if i < centroid.count {
                let diff = feature.value - centroid[i]
                sum += diff * diff
            }
        }
        
        return sqrt(sum)
    }
    
    func predict(features: [MLFeature]) throws -> MLPrediction {
        guard isTrained else {
            throw MLError.predictionFailed
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let sample = MLSample(features: features)
        let clusterIndex = findNearestCluster(sample: sample)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let processingTime = endTime - startTime
        
        return MLPrediction(
            label: "Cluster \(clusterIndex)",
            confidence: 1.0,
            processingTime: processingTime
        )
    }
    
    func batchPredict(samples: [MLSample]) throws -> [MLPrediction] {
        guard isTrained else {
            throw MLError.predictionFailed
        }
        
        return try samples.map { sample in
            try predict(features: sample.features)
        }
    }
    
    func save(to url: URL) throws {
        let modelData = [
            "centroids": centroids,
            "k": k,
            "inputFeatures": inputFeatures,
            "isTrained": isTrained
        ] as [String: Any]
        
        let data = try JSONSerialization.data(withJSONObject: modelData)
        try data.write(to: url)
    }
}


class FeatureEngineer {
    static func extractTextFeatures(from text: String) -> [MLFeature] {
        var features: [MLFeature] = []
        
        
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        features.append(MLFeature(name: "word_count", value: Double(words.count), type: .numerical))
        
        
        features.append(MLFeature(name: "char_count", value: Double(text.count), type: .numerical))
        
        
        let avgWordLength = words.isEmpty ? 0 : Double(words.map { $0.count }.reduce(0, +)) / Double(words.count)
        features.append(MLFeature(name: "avg_word_length", value: avgWordLength, type: .numerical))
        
        
        let positiveWords = ["good", "great", "excellent", "amazing", "wonderful"]
        let negativeWords = ["bad", "terrible", "awful", "horrible", "disappointing"]
        
        let positiveCount = words.filter { positiveWords.contains($0.lowercased()) }.count
        let negativeCount = words.filter { negativeWords.contains($0.lowercased()) }.count
        
        features.append(MLFeature(name: "positive_words", value: Double(positiveCount), type: .numerical))
        features.append(MLFeature(name: "negative_words", value: Double(negativeCount), type: .numerical))
        
        return features
    }
    
    static func extractImageFeatures(from image: UIImage) throws -> [MLFeature] {
        guard let cgImage = image.cgImage else {
            throw MLError.featureExtractionFailed
        }
        
        var features: [MLFeature] = []
        
        
        features.append(MLFeature(name: "width", value: Double(cgImage.width), type: .numerical))
        features.append(MLFeature(name: "height", value: Double(cgImage.height), type: .numerical))
        features.append(MLFeature(name: "aspect_ratio", value: Double(cgImage.width) / Double(cgImage.height), type: .numerical))
        
        
        let colorStats = calculateColorStatistics(image: image)
        features.append(contentsOf: colorStats)
        
        return features
    }
    
    private static func calculateColorStatistics(image: UIImage) -> [MLFeature] {
        guard let cgImage = image.cgImage else { return [] }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var redSum = 0.0, greenSum = 0.0, blueSum = 0.0
        let pixelCount = width * height
        
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            redSum += Double(pixelData[i])
            greenSum += Double(pixelData[i + 1])
            blueSum += Double(pixelData[i + 2])
        }
        
        let avgRed = redSum / Double(pixelCount) / 255.0
        let avgGreen = greenSum / Double(pixelCount) / 255.0
        let avgBlue = blueSum / Double(pixelCount) / 255.0
        
        return [
            MLFeature(name: "avg_red", value: avgRed, type: .numerical),
            MLFeature(name: "avg_green", value: avgGreen, type: .numerical),
            MLFeature(name: "avg_blue", value: avgBlue, type: .numerical),
            MLFeature(name: "brightness", value: (avgRed + avgGreen + avgBlue) / 3.0, type: .numerical)
        ]
    }
    
    static func oneHotEncode(categoricalFeature: String, categories: [String]) -> [MLFeature] {
        return categories.map { category in
            let value = categoricalFeature == category ? 1.0 : 0.0
            return MLFeature(name: "category_\(category)", value: value, type: .binary)
        }
    }
    
    static func polynomialFeatures(features: [MLFeature], degree: Int = 2) -> [MLFeature] {
        var polyFeatures = features
        
        if degree >= 2 {
            
            for feature in features {
                if feature.type == .numerical {
                    let squaredFeature = MLFeature(
                        name: "\(feature.name)_squared",
                        value: feature.value * feature.value,
                        type: .numerical
                    )
                    polyFeatures.append(squaredFeature)
                }
            }
            
            
            for i in 0..<features.count {
                for j in (i+1)..<features.count {
                    if features[i].type == .numerical && features[j].type == .numerical {
                        let interactionFeature = MLFeature(
                            name: "\(features[i].name)_x_\(features[j].name)",
                            value: features[i].value * features[j].value,
                            type: .numerical
                        )
                        polyFeatures.append(interactionFeature)
                    }
                }
            }
        }
        
        return polyFeatures
    }
}


class MLModelManager {
    static let shared = MLModelManager()
    
    private var models: [String: MLModel] = [:]
    private let queue = DispatchQueue(label: "ml.model.manager", qos: .userInitiated)
    
    private init() {}
    
    func registerModel(_ model: MLModel) {
        queue.async {
            self.models[model.name] = model
        }
    }
    
    func getModel(name: String) -> MLModel? {
        return queue.sync {
            return models[name]
        }
    }
    
    func loadCoreMLModel(from url: URL, name: String? = nil) throws {
        let model = try CoreMLModelWrapper(modelURL: url)
        let modelName = name ?? model.name
        registerModel(model)
    }
    
    func predict(modelName: String, features: [MLFeature]) throws -> MLPrediction {
        guard let model = getModel(name: modelName) else {
            throw MLError.modelNotFound
        }
        
        return try model.predict(features: features)
    }
    
    func batchPredict(modelName: String, samples: [MLSample]) throws -> [MLPrediction] {
        guard let model = getModel(name: modelName) else {
            throw MLError.modelNotFound
        }
        
        return try model.batchPredict(samples: samples)
    }
    
    func removeModel(name: String) {
        queue.async {
            self.models.removeValue(forKey: name)
        }
    }
    
    func listModels() -> [String] {
        return queue.sync {
            return Array(models.keys)
        }
    }
}


class ModelEvaluator {
    static func evaluateClassification(predictions: [MLPrediction], trueLabels: [String]) -> [String: Double] {
        guard predictions.count == trueLabels.count else {
            return [:]
        }
        
        var correctPredictions = 0
        var confusionMatrix: [String: [String: Int]] = [:]
        
        for (prediction, trueLabel) in zip(predictions, trueLabels) {
            if prediction.label == trueLabel {
                correctPredictions += 1
            }
            
            
            if confusionMatrix[trueLabel] == nil {
                confusionMatrix[trueLabel] = [:]
            }
            confusionMatrix[trueLabel]![prediction.label, default: 0] += 1
        }
        
        let accuracy = Double(correctPredictions) / Double(predictions.count)
        
        
        var metrics: [String: Double] = ["accuracy": accuracy]
        
        let uniqueLabels = Set(trueLabels)
        var totalPrecision = 0.0
        var totalRecall = 0.0
        var totalF1 = 0.0
        
        for label in uniqueLabels {
            let tp = confusionMatrix[label]?[label] ?? 0
            let fp = confusionMatrix.values.compactMap { $0[label] }.reduce(0, +) - tp
            let fn = (confusionMatrix[label]?.values.reduce(0, +) ?? 0) - tp
            
            let precision = tp > 0 ? Double(tp) / Double(tp + fp) : 0.0
            let recall = tp > 0 ? Double(tp) / Double(tp + fn) : 0.0
            let f1 = (precision + recall) > 0 ? 2 * (precision * recall) / (precision + recall) : 0.0
            
            metrics["precision_\(label)"] = precision
            metrics["recall_\(label)"] = recall
            metrics["f1_\(label)"] = f1
            
            totalPrecision += precision
            totalRecall += recall
            totalF1 += f1
        }
        
        metrics["avg_precision"] = totalPrecision / Double(uniqueLabels.count)
        metrics["avg_recall"] = totalRecall / Double(uniqueLabels.count)
        metrics["avg_f1"] = totalF1 / Double(uniqueLabels.count)
        
        return metrics
    }
    
    static func evaluateRegression(predictions: [MLPrediction], trueValues: [Double]) -> [String: Double] {
        guard predictions.count == trueValues.count else {
            return [:]
        }
        
        let predictedValues = predictions.compactMap { Double($0.label) }
        guard predictedValues.count == trueValues.count else {
            return [:]
        }
        
        
        let mae = zip(predictedValues, trueValues)
            .map { abs($0 - $1) }
            .reduce(0, +) / Double(predictedValues.count)
        
        
        let mse = zip(predictedValues, trueValues)
            .map { pow($0 - $1, 2) }
            .reduce(0, +) / Double(predictedValues.count)
        let rmse = sqrt(mse)
        
        
        let meanTrue = trueValues.reduce(0, +) / Double(trueValues.count)
        let totalSumSquares = trueValues.map { pow($0 - meanTrue, 2) }.reduce(0, +)
        let residualSumSquares = zip(predictedValues, trueValues)
            .map { pow($0 - $1, 2) }
            .reduce(0, +)
        
        let r2 = 1 - (residualSumSquares / totalSumSquares)
        
        return [
            "mae": mae,
            "mse": mse,
            "rmse": rmse,
            "r2": r2
        ]
    }
}


class MLPipeline {
    private var steps: [(String, (MLDataset) throws -> MLDataset)] = []
    
    func addStep(name: String, transform: @escaping (MLDataset) throws -> MLDataset) {
        steps.append((name, transform))
    }
    
    func process(dataset: MLDataset) throws -> MLDataset {
        var processedDataset = dataset
        
        for (stepName, transform) in steps {
            do {
                processedDataset = try transform(processedDataset)
            } catch {
                throw MLError.dataPreprocessingFailed
            }
        }
        
        return processedDataset
    }
    
    func addNormalizationStep() {
        addStep(name: "normalization") { dataset in
            return dataset.normalize()
        }
    }
    
    func addFilterStep(predicate: @escaping (MLSample) -> Bool) {
        addStep(name: "filter") { dataset in
            let filteredSamples = dataset.samples.filter(predicate)
            return MLDataset(samples: filteredSamples, featureNames: dataset.featureNames, labelName: dataset.labelName)
        }
    }
    
    func addFeatureSelectionStep(selectedFeatures: [String]) {
        addStep(name: "feature_selection") { dataset in
            let filteredSamples = dataset.samples.map { sample in
                let filteredFeatures = sample.features.filter { selectedFeatures.contains($0.name) }
                return MLSample(features: filteredFeatures, label: sample.label, weight: sample.weight)
            }
            return MLDataset(samples: filteredSamples, featureNames: selectedFeatures, labelName: dataset.labelName)
        }
    }
}


extension MLModelManager {
    func trainLinearRegression(name: String, dataset: MLDataset, learningRate: Double = 0.01, epochs: Int = 1000) throws {
        let model = LinearRegressionModel(inputFeatures: dataset.featureNames)
        try model.train(dataset: dataset, learningRate: learningRate, epochs: epochs)
        registerModel(model)
    }
    
    func trainKMeansClustering(name: String, dataset: MLDataset, k: Int, maxIterations: Int = 100) throws {
        let model = KMeansClusteringModel(inputFeatures: dataset.featureNames, k: k)
        try model.train(dataset: dataset, maxIterations: maxIterations)
        registerModel(model)
    }
}


@available(iOS 13.0, *)
extension MLModelManager {
    func classifyImage(_ image: UIImage, modelName: String) throws -> MLPrediction {
        guard let model = getModel(name: modelName) as? CoreMLModelWrapper else {
            throw MLError.modelNotFound
        }
        
        let features = try FeatureEngineer.extractImageFeatures(from: image)
        return try model.predict(features: features)
    }
    
    func detectObjects(in image: UIImage, completion: @escaping ([VNRecognizedObjectObservation]) -> Void) {
        let request = VNDetectRectanglesRequest { request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            completion(observations)
        }
        
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
    }
}
