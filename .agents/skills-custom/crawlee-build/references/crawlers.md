# Crawler Types

## Selection Guide

| Scenario | Crawler | Why |
|----------|---------|-----|
| Simple static HTML | `BeautifulSoupCrawler` | Lightest, familiar API |
| CSS+XPath selectors | `ParselCrawler` | Scrapy-style selectors |
| Anti-bot (static) | `ParselCrawler` + `CurlImpersonateHttpClient` | TLS fingerprint bypass |
| JavaScript/SPA | `PlaywrightCrawler` | Full browser rendering |
| Unknown/mixed | `AdaptivePlaywrightCrawler` | Tries HTTP first, falls back to browser |
| API endpoint | `HttpCrawler` | Raw HTTP, no parsing overhead |

## AdaptivePlaywrightCrawler (Mixed HTTP/Browser)

Use when the approved Crawlee design needs both HTTP efficiency and browser fallback. It is not the default for ordinary HTTP/API/listing-detail production scraping; those usually belong in Scrapy.

Tries HTTP-based crawling first, falls back to Playwright when content is missing.
Uses unified `parsed_content` interface (BeautifulSoup object) regardless of mode.

```python
import asyncio
from crawlee import ConcurrencySettings, HttpHeaders
from crawlee.crawlers import (
    AdaptivePlaywrightCrawler,
    AdaptivePlaywrightCrawlingContext,
    AdaptivePlaywrightPreNavCrawlingContext,
)
from crawlee.http_clients import CurlImpersonateHttpClient

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
        request_handler_timeout=timedelta(seconds=45),
        playwright_crawler_specific_kwargs={
            "headless": True,
            "browser_launch_options": {"chromium_sandbox": False},
        },
    )

    @crawler.pre_navigation_hook
    async def common_setup(context: AdaptivePlaywrightPreNavCrawlingContext) -> None:
        context.request.headers |= HttpHeaders({"Accept-Language": "en-US,en;q=0.9"})

    @crawler.pre_navigation_hook(playwright_only=True)
    async def browser_setup(context: AdaptivePlaywrightPreNavCrawlingContext) -> None:
        await context.page.set_viewport_size({"width": 1280, "height": 720})
        if context.block_requests:
            await context.block_requests(extra_url_patterns=["*.css", "*.woff2"])

    @crawler.router.default_handler
    async def handler(context: AdaptivePlaywrightCrawlingContext) -> None:
        title_tag = context.parsed_content.find("title")
        title = title_tag.get_text() if title_tag else None
        await context.push_data({"url": context.request.url, "title": title})
        await context.enqueue_links(strategy="same-domain")

    await crawler.run(["https://example.com"])

if __name__ == "__main__":
    asyncio.run(main())
```

## BeautifulSoupCrawler

Best for simple static HTML with BeautifulSoup API.

```python
from crawlee.crawlers import BeautifulSoupCrawler, BeautifulSoupCrawlingContext

crawler = BeautifulSoupCrawler(
    parser="lxml",                    # 'lxml', 'html.parser', 'html5lib'
    max_requests_per_crawl=100,
    max_crawl_depth=3,
    concurrency_settings=ConcurrencySettings(max_concurrency=5, max_tasks_per_minute=60),
)

@crawler.router.default_handler
async def handler(context: BeautifulSoupCrawlingContext) -> None:
    data = {
        "url": context.request.url,
        "title": context.soup.title.string if context.soup.title else None,
        "text": context.soup.get_text(separator=" ", strip=True)[:5000],
    }
    await context.push_data(data)
    await context.enqueue_links(strategy="same-domain")
```

## ParselCrawler

Scrapy's CSS + XPath selectors. Best for structured data extraction.

```python
from crawlee.crawlers import ParselCrawler, ParselCrawlingContext
from crawlee.http_clients import CurlImpersonateHttpClient

http_client = CurlImpersonateHttpClient(impersonate="chrome131")

crawler = ParselCrawler(
    http_client=http_client,
    max_requests_per_crawl=100,
)

@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    data = {
        "url": context.request.url,
        "title": context.selector.css("title::text").get(),
        "h1": context.selector.css("h1::text").get(),
        "links": context.selector.css("a::attr(href)").getall(),
    }
    await context.push_data(data)
```

## PlaywrightCrawler

Full browser rendering for JavaScript-heavy sites.

```python
from crawlee.crawlers import PlaywrightCrawler, PlaywrightCrawlingContext

crawler = PlaywrightCrawler(
    max_requests_per_crawl=50,
    headless=True,
    browser_type="chromium",          # 'chromium', 'firefox', 'webkit'
    concurrency_settings=ConcurrencySettings(max_concurrency=3, max_tasks_per_minute=30),
)

@crawler.router.default_handler
async def handler(context: PlaywrightCrawlingContext) -> None:
    await context.page.wait_for_selector(".content", timeout=10000)
    title = await context.page.title()
    content = await context.page.inner_text(".content")
    await context.push_data({"url": context.request.url, "title": title, "content": content})
    await context.enqueue_links(selector="a.next-page")
```

**Fingerprint generation** (anti-detection):

```python
from crawlee.fingerprint_suite import DefaultFingerprintGenerator, HeaderGeneratorOptions

fingerprint_generator = DefaultFingerprintGenerator(
    header_options=HeaderGeneratorOptions(browsers=["chrome"]),
)

crawler = PlaywrightCrawler(
    headless=True,
    browser_type="chromium",
    fingerprint_generator=fingerprint_generator,
)
```

**Multiple browser types via BrowserPool:**

```python
from crawlee.browsers import BrowserPool, PlaywrightBrowserPlugin

pool = BrowserPool(plugins=[
    PlaywrightBrowserPlugin(browser_type="chromium", max_open_pages_per_browser=1),
    PlaywrightBrowserPlugin(browser_type="firefox", max_open_pages_per_browser=1),
])

crawler = PlaywrightCrawler(browser_pool=pool)
```

## HttpCrawler

Raw HTTP responses without parsing. Best for API endpoints.

```python
from crawlee.crawlers import HttpCrawler, HttpCrawlingContext

crawler = HttpCrawler()

@crawler.router.default_handler
async def handler(context: HttpCrawlingContext) -> None:
    body = (await context.http_response.read()).decode()
    import json
    data = json.loads(body)
    await context.push_data(data)
```

## CurlImpersonateHttpClient

TLS fingerprint impersonation via `curl_cffi`. Use with any HTTP-based crawler.

```python
from crawlee.http_clients import CurlImpersonateHttpClient

http_client = CurlImpersonateHttpClient(
    persist_cookies_per_session=True,
    timeout=10,
    impersonate="chrome131",     # 'chrome131', 'firefox135', etc.
)

crawler = ParselCrawler(http_client=http_client)
```

Available profiles: `chrome131`, `firefox135`, `safari18_0`, `edge131`.
Fallback: rotate profiles if one gets blocked.

## ConcurrencySettings

```python
from crawlee import ConcurrencySettings

concurrency = ConcurrencySettings(
    min_concurrency=1,                  # Never go below
    max_concurrency=10,                 # Never exceed
    desired_concurrency=5,              # Starting point (auto-scales)
    max_tasks_per_minute=120,           # Rate limit
)

crawler = BeautifulSoupCrawler(concurrency_settings=concurrency)
```

Guidelines:
- **Gentle crawling**: `max_concurrency=1-3`, `max_tasks_per_minute=30-60`
- **Normal crawling**: `max_concurrency=5-10`, `max_tasks_per_minute=120`
- **Aggressive crawling**: `max_concurrency=20-50`, no rate limit (be cautious)
