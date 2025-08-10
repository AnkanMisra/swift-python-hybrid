import os
import json
import yaml
import toml
import configparser
from typing import Any, Dict, List, Optional, Union, Type, Callable, Set
from pathlib import Path
from dataclasses import dataclass, field
from enum import Enum
import threading
import time
from datetime import datetime, timedelta
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import base64
import hashlib
import re
from abc import ABC, abstractmethod
from collections import defaultdict
from functools import wraps
import weakref
from concurrent.futures import ThreadPoolExecutor
import asyncio
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class ConfigFormat(Enum):
    JSON = "json"
    YAML = "yaml"
    TOML = "toml"
    INI = "ini"
    ENV = "env"
    PYTHON = "py"

class ValidationLevel(Enum):
    NONE = "none"
    BASIC = "basic"
    STRICT = "strict"
    CUSTOM = "custom"

class ConfigSource(Enum):
    FILE = "file"
    ENVIRONMENT = "environment"
    REMOTE = "remote"
    DATABASE = "database"
    MEMORY = "memory"

@dataclass
class ConfigMetadata:
    source: ConfigSource
    format: ConfigFormat
    path: Optional[str] = None
    last_modified: Optional[datetime] = None
    checksum: Optional[str] = None
    encrypted: bool = False
    version: str = "1.0"
    description: str = ""
    tags: Set[str] = field(default_factory=set)

@dataclass
class ValidationRule:
    field_path: str
    validator: Callable[[Any], bool]
    error_message: str
    required: bool = True
    default_value: Any = None

@dataclass
class ConfigSchema:
    rules: List[ValidationRule] = field(default_factory=list)
    allow_extra_fields: bool = True
    strict_types: bool = False

class ConfigError(Exception):
    pass

class ValidationError(ConfigError):
    def __init__(self, field_path: str, message: str):
        self.field_path = field_path
        self.message = message
        super().__init__(f"Validation error at '{field_path}': {message}")

class ConfigNotFoundError(ConfigError):
    pass

class ConfigParseError(ConfigError):
    pass

class ConfigLoader(ABC):
    @abstractmethod
    def load(self, source: str) -> Dict[str, Any]:
        pass
    
    @abstractmethod
    def save(self, data: Dict[str, Any], destination: str) -> None:
        pass
    
    @abstractmethod
    def supports_format(self, format: ConfigFormat) -> bool:
        pass

