# Proxy Configuration

## When to Use

- Site returns 403/429 after a few requests
- IP bans detected (connection refused, timeouts after initial success)
- User explicitly requests proxy
- Anti-bot detection that rotates past UA rotation + delays

## Setup

Proxy URL goes in environment variable, NEVER hardcoded.

### 1. Create `.env.template`
```
HTTP_PROXY=
HTTPS_PROXY=
```

### 2. Add to `.gitignore`
```
.env
```

### 3. Configure settings.py
```python
import os

HTTP_PROXY = os.environ.get("HTTP_PROXY")
HTTPS_PROXY = os.environ.get("HTTPS_PROXY")

if HTTP_PROXY:
    DOWNLOADER_MIDDLEWARES.update({
        "scrapy.downloadermiddlewares.httpproxy.HttpProxyMiddleware": 110,
    })
```

### 4. Simple proxy middleware

If the user's proxy provider uses a single rotating endpoint (most common):
```python
import os

class ProxyMiddleware:
    def __init__(self):
        self.proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY")

    def process_request(self, request):
        if self.proxy:
            request.meta["proxy"] = self.proxy
```

This is usually enough — the proxy provider handles IP rotation on their end.

## Docker Integration

In `docker-compose.yml`:
```yaml
services:
  scraper:
    build: .
    env_file: .env
    # or explicitly:
    environment:
      - HTTP_PROXY=${HTTP_PROXY}
      - HTTPS_PROXY=${HTTPS_PROXY}
```

## Verification

After configuring proxy, verify it works:
```bash
uv run scrapy crawl <spider> -s CLOSESPIDER_ITEMCOUNT=3 -s LOG_LEVEL=INFO
```

Check logs for:
- No 403/429 errors
- Requests going through proxy (look for proxy-related headers in response)
- Items being scraped successfully
