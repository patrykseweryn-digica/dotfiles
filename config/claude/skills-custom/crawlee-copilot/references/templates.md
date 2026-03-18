# Code Templates

## Single-File Template

For simple crawlers (1-3 page types).

```python
"""Crawler for [TARGET SITE].

Extracts [WHAT] from [WHERE].

Usage:
    uv run crawler.py
"""

import asyncio
from datetime import timedelta

from crawlee import ConcurrencySettings, Request
from crawlee.crawlers import (
    AdaptivePlaywrightCrawler,
    AdaptivePlaywrightCrawlingContext,
)
from crawlee.http_clients import CurlImpersonateHttpClient
from pydantic import BaseModel


# --- Models ---

class Item(BaseModel):
    url: str
    title: str
    # Add fields here


# --- Crawler ---

async def main() -> None:
    http_client = CurlImpersonateHttpClient(impersonate="chrome131")

    crawler = AdaptivePlaywrightCrawler.with_beautifulsoup_static_parser(
        http_client=http_client,
        max_requests_per_crawl=100,
        max_crawl_depth=3,
        concurrency_settings=ConcurrencySettings(
            desired_concurrency=5,
            max_concurrency=10,
            max_tasks_per_minute=120,
        ),
        request_handler_timeout=timedelta(seconds=30),
    )

    @crawler.router.default_handler
    async def handler(context: AdaptivePlaywrightCrawlingContext) -> None:
        title_tag = context.parsed_content.find("title")
        title = title_tag.get_text(strip=True) if title_tag else ""

        item = Item(url=context.request.url, title=title)
        await context.push_data(item.model_dump(mode="json"))
        await context.enqueue_links(strategy="same-domain")

    await crawler.run(["https://example.com"])
    await crawler.export_data(path="output/results.json")


if __name__ == "__main__":
    asyncio.run(main())
```

## Single-File with Router (multiple page types)

```python
import asyncio
from crawlee import ConcurrencySettings, Request
from crawlee.crawlers import ParselCrawler, ParselCrawlingContext
from crawlee.http_clients import CurlImpersonateHttpClient
from pydantic import BaseModel


class Product(BaseModel):
    url: str
    name: str
    price: str | None = None
    description: str | None = None


async def main() -> None:
    http_client = CurlImpersonateHttpClient(impersonate="chrome131")
    crawler = ParselCrawler(http_client=http_client, max_requests_per_crawl=500)

    @crawler.router.default_handler
    async def listing(context: ParselCrawlingContext) -> None:
        for link in context.selector.css(".product-link::attr(href)").getall():
            await context.add_requests([
                Request.from_url(context.request.join_url(link), label="product")
            ])
        await context.enqueue_links(selector='a[rel="next"]')

    @crawler.router.handler(label="product")
    async def product(context: ParselCrawlingContext) -> None:
        item = Product(
            url=context.request.url,
            name=context.selector.css("h1::text").get(""),
            price=context.selector.css(".price::text").get(),
            description=context.selector.css(".description::text").get(),
        )
        await context.push_data(item.model_dump(mode="json"))

    await crawler.run(["https://shop.com/products"])
    await crawler.export_data(path="output/products.json")


if __name__ == "__main__":
    asyncio.run(main())
```

## Modular Project Structure

For complex crawlers (4+ handlers, custom pipeline, configuration).

```
my_crawler/
├── pyproject.toml
├── .env
├── .env.template
├── .gitignore
├── Dockerfile
├── docker-compose.yml
├── src/
│   ├── __init__.py
│   ├── main.py           # Entry point
│   ├── config.py          # Settings (env vars, constants)
│   ├── models.py          # Pydantic models
│   ├── crawler.py         # Crawler factory & configuration
│   ├── handlers/
│   │   ├── __init__.py
│   │   ├── listing.py     # Listing page handler
│   │   └── detail.py      # Detail page handler
│   └── storage.py         # Custom storage (if not using push_data)
├── tests/
│   ├── __init__.py
│   ├── fixtures/          # Saved HTML for unit tests
│   ├── cassettes/         # VCR cassettes for integration tests
│   ├── test_handlers.py
│   └── test_models.py
└── output/                # Crawl results
```

### pyproject.toml

```toml
[project]
name = "my-crawler"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "crawlee[beautifulsoup,parsel,playwright,curl-impersonate]>=1.5",
    "pydantic>=2.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.24",
    "ruff>=0.8",
    "pyright>=1.1",
]

[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "UP"]

[tool.pyright]
pythonVersion = "3.12"
typeCheckingMode = "basic"

[tool.pytest.ini_options]
asyncio_mode = "auto"
```

### config.py

```python
import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    max_requests: int = 100
    max_depth: int = 3
    max_concurrency: int = 10
    tasks_per_minute: int = 120
    impersonate_profile: str = "chrome131"
    proxy_urls: str = ""  # Comma-separated

    class Config:
        env_file = ".env"

settings = Settings()
```

### crawler.py

```python
from datetime import timedelta
from crawlee import ConcurrencySettings
from crawlee.crawlers import AdaptivePlaywrightCrawler
from crawlee.http_clients import CurlImpersonateHttpClient
from .config import settings

def create_crawler() -> AdaptivePlaywrightCrawler:
    http_client = CurlImpersonateHttpClient(impersonate=settings.impersonate_profile)

    return AdaptivePlaywrightCrawler.with_beautifulsoup_static_parser(
        http_client=http_client,
        max_requests_per_crawl=settings.max_requests,
        max_crawl_depth=settings.max_depth,
        concurrency_settings=ConcurrencySettings(
            desired_concurrency=5,
            max_concurrency=settings.max_concurrency,
            max_tasks_per_minute=settings.tasks_per_minute,
        ),
        request_handler_timeout=timedelta(seconds=30),
    )
```

### main.py

```python
import asyncio
from .crawler import create_crawler
from .handlers.listing import register_listing_handlers
from .handlers.detail import register_detail_handlers

async def main() -> None:
    crawler = create_crawler()
    register_listing_handlers(crawler)
    register_detail_handlers(crawler)

    await crawler.run(["https://example.com"])
    await crawler.export_data(path="output/results.json")

if __name__ == "__main__":
    asyncio.run(main())
```

### handlers/listing.py

```python
from crawlee import Request
from crawlee.crawlers import AdaptivePlaywrightCrawler, AdaptivePlaywrightCrawlingContext

def register_listing_handlers(crawler: AdaptivePlaywrightCrawler) -> None:
    @crawler.router.default_handler
    async def listing(context: AdaptivePlaywrightCrawlingContext) -> None:
        for link in context.parsed_content.select(".product-link"):
            href = link.get("href")
            if href:
                await context.add_requests([
                    Request.from_url(context.request.join_url(href), label="detail")
                ])
```

### .env.template

```bash
# Proxy (optional)
PROXY_URLS=
# Concurrency
MAX_REQUESTS=100
MAX_CONCURRENCY=10
TASKS_PER_MINUTE=120
# Browser impersonation
IMPERSONATE_PROFILE=chrome131
```

### .gitignore

```
.env
output/
storage/
__pycache__/
.ruff_cache/
```
