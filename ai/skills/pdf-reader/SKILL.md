---
name: pdf-reader
description: Read and understand PDF files, especially math lecture notes and academic papers. Use when the user asks to read, analyze, or search a PDF's content. For creating, editing, merging or filling PDFs, use the pdf skill.
---

# PDF Reader

Read and comprehend PDF files, especially math lecture notes and academic papers. Uses a hybrid text extraction + vision approach for maximum comprehension of equations, diagrams, and structured content.

## Setup

The scripts need `pymupdf` in a venv at `SKILL_DIR/.venv`. If it is missing, run `python -m venv SKILL_DIR/.venv`, then install `requirements.txt` with that venv's pip.
The venv interpreter is `SKILL_DIR/.venv/Scripts/python.exe` on Windows and `SKILL_DIR/.venv/bin/python` elsewhere. On Windows, `python3` is a Store stub, so use `python`.

## Scripts

All scripts are in `SKILL_DIR/scripts/`.

| Script | Purpose | Key args |
|---|---|---|
| `pdf_info.py <path>` | Metadata + per-page analysis (page count, TOC, text density, math density, image count) | — |
| `pdf_extract.py <path> [--pages SPEC]` | Extract text by page | `--pages all\|1-5\|1,3,7\|3` |
| `pdf_render.py <path> [--pages SPEC] [--dpi N]` | Render pages to PNG images in `<system temp>/pdf-reader-*/` | `--pages`, `--dpi` (default 150) |
| `pdf_search.py <path> <query> [--context N] [--literal]` | Search text content by regex or literal | `--context` lines (default 3), `--literal` flag |

Page specs: `all`, `1-5`, `1,3,7`, `3` (1-indexed, inclusive ranges).

## Strategy: How to Read a PDF

### Step 1: Always Triage First

Run `pdf_info.py` on every new PDF before doing anything else. This tells you:
- How many pages (determines strategy)
- Whether there's a TOC (enables structural navigation)
- Per-page math density and image count (identifies which pages need vision)
- Per-page text length (spots pages that are mostly diagrams/figures)

### Step 2: Pick a Strategy Based on Size and Content

#### Short PDFs (≤15 pages)
- Read the PDF directly with the Read tool (up to 20 pages per call). Render a page at 200 DPI only when its equations come out unreadable.

#### Medium PDFs (15–60 pages)
- Extract all text first (cheap, gives structural overview)
- Check `pdf_info.py` output for pages with high `math_density` (>0.02) or `image_count` > 0 or low `text_length` (<100, likely diagram-only pages)
- Render only those math/diagram-heavy pages as images
- Read those images with `read` for equation and figure comprehension
- For the rest, text extraction is sufficient

#### Long PDFs (60+ pages)
- Extract text for a structural overview — focus on TOC and section headers
- Do NOT render all pages (too many tokens)
- For targeted questions: use `pdf_search.py` to find relevant pages, then render those
- For full comprehension: work section by section, summarizing as you go
- Warn the user about scope — offer to focus on specific sections

### Step 3: Targeted Lookups

When the user asks about something specific (e.g., "check theorem 3.2", "what's on page 7"):
1. `pdf_search.py <path> "theorem 3.2"` — find the page
2. `pdf_render.py <path> --pages <page>` — render just that page
3. `read` the image — see the actual theorem with proper math rendering
4. If context is needed, extract text from surrounding pages

### Step 4: Visual Reading Guidelines

When reading rendered page images:
- **150 DPI** (default) is good for most math and text
- **200 DPI** if equations are small, dense, or hard to read at 150
- **100 DPI** only for quick structural scanning (saves tokens)
- State equations explicitly in your response using LaTeX notation when discussing them
- Describe diagrams and figures in detail — the user may not be looking at the PDF simultaneously
- Note page numbers when referencing content so the user can find it

### Step 5: What to Watch For

- **Pages with low text_length but high image_count**: likely full-page diagrams or figures — always render these
- **Pages with high math_density**: equations that text extraction will mangle — always render these
- **Pages with decent text but zero math**: text extraction alone is fine, skip rendering
- **TOC entries**: use these to navigate structurally rather than reading linearly

