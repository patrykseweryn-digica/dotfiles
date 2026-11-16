# Production layer

Add these parts only when the user asks for production output. The default
project already has sample and full modes and one JSONL file per run.

## Data stages

Follow `../web-scraping-references/references/lifecycle.md` and
`storage-policy.md` in the same folder:

- manifest, parsed output, curated output, audit output per run
- stable IDs, source URL, fetched timestamp, run ID, schema version
- raw samples and failures for replay

Implement each stage as an item pipeline or a Scrapy extension, not as
code in the spider. Write an operator runbook from
`../web-scraping-references/references/operator-runbook.md`.

## Structured logs (structlog)

`uv add structlog`

Scrapy logs through the standard `logging` module and builds its root
log formatter from the `LOG_ROOT_FORMATTER` setting. Point that setting at
a structlog formatter. Scrapy's `LOG_LEVEL`, `LOG_FILE`, and the closing
stats dump keep working. Do not set `LOG_ENABLED = False`.

```python
# base/logs.py
import uuid

import structlog

SHARED = [
    structlog.contextvars.merge_contextvars,
    structlog.stdlib.add_logger_name,
    structlog.stdlib.add_log_level,
    structlog.processors.TimeStamper(fmt="iso", utc=True),
]


def structlog_formatter(settings) -> structlog.stdlib.ProcessorFormatter:
    """Scrapy LOG_ROOT_FORMATTER: JSON lines when LOG_JSON=True."""
    structlog.configure(
        processors=[*SHARED, structlog.stdlib.ProcessorFormatter.wrap_for_formatter],
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )
    structlog.contextvars.bind_contextvars(run_id=uuid.uuid4().hex)
    renderer = (
        structlog.processors.JSONRenderer()
        if settings.getbool("LOG_JSON")
        else structlog.dev.ConsoleRenderer()
    )
    return structlog.stdlib.ProcessorFormatter(
        foreign_pre_chain=SHARED,
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            renderer,
        ],
    )
```

```python
# settings.py
LOG_ROOT_FORMATTER = "base.logs.structlog_formatter"
LOG_JSON = False  # production: -s LOG_JSON=True -s LOG_COLOR=False
```

Log your own events with fields:

```python
log = structlog.get_logger(__name__)
log.info("item_dropped", url=item.url, reason="no_price")
```

## SQLite output (opt-in)

Add only when the user asks for SQLite. Otherwise feeds write JSONL.

- Store record items only. Pass list items through unchanged.
- Read the path from `SQLITE_DB_PATH`, default `output.db`. Build the
  pipeline in `from_crawler`.
- One column per item field. Declare `url TEXT UNIQUE` next to an
  autoincrement `id`. Store list fields as JSON strings.
- Define `open_spider`, `close_spider`, and `process_item` without a
  `spider` argument. Why: Scrapy deprecates it.
- Use one connection and `INSERT OR REPLACE`. Why: SQLite has one writer.

```python
import json
import sqlite3

import attrs

from base.items import Book


class SQLitePipeline:
    def __init__(self, path: str) -> None:
        self.path = path
        self.names = [f.name for f in attrs.fields(Book)]

    @classmethod
    def from_crawler(cls, crawler):
        return cls(crawler.settings.get("SQLITE_DB_PATH", "output.db"))

    def open_spider(self) -> None:
        self.db = sqlite3.connect(self.path)
        cols = ", ".join(
            "url TEXT UNIQUE" if n == "url" else f"{n} TEXT" for n in self.names
        )
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS books "
            f"(id INTEGER PRIMARY KEY AUTOINCREMENT, {cols})"
        )

    def close_spider(self) -> None:
        self.db.commit()
        self.db.close()

    def process_item(self, item):
        if not isinstance(item, Book):
            return item
        values = [
            json.dumps(v) if isinstance(v, list) else v
            for v in attrs.astuple(item, recurse=False)
        ]
        marks = ", ".join("?" for _ in self.names)
        self.db.execute(
            f"INSERT OR REPLACE INTO books ({', '.join(self.names)}) VALUES ({marks})",
            values,
        )
        return item
```

## Deploy

Docker, cron, stats JSON, and alerts belong to `scrapy-deploy`.
