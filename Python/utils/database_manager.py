import asyncio
import threading
import time
import logging
import hashlib
import json
from abc import ABC, abstractmethod
from contextlib import contextmanager, asynccontextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from functools import wraps
from typing import Any, Dict, List, Optional, Union, Callable, TypeVar, Generic, Tuple
from queue import Queue, Empty
from weakref import WeakValueDictionary
import sqlite3
import asyncpg
import psycopg2
from psycopg2 import pool as pg_pool
from sqlalchemy import create_engine, text, MetaData, Table
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import QueuePool, StaticPool
from sqlalchemy.exc import SQLAlchemyError
from redis import Redis, ConnectionPool as RedisPool
import pymongo
from pymongo import MongoClient

T = TypeVar('T')

class DatabaseType(Enum):
    POSTGRESQL = "postgresql"
    MYSQL = "mysql"
    SQLITE = "sqlite"
    REDIS = "redis"
    MONGODB = "mongodb"
    ORACLE = "oracle"
    MSSQL = "mssql"

class ConnectionState(Enum):
    IDLE = "idle"
    ACTIVE = "active"
    CLOSED = "closed"
    ERROR = "error"
    TESTING = "testing"

class TransactionIsolation(Enum):
    READ_UNCOMMITTED = "READ UNCOMMITTED"
    READ_COMMITTED = "READ COMMITTED"
    REPEATABLE_READ = "REPEATABLE READ"
    SERIALIZABLE = "SERIALIZABLE"

@dataclass
class DatabaseConfig:
    host: str
    port: int
    database: str
    username: str
    password: str
    db_type: DatabaseType
    pool_size: int = 10
    max_overflow: int = 20
    pool_timeout: int = 30
    pool_recycle: int = 3600
    pool_pre_ping: bool = True
    connect_timeout: int = 10
    command_timeout: int = 30
    ssl_mode: str = "prefer"
    charset: str = "utf8mb4"
    options: Dict[str, Any] = field(default_factory=dict)
    
    def get_connection_string(self) -> str:
        if self.db_type == DatabaseType.POSTGRESQL:
            return f"postgresql://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}"
        elif self.db_type == DatabaseType.MYSQL:
            return f"mysql+pymysql://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}?charset={self.charset}"
        elif self.db_type == DatabaseType.SQLITE:
            return f"sqlite:///{self.database}"
        elif self.db_type == DatabaseType.ORACLE:
            return f"oracle+cx_oracle://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}"
        elif self.db_type == DatabaseType.MSSQL:
            return f"mssql+pyodbc://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}?driver=ODBC+Driver+17+for+SQL+Server"
        else:
            raise ValueError(f"Unsupported database type: {self.db_type}")

@dataclass
class ConnectionMetrics:
    total_connections: int = 0
    active_connections: int = 0
    idle_connections: int = 0
    failed_connections: int = 0
    total_queries: int = 0
    successful_queries: int = 0
    failed_queries: int = 0
    average_query_time: float = 0.0
    peak_connections: int = 0
    connection_errors: int = 0
    last_error: Optional[str] = None
    uptime: float = 0.0
    
    def update_query_time(self, query_time: float):
        total_queries = self.successful_queries + self.failed_queries
        if total_queries > 0:
            self.average_query_time = (
                (self.average_query_time * (total_queries - 1) + query_time) / total_queries
            )

@dataclass
class QueryResult:
    data: List[Dict[str, Any]]
    row_count: int
    execution_time: float
    query_hash: str
    timestamp: datetime
    columns: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

class DatabaseConnection:
    def __init__(self, connection: Any, config: DatabaseConfig):
        self.connection = connection
        self.config = config
        self.state = ConnectionState.IDLE
        self.created_at = datetime.now()
        self.last_used = datetime.now()
        self.query_count = 0
        self.error_count = 0
        self.transaction_active = False
        self.lock = threading.Lock()
    
    def is_healthy(self) -> bool:
        try:
            if self.config.db_type == DatabaseType.POSTGRESQL:
                cursor = self.connection.cursor()
                cursor.execute("SELECT 1")
                cursor.close()
            elif self.config.db_type == DatabaseType.MYSQL:
                cursor = self.connection.cursor()
                cursor.execute("SELECT 1")
                cursor.close()
            elif self.config.db_type == DatabaseType.SQLITE:
                cursor = self.connection.cursor()
                cursor.execute("SELECT 1")
                cursor.close()
            return True
        except Exception:
            return False
    
    def reset(self):
        if self.transaction_active:
            try:
                self.connection.rollback()
                self.transaction_active = False
            except Exception:
                pass
    
    def close(self):
        try:
            if self.transaction_active:
                self.connection.rollback()
            self.connection.close()
            self.state = ConnectionState.CLOSED
        except Exception:
            pass

