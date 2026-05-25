# Result Analysis

## When to Trigger

After user runs a spider (locally or via deploy), analyze the output data.

## Analysis Flow

### Step 1: Load Output Data

Find the most recent output file:
```bash
ls -t output/<spider_name>/*.jsonl | head -1
```

Read the JSONL file and parse items.

### Step 2: Basic Statistics

Report:
- Total items scraped
- Scraping duration (from Scrapy stats if available)
- Items per second
- HTTP status codes distribution
- Error count and types

### Step 3: Field Analysis

For each field in the Pydantic model:

| Metric | What it shows |
|--------|---------------|
| Fill rate | % of items where field is non-null and non-empty |
| Unique values | Count of distinct values (high = good for IDs, low = suspicious for descriptions) |
| Type consistency | All values match expected type? |
| Length distribution | min/max/avg length for strings |
| Value distribution | Top 10 most common values (useful for categories, currencies) |
| Outliers | Values that deviate significantly from the mean (for numeric fields) |

### Step 4: Data Quality Checks

| Check | What it catches |
|-------|----------------|
| Duplicates | Same item scraped multiple times (by URL or unique field) |
| Empty required fields | Selector broke or page structure changed |
| Suspiciously uniform data | All items have same value for a field → selector is wrong |
| Truncated data | Field values all end at same length → encoding issue or selector too narrow |
| Mixed types | Some prices are "19.99", others are "$19.99" → processor missing |
| Missing pagination | Expected 100+ items but got 20 → pagination might not work |

### Step 5: Schema Validation

Validate each item against the Pydantic model:
```python
from pydantic import ValidationError

errors = []
for i, line in enumerate(open(output_file)):
    item = json.loads(line)
    try:
        ItemModel(**item)
    except ValidationError as e:
        errors.append({"line": i, "errors": e.errors()})
```

Report validation error summary: which fields fail, how often, example bad values.

### Step 6: AI Suggestions

Based on findings, suggest specific fixes:

| Finding | Suggestion |
|---------|------------|
| Field X empty in >20% of items | "Selector `{selector}` might be wrong. The page might use a different class for some items. Try: `{alternative_selector}`" |
| Duplicate items (>5%) | "Spider is revisiting pages. Add `DUPEFILTER_CLASS` or check pagination logic." |
| Price field has mixed formats | "Add a price processor to ItemLoader: `price_in = MapCompose(remove_currency, float)`" |
| Only 1 page of results | "Pagination selector might be wrong. Current: `{selector}`. Check if the site uses AJAX pagination." |
| HTTP 429 errors | "Site is rate-limiting. Increase DOWNLOAD_DELAY to 2-3 seconds or enable proxy rotation." |
| HTTP 403 errors | "Site might have bot protection. Consider using anti-bot tools (see /web-scraper-copilot anti-bot guidance)." |

### Step 7: Report

Present findings as a structured summary:

```markdown
## Scraping Results: <spider_name>

### Overview
- Items: 1,234 | Duration: 45min | Speed: 0.46 items/sec
- HTTP: 200 (1,250), 404 (3), 429 (12)

### Field Quality
| Field | Fill Rate | Unique | Issues |
|-------|-----------|--------|--------|
| name  | 100%      | 1,230  | OK |
| price | 98%       | 156    | 2% empty |
| image | 87%       | 1,074  | 13% missing |

### Issues Found
1. **13% missing images** — selector `.product-image img::attr(src)` returns None for items using lazy loading. Fix: try `::attr(data-src)` as fallback.
2. **12 rate-limit errors** — increase DOWNLOAD_DELAY to 2.

### Recommendations
- Add `data-src` fallback for image selector
- Increase download delay
- Run again to verify fixes
```

## Comparing Runs

If user has multiple output files, offer to compare:
- Items gained/lost between runs
- Field quality changes
- New errors or resolved errors
