# Parsing Libraries

## Quick Selection

```
CSS + XPath (Scrapy ecosystem)   → parsel (default)
Max speed, CSS only              → selectolax (lexbor backend)
JS objects in <script> tags      → chompjs + jmespath
Structured data (JSON-LD, etc.)  → extruct
Adaptive element matching        → Scrapling (validate relocated fields)
Article/news content extraction  → trafilatura
```

---

## parsel (default)

CSS selectors + XPath + regex in one API. Uses lxml internally. Standalone — no Scrapy needed.

```bash
uv add parsel
```

```python
from parsel import Selector

sel = Selector(text=html)
title = sel.css("h1::text").get("")
prices = sel.css(".price::text").getall()
# XPath also available:
author = sel.xpath("//span[@class='author']/text()").get("")
```

---

## selectolax (speed)

5-30x faster than BeautifulSoup. Use the **lexbor** backend (default, actively maintained).

```bash
uv add selectolax
```

```python
from selectolax.lexbor import LexborHTMLParser

parser = LexborHTMLParser(html)
title = parser.css_first("h1").text(strip=True)
prices = [node.text(strip=True) for node in parser.css(".price")]
```

**No XPath support** — CSS selectors only. Use parsel if you need XPath.

---

## chompjs + jmespath (JS data extraction)

Extract JavaScript objects from `<script>` tags, then query with jmespath.
Handles non-standard JS (unquoted keys, trailing commas) where `json.loads()` fails.

```bash
uv add chompjs jmespath
```

```python
import chompjs
import jmespath
from parsel import Selector

sel = Selector(text=html)

# Extract JS object from <script> tag
script = sel.css("script:contains('window.__data')::text").get("")
data = chompjs.parse_js_object(script)

# Query the extracted data
names = jmespath.search("products[*].name", data)
```

### Common patterns
```python
# Next.js __NEXT_DATA__
next_data = sel.css("script#__NEXT_DATA__::text").get("")
data = chompjs.parse_js_object(next_data)
props = jmespath.search("props.pageProps", data)

# window.__INITIAL_STATE__ (React/Vue SSR)
import re
match = re.search(r"window\.__INITIAL_STATE__\s*=\s*({.+?});", html)
if match:
    data = chompjs.parse_js_object(match.group(1))
```

---

## extruct (structured data)

Automatically extracts JSON-LD, Microdata, RDFa, OpenGraph from any page.
Many e-commerce, recipe, and news sites embed structured data.

```bash
uv add extruct
```

```python
import extruct

data = extruct.extract(html, syntaxes=["json-ld", "opengraph", "microdata"])

# JSON-LD (most common on e-commerce)
for item in data["json-ld"]:
    if item.get("@type") == "Product":
        print(item["name"], item["offers"]["price"])

# OpenGraph
og = data["opengraph"][0] if data["opengraph"] else {}
title = og.get("og:title")
```

**Check for structured data FIRST** — it's cleaner than CSS selectors and survives
site redesigns.

---

## Swapping Parsers

parsel and selectolax have different APIs but do the same thing:

```python
# parsel
from parsel import Selector
sel = Selector(text=html)
title = sel.css("h1::text").get("")

# selectolax
from selectolax.lexbor import LexborHTMLParser
parser = LexborHTMLParser(html)
title = parser.css_first("h1").text(strip=True)
```

To swap, change the import and adapt `.get()` → `.text()`. Logic stays the same.

---

## Scrapling (optional parsing)

Use Scrapling when its parsing API or adaptive matching solves an observed extraction problem.
Keep existing parsers when they already satisfy the data contract.

```bash
uv add scrapling
```

```python
from scrapling import Selector

page = Selector(html, url=url)
title = page.css("h1::text").get()
```

For Scrapy, convert the fetched response inside the existing callback:

```python
from scrapling.integrations.scrapy import convert_response

page = convert_response(response)
title = page.css("h1::text").get()
```

Keep Scrapy requests, scheduling, retries, and pipelines unchanged.
Use the original Scrapy response for `response.follow()`.
Scrapling's own `Response.follow()` creates requests for its separate crawler.
See the [Scrapy integration guide](https://scrapling.readthedocs.io/en/latest/integrations/scrapy.html).

Adaptive matching relocates elements by similarity; it does not prove field correctness.
Validate relocated fields against saved samples before trusting output.
Persist learned state explicitly when enabling adaptive matching across runs.
Check the [adaptive parsing guide](https://scrapling.readthedocs.io/en/latest/parsing/adaptive.html)
for current settings and storage configuration.

For agent reconnaissance and MCP setup, read
[`toolbox.md`](../../web-scraping-references/references/toolbox.md#scrapling-mcp).

---

## trafilatura (article/content extraction)

Extracts main content from articles, blog posts, and news pages. Removes boilerplate
(navigation, ads, footers, sidebars). Also extracts metadata: title, author, date, categories.

```bash
uv add trafilatura
```

```python
import trafilatura

# From HTML string
result = trafilatura.extract(html, include_comments=False, include_tables=True)
# Returns clean text content

# With metadata
result = trafilatura.bare_extraction(html, include_comments=False)
# result["text"], result["title"], result["author"], result["date"],
# result["categories"], result["tags"]

# Output as Markdown, XML, or JSON
md = trafilatura.extract(html, output_format="markdown")
```

### When to use
- Scraping articles, blog posts, news, documentation
- When you need clean text without writing page-specific selectors
- Building text corpora or datasets from web content

### When NOT to use
- Structured data (products, listings) — use parsel/extruct
- When you need specific fields from specific elements — use parsel
