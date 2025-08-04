import asyncio
import logging
import time
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
from dataclasses import dataclass, field
from enum import Enum
from typing import (
    Any, Awaitable, Callable, Dict, List, Optional, Set, Union,
    TypeVar, Generic, Coroutine, Tuple
)
from uuid import UUID, uuid4
from functools import wraps
import weakref
from contextlib import asynccontextmanager

T = TypeVar('T')
R = TypeVar('R')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TaskPriority(Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4

class TaskStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

class GroupFailurePolicy(Enum):
    CONTINUE_ON_FAILURE = "continue"
    FAIL_FAST = "fail_fast"

@dataclass
class TaskResult(Generic[T]):
    task_id: UUID
    status: TaskStatus
    result: Optional[T] = None
    error: Optional[Exception] = None
    start_time: Optional[float] = None
    end_time: Optional[float] = None
    execution_time: Optional[float] = None

    def __post_init__(self):
        if self.start_time and self.end_time:
            self.execution_time = self.end_time - self.start_time

@dataclass
class QueuedTask:
    task_id: UUID
    coro: Coroutine
    priority: TaskPriority
    created_at: float = field(default_factory=time.time)
    timeout: Optional[float] = None
    retry_count: int = 0
    max_retries: int = 0
    retry_delay: float = 1.0
    callback: Optional[Callable] = None

class AsyncTaskManager:
    def __init__(
        self,
        max_concurrent_tasks: int = 100,
        max_queue_size: int = 1000,
        default_timeout: float = 300.0,
        thread_pool_size: int = 10,
        process_pool_size: int = 4
    ):
        self.max_concurrent_tasks = max_concurrent_tasks
        self.max_queue_size = max_queue_size
        self.default_timeout = default_timeout
        
        self._running_tasks: Dict[UUID, asyncio.Task] = {}
        self._task_queue: List[QueuedTask] = []
        self._task_results: Dict[UUID, TaskResult] = {}
        self._task_history: List[TaskResult] = []
        self._semaphore = asyncio.Semaphore(max_concurrent_tasks)
        self._queue_lock = asyncio.Lock()
        self._shutdown_event = asyncio.Event()
        self._worker_task: Optional[asyncio.Task] = None
        
        self._thread_executor = ThreadPoolExecutor(max_workers=thread_pool_size)
        self._process_executor = ProcessPoolExecutor(max_workers=process_pool_size)
        
        self._callbacks: Dict[str, List[Callable]] = {
            'task_started': [],
            'task_completed': [],
            'task_failed': [],
            'task_cancelled': []
        }
        
        self._metrics = {
            'total_tasks': 0,
            'completed_tasks': 0,
            'failed_tasks': 0,
            'cancelled_tasks': 0,
            'average_execution_time': 0.0
        }

    async def start(self):
        if self._worker_task is None or self._worker_task.done():
            self._worker_task = asyncio.create_task(self._queue_worker())
            logger.info("AsyncTaskManager started")

    async def stop(self):
        self._shutdown_event.set()
        
        if self._worker_task:
            await self._worker_task
        
        for task in self._running_tasks.values():
            task.cancel()
        
        if self._running_tasks:
            await asyncio.gather(*self._running_tasks.values(), return_exceptions=True)
        
        self._thread_executor.shutdown(wait=True)
        self._process_executor.shutdown(wait=True)
        
        logger.info("AsyncTaskManager stopped")

    async def submit_task(
        self,
        coro: Coroutine[Any, Any, T],
        priority: TaskPriority = TaskPriority.MEDIUM,
        timeout: Optional[float] = None,
        max_retries: int = 0,
        retry_delay: float = 1.0,
        callback: Optional[Callable[[TaskResult], None]] = None
    ) -> UUID:
        task_id = uuid4()
        
        if len(self._task_queue) >= self.max_queue_size:
            raise RuntimeError("Task queue is full")
        
        queued_task = QueuedTask(
            task_id=task_id,
            coro=coro,
            priority=priority,
            timeout=timeout or self.default_timeout,
            max_retries=max_retries,
            retry_delay=retry_delay,
            callback=callback
        )
        
        async with self._queue_lock:
            self._task_queue.append(queued_task)
            self._task_queue.sort(key=lambda x: x.priority.value, reverse=True)
        
        self._metrics['total_tasks'] += 1
        logger.debug(f"Task {task_id} queued with priority {priority.name}")
        
        return task_id

    async def execute_task(
        self,
        coro: Coroutine[Any, Any, T],
        priority: TaskPriority = TaskPriority.MEDIUM,
        timeout: Optional[float] = None
    ) -> T:
        task_id = await self.submit_task(coro, priority, timeout)
        result = await self.wait_for_task(task_id)
        
        if result.status == TaskStatus.FAILED and result.error:
            raise result.error
        
        return result.result

    async def wait_for_task(self, task_id: UUID, timeout: Optional[float] = None) -> TaskResult:
        start_time = time.time()
        
        while True:
            if task_id in self._task_results:
                return self._task_results[task_id]
            
            if timeout and (time.time() - start_time) > timeout:
                raise asyncio.TimeoutError(f"Waiting for task {task_id} timed out")
            
            await asyncio.sleep(0.1)

    async def cancel_task(self, task_id: UUID) -> bool:
        if task_id in self._running_tasks:
            self._running_tasks[task_id].cancel()
            return True
        
        async with self._queue_lock:
            for i, queued_task in enumerate(self._task_queue):
                if queued_task.task_id == task_id:
                    del self._task_queue[i]
                    result = TaskResult(
                        task_id=task_id,
                        status=TaskStatus.CANCELLED
                    )
                    self._task_results[task_id] = result
                    self._metrics['cancelled_tasks'] += 1
                    await self._notify_callbacks('task_cancelled', result)
                    return True
        
        return False

    async def cancel_all_tasks(self):
        for task_id in list(self._running_tasks.keys()):
            await self.cancel_task(task_id)
        
        async with self._queue_lock:
            for queued_task in self._task_queue:
                result = TaskResult(
                    task_id=queued_task.task_id,
                    status=TaskStatus.CANCELLED
                )
                self._task_results[queued_task.task_id] = result
                self._metrics['cancelled_tasks'] += 1
                await self._notify_callbacks('task_cancelled', result)
            
            self._task_queue.clear()

    async def execute_task_group(
        self,
        tasks: List[Tuple[Coroutine, TaskPriority]],
        failure_policy: GroupFailurePolicy = GroupFailurePolicy.CONTINUE_ON_FAILURE,
        timeout: Optional[float] = None
    ) -> List[TaskResult]:
        task_ids = []
        
        for coro, priority in tasks:
            task_id = await self.submit_task(coro, priority, timeout)
            task_ids.append(task_id)
        
        results = []
        
        for task_id in task_ids:
            try:
                result = await self.wait_for_task(task_id, timeout)
                results.append(result)
                
                if (failure_policy == GroupFailurePolicy.FAIL_FAST and 
                    result.status == TaskStatus.FAILED):
                    for remaining_id in task_ids[len(results):]:
                        await self.cancel_task(remaining_id)
                    break
                    
            except Exception as e:
                error_result = TaskResult(
                    task_id=task_id,
                    status=TaskStatus.FAILED,
                    error=e
                )
                results.append(error_result)
                
                if failure_policy == GroupFailurePolicy.FAIL_FAST:
                    break
        
        return results

    async def execute_with_retry(
        self,
        coro_factory: Callable[[], Coroutine[Any, Any, T]],
        max_retries: int = 3,
        retry_delay: float = 1.0,
        backoff_multiplier: float = 2.0,
        timeout: Optional[float] = None
    ) -> T:
        last_exception = None
        current_delay = retry_delay
        
        for attempt in range(max_retries + 1):
            try:
                coro = coro_factory()
                return await self.execute_task(coro, timeout=timeout)
            except Exception as e:
                last_exception = e
                
                if attempt < max_retries:
                    logger.warning(
                        f"Task failed on attempt {attempt + 1}, retrying in {current_delay}s: {e}"
                    )
                    await asyncio.sleep(current_delay)
                    current_delay *= backoff_multiplier
                else:
                    logger.error(f"Task failed after {max_retries + 1} attempts: {e}")
        
        raise last_exception

    async def execute_batch(
        self,
        items: List[Any],
        processor: Callable[[Any], Coroutine[Any, Any, R]],
        batch_size: int = 10,
        priority: TaskPriority = TaskPriority.MEDIUM
    ) -> List[TaskResult[R]]:
        results = []
        
        for i in range(0, len(items), batch_size):
            batch = items[i:i + batch_size]
            batch_tasks = [(processor(item), priority) for item in batch]
            batch_results = await self.execute_task_group(batch_tasks)
            results.extend(batch_results)
        
        return results

    async def run_in_thread(
        self,
        func: Callable[..., T],
        *args,
        **kwargs
    ) -> T:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(self._thread_executor, func, *args, **kwargs)

    async def run_in_process(
        self,
        func: Callable[..., T],
        *args,
        **kwargs
    ) -> T:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(self._process_executor, func, *args, **kwargs)

    def add_callback(self, event: str, callback: Callable[[TaskResult], None]):
        if event in self._callbacks:
            self._callbacks[event].append(callback)
        else:
            raise ValueError(f"Unknown event type: {event}")

    def remove_callback(self, event: str, callback: Callable[[TaskResult], None]):
        if event in self._callbacks and callback in self._callbacks[event]:
            self._callbacks[event].remove(callback)

    def get_task_status(self, task_id: UUID) -> Optional[TaskStatus]:
        if task_id in self._running_tasks:
            return TaskStatus.RUNNING
        elif task_id in self._task_results:
            return self._task_results[task_id].status
        else:
            for queued_task in self._task_queue:
                if queued_task.task_id == task_id:
                    return TaskStatus.PENDING
        return None

    def get_metrics(self) -> Dict[str, Any]:
        return {
            **self._metrics,
            'running_tasks': len(self._running_tasks),
            'queued_tasks': len(self._task_queue),
            'completed_results': len([r for r in self._task_results.values() 
                                    if r.status == TaskStatus.COMPLETED])
        }

    async def _queue_worker(self):
        while not self._shutdown_event.is_set():
            try:
                await self._process_queue()
                await asyncio.sleep(0.01)
            except Exception as e:
                logger.error(f"Queue worker error: {e}")
                await asyncio.sleep(1.0)

    async def _process_queue(self):
        if len(self._running_tasks) >= self.max_concurrent_tasks:
            return
        
        async with self._queue_lock:
            if not self._task_queue:
                return
            
            queued_task = self._task_queue.pop(0)
        
        await self._semaphore.acquire()
        task = asyncio.create_task(self._execute_queued_task(queued_task))
        self._running_tasks[queued_task.task_id] = task

    async def _execute_queued_task(self, queued_task: QueuedTask):
        start_time = time.time()
        result = TaskResult(
            task_id=queued_task.task_id,
            status=TaskStatus.RUNNING,
            start_time=start_time
        )
        
        await self._notify_callbacks('task_started', result)
        
        try:
            if queued_task.timeout:
                task_result = await asyncio.wait_for(
                    queued_task.coro,
                    timeout=queued_task.timeout
                )
            else:
                task_result = await queued_task.coro
            
            end_time = time.time()
            result.status = TaskStatus.COMPLETED
            result.result = task_result
            result.end_time = end_time
            result.execution_time = end_time - start_time
            
            self._metrics['completed_tasks'] += 1
            self._update_average_execution_time(result.execution_time)
            
            await self._notify_callbacks('task_completed', result)
            
        except asyncio.CancelledError:
            result.status = TaskStatus.CANCELLED
            self._metrics['cancelled_tasks'] += 1
            await self._notify_callbacks('task_cancelled', result)
            
        except Exception as e:
            end_time = time.time()
            result.status = TaskStatus.FAILED
            result.error = e
            result.end_time = end_time
            result.execution_time = end_time - start_time
            
            if queued_task.retry_count < queued_task.max_retries:
                queued_task.retry_count += 1
                await asyncio.sleep(queued_task.retry_delay)
                
                async with self._queue_lock:
                    self._task_queue.insert(0, queued_task)
                
                logger.info(
                    f"Retrying task {queued_task.task_id} "
                    f"(attempt {queued_task.retry_count}/{queued_task.max_retries})"
                )
            else:
                self._metrics['failed_tasks'] += 1
                await self._notify_callbacks('task_failed', result)
        
        finally:
            self._task_results[queued_task.task_id] = result
            self._task_history.append(result)
            
            if queued_task.callback:
                try:
                    await queued_task.callback(result)
                except Exception as e:
                    logger.error(f"Callback error for task {queued_task.task_id}: {e}")
            
            self._running_tasks.pop(queued_task.task_id, None)
            self._semaphore.release()

    async def _notify_callbacks(self, event: str, result: TaskResult):
        for callback in self._callbacks.get(event, []):
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(result)
                else:
                    callback(result)
            except Exception as e:
                logger.error(f"Callback error for event {event}: {e}")

    def _update_average_execution_time(self, execution_time: float):
        completed = self._metrics['completed_tasks']
        current_avg = self._metrics['average_execution_time']
        self._metrics['average_execution_time'] = (
            (current_avg * (completed - 1) + execution_time) / completed
        )

    @asynccontextmanager
    async def managed_lifecycle(self):
        await self.start()
        try:
            yield self
        finally:
            await self.stop()

def task_timeout(timeout: float):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            return await asyncio.wait_for(func(*args, **kwargs), timeout=timeout)
        return wrapper
    return decorator

def retry_on_failure(max_retries: int = 3, delay: float = 1.0, backoff: float = 2.0):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            last_exception = None
            current_delay = delay
            
            for attempt in range(max_retries + 1):
                try:
                    return await func(*args, **kwargs)
                except Exception as e:
                    last_exception = e
                    if attempt < max_retries:
                        await asyncio.sleep(current_delay)
                        current_delay *= backoff
            
            raise last_exception
        return wrapper
    return decorator

class TaskManagerSingleton:
    _instance: Optional[AsyncTaskManager] = None
    _lock = asyncio.Lock()
    
    @classmethod
    async def get_instance(cls, **kwargs) -> AsyncTaskManager:
        if cls._instance is None:
            async with cls._lock:
                if cls._instance is None:
                    cls._instance = AsyncTaskManager(**kwargs)
                    await cls._instance.start()
        return cls._instance
    
    @classmethod
    async def shutdown(cls):
        if cls._instance:
            await cls._instance.stop()
            cls._instance = None

async def example_usage():
    async with AsyncTaskManager().managed_lifecycle() as manager:
        async def sample_task(duration: float, should_fail: bool = False) -> str:
            await asyncio.sleep(duration)
            if should_fail:
                raise ValueError("Task failed intentionally")
            return f"Task completed after {duration}s"
        
        task_id1 = await manager.submit_task(
            sample_task(1.0),
            priority=TaskPriority.HIGH
        )
        
        task_id2 = await manager.submit_task(
            sample_task(2.0),
            priority=TaskPriority.LOW,
            max_retries=2
        )
        
        result1 = await manager.wait_for_task(task_id1)
        result2 = await manager.wait_for_task(task_id2)
        
        print(f"Task 1 result: {result1.result}")
        print(f"Task 2 result: {result2.result}")
        print(f"Metrics: {manager.get_metrics()}")

if __name__ == "__main__":
    asyncio.run(example_usage())