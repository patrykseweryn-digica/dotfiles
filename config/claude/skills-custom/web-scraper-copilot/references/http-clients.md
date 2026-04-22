# HTTP Clients with TLS Fingerprinting

All clients share the same purpose: make HTTP requests that look like a real browser
at the TLS/HTTP2 level. They are interchangeable — pick based on the situation.

## Quick Selection

```
Default                    → curl_cffi (most mature, HTTP/3, production-ready)
Max TLS control needed     → rnet (finest-grained fingerprint control)
httpx-compatible API       → impit (Rust backend, drop-in httpx replacement)
Lightweight / minimal      → primp (simple API, small footprint)
```

## curl_cffi (default)

**Backend:** C (curl-impersonate) | **Async:** Yes | **HTTP/3:** Yes

```bash
uv add curl_cffi
```

### Sync
```python
from curl_cffi.requests import Session

with Session() as s:
    resp = s.get("https://example.com", impersonate="chrome")
    print(resp.text)
```

### Async
```python
from curl_cffi.requests import AsyncSession

async with AsyncSession() as s:
    resp = await s.get("https://example.com", impersonate="chrome")
    print(resp.text)
```

### With proxy
```python
with Session() as s:
    resp = s.get(url, impersonate="chrome", proxies={
        "https": os.environ.get("HTTPS_PROXY"),
    })
```

### Browser profiles
Available: `"chrome"`, `"firefox"`, `"safari"`, `"edge"`. Version-specific:
`"chrome131"`, `"firefox133"`, etc.

---

## rnet (advanced)

**Backend:** Rust (BoringSSL) | **Async:** Yes | **Python:** 3.11+

Best TLS fingerprint control — individual cipher suites, extension order, HTTP/2 settings.

```bash
uv add rnet
```

### Async (default)
```python
import rnet

async def fetch():
    client = rnet.Client(impersonate=rnet.Impersonate.Chrome131)
    resp = await client.get("https://example.com")
    return resp.text()
```

### Blocking
```python
import rnet

client = rnet.BlockingClient(impersonate=rnet.Impersonate.Chrome131)
resp = client.get("https://example.com")
```

### Fine-grained TLS control
```python
import rnet

client = rnet.Client(
    impersonate=rnet.Impersonate.Chrome131,
    tls_config=rnet.TlsConfig(
        cipher_list=["TLS_AES_128_GCM_SHA256", "TLS_AES_256_GCM_SHA384"],
        min_tls_version=rnet.TlsVersion.TLS_1_2,
    ),
)
```

**Note:** Still in RC (v3.0.0-rc). API may change. Requires Python 3.11+.

---

## primp (lightweight)

**Backend:** Rust | **Async:** Yes | **Python:** 3.10+

Simple API, smallest footprint. By the author of `duckduckgo_search`.

```bash
uv add primp
```

### Sync
```python
from primp import Client

client = Client(impersonate="chrome_131")
resp = client.get("https://example.com")
```

### Async
```python
from primp import AsyncClient

async with AsyncClient(impersonate="chrome_131") as client:
    resp = await client.get("https://example.com")
```

No HTTP/3, no WebSocket. Use curl_cffi if you need those.

---

## impit (httpx-compatible)

**Backend:** Rust (reqwest/rustls) | **Async:** Yes | **HTTP/3:** Yes

By Apify. API designed as drop-in httpx replacement. Default client in Crawlee Python.

```bash
uv add impit
```

### Sync
```python
from impit import Client

with Client(browser="chrome") as client:
    resp = client.get("https://example.com")
    print(resp.text)
```

### Async
```python
from impit import AsyncClient

async with AsyncClient(browser="chrome") as client:
    resp = await client.get("https://example.com")
    print(resp.text)
```

### With proxy
```python
with Client(browser="chrome", proxy=os.environ.get("HTTPS_PROXY")) as client:
    resp = client.get(url)
```

Best when migrating from httpx — same API patterns. Supports HTTP/1.1, HTTP/2, HTTP/3.

---

## Swapping Clients

All four follow the same pattern: create client → set impersonation → get/post.
To swap, change the import and client creation. The rest of the code stays the same.

```python
# curl_cffi
from curl_cffi.requests import Session
client = Session()
resp = client.get(url, impersonate="chrome")

# rnet
import rnet
client = rnet.BlockingClient(impersonate=rnet.Impersonate.Chrome131)
resp = client.get(url)

# primp
from primp import Client
client = Client(impersonate="chrome_131")
resp = client.get(url)

# impit
from impit import Client
client = Client(browser="chrome")
resp = client.get(url)
```

## When HTTP Client Is Not Enough

If TLS fingerprinting alone doesn't bypass protection (still getting 403/captcha),
escalate to browser automation → read `references/browsers.md`.
