import Foundation
import CoreData
import SQLite3


enum DatabaseError: Error, LocalizedError {
    case connectionFailed
    case queryFailed(String)
    case insertFailed
    case updateFailed
    case deleteFailed
    case migrationFailed
    case corruptedData
    case invalidConfiguration
    case transactionFailed
    case constraintViolation
    case tableNotFound
    case columnNotFound
    case dataTypeMismatch
    case backupFailed
    case restoreFailed
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to database"
        case .queryFailed(let query):
            return "Query failed: \(query)"
        case .insertFailed:
            return "Insert operation failed"
        case .updateFailed:
            return "Update operation failed"
        case .deleteFailed:
            return "Delete operation failed"
        case .migrationFailed:
            return "Database migration failed"
        case .corruptedData:
            return "Database data is corrupted"
        case .invalidConfiguration:
            return "Invalid database configuration"
        case .transactionFailed:
            return "Database transaction failed"
        case .constraintViolation:
            return "Database constraint violation"
        case .tableNotFound:
            return "Table not found"
        case .columnNotFound:
            return "Column not found"
        case .dataTypeMismatch:
            return "Data type mismatch"
        case .backupFailed:
            return "Database backup failed"
        case .restoreFailed:
            return "Database restore failed"
        }
    }
}


struct DatabaseConfiguration {
    let type: DatabaseType
    let name: String
    let version: Int
    let encryptionKey: String?
    let connectionString: String?
    let maxConnections: Int
    let timeout: TimeInterval
    let enableWAL: Bool
    let enableForeignKeys: Bool
    
    init(type: DatabaseType,
         name: String,
         version: Int = 1,
         encryptionKey: String? = nil,
         connectionString: String? = nil,
         maxConnections: Int = 10,
         timeout: TimeInterval = 30,
         enableWAL: Bool = true,
         enableForeignKeys: Bool = true) {
        self.type = type
        self.name = name
        self.version = version
        self.encryptionKey = encryptionKey
        self.connectionString = connectionString
        self.maxConnections = maxConnections
        self.timeout = timeout
        self.enableWAL = enableWAL
        self.enableForeignKeys = enableForeignKeys
    }
}


enum DatabaseType {
    case coreData
    case sqlite
    case remote(url: URL)
    case memory
}


protocol DatabaseQuery {
    var sql: String { get }
    var parameters: [Any] { get }
}


struct BasicQuery: DatabaseQuery {
    let sql: String
    let parameters: [Any]
    
    init(sql: String, parameters: [Any] = []) {
        self.sql = sql
        self.parameters = parameters
    }
}


protocol DatabaseTransaction {
    func execute(_ block: () throws -> Void) throws
    func commit() throws
    func rollback() throws
}


protocol DatabaseProvider {
    associatedtype ResultType
    
    func connect() throws
    func disconnect()
    func execute(query: DatabaseQuery) throws -> ResultType
    func beginTransaction() throws -> DatabaseTransaction
    func migrate(to version: Int) throws
    func backup(to url: URL) throws
    func restore(from url: URL) throws
}


class SQLiteProvider: DatabaseProvider {
    typealias ResultType = [[String: Any]]
    
    private var database: OpaquePointer?
    private let configuration: DatabaseConfiguration
    private let queue = DispatchQueue(label: "sqlite.queue", qos: .utility)
    
    init(configuration: DatabaseConfiguration) {
        self.configuration = configuration
    }
    
    func connect() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let databaseURL = documentsPath.appendingPathComponent("\(configuration.name).sqlite")
        
        let result = sqlite3_open(databaseURL.path, &database)
        guard result == SQLITE_OK else {
            throw DatabaseError.connectionFailed
        }
        
        if configuration.enableWAL {
            try enableWALMode()
        }
        
        if configuration.enableForeignKeys {
            try enableForeignKeys()
        }
        
