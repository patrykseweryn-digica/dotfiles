# Pagination

## Auto-Detection Strategy

Check in this priority order:

### 1. Standard pagination links

```python
from parsel import Selector

sel = Selector(text=html)

# rel="next"
next_url = sel.css('link[rel="next"]::attr(href)').get()
next_url = next_url or sel.css('a[rel="next"]::attr(href)').get()

# Numbered pages
pages = sel.css(".pagination a::attr(href)").getall()
pages = pages or sel.css("nav.pages a::attr(href)").getall()

# "Next" text link
next_link = sel.xpath('//a[contains(text(), "Next") or contains(text(), "Następna") or contains(text(), "»")]/@href').get()
```

### 2. Load More / Infinite scroll

Look for:
- `<button>` with text "Load More", "Show More", "Pokaż więcej"
- `data-page`, `data-offset`, `data-next` attributes
- JavaScript scroll handlers
- API calls triggered on scroll (use DevTools to intercept)

### 3. URL pattern analysis

```
/page/1, /page/2          → Numbered path segments
?page=1, ?p=1             → Query parameter
?offset=0, ?offset=20     → Offset-based
?cursor=abc123             → Cursor-based
```

### 4. API-based pagination

Check network requests (DevTools MCP) for:
- `offset` / `limit` parameters
- `cursor` / `after` / `next_token` parameters
- `page` / `per_page` parameters
- Response headers: `X-Total-Count`, `Link` header

## Crawlee Patterns

### Next-link pagination (enqueue_links)

```python
@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    # Extract items on current page
    for item in context.selector.css(".item"):
        await context.push_data({
            "name": item.css("h2::text").get(),
            "price": item.css(".price::text").get(),
        })

    # Follow "next" link
    await context.enqueue_links(selector='a[rel="next"], a.next-page')
```

### Numbered pages (generate all URLs upfront)

```python
import asyncio
from crawlee import Request
from crawlee.crawlers import ParselCrawler, ParselCrawlingContext

async def main() -> None:
    crawler = ParselCrawler()

    @crawler.router.default_handler
    async def handler(context: ParselCrawlingContext) -> None:
        for item in context.selector.css(".item"):
            await context.push_data({"name": item.css("h2::text").get()})

    # Generate all page URLs
    urls = [f"https://example.com/items?page={i}" for i in range(1, 51)]
    await crawler.run(urls)
```

### Infinite scroll (Playwright)

```python
from crawlee.crawlers import PlaywrightCrawler, PlaywrightCrawlingContext

crawler = PlaywrightCrawler(headless=True)

@crawler.router.default_handler
async def handler(context: PlaywrightCrawlingContext) -> None:
    seen_items = set()
    max_scrolls = 30

    for _ in range(max_scrolls):
        items = await context.page.query_selector_all(".item")
        new_count = 0
        for item in items:
            item_id = await item.get_attribute("data-id")
            if item_id and item_id not in seen_items:
                seen_items.add(item_id)
                new_count += 1
                name = await (await item.query_selector("h2")).inner_text()
                await context.push_data({"id": item_id, "name": name})

        if new_count == 0:
            break

        await context.page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
        await context.page.wait_for_timeout(1500)
```

### API cursor pagination (HttpCrawler)

See `api-scraping.md` for examples.

## Verification

After implementing pagination, verify:
- [ ] First page loads correctly
- [ ] Last page reached (no infinite loop)
- [ ] Total items match expected count
- [ ] No duplicate items
- [ ] Rate limiting respected