class ConnectionPool:
    def __init__(self, config: DatabaseConfig):
        self.config = config
        self.connections: Queue = Queue(maxsize=config.pool_size + config.max_overflow)
        self.active_connections: Dict[int, DatabaseConnection] = {}
        self.metrics = ConnectionMetrics()
        self.lock = threading.RLock()
        self.health_check_interval = 300
        self.health_check_thread = None
        self.start_time = time.time()
        self._initialize_pool()
        self._start_health_check()
    
    def _initialize_pool(self):
        for _ in range(self.config.pool_size):
            try:
                conn = self._create_connection()
                self.connections.put(conn)
                self.metrics.total_connections += 1
                self.metrics.idle_connections += 1
            except Exception as e:
                self.metrics.failed_connections += 1
                self.metrics.last_error = str(e)
    
    def _create_connection(self) -> DatabaseConnection:
        if self.config.db_type == DatabaseType.POSTGRESQL:
            import psycopg2
            conn = psycopg2.connect(
                host=self.config.host,
                port=self.config.port,
                database=self.config.database,
                user=self.config.username,
                password=self.config.password,
                connect_timeout=self.config.connect_timeout
            )
        elif self.config.db_type == DatabaseType.MYSQL:
            import pymysql
            conn = pymysql.connect(
                host=self.config.host,
                port=self.config.port,
                database=self.config.database,
                user=self.config.username,
                password=self.config.password,
                charset=self.config.charset,
                connect_timeout=self.config.connect_timeout
            )
        elif self.config.db_type == DatabaseType.SQLITE:
            conn = sqlite3.connect(
                self.config.database,
                timeout=self.config.connect_timeout,
                check_same_thread=False
            )
        else:
            raise ValueError(f"Unsupported database type: {self.config.db_type}")
        
        return DatabaseConnection(conn, self.config)
    
    @contextmanager
    def get_connection(self):
        conn = None
        try:
            conn = self._acquire_connection()
            yield conn
        finally:
            if conn:
                self._release_connection(conn)
    
    def _acquire_connection(self) -> DatabaseConnection:
        with self.lock:
            try:
                conn = self.connections.get(timeout=self.config.pool_timeout)
                conn.state = ConnectionState.ACTIVE
                conn.last_used = datetime.now()
                
                self.active_connections[id(conn)] = conn
                self.metrics.active_connections += 1
                self.metrics.idle_connections -= 1
                
                if self.metrics.active_connections > self.metrics.peak_connections:
                    self.metrics.peak_connections = self.metrics.active_connections
                
                if not conn.is_healthy():
                    self._replace_connection(conn)
                    return self._acquire_connection()
                
                return conn
                
            except Empty:
                if len(self.active_connections) < self.config.pool_size + self.config.max_overflow:
                    conn = self._create_connection()
                    conn.state = ConnectionState.ACTIVE
                    self.active_connections[id(conn)] = conn
                    self.metrics.total_connections += 1
                    self.metrics.active_connections += 1
                    return conn
                else:
                    raise Exception("Connection pool exhausted")
    
    def _release_connection(self, conn: DatabaseConnection):
        with self.lock:
            if id(conn) in self.active_connections:
                del self.active_connections[id(conn)]
                self.metrics.active_connections -= 1
                
                conn.reset()
                conn.state = ConnectionState.IDLE
                
                if conn.is_healthy():
                    self.connections.put(conn)
                    self.metrics.idle_connections += 1
                else:
                    self._replace_connection(conn)
    
    def _replace_connection(self, old_conn: DatabaseConnection):
        try:
            old_conn.close()
            new_conn = self._create_connection()
            self.connections.put(new_conn)
            self.metrics.idle_connections += 1
        except Exception as e:
            self.metrics.connection_errors += 1
            self.metrics.last_error = str(e)
    
    def _start_health_check(self):
        def health_check_worker():
            while True:
                time.sleep(self.health_check_interval)
                self._perform_health_check()
        
        self.health_check_thread = threading.Thread(target=health_check_worker, daemon=True)
        self.health_check_thread.start()
    
    def _perform_health_check(self):
        with self.lock:
            unhealthy_connections = []
            temp_connections = []
            
            while not self.connections.empty():
                try:
                    conn = self.connections.get_nowait()
                    if conn.is_healthy():
                        temp_connections.append(conn)
                    else:
                        unhealthy_connections.append(conn)
                except Empty:
                    break
            
            for conn in temp_connections:
                self.connections.put(conn)
            
            for conn in unhealthy_connections:
                self._replace_connection(conn)
    
    def get_metrics(self) -> ConnectionMetrics:
        with self.lock:
            self.metrics.uptime = time.time() - self.start_time
            return self.metrics
    
    def close_all(self):
        with self.lock:
            while not self.connections.empty():
                try:
                    conn = self.connections.get_nowait()
                    conn.close()
                except Empty:
                    break
            
            for conn in self.active_connections.values():
                conn.close()
            
            self.active_connections.clear()

