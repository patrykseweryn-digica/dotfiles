# Pagination Auto-Detection

## Detection Strategy

Analyze the page for pagination patterns in this order:

### 1. Standard Pagination Links
Look for:
- `<a>` tags with text: "Next", "Następna", "»", "›", "→", ">>"
- `<a>` tags with class/id containing: "next", "pagination", "pager"
- `<nav>` or `<ul>` with numbered page links (1, 2, 3...)
- `rel="next"` attribute on links

CSS selectors to try:
```
a.next, a[rel="next"], .pagination a.next,
li.next > a, .pager .next a,
nav.pagination a:last-child,
a[aria-label="Next"], a[aria-label*="next"]
```

### 2. Load More / Infinite Scroll
Look for:
- Buttons with text: "Load more", "Show more", "Pokaż więcej"
- `data-page`, `data-offset`, `data-cursor` attributes
- JavaScript scroll event handlers (in script tags)
- API endpoints in XHR/fetch calls (look for `/api/`, `?page=`, `?offset=`)

If infinite scroll detected:
- **Scrapy projects** → use scrapy-playwright (Scrapy download handler API — pydoll/camoufox don't integrate with Scrapy).
- **Standalone scripts** → use pydoll directly (see `references/browsers.md`).
- **Always check for API endpoints first** — direct API calls avoid browser overhead.

### 3. URL Pattern Analysis
Check if current URL has pagination parameters:
- `?page=1`, `?p=1`, `?offset=0`
- `/page/1/`, `/p/1/`
- `?start=0&count=20`

If found, generate pagination by incrementing the parameter.

### 4. API-based Pagination
If the page loads data via XHR/fetch:
- Look for JSON API endpoints in page source
- Check for `cursor`, `next_token`, `offset` in API responses
- Suggest direct API scraping instead of HTML parsing

## Verification

After detecting a pagination pattern, verify it:

1. Construct the URL for page 2
2. Fetch page 2 via WebFetch
3. Confirm it has different content than page 1
4. Check if page 2 has the same pagination structure (next → page 3)

If verification fails, warn the user and ask them to confirm the pagination pattern.

## Generated Code Patterns

### Standard next-link pagination
```python
def handle_pagination(self, response):
    next_page = response.css("a.next::attr(href)").get()
    if next_page:
        yield response.follow(next_page, self.parse)
```

### Numbered page pagination
```python
def start_requests(self):
    for page in range(1, self.max_pages + 1):
        yield scrapy.Request(
            f"{self.base_url}?page={page}",
            callback=self.parse,
        )
```

### API cursor pagination
```python
def parse_api(self, response):
    data = response.json()
    for item in data["results"]:
        yield self.parse_item(item)

    if cursor := data.get("next_cursor"):
        yield scrapy.Request(
            f"{self.api_url}?cursor={cursor}",
            callback=self.parse_api,
        )
```

### Infinite scroll (scrapy-playwright — for Scrapy projects only)

For standalone scripts, use pydoll directly (see `references/browsers.md`).

```python
custom_settings = {
    "DOWNLOAD_HANDLERS": {
        "https": "scrapy_playwright.handler.ScrapyPlaywrightDownloadHandler",
    },
}

def start_requests(self):
    yield scrapy.Request(
        self.start_url,
        meta={"playwright": True, "playwright_include_page": True},
    )

async def parse(self, response):
    page = response.meta["playwright_page"]
    prev_count = 0
    while True:
        await page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
        await page.wait_for_timeout(2000)
        items = await page.query_selector_all(".item")
        if len(items) == prev_count:
            break
        prev_count = len(items)
    # Now parse the fully loaded page
    ...
```
