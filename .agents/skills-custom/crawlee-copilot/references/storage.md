# Storage Backends

## Default: Crawlee push_data (JSONL)

```python
@crawler.router.default_handler
async def handler(context: BeautifulSoupCrawlingContext) -> None:
    await context.push_data({
        "url": context.request.url,
        "title": context.soup.title.string,
    })

# Export after crawling
await crawler.export_data(path="output/results.json")    # JSON
await crawler.export_data(path="output/results.csv")      # CSV
```

## Named Datasets

```python
from crawlee.storages import Dataset

products = await Dataset.open(name="products")
errors = await Dataset.open(name="errors")

@crawler.router.default_handler
async def handler(context: BeautifulSoupCrawlingContext) -> None:
    try:
        data = extract_product(context.soup)
        await products.push_data(data)
    except Exception as e:
        await errors.push_data({"url": context.request.url, "error": str(e)})
```

## KeyValueStore (metadata, screenshots, HTML snapshots)

```python
from crawlee.storages import KeyValueStore

kvs = await KeyValueStore.open(name="snapshots")

@crawler.router.default_handler
async def handler(context: PlaywrightCrawlingContext) -> None:
    screenshot = await context.page.screenshot()
    await kvs.set_value(f"screenshot-{context.request.id}", screenshot, content_type="image/png")
    await kvs.set_value(f"html-{context.request.id}", await context.page.content(), content_type="text/html")
```

## JSONL (manual)

```python
import json
from pathlib import Path

output_path = Path("output/results.jsonl")
output_path.parent.mkdir(exist_ok=True)

@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    data = {"url": context.request.url, "title": context.selector.css("title::text").get()}
    with output_path.open("a") as f:
        f.write(json.dumps(data, ensure_ascii=False) + "\n")
```

## CSV

```python
import csv
from pathlib import Path

output_path = Path("output/results.csv")
fieldnames = ["url", "title", "price"]

@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    data = {
        "url": context.request.url,
        "title": context.selector.css("title::text").get(),
        "price": context.selector.css(".price::text").get(),
    }
    file_exists = output_path.exists()
    with output_path.open("a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if not file_exists:
            writer.writeheader()
        writer.writerow(data)
```

## SQLite

```python
import sqlite3
from contextlib import closing

DB_PATH = "output/results.db"

def init_db():
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS items (
                url TEXT PRIMARY KEY,
                title TEXT,
                price REAL,
                crawled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    data = {
        "url": context.request.url,
        "title": context.selector.css("title::text").get(),
        "price": context.selector.css(".price::text").get(),
    }
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute(
            "INSERT OR REPLACE INTO items (url, title, price) VALUES (?, ?, ?)",
            (data["url"], data["title"], data["price"]),
        )
        conn.commit()
```

## PostgreSQL

```python
import asyncpg
import os

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/scraping")

async def init_db():
    conn = await asyncpg.connect(DATABASE_URL)
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS items (
            url TEXT PRIMARY KEY,
            title TEXT,
            price NUMERIC,
            crawled_at TIMESTAMP DEFAULT NOW()
        )
    """)
    await conn.close()

pool = None

async def get_pool():
    global pool
    if pool is None:
        pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=10)
    return pool

@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    data = {
        "url": context.request.url,
        "title": context.selector.css("title::text").get(),
        "price": context.selector.css(".price::text").get(),
    }
    p = await get_pool()
    async with p.acquire() as conn:
        await conn.execute(
            """INSERT INTO items (url, title, price)
               VALUES ($1, $2, $3)
               ON CONFLICT (url) DO UPDATE SET title=$2, price=$3, crawled_at=NOW()""",
            data["url"], data["title"], data["price"],
        )
```

## Parquet (for data analysis)

```python
import pandas as pd
from pathlib import Path

items: list[dict] = []

@crawler.router.default_handler
async def handler(context: ParselCrawlingContext) -> None:
    items.append({
        "url": context.request.url,
        "title": context.selector.css("title::text").get(),
    })

# After crawling:
df = pd.DataFrame(items)
df.to_parquet("output/results.parquet", index=False)
```
