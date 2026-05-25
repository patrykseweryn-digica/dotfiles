# Data Analysis Module

Optional module for analyzing scraped data. Add as `src/<project>/analyze.py` or `src/<project>/analyze/` package.

## Quick Analysis (single file)

Simple filtering, stats, aggregations on JSONL output.

```python
"""Analyze scraped data."""

from pathlib import Path
from typing import TypeVar

from loguru import logger
from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


def load_items(path: Path, model: type[T]) -> list[T]:
    with open(path) as f:
        items = [model.model_validate_json(line) for line in f if line.strip()]
    logger.info(f"Loaded {len(items)} items from {path}")
    return items


def filter_items(items: list[T], **kwargs) -> list[T]:
    """Filter items by field values. AND between params, OR within lists."""
    def matches(item: T) -> bool:
        for field, value in kwargs.items():
            actual = getattr(item, field, None)
            if isinstance(value, list):
                if actual not in value:
                    return False
            elif actual != value:
                return False
        return True
    return [i for i in items if matches(i)]
```

## DuckDB Analysis (multi-file, SQL)

For larger datasets — load JSONL/TSV into DuckDB, run SQL. No database server needed.

```python
"""Analyze scraped data with DuckDB."""

import re
from pathlib import Path

import duckdb
from loguru import logger

READERS = {
    ".jsonl": ("read_json_auto", {}),
    ".csv": ("read_csv_auto", {"sep": ","}),
    ".tsv": ("read_csv_auto", {"sep": "\t"}),
}


def load(paths: list[Path], table: str = "items") -> duckdb.DuckDBPyConnection:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", table):
        raise ValueError(f"Invalid table name: {table!r}")

    con = duckdb.connect()
    for i, path in enumerate(paths):
        reader, opts = READERS[path.suffix]
        opt_args = "".join(f", {k}=?" for k in opts)
        select = f"SELECT * FROM {reader}(?{opt_args})"
        params = [str(path), *opts.values()]
        if i == 0:
            con.execute(f"CREATE OR REPLACE TABLE {table} AS {select}", params)
        else:
            con.execute(f"INSERT INTO {table} {select}", params)
    count = con.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
    logger.info(f"Loaded {count} rows into {table}")
    return con


def dedup(con: duckdb.DuckDBPyConnection, table: str, key: str) -> None:
    con.execute(f"""
        CREATE OR REPLACE TABLE {table} AS
        SELECT DISTINCT ON ({key}) * FROM {table}
    """)
```

## Rich Terminal Output

```python
from rich.console import Console
from rich.table import Table


def print_table(rows: list[dict], title: str = "") -> None:
    if not rows:
        return
    table = Table(title=title)
    for col in rows[0]:
        table.add_column(col)
    for row in rows:
        table.add_row(*[str(v) for v in row.values()])
    Console().print(table)
```

## Plotly HTML Dashboards

```python
import webbrowser
from pathlib import Path

import plotly.graph_objects as go
from plotly.subplots import make_subplots


def render_dashboard(data: dict, output: Path) -> None:
    fig = make_subplots(rows=2, cols=2, subplot_titles=list(data.keys()))

    for i, (title, values) in enumerate(data.items()):
        row, col = divmod(i, 2)
        fig.add_trace(
            go.Bar(x=list(values.keys()), y=list(values.values()), name=title),
            row=row + 1, col=col + 1,
        )

    fig.update_layout(height=800, showlegend=False)
    fig.write_html(str(output))
    webbrowser.open(str(output))
```

## Dependencies

Add to `pyproject.toml` as needed:
- `duckdb` — SQL analytics on JSONL/CSV/TSV
- `rich` — terminal tables and formatting
- `plotly` — interactive HTML charts
- `numpy` — numerical operations (if scoring/stats needed)
