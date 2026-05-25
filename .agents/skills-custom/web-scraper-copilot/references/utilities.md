# Utilities

Core libraries (loguru, stamina, fake-useragent) go in every scraper.
Others (dateparser, ftfy, price-parser) — add when the scraper needs them.

## loguru — Logging

Zero-config, async-safe, built-in rotation. Default choice for all scrapers.

```bash
uv add loguru
```

```python
from loguru import logger

# Console output works immediately (colored, formatted)
logger.info("Starting scrape")
logger.warning("Rate limited, retrying...")

# Add file logging with rotation + JSON
logger.add("scrape.log", rotation="10 MB", serialize=True)

# Add context
logger.bind(url=url, page=page_num).info("Scraped page")
```

### Scrapy integration

See `references/scrapy-integration.md` for loguru routing in Scrapy.

---

## stamina — Retry

Opinionated wrapper around tenacity with production defaults: exponential backoff + jitter.

```bash
uv add stamina
```

```python
from stamina import retry

@retry(on=Exception, attempts=3)
def fetch(session, url):
    resp = session.get(url, impersonate="chrome")
    resp.raise_for_status()
    return resp.text

# Async
@retry(on=Exception, attempts=3)
async def async_fetch(session, url):
    resp = await session.get(url, impersonate="chrome")
    resp.raise_for_status()
    return resp.text
```

For custom retry logic (specific status codes, custom waits), use **tenacity** directly:
```python
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_result

@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(min=1, max=30),
    retry=retry_if_result(lambda r: r.status_code == 429),
)
def fetch_with_backoff(session, url):
    return session.get(url, impersonate="chrome")
```

---

## fake-useragent — UA Rotation

326k+ real user agents from real browser distributions.

```bash
uv add fake-useragent
```

```python
from fake_useragent import UserAgent

ua = UserAgent()
headers = {"User-Agent": ua.random}

# Filter by browser
ua.chrome  # random Chrome UA
ua.firefox  # random Firefox UA
```

Include in every scraper. Trivial to add, reduces detection.

---

## aiolimiter — Rate Limiting

Async leaky bucket rate limiter. Use when you need per-domain throttling.

```bash
uv add aiolimiter
```

```python
from aiolimiter import AsyncLimiter

# 10 requests per second
limiter = AsyncLimiter(10, 1)

async def fetch(session, url):
    async with limiter:
        return await session.get(url, impersonate="chrome")
```

For sync code or persistent rate limiting across restarts, use **pyrate-limiter**:
```bash
uv add pyrate-limiter
```

---

## price-parser — Price Extraction

Extracts price + currency from any format. Essential for e-commerce scraping.

```bash
uv add price-parser
```

```python
from price_parser import Price

price = Price.fromstring("$19.99")
# price.amount = Decimal('19.99'), price.currency = '$'

price = Price.fromstring("22,90 EUR")
# price.amount = Decimal('22.90'), price.currency = 'EUR'

price = Price.fromstring("1.299.000 VND")
# price.amount = Decimal('1299000'), price.currency = 'VND'
```

---

## dateparser — Date Parsing (200+ languages)

Parses human-readable dates in 200+ languages, including relative dates.
More powerful than python-dateutil — handles "3 days ago", "przed 2 godzinami",
"hace 3 días", informal formats.

```bash
uv add dateparser
```

```python
import dateparser

dateparser.parse("March 5th, 2025")          # datetime(2025, 3, 5)
dateparser.parse("3 days ago")               # relative → absolute datetime
dateparser.parse("przed 2 godzinami")        # Polish
dateparser.parse("hace 3 días")              # Spanish
dateparser.parse("il y a 5 minutes")         # French

# With settings
dateparser.parse("in 2 days", settings={"PREFER_DATES_FROM": "future"})

# Search dates in text
from dateparser.search import search_dates
search_dates("Posted on March 5 and updated June 10")
# [('March 5', datetime(...)), ('June 10', datetime(...))]
```

---

## ftfy — Unicode Fixing

Fixes garbled Unicode (mojibake) from incorrectly decoded web pages. Essential for
international scraping. Zero config — one function call.

```bash
uv add ftfy
```

```python
import ftfy

ftfy.fix_text("Ã©clair")           # "éclair"
ftfy.fix_text("â€\x9cquotedâ€\x9d")  # '"quoted"'
ftfy.fix_text("&amp;amp; hi")      # "& hi"

# Use in a Pydantic model validator for automatic cleanup
from pydantic import field_validator

class Item(BaseModel):
    name: str

    @field_validator("name")
    @classmethod
    def fix_unicode(cls, v: str) -> str:
        return ftfy.fix_text(v)
```

Apply to scraped text fields when source pages have mixed/broken encodings.

---

## w3lib — Web Utilities

URL normalization, HTML cleaning, encoding detection. From the Scrapy ecosystem.

```bash
uv add w3lib
```

```python
from w3lib.html import remove_tags, replace_entities
from w3lib.url import canonicalize_url

clean = remove_tags("<p>Hello <b>world</b></p>")  # "Hello world"
url = canonicalize_url("https://Example.Com/path/../page?b=2&a=1")
```

---

## Standard Dependencies Block

For `pyproject.toml` — include in every scraper project:

```toml
dependencies = [
    "curl_cffi>=0.14",
    "parsel>=1.9",
    "pydantic>=2.0",
    "loguru>=0.7",
    "stamina>=2.0",
    "fake-useragent>=2.0",
    "w3lib>=2.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=1.0",
    "ruff>=0.4",
    "pyright>=1.1",
]
parsing = [
    "chompjs>=1.4",
    "jmespath>=1.0",
    "extruct>=0.17",
    "price-parser>=0.5",
    "dateparser>=1.2",
    "ftfy>=6.0",
]
browser = [
    "pydoll-python>=2.0",
]
scrapy = [
    "scrapy>=2.11",
    "scrapy-poet>=0.24",
    "web-poet>=0.17",
    "itemloaders>=1.3",
]
```
