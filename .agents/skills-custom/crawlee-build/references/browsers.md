# Anti-Bot Escalation & Browser Automation

## Escalation Ladder

Try each level in order. Move up only when lower level fails.

```
Level 1: Default HTTP            → No impersonation, basic headers
Level 2: CurlImpersonate         → TLS fingerprint bypass (curl_cffi)
Level 3: AdaptivePlaywright      → Auto HTTP/browser switching
Level 4: Playwright + stealth    → Fingerprint generation, viewport randomization
Level 5: External stealth browser → pydoll, camoufox, nodriver
Level 6: Proxy rotation          → Combine with any level above
```

## Level 2: CurlImpersonateHttpClient

Browser TLS fingerprint impersonation without a real browser.

```python
from crawlee.http_clients import CurlImpersonateHttpClient

http_client = CurlImpersonateHttpClient(
    impersonate="chrome131",
    timeout=15,
    persist_cookies_per_session=True,
)

# Profile rotation on failure:
PROFILES = ["chrome131", "firefox135", "safari18_0", "edge131"]

async def try_with_rotation(url: str) -> str | None:
    for profile in PROFILES:
        client = CurlImpersonateHttpClient(impersonate=profile, timeout=15)
        try:
            # ... attempt crawl
            return result
        except Exception:
            continue
    return None
```

## Level 3: AdaptivePlaywrightCrawler

Tries HTTP first (fast), automatically falls back to Playwright when needed.

See `crawlers.md` for full configuration example.

## Level 4: Playwright + Fingerprint Generation

```python
from crawlee.fingerprint_suite import DefaultFingerprintGenerator, HeaderGeneratorOptions, ScreenOptions
from crawlee.crawlers import PlaywrightCrawler

fingerprint_gen = DefaultFingerprintGenerator(
    header_options=HeaderGeneratorOptions(browsers=["chrome", "firefox"]),
    screen_options=ScreenOptions(min_width=1024, max_width=1920),
)

crawler = PlaywrightCrawler(
    headless=True,
    browser_type="chromium",
    fingerprint_generator=fingerprint_gen,
    browser_new_context_options={
        "color_scheme": "light",
        "locale": "en-US",
    },
)
```

## Level 5: External Stealth Browsers

Use when crawlee's built-in Playwright isn't enough.

| Browser | License | Cloudflare bypass | Notes |
|---------|---------|-------------------|-------|
| pydoll | MIT | Good | CDP direct, behavioral evasion |
| camoufox | MPL-2.0 | ~83% | Custom Firefox, C++ fingerprint injection |
| nodriver | AGPL | ~83% | Direct CDP, built-in Cloudflare handler |
| patchright | Apache-2.0 | Good | Playwright drop-in with stealth patches |

### pydoll (recommended)

```bash
uv add pydoll-python
```

```python
from pydoll.browser.chromium import Chromium
from pydoll.connection.connection import Connection

async def fetch_with_pydoll(url: str) -> str:
    async with Chromium(headless=True) as browser:
        tab = await browser.start()
        await tab.go_to(url)
        await tab.wait_element("body", timeout=15)
        html = await tab.get_page_source()
    return html
```

### camoufox

```bash
uv add camoufox[geoip]
```

```python
from camoufox.async_api import AsyncCamoufox

async def fetch_with_camoufox(url: str) -> str:
    async with AsyncCamoufox(headless=True) as browser:
        page = await browser.new_page()
        await page.goto(url, wait_until="domcontentloaded")
        html = await page.content()
        await page.close()
    return html
```

### nodriver

**AGPL license** — check compatibility with your project.

```bash
uv add nodriver
```

```python
import nodriver as uc

async def fetch_with_nodriver(url: str) -> str:
    browser = await uc.start(headless=True)
    page = await browser.get(url)
    html = await page.get_content()
    browser.stop()
    return html
```

## SPA Rendering Patterns

### Infinite scroll (Playwright)

```python
@crawler.router.default_handler
async def handler(context: PlaywrightCrawlingContext) -> None:
    prev_height = 0
    for _ in range(20):  # Max 20 scroll attempts
        await context.page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
        await context.page.wait_for_timeout(1500)
        new_height = await context.page.evaluate("document.body.scrollHeight")
        if new_height == prev_height:
            break
        prev_height = new_height

    items = await context.page.query_selector_all(".item")
    # ... extract data
```

### Click "Load More"

```python
@crawler.router.default_handler
async def handler(context: PlaywrightCrawlingContext) -> None:
    while True:
        btn = await context.page.query_selector("button.load-more")
        if not btn or not await btn.is_visible():
            break
        await btn.click()
        await context.page.wait_for_timeout(1000)

    # All items loaded, extract
```

### Wait for dynamic content

```python
@crawler.router.default_handler
async def handler(context: PlaywrightCrawlingContext) -> None:
    await context.page.wait_for_selector("[data-loaded='true']", timeout=15000)
    # OR wait for network to idle:
    await context.page.wait_for_load_state("networkidle")
```

## Combining with Proxy

See `proxy.md` for configuration. Any level can be combined with proxy:

```python
from crawlee import ProxyConfiguration

proxy = ProxyConfiguration(
    tiered_proxy_urls=[
        ["http://datacenter-proxy:8080"],      # Tier 0: cheap
        ["http://residential-proxy:8080"],      # Tier 1: premium
    ]
)

crawler = AdaptivePlaywrightCrawler.with_beautifulsoup_static_parser(
    http_client=CurlImpersonateHttpClient(impersonate="chrome131"),
    proxy_configuration=proxy,
    use_session_pool=True,
    max_session_rotations=5,
)
```
