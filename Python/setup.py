

from setuptools import setup, find_packages

with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="python-project-collection",
    version="1.0.0",
    author="Your Name",
    author_email="your.email@example.com",
    description="A comprehensive collection of Python modules for web development, data processing, and machine learning",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/yourusername/python-project-collection",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Web Development",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Topic :: Internet :: WWW/HTTP :: Browsers",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.1",
        ],
        "ml": [
            "tensorflow>=2.13.0",
            "torch>=2.0.1",
            "scikit-learn>=1.3.0",
        ],
        "web": [
            "selenium>=4.11.2",
            "beautifulsoup4>=4.12.2",
            "websockets>=11.0.3",
        ],
    },
    entry_points={
        "console_scripts": [
            "scrape-web=web.web_scraper:main",
            "run-pipeline=data.data_pipeline:main",
            "start-api=api.flask_api:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)
