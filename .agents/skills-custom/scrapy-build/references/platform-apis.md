# Platform APIs

Probe only sites that sell products. One probe costs one request, so
probe when unsure. Before you write HTML selectors for a shop's listing
page, probe for these platforms. If one matches, the list page
object parses JSON with `json.loads(self.response.body)`. Probe through `savefixture` only.

Helpers used below:

```python
import json
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse


def with_param(url: str, key: str, value: int) -> str:
    parsed = urlparse(url)
    params = {
        k: v[0] for k, v in parse_qs(parsed.query, keep_blank_values=True).items()
    }
    params[key] = str(value)
    return urlunparse(parsed._replace(query=urlencode(params)))
```

## Shopify

Detect: write the stub list page object with
`@handle_urls("<domain>/products.json")`, then:

```bash
uv run scrapy savefixture base.pages.<file>.<Prefix>BookListPage \
  "https://<domain>/products.json?limit=250"
```

- Body is JSON with a `"products"` array: the site is Shopify. Keep the
  fixture; it is the list page fixture.
- Anything else, or a failure: not Shopify. A 404 saves no directory;
  delete a directory only if one was saved. Switch `handle_urls` to the
  HTML listing pattern and use HTML.

```python
@handle_urls("example.com/products.json")
class ExampleBookListPage(WebPage, Returns[BookList]):
    @field
    def item_urls(self) -> list[str] | None:
        data = json.loads(self.response.body)
        parsed = urlparse(str(self.response.url))
        base = f"{parsed.scheme}://{parsed.netloc}"
        return [
            f"{base}/products/{p['handle']}" for p in data.get("products", [])
        ] or None

    @field
    def next_page_url(self) -> str | None:
        data = json.loads(self.response.body)
        if len(data.get("products", [])) < 250:
            return None
        url = str(self.response.url)
        page = int(parse_qs(urlparse(url).query).get("page", ["1"])[0])
        return with_param(url, "page", page + 1)
```

- Start URL: `https://<domain>/products.json?limit=250`.
- Paginate with `page=N` until a page has fewer than 250 products.
- Never use `since_id`. Why: stores sort by "featured", not by ID, so
  `since_id` repeats the same products.

## Ecwid

Detect: search the raw HTML listing fixture for `ecwidStoreID`. Search the
raw `<Response>-body.html`. Why: clear-html strips the `<script>` tags
that hold it.

- Store ID: `ecwidStoreID = "..."`, or the number in CDN image URLs
  `d2j6dbq0eux0bg.cloudfront.net/images/{storeId}/...`.
- Public token: first `public_[A-Za-z0-9]+` not scoped to a named app. If
  none exists, use the one under `appsPublicTokens`.
- Category ID: class `ecwid-productBrowser-CategoryPage-{categoryId}`.
- Start URL: `https://app.ecwid.com/api/v3/{storeId}/products?categoryId={categoryId}&enabled=true&limit=100&token={publicToken}`.
  Save the list fixture against this URL.
- `handle_urls`: `"app.ecwid.com/api/v3/{storeId}/products"`. Add
  `app.ecwid.com` to `allowed_domains`.

```python
    @field
    def item_urls(self) -> list[str] | None:
        data = json.loads(self.response.body)
        return [i["url"] for i in data.get("items", []) if i.get("url")] or None

    @field
    def next_page_url(self) -> str | None:
        data = json.loads(self.response.body)
        offset, count = data.get("offset", 0), data.get("count", 0)
        total, limit = data.get("total", 0), data.get("limit", 100)
        if offset + count >= total:
            return None
        return with_param(str(self.response.url), "offset", offset + limit)
```

## No platform found

Use HTML selectors on `WebPage`. Climb the fetch ladder only with evidence.
