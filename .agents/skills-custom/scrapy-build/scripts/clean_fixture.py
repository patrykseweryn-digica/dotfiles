"""Shrink saved web-poet fixtures into files an agent can read cheaply.

Usage:
    python scripts/clean_fixture.py tests/fixtures/<page-object>/test-N [...]

For each inputs/<Response>-body.html in a fixture, write next to it:
    <Response>-body-clean.html  readable HTML; find content here
    <Response>-body.txt         plain text; copy expected values from here

Never write selectors against the clean HTML: clear-html drops class and id
attributes and renames tags. Selectors target the raw <Response>-body.html.

JSON and XML bodies are skipped; read them raw. This script only reads
files that `scrapy savefixture` wrote. It never fetches a page.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from clear_html import clean_node, cleaned_node_to_html, cleaned_node_to_text
from lxml.html import document_fromstring

BODY_SUFFIX = "-body.html"
XML_DECLARATION = re.compile(r"^\s*<\?xml[^>]*\?>", re.IGNORECASE)
XML_ROOTS = ("<urlset", "<sitemapindex", "<rss", "<feed")


def body_kind(text: str) -> str:
    """Return 'json', 'xml', or 'html' for a decoded response body."""
    head = text.lstrip()[:200].lower()
    if head.startswith(("{", "[")):
        return "json"
    if head.startswith(XML_ROOTS):
        return "xml"
    return "html"


def response_url(inputs: Path, prefix: str) -> str | None:
    """Read the response URL so clear-html can absolutize links."""
    info = inputs / f"{prefix}-info.json"
    if info.is_file():
        return json.loads(info.read_text(encoding="utf-8")).get("url")
    url_file = inputs / "ResponseUrl.txt"
    if url_file.is_file():
        return url_file.read_text(encoding="utf-8").strip() or None
    return None


def clean_body(body: Path) -> str:
    """Clean one raw body file and return a one-line report."""
    inputs = body.parent
    prefix = body.name.removesuffix(BODY_SUFFIX)
    # Decode explicitly: lxml falls back to Latin-1 when a page has no
    # charset declaration, which garbles non-ASCII text.
    text = body.read_bytes().decode("utf-8", errors="replace")
    # lxml rejects str input that keeps an XML encoding declaration.
    text = XML_DECLARATION.sub("", text, count=1)

    kind = body_kind(text)
    if kind != "html":
        return f"{body}: {kind} body, skipped (read it raw)"

    node = clean_node(document_fromstring(text), response_url(inputs, prefix))
    clean_path = inputs / f"{prefix}-body-clean.html"
    text_path = inputs / f"{prefix}-body.txt"
    clean_path.write_text(cleaned_node_to_html(node), encoding="utf-8")
    text_path.write_text(cleaned_node_to_text(node) or "", encoding="utf-8")

    raw_kb = body.stat().st_size / 1024
    clean_kb = clean_path.stat().st_size / 1024
    return f"{body}: {raw_kb:.0f} KB -> {clean_path.name} {clean_kb:.0f} KB, {text_path.name}"


def raw_bodies(fixture: Path) -> list[Path]:
    # "*-body.html" never matches the "*-body-clean.html" outputs.
    return sorted((fixture / "inputs").glob(f"*{BODY_SUFFIX}"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Shrink saved web-poet fixtures into files an agent can read cheaply."
    )
    parser.add_argument("fixtures", nargs="+", type=Path, help="test-N directories")
    args = parser.parse_args(argv)

    status = 0
    for fixture in args.fixtures:
        bodies = raw_bodies(fixture)
        if not bodies:
            print(
                f"{fixture}: no inputs/*{BODY_SUFFIX}; run savefixture first",
                file=sys.stderr,
            )
            status = 1
            continue
        for body in bodies:
            print(clean_body(body))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
