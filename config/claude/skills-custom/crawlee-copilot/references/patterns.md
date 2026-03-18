# Crawlee Patterns

## Router Pattern

Dispatch requests to different handlers based on labels.

```python
from crawlee import Request
from crawlee.crawlers import ParselCrawler, ParselCrawlingContext

crawler = ParselCrawler()

@crawler.router.default_handler
async def listing_handler(context: ParselCrawlingContext) -> None:
    """Handle listing/category pages."""
    for link in context.selector.css(".product-link::attr(href)").getall():
        await context.add_requests([
            Request.from_url(
                context.request.join_url(link),
                label="detail",
            )
        ])
    # Follow pagination
    await context.enqueue_links(selector='a[rel="next"]')

@crawler.router.handler(label="detail")
async def detail_handler(context: ParselCrawlingContext) -> None:
    """Handle product detail pages."""
    await context.push_data({
        "url": context.request.url,
        "name": context.selector.css("h1::text").get(),
        "price": context.selector.css(".price::text").get(),
        "description": context.selector.css(".desc::text").get(),
    })

# Start crawl with labeled request
await crawler.run([
    Request.from_url("https://shop.com/products", label="listing")
])
```

## Pre-Navigation Hooks

Run code before every request (set headers, block resources, etc.).

### HTTP-based crawlers

```python
from crawlee import HttpHeaders
from crawlee.crawlers import BasicCrawlingContext

@crawler.pre_navigation_hook
async def setup(context: BasicCrawlingContext) -> None:
    context.request.headers |= HttpHeaders({
        "Accept-Language": "pl-PL,pl;q=0.9,en;q=0.8",
        "Accept": "text/html,application/xhtml+xml",
    })
```

### Playwright-specific hooks

```python
from crawlee.crawlers import PlaywrightPreNavCrawlingContext

@crawler.pre_navigation_hook
async def browser_setup(context: PlaywrightPreNavCrawlingContext) -> None:
    await context.page.set_extra_http_headers({"X-Custom": "value"})
    await context.page.set_viewport_size({"width": 1280, "height": 720})
```

### Adaptive — dual hooks

```python
from crawlee.crawlers import AdaptivePlaywrightPreNavCrawlingContext

# Runs for ALL requests (HTTP and browser)
@crawler.pre_navigation_hook
async def common_hook(context: AdaptivePlaywrightPreNavCrawlingContext) -> None:
    context.request.headers |= HttpHeaders({"Accept-Language": "pl-PL"})

# Runs ONLY for browser requests
@crawler.pre_navigation_hook(playwright_only=True)
async def browser_hook(context: AdaptivePlaywrightPreNavCrawlingContext) -> None:
    if context.block_requests:
        await context.block_requests(extra_url_patterns=["*.css", "*.woff2", "*.png"])
```

## Session Management

Sessions persist cookies and track health (error score).

```python
from crawlee.sessions import SessionPool

session_pool = SessionPool(
    max_pool_size=100,
    create_session_settings={
        "max_age": timedelta(minutes=50),
        "max_error_score": 3.0,
        "error_score_decrement": 0.5,
        "max_usage_count": 50,
        "blocked_status_codes": [401, 403, 429],
    },
)

crawler = ParselCrawler(
    session_pool=session_pool,
    max_session_rotations=5,
)
```

## enqueue_links Strategies

```python
# Same hostname (default)
await context.enqueue_links()

# Same domain (includes subdomains)
await context.enqueue_links(strategy="same-domain")

# All links
from crawlee import EnqueueStrategy
await context.enqueue_links(strategy=EnqueueStrategy.ALL)

# With CSS selector
await context.enqueue_links(selector="a.product-link")

# With label (route to specific handler)
await context.enqueue_links(selector=".category a", label="category")

# With include/exclude patterns
from crawlee import Glob
await context.enqueue_links(
    include=[Glob("https://example.com/products/*")],
    exclude=[Glob("https://example.com/products/archive/*")],
)

# With regex
import re
await context.enqueue_links(
    include=[re.compile(r"/products/\d+")],
    exclude=[re.compile(r"/admin/")],
)

# Limit number of links
await context.enqueue_links(selector="a", limit=10, strategy="same-domain")

# With user_data
await context.enqueue_links(
    selector=".item a",
    label="detail",
    user_data={"source": "listing"},
)
```

## Request user_data

Pass data between handlers via `user_data`:

```python
# Sending data
await context.add_requests([
    Request.from_url(
        url,
        label="detail",
        user_data={"category": "electronics", "listing_page": 1},
    )
])

# Receiving data
@crawler.router.handler(label="detail")
async def handler(context: ParselCrawlingContext) -> None:
    category = context.request.user_data["category"]
    page = context.request.user_data["listing_page"]
```

## Error Handling

```python
@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    # crawlee auto-retries failed requests (max_request_retries)
    # Check if we've been blocked
    status = context.http_response.status_code
    if status in (403, 429):
        # Session will be rotated automatically if session_pool is configured
        raise Exception(f"Blocked with status {status}")

    # Validate extracted data
    title = context.selector.css("title::text").get()
    if not title:
        context.log.warning(f"No title found at {context.request.url}")
        return  # Skip this page, don't push empty data

    await context.push_data({"url": context.request.url, "title": title})
```

## Content Deduplication

Track content hashes to skip duplicate pages:

```python
import hashlib

seen_hashes: set[str] = set()

@crawler.router.default_handler
async def handler(context: BeautifulSoupCrawlingContext) -> None:
    text = context.soup.get_text(strip=True)
    content_hash = hashlib.sha256(text.encode()).hexdigest()

    if content_hash in seen_hashes:
        context.log.debug(f"Duplicate content at {context.request.url}")
        return

    seen_hashes.add(content_hash)
    await context.push_data({"url": context.request.url, "content": text})
```

## URL Filtering

```python
import re

EXCLUDE_PATTERNS = re.compile(
    r"(?i)"
    r"\.(?:pdf|doc|docx|xls|xlsx|zip|rar|jpg|jpeg|png|gif|svg|mp3|mp4|avi|mov)"
    r"|/wp-admin|/wp-login|/feed/"
    r"|/tag/|/author/|/category/"
    r"|#|javascript:|mailto:"
)

@crawler.pre_navigation_hook
async def filter_urls(context: BasicCrawlingContext) -> None:
    if EXCLUDE_PATTERNS.search(context.request.url):
        context.request.skip()  # Skip this request
```

## Pydantic Models for Data Validation

```python
from pydantic import BaseModel, HttpUrl

class Product(BaseModel):
    url: HttpUrl
    name: str
    price: float | None = None
    description: str | None = None
    images: list[str] = []

@crawler.router.handler(label="product")
async def handler(context: ParselCrawlingContext) -> None:
    product = Product(
        url=context.request.url,
        name=context.selector.css("h1::text").get(""),
        price=parse_price(context.selector.css(".price::text").get()),
        description=context.selector.css(".desc::text").get(),
        images=context.selector.css(".gallery img::attr(src)").getall(),
    )
    await context.push_data(product.model_dump(mode="json"))
```