class QueryExecutor:
    def __init__(self, pool: ConnectionPool):
        self.pool = pool
        self.query_cache: Dict[str, QueryResult] = {}
        self.cache_ttl = 300
        self.cache_lock = threading.Lock()
    
    def execute_query(self, query: str, params: Optional[Tuple] = None, 
                     cache_key: Optional[str] = None) -> QueryResult:
        start_time = time.time()
        query_hash = hashlib.md5(f"{query}{params or ''}".encode()).hexdigest()
        
        if cache_key and self._get_cached_result(cache_key):
            return self._get_cached_result(cache_key)
        
        with self.pool.get_connection() as db_conn:
            try:
                cursor = db_conn.connection.cursor()
                
                if params:
                    cursor.execute(query, params)
                else:
                    cursor.execute(query)
                
                if cursor.description:
                    columns = [desc[0] for desc in cursor.description]
                    rows = cursor.fetchall()
                    data = [dict(zip(columns, row)) for row in rows]
                else:
                    columns = []
                    data = []
                    rows = []
                
                cursor.close()
                
                execution_time = time.time() - start_time
                result = QueryResult(
                    data=data,
                    row_count=len(rows) if rows else cursor.rowcount,
                    execution_time=execution_time,
                    query_hash=query_hash,
                    timestamp=datetime.now(),
                    columns=columns
                )
                
                if cache_key:
                    self._cache_result(cache_key, result)
                
                self.pool.metrics.successful_queries += 1
                self.pool.metrics.update_query_time(execution_time)
                
                return result
                
            except Exception as e:
                self.pool.metrics.failed_queries += 1
                self.pool.metrics.last_error = str(e)
                raise
    
    def execute_many(self, query: str, params_list: List[Tuple]) -> List[QueryResult]:
        results = []
        
        with self.pool.get_connection() as db_conn:
            try:
                cursor = db_conn.connection.cursor()
                
                for params in params_list:
                    start_time = time.time()
                    cursor.execute(query, params)
                    
                    if cursor.description:
                        columns = [desc[0] for desc in cursor.description]
                        rows = cursor.fetchall()
                        data = [dict(zip(columns, row)) for row in rows]
                    else:
                        columns = []
                        data = []
                        rows = []
                    
                    execution_time = time.time() - start_time
                    query_hash = hashlib.md5(f"{query}{params}".encode()).hexdigest()
                    
                    result = QueryResult(
                        data=data,
                        row_count=len(rows) if rows else cursor.rowcount,
                        execution_time=execution_time,
                        query_hash=query_hash,
                        timestamp=datetime.now(),
                        columns=columns
                    )
                    
                    results.append(result)
                    self.pool.metrics.successful_queries += 1
                    self.pool.metrics.update_query_time(execution_time)
                
                cursor.close()
                return results
                
            except Exception as e:
                self.pool.metrics.failed_queries += 1
                self.pool.metrics.last_error = str(e)
                raise
    
    def _get_cached_result(self, cache_key: str) -> Optional[QueryResult]:
        with self.cache_lock:
            if cache_key in self.query_cache:
                result = self.query_cache[cache_key]
                if (datetime.now() - result.timestamp).total_seconds() < self.cache_ttl:
                    return result
                else:
                    del self.query_cache[cache_key]
            return None
    
    def _cache_result(self, cache_key: str, result: QueryResult):
        with self.cache_lock:
            self.query_cache[cache_key] = result
    
    def clear_cache(self):
        with self.cache_lock:
            self.query_cache.clear()

