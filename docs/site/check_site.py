#!/usr/bin/env python3
"""Check a built HonKit site before it is published.

  python3 docs/site/check_site.py build/site

Fails on: internal links or images that do not resolve, #anchors with no matching
id, links still pointing at .md files, GitBook template tags or Markdown tables left
unrendered, pages missing from the output, and pages without the custom sidebar
(theme/_layouts) marking the current page.
"""
import os
import re
import sys
from html.parser import HTMLParser
from urllib.parse import unquote, urlparse

site = sys.argv[1] if len(sys.argv) > 1 else 'build/site'
errors = []


def error(msg):
    errors.append(msg)
    print(f'::error::{msg}' if os.environ.get('GITHUB_ACTIONS') else f'ERROR: {msg}')


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.images = set(), [], []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a: self.ids.add(a['id'])
        if 'name' in a and tag == 'a': self.ids.add(a['name'])
        if tag == 'a' and a.get('href'): self.links.append(a['href'])
        if tag == 'img' and a.get('src'): self.images.append(a['src'])


pages = {}
for d, _, files in os.walk(site):
    if os.path.relpath(d, site).split(os.sep)[0] == 'gitbook':
        continue  # theme and plugin assets
    for f in files:
        if f.endswith('.html'):
            path = os.path.normpath(os.path.join(d, f))
            parser = Page()
            text = open(path, encoding='utf-8').read()
            parser.feed(text)
            pages[path] = (parser, text)

if not pages:
    error(f'no HTML pages found in {site}')

for path, (page, text) in pages.items():
    rel = os.path.relpath(path, site)
    body = re.sub(r'<script.*?</script>', '', text, flags=re.S)
    if re.search(r'{%\s*(end)?hint', body):
        error(f'{rel}: unrendered {{% hint %}} tag')
    if re.search(r'\|\s*-{3,}\s*\|', body):
        error(f'{rel}: unrendered Markdown table (a table nested in a list item?)')
    if 'class="paco-brand"' not in text:
        error(f'{rel}: default sidebar (theme/_layouts override not applied)')
    elif text.count('aria-current="page"') != 1:
        error(f'{rel}: sidebar does not mark exactly one current page')
    for href in page.links:
        u = urlparse(href)
        if u.scheme or href.startswith('//') or href.startswith('mailto:'):
            continue
        target = os.path.normpath(os.path.join(os.path.dirname(path), unquote(u.path))) if u.path else path
        if os.path.isdir(target):
            target = os.path.join(target, 'index.html')
        if u.path.endswith('.md'):
            error(f'{rel}: link still points to Markdown: {href}')
        elif not os.path.exists(target):
            error(f'{rel}: broken link {href}')
        elif u.fragment and target in pages and unquote(u.fragment) not in pages[target][0].ids:
            error(f'{rel}: unknown anchor {href}')
    for src in page.images:
        u = urlparse(src)
        if u.scheme or src.startswith('//') or src.startswith('data:'):
            continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(path), unquote(u.path)))):
            error(f'{rel}: missing image {src}')

for required in ('index.html', 'user-guide/index.html', 'developer-guide/index.html'):
    if os.path.normpath(os.path.join(site, required)) not in pages:
        error(f'missing page {required}')

mermaid = sum(t.count('class="mermaid-src"') for _, t in pages.values())
figures = sum(t.count('<figure>') for _, t in pages.values())
print(f'Checked {len(pages)} pages, {figures} figures, {mermaid} Mermaid diagrams: '
      f'{"OK" if not errors else f"{len(errors)} problem(s)"}')
sys.exit(1 if errors else 0)
