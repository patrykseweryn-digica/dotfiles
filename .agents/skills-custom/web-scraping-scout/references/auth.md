# Authentication

## Auto-Detection

After fetching a page, check if auth is needed:
- HTTP 401/403 response
- Redirect to URL containing `/login`, `/signin`, `/auth`, `/account`
- Page contains `<form>` with password input
- Page contains "Please log in", "Sign in to continue", etc.

If detected, inform user and ask for auth details.

## Auth Strategies

### 1. Form Login (most common)

Use Chrome DevTools MCP to analyze the login flow:
```
1. mcp__chrome-devtools__navigate_page(url=login_url)
2. mcp__chrome-devtools__take_snapshot() — find the login form fields
3. mcp__chrome-devtools__fill_form({fields}) — fill username/password
4. mcp__chrome-devtools__click({uid}) — submit
5. mcp__chrome-devtools__list_network_requests(resourceTypes=["xhr","fetch","document"])
   → capture the auth request (POST /login, Set-Cookie headers)
6. mcp__chrome-devtools__get_network_request(reqid=N) — get full request/response
```

From the captured request, generate a Scrapy login spider:
```python
class AuthSpider(scrapy.Spider):
    name = "mysite"

    def start_requests(self):
        yield scrapy.Request(
            "https://example.com/login",
            callback=self.login,
        )

    def login(self, response):
        yield scrapy.FormRequest.from_response(
            response,
            formdata={
                "username": os.environ["SITE_USERNAME"],
                "password": os.environ["SITE_PASSWORD"],
            },
            callback=self.after_login,
        )

    def after_login(self, response):
        if "logout" in response.text:
            yield from self.parse_authenticated(response)
        else:
            self.logger.error("Login failed")

    def parse_authenticated(self, response):
        # regular scraping logic here
        ...
```

### 2. Cookie/Header Auth

If the site uses API tokens or cookies:
```python
custom_settings = {
    "DEFAULT_REQUEST_HEADERS": {
        "Authorization": f"Bearer {os.environ['API_TOKEN']}",
    },
}
```

Or cookie-based:
```python
custom_settings = {
    "COOKIES_ENABLED": True,
}

def start_requests(self):
    yield scrapy.Request(
        url,
        cookies={"session": os.environ["SESSION_COOKIE"]},
    )
```

### 3. OAuth / Token-based

For sites with OAuth flow, guide user to:
1. Manually obtain the token (browser DevTools → Network → copy auth header)
2. Store in env var
3. Spider uses header auth (strategy 2)

## Credential Management

NEVER hardcode credentials. Always:
1. Create `.env.template` with required vars:
   ```
   SITE_USERNAME=
   SITE_PASSWORD=
   ```
2. Add `.env` to `.gitignore`
3. Load in settings via `os.environ.get()`
4. Warn user if `.env` is not in `.gitignore`