class TransactionManager:
    def __init__(self, pool: ConnectionPool):
        self.pool = pool
        self.active_transactions: Dict[int, DatabaseConnection] = {}
        self.transaction_lock = threading.Lock()
    
    @contextmanager
    def transaction(self, isolation_level: Optional[TransactionIsolation] = None):
        conn = None
        try:
            conn = self.pool._acquire_connection()
            
            if isolation_level:
                self._set_isolation_level(conn, isolation_level)
            
            conn.connection.begin()
            conn.transaction_active = True
            
            with self.transaction_lock:
                self.active_transactions[id(conn)] = conn
            
            yield conn
            
            conn.connection.commit()
            conn.transaction_active = False
            
        except Exception as e:
            if conn and conn.transaction_active:
                try:
                    conn.connection.rollback()
                    conn.transaction_active = False
                except Exception:
                    pass
            raise
        finally:
            if conn:
                with self.transaction_lock:
                    self.active_transactions.pop(id(conn), None)
                self.pool._release_connection(conn)
    
    def _set_isolation_level(self, conn: DatabaseConnection, level: TransactionIsolation):
        if conn.config.db_type == DatabaseType.POSTGRESQL:
            cursor = conn.connection.cursor()
            cursor.execute(f"SET TRANSACTION ISOLATION LEVEL {level.value}")
            cursor.close()
        elif conn.config.db_type == DatabaseType.MYSQL:
            cursor = conn.connection.cursor()
            cursor.execute(f"SET TRANSACTION ISOLATION LEVEL {level.value}")
            cursor.close()
    
    def rollback_all_transactions(self):
        with self.transaction_lock:
            for conn in list(self.active_transactions.values()):
                try:
                    if conn.transaction_active:
                        conn.connection.rollback()
                        conn.transaction_active = False
                except Exception:
                    pass

class DatabaseManager:
    _instances: Dict[str, 'DatabaseManager'] = {}
    _lock = threading.Lock()
    
    def __new__(cls, config: DatabaseConfig, name: str = "default"):
        with cls._lock:
            if name not in cls._instances:
                instance = super().__new__(cls)
                cls._instances[name] = instance
            return cls._instances[name]
    
    def __init__(self, config: DatabaseConfig, name: str = "default"):
        if not hasattr(self, 'initialized'):
            self.config = config
            self.name = name
            self.pool = ConnectionPool(config)
            self.query_executor = QueryExecutor(self.pool)
            self.transaction_manager = TransactionManager(self.pool)
            self.migration_manager = MigrationManager(self)
            self.backup_manager = BackupManager(self)
            self.initialized = True
    
    @classmethod
    def get_instance(cls, name: str = "default") -> 'DatabaseManager':
        with cls._lock:
            if name in cls._instances:
                return cls._instances[name]
            raise ValueError(f"Database manager '{name}' not found")
    
    def execute_query(self, query: str, params: Optional[Tuple] = None, 
                     cache_key: Optional[str] = None) -> QueryResult:
        return self.query_executor.execute_query(query, params, cache_key)
    
    def execute_many(self, query: str, params_list: List[Tuple]) -> List[QueryResult]:
        return self.query_executor.execute_many(query, params_list)
    
    @contextmanager
    def transaction(self, isolation_level: Optional[TransactionIsolation] = None):
        with self.transaction_manager.transaction(isolation_level) as conn:
            yield DatabaseSession(conn, self.query_executor)
    
    def get_metrics(self) -> ConnectionMetrics:
        return self.pool.get_metrics()
    
    def health_check(self) -> Dict[str, Any]:
        metrics = self.get_metrics()
        return {
            "status": "healthy" if metrics.connection_errors == 0 else "degraded",
            "total_connections": metrics.total_connections,
            "active_connections": metrics.active_connections,
            "idle_connections": metrics.idle_connections,
            "failed_connections": metrics.failed_connections,
            "uptime": metrics.uptime,
            "last_error": metrics.last_error
        }
    
    def close(self):
        self.pool.close_all()
        with self._lock:
            if self.name in self._instances:
                del self._instances[self.name]

