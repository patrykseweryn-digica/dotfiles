# Parsers

## Quick Selection

```
JSON-LD / microdata in HTML?     → extruct             (cleanest, survives redesigns)
JS objects in <script> tags?     → chompjs + jmespath   (Next.js, SPAs, __INITIAL_STATE__)
Articles / news / blogs?         → trafilatura          (clean text, no selectors needed)
Structured HTML (CSS/XPath)?     → parsel               (default, Scrapy-style)
Need speed (>10k items)?         → selectolax           (5-30x faster, CSS only)
Long-running, site redesigns?    → Scrapling            (self-healing selectors)
```

## parsel (default)

Scrapy's selector library. CSS + XPath + regex. Available via `context.selector` in ParselCrawler.

```python
# CSS selectors
title = context.selector.css("title::text").get()
prices = context.selector.css(".price::text").getall()
links = context.selector.css("a::attr(href)").getall()

# XPath
rows = context.selector.xpath("//table//tr")
for row in rows:
    cols = row.xpath(".//td/text()").getall()

# Regex extraction
phone = context.selector.re_first(r"\+?\d[\d\s-]{8,}")
```

## BeautifulSoup (context.soup)

Available via `context.soup` in BeautifulSoupCrawler, or `context.parsed_content` in AdaptivePlaywrightCrawler.

```python
title = context.soup.title.string
links = [a["href"] for a in context.soup.find_all("a", href=True)]
text = context.soup.get_text(separator=" ", strip=True)
divs = context.soup.select("div.content > p")
```

## selectolax

5-30x faster than lxml/bs4. CSS selectors only.

```bash
uv add selectolax
```

```python
from selectolax.parser import HTMLParser

tree = HTMLParser(html)
for node in tree.css("div.item"):
    title = node.css_first("h2").text(strip=True)
    price = node.css_first(".price").text(strip=True)
```

## chompjs + jmespath

Extract JavaScript objects from `<script>` tags.

```bash
uv add chompjs jmespath
```

```python
import chompjs
import jmespath
from parsel import Selector

sel = Selector(text=html)

# Next.js __NEXT_DATA__
script = sel.css("script#__NEXT_DATA__::text").get()
if script:
    data = chompjs.parse_js_object(script)
    items = jmespath.search("props.pageProps.items[*].{name: name, price: price}", data)

# window.__INITIAL_STATE__
script = sel.xpath('//script[contains(text(), "__INITIAL_STATE__")]/text()').get()
if script:
    data = chompjs.parse_js_object(script.split("=", 1)[1])
```

## extruct

Extract structured data (JSON-LD, Microdata, RDFa, OpenGraph).

```bash
uv add extruct
```

```python
import extruct

metadata = extruct.extract(html, base_url=url, syntaxes=["json-ld", "microdata", "opengraph"])

# JSON-LD (schema.org)
for item in metadata.get("json-ld", []):
    if item.get("@type") == "Product":
        name = item["name"]
        price = item["offers"]["price"]

# OpenGraph
og = metadata.get("opengraph", [{}])[0]
og_title = og.get("og:title")
```

## trafilatura

Article/content extraction. Removes boilerplate (nav, footer, ads).

```bash
uv add trafilatura
```

```python
import trafilatura

text = trafilatura.extract(html)                              # Plain text
text_with_meta = trafilatura.extract(html, include_comments=False,
                                      include_tables=True,
                                      output_format="txt")
# With metadata
result = trafilatura.bare_extraction(html, url=url)
title = result["title"]
author = result["author"]
date = result["date"]
text = result["text"]
```

## Scrapling

Self-healing selectors — survives website redesigns by matching element similarity.

```bash
uv add scrapling
```

```python
from scrapling import Adaptor

page = Adaptor(html, url=url)
# First run: finds element, stores fingerprint
price = page.css(".product-price", auto_save=True)
# Later runs: if CSS fails, finds element by similarity to stored fingerprint
```

## Swapping Parsers

All parsers work with any crawler — just parse the HTML yourself:

```python
from crawlee.crawlers import BeautifulSoupCrawler, BeautifulSoupCrawlingContext
from selectolax.parser import HTMLParser

@crawler.router.default_handler
async def handler(context: BeautifulSoupCrawlingContext) -> None:
    html = str(context.soup)
    tree = HTMLParser(html)  # Use selectolax instead of BS4
    items = [node.text() for node in tree.css(".item")]
```
