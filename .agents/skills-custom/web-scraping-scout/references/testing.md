# Test Generation

## Test Types

### 1. Unit Tests — Page Object Fixtures

Test PageObject parsing against saved HTML samples.

**Fixture creation flow:**
1. Fetch the target page (WebFetch or Playwright)
2. Save the HTML response to `<domain>/tests/fixtures/<page_type>.html`
3. Generate test that loads fixture and asserts PageObject output

**Generated test pattern:**
```python
import pytest
from pathlib import Path
from web_poet import HttpResponse, RequestUrl

from ..page_objects import ProductPage
from ..items import ProductItem


@pytest.fixture
def product_html():
    fixture_path = Path(__file__).parent / "fixtures" / "product_page.html"
    return fixture_path.read_text()


@pytest.fixture
def product_page(product_html):
    response = HttpResponse(
        url=RequestUrl("https://example.com/product/1"),
        body=product_html.encode(),
    )
    return ProductPage(response=response)


class TestProductPage:
    @pytest.mark.asyncio
    async def test_returns_product_item(self, product_page):
        item = await product_page.to_item()
        assert isinstance(item, ProductItem)

    @pytest.mark.asyncio
    async def test_name_not_empty(self, product_page):
        item = await product_page.to_item()
        assert item.name
        assert len(item.name) > 0

    @pytest.mark.asyncio
    async def test_price_is_positive(self, product_page):
        item = await product_page.to_item()
        assert item.price > 0

    @pytest.mark.asyncio
    async def test_url_is_valid(self, product_page):
        item = await product_page.to_item()
        assert item.url.startswith("http")

    @pytest.mark.asyncio
    async def test_all_required_fields_present(self, product_page):
        item = await product_page.to_item()
        for field_name, field_info in ProductItem.model_fields.items():
            if field_info.is_required():
                assert getattr(item, field_name) is not None, f"{field_name} is None"
```

### 2. Integration Tests — VCR Cassettes

Record real HTTP responses and replay them in tests.

**Setup:**
```python
# conftest.py
import pytest
import vcr

@pytest.fixture
def vcr_config():
    return {
        "cassette_library_dir": str(Path(__file__).parent / "cassettes"),
        "record_mode": "once",  # record first time, replay after
        "match_on": ["uri", "method"],
        "decode_compressed_response": True,
    }
```

**Generated test pattern:**
```python
import vcr
from scrapy.http import HtmlResponse
from pathlib import Path

CASSETTES = Path(__file__).parent / "cassettes"


class TestProductSpider:
    @vcr.use_cassette(str(CASSETTES / "product_list.yaml"))
    def test_spider_extracts_links(self):
        """Spider should find product links on listing page."""
        # Use the same HTTP client as the scraper (curl_cffi, not requests)
        # to ensure VCR cassettes match real TLS behavior.
        from curl_cffi.requests import Session

        spider = ProductSpider()
        url = "https://example.com/products"

        with Session() as s:
            resp = s.get(url, impersonate="chrome")
        response = HtmlResponse(url=url, body=resp.content)

        results = list(spider.parse(response))
        requests_out = [r for r in results if hasattr(r, "url")]
        assert len(requests_out) > 0, "Spider should generate follow requests"

    @vcr.use_cassette(str(CASSETTES / "product_detail.yaml"))
    def test_spider_extracts_item(self):
        """Spider should extract a valid item from detail page."""
        from curl_cffi.requests import Session

        spider = ProductSpider()
        url = "https://example.com/product/1"

        with Session() as s:
            resp = s.get(url, impersonate="chrome")
        response = HtmlResponse(url=url, body=resp.content)

        page = ProductPage(response=HttpResponse(
            url=RequestUrl(url), body=resp.content
        ))
        item = page.to_item()
        assert isinstance(item, ProductItem)
        assert item.name
```

## Test Generation Flow

0. **Ensure dev deps installed** — run `uv sync --extra dev` before running tests
1. **Identify what exists** — check which spiders and page objects are in the project
2. **Fetch sample pages** — get HTML for each page type the spider handles
3. **Save fixtures** — store HTML in `tests/fixtures/`
4. **Record cassettes** — if user wants integration tests, do a test crawl with VCR recording
5. **Generate test file** — write tests that cover:
   - Required fields are present and non-empty
   - Types are correct (price is float, not string)
   - URLs are valid
   - Lists have expected minimum items
   - Pagination produces follow requests
6. **Run tests** — execute `uv run pytest <domain>/tests/ -v` and report results

## Test Naming Convention

```
test_<page_object>_<what_it_tests>
test_product_page_extracts_name
test_product_page_price_is_positive
test_listing_page_finds_product_links
test_spider_follows_pagination
```