class DatabaseSession:
    def __init__(self, connection: DatabaseConnection, query_executor: QueryExecutor):
        self.connection = connection
        self.query_executor = query_executor
    
    def execute(self, query: str, params: Optional[Tuple] = None) -> QueryResult:
        start_time = time.time()
        query_hash = hashlib.md5(f"{query}{params or ''}".encode()).hexdigest()
        
        try:
            cursor = self.connection.connection.cursor()
            
            if params:
                cursor.execute(query, params)
            else:
                cursor.execute(query)
            
            if cursor.description:
                columns = [desc[0] for desc in cursor.description]
                rows = cursor.fetchall()
                data = [dict(zip(columns, row)) for row in rows]
            else:
                columns = []
                data = []
                rows = []
            
            cursor.close()
            
            execution_time = time.time() - start_time
            return QueryResult(
                data=data,
                row_count=len(rows) if rows else cursor.rowcount,
                execution_time=execution_time,
                query_hash=query_hash,
                timestamp=datetime.now(),
                columns=columns
            )
            
        except Exception as e:
            raise

class MigrationManager:
    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager
        self.migrations_table = "schema_migrations"
        self._ensure_migrations_table()
    
    def _ensure_migrations_table(self):
        create_table_query = f"""
        CREATE TABLE IF NOT EXISTS {self.migrations_table} (
            version VARCHAR(255) PRIMARY KEY,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            checksum VARCHAR(64)
        )
        """
        self.db_manager.execute_query(create_table_query)
    
    def apply_migration(self, version: str, migration_sql: str) -> bool:
        checksum = hashlib.sha256(migration_sql.encode()).hexdigest()
        
        with self.db_manager.transaction() as session:
            existing = session.execute(
                f"SELECT checksum FROM {self.migrations_table} WHERE version = %s",
                (version,)
            )
            
            if existing.data:
                if existing.data[0]['checksum'] != checksum:
                    raise ValueError(f"Migration {version} checksum mismatch")
                return False
            
            session.execute(migration_sql)
            session.execute(
                f"INSERT INTO {self.migrations_table} (version, checksum) VALUES (%s, %s)",
                (version, checksum)
            )
            
            return True
    
    def get_applied_migrations(self) -> List[str]:
        result = self.db_manager.execute_query(
            f"SELECT version FROM {self.migrations_table} ORDER BY applied_at"
        )
        return [row['version'] for row in result.data]

class BackupManager:
    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager
    
    def create_backup(self, backup_path: str, tables: Optional[List[str]] = None) -> bool:
        try:
            if self.db_manager.config.db_type == DatabaseType.POSTGRESQL:
                return self._create_postgres_backup(backup_path, tables)
            elif self.db_manager.config.db_type == DatabaseType.MYSQL:
                return self._create_mysql_backup(backup_path, tables)
            elif self.db_manager.config.db_type == DatabaseType.SQLITE:
                return self._create_sqlite_backup(backup_path)
            else:
                raise NotImplementedError(f"Backup not supported for {self.db_manager.config.db_type}")
        except Exception:
            return False
    
    def _create_postgres_backup(self, backup_path: str, tables: Optional[List[str]]) -> bool:
        import subprocess
        
        cmd = [
            "pg_dump",
            "-h", self.db_manager.config.host,
            "-p", str(self.db_manager.config.port),
            "-U", self.db_manager.config.username,
            "-d", self.db_manager.config.database,
            "-f", backup_path
        ]
        
        if tables:
            for table in tables:
                cmd.extend(["-t", table])
        
        env = {"PGPASSWORD": self.db_manager.config.password}
        result = subprocess.run(cmd, env=env, capture_output=True)
        
        return result.returncode == 0
    
    def _create_mysql_backup(self, backup_path: str, tables: Optional[List[str]]) -> bool:
        import subprocess
        
        cmd = [
            "mysqldump",
            "-h", self.db_manager.config.host,
            "-P", str(self.db_manager.config.port),
            "-u", self.db_manager.config.username,
            f"-p{self.db_manager.config.password}",
            self.db_manager.config.database
        ]
        
        if tables:
            cmd.extend(tables)
        
        with open(backup_path, 'w') as f:
            result = subprocess.run(cmd, stdout=f, capture_output=False)
        
        return result.returncode == 0
    
    def _create_sqlite_backup(self, backup_path: str) -> bool:
        import shutil
        try:
            shutil.copy2(self.db_manager.config.database, backup_path)
            return True
        except Exception:
            return False

