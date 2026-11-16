# Project setup

## Layout

```
<root>/
├── pyproject.toml
├── scrapy.cfg
├── .gitignore
├── scripts/clean_fixture.py        # copied from this skill, never rewritten
├── base/                           # all source lives in the project package
│   ├── settings.py
│   ├── items.py
│   ├── middlewares.py              # only when a fetch tier needs one
│   ├── pipelines.py
│   ├── pages/__init__.py
│   ├── pages/<domain>.py           # one file per domain
│   └── spiders/<record>.py         # one spider per record type
├── tests/fixtures/<page-object-fqn>/test-N/
└── output/<spider>/<time>.jsonl
```

Name the package `base` unless the user gives a name. Why: domain names
belong to page objects and spiders, so the scaffold stays reusable.

## Create (step 1)

```bash
uv init --bare
uv add scrapy scrapy-poet web-poet attrs clear-html
uv add --dev pytest ruff pyright
uv run scrapy startproject base .
mkdir -p scripts && cp <skill-dir>/scripts/clean_fixture.py scripts/
printf '.venv/\n__pycache__/\n.pytest_cache/\n.ruff_cache/\noutput/\n' > .gitignore
```

Append this section at the end of `pyproject.toml`:

```toml
[tool.pytest.ini_options]
pythonpath = ["."]
```

Why: pytest must import `base` while it collects fixture tests.

Add fetch-tier packages only when that tier is chosen (`fetching.md`).
`clear-html` is a direct dependency because `clean_fixture.py` imports it.

## Replace templates (step 2)

`startproject` writes template code that conflicts with this method:

- `items.py`: delete the template item. Step 3 writes the real items.
- `middlewares.py`: delete the file. The template classes use the
  deprecated `spider` argument. Create the file again only for a fetch
  tier.
- `pipelines.py`: delete the template pipeline and its unused import.
- `settings.py`: replace the template `ADDONS = {}`,
  `CONCURRENT_REQUESTS_PER_DOMAIN`, and `DOWNLOAD_DELAY` with the values
  below. Keep one assignment per setting.

## settings.py

```python
ADDONS = {
    "scrapy_poet.Addon": 300,
}
SCRAPY_POET_DISCOVER = ["base.pages"]
SCRAPY_POET_TESTS_DIR = "tests/fixtures"
ROBOTSTXT_OBEY = True

# Direct fetch (no Zyte API): stay polite, the site sees every request.
CONCURRENT_REQUESTS_PER_DOMAIN = 8
CONCURRENT_REQUESTS = 8 * 1  # 8 x number of domains; update per domain
DOWNLOAD_DELAY = 0.5  # AutoThrottle lower bound
AUTOTHROTTLE_ENABLED = True
AUTOTHROTTLE_START_DELAY = 1
AUTOTHROTTLE_MAX_DELAY = 30
AUTOTHROTTLE_TARGET_CONCURRENCY = 2.0
```

- `ADDONS` wires middlewares and the request fingerprinter. Do not set
  `DOWNLOADER_MIDDLEWARES`, `SPIDER_MIDDLEWARES`, or
  `REQUEST_FINGERPRINTER_CLASS` for scrapy-poet by hand. Why: the addon
  owns the order, and manual copies break when the package changes.
- Without `SCRAPY_POET_DISCOVER`, page objects never register and
  injection silently does nothing.
- Without `SCRAPY_POET_TESTS_DIR`, `savefixture` writes `fixtures/` at the
  root, outside `tests/`.
- Do not set `FEEDS` in `settings.py`. Why: `savefixture` and
  `scrapy fetch` run internal spiders, and a global feed writes stray
  output files for them. Pass the feed with `-o` instead (below).
- Other fetch tiers change concurrency. See `fetching.md`.

## Run modes

```bash
# sample
uv run scrapy crawl <spider> -s CLOSESPIDER_ITEMCOUNT=20 -o "output/%(name)s/%(time)s.jsonl"
# full
uv run scrapy crawl <spider> -o "output/%(name)s/%(time)s.jsonl"
```

Each run writes a new file and never overwrites a previous run. Run the
sample mode after every change. Run the full mode only when the user
asks. `CLOSESPIDER_ITEMCOUNT` stops the crawl near the limit, not exactly
at it.

## Code style

The verify commands run ruff's default rules. Write code that passes:

- Use `str | None`, not `Optional[str]`.
- Do not end a function with `return None` when it returns nothing.
- Annotate mutable class attributes such as `urls` with `ClassVar`.

## Verify

```bash
uv run ruff check --fix && uv run ruff format
uv run pyright
uv run pytest
uv run scrapy crawl <spider> -s CLOSESPIDER_ITEMCOUNT=20 -o "output/%(name)s/%(time)s.jsonl"
```

Then open the newest `output/<spider>/*.jsonl`. Check that each requested
field has values and that `url` values are unique.
