# Scrapy Integration

Use Scrapy when you need: hundreds+ pages, complex navigation, pipelines,
middleware chains, or recurring/long-running scrapes.

For simpler tasks, generate a standalone script instead (see SKILL.md template).

## Project Setup

### 1. Initialize with uv
```bash
mkdir <project_name> && cd <project_name>
uv init --no-readme
```

### 2. Dependencies (pyproject.toml)
```toml
[project]
dependencies = [
    "scrapy>=2.11",
    "scrapy-poet>=0.24",
    "web-poet>=0.17",
    "pydantic>=2.0",
    "itemloaders>=1.3",
    "w3lib>=2.0",
    "loguru>=0.7",
    "stamina>=2.0",
    "fake-useragent>=2.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=1.0",
    "ruff>=0.4",
    "pyright>=1.1",
]
browser = [
    "scrapy-playwright>=0.0.40",
]
```

### 3. Install
```bash
uv sync --all-extras
```

### 4. Project structure (per-domain)
```
my_project/
├── pyproject.toml
├── scrapy.cfg
├── Dockerfile
├── docker-compose.yml
├── settings.py
├── middlewares.py
├── pipelines.py
├── example_com/
│   ├── __init__.py
│   ├── items.py          # Pydantic models
│   ├── loaders.py        # ItemLoaders
│   ├── page_objects.py   # web-poet PageObjects
│   ├── spiders/
│   │   ├── __init__.py
│   │   └── products.py
│   └── tests/
│       ├── __init__.py
│       ├── fixtures/
│       └── test_page_objects.py
```

### 5. Settings defaults
```python
BOT_NAME = "<project_name>"
SPIDER_MODULES = ["<domain>.spiders"]
ROBOTSTXT_OBEY = True
AUTOTHROTTLE_ENABLED = True
AUTOTHROTTLE_START_DELAY = 1
AUTOTHROTTLE_MAX_DELAY = 10
CONCURRENT_REQUESTS = 8
DOWNLOAD_DELAY = 0.5
TWISTED_REACTOR = "twisted.internet.asyncioreactor.AsyncioSelectorReactor"

DOWNLOADER_MIDDLEWARES = {
    "scrapy_poet.InjectionMiddleware": 543,
    "middlewares.RotatingUserAgentMiddleware": 400,
    "scrapy.downloadermiddlewares.useragent.UserAgentMiddleware": None,
}
SPIDER_MIDDLEWARES = {
    "scrapy_poet.RetryMiddleware": 275,
}
FEEDS = {
    "output/%(name)s/%(time)s.jsonl": {
        "format": "jsonlines",
        "encoding": "utf-8",
    },
}
```

### 6. UA Middleware
```python
from fake_useragent import UserAgent

ua = UserAgent()

class RotatingUserAgentMiddleware:
    def process_request(self, request):
        request.headers["User-Agent"] = ua.random
```

### 7. Loguru integration in settings.py
```python
import logging
from loguru import logger

class InterceptHandler(logging.Handler):
    def emit(self, record):
        level = logger.level(record.levelname).name
        logger.opt(depth=6, exception=record.exc_info).log(level, record.getMessage())

# Replace stdlib handlers with loguru; INFO level to skip noisy DEBUG from libs
logging.basicConfig(handlers=[InterceptHandler()], level=logging.INFO, force=True)
for noisy in ("filelock", "tldextract", "asyncio", "hpack"):
    logging.getLogger(noisy).setLevel(logging.WARNING)

logger.add("scrapy.log", rotation="50 MB", serialize=True)

# Disable Scrapy's own log output to prevent duplicate lines
LOG_ENABLED = False
```

## Code Patterns

### Pydantic Item
```python
from pydantic import BaseModel

class ProductItem(BaseModel):
    name: str
    price: float
    url: str
    description: str | None = None
```

### web-poet PageObject
Override `to_item()` as `async def`. Do NOT use `@field` decorators (RecursionError).
Use `WebPage[ItemType]` generic syntax.
```python
import attrs
from web_poet import WebPage, handle_urls
from .items import ProductItem

@handle_urls("example.com")
@attrs.define
class ProductPage(WebPage[ProductItem]):
    async def to_item(self) -> ProductItem:
        return ProductItem(
            name=self.css("h1::text").get(""),
            price=float(self.css(".price::text").get("0")),
            url=str(self.url),
        )
```

### Spider with PageObject injection
```python
import scrapy
from scrapy_poet import DummyResponse
from ..page_objects import ProductPage

class ProductSpider(scrapy.Spider):
    name = "products"
    start_urls = ["https://example.com/products"]

    def parse(self, response):
        for link in response.css(".product-link::attr(href)").getall():
            yield response.follow(link, self.parse_product)
        next_page = response.css("a.next::attr(href)").get()
        if next_page:
            yield response.follow(next_page, self.parse)

    async def parse_product(self, response: DummyResponse, page: ProductPage):
        yield await page.to_item()
```

### Single-page spider (no PageObject needed)
```python
def parse(self, response):
    for el in response.css(".item"):
        yield {
            "text": el.css(".text::text").get(""),
            "author": el.css(".author::text").get(""),
        }
    next_page = response.css("li.next a::attr(href)").get()
    if next_page:
        yield response.follow(next_page, self.parse)
```

## Docker

### Dockerfile
```dockerfile
FROM python:3.12-slim AS base
WORKDIR /app
RUN pip install uv

FROM base AS deps
COPY pyproject.toml uv.lock* ./
RUN uv sync --no-dev --frozen 2>/dev/null || uv sync --no-dev

FROM python:3.12-slim AS runtime
WORKDIR /app
COPY --from=deps /app/.venv /app/.venv
COPY . .
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["scrapy"]
CMD ["list"]
```

### docker-compose.yml
```yaml
services:
  scraper:
    build: .
    command: ["crawl", "${SPIDER_NAME:-products}"]
    volumes:
      - ./output:/app/output
    env_file: .env
    restart: "no"
```
