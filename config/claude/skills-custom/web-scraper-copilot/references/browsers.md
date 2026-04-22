# Browser Automation (Anti-Detect)

Use browser automation when HTTP clients with TLS fingerprinting are not enough —
the site requires JS rendering, behavioral analysis, or deep fingerprint checks.

## Quick Selection

```
Default (clean async, MIT)       → pydoll (behavioral evasion, no fingerprint spoofing)
Max stealth (fingerprinting)     → camoufox (C++ fingerprint injection, MIT, currently unstable)
Cloudflare bypass (83%)          → nodriver (AGPL license — check compatibility!)
Playwright drop-in stealth       → patchright (Apache 2.0)
```

## License Warning

| Library | License | Commercial OK? |
|---|---|---|
| pydoll | MIT | Yes |
| camoufox | MIT | Yes |
| nodriver | **AGPL-3.0** | Requires open-sourcing derivative works |
| patchright | Apache 2.0 | Yes |

---

## pydoll (default)

**Approach:** CDP direct, behavioral evasion | **Async:** Yes (only)

No WebDriver binary, so `navigator.webdriver` is never set. Simulates human behavior:
Bezier mouse movements, Fitts's Law timing, physiological tremor.

```bash
uv add pydoll-python
```

```python
from pydoll.browser.chromium import Chromium

async def scrape(url: str) -> str:
    async with Chromium() as browser:
        page = await browser.get(url)
        await page.wait_element("css:.content")
        content = await page.content
        return content
```

### When to use
- Sites detecting WebDriver/automation flags
- Sites with behavioral analysis (mouse tracking, timing)
- When you need MIT license

### When NOT to use
- Sites with deep fingerprint detection (canvas, WebGL, fonts)
- Cloudflare managed challenges → use camoufox or nodriver

---

## camoufox

**Approach:** Custom Firefox, C++ fingerprint injection | **Cloudflare:** 83%

Deepest anti-detection — fingerprints injected at browser engine level, not JS.
Spoofs: navigator, screen, WebGL, geolocation, timezone, WebRTC, fonts.

```bash
uv add camoufox[geoip]
```

### Sync
```python
from camoufox.sync_api import Camoufox

with Camoufox(headless=True) as browser:
    page = browser.new_page()
    page.goto("https://example.com")
    content = page.content()
```

### Async
```python
from camoufox.async_api import AsyncCamoufox

async with AsyncCamoufox(headless=True) as browser:
    page = await browser.new_page()
    await page.goto("https://example.com")
    content = await page.content()
```

### When to use
- Cloudflare, DataDome, PerimeterX bypass
- Sites with canvas/WebGL fingerprinting
- When MIT license needed

### Caveats
- ~1GB memory per instance (Firefox-based)
- Currently in unstable transition (CloverLabsAI fork)
- Breaking changes expected

---

## nodriver

**Approach:** Direct CDP, no chromedriver | **Cloudflare:** 83%

Successor to undetected-chromedriver. Built-in `cf_verify()` for Cloudflare.

```bash
uv add nodriver
```

```python
import nodriver as uc

async def scrape(url: str) -> str:
    browser = await uc.start(headless=True)
    page = await browser.get(url)
    await page.sleep(2)
    content = await page.get_content()
    browser.stop()
    return content
```

### Cloudflare bypass
```python
page = await browser.get(url)
await page.cf_verify()  # built-in Cloudflare handler
```

### When to use
- Cloudflare bypass is the primary need
- Simple async API preferred

### Caveats
- **AGPL license** — must open-source derivative works
- Async-only, no sync API

---

## patchright (Playwright drop-in)

**Approach:** Patched Playwright | **Cloudflare:** 67%

Same API as Playwright but with stealth patches. Swap `playwright` → `patchright`.

```bash
uv add patchright
```

```python
from patchright.async_api import async_playwright

async def scrape(url: str) -> str:
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        await page.goto(url)
        content = await page.content()
        await browser.close()
        return content
```

### When to use
- Already using Playwright, want to add stealth
- Need sync + async
- Apache 2.0 license

---

## SPA Rendering Patterns

These patterns work with any browser above.

### Infinite scroll
```python
prev_height = 0
while True:
    await page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
    await page.wait_for_timeout(2000)
    new_height = await page.evaluate("document.body.scrollHeight")
    if new_height == prev_height:
        break
    prev_height = new_height
```

### Click "Load More"
```python
while True:
    btn = await page.query_selector("button.load-more")
    if not btn or not await btn.is_visible():
        break
    await btn.click()
    await page.wait_for_timeout(2000)
```

### Wait for dynamic content
```python
await page.wait_for_selector(".products-loaded", timeout=10000)
```

## Swapping Browsers

All browsers follow: launch → navigate → get content → close.
To swap, change the import and launch code. Parsing logic stays the same.
