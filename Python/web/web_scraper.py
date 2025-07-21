

import requests
from bs4 import BeautifulSoup
import time
import random
from urllib.parse import urljoin, urlparse
from typing import List, Dict, Optional, Set
import logging
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import csv


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class ScrapedData:

    url: str
    title: str
    content: str
    links: List[str]
    metadata: Dict[str, str]
    timestamp: float

class WebScraper:

    
    def __init__(self, delay_range=(1, 3), max_retries=3, timeout=10):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        })
        self.delay_range = delay_range
        self.max_retries = max_retries
        self.timeout = timeout
        self.visited_urls: Set[str] = set()
        
    def _random_delay(self):

        delay = random.uniform(*self.delay_range)
        time.sleep(delay)
        
    def _get_page(self, url: str) -> Optional[requests.Response]:

        for attempt in range(self.max_retries):
            try:
                self._random_delay()
                response = self.session.get(url, timeout=self.timeout)
                response.raise_for_status()
                return response
            except requests.RequestException as e:
                logger.warning(f"Attempt {attempt + 1} failed for {url}: {e}")
                if attempt == self.max_retries - 1:
                    logger.error(f"Failed to fetch {url} after {self.max_retries} attempts")
        return None
    
    def scrape_page(self, url: str) -> Optional[ScrapedData]:

        if url in self.visited_urls:
            logger.info(f"Already visited {url}, skipping")
            return None
            
        response = self._get_page(url)
        if not response:
            return None
            
        self.visited_urls.add(url)
        
        try:
            soup = BeautifulSoup(response.content, 'html.parser')
            

            title = soup.find('title')
            title_text = title.get_text().strip() if title else "No title"
            

            content_selectors = ['article', 'main', '.content', '#content', 'body']
            content = ""
            for selector in content_selectors:
                content_elem = soup.select_one(selector)
                if content_elem:
                    content = content_elem.get_text().strip()
                    break
            

            links = []
            for link in soup.find_all('a', href=True):
                absolute_url = urljoin(url, link['href'])
                if self._is_valid_url(absolute_url):
                    links.append(absolute_url)
            

            metadata = {}
            for meta in soup.find_all('meta'):
                name = meta.get('name') or meta.get('property')
                content_attr = meta.get('content')
                if name and content_attr:
                    metadata[name] = content_attr
            
            return ScrapedData(
                url=url,
                title=title_text,
                content=content[:1000],
                links=links,
                metadata=metadata,
                timestamp=time.time()
            )
            
        except Exception as e:
            logger.error(f"Error parsing {url}: {e}")
            return None
    
    def _is_valid_url(self, url: str) -> bool:

        try:
            parsed = urlparse(url)
            return parsed.scheme in ('http', 'https') and parsed.netloc
        except:
            return False
    
    def scrape_multiple(self, urls: List[str], max_workers=5) -> List[ScrapedData]:

        results = []
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_url = {executor.submit(self.scrape_page, url): url for url in urls}
            
            for future in as_completed(future_to_url):
                url = future_to_url[future]
                try:
                    result = future.result()
                    if result:
                        results.append(result)
                        logger.info(f"Successfully scraped {url}")
                except Exception as e:
                    logger.error(f"Error scraping {url}: {e}")
        
        return results
    
    def crawl_website(self, start_url: str, max_pages=10, same_domain_only=True) -> List[ScrapedData]:

        domain = urlparse(start_url).netloc if same_domain_only else None
        to_visit = [start_url]
        results = []
        
        while to_visit and len(results) < max_pages:
            url = to_visit.pop(0)
            
            if same_domain_only and urlparse(url).netloc != domain:
                continue
                
            scraped_data = self.scrape_page(url)
            if scraped_data:
                results.append(scraped_data)
                

                for link in scraped_data.links:
                    if link not in self.visited_urls and link not in to_visit:
                        if not same_domain_only or urlparse(link).netloc == domain:
                            to_visit.append(link)
        
        return results

class DataExporter:

    
    @staticmethod
    def to_json(data: List[ScrapedData], filename: str):

        json_data = []
        for item in data:
            json_data.append({
                'url': item.url,
                'title': item.title,
                'content': item.content,
                'links': item.links,
                'metadata': item.metadata,
                'timestamp': item.timestamp
            })
        
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(json_data, f, indent=2, ensure_ascii=False)
        
        logger.info(f"Data exported to {filename}")
    
    @staticmethod
    def to_csv(data: List[ScrapedData], filename: str):

        with open(filename, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['URL', 'Title', 'Content Preview', 'Link Count', 'Timestamp'])
            
            for item in data:
                writer.writerow([
                    item.url,
                    item.title,
                    item.content[:100] + '...' if len(item.content) > 100 else item.content,
                    len(item.links),
                    time.ctime(item.timestamp)
                ])
        
        logger.info(f"Data exported to {filename}")

def main():


    scraper = WebScraper(delay_range=(1, 2), max_retries=3)
    

    urls = [
        'https://httpbin.org/html',
        'https://example.com',
        'https://httpbin.org/json'
    ]
    

    logger.info("Starting web scraping...")
    results = scraper.scrape_multiple(urls, max_workers=3)
    
    if results:
        logger.info(f"Successfully scraped {len(results)} pages")
        

        exporter = DataExporter()
        exporter.to_json(results, 'scraped_data.json')
        exporter.to_csv(results, 'scraped_data.csv')
        

        for result in results:
            print(f"\nURL: {result.url}")
            print(f"Title: {result.title}")
            print(f"Content preview: {result.content[:100]}...")
            print(f"Links found: {len(result.links)}")
    else:
        logger.warning("No data was scraped")

if __name__ == "__main__":
    main()
