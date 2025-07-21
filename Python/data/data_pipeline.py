

from multiprocessing import Pool, cpu_count
import pandas as pd
from typing import List, Tuple, Any
import logging
import random
import time


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DataPipeline:


    def __init__(self, num_workers: int = cpu_count(), batch_size: int = 10000):
        self.num_workers = num_workers
        self.batch_size = batch_size
        logger.debug(f"Pipeline initialized with {num_workers} workers and batch size of {batch_size}")

    @staticmethod
    def _transform_data(batch: pd.DataFrame) -> pd.DataFrame:


        logger.info(f"Processing batch of size {len(batch)}")


        for column in batch.select_dtypes(include=['int', 'float']).columns:
            batch[column] = (batch[column] - batch[column].mean()) / batch[column].std()


        for column in batch.select_dtypes(include=['category']).columns:
            batch[column] = batch[column].cat.codes


        delay = random.uniform(0.1, 0.3)
        time.sleep(delay)

        return batch

    def process_data(self, data: pd.DataFrame) -> pd.DataFrame:


        logger.info("Starting data processing...")


        batched_data = [data[i:i + self.batch_size] for i in range(0, len(data), self.batch_size)]


        with Pool(self.num_workers) as pool:
            processed_batches = pool.map(self._transform_data, batched_data)


        processed_data = pd.concat(processed_batches, ignore_index=True)
        logger.info("Data processing complete.")
        return processed_data

    @staticmethod
    def validate_data(data: pd.DataFrame) -> Tuple[bool, List[str]]:


        logger.info("Starting data validation...")
        errors = []


        critical_columns = ['id', 'value']
        for column in critical_columns:
            if data[column].isnull().any():
                errors.append(f"Column '{column}' contains missing values.")


        if data.duplicated(subset=['id']).any():
            errors.append("Duplicate IDs found.")

        logger.info("Data validation complete.")
        return len(errors) == 0, errors

    def sample_data(self, data: pd.DataFrame, frac: float = 0.1) -> pd.DataFrame:


        logger.info(f"Sampling {frac * 100}% of data...")
        sample = data.sample(frac=frac, random_state=42)
        logger.info("Sampling complete.")
        return sample


def main():


    data_size = 100000
    df = pd.DataFrame({
        'id': range(data_size),
        'value': [random.uniform(0, 100) for _ in range(data_size)],
        'category': pd.Categorical([random.choice(['A', 'B', 'C']) for _ in range(data_size)])
    })

    pipeline = DataPipeline(num_workers=4, batch_size=5000)

    logger.info("Starting data pipeline...")


    is_valid, errors = pipeline.validate_data(df)
    if not is_valid:
        for error in errors:
            logger.error(error)


    processed_data = pipeline.process_data(df)


    sample = pipeline.sample_data(processed_data, 0.01)


    logger.info("Sampled data:")
    logger.info(sample.head())
    logger.info("Data pipeline complete.")


if __name__ == '__main__':
    main()
