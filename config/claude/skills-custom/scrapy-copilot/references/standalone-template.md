# Standalone Script Template

For simple scrapes (not Scrapy). Generate a single `.py` file with clear sections.

Every generated script includes:
- **loguru** for logging (see `references/utilities.md`)
- **stamina** for retry logic
- **fake-useragent** for UA rotation
- **pydantic** for data validation at output boundary

```python
"""Scrape [description] from [url]."""

import os
from pathlib import Path

from curl_cffi.requests import Session  # swappable: rnet, impit, primp
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


@retry(on=Exception, attempts=3)
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
    output = Path("output")
    output.mkdir(exist_ok=True)

    with Session() as session:
        session.headers.update({"User-Agent": ua.random})
        html = fetch(session, "https://example.com")
        items = parse(html, "https://example.com")

    logger.info(f"Scraped {len(items)} items")
    output_file = output / "results.jsonl"
    with open(output_file, "w") as f:
        for item in items:
            f.write(item.model_dump_json() + "\n")


if __name__ == "__main__":
    main()
```
