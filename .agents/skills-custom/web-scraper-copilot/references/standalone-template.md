# Standalone Script Template

Default framework for web scrapers. Generate a project with clear structure.

## Recommended Project Structure

```
src/<project>/
├── __init__.py
├── __main__.py          # entry: from .scraper import main; main()
├── scraper.py           # core scraping logic
├── models.py            # Pydantic models
├── config.py            # search params, constants (optional)
└── analyze.py           # data analysis module (optional, see references/data-analysis.md)
```

With `pyproject.toml` (uv, hatchling), `.gitignore`, `outputs/` directory.

The 3 templates below are self-contained — copy one, then split out `Item` into `models.py`
and the JSONL writer into `storage.py` (see `references/storage.md` for export variants:
JSONL, CSV, TSV) once the project grows.

---

## Template 1: Sync API Scraper

For REST/GraphQL APIs with simple pagination. Pattern from Indeed-style scrapers.

```python
"""Scrape [description] from [API endpoint]."""

import random
import time
from pathlib import Path

from curl_cffi.requests import Session
from loguru import logger
from pydantic import BaseModel


API_URL = "https://example.com/api/items"
API_HEADERS = {
    "accept": "application/json",
    "user-agent": "Mozilla/5.0 ...",
}


class Item(BaseModel):
    """Define fields here."""
    id: str
    name: str
    url: str


def fetch_page(session: Session, offset: int = 0) -> dict:
    resp = session.get(
        API_URL,
        params={"offset": offset, "limit": 100},
        impersonate="chrome",
    )
    resp.raise_for_status()
    return resp.json()


def scrape_all(
    min_delay: float = 1.0,
    max_delay: float = 3.0,
    max_pages: int = 1000,
) -> list[Item]:
    seen_ids: set[str] = set()
    items: list[Item] = []

    with Session(headers=API_HEADERS) as session:
        offset = 0
        for page in range(max_pages):
            data = fetch_page(session, offset)
            results = data.get("results", [])
            if not results:
                break

            new_count = 0
            for raw in results:
                item = Item(**raw)
                if item.id not in seen_ids:
                    seen_ids.add(item.id)
                    items.append(item)
                    new_count += 1

            logger.info(f"Page {page} offset={offset}: {len(results)} results, {len(items)} total unique")
            if new_count == 0:
                break  # API returned only duplicates — likely looping

            offset += len(results)
            time.sleep(random.uniform(min_delay, max_delay))

    return items


def export(items: list[Item], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for item in items:
            f.write(item.model_dump_json() + "\n")
    logger.info(f"Exported {len(items)} items to {path}")


def main():
    logger.add("scrape.log", rotation="10 MB", serialize=True)
    items = scrape_all()
    export(items, Path("outputs/results.jsonl"))


if __name__ == "__main__":
    main()
```

---

## Template 2: Async API Scraper

For APIs requiring high throughput — two-phase pattern (list → detail).
Uses aiolimiter for rate limiting, semaphore for concurrency control, stamina for retries.

```python
"""Scrape [description] from [API endpoint]."""

import asyncio
from pathlib import Path

from aiolimiter import AsyncLimiter
from curl_cffi.requests import AsyncSession
from curl_cffi.requests.exceptions import RequestException
from fake_useragent import UserAgent
from loguru import logger
from pydantic import BaseModel
from stamina import retry

RATE_LIMIT = 10  # requests/second
CONCURRENCY = 20  # max parallel detail fetches
MAX_LISTING_PAGES = 1000
BASE_URL = "https://example.com/api"

ua = UserAgent()
limiter = AsyncLimiter(RATE_LIMIT, 1)


class Item(BaseModel):
    """Define fields here."""
    id: str
    name: str
    url: str
    description: str = ""


@retry(on=RequestException, attempts=3)
async def fetch(session: AsyncSession, url: str) -> dict:
    async with limiter:
        resp = await session.get(url, impersonate="chrome")
        resp.raise_for_status()
        return resp.json()


async def scrape_listings(session: AsyncSession) -> list[dict]:
    """Phase 1: Fetch lightweight listings with pagination."""
    all_items: list[dict] = []
    offset = 0

    for _ in range(MAX_LISTING_PAGES):
        data = await fetch(session, f"{BASE_URL}/items?offset={offset}&limit=100")
        results = data.get("results", [])
        if not results:
            break
        all_items.extend(results)
        logger.info(f"Listings: offset={offset}, total={len(all_items)}")
        offset += len(results)

    return all_items


async def scrape_detail(session: AsyncSession, sem: asyncio.Semaphore, item_id: str) -> dict | None:
    """Phase 2: Fetch full details for a single item."""
    async with sem:
        try:
            return await fetch(session, f"{BASE_URL}/items/{item_id}")
        except RequestException:
            logger.warning(f"Failed to fetch detail for {item_id}")
            return None


async def scrape_all() -> list[Item]:
    sem = asyncio.Semaphore(CONCURRENCY)

    async with AsyncSession(headers={"User-Agent": ua.random, "Referer": BASE_URL}) as session:
        # Phase 1: listings
        raw_listings = await scrape_listings(session)
        unique = {r["id"]: r for r in raw_listings}
        logger.info(f"Phase 1 done: {len(unique)} unique listings")

        # Phase 2: details (parallel with concurrency limit)
        tasks = [scrape_detail(session, sem, item_id) for item_id in unique]
        details = await asyncio.gather(*tasks)

    items = [Item(**d) for d in details if d]
    logger.info(f"Phase 2 done: {len(items)} items with details")
    return items


def export(items: list[Item], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for item in items:
            f.write(item.model_dump_json() + "\n")
    logger.info(f"Exported {len(items)} items to {path}")


def main():
    logger.add("scrape.log", rotation="10 MB", serialize=True)
    items = asyncio.run(scrape_all())
    export(items, Path("outputs/results.jsonl"))


if __name__ == "__main__":
    main()
```

---

## Template 3: HTML Scraper (sync)

For pages without API — classic HTML parsing with selectors.

```python
"""Scrape [description] from [url]."""

from pathlib import Path

from curl_cffi.requests import Session
from curl_cffi.requests.exceptions import RequestException
from fake_useragent import UserAgent
from loguru import logger
from parsel import Selector  # swappable: selectolax, Scrapling
from pydantic import BaseModel
from stamina import retry

ua = UserAgent()


class Item(BaseModel):
    """Define fields here."""
    name: str
    url: str


@retry(on=RequestException, attempts=3)
def fetch(session: Session, url: str) -> str:
    resp = session.get(url, impersonate="chrome")
    resp.raise_for_status()
    return resp.text


def parse(html: str, url: str) -> list[Item]:
    sel = Selector(text=html)
    items = []
    for el in sel.css(".item"):
        items.append(Item(
            name=el.css("h2::text").get(""),
            url=url,
        ))
    return items


def main():
    logger.add("scrape.log", rotation="10 MB", serialize=True)
    output = Path("outputs")
    output.mkdir(exist_ok=True)

    with Session() as session:
        session.headers.update({"User-Agent": ua.random})
        html = fetch(session, "https://example.com")
        items = parse(html, "https://example.com")

    logger.info(f"Scraped {len(items)} items")
    with open(output / "results.jsonl", "w") as f:
        for item in items:
            f.write(item.model_dump_json() + "\n")


if __name__ == "__main__":
    main()
```
