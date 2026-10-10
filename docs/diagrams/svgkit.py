"""Tiny SVG builder with PaCo's shared palette and icons."""
from xml.sax.saxutils import escape

FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, 'SF Mono', Menlo, Consolas, monospace"
C = dict(
    ink='#0F172A', muted='#64748B', faint='#94A3B8', line='#CBD5E1', border='#E2E8F0',
    panel='#F8FAFC', panel2='#F1F5F9', white='#FFFFFF',
    blue='#2563EB', blueL='#DBEAFE', blueM='#93C5FD',
    green='#16A34A', greenL='#DCFCE7', greenM='#86EFAC',
    red='#DC2626', redL='#FEE2E2', redM='#FCA5A5',
    orange='#EA580C', orangeL='#FFEDD5', orangeM='#FDBA74',
    purple='#7C3AED', purpleL='#EDE9FE',
    slate='#334155', slateL='#E2E8F0', amberL='#FEF3C7', amber='#B45309',
)
ARROW_COLORS = ['ink', 'muted', 'blue', 'green', 'red', 'orange', 'purple', 'slate', 'faint']


class SVG:
    def __init__(self, w, h, title, desc=''):
        self.w, self.h, self.title, self.desc = w, h, title, desc
        self.parts = []

    # ---- primitives -------------------------------------------------------
    def add(self, s):
        self.parts.append(s)

    def rect(self, x, y, w, h, fill='none', stroke=None, rx=8, sw=1.5, dash=None, opacity=None):
        a = f'x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"'
        if stroke: a += f' stroke="{stroke}" stroke-width="{sw}"'
        if dash: a += f' stroke-dasharray="{dash}"'
        if opacity is not None: a += f' opacity="{opacity}"'
        self.add(f'<rect {a}/>')

    def text(self, x, y, s, size=14, fill=None, weight=400, anchor='start', mono=False, italic=False, opacity=None):
        fill = fill or C['ink']
        fam = MONO if mono else FONT
        a = f'x="{x}" y="{y}" font-family="{fam}" font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"'
        if italic: a += ' font-style="italic"'
        if opacity is not None: a += f' opacity="{opacity}"'
        self.add(f'<text {a}>{escape(s)}</text>')

    def lines(self, x, y, rows, size=14, lh=None, **kw):
        lh = lh or round(size * 1.35)
        for i, r in enumerate(rows):
            self.text(x, y + i * lh, r, size=size, **kw)

    def line(self, x1, y1, x2, y2, color='muted', sw=2, arrow=False, start_arrow=False, dash=None):
        col = C.get(color, color)
        a = f'x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="{sw}" stroke-linecap="round"'
        if dash: a += f' stroke-dasharray="{dash}"'
        if arrow: a += f' marker-end="url(#a-{color})"'
        if start_arrow: a += f' marker-start="url(#a-{color})"'
        self.add(f'<line {a}/>')

    def path(self, d, color='muted', sw=2, fill='none', arrow=False, start_arrow=False, dash=None):
        col = C.get(color, color)
        a = f'd="{d}" stroke="{col}" stroke-width="{sw}" fill="{fill}" stroke-linecap="round" stroke-linejoin="round"'
        if dash: a += f' stroke-dasharray="{dash}"'
        if arrow: a += f' marker-end="url(#a-{color})"'
        if start_arrow: a += f' marker-start="url(#a-{color})"'
        self.add(f'<path {a}/>')

    def circle(self, cx, cy, r, fill='none', stroke=None, sw=1.5):
        a = f'cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
        if stroke: a += f' stroke="{stroke}" stroke-width="{sw}"'
        self.add(f'<circle {a}/>')

    # ---- composite pieces -------------------------------------------------
    def box(self, x, y, w, h, title, sub=None, fill=None, stroke=None, tcolor=None, scolor=None,
            tsize=14, ssize=12, rx=10, mono_sub=False, mono_title=False):
        self.rect(x, y, w, h, fill=fill or C['white'], stroke=stroke or C['line'], rx=rx)
        cx = x + w / 2
        if sub is None:
            self.text(cx, y + h / 2 + tsize * 0.36, title, size=tsize, weight=600, anchor='middle',
                      fill=tcolor, mono=mono_title)
        else:
            subs = sub if isinstance(sub, list) else [sub]
            total = tsize + 6 + len(subs) * (ssize + 4)
            ty = y + (h - total) / 2 + tsize * 0.9
            self.text(cx, ty, title, size=tsize, weight=600, anchor='middle', fill=tcolor, mono=mono_title)
            for i, s in enumerate(subs):
                self.text(cx, ty + 6 + (i + 1) * (ssize + 4) - 2, s, size=ssize, anchor='middle',
                          fill=scolor or C['muted'], mono=mono_sub)

    def pill(self, x, y, w, h, label, fill, color, size=12, weight=600):
        self.rect(x, y, w, h, fill=fill, rx=h / 2)
        self.text(x + w / 2, y + h / 2 + size * 0.36, label, size=size, weight=weight, anchor='middle', fill=color)

    def button(self, x, y, w, h, label, kind='primary', size=12):
        if kind == 'primary':
            self.rect(x, y, w, h, fill=C['blue'], rx=6)
            self.text(x + w / 2, y + h / 2 + size * 0.36, label, size=size, weight=600, anchor='middle', fill='#fff')
        else:
            self.rect(x, y, w, h, fill=C['white'], stroke=C['line'], rx=6, sw=1)
            col = C['red'] if kind == 'danger' else C['ink']
            self.text(x + w / 2, y + h / 2 + size * 0.36, label, size=size, weight=500, anchor='middle', fill=col)

    def num(self, cx, cy, n, fill=None, r=13):
        self.circle(cx, cy, r, fill=fill or C['blue'])
        self.text(cx, cy + 5, str(n), size=14, weight=700, anchor='middle', fill='#fff')

    # ---- icons --------------------------------------------------------------
    def shield(self, cx, cy, s, color, slash=False, check=False, fill=None):
        d = (f'M{cx},{cy - s} L{cx + 0.82 * s},{cy - 0.62 * s} L{cx + 0.82 * s},{cy + 0.08 * s} '
             f'Q{cx + 0.82 * s},{cy + 0.78 * s} {cx},{cy + 1.12 * s} '
             f'Q{cx - 0.82 * s},{cy + 0.78 * s} {cx - 0.82 * s},{cy + 0.08 * s} '
             f'L{cx - 0.82 * s},{cy - 0.62 * s} Z')
        self.add(f'<path d="{d}" fill="{fill or color}" stroke="{color}" stroke-width="{max(1, s * 0.12)}" stroke-linejoin="round"/>')
        inner = '#fff'
        if slash:
            self.add(f'<line x1="{cx - 0.55 * s}" y1="{cy - 0.55 * s}" x2="{cx + 0.55 * s}" y2="{cy + 0.75 * s}" '
                     f'stroke="{inner}" stroke-width="{max(1.5, s * 0.16)}" stroke-linecap="round"/>')
        elif check:
            self.add(f'<path d="M{cx - 0.38 * s},{cy + 0.08 * s} L{cx - 0.08 * s},{cy + 0.4 * s} L{cx + 0.42 * s},{cy - 0.25 * s}" '
                     f'stroke="{inner}" stroke-width="{max(1.5, s * 0.16)}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
        else:  # checkered: lighten the top-right and bottom-left quarters
            m = cy + 0.05 * s
            q1 = f'M{cx},{cy - s} L{cx + 0.82 * s},{cy - 0.62 * s} L{cx + 0.82 * s},{m} L{cx},{m} Z'
            q2 = (f'M{cx - 0.82 * s},{m} L{cx},{m} L{cx},{cy + 1.12 * s} '
                  f'Q{cx - 0.82 * s},{cy + 0.78 * s} {cx - 0.82 * s},{cy + 0.08 * s} Z')
            self.add(f'<path d="{q1} {q2}" fill="{inner}" opacity="0.42"/>')

    def laptop(self, x, y, w, screen_fill=None, color=None):
        color = color or C['slate']
        h = w * 0.62
        self.rect(x, y, w, h, fill=color, rx=w * 0.05)
        self.rect(x + w * 0.05, y + w * 0.05, w * 0.9, h - w * 0.09, fill=screen_fill or C['panel'], rx=w * 0.02)
        by = y + h
        self.add(f'<path d="M{x - w * 0.1},{by + 2} L{x + w * 1.1},{by + 2} L{x + w * 1.05},{by + w * 0.07} '
                 f'L{x - w * 0.05},{by + w * 0.07} Z" fill="{color}"/>')
        return (x + w / 2, y + h / 2)

    def lock(self, cx, cy, s, color=None, bg=None):
        color = color or C['slate']
        if bg: self.circle(cx, cy + s * 0.1, s * 1.15, fill=bg)
        self.add(f'<path d="M{cx - 0.4 * s},{cy - 0.1 * s} V{cy - 0.45 * s} A{0.4 * s},{0.4 * s} 0 0 1 {cx + 0.4 * s},{cy - 0.45 * s} V{cy - 0.1 * s}" '
                 f'stroke="{color}" stroke-width="{s * 0.16}" fill="none"/>')
        self.rect(cx - 0.6 * s, cy - 0.12 * s, 1.2 * s, 0.9 * s, fill=color, rx=s * 0.12)

    def cloud(self, cx, cy, s, fill, stroke):
        d = (f'M{cx - 1.1 * s},{cy + 0.45 * s} A{0.45 * s},{0.45 * s} 0 0 1 {cx - 0.9 * s},{cy - 0.3 * s} '
             f'A{0.6 * s},{0.6 * s} 0 0 1 {cx + 0.1 * s},{cy - 0.55 * s} A{0.5 * s},{0.5 * s} 0 0 1 {cx + 0.95 * s},{cy - 0.1 * s} '
             f'A{0.42 * s},{0.42 * s} 0 0 1 {cx + 1.05 * s},{cy + 0.45 * s} Z')
        self.add(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="2" stroke-linejoin="round"/>')

    def checkmark(self, cx, cy, r, color):
        self.circle(cx, cy, r, fill=color)
        self.add(f'<path d="M{cx - r * 0.45},{cy} L{cx - r * 0.1},{cy + r * 0.38} L{cx + r * 0.5},{cy - r * 0.35}" '
                 f'stroke="#fff" stroke-width="{r * 0.28}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')

    def cross(self, cx, cy, r, color):
        self.circle(cx, cy, r, fill=color)
        k = r * 0.4
        self.add(f'<path d="M{cx - k},{cy - k} L{cx + k},{cy + k} M{cx + k},{cy - k} L{cx - k},{cy + k}" '
                 f'stroke="#fff" stroke-width="{r * 0.28}" stroke-linecap="round"/>')

    def person(self, cx, cy, s, color):
        self.circle(cx, cy - 0.35 * s, 0.32 * s, fill=color)
        self.add(f'<path d="M{cx - 0.6 * s},{cy + 0.6 * s} Q{cx - 0.6 * s},{cy + 0.05 * s} {cx},{cy + 0.05 * s} '
                 f'Q{cx + 0.6 * s},{cy + 0.05 * s} {cx + 0.6 * s},{cy + 0.6 * s} Z" fill="{color}"/>')

    def clock(self, cx, cy, r, color):
        self.circle(cx, cy, r, fill='#fff', stroke=color, sw=r * 0.18)
        self.add(f'<path d="M{cx},{cy - r * 0.55} L{cx},{cy} L{cx + r * 0.42},{cy + r * 0.25}" stroke="{color}" '
                 f'stroke-width="{r * 0.16}" fill="none" stroke-linecap="round"/>')

    def toggle(self, x, y, on, w=40, h=22):
        self.rect(x, y, w, h, fill=C['green'] if on else C['line'], rx=h / 2)
        self.circle(x + (w - h / 2) if on else x + h / 2, y + h / 2, h / 2 - 2.5, fill='#fff')

    def file(self, x, y, w, h, label, color=None, mono=True, size=11):
        color = color or C['slate']
        f = min(12, w * 0.2)
        self.add(f'<path d="M{x},{y} H{x + w - f} L{x + w},{y + f} V{y + h} H{x} Z" fill="#fff" stroke="{color}" stroke-width="1.5" stroke-linejoin="round"/>')
        self.add(f'<path d="M{x + w - f},{y} V{y + f} H{x + w}" fill="none" stroke="{color}" stroke-width="1.5"/>')
        self.text(x + w / 2, y + h / 2 + 4, label, size=size, anchor='middle', mono=mono, fill=C['ink'])

    def cylinder(self, x, y, w, h, label, sub=None, color=None, fill=None):
        color = color or C['slate']
        fill = fill or C['white']
        ry = 7
        self.add(f'<path d="M{x},{y + ry} V{y + h - ry} A{w / 2},{ry} 0 0 0 {x + w},{y + h - ry} V{y + ry}" '
                 f'fill="{fill}" stroke="{color}" stroke-width="1.5"/>')
        self.add(f'<ellipse cx="{x + w / 2}" cy="{y + ry}" rx="{w / 2}" ry="{ry}" fill="{fill}" stroke="{color}" stroke-width="1.5"/>')
        if sub:
            self.text(x + w / 2, y + h / 2 + 4, label, size=12, anchor='middle', mono=True, weight=600)
            self.text(x + w / 2, y + h / 2 + 19, sub, size=10.5, anchor='middle', fill=C['muted'])
        else:
            self.text(x + w / 2, y + h / 2 + 8, label, size=12, anchor='middle', mono=True, weight=600)

    def window(self, x, y, w, h, title=None):
        self.rect(x, y, w, h, fill=C['white'], stroke=C['line'], rx=12, sw=1.2)
        self.add(f'<path d="M{x},{y + 28} V{y + 12} A12,12 0 0 1 {x + 12},{y} H{x + w - 12} A12,12 0 0 1 {x + w},{y + 12} V{y + 28} Z" fill="{C["panel2"]}"/>')
        self.line(x, y + 28, x + w, y + 28, color='border', sw=1)
        for i, col in enumerate(['#FF5F57', '#FEBC2E', '#28C840']):
            self.circle(x + 16 + i * 17, y + 14, 5.5, fill=col)
        if title:
            self.text(x + w / 2, y + 18.5, title, size=12, weight=600, anchor='middle', fill=C['muted'])

    def popover(self, x, y, w, h):
        self.rect(x + 2, y + 4, w, h, fill='#0F172A', rx=14, opacity=0.08)
        self.rect(x, y, w, h, fill=C['white'], stroke=C['line'], rx=14, sw=1.2)

    def callout(self, x1, y1, x2, y2, label, side='left', size=12.5, sub=None):
        self.line(x1, y1, x2, y2, color='faint', sw=1.2)
        self.circle(x2, y2, 3, fill=C['faint'])
        anchor = 'end' if side == 'left' else 'start'
        tx = x1 - 6 if side == 'left' else x1 + 6
        self.text(tx, y1 + 4, label, size=size, weight=600, anchor=anchor)
        if sub:
            self.text(tx, y1 + 20, sub, size=11, anchor=anchor, fill=C['muted'])

    # ---- output -------------------------------------------------------------
    def render(self):
        defs = ['<defs>']
        for name in ARROW_COLORS:
            defs.append(f'<marker id="a-{name}" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="7" markerHeight="7" '
                        f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{C[name]}"/></marker>')
        defs.append('<pattern id="hatch" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
                    f'<rect width="8" height="8" fill="{C["greenL"]}"/><line x1="0" y1="0" x2="0" y2="8" stroke="{C["green"]}" stroke-width="3"/></pattern>')
        defs.append('</defs>')
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}" '
                f'role="img" aria-labelledby="t d">\n<title id="t">{escape(self.title)}</title>\n<desc id="d">{escape(self.desc)}</desc>\n')
        bg = f'<rect x="0.5" y="0.5" width="{self.w - 1}" height="{self.h - 1}" rx="16" fill="#FFFFFF" stroke="{C["border"]}"/>\n'
        return head + '\n'.join(defs) + '\n' + bg + '\n'.join(self.parts) + '\n</svg>\n'

    def save(self, path):
        with open(path, 'w') as f:
            f.write(self.render())
