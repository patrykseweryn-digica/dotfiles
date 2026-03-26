---
name: digica-md2docx
description: Convert Markdown files to styled DOCX documents using Digica corporate template (Outfit font, branded header/footer). Use when user wants to create a .docx from markdown, convert MD to Word, generate a document for Google Docs import, or mentions "md2docx", "markdown to docx", "zrób docx", "skonwertuj na docx". Produces Google Docs-compatible output with embedded Outfit fonts.
---

# Digica MD→DOCX Converter

Convert Markdown to professionally styled DOCX using the Digica corporate template.

## Quick Start

```bash
python scripts/md2docx.py input.md [output.docx]
```

If output path is omitted, creates `input.docx` next to the source file.

## Dependencies

Install before first use:

```bash
pip install python-docx markdown-it-py Pillow
```

## Style Mapping

| Markdown | DOCX Style | Font | Size | Bold |
|----------|-----------|------|------|------|
| `#` | Heading 1 | Outfit | 20pt | Yes |
| `##` | Heading 2 | Outfit | 16pt | Yes |
| `###` | Heading 3 | Outfit | 14pt | Yes |
| `####` | Heading 4 | Outfit | 12pt | Yes |
| `#####` | Heading 5 | Outfit | 11pt | Yes |
| `######` | Heading 6 | Outfit | 10pt | Yes |
| body text | Normal | Outfit | 11pt | No |
| `` `code` `` | inline | Courier New | 11pt | No |
| code fence | block | Courier New | 9pt | No |

## Supported Elements

- **Headings** H1–H6 (all bold Outfit)
- **Inline**: bold, italic, inline code (grey background), links (blue + URL in brackets)
- **Lists**: bullet (`•` `◦` `▪` by depth), numbered, nested up to 3 levels
- **Tables**: with column alignment (left/center/right), bold blue header row
- **Code blocks**: grey background, Courier New 9pt
- **Images**: centered, scaled to max 16cm width, preserves aspect ratio
- **Horizontal rules**: thin bottom border

## Template

The template (`assets/template.docx`) includes:
- Digica header with company logos
- Footer with contact email
- Embedded Outfit fonts (regular + bold in `assets/fonts/`)
- Pre-configured heading and body styles

## How Claude Should Use This

1. User provides a markdown file or writes markdown content
2. Save content to a `.md` file if needed
3. Run the conversion script:
   ```bash
   python /path/to/scripts/md2docx.py input.md
   ```
4. Report the output path to the user

For images in markdown: support both relative (`./img.png`) and absolute paths. Images are centered and capped at page width.