def database_operation(db_name: str = "default", cache_key: Optional[str] = None):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            db_manager = DatabaseManager.get_instance(db_name)
            
            if hasattr(func, '__annotations__') and 'return' in func.__annotations__:
                if 'query' in kwargs or (args and isinstance(args[0], str)):
                    query = kwargs.get('query', args[0] if args else "")
                    params = kwargs.get('params', args[1] if len(args) > 1 else None)
                    return db_manager.execute_query(query, params, cache_key)
            
            return func(db_manager, *args, **kwargs)
        return wrapper
    return decorator

class DatabaseRouter:
    def __init__(self):
        self.read_databases: List[DatabaseManager] = []
        self.write_databases: List[DatabaseManager] = []
        self.current_read_index = 0
        self.current_write_index = 0
        self.lock = threading.Lock()
    
    def add_read_database(self, db_manager: DatabaseManager):
        with self.lock:
            self.read_databases.append(db_manager)
    
    def add_write_database(self, db_manager: DatabaseManager):
        with self.lock:
            self.write_databases.append(db_manager)
    
    def get_read_database(self) -> DatabaseManager:
        with self.lock:
            if not self.read_databases:
                raise ValueError("No read databases configured")
            
            db = self.read_databases[self.current_read_index]
            self.current_read_index = (self.current_read_index + 1) % len(self.read_databases)
            return db
    
    def get_write_database(self) -> DatabaseManager:
        with self.lock:
            if not self.write_databases:
                raise ValueError("No write databases configured")
            
            db = self.write_databases[self.current_write_index]
            self.current_write_index = (self.current_write_index + 1) % len(self.write_databases)
            return db
    
    def execute_read_query(self, query: str, params: Optional[Tuple] = None) -> QueryResult:
        db = self.get_read_database()
        return db.execute_query(query, params)
    
    def execute_write_query(self, query: str, params: Optional[Tuple] = None) -> QueryResult:
        db = self.get_write_database()
        return db.execute_query(query, params)

class DatabaseMonitor:
    def __init__(self, db_managers: List[DatabaseManager]):
        self.db_managers = db_managers
        self.monitoring = False
        self.monitor_thread = None
        self.alert_thresholds = {
            'connection_usage': 0.8,
            'query_time': 5.0,
            'error_rate': 0.1
        }
    
    def start_monitoring(self, interval: float = 60.0):
        if self.monitoring:
            return
        
        self.monitoring = True
        
        def monitor_worker():
            while self.monitoring:
                for db_manager in self.db_managers:
                    self._check_database_health(db_manager)
                time.sleep(interval)
        
        self.monitor_thread = threading.Thread(target=monitor_worker, daemon=True)
        self.monitor_thread.start()
    
    def stop_monitoring(self):
        self.monitoring = False
        if self.monitor_thread:
            self.monitor_thread.join()
    
    def _check_database_health(self, db_manager: DatabaseManager):
        metrics = db_manager.get_metrics()
        
        connection_usage = metrics.active_connections / metrics.total_connections if metrics.total_connections > 0 else 0
        if connection_usage > self.alert_thresholds['connection_usage']:
            logging.warning(f"High connection usage: {connection_usage:.2%} for {db_manager.name}")
        
        if metrics.average_query_time > self.alert_thresholds['query_time']:
            logging.warning(f"Slow queries detected: {metrics.average_query_time:.2f}s for {db_manager.name}")
        
        total_queries = metrics.successful_queries + metrics.failed_queries
        error_rate = metrics.failed_queries / total_queries if total_queries > 0 else 0
        if error_rate > self.alert_thresholds['error_rate']:
            logging.warning(f"High error rate: {error_rate:.2%} for {db_manager.name}")