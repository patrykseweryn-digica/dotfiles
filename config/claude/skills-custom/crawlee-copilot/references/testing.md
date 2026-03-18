# Testing

## Test Types

1. **Unit tests** — Test handlers against saved HTML fixtures
2. **Integration tests** — Test full crawl with VCR cassettes (recorded HTTP responses)
3. **Model tests** — Test Pydantic model validation

## Dependencies

```toml
[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.24",
    "vcrpy>=6.0",
]
```

## Unit Tests (HTML Fixtures)

### Step 1: Save HTML fixtures during development

```python
# Save a page's HTML for testing
from pathlib import Path

fixture_dir = Path("tests/fixtures")
fixture_dir.mkdir(parents=True, exist_ok=True)

@crawler.router.default_handler
async def handler(context: BeautifulSoupCrawlingContext) -> None:
    # Save fixture (remove in production)
    fixture_path = fixture_dir / f"{context.request.url.split('/')[-1]}.html"
    fixture_path.write_text(str(context.soup), encoding="utf-8")
    # ... normal handler logic
```

### Step 2: Write tests against fixtures

```python
# tests/test_handlers.py
import pytest
from pathlib import Path
from bs4 import BeautifulSoup

FIXTURES = Path(__file__).parent / "fixtures"

def load_fixture(name: str) -> BeautifulSoup:
    html = (FIXTURES / name).read_text(encoding="utf-8")
    return BeautifulSoup(html, "lxml")


class TestListingHandler:
    def test_extracts_product_links(self):
        soup = load_fixture("listing.html")
        links = [a["href"] for a in soup.select(".product-link")]
        assert len(links) > 0
        assert all(link.startswith("/") or link.startswith("http") for link in links)

    def test_extracts_pagination(self):
        soup = load_fixture("listing.html")
        next_link = soup.select_one('a[rel="next"]')
        assert next_link is not None


class TestDetailHandler:
    def test_extracts_title(self):
        soup = load_fixture("detail.html")
        title = soup.select_one("h1")
        assert title is not None
        assert title.get_text(strip=True)

    def test_extracts_price(self):
        soup = load_fixture("detail.html")
        price = soup.select_one(".price")
        assert price is not None
```

### For ParselCrawler (CSS/XPath):

```python
from parsel import Selector

def load_selector(name: str) -> Selector:
    html = (FIXTURES / name).read_text(encoding="utf-8")
    return Selector(text=html)

class TestDetailHandler:
    def test_extracts_title(self):
        sel = load_selector("detail.html")
        title = sel.css("h1::text").get()
        assert title is not None
```

## Integration Tests (VCR Cassettes)

Record HTTP responses and replay them in tests.

```python
# tests/test_integration.py
import pytest
import vcr
from crawlee.crawlers import ParselCrawler, ParselCrawlingContext

CASSETTES = Path(__file__).parent / "cassettes"

@vcr.use_cassette(str(CASSETTES / "example_crawl.yaml"), record_mode="once")
@pytest.mark.asyncio
async def test_full_crawl():
    results = []

    crawler = ParselCrawler(max_requests_per_crawl=5)

    @crawler.router.default_handler
    async def handler(context: ParselCrawlingContext) -> None:
        results.append({
            "url": context.request.url,
            "title": context.selector.css("title::text").get(),
        })

    await crawler.run(["https://example.com"])

    assert len(results) > 0
    assert all(r["title"] for r in results)
```

## Model Tests

```python
# tests/test_models.py
import pytest
from src.models import Product

class TestProductModel:
    def test_valid_product(self):
        product = Product(
            url="https://example.com/product/1",
            name="Widget",
            price=9.99,
        )
        assert product.name == "Widget"
        assert product.price == 9.99

    def test_missing_required_field(self):
        with pytest.raises(Exception):
            Product(url="https://example.com", name="")  # Empty name

    def test_optional_fields_default(self):
        product = Product(url="https://example.com", name="Widget")
        assert product.price is None
        assert product.images == []
```

## Test Generation Flow

1. Run crawler on target with `--save-fixtures` flag or manual HTML saving
2. Identify distinct page types (listing, detail, etc.)
3. Save 2-3 representative HTML pages per type
4. Generate unit tests per handler
5. Record VCR cassette for integration test
6. Run: `uv run pytest -v`

## Running Tests

```bash
uv run pytest -v                  # All tests
uv run pytest tests/test_handlers.py  # Only handler tests
uv run pytest -k "test_detail"   # Filter by name
```
