# Proxy Configuration

## When to Use Proxy

- Getting 403/429 after a few requests
- IP-based rate limiting or geo-blocking
- User explicitly requests it

**Ask about proxy EARLY** — don't wait until the crawler is blocked.

## Crawlee ProxyConfiguration

### Simple rotation

```python
from crawlee import ProxyConfiguration

proxy = ProxyConfiguration(
    proxy_urls=[
        "http://proxy1.example.com:8080",
        "http://proxy2.example.com:8080",
        "http://user:pass@proxy3.example.com:8080",
    ]
)

crawler = BeautifulSoupCrawler(
    proxy_configuration=proxy,
    use_session_pool=True,
    max_session_rotations=5,
)
```

### Tiered proxies (auto-escalation)

Crawlee tries cheaper proxies first, escalates on blocks:

```python
proxy = ProxyConfiguration(
    tiered_proxy_urls=[
        # Tier 0: datacenter (cheapest, tried first)
        ["http://dc-proxy1:8080", "http://dc-proxy2:8080"],
        # Tier 1: residential (more expensive, used if tier 0 fails)
        ["http://resi-proxy1:8080", "http://resi-proxy2:8080"],
        # Tier 2: mobile/ISP (most expensive, last resort)
        ["http://mobile-proxy:8080"],
    ]
)
```

### Custom proxy function

```python
async def my_proxy_function(session_id: str | None, request) -> str | None:
    if "api.example.com" in request.url:
        return None  # Direct connection for APIs
    return "http://default-proxy:8080"

proxy = ProxyConfiguration(new_url_function=my_proxy_function)
```

## Environment Variables

```bash
# .env
PROXY_URLS=http://proxy1:8080,http://proxy2:8080
PROXY_USERNAME=user
PROXY_PASSWORD=pass
```

```python
import os

proxy_urls_str = os.getenv("PROXY_URLS", "")
proxy_urls = [url.strip() for url in proxy_urls_str.split(",") if url.strip()]

if proxy_urls:
    proxy = ProxyConfiguration(proxy_urls=proxy_urls)
    crawler = ParselCrawler(proxy_configuration=proxy)
else:
    crawler = ParselCrawler()  # No proxy
```

## Session Pool with Proxy

Sessions stick to the same proxy, ensuring cookie consistency:

```python
from crawlee.sessions import SessionPool

session_pool = SessionPool(
    max_pool_size=50,
    create_session_settings={
        "max_usage_count": 30,
        "max_error_score": 3.0,
        "blocked_status_codes": [403, 429],
    },
)

crawler = ParselCrawler(
    proxy_configuration=proxy,
    session_pool=session_pool,
    max_session_rotations=5,
)
```

## Docker Integration

```yaml
# docker-compose.yml
services:
  crawler:
    build: .
    env_file: .env
    environment:
      - PROXY_URLS=${PROXY_URLS}
```

## Verification Checklist

- [ ] Proxy URLs loaded from environment (never hardcoded)
- [ ] `.env` in `.gitignore`
- [ ] Session pool enabled for cookie persistence
- [ ] Tiered proxies configured (if multiple quality levels)
- [ ] Rate limiting set per proxy tier
- [ ] Fallback to direct connection if no proxy configured
