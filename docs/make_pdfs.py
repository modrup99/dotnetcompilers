#!/usr/bin/env python3
"""Render each language's Markdown reference (<lang>/<lang>.md) to a styled PDF in
docs/pdf/. Markdown -> HTML (python-markdown) -> PDF (headless Chrome).

Usage:  py docs/make_pdfs.py
"""
import os
import subprocess
import sys
import markdown

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF_DIR = os.path.join(ROOT, "docs", "pdf")
HTML_DIR = os.path.join(ROOT, "docs", "_html")

# (markdown file, output basename, friendly title)
DOCS = [
    ("qbasic/qbasic.md", "QBasic",      "QBasic"),
    ("cpp/tcpp.md",      "TinyCpp",     "Tiny C++"),
    ("forth/forth.md",   "Forth",       "Forth"),
    ("logo/logo.md",     "Logo",        "Logo"),
    ("lisp/lisp.md",     "Lisp",        "Lisp"),
    ("prolog/prolog.md", "Prolog",      "Prolog"),
    ("bc/bc.md",         "bc",          "bc"),
    ("coil/coil.md",     "Coil",        "Coil"),
    ("fortran/fortran.md", "Fortran90", "Fortran 90"),
    ("cobol/cobol.md",   "COBOL",       "COBOL"),
    ("ada/ada.md",       "Ada",         "Ada"),
]

CSS = """
@page { size: A4; margin: 18mm 16mm; }
* { box-sizing: border-box; }
body { font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
       font-size: 10.5pt; line-height: 1.5; color: #1b1f23; max-width: 100%; }
h1 { font-size: 22pt; border-bottom: 3px solid #2b6cb0; padding-bottom: 6px; color: #1a365d; }
h2 { font-size: 15pt; margin-top: 22px; border-bottom: 1px solid #d0d7de; padding-bottom: 4px; color: #2b4f72; }
h3 { font-size: 12pt; margin-top: 18px; color: #2b4f72; }
p, li { font-size: 10.5pt; }
code { font-family: "Cascadia Code", "Consolas", monospace; font-size: 9.5pt;
       background: #f3f4f6; padding: 1px 4px; border-radius: 3px; color: #b5306a; }
pre { background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px;
      padding: 10px 12px; overflow-x: auto; page-break-inside: avoid; }
pre code { background: none; padding: 0; color: #1b1f23; font-size: 9pt; line-height: 1.45; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; }
th, td { border: 1px solid #d0d7de; padding: 5px 9px; text-align: left; font-size: 9.5pt; }
th { background: #eef2f7; }
hr { border: none; border-top: 1px solid #d0d7de; margin: 20px 0; }
a { color: #2b6cb0; text-decoration: none; }
blockquote { border-left: 3px solid #d0d7de; margin: 0; padding-left: 12px; color: #57606a; }
h2, h3 { page-break-after: avoid; }
"""

HTML_TMPL = """<!doctype html><html><head><meta charset="utf-8">
<title>{title}</title><style>{css}</style></head><body>{body}</body></html>"""


def find_chrome():
    for p in [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]:
        if os.path.exists(p):
            return p
    sys.exit("no Chrome/Edge found")


def main():
    os.makedirs(PDF_DIR, exist_ok=True)
    os.makedirs(HTML_DIR, exist_ok=True)
    browser = find_chrome()
    md = markdown.Markdown(extensions=["fenced_code", "tables", "toc", "sane_lists"])
    for rel, base, title in DOCS:
        src = os.path.join(ROOT, rel)
        if not os.path.exists(src):
            print("  skip (missing):", rel); continue
        md.reset()
        with open(src, encoding="utf-8") as f:
            body = md.convert(f.read())
        html_path = os.path.join(HTML_DIR, base + ".html")
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(HTML_TMPL.format(title=title, css=CSS, body=body))
        pdf_path = os.path.join(PDF_DIR, base + ".pdf")
        subprocess.run([
            browser, "--headless=new", "--disable-gpu", "--no-sandbox",
            "--no-pdf-header-footer", "--print-to-pdf=" + pdf_path,
            "file:///" + html_path.replace("\\", "/"),
        ], check=True, capture_output=True)
        ok = os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 0
        print(f"  {'OK ' if ok else 'ERR'} {rel} -> docs/pdf/{base}.pdf ({os.path.getsize(pdf_path) if ok else 0} bytes)")


if __name__ == "__main__":
    main()
