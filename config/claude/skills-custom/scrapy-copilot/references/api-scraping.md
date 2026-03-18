# API Scraping & Reverse Engineering

## When to Use

Prefer API scraping over HTML parsing when:
- Page is an SPA that loads data via XHR/fetch
- API returns clean JSON (easier to parse than HTML)
- Rate limits are more generous for API than for pages

## Discovering API Endpoints

Use Chrome DevTools MCP to intercept network requests:

```
1. mcp__chrome-devtools__navigate_page(url=target_url)
2. mcp__chrome-devtools__list_network_requests(resourceTypes=["xhr", "fetch"])
3. For each interesting request:
   mcp__chrome-devtools__get_network_request(reqid=N)
   → full URL, headers, request body, response body
4. Interact with page (click next, scroll) to capture pagination calls:
   mcp__chrome-devtools__click({uid})
5. mcp__chrome-devtools__list_network_requests(resourceTypes=["xhr", "fetch"])
   → compare URLs to find pagination pattern
```

## Standalone Script Pattern

Use curl_cffi with TLS fingerprinting — the API may check TLS fingerprints too.

### REST API with offset pagination
```python
from curl_cffi.requests import Session
from fake_useragent import UserAgent
from loguru import logger
from pydantic import BaseModel
from stamina import retry

ua = UserAgent()

class Product(BaseModel):
    name: str
    price: float
    url: str

@retry(on=Exception, attempts=3)
def fetch_page(session: Session, url: str, params: dict | None = None) -> dict:
    resp = session.get(url, params=params, impersonate="chrome")
    resp.raise_for_status()
    return resp.json()

def scrape_api():
    api_url = "https://api.example.com/v1/products"
    page_size = 20
    all_items = []

    with Session() as s:
        s.headers.update({"User-Agent": ua.random})
        offset = 0
        while True:
            data = fetch_page(s, api_url, params={"offset": offset, "limit": page_size})
            items = [Product(**item) for item in data["results"]]
            all_items.extend(items)
            logger.info(f"Fetched {len(all_items)} items (offset={offset})")
            if len(data["results"]) < page_size:
                break
            offset += page_size

    return all_items
```

### REST API with cursor pagination
```python

def scrape_cursor_api():
    api_url = "https://api.example.com/v1/products"
    all_items = []
    cursor = None

    with Session() as s:
        s.headers.update({"User-Agent": ua.random})
        while True:
            params = {"cursor": cursor} if cursor else None
            data = fetch_page(s, api_url, params=params)
            all_items.extend(data["results"])
            cursor = data.get("next_cursor")
            if not cursor:
                break

    return all_items
```

### POST-based API (search/filter)
```python
import json

@retry(on=Exception, attempts=3)
def search_api(session: Session, query: str, page: int) -> dict:
    resp = session.post(
        "https://api.example.com/search",
        headers={"Content-Type": "application/json"},
        data=json.dumps({"query": query, "page": page}),
        impersonate="chrome",
    )
    resp.raise_for_status()
    return resp.json()
```

### API with auth headers
```python
import os

with Session() as s:
    s.headers.update({
        "User-Agent": ua.random,
        "Authorization": f"Bearer {os.environ['API_TOKEN']}",
    })
```

## Scrapy API Spider

When you need Scrapy's pipeline/middleware stack for API scraping:
```python
import scrapy

class ApiSpider(scrapy.Spider):
    name = "api_products"
    api_url = "https://api.example.com/v1/products"

    def start_requests(self):
        yield scrapy.Request(f"{self.api_url}?offset=0&limit=20")

    def parse(self, response):
        data = response.json()
        for item in data["results"]:
            yield item
        if len(data["results"]) == 20:
            offset = data.get("offset", 0) + 20
            yield scrapy.Request(f"{self.api_url}?offset={offset}&limit=20")
```

## Combining API + HTML

Sometimes API gives partial data, HTML has the rest:
```python
@retry(on=Exception, attempts=3)
def fetch(session, url):
    return session.get(url, impersonate="chrome")

# Get list from API
api_data = fetch(session, api_url).json()
for item in api_data["results"]:
    # Get extra fields from HTML detail page
    html = fetch(session, item["detail_url"]).text
    sel = Selector(text=html)
    item["description"] = sel.css(".description::text").get("")
```
