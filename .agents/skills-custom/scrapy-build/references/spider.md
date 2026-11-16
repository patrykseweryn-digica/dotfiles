# Spider

One spider per record type. All domains for that record share the spider.

```python
from typing import ClassVar

import scrapy

from base.items import Book, BookList


class BooksSpider(scrapy.Spider):
    name = "books"
    allowed_domains = ("books.toscrape.com",)
    urls: ClassVar[list[str]] = [
        "https://books.toscrape.com/catalogue/category/books_1/index.html",
    ]

    async def start(self):
        for url in self.urls:
            yield scrapy.Request(url, callback=self.parse)

    async def parse(self, response, listing: BookList):
        for url in listing.item_urls or []:
            yield response.follow(url, callback=self.parse_item)
        if listing.next_page_url:
            yield response.follow(listing.next_page_url, callback=self.parse)

    async def parse_item(self, _, item: Book):
        yield item
```

- Import items only, never page objects. Why: scrapy-poet finds the page
  object through `handle_urls`, so the spider never names a domain.
- Make every callback `async def`.
- Use `async def start()` with a `urls` list, not `start_urls`. Why: a new
  start URL is one list entry with no logic change.
- Use `scrapy.Request` only in `start()`. Use `response.follow()` in
  callbacks. Why: `follow` resolves relative URLs.
- Name an unused response parameter `_`. Do not use `DummyResponse`.
- Write `allowed_domains` as a tuple and annotate `urls` with `ClassVar`.
  Why: ruff rejects mutable class defaults, and pyright rejects
  `ClassVar` on `allowed_domains`, which `Spider` declares itself.

## Adding a domain

1. Write the domain's page objects and fixtures (creation flow steps 5-7).
   Start the domain at fetch tier 1.
2. Append start URLs to `urls`.
3. Add the hostname to `allowed_domains`.
4. Update `CONCURRENT_REQUESTS` in `settings.py` for the new domain count.
5. Rename the spider class and file if the name no longer fits its scope.
