# API Discovery & Scraping

## API Discovery Workflow

Use Chrome DevTools MCP to intercept network requests:

1. **Navigate** to the target page with DevTools open
2. **Filter** for XHR/Fetch requests
3. **Identify** API endpoints (JSON responses, REST patterns)
4. **Analyze** request/response structure (pagination, auth headers)

```
mcp__chrome-devtools__navigate_page(url)
mcp__chrome-devtools__list_network_requests()    # Filter for XHR/Fetch
mcp__chrome-devtools__get_network_request(id)    # Inspect specific request
```

## HttpCrawler for API Endpoints

### REST API with offset pagination

```python
import asyncio
import json
from crawlee import Request
from crawlee.crawlers import HttpCrawler, HttpCrawlingContext

async def main() -> None:
    PAGE_SIZE = 50

    crawler = HttpCrawler(max_requests_per_crawl=100)

    @crawler.router.default_handler
    async def handler(context: HttpCrawlingContext) -> None:
        body = (await context.http_response.read()).decode()
        data = json.loads(body)

        items = data.get("results", [])
        for item in items:
            await context.push_data(item)

        # Paginate
        total = data.get("total", 0)
        offset = int(context.request.user_data.get("offset", 0))
        next_offset = offset + PAGE_SIZE
        if next_offset < total:
            await context.add_requests([
                Request.from_url(
                    f"https://api.example.com/items?offset={next_offset}&limit={PAGE_SIZE}",
                    user_data={"offset": next_offset},
                )
            ])

    await crawler.run([
        Request.from_url(
            "https://api.example.com/items?offset=0&limit=50",
            user_data={"offset": 0},
        )
    ])

if __name__ == "__main__":
    asyncio.run(main())
```

### REST API with cursor pagination

```python
@crawler.router.default_handler
async def handler(context: HttpCrawlingContext) -> None:
    body = (await context.http_response.read()).decode()
    data = json.loads(body)

    for item in data.get("data", []):
        await context.push_data(item)

    next_cursor = data.get("next_cursor")
    if next_cursor:
        await context.add_requests([
            Request.from_url(
                f"https://api.example.com/items?cursor={next_cursor}",
            )
        ])
```

### POST-based API (search/filter)

```python
import json
from crawlee import Request

# Create POST request
request = Request.from_url(
    "https://api.example.com/search",
    method="POST",
    payload=json.dumps({"query": "shoes", "page": 1}).encode(),
    headers={"Content-Type": "application/json"},
    unique_key="search-page-1",  # Prevent dedup issues with same URL
)

await crawler.run([request])
```

### GraphQL API

```python
import json
from crawlee import Request

query = """
query GetItems($page: Int!) {
    items(page: $page) {
        data { id name price }
        pageInfo { hasNextPage }
    }
}
"""

request = Request.from_url(
    "https://api.example.com/graphql",
    method="POST",
    payload=json.dumps({"query": query, "variables": {"page": 1}}).encode(),
    headers={"Content-Type": "application/json"},
    unique_key="graphql-page-1",
)
```

## Combining API + HTML

When API provides partial data and HTML has the rest:

```python
from crawlee.crawlers import ParselCrawler, ParselCrawlingContext
from crawlee import Request

crawler = ParselCrawler()

@crawler.router.default_handler
async def listing_handler(context: ParselCrawlingContext) -> None:
    # API gives us listing with basic info
    body = (await context.http_response.read()).decode()
    items = json.loads(body)["results"]

    for item in items:
        await context.add_requests([
            Request.from_url(item["detail_url"], label="detail", user_data={"api_data": item})
        ])

@crawler.router.handler(label="detail")
async def detail_handler(context: ParselCrawlingContext) -> None:
    api_data = context.request.user_data["api_data"]
    # Enrich with HTML-only data
    description = context.selector.css(".description::text").get()
    images = context.selector.css(".gallery img::attr(src)").getall()

    await context.push_data({**api_data, "description": description, "images": images})
```

## Checking for Embedded Data First

Before hitting APIs, check if data is already in the HTML:

```python
import chompjs
import extruct

# 1. Check JSON-LD
metadata = extruct.extract(html, syntaxes=["json-ld"])
if metadata["json-ld"]:
    # Data is right there, no API needed
    return metadata["json-ld"]

# 2. Check __NEXT_DATA__
from parsel import Selector
sel = Selector(text=html)
next_data = sel.css("script#__NEXT_DATA__::text").get()
if next_data:
    return chompjs.parse_js_object(next_data)

# 3. Check window.__INITIAL_STATE__ or similar
for script in sel.css("script::text").getall():
    if "__INITIAL_STATE__" in script or "window.__data" in script:
        return chompjs.parse_js_object(script.split("=", 1)[1])
```
