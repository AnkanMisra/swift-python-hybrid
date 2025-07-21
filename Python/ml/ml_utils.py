

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split, cross_val_score, GridSearchCV
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.linear_model import LogisticRegression, LinearRegression
from sklearn.svm import SVC, SVR
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    mean_squared_error, mean_absolute_error, r2_score,
    classification_report, confusion_matrix
)
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.pipeline import Pipeline
import joblib
import matplotlib.pyplot as plt
import seaborn as sns
from typing import Dict, List, Tuple, Any, Optional
import logging
from dataclasses import dataclass
import warnings


warnings.filterwarnings('ignore')


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class ModelResult:

    model_name: str
    accuracy: float
    precision: float
    recall: float
    f1_score: float
    cv_scores: List[float]
    best_params: Optional[Dict] = None

class MLPipeline:

    
    def __init__(self):
        self.models = {}
        self.results = {}
        self.scaler = StandardScaler()
        self.label_encoder = LabelEncoder()
        
    def prepare_data(self, df: pd.DataFrame, target_column: str, 
                    test_size: float = 0.2, random_state: int = 42) -> Tuple:

        logger.info("Preparing data for machine learning...")
        

        X = df.drop(columns=[target_column])
        y = df[target_column]
        

        categorical_columns = X.select_dtypes(include=['object', 'category']).columns
        for col in categorical_columns:
            X[col] = LabelEncoder().fit_transform(X[col].astype(str))
        

        X = X.fillna(X.mean())
        

        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=random_state, stratify=y
        )
        

        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)
        
        logger.info(f"Data prepared: {X_train.shape[0]} training samples, {X_test.shape[0]} test samples")
        
        return X_train_scaled, X_test_scaled, y_train, y_test
    
    def train_models(self, X_train: np.ndarray, y_train: np.ndarray, 
                    problem_type: str = 'classification') -> Dict:

        logger.info(f"Training models for {problem_type}...")
        
        if problem_type == 'classification':
            models = {
                'Random Forest': RandomForestClassifier(n_estimators=100, random_state=42),
                'Logistic Regression': LogisticRegression(random_state=42, max_iter=1000),
                'SVM': SVC(random_state=42, probability=True)
            }
        else:
            models = {
                'Random Forest': RandomForestRegressor(n_estimators=100, random_state=42),
                'Linear Regression': LinearRegression(),
                'SVR': SVR()
            }
        
        trained_models = {}
        for name, model in models.items():
            logger.info(f"Training {name}...")
            model.fit(X_train, y_train)
            trained_models[name] = model
            
        self.models = trained_models
        return trained_models
    
    def evaluate_classification_models(self, X_test: np.ndarray, y_test: np.ndarray, 
                                     X_train: np.ndarray, y_train: np.ndarray) -> List[ModelResult]:

        logger.info("Evaluating classification models...")
        
        results = []
        for name, model in self.models.items():

            y_pred = model.predict(X_test)
            y_pred_proba = model.predict_proba(X_test)[:, 1] if hasattr(model, 'predict_proba') else None
            

            accuracy = accuracy_score(y_test, y_pred)
            precision = precision_score(y_test, y_pred, average='weighted')
            recall = recall_score(y_test, y_pred, average='weighted')
            f1 = f1_score(y_test, y_pred, average='weighted')
            

            cv_scores = cross_val_score(model, X_train, y_train, cv=5, scoring='accuracy')
            
            result = ModelResult(
                model_name=name,
                accuracy=accuracy,
                precision=precision,
                recall=recall,
                f1_score=f1,
                cv_scores=cv_scores.tolist()
            )
            results.append(result)
            
            logger.info(f"{name} - Accuracy: {accuracy:.4f}, F1: {f1:.4f}")
        
        self.results = results
        return results
    
    def evaluate_regression_models(self, X_test: np.ndarray, y_test: np.ndarray) -> Dict[str, Dict]:

        logger.info("Evaluating regression models...")
        
        results = {}
        for name, model in self.models.items():
            y_pred = model.predict(X_test)
            
            mse = mean_squared_error(y_test, y_pred)
            mae = mean_absolute_error(y_test, y_pred)
            r2 = r2_score(y_test, y_pred)
            rmse = np.sqrt(mse)
            
            results[name] = {
                'MSE': mse,
                'MAE': mae,
                'RMSE': rmse,
                'R2': r2
            }
            
            logger.info(f"{name} - RMSE: {rmse:.4f}, R2: {r2:.4f}")
        
        return results
    
    def hyperparameter_tuning(self, model_name: str, X_train: np.ndarray, 
                            y_train: np.ndarray, param_grid: Dict) -> Dict:

        logger.info(f"Performing hyperparameter tuning for {model_name}...")
        
        model = self.models[model_name]
        grid_search = GridSearchCV(
            model, param_grid, cv=5, scoring='accuracy', n_jobs=-1, verbose=1
        )
        
        grid_search.fit(X_train, y_train)
        
        logger.info(f"Best parameters for {model_name}: {grid_search.best_params_}")
        logger.info(f"Best cross-validation score: {grid_search.best_score_:.4f}")
        

        self.models[model_name] = grid_search.best_estimator_
        
        return grid_search.best_params_
    
    def save_model(self, model_name: str, filepath: str):

        if model_name in self.models:
            joblib.dump(self.models[model_name], filepath)
            logger.info(f"Model {model_name} saved to {filepath}")
        else:
            logger.error(f"Model {model_name} not found")
    
    def load_model(self, filepath: str, model_name: str):

        try:
            model = joblib.load(filepath)
            self.models[model_name] = model
            logger.info(f"Model loaded from {filepath} as {model_name}")
        except Exception as e:
            logger.error(f"Error loading model: {e}")
    
    def plot_model_comparison(self, results: List[ModelResult], save_path: Optional[str] = None):

        model_names = [result.model_name for result in results]
        accuracies = [result.accuracy for result in results]
        f1_scores = [result.f1_score for result in results]
        
        x = np.arange(len(model_names))
        width = 0.35
        
        fig, ax = plt.subplots(figsize=(10, 6))
        bars1 = ax.bar(x - width/2, accuracies, width, label='Accuracy', alpha=0.8)
        bars2 = ax.bar(x + width/2, f1_scores, width, label='F1 Score', alpha=0.8)
        
        ax.set_xlabel('Models')
        ax.set_ylabel('Score')
        ax.set_title('Model Performance Comparison')
        ax.set_xticks(x)
        ax.set_xticklabels(model_names)
        ax.legend()
        ax.set_ylim(0, 1)
        

        for bar in bars1 + bars2:
            height = bar.get_height()
            ax.annotate(f'{height:.3f}',
                       xy=(bar.get_x() + bar.get_width() / 2, height),
                       xytext=(0, 3),
                       textcoords="offset points",
                       ha='center', va='bottom')
        
        plt.tight_layout()
        
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            logger.info(f"Plot saved to {save_path}")
        
        plt.show()