        try setTimeoutAndOptimizations()
    }
    
    func disconnect() {
        if let database = database {
            sqlite3_close(database)
            self.database = nil
        }
    }
    
    func execute(query: DatabaseQuery) throws -> [[String: Any]] {
        guard let database = database else {
            throw DatabaseError.connectionFailed
        }
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, query.sql, -1, &statement, nil)
        
        guard result == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw DatabaseError.queryFailed(errorMessage)
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        
        try bindParameters(statement: statement, parameters: query.parameters)
        
        var results: [[String: Any]] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let row = extractRow(from: statement)
            results.append(row)
        }
        
        return results
    }
    
    func beginTransaction() throws -> DatabaseTransaction {
        return SQLiteTransaction(database: database!)
    }
    
    func migrate(to version: Int) throws {
        let currentVersion = getCurrentVersion()
        
        if currentVersion < version {
            for migrationVersion in (currentVersion + 1)...version {
                try performMigration(to: migrationVersion)
            }
            try updateVersion(to: version)
        }
    }
    
    func backup(to url: URL) throws {
        guard let database = database else {
            throw DatabaseError.connectionFailed
        }
        
        var backup: OpaquePointer?
        var destination: OpaquePointer?
        
        let result = sqlite3_open(url.path, &destination)
        guard result == SQLITE_OK else {
            throw DatabaseError.backupFailed
        }
        
        backup = sqlite3_backup_init(destination, "main", database, "main")
        guard backup != nil else {
            sqlite3_close(destination)
            throw DatabaseError.backupFailed
        }
        
        let backupResult = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        sqlite3_close(destination)
        
        guard backupResult == SQLITE_DONE else {
            throw DatabaseError.backupFailed
        }
    }
    
    func restore(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DatabaseError.restoreFailed
        }
        
        disconnect()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let databaseURL = documentsPath.appendingPathComponent("\(configuration.name).sqlite")
        
        try FileManager.default.copyItem(at: url, to: databaseURL)
        try connect()
    }
    
    private func enableWALMode() throws {
        let query = BasicQuery(sql: "PRAGMA journal_mode=WAL")
        _ = try execute(query: query)
    }
    
    private func enableForeignKeys() throws {
        let query = BasicQuery(sql: "PRAGMA foreign_keys=ON")
        _ = try execute(query: query)
    }
    
    private func setTimeoutAndOptimizations() throws {
        let timeoutQuery = BasicQuery(sql: "PRAGMA busy_timeout=\(Int(configuration.timeout * 1000))")
        _ = try execute(query: timeoutQuery)
        
        let cacheQuery = BasicQuery(sql: "PRAGMA cache_size=10000")
        _ = try execute(query: cacheQuery)
        
        let syncQuery = BasicQuery(sql: "PRAGMA synchronous=NORMAL")
        _ = try execute(query: syncQuery)
    }
    
    private func bindParameters(statement: OpaquePointer?, parameters: [Any]) throws {
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            
            switch parameter {
            case let stringValue as String:
                sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
            case let intValue as Int:
                sqlite3_bind_int64(statement, bindIndex, Int64(intValue))
            case let doubleValue as Double:
                sqlite3_bind_double(statement, bindIndex, doubleValue)
            case let boolValue as Bool:
                sqlite3_bind_int(statement, bindIndex, boolValue ? 1 : 0)
            case let dataValue as Data:
                dataValue.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, bindIndex, bytes.baseAddress, Int32(dataValue.count), nil)
                }
            case is NSNull:
                sqlite3_bind_null(statement, bindIndex)
            default:
                throw DatabaseError.dataTypeMismatch
            }
        }
    }
    
    private func extractRow(from statement: OpaquePointer?) -> [String: Any] {
        var row: [String: Any] = [:]
        let columnCount = sqlite3_column_count(statement)
        
        for i in 0..<columnCount {
            let columnName = String(cString: sqlite3_column_name(statement, i))
            let columnType = sqlite3_column_type(statement, i)
            
            switch columnType {
            case SQLITE_TEXT:
                let value = String(cString: sqlite3_column_text(statement, i))
                row[columnName] = value
            case SQLITE_INTEGER:
                let value = sqlite3_column_int64(statement, i)
                row[columnName] = Int(value)
            case SQLITE_FLOAT:
                let value = sqlite3_column_double(statement, i)
                row[columnName] = value
            case SQLITE_BLOB:
                let bytes = sqlite3_column_blob(statement, i)
                let count = sqlite3_column_bytes(statement, i)
                let data = Data(bytes: bytes!, count: Int(count))
                row[columnName] = data
            case SQLITE_NULL:
                row[columnName] = NSNull()
            default:
                row[columnName] = NSNull()
            }
        }
        
        return row
    }
    
    private func getCurrentVersion() -> Int {
        do {
            let query = BasicQuery(sql: "PRAGMA user_version")
            let result = try execute(query: query)
            if let firstRow = result.first, let version = firstRow["user_version"] as? Int {
                return version
            }
        } catch {
            
        }
        return 0
    }
    
    private func updateVersion(to version: Int) throws {
        let query = BasicQuery(sql: "PRAGMA user_version = \(version)")
        _ = try execute(query: query)
    }
    
    private func performMigration(to version: Int) throws {
        
        switch version {
        case 1:
            try createInitialTables()
        case 2:
            try addUserProfileTable()
        case 3:
            try addIndexes()
        default:
            break
        }
    }
    
    private func createInitialTables() throws {
        let createUsersTable = BasicQuery(sql: """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        _ = try execute(query: createUsersTable)
        
        let createSessionsTable = BasicQuery(sql: """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                expires_at DATETIME NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
            )
        """)
        _ = try execute(query: createSessionsTable)
    }
    
    private func addUserProfileTable() throws {
        let createProfileTable = BasicQuery(sql: """
            CREATE TABLE IF NOT EXISTS user_profiles (
                user_id INTEGER PRIMARY KEY,
                first_name TEXT,
                last_name TEXT,
                avatar_url TEXT,
                bio TEXT,
                FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
            )
        """)
        _ = try execute(query: createProfileTable)
    }
    
    private func addIndexes() throws {
        let indexes = [
            "CREATE INDEX IF NOT EXISTS idx_users_email ON users (email)",
            "CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions (user_id)",
            "CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions (expires_at)"
        ]
        
        for indexSQL in indexes {
            let query = BasicQuery(sql: indexSQL)
            _ = try execute(query: query)
        }
    }
}


class SQLiteTransaction: DatabaseTransaction {
    private let database: OpaquePointer
    private var isActive = false
    
    init(database: OpaquePointer) {
        self.database = database
    }
    
    func execute(_ block: () throws -> Void) throws {
        guard !isActive else {
            throw DatabaseError.transactionFailed
        }
        
        let beginResult = sqlite3_exec(database, "BEGIN TRANSACTION", nil, nil, nil)
        guard beginResult == SQLITE_OK else {
            throw DatabaseError.transactionFailed
        }
        
        isActive = true
        
        do {
            try block()
            try commit()
        } catch {
            try rollback()
            throw error
        }
    }
    
    func commit() throws {
        guard isActive else {
            throw DatabaseError.transactionFailed
        }
        
        let commitResult = sqlite3_exec(database, "COMMIT", nil, nil, nil)
        guard commitResult == SQLITE_OK else {
            throw DatabaseError.transactionFailed
        }
        
        isActive = false
    }
    
    func rollback() throws {
        guard isActive else {
            throw DatabaseError.transactionFailed
        }
        
        let rollbackResult = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
        guard rollbackResult == SQLITE_OK else {
            throw DatabaseError.transactionFailed
        }
        
        isActive = false
    }
}


class CoreDataProvider: DatabaseProvider {
    typealias ResultType = [NSManagedObject]
    
    private let configuration: DatabaseConfiguration
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: configuration.name)
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data error: \(error)")
            }
        }
        return container
    }()
    
    private var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    init(configuration: DatabaseConfiguration) {
        self.configuration = configuration
    }
    
    func connect() throws {
        
        _ = persistentContainer
    }
    
    func disconnect() {
        
    }
    
    func execute(query: DatabaseQuery) throws -> [NSManagedObject] {
        
        
        throw DatabaseError.queryFailed("Core Data provider doesn't support raw SQL queries")
    }
    
    func beginTransaction() throws -> DatabaseTransaction {
        return CoreDataTransaction(context: context)
    }
    
    func migrate(to version: Int) throws {
        
        
    }
    
    func backup(to url: URL) throws {
        let coordinator = persistentContainer.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first else {
            throw DatabaseError.backupFailed
        }
        
        try coordinator.migratePersistentStore(store, to: url, options: nil, withType: NSSQLiteStoreType)
    }
    
    func restore(from url: URL) throws {
        
        throw DatabaseError.restoreFailed
    }
    
    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    func fetch<T: NSManagedObject>(entity: T.Type, predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: entity))
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        
        return try context.fetch(request)
    }
    
    func create<T: NSManagedObject>(entity: T.Type) -> T {
        let entityName = String(describing: entity)
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as! T
    }
    
    func delete(_ object: NSManagedObject) {
        context.delete(object)
    }
}


class CoreDataTransaction: DatabaseTransaction {
    private let context: NSManagedObjectContext
    private var childContext: NSManagedObjectContext?
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    func execute(_ block: () throws -> Void) throws {
        let child = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        child.parent = context
        childContext = child
        
        try child.performAndWait {
            try block()
            try commit()
        }
    }
    
    func commit() throws {
        guard let child = childContext else {
            throw DatabaseError.transactionFailed
        }
        
        if child.hasChanges {
            try child.save()
        }
        
        if context.hasChanges {
            try context.save()
        }
    }
    
    func rollback() throws {
        childContext?.rollback()
        context.rollback()
    }
}


class QueryBuilder {
    private var selectFields: [String] = []
    private var fromTable: String = ""
    private var whereConditions: [String] = []
    private var joinClauses: [String] = []
    private var orderByFields: [String] = []
    private var limitValue: Int?
    private var offsetValue: Int?
    private var parameters: [Any] = []
    
    func select(_ fields: String...) -> QueryBuilder {
        selectFields.append(contentsOf: fields)
        return self
    }
    
    func from(_ table: String) -> QueryBuilder {
        fromTable = table
        return self
    }
    
    func `where`(_ condition: String, parameters: Any...) -> QueryBuilder {
        whereConditions.append(condition)
        self.parameters.append(contentsOf: parameters)
        return self
    }
    
    func join(_ table: String, on condition: String) -> QueryBuilder {
        joinClauses.append("JOIN \(table) ON \(condition)")
        return self
    }
    
    func leftJoin(_ table: String, on condition: String) -> QueryBuilder {
        joinClauses.append("LEFT JOIN \(table) ON \(condition)")
        return self
    }
    
    func orderBy(_ field: String, ascending: Bool = true) -> QueryBuilder {
        let direction = ascending ? "ASC" : "DESC"
        orderByFields.append("\(field) \(direction)")
        return self
    }
    
    func limit(_ limit: Int) -> QueryBuilder {
        limitValue = limit
        return self
    }
    
    func offset(_ offset: Int) -> QueryBuilder {
        offsetValue = offset
        return self
    }
    
    func build() -> DatabaseQuery {
        var sql = "SELECT "
        
        if selectFields.isEmpty {
            sql += "*"
        } else {
            sql += selectFields.joined(separator: ", ")
        }
        
        sql += " FROM \(fromTable)"
        
        if !joinClauses.isEmpty {
            sql += " " + joinClauses.joined(separator: " ")
        }
        
        if !whereConditions.isEmpty {
            sql += " WHERE " + whereConditions.joined(separator: " AND ")
        }
        
        if !orderByFields.isEmpty {
            sql += " ORDER BY " + orderByFields.joined(separator: ", ")
        }
        
        if let limit = limitValue {
            sql += " LIMIT \(limit)"
        }
        
        if let offset = offsetValue {
            sql += " OFFSET \(offset)"
        }
        
        return BasicQuery(sql: sql, parameters: parameters)
    }
}


class DatabaseService {
    static let shared = DatabaseService()
    
    private var providers: [String: Any] = [:]
    private let queue = DispatchQueue(label: "database.service", qos: .utility)
    
    private init() {}
    
    func configure(name: String, configuration: DatabaseConfiguration) throws {
        switch configuration.type {
        case .sqlite, .memory:
            let provider = SQLiteProvider(configuration: configuration)
            try provider.connect()
            providers[name] = provider
        case .coreData:
            let provider = CoreDataProvider(configuration: configuration)
            try provider.connect()
            providers[name] = provider
        case .remote:
            
            throw DatabaseError.invalidConfiguration
        }
    }
    
    func getProvider<T: DatabaseProvider>(name: String, type: T.Type) -> T? {
        return providers[name] as? T
    }
    
    func execute(query: DatabaseQuery, database: String = "default") throws -> [[String: Any]] {
        guard let provider = providers[database] as? SQLiteProvider else {
            throw DatabaseError.connectionFailed
        }
        
        return try provider.execute(query: query)
    }
    
    func transaction<T>(database: String = "default", block: () throws -> T) throws -> T {
        guard let provider = providers[database] as? SQLiteProvider else {
            throw DatabaseError.connectionFailed
        }
        
        let transaction = try provider.beginTransaction()
        
        do {
            let result = try block()
            try transaction.commit()
            return result
        } catch {
            try transaction.rollback()
            throw error
        }
    }
    
    func backup(database: String = "default", to url: URL) throws {
        guard let provider = providers[database] as? SQLiteProvider else {
            throw DatabaseError.connectionFailed
        }
        
        try provider.backup(to: url)
    }
    
    func restore(database: String = "default", from url: URL) throws {
        guard let provider = providers[database] as? SQLiteProvider else {
            throw DatabaseError.connectionFailed
        }
        
        try provider.restore(from: url)
    }
    
    func queryBuilder() -> QueryBuilder {
        return QueryBuilder()
    }
}


extension DatabaseService {
    func insertUser(username: String, email: String, passwordHash: String) throws -> Int {
        let query = BasicQuery(
            sql: "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)",
            parameters: [username, email, passwordHash]
        )
        
        _ = try execute(query: query)
        
        let lastInsertQuery = BasicQuery(sql: "SELECT last_insert_rowid()")
        let result = try execute(query: lastInsertQuery)
        
        if let firstRow = result.first, let id = firstRow["last_insert_rowid()"] as? Int {
            return id
        }
        
        throw DatabaseError.insertFailed
    }
    
    func findUser(by email: String) throws -> [String: Any]? {
        let query = queryBuilder()
            .select("*")
            .from("users")
            .where("email = ?", parameters: email)
            .build()
        
        let result = try execute(query: query)
        return result.first
    }
    
    func updateUser(id: Int, fields: [String: Any]) throws {
        let setClause = fields.keys.map { "\($0) = ?" }.joined(separator: ", ")
        let values = Array(fields.values)
        
        let query = BasicQuery(
            sql: "UPDATE users SET \(setClause) WHERE id = ?",
            parameters: values + [id]
        )
        
        _ = try execute(query: query)
    }
    
    func deleteUser(id: Int) throws {
        let query = BasicQuery(
            sql: "DELETE FROM users WHERE id = ?",
            parameters: [id]
        )
        
        _ = try execute(query: query)
    }
    
    func createSession(userId: Int, sessionId: String, expiresAt: Date) throws {
        let query = BasicQuery(
            sql: "INSERT INTO sessions (id, user_id, expires_at) VALUES (?, ?, ?)",
            parameters: [sessionId, userId, expiresAt]
        )
        
        _ = try execute(query: query)
    }
    
    func cleanupExpiredSessions() throws {
        let query = BasicQuery(
            sql: "DELETE FROM sessions WHERE expires_at < ?",
            parameters: [Date()]
        )
        
        _ = try execute(query: query)
    }
}


class MigrationManager {
    private let databaseService: DatabaseService
    
    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }
    
    func runMigrations(for database: String = "default", to targetVersion: Int) throws {
        guard let provider = databaseService.getProvider(name: database, type: SQLiteProvider.self) else {
            throw DatabaseError.connectionFailed
        }
        
        try provider.migrate(to: targetVersion)
    }
    
    func getCurrentVersion(for database: String = "default") throws -> Int {
        let query = BasicQuery(sql: "PRAGMA user_version")
        let result = try databaseService.execute(query: query, database: database)
        
        if let firstRow = result.first, let version = firstRow["user_version"] as? Int {
            return version
        }
        
        return 0
    }
}


class ConnectionPool {
    private var availableConnections: [SQLiteProvider] = []
    private var activeConnections: [SQLiteProvider] = []
    private let maxConnections: Int
    private let configuration: DatabaseConfiguration
    private let semaphore: DispatchSemaphore
    private let queue = DispatchQueue(label: "connection.pool", qos: .utility)
    
    init(configuration: DatabaseConfiguration) {
        self.configuration = configuration
        self.maxConnections = configuration.maxConnections
        self.semaphore = DispatchSemaphore(value: maxConnections)
    }
    
    func getConnection() throws -> SQLiteProvider {
        semaphore.wait()
        
        return try queue.sync {
            if let connection = availableConnections.popLast() {
                activeConnections.append(connection)
                return connection
            } else {
                let connection = SQLiteProvider(configuration: configuration)
                try connection.connect()
                activeConnections.append(connection)
                return connection
            }
        }
    }
    
    func returnConnection(_ connection: SQLiteProvider) {
        queue.sync {
            if let index = activeConnections.firstIndex(where: { $0 === connection }) {
                activeConnections.remove(at: index)
                availableConnections.append(connection)
            }
        }
        semaphore.signal()
    }
    
    func closeAllConnections() {
        queue.sync {
            for connection in availableConnections + activeConnections {
                connection.disconnect()
            }
            availableConnections.removeAll()
            activeConnections.removeAll()
        }
    }
}
