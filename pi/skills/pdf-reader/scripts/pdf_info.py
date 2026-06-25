#!/usr/bin/env python3
"""PDF metadata and per-page analysis. Always run this first to triage a PDF."""

import sys
import json
import pymupdf


def analyze(path: str) -> dict:
    doc = pymupdf.open(path)
    meta = doc.metadata or {}

    pages = []
    for i, page in enumerate(doc):
        text = page.get_text()
        text_len = len(text)
        images = page.get_images(full=True)

        # Estimate math density: ratio of unicode math-range chars to total chars
        math_chars = sum(
            1 for c in text
            if ('∀' <= c <= '⋿')    # Mathematical Operators
            or ('℀' <= c <= '⅏')     # Letterlike Symbols
            or ('←' <= c <= '⇿')     # Arrows
            or ('⟀' <= c <= '⟯')     # Misc Mathematical Symbols-A
            or ('⦀' <= c <= '⧿')     # Misc Mathematical Symbols-B
            or ('⨀' <= c <= '⫿')     # Supplemental Mathematical Operators
            or ('Ͱ' <= c <= 'Ͽ')     # Greek
            or ('ᵀ0' <= c <= 'ᵿF')   # Mathematical Alphanumeric Symbols
            or c in '∫∑∏√∂∇∞≈≠≤≥±×÷∈∉⊂⊃∪∩∧∨¬∀∃∅'
        )
        math_density = math_chars / max(text_len, 1)

        pages.append({
            "page": i + 1,
            "text_length": text_len,
            "image_count": len(images),
            "math_density": round(math_density, 4),
        })

    # Try to extract TOC
    toc = doc.get_toc()
    toc_entries = [
        {"level": level, "title": title, "page": page_num}
        for level, title, page_num in toc
    ]

    result = {
        "file": path,
        "page_count": len(doc),
        "title": meta.get("title", ""),
        "author": meta.get("author", ""),
        "subject": meta.get("subject", ""),
        "toc": toc_entries,
        "pages": pages,
    }

    doc.close()
    return result


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: pdf_info.py <path>", file=sys.stderr)
        sys.exit(1)

    result = analyze(sys.argv[1])
    print(json.dumps(result, indent=2))