class JSONLoader(ConfigLoader):
    def load(self, source: str) -> Dict[str, Any]:
        try:
            with open(source, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (json.JSONDecodeError, FileNotFoundError) as e:
            raise ConfigParseError(f"Failed to load JSON config from {source}: {e}")
    
    def save(self, data: Dict[str, Any], destination: str) -> None:
        with open(destination, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    
    def supports_format(self, format: ConfigFormat) -> bool:
        return format == ConfigFormat.JSON

class YAMLLoader(ConfigLoader):
    def load(self, source: str) -> Dict[str, Any]:
        try:
            with open(source, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f) or {}
        except (yaml.YAMLError, FileNotFoundError) as e:
            raise ConfigParseError(f"Failed to load YAML config from {source}: {e}")
    
    def save(self, data: Dict[str, Any], destination: str) -> None:
        with open(destination, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
    
    def supports_format(self, format: ConfigFormat) -> bool:
        return format == ConfigFormat.YAML

class TOMLLoader(ConfigLoader):
    def load(self, source: str) -> Dict[str, Any]:
        try:
            with open(source, 'r', encoding='utf-8') as f:
                return toml.load(f)
        except (toml.TomlDecodeError, FileNotFoundError) as e:
            raise ConfigParseError(f"Failed to load TOML config from {source}: {e}")
    
    def save(self, data: Dict[str, Any], destination: str) -> None:
        with open(destination, 'w', encoding='utf-8') as f:
            toml.dump(data, f)
    
    def supports_format(self, format: ConfigFormat) -> bool:
        return format == ConfigFormat.TOML

class INILoader(ConfigLoader):
    def load(self, source: str) -> Dict[str, Any]:
        try:
            parser = configparser.ConfigParser()
            parser.read(source, encoding='utf-8')
            return {section: dict(parser[section]) for section in parser.sections()}
        except (configparser.Error, FileNotFoundError) as e:
            raise ConfigParseError(f"Failed to load INI config from {source}: {e}")
    
    def save(self, data: Dict[str, Any], destination: str) -> None:
        parser = configparser.ConfigParser()
        for section, values in data.items():
            parser[section] = {k: str(v) for k, v in values.items()}
        
        with open(destination, 'w', encoding='utf-8') as f:
            parser.write(f)
    
    def supports_format(self, format: ConfigFormat) -> bool:
        return format == ConfigFormat.INI

class EnvironmentLoader(ConfigLoader):
    def __init__(self, prefix: str = "", separator: str = "_"):
        self.prefix = prefix
        self.separator = separator
    
    def load(self, source: str = "") -> Dict[str, Any]:
        config = {}
        prefix_len = len(self.prefix)
        
        for key, value in os.environ.items():
            if self.prefix and not key.startswith(self.prefix):
                continue
            
            config_key = key[prefix_len:].lower() if self.prefix else key.lower()
            config_key = config_key.lstrip(self.separator)
            
            if self.separator in config_key:
                self._set_nested_value(config, config_key.split(self.separator), self._parse_value(value))
            else:
                config[config_key] = self._parse_value(value)
        
        return config
    
    def save(self, data: Dict[str, Any], destination: str = "") -> None:
        raise NotImplementedError("Environment variables cannot be saved directly")
    
    def supports_format(self, format: ConfigFormat) -> bool:
        return format == ConfigFormat.ENV
    
    def _set_nested_value(self, config: Dict[str, Any], keys: List[str], value: Any) -> None:
        current = config
        for key in keys[:-1]:
            if key not in current:
                current[key] = {}
            current = current[key]
        current[keys[-1]] = value
    
    def _parse_value(self, value: str) -> Any:
        if value.lower() in ('true', 'false'):
            return value.lower() == 'true'
        
        try:
            if '.' in value:
                return float(value)
            return int(value)
        except ValueError:
            return value

class ConfigEncryption:
    def __init__(self, password: str, salt: Optional[bytes] = None):
        self.salt = salt or os.urandom(16)
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=self.salt,
            iterations=100000,
        )
        key = base64.urlsafe_b64encode(kdf.derive(password.encode()))
        self.cipher = Fernet(key)
    
    def encrypt(self, data: str) -> str:
        encrypted = self.cipher.encrypt(data.encode())
        return base64.urlsafe_b64encode(self.salt + encrypted).decode()
    
    def decrypt(self, encrypted_data: str) -> str:
        try:
            data = base64.urlsafe_b64decode(encrypted_data.encode())
            salt = data[:16]
            encrypted = data[16:]
            
            if salt != self.salt:
                raise ValueError("Invalid salt")
            
            return self.cipher.decrypt(encrypted).decode()
        except Exception as e:
            raise ConfigError(f"Failed to decrypt config data: {e}")

class ConfigValidator:
    def __init__(self, schema: ConfigSchema):
        self.schema = schema
    
    def validate(self, config: Dict[str, Any]) -> Dict[str, Any]:
        validated_config = config.copy()
        errors = []
        
        for rule in self.schema.rules:
            try:
                value = self._get_nested_value(config, rule.field_path)
                
                if value is None:
                    if rule.required:
                        if rule.default_value is not None:
                            self._set_nested_value(validated_config, rule.field_path, rule.default_value)
                        else:
                            errors.append(ValidationError(rule.field_path, "Required field is missing"))
                    continue
                
                if not rule.validator(value):
                    errors.append(ValidationError(rule.field_path, rule.error_message))
                
            except KeyError:
                if rule.required:
                    if rule.default_value is not None:
                        self._set_nested_value(validated_config, rule.field_path, rule.default_value)
                    else:
                        errors.append(ValidationError(rule.field_path, "Required field is missing"))
        
        if errors:
            error_messages = [str(error) for error in errors]
            raise ConfigError(f"Validation failed: {'; '.join(error_messages)}")
        
        return validated_config
    
    def _get_nested_value(self, config: Dict[str, Any], path: str) -> Any:
        keys = path.split('.')
        current = config
        
        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return None
        
        return current
    
    def _set_nested_value(self, config: Dict[str, Any], path: str, value: Any) -> None:
        keys = path.split('.')
        current = config
        
        for key in keys[:-1]:
            if key not in current:
                current[key] = {}
            current = current[key]
        
        current[keys[-1]] = value

class ConfigWatcher(FileSystemEventHandler):
    def __init__(self, config_manager: 'ConfigManager', file_path: str):
        self.config_manager = weakref.ref(config_manager)
        self.file_path = Path(file_path).resolve()
        self.last_modified = 0
        self.debounce_delay = 0.5
    
    def on_modified(self, event):
        if event.is_directory:
            return
        
        file_path = Path(event.src_path).resolve()
        if file_path == self.file_path:
            current_time = time.time()
            if current_time - self.last_modified > self.debounce_delay:
                self.last_modified = current_time
                config_manager = self.config_manager()
                if config_manager:
                    config_manager._reload_config(str(file_path))

class ConfigCache:
    def __init__(self, max_size: int = 1000, ttl: int = 3600):
        self.max_size = max_size
        self.ttl = ttl
        self.cache: Dict[str, tuple] = {}
        self.access_times: Dict[str, float] = {}
        self.lock = threading.RLock()
    
    def get(self, key: str) -> Optional[Any]:
        with self.lock:
            if key in self.cache:
                value, timestamp = self.cache[key]
                if time.time() - timestamp < self.ttl:
                    self.access_times[key] = time.time()
                    return value
                else:
                    del self.cache[key]
                    del self.access_times[key]
            return None
    
    def set(self, key: str, value: Any) -> None:
        with self.lock:
            current_time = time.time()
            
            if len(self.cache) >= self.max_size:
                self._evict_lru()
            
            self.cache[key] = (value, current_time)
            self.access_times[key] = current_time
    
    def invalidate(self, key: str) -> None:
        with self.lock:
            self.cache.pop(key, None)
            self.access_times.pop(key, None)
    
    def clear(self) -> None:
        with self.lock:
            self.cache.clear()
            self.access_times.clear()
    
    def _evict_lru(self) -> None:
        if not self.access_times:
            return
        
        lru_key = min(self.access_times.keys(), key=lambda k: self.access_times[k])
        del self.cache[lru_key]
        del self.access_times[lru_key]

class ConfigProfile:
    def __init__(self, name: str, config: Dict[str, Any], metadata: Optional[ConfigMetadata] = None):
        self.name = name
        self.config = config
        self.metadata = metadata or ConfigMetadata(source=ConfigSource.MEMORY, format=ConfigFormat.JSON)
        self.created_at = datetime.now()
        self.updated_at = self.created_at
    
    def update(self, config: Dict[str, Any]) -> None:
        self.config.update(config)
        self.updated_at = datetime.now()
    
    def merge(self, other_config: Dict[str, Any]) -> None:
        self._deep_merge(self.config, other_config)
        self.updated_at = datetime.now()
    
    def _deep_merge(self, base: Dict[str, Any], update: Dict[str, Any]) -> None:
        for key, value in update.items():
            if key in base and isinstance(base[key], dict) and isinstance(value, dict):
                self._deep_merge(base[key], value)
            else:
                base[key] = value

class ConfigManager:
    _instance = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        if hasattr(self, '_initialized'):
            return
        
        self._initialized = True
        self.profiles: Dict[str, ConfigProfile] = {}
        self.active_profile = "default"
        self.loaders: Dict[ConfigFormat, ConfigLoader] = {
            ConfigFormat.JSON: JSONLoader(),
            ConfigFormat.YAML: YAMLLoader(),
            ConfigFormat.TOML: TOMLLoader(),
            ConfigFormat.INI: INILoader(),
            ConfigFormat.ENV: EnvironmentLoader(),
        }
        self.validators: Dict[str, ConfigValidator] = {}
        self.encryption: Optional[ConfigEncryption] = None
        self.cache = ConfigCache()
        self.watchers: Dict[str, tuple] = {}
        self.observers: List[Observer] = []
        self.change_callbacks: List[Callable] = []
        self.lock = threading.RLock()
        self.executor = ThreadPoolExecutor(max_workers=4)
        
        self._load_default_profile()
    
    def _load_default_profile(self) -> None:
        env_config = self.loaders[ConfigFormat.ENV].load()
        default_profile = ConfigProfile("default", env_config)
        self.profiles["default"] = default_profile
    
    def load_config(
        self,
        source: Union[str, Path],
        profile_name: str = "default",
        format: Optional[ConfigFormat] = None,
        encrypted: bool = False,
        merge: bool = True,
        watch: bool = False
    ) -> None:
        source_path = Path(source)
        
        if not source_path.exists():
            raise ConfigNotFoundError(f"Config file not found: {source}")
        
        if format is None:
            format = self._detect_format(source_path)
        
        loader = self.loaders.get(format)
        if not loader:
            raise ConfigError(f"No loader available for format: {format}")
        
        try:
            config_data = loader.load(str(source_path))
            
            if encrypted and self.encryption:
                config_data = self._decrypt_config(config_data)
            
            metadata = ConfigMetadata(
                source=ConfigSource.FILE,
                format=format,
                path=str(source_path),
                last_modified=datetime.fromtimestamp(source_path.stat().st_mtime),
                checksum=self._calculate_checksum(str(source_path)),
                encrypted=encrypted
            )
            
            with self.lock:
                if profile_name in self.profiles and merge:
                    self.profiles[profile_name].merge(config_data)
                    self.profiles[profile_name].metadata = metadata
                else:
                    self.profiles[profile_name] = ConfigProfile(profile_name, config_data, metadata)
                
                if profile_name in self.validators:
                    validator = self.validators[profile_name]
                    self.profiles[profile_name].config = validator.validate(self.profiles[profile_name].config)
            
            if watch:
                self._setup_file_watcher(str(source_path))
            
            self._notify_change_callbacks(profile_name, config_data)
            
        except Exception as e:
            raise ConfigError(f"Failed to load config from {source}: {e}")
    
    def save_config(
        self,
        destination: Union[str, Path],
        profile_name: str = None,
        format: Optional[ConfigFormat] = None,
        encrypted: bool = False
    ) -> None:
        if profile_name is None:
            profile_name = self.active_profile
        
        if profile_name not in self.profiles:
            raise ConfigError(f"Profile '{profile_name}' not found")
        
        destination_path = Path(destination)
        
        if format is None:
            format = self._detect_format(destination_path)
        
        loader = self.loaders.get(format)
        if not loader:
            raise ConfigError(f"No loader available for format: {format}")
        
        config_data = self.profiles[profile_name].config.copy()
        
        if encrypted and self.encryption:
            config_data = self._encrypt_config(config_data)
        
        try:
            destination_path.parent.mkdir(parents=True, exist_ok=True)
            loader.save(config_data, str(destination_path))
        except Exception as e:
            raise ConfigError(f"Failed to save config to {destination}: {e}")
    
    def get(self, key: str, default: Any = None, profile_name: str = None) -> Any:
        if profile_name is None:
            profile_name = self.active_profile
        
        cache_key = f"{profile_name}.{key}"
        cached_value = self.cache.get(cache_key)
        if cached_value is not None:
            return cached_value
        
        with self.lock:
            if profile_name not in self.profiles:
                return default
            
            value = self._get_nested_value(self.profiles[profile_name].config, key, default)
            self.cache.set(cache_key, value)
            return value
    
    def set(self, key: str, value: Any, profile_name: str = None) -> None:
        if profile_name is None:
            profile_name = self.active_profile
        
        with self.lock:
            if profile_name not in self.profiles:
                self.profiles[profile_name] = ConfigProfile(profile_name, {})
            
            self._set_nested_value(self.profiles[profile_name].config, key, value)
            self.profiles[profile_name].updated_at = datetime.now()
            
            cache_key = f"{profile_name}.{key}"
            self.cache.invalidate(cache_key)
            
            self._notify_change_callbacks(profile_name, {key: value})
    
    def delete(self, key: str, profile_name: str = None) -> bool:
        if profile_name is None:
            profile_name = self.active_profile
        
        with self.lock:
            if profile_name not in self.profiles:
                return False
            
            success = self._delete_nested_value(self.profiles[profile_name].config, key)
            if success:
                self.profiles[profile_name].updated_at = datetime.now()
                cache_key = f"{profile_name}.{key}"
                self.cache.invalidate(cache_key)
                self._notify_change_callbacks(profile_name, {key: None})
            
            return success
    
    def has(self, key: str, profile_name: str = None) -> bool:
        if profile_name is None:
            profile_name = self.active_profile
        
        with self.lock:
            if profile_name not in self.profiles:
                return False
            
            return self._get_nested_value(self.profiles[profile_name].config, key) is not None
    
    def get_profile(self, profile_name: str) -> Optional[ConfigProfile]:
        return self.profiles.get(profile_name)
    
    def list_profiles(self) -> List[str]:
        return list(self.profiles.keys())
    
    def switch_profile(self, profile_name: str) -> None:
        if profile_name not in self.profiles:
            raise ConfigError(f"Profile '{profile_name}' not found")
        
        with self.lock:
            old_profile = self.active_profile
            self.active_profile = profile_name
            self.cache.clear()
            
            self._notify_change_callbacks(profile_name, self.profiles[profile_name].config)
    
    def create_profile(self, profile_name: str, config: Dict[str, Any] = None) -> None:
        if config is None:
            config = {}
        
        with self.lock:
            if profile_name in self.profiles:
                raise ConfigError(f"Profile '{profile_name}' already exists")
            
            self.profiles[profile_name] = ConfigProfile(profile_name, config)
    
    def delete_profile(self, profile_name: str) -> None:
        if profile_name == "default":
            raise ConfigError("Cannot delete default profile")
        
        with self.lock:
            if profile_name not in self.profiles:
                raise ConfigError(f"Profile '{profile_name}' not found")
            
            del self.profiles[profile_name]
            
            if self.active_profile == profile_name:
                self.active_profile = "default"
                self.cache.clear()
    
    def set_validator(self, profile_name: str, schema: ConfigSchema) -> None:
        self.validators[profile_name] = ConfigValidator(schema)
        
        if profile_name in self.profiles:
            with self.lock:
                self.profiles[profile_name].config = self.validators[profile_name].validate(
                    self.profiles[profile_name].config
                )
    
    def set_encryption(self, password: str, salt: Optional[bytes] = None) -> None:
        self.encryption = ConfigEncryption(password, salt)
    
    def add_change_callback(self, callback: Callable[[str, Dict[str, Any]], None]) -> None:
        self.change_callbacks.append(callback)
    
    def remove_change_callback(self, callback: Callable[[str, Dict[str, Any]], None]) -> None:
        if callback in self.change_callbacks:
            self.change_callbacks.remove(callback)
    
    def reload_config(self, profile_name: str = None) -> None:
        if profile_name is None:
            profile_name = self.active_profile
        
        if profile_name not in self.profiles:
            return
        
        profile = self.profiles[profile_name]
        if profile.metadata.path:
            self.load_config(
                profile.metadata.path,
                profile_name,
                profile.metadata.format,
                profile.metadata.encrypted,
                merge=False
            )
    
    def _reload_config(self, file_path: str) -> None:
        for profile_name, profile in self.profiles.items():
            if profile.metadata.path == file_path:
                try:
                    self.reload_config(profile_name)
                except Exception as e:
                    print(f"Failed to reload config for profile '{profile_name}': {e}")
    
    def _detect_format(self, file_path: Path) -> ConfigFormat:
        suffix = file_path.suffix.lower()
        format_map = {
            '.json': ConfigFormat.JSON,
            '.yaml': ConfigFormat.YAML,
            '.yml': ConfigFormat.YAML,
            '.toml': ConfigFormat.TOML,
            '.ini': ConfigFormat.INI,
            '.cfg': ConfigFormat.INI,
            '.conf': ConfigFormat.INI,
            '.py': ConfigFormat.PYTHON,
        }
        return format_map.get(suffix, ConfigFormat.JSON)
    
    def _calculate_checksum(self, file_path: str) -> str:
        with open(file_path, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()
    
    def _encrypt_config(self, config: Dict[str, Any]) -> Dict[str, Any]:
        if not self.encryption:
            return config
        
        encrypted_config = {}
        for key, value in config.items():
            if isinstance(value, dict):
                encrypted_config[key] = self._encrypt_config(value)
            else:
                encrypted_config[key] = self.encryption.encrypt(str(value))
        
        return encrypted_config
    
    def _decrypt_config(self, config: Dict[str, Any]) -> Dict[str, Any]:
        if not self.encryption:
            return config
        
        decrypted_config = {}
        for key, value in config.items():
            if isinstance(value, dict):
                decrypted_config[key] = self._decrypt_config(value)
            else:
                try:
                    decrypted_config[key] = self.encryption.decrypt(str(value))
                except:
                    decrypted_config[key] = value
        
        return decrypted_config
    
    def _get_nested_value(self, config: Dict[str, Any], key: str, default: Any = None) -> Any:
        keys = key.split('.')
        current = config
        
        for k in keys:
            if isinstance(current, dict) and k in current:
                current = current[k]
            else:
                return default
        
        return current
    
    def _set_nested_value(self, config: Dict[str, Any], key: str, value: Any) -> None:
        keys = key.split('.')
        current = config
        
        for k in keys[:-1]:
            if k not in current:
                current[k] = {}
            current = current[k]
        
        current[keys[-1]] = value
    
    def _delete_nested_value(self, config: Dict[str, Any], key: str) -> bool:
        keys = key.split('.')
        current = config
        
        for k in keys[:-1]:
            if isinstance(current, dict) and k in current:
                current = current[k]
            else:
                return False
        
        if isinstance(current, dict) and keys[-1] in current:
            del current[keys[-1]]
            return True
        
        return False
    
    def _setup_file_watcher(self, file_path: str) -> None:
        if file_path in self.watchers:
            return
        
        observer = Observer()
        event_handler = ConfigWatcher(self, file_path)
        watch_dir = str(Path(file_path).parent)
        
        observer.schedule(event_handler, watch_dir, recursive=False)
        observer.start()
        
        self.watchers[file_path] = (observer, event_handler)
        self.observers.append(observer)
    
    def _notify_change_callbacks(self, profile_name: str, changes: Dict[str, Any]) -> None:
        for callback in self.change_callbacks:
            try:
                callback(profile_name, changes)
            except Exception as e:
                print(f"Error in change callback: {e}")
    
    def shutdown(self) -> None:
        for observer in self.observers:
            observer.stop()
            observer.join()
        
        self.executor.shutdown(wait=True)
        self.cache.clear()

def config_property(key: str, default: Any = None, profile_name: str = None):
    def decorator(cls):
        def getter(self):
            return ConfigManager().get(key, default, profile_name)
        
        def setter(self, value):
            ConfigManager().set(key, value, profile_name)
        
        setattr(cls, key.replace('.', '_'), property(getter, setter))
        return cls
    
    return decorator

def config_required(*keys):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            config_manager = ConfigManager()
            missing_keys = []
            
            for key in keys:
                if not config_manager.has(key):
                    missing_keys.append(key)
            
            if missing_keys:
                raise ConfigError(f"Required configuration keys missing: {missing_keys}")
            
            return func(*args, **kwargs)
        
        return wrapper
    return decorator

class ConfigBuilder:
    def __init__(self):
        self.config = {}
        self.profile_name = "default"
        self.format = ConfigFormat.JSON
        self.encrypted = False
        self.watch = False
        self.merge = True
    
    def from_file(self, file_path: Union[str, Path]) -> 'ConfigBuilder':
        self.file_path = file_path
        return self
    
    def with_profile(self, profile_name: str) -> 'ConfigBuilder':
        self.profile_name = profile_name
        return self
    
    def with_format(self, format: ConfigFormat) -> 'ConfigBuilder':
        self.format = format
        return self
    
    def with_encryption(self, encrypted: bool = True) -> 'ConfigBuilder':
        self.encrypted = encrypted
        return self
    
    def with_watching(self, watch: bool = True) -> 'ConfigBuilder':
        self.watch = watch
        return self
    
    def with_merge(self, merge: bool = True) -> 'ConfigBuilder':
        self.merge = merge
        return self
    
    def with_data(self, data: Dict[str, Any]) -> 'ConfigBuilder':
        self.config.update(data)
        return self
    
    def build(self) -> ConfigManager:
        config_manager = ConfigManager()
        
        if hasattr(self, 'file_path'):
            config_manager.load_config(
                self.file_path,
                self.profile_name,
                self.format,
                self.encrypted,
                self.merge,
                self.watch
            )
        
        if self.config:
            if self.profile_name in config_manager.profiles and self.merge:
                config_manager.profiles[self.profile_name].merge(self.config)
            else:
                config_manager.create_profile(self.profile_name, self.config)
        
        return config_manager

class ConfigMonitor:
    def __init__(self, config_manager: ConfigManager):
        self.config_manager = config_manager
        self.metrics = defaultdict(int)
        self.start_time = datetime.now()
        self.last_access_times = {}
        
        config_manager.add_change_callback(self._on_config_change)
    
    def _on_config_change(self, profile_name: str, changes: Dict[str, Any]) -> None:
        self.metrics['config_changes'] += 1
        self.metrics[f'profile_{profile_name}_changes'] += 1
        self.last_access_times[profile_name] = datetime.now()
    
    def get_metrics(self) -> Dict[str, Any]:
        uptime = datetime.now() - self.start_time
        
        return {
            'uptime_seconds': uptime.total_seconds(),
            'total_profiles': len(self.config_manager.profiles),
            'active_profile': self.config_manager.active_profile,
            'cache_size': len(self.config_manager.cache.cache),
            'watchers_count': len(self.config_manager.watchers),
            'metrics': dict(self.metrics),
            'last_access_times': {k: v.isoformat() for k, v in self.last_access_times.items()}
        }

config_manager = ConfigManager()