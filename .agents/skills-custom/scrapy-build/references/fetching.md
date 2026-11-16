# Fetch ladder

| Tier | Use when | Page base class |
|---|---|---|
| 1. Scrapy downloader | Default | `WebPage` |
| 2. scrapy-impersonate | Blocked by TLS fingerprint (403, bot page) | `WebPage` |
| 3. scrapy-playwright | Raw fixture lacks JavaScript-rendered data | `WebPage` |
| 4. Zyte API | User asks for it | `WebPage` / `BrowserPage` |

Every domain starts at tier 1. Raise a domain's tier only with evidence
from its raw fixture, and pick the lowest tier that fixes that problem:

- Blocked response (403, 429, bot-check page): tier 2.
- Content missing from the raw HTML, but visible in a browser: tier 3.
  Partial loss is enough, for example missing pagination links. First
  check inline `<script>` JSON in the raw HTML; it often holds the data.

Do not add a fifth strategy, a custom client, or a script. If no tier
yields data, the selectors are wrong. A higher tier changes settings and
middlewares only; page objects stay the same.

After you change a domain's tier, delete that domain's fixtures and save
them again. Why: tests must use the response the spider now receives.

Tiers 2 and 3 need a downloader middleware that sets request meta. Why:
`savefixture` builds its own request and skips the spider, so only a
downloader middleware reaches every request. Use `setdefault` so one
request can opt out. Omit the `spider` argument in `process_request`;
Scrapy deprecates it.

Choose the tier per domain. The middleware acts only on hosts listed in a
setting. Other requests fall through to the plain Scrapy downloader. Why:
one JavaScript site must not force a browser on every other domain.

```python
# base/middlewares.py
from urllib.parse import urlparse


def host_matches(url: str, domains: set[str]) -> bool:
    host = urlparse(url).hostname or ""
    return any(host == d or host.endswith(f".{d}") for d in domains)
```

## Tier 2: scrapy-impersonate (curl_cffi)

`uv add scrapy-impersonate`

```python
DOWNLOAD_HANDLERS = {
    "http": "scrapy_impersonate.ImpersonateDownloadHandler",
    "https": "scrapy_impersonate.ImpersonateDownloadHandler",
}
IMPERSONATE_DOMAINS = ["example.com"]
DOWNLOADER_MIDDLEWARES = {"base.middlewares.ImpersonateMiddleware": 543}
```

```python
class ImpersonateMiddleware:
    def __init__(self, domains: list[str]) -> None:
        self.domains = set(domains)

    @classmethod
    def from_crawler(cls, crawler):
        return cls(crawler.settings.getlist("IMPERSONATE_DOMAINS"))

    def process_request(self, request):
        if host_matches(request.url, self.domains):
            request.meta.setdefault("impersonate", "chrome")
            # curl_cffi sends a UA that matches its TLS fingerprint
            request.headers.pop(b"User-Agent", None)
```

The handler acts only on requests with `meta["impersonate"]`. Never rotate
user agents here. Why: a UA that does not match the TLS fingerprint
exposes the bot.

## Tier 3: scrapy-playwright

`uv add scrapy-playwright` plus the chosen backend.

```python
TWISTED_REACTOR = "twisted.internet.asyncioreactor.AsyncioSelectorReactor"
DOWNLOAD_HANDLERS = {
    "http": "scrapy_playwright.handler.ScrapyPlaywrightDownloadHandler",
    "https": "scrapy_playwright.handler.ScrapyPlaywrightDownloadHandler",
}
PLAYWRIGHT_DOMAINS = ["example.com"]
DOWNLOADER_MIDDLEWARES = {"base.middlewares.PlaywrightRequestMiddleware": 543}
PLAYWRIGHT_MAX_PAGES_PER_CONTEXT = 8  # each browser page is heavy
```

```python
class PlaywrightRequestMiddleware:
    def __init__(self, domains: list[str]) -> None:
        self.domains = set(domains)

    @classmethod
    def from_crawler(cls, crawler):
        return cls(crawler.settings.getlist("PLAYWRIGHT_DOMAINS"))

    def process_request(self, request):
        if not host_matches(request.url, self.domains):
            return
        request.meta.setdefault("playwright", True)
        # camoufox manages its own viewport; harmless for patchright
        request.meta.setdefault("playwright_context_kwargs", {"no_viewport": True})
        # camoufox's driver can crash on scripts that throw after `load`
        request.meta.setdefault(
            "playwright_page_goto_kwargs", {"wait_until": "domcontentloaded"}
        )
```

- Do not subclass `ScrapyPlaywrightDownloadHandler`.
- Leave `PLAYWRIGHT_CONTEXTS` empty. Why: a startup context opens an idle
  browser before the first request.
- Raise `PLAYWRIGHT_DEFAULT_NAVIGATION_TIMEOUT` if pages time out.
- The warning `Navigating to ... returned None, the response will have
  empty headers and status 200` means the real HTTP status is lost. A
  404 or 500 then looks like 200. Check that pages contain the expected
  content; do not trust the status code on browser-rendered domains.

### Backend: patchright (default)

`uv add patchright && uv run patchright install chromium`

```python
PLAYWRIGHT_BROWSER_TYPE = "chromium"
PLAYWRIGHT_BROWSER_PROVIDER = "base.providers.PatchrightBrowserProvider"
```

### Backend: camoufox

`uv add camoufox && uv run camoufox fetch`

```python
PLAYWRIGHT_BROWSER_TYPE = "firefox"
PLAYWRIGHT_BROWSER_PROVIDER = "base.providers.CamoufoxBrowserProvider"
```

### base/providers.py

Write only the provider class of the selected backend. Why: pyright fails
on imports of an uninstalled backend. Import the backend inside the
methods, as below.

```python
from contextlib import AsyncExitStack

from scrapy_playwright.handler import PERSISTENT_CONTEXT_PATH_KEY, Config


class PatchrightBrowserProvider:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.stack = AsyncExitStack()

    async def start(self) -> None:
        from patchright.async_api import async_playwright

        pw = await self.stack.enter_async_context(async_playwright())
        self.browser_type = pw.chromium

    async def launch_browser(self):
        return await self.browser_type.launch(**self.config.launch_options)

    async def launch_persistent_context(self, context_kwargs: dict):
        return await self.browser_type.launch_persistent_context(**context_kwargs)

    async def close(self) -> None:
        await self.stack.aclose()


class CamoufoxBrowserProvider:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.stack = AsyncExitStack()

    async def start(self) -> None:
        pass

    async def launch_browser(self):
        from camoufox.async_api import AsyncCamoufox

        return await self.stack.enter_async_context(
            AsyncCamoufox(**self.config.launch_options)
        )

    async def launch_persistent_context(self, context_kwargs: dict):
        from camoufox.async_api import AsyncCamoufox

        return await self.stack.enter_async_context(
            AsyncCamoufox(
                persistent_context=True,
                user_data_dir=context_kwargs[PERSISTENT_CONTEXT_PATH_KEY],
                **self.config.launch_options,
            )
        )

    async def close(self) -> None:
        await self.stack.aclose()
```

## Tier 4: Zyte API

Use only when the user asks. Do not combine with tier 2 or 3.

```toml
dependencies = ["scrapy-zyte-api[provider]"]
```

```python
ADDONS = {
    "scrapy_poet.Addon": 300,  # must come before zyte-api
    "scrapy_zyte_api.Addon": 500,
}
CONCURRENT_REQUESTS_PER_DOMAIN = 32
CONCURRENT_REQUESTS = 32 * 1  # 32 x number of domains
DOWNLOAD_DELAY = 0
AUTOTHROTTLE_ENABLED = True
AUTOTHROTTLE_START_DELAY = 0.25
AUTOTHROTTLE_MAX_DELAY = 30
AUTOTHROTTLE_TARGET_CONCURRENCY = 32.0
```

- `scrapy_poet.Addon` comes first so zyte-api can wrap its fingerprinter.
- The `provider` extra is required by `scrapy_zyte_api.Addon`.
- Read the key from `ZYTE_API_KEY` in the environment. Never write it to a
  file. If the key is missing, ask the user. Do not remove the addon or
  fall back to another tier.
- Higher concurrency is safe here because Zyte spreads the load.
- Start with `WebPage`. Switch one page object to `BrowserPage` only after
  its raw fixture lacks the data. Never enable `browserHtml` in settings,
  `ZYTE_API_DEFAULT_PARAMS`, or request meta. The base class controls it.