class FeatureEngineering:

    
    @staticmethod
    def create_polynomial_features(X: pd.DataFrame, degree: int = 2) -> pd.DataFrame:

        from sklearn.preprocessing import PolynomialFeatures
        
        poly = PolynomialFeatures(degree=degree, include_bias=False)
        X_poly = poly.fit_transform(X)
        
        feature_names = poly.get_feature_names_out(X.columns)
        return pd.DataFrame(X_poly, columns=feature_names)
    
    @staticmethod
    def feature_selection(X: pd.DataFrame, y: pd.Series, k: int = 10) -> pd.DataFrame:

        from sklearn.feature_selection import SelectKBest, f_classif
        
        selector = SelectKBest(score_func=f_classif, k=k)
        X_selected = selector.fit_transform(X, y)
        
        selected_features = X.columns[selector.get_support()]
        return pd.DataFrame(X_selected, columns=selected_features)
    
    @staticmethod
    def detect_outliers(df: pd.DataFrame, method: str = 'iqr') -> pd.DataFrame:

        outliers = pd.DataFrame()
        
        if method == 'iqr':
            for column in df.select_dtypes(include=[np.number]).columns:
                Q1 = df[column].quantile(0.25)
                Q3 = df[column].quantile(0.75)
                IQR = Q3 - Q1
                lower_bound = Q1 - 1.5 * IQR
                upper_bound = Q3 + 1.5 * IQR
                outliers[column] = (df[column] < lower_bound) | (df[column] > upper_bound)
        
        elif method == 'zscore':
            from scipy import stats
            for column in df.select_dtypes(include=[np.number]).columns:
                z_scores = np.abs(stats.zscore(df[column]))
                outliers[column] = z_scores > 3
        
        return outliers

def generate_sample_data(n_samples: int = 1000) -> pd.DataFrame:

    from sklearn.datasets import make_classification
    
    X, y = make_classification(
        n_samples=n_samples,
        n_features=10,
        n_informative=5,
        n_redundant=2,
        n_clusters_per_class=1,
        random_state=42
    )
    

    feature_names = [f'feature_{i}' for i in range(X.shape[1])]
    df = pd.DataFrame(X, columns=feature_names)
    df['target'] = y
    
    return df

def main():


    df = generate_sample_data(1000)
    logger.info(f"Generated dataset with shape: {df.shape}")
    

    pipeline = MLPipeline()
    

    X_train, X_test, y_train, y_test = pipeline.prepare_data(df, 'target')
    

    trained_models = pipeline.train_models(X_train, y_train, 'classification')
    

    results = pipeline.evaluate_classification_models(X_test, y_test, X_train, y_train)
    

    print("\nModel Evaluation Results:")
    print("=" * 50)
    for result in results:
        print(f"{result.model_name}:")
        print(f"  Accuracy: {result.accuracy:.4f}")
        print(f"  Precision: {result.precision:.4f}")
        print(f"  Recall: {result.recall:.4f}")
        print(f"  F1 Score: {result.f1_score:.4f}")
        print(f"  CV Mean: {np.mean(result.cv_scores):.4f} ± {np.std(result.cv_scores):.4f}")
        print()
    

    pipeline.plot_model_comparison(results)
    

    rf_params = {
        'n_estimators': [50, 100, 200],
        'max_depth': [None, 10, 20],
        'min_samples_split': [2, 5, 10]
    }
    
    best_params = pipeline.hyperparameter_tuning('Random Forest', X_train, y_train, rf_params)
    

    pipeline.save_model('Random Forest', 'best_model.pkl')

if __name__ == "__main__":
    main()
