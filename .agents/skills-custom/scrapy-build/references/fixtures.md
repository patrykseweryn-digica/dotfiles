# Fixtures

A fixture is a saved response plus the expected item. web-poet's pytest
plugin turns each fixture into tests, one test per field.

## Save

```bash
uv run scrapy savefixture base.pages.books_toscrape_com.BooksToscrapeBookPage \
  "https://books.toscrape.com/catalogue/some-book_1/index.html"
```

- `savefixture` boots the full crawler stack: settings, addons, and fetch
  tier. It needs the project, settings, and the stub class first.
- It writes `tests/fixtures/<page-object-fqn>/test-N/`.
- Use the page object class of the URL's own domain.
- Take detail URLs from the saved list fixture, not from memory. Use its
  links, or build URLs from inline script JSON when the list has no links.
- Save one fixture per page object first. Add more fixtures for page
  variants, for example a product without a discount.

## Clean

```bash
uv run python scripts/clean_fixture.py tests/fixtures/<page-object-fqn>/test-N
```

The script writes next to the raw input:

| File | Use |
|---|---|
| `<Response>-body.html` | Raw response. Write and check selectors here. |
| `<Response>-body-clean.html` | Read to find content. Never select here. |
| `<Response>-body.txt` | Read to fill `output.json`. |

`<Response>` is `HttpResponse`, or `BrowserResponse` for `BrowserPage`.
The script skips JSON and XML bodies; read those raw. Why clean at all:
raw pages are often 100-700 KB, and the clean files are 50-95% smaller.

## Subagent brief (step 7)

Spawn one subagent per page object, all in parallel. Give each this brief:

```
Project root: <root>. Items: base/items.py (<item class>).
Page object: <fqn> in <file>. Fixture: <fixture dir>.
Fields: <field list with meaning>.
Other subagents edit other classes in the same file at the same time.
Edit only your class, with targeted edits. Never rewrite the whole file.
1. Read inputs/<Response>-body.txt. Write expected values to output.json.
   URL fields are not in .txt: take them from the raw HTML links or from
   inline <script> JSON.
2. Find each field in -clean.html. Write CSS/XPath selectors and check
   them against the raw inputs/<Response>-body.html.
3. Put the selectors in your class. Keep @field and Returns[Item].
4. Run `uv run pytest tests/fixtures/<fqn>` until all tests pass.
Code style: `str | None` not Optional; no trailing `return None`;
`ClassVar` on mutable class attributes; wrap urljoin() in str().
Do not fetch any page. Do not run `ruff --fix` or edit settings.
Report: fields that stay None and why, and the pytest result.
```

After all subagents finish, the main agent runs `uv run ruff check --fix`
and `uv run pytest` on the whole project. Why: a subagent cannot fix lint
in a shared file without touching other classes.

Why subagents: each page object is independent, and selector work is the
most token-heavy step. The main agent keeps the other steps.

## output.json

- Values must equal what the selectors return, not a summary. Why: a
  shortened description fails its test.
- A field that is truly absent on the page stays `null`.
- After a field changes in the page object, update every fixture of that
  class.
