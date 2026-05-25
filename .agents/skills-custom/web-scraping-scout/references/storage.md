# Storage Backends

After generating the scraper, ask: "Where do you want to save the scraped data?"
Default is JSONL.

## Standalone Scripts

### JSONL (default)

```python
from pathlib import Path

def export_jsonl(items: list, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for item in items:
            f.write(item.model_dump_json() + "\n")
```

### TSV / CSV

```python
import csv
from pathlib import Path

def export_tsv(items: list, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not items:
        return
    fields = list(items[0].model_fields.keys())
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for item in items:
            writer.writerow(item.model_dump())
```

Replace `delimiter="\t"` with `delimiter=","` for CSV.

---

## Scrapy Backends

### JSONL (default — already configured)
No changes needed. Output goes to `output/<spider>/<timestamp>.jsonl`.

### CSV
```python
# settings.py
FEEDS = {
    "output/%(name)s/%(time)s.csv": {
        "format": "csv",
        "encoding": "utf-8",
    },
}
```

### SQLite (local dev)

Generate a pipeline:
```python
# pipelines.py
import sqlite3
from pathlib import Path


class SQLitePipeline:
    def open_spider(self, spider):
        db_path = Path("output") / f"{spider.name}.db"
        db_path.parent.mkdir(exist_ok=True)
        self.conn = sqlite3.connect(str(db_path))
        self.cursor = self.conn.cursor()

    def close_spider(self, spider):
        self.conn.commit()
        self.conn.close()

    def process_item(self, item, spider):
        data = dict(item)
        columns = ", ".join(data.keys())
        placeholders = ", ".join(["?"] * len(data))
        self.cursor.execute(
            f"CREATE TABLE IF NOT EXISTS items ({', '.join(f'{k} TEXT' for k in data.keys())})"
        )
        self.cursor.execute(
            f"INSERT INTO items ({columns}) VALUES ({placeholders})",
            list(data.values()),
        )
        return item
```

Enable in settings:
```python
ITEM_PIPELINES = {
    "pipelines.SQLitePipeline": 300,
}
```

### PostgreSQL

Add dependency: `uv add psycopg2-binary`

Generate a pipeline:
```python
# pipelines.py
import os
import psycopg2

class PostgresPipeline:
    def open_spider(self, spider):
        self.conn = psycopg2.connect(os.environ["DATABASE_URL"])
        self.cursor = self.conn.cursor()

    def close_spider(self, spider):
        self.conn.commit()
        self.conn.close()

    def process_item(self, item, spider):
        data = dict(item)
        columns = ", ".join(data.keys())
        placeholders = ", ".join(["%s"] * len(data))
        self.cursor.execute(
            f"INSERT INTO {spider.name} ({columns}) VALUES ({placeholders})"
            f" ON CONFLICT DO NOTHING",
            list(data.values()),
        )
        return item
```

Add to `.env.template`:
```
DATABASE_URL=postgresql://user:pass@localhost:5432/scraping
```

### Parquet (for data analysis)

Add dependency: `uv add pandas pyarrow`

```python
# pipelines.py
import pandas as pd
from pathlib import Path


class ParquetPipeline:
    def open_spider(self, spider):
        self.items = []

    def close_spider(self, spider):
        if self.items:
            df = pd.DataFrame(self.items)
            output = Path("output") / f"{spider.name}.parquet"
            output.parent.mkdir(exist_ok=True)
            df.to_parquet(str(output), index=False)

    def process_item(self, item, spider):
        self.items.append(dict(item))
        return item
```

### S3

Add dependency: `uv add boto3`

Use Scrapy's built-in S3 feed export:
```python
# settings.py
FEEDS = {
    "s3://my-bucket/scrapy/%(name)s/%(time)s.jsonl": {
        "format": "jsonlines",
    },
}
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY")
```

## Multiple Backends

Scrapy supports multiple FEEDS and pipelines simultaneously:
```python
FEEDS = {
    "output/%(name)s/%(time)s.jsonl": {"format": "jsonlines"},  # local backup
    "s3://bucket/%(name)s/%(time)s.jsonl": {"format": "jsonlines"},  # cloud
}
ITEM_PIPELINES = {
    "pipelines.PostgresPipeline": 300,  # also save to DB
}
```
