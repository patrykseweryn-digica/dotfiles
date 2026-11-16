# Items and page objects

## Items

Define items in `base/items.py` with `@attrs.define`. Do not inherit from
`zyte_common_items`. Why: its fixed schema couples the project to Zyte.

Each record type gets two items:

```python
import attrs


@attrs.define
class Book:  # record item: fields the user asked for
    url: str  # required
    title: str | None = None  # every other field is optional
    price: str | None = None


@attrs.define
class BookList:  # list item: crawl control only
    url: str
    item_urls: list[str] | None = None
    next_page_url: str | None = None
```

- The list item holds exactly `url`, `item_urls`, `next_page_url`. It never
  stores record data. Why: records come from detail pages only.
- Keep prices as decimal strings, not floats. Why: floats lose precision.
- When a field has a raw and a normalized form, keep both. Example:
  `currency_raw = "£"` and `currency = "GBP"`. Why: consumers can audit.

## Imports

```python
from web_poet import Returns, WebPage, field, handle_urls
```

`scrapy_poet` does not export these names.

## Files and names

- Put all page objects of one domain in `base/pages/<domain>.py`, for
  example `books_toscrape_com.py`. Why: a site redesign touches one file.
- Prefix class names with the domain: `BooksToscrapeBookPage`,
  `BooksToscrapeBookListPage`. Why: fixture directories use the class name,
  and two domains must never collide.
- When you rename a class, rename its fixture directory too.

## Page object

```python
@handle_urls("books.toscrape.com/catalogue/")
class BooksToscrapeBookPage(WebPage, Returns[Book]):
    @field
    def url(self) -> str:  # pyright: ignore[reportIncompatibleMethodOverride]
        return str(self.response.url)

    @field
    def title(self) -> str | None:
        return self.css("h1::text").get()
```

- Every data field uses `@field`. Never `@property`.
- Declare the item with `Returns[Item]`. Never define `to_item()`.
- `url` returns `str(self.response.url)`. Why: `response.url` is a
  `ResponseUrl` object, not a string. Keep the pyright comment: `WebPage`
  already has a `url` property, and the `@field` override is intended.
- Wrap `self.response.urljoin(...)` in `str()` too. It returns a
  `RequestUrl` object.
- Base class is `WebPage` unless Zyte API is on and the raw fixture lacks
  the data. Then use `BrowserPage`. See `fetching.md`.

## handle_urls

Pass one non-empty string that partially matches the URLs.

1. List and detail URLs differ by path: use a path prefix for each, for
   example `"site.com/shop/"` and `"site.com/products/"`.
2. No path difference: use `"site.com/*"` for both. scrapy-poet picks the
   page object by the `Returns[...]` type the callback asks for.

Never pass `""` or a list. Why: `""` causes registry conflicts, and a list
does not register at all.

## Stubs

Before `savefixture`, write each class with `pass` field bodies:

```python
    @field
    def title(self) -> str | None:
        pass
```

Why: `savefixture` imports the class, so the class must exist. `pass`
returns `None`. `raise NotImplementedError` breaks fixture saving and
crawls.
