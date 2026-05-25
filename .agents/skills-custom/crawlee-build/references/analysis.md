# Output Analysis & Validation

## Analysis Flow

After a crawl run, analyze the output to verify data quality.

```
1. Load output       → Read JSONL/JSON/CSV
2. Basic stats       → Item count, duration, success rate
3. Field analysis    → Fill rate, types, uniqueness
4. Quality checks    → Duplicates, empty fields, truncation
5. Schema validation → Validate against Pydantic model
6. Report            → Summarize findings, suggest fixes
```

## Step 1: Load Output

```python
import json
from pathlib import Path

def load_jsonl(path: str) -> list[dict]:
    items = []
    with open(path) as f:
        for line in f:
            items.append(json.loads(line))
    return items

def load_json(path: str) -> list[dict]:
    with open(path) as f:
        data = json.load(f)
    return data if isinstance(data, list) else [data]

items = load_jsonl("output/results.jsonl")
```

## Step 2: Basic Statistics

```python
print(f"Total items: {len(items)}")
print(f"Unique URLs: {len(set(item.get('url', '') for item in items))}")

# HTTP status distribution (if available)
statuses = [item.get("status") for item in items if "status" in item]
if statuses:
    from collections import Counter
    print(f"Status codes: {Counter(statuses)}")
```

## Step 3: Field Analysis

```python
def analyze_fields(items: list[dict]) -> dict:
    if not items:
        return {}

    all_keys = set()
    for item in items:
        all_keys.update(item.keys())

    report = {}
    for key in sorted(all_keys):
        values = [item.get(key) for item in items]
        non_null = [v for v in values if v is not None and v != "" and v != []]
        unique = set(str(v) for v in non_null)

        report[key] = {
            "fill_rate": f"{len(non_null)/len(items)*100:.1f}%",
            "unique_values": len(unique),
            "types": list(set(type(v).__name__ for v in non_null)),
            "sample": non_null[:3] if non_null else [],
        }

    return report

for field, stats in analyze_fields(items).items():
    print(f"  {field}: fill={stats['fill_rate']}, unique={stats['unique_values']}, types={stats['types']}")
```

## Step 4: Quality Checks

```python
def check_quality(items: list[dict]) -> list[str]:
    issues = []

    # Duplicates
    urls = [item.get("url", "") for item in items]
    dup_count = len(urls) - len(set(urls))
    if dup_count > 0:
        issues.append(f"⚠ {dup_count} duplicate URLs")

    # Empty/null fields
    for key in items[0].keys() if items else []:
        empty = sum(1 for item in items if not item.get(key))
        if empty > len(items) * 0.5:
            issues.append(f"⚠ Field '{key}' is empty in {empty}/{len(items)} items ({empty/len(items)*100:.0f}%)")

    # Uniform data (all same value)
    for key in items[0].keys() if items else []:
        values = set(str(item.get(key, "")) for item in items)
        if len(values) == 1 and len(items) > 5:
            issues.append(f"⚠ Field '{key}' has uniform value across all items")

    # Truncated text (suspiciously same length)
    for key in items[0].keys() if items else []:
        lengths = [len(str(item.get(key, ""))) for item in items if item.get(key)]
        if lengths and max(lengths) == min(lengths) and max(lengths) > 50:
            issues.append(f"⚠ Field '{key}' may be truncated (all {max(lengths)} chars)")

    return issues

issues = check_quality(items)
for issue in issues:
    print(issue)
if not issues:
    print("✓ No quality issues detected")
```

## Step 5: Schema Validation

```python
from pydantic import BaseModel, ValidationError

class ExpectedItem(BaseModel):
    url: str
    title: str
    price: float | None = None

valid = 0
errors = []
for i, item in enumerate(items):
    try:
        ExpectedItem(**item)
        valid += 1
    except ValidationError as e:
        errors.append(f"Item {i}: {e.error_count()} errors")

print(f"Schema validation: {valid}/{len(items)} valid")
if errors:
    for err in errors[:5]:
        print(f"  {err}")
```

## Step 6: Report Format

```markdown
## Crawl Report

### Summary
- **Items collected**: 150
- **Unique URLs**: 148
- **Duration**: ~5 min

### Field Analysis
| Field | Fill Rate | Unique | Types |
|-------|-----------|--------|-------|
| url | 100% | 148 | str |
| title | 98% | 145 | str |
| price | 85% | 42 | float |

### Quality Issues
- ⚠ 2 duplicate URLs
- ⚠ Field 'description' empty in 22/150 items (15%)

### Recommendations
- Add deduplication by URL
- Check selector for 'description' field — may need fallback selector
```

## Comparing Runs

```python
def compare_runs(run1: list[dict], run2: list[dict]) -> dict:
    urls1 = set(item.get("url") for item in run1)
    urls2 = set(item.get("url") for item in run2)

    return {
        "run1_count": len(run1),
        "run2_count": len(run2),
        "new_items": len(urls2 - urls1),
        "removed_items": len(urls1 - urls2),
        "common_items": len(urls1 & urls2),
    }
```
