import Foundation
import CoreData

class CoreDataManager {
    static let shared = CoreDataManager()
    
    private init() {}
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "DataModel")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data error: \(error)")
            }
        }
        return container
    }()
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    func save() {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
    
    func fetch<T: NSManagedObject>(_ objectType: T.Type) -> [T] {
        let entityName = String(describing: objectType)
        let request = NSFetchRequest<T>(entityName: entityName)
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch \(entityName): \(error)")
            return []
        }
    }
    
    func delete(_ object: NSManagedObject) {
        context.delete(object)
        save()
    }
    
    func deleteAll<T: NSManagedObject>(_ objectType: T.Type) {
        let objects = fetch(objectType)
        objects.forEach { context.delete($0) }
        save()
    }
    
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        persistentContainer.performBackgroundTask(block)
    }
}


extension NSManagedObject {
    static var entityName: String {
        return String(describing: self)
    }
    
    static func create(in context: NSManagedObjectContext) -> Self {
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as! Self
    }
}


protocol Repository {
    associatedtype Entity: NSManagedObject
    
    func getAll() -> [Entity]
    func get(by predicate: NSPredicate) -> [Entity]
    func create() -> Entity
    func delete(_ entity: Entity)
    func save()
}

class GenericRepository<T: NSManagedObject>: Repository {
    typealias Entity = T
    
    private let coreDataManager = CoreDataManager.shared
    
    func getAll() -> [T] {
        return coreDataManager.fetch(T.self)
    }
    
    func get(by predicate: NSPredicate) -> [T] {
        let request = NSFetchRequest<T>(entityName: T.entityName)
        request.predicate = predicate
        
        do {
            return try coreDataManager.context.fetch(request)
        } catch {
            print("Failed to fetch with predicate: \(error)")
            return []
        }
    }
    
    func create() -> T {
        return T.create(in: coreDataManager.context)
    }
    
    func delete(_ entity: T) {
        coreDataManager.delete(entity)
    }
    
    func save() {
        coreDataManager.save()
    }
}
