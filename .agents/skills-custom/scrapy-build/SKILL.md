---
name: scrapy-build
description: "Build or extend Scrapy projects with the JWR method: web-poet page objects, scrapy-poet injection, savefixture tests, one spider for many domains, and an HTTP, curl_cffi, Playwright, or Zyte API fetch ladder. Use when creating a Scrapy project, adding a domain or spider, or writing page objects."
argument-hint: "[urls] [browser=patchright|camoufox] [zyte]"
---

# Scrapy Build

Scrapy is the default production implementation path. This skill follows the
JWR method from `zytelabs/scrapy-openspec`. Each rule below fixed a real
mistake, so follow it even when another way looks shorter.

## Inputs

Collect these before you write code:

- Start URLs for every domain.
- Record fields per domain. Ask the user; never guess the schema.
- Browser backend: `patchright` (default) or `camoufox` when the user asks.
- Zyte API: off unless the user asks. Read `references/fetching.md`.
- Production layer: off unless the user asks. Read `references/production.md`.

## Creation flow

Run the steps in this order. Each step needs the output of the previous one.

1. Create the project, `.gitignore`, and pytest config. Copy
   `scripts/clean_fixture.py` from this skill into the project's `scripts/`.
   Read `references/project-setup.md`.
2. Replace the `startproject` templates. Configure `settings.py` for
   tier 1 of the fetch ladder only.
3. Write `items.py`: one record item and one list item per record type.
   Read `references/page-objects.md`.
4. Generate the spider scaffold with `scrapy genspider`.
5. Create `base/pages/__init__.py`. Write page object stubs with `pass`
   bodies, one file per domain.
6. For sites that sell products, probe platform APIs first
   (`references/platform-apis.md`). Save and clean one fixture per page
   object. Take detail URLs from the saved list fixture: links or inline
   script JSON. Raise a domain's fetch tier only in this step. Read
   `references/fixtures.md` and `references/fetching.md`.
7. Spawn one subagent per page object, in parallel. Each subagent writes
   `output.json`, writes selectors, and makes its fixture tests pass.
   Then run `ruff check --fix base/pages` and `pytest`.
8. Write the spider body. Read `references/spider.md`.
9. Verify: `ruff check`, `ruff format`, `pyright`, `pytest`, sample crawl.

## Hard rules

- Get page HTML only from `scrapy savefixture` during the build. Do not use
  curl, httpx, fetch tools, or a browser. Why: fixtures are the test input,
  so selectors match what the spider receives.
- If `savefixture` fails, fix the cause: missing stub, settings, URL, or key.
  Do not write a download script. Why: a workaround hides a broken project.
- Write selectors against the raw `<Response>-body.html`, never the
  `-clean.html`. Why: clear-html drops `class`/`id` and renames tags.
- Use `@field` and `Returns[Item]`. Never `@property` or `to_item()`.
  Why: scrapy-poet builds items only from `@field` methods.
- Type spider callbacks with items, never page objects. Why: the spider
  stays domain-agnostic, so a new domain needs no spider change.
- Raise a domain's fetch tier only after its raw fixture shows the
  problem. Pick the lowest tier that fixes that problem. Why: each tier
  costs speed, money, or stability.
- If a fixture contradicts what the user described, tell the user before
  you choose a workaround. Example: the listing has no links to details.
- Copy expected values into `output.json` exactly as selectors return them.
  Why: a shortened value fails the test.
- Append new `pyproject.toml` sections at the end of the file. Why: an
  insert inside `[project]` duplicates a header and breaks the TOML.

## References

- `references/project-setup.md`: layout, dependencies, settings, pytest.
- `references/page-objects.md`: items, naming, `handle_urls`, stubs.
- `references/spider.md`: async spider, `urls`, new domains.
- `references/fixtures.md`: savefixture, cleaning, subagent brief.
- `references/fetching.md`: fetch ladder, Playwright, curl_cffi, Zyte API.
- `references/platform-apis.md`: Shopify and Ecwid JSON APIs.
- `references/production.md`: sample/full mode, outputs, structlog, SQLite.

## Boundaries

- Docker, scheduling, monitoring, alerts: use `scrapy-deploy`.
- Click, scroll, or stateful UI flows: use `crawlee-build`.
- Feasibility proof only: use `web-scraping-simple`.
- Broken existing spider: use `web-scraping-debug`.
