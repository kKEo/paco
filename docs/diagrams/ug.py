import sys
from svgkit import SVG, C

OUT = sys.argv[1]


def overview():
    s = SVG(760, 410, "PaCo on two Macs",
            "The parent's Mac sends rules and approvals to the child's Mac over an encrypted connection on the home network; "
            "the child's Mac enforces them and can ask for more time.")
    s.rect(20, 146, 720, 246, fill=C['panel'], stroke=C['line'], rx=16, dash='6 5')
    s.text(40, 172, 'Your home network', size=13, weight=600, fill=C['muted'])
    s.cloud(612, 52, 34, C['white'], C['blue'])
    s.text(612, 64, 'Internet', size=13, weight=600, anchor='middle', fill=C['blue'])
    s.line(612, 96, 612, 192, color='red', sw=2.5, dash='5 4')
    s.cross(612, 128, 12, C['red'])
    s.text(592, 124, 'Off on schedule', size=12, weight=600, anchor='end', fill=C['red'])
    s.text(592, 139, 'unless you approve time', size=11.5, anchor='end', fill=C['muted'])
    s.laptop(80, 196, 180, screen_fill=C['blueL'])
    s.shield(170, 236, 22, C['blue'])
    s.text(170, 342, "Parent's Mac", size=15, weight=700, anchor='middle')
    s.text(170, 362, 'Profiles · schedules · app rules', size=12, anchor='middle', fill=C['muted'])
    s.text(170, 378, 'Protected by your PIN', size=12, anchor='middle', fill=C['muted'])
    s.laptop(522, 196, 180, screen_fill=C['redL'])
    s.shield(612, 236, 22, C['red'], slash=True)
    s.text(612, 342, "Child's Mac", size=15, weight=700, anchor='middle')
    s.text(612, 362, 'Enforces the rules it received', size=12, anchor='middle', fill=C['muted'])
    s.text(612, 378, 'Keeps working when you are away', size=12, anchor='middle', fill=C['muted'])
    s.line(292, 224, 488, 224, color='blue', sw=2.5, arrow=True)
    s.text(390, 214, 'Rules · approvals', size=12.5, weight=600, anchor='middle', fill=C['blue'])
    s.line(488, 276, 292, 276, color='orange', sw=2.5, arrow=True)
    s.text(390, 298, 'Time requests · PIN checks', size=12.5, weight=600, anchor='middle', fill=C['orange'])
    s.lock(390, 246, 13, color=C['slate'], bg=C['white'])
    s.save(f'{OUT}/ug-overview.svg')


def menubar():
    s = SVG(760, 170, "Menu bar icon states", "Green shield: internet on. Red shield with slash: internet off. Grey shield with slash: service unreachable.")
    states = [
        (C['green'], False, 'Internet is on', 'Schedules allow it right now'),
        (C['red'], True, 'Internet is off', 'A schedule or the switch blocks it'),
        (C['faint'], True, 'Service unreachable', 'See Troubleshooting'),
    ]
    for i, (col, slash, t, sub) in enumerate(states):
        x = 20 + i * 245
        s.rect(x, 20, 230, 40, fill=C['panel2'], rx=8)
        for k in range(3):
            s.rect(x + 14 + k * 24, 33, 14, 14, fill=C['line'], rx=3)
        s.rect(x + 100, 25, 34, 30, fill=C['white'], stroke=C['line'], rx=6, sw=1)
        s.shield(x + 117, 37, 9, col, slash=slash)
        s.text(x + 216, 45, 'Thu 21:04', size=12.5, anchor='end', fill=C['muted'])
        s.line(x + 117, 64, x + 117, 92, color='faint', sw=1.2)
        s.text(x + 117, 114, t, size=14, weight=700, anchor='middle', fill=col if col != C['faint'] else C['slate'])
        s.text(x + 117, 134, sub, size=12, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/ug-menubar.svg')


def pairing():
    s = SVG(760, 300, "Pairing in three steps", "Click Pair on your Mac, type the code on the child's Mac, and the two connect.")
    xs = [20, 270, 520]
    titles = [("On your Mac", "Devices → Pair"), ("On the child's Mac", "Pair with Parent"), ("Both Macs", "Connected")]
    for i, x in enumerate(xs):
        s.rect(x, 20, 220, 262, fill=C['panel'], stroke=C['border'], rx=14)
        s.num(x + 26, 46, i + 1)
        s.text(x + 48, 44, titles[i][0], size=14, weight=700)
        s.text(x + 48, 61, titles[i][1], size=12, fill=C['muted'])
    for x in (246, 496):
        s.path(f'M{x},150 L{x + 16},150', color='faint', sw=3, arrow=True)
    # step 1
    x = 20
    s.text(x + 18, 98, 'NEARBY DEVICES', size=10.5, weight=600, fill=C['muted'])
    s.rect(x + 14, 106, 192, 44, fill=C['white'], stroke=C['line'], rx=8, sw=1)
    s.laptop(x + 26, 117, 26, color=C['blue'])
    s.text(x + 62, 133, "Alex's MacBook", size=12.5, weight=600)
    s.button(x + 160, 118, 38, 22, 'Pair', size=11.5)
    s.text(x + 110, 182, 'Pairing Code', size=12, weight=600, anchor='middle', fill=C['muted'])
    s.rect(x + 22, 192, 176, 46, fill=C['white'], stroke=C['blue'], rx=8, sw=1.5)
    s.text(x + 110, 223, '7KQ2M9XD', size=22, weight=700, anchor='middle', mono=True, fill=C['blue'])
    s.text(x + 110, 262, 'Read it out or show it', size=11.5, anchor='middle', fill=C['muted'])
    # step 2
    x = 270
    s.popover(x + 20, 92, 180, 150)
    s.text(x + 110, 118, 'Pair with Parent', size=13, weight=700, anchor='middle')
    s.rect(x + 36, 136, 148, 30, fill=C['white'], stroke=C['line'], rx=6, sw=1)
    s.text(x + 48, 156, '7KQ2M9XD', size=14, mono=True, weight=600)
    s.button(x + 40, 184, 64, 26, 'Cancel', kind='secondary')
    s.button(x + 116, 184, 64, 26, 'Pair')
    s.text(x + 110, 262, 'Case and spaces don’t matter', size=11.5, anchor='middle', fill=C['muted'])
    # step 3
    x = 520
    s.rect(x + 14, 106, 192, 56, fill=C['white'], stroke=C['line'], rx=8, sw=1)
    s.laptop(x + 26, 121, 26, color=C['green'])
    s.text(x + 62, 130, "Alex's MacBook", size=12.5, weight=600)
    s.circle(x + 66, 146, 4, fill=C['green'])
    s.text(x + 75, 150, 'Connected', size=12, weight=600, fill=C['green'])
    s.lock(x + 110, 196, 12, color=C['slate'])
    s.text(x + 110, 232, 'Rules are sent now and', size=12, anchor='middle', fill=C['muted'])
    s.text(x + 110, 248, 'after every change', size=12, anchor='middle', fill=C['muted'])
    s.text(x + 110, 268, 'Usually within 30 seconds', size=11.5, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/ug-pairing.svg')


def dashboard():
    s = SVG(760, 430, "The parent dashboard", "Sidebar with eight sections; Home shows pending requests, a manual override banner and a card per profile.")
    s.window(20, 20, 720, 390, 'PaCo')
    s.rect(21, 49, 180, 360, fill=C['panel'], rx=0)
    s.line(201, 49, 201, 409, color='border', sw=1)
    items = ['Home', 'Profiles', 'Schedules', 'App Rules', 'Usage', 'Devices', 'Requests', 'Settings']
    for i, it in enumerate(items):
        y = 64 + i * 38
        if i == 0:
            s.rect(30, y, 162, 30, fill=C['blue'], rx=7)
        col = '#fff' if i == 0 else C['ink']
        s.circle(48, y + 15, 7, fill='#fff' if i == 0 else C['line'])
        s.text(64, y + 20, it, size=13.5, weight=600 if i == 0 else 500, fill=col)
    x0 = 225
    s.text(x0, 90, 'Home', size=26, weight=800)
    s.rect(x0, 108, 490, 44, fill=C['orangeL'], rx=10)
    s.clock(x0 + 22, 130, 9, C['orange'])
    s.text(x0 + 42, 135, '1 pending time request', size=14, weight=600)
    s.rect(x0, 162, 490, 50, fill=C['blueL'], rx=10)
    s.text(x0 + 16, 184, 'Manual: internet OFF until 20:15,', size=13, weight=500)
    s.text(x0 + 16, 201, 'then back to the schedule', size=13, fill=C['muted'])
    s.button(x0 + 360, 175, 116, 26, 'Back to schedule', kind='secondary')
    s.rect(x0, 228, 490, 84, fill=C['white'], stroke=C['line'], rx=12, sw=1)
    s.person(x0 + 42, 270, 30, C['blue'])
    s.text(x0 + 78, 262, 'Alex', size=17, weight=700)
    s.circle(x0 + 82, 282, 4.5, fill=C['red'])
    s.text(x0 + 92, 287, 'Internet OFF', size=13, fill=C['muted'])
    s.toggle(x0 + 430, 259, False)
    s.text(x0, 345, 'The switch overrides the schedule for 60 minutes', size=12.5, fill=C['muted'])
    s.text(x0, 363, 'on the Mac you are using.', size=12.5, fill=C['muted'])
    s.save(f'{OUT}/ug-dashboard.svg')


def _axis(s, x0, day_w, days, y_top, y_bot):
    for i, d in enumerate(days):
        x = x0 + i * day_w
        s.rect(x, y_top, day_w, y_bot - y_top, fill=C['panel'] if i % 2 == 0 else C['white'], rx=0)
        s.text(x + day_w / 2, y_top - 12, d, size=13, weight=700, anchor='middle')
        for h in (0, 6, 12, 18):
            hx = x + day_w * h / 24
            s.line(hx, y_bot, hx, y_bot + 5, color='faint', sw=1)
            s.text(hx, y_bot + 18, f'{h:02d}', size=10.5, anchor='middle', fill=C['muted'])
    s.line(x0 + len(days) * day_w, y_bot, x0 + len(days) * day_w, y_bot + 5, color='faint', sw=1)


def schedule_overnight():
    s = SVG(760, 360, "Overnight schedules belong to the day they start",
            "A Thursday 21:00 to 07:00 schedule blocks until Friday 07:00 but not Friday evening; a daytime schedule blocks the selected day only.")
    x0, dw = 70, 220
    _axis(s, x0, dw, ['Thursday', 'Friday', 'Saturday'], 50, 268)
    ph = dw / 24

    def bar(y, d0, h0, d1, h1, color, fill, label=None, dash=None):
        xa, xb = x0 + d0 * dw + h0 * ph, x0 + d1 * dw + h1 * ph
        s.rect(xa, y, xb - xa, 28, fill=fill, stroke=color, rx=6, sw=1.5, dash=dash)
        if label:
            s.text((xa + xb) / 2, y + 19, label, size=12, weight=600, anchor='middle', fill=color)

    s.text(x0 + 8, 80, 'Overnight: Thursday, OFF 21:00 → ON 07:00', size=13, weight=700)
    bar(92, 0, 21, 1, 7, C['red'], C['redL'], 'off')
    bar(92, 1, 21, 2, 7, C['faint'], 'none', dash='5 4')
    s.text(x0 + dw * 1.875, 140, 'Friday evening stays on', size=11.5, anchor='middle', fill=C['muted'])
    s.text(x0 + dw * 1.875, 154, '(select Friday to block it)', size=11.5, anchor='middle', fill=C['muted'])
    s.text(x0 + 8, 192, 'Daytime: Thursday, OFF 09:00 → ON 15:00', size=13, weight=700)
    bar(204, 0, 9, 0, 15, C['red'], C['redL'], 'off')
    s.text(x0 + dw * 0.5, 252, 'Only the selected day', size=11.5, anchor='middle', fill=C['muted'])
    # legend
    s.rect(70, 312, 26, 16, fill=C['redL'], stroke=C['red'], rx=4)
    s.text(104, 325, 'Internet off', size=12.5)
    s.rect(220, 312, 26, 16, fill='none', stroke=C['faint'], rx=4, dash='4 3')
    s.text(254, 325, 'Not blocked: the next day is not selected', size=12.5)
    s.save(f'{OUT}/ug-schedule-overnight.svg')


def precedence():
    s = SVG(760, 260, "What decides whether the internet is on",
            "First the manual switch, then an approved time request, then the schedules.")
    rows = [
        ('1', 'Manual switch on Home', 'On or off for 60 minutes, then the schedule resumes', C['purple'], C['purpleL']),
        ('2', 'Approved time request', 'On for the minutes you granted', C['green'], C['greenL']),
        ('3', 'Schedules', 'If any active schedule says off, the internet is off', C['blue'], C['blueL']),
    ]
    for i, (n, t, sub, col, bg) in enumerate(rows):
        y = 24 + i * 76
        x = 110 + i * 22
        w = 620 - i * 44
        s.rect(x, y, w, 62, fill=bg, stroke=col, rx=12, sw=1.5)
        s.num(x + 30, y + 31, n, fill=col, r=15)
        s.text(x + 56, y + 27, t, size=15, weight=700)
        s.text(x + 56, y + 46, sub, size=12.5, fill=C['muted'])
    s.line(58, 228, 58, 34, color='slate', sw=2.5, arrow=True)
    s.text(46, 135, 'wins', size=12, weight=700, anchor='end', fill=C['slate'])
    s.text(46, 150, 'first', size=12, weight=700, anchor='end', fill=C['slate'])
    s.save(f'{OUT}/ug-precedence.svg')


def app_rules():
    s = SVG(760, 290, "Always Blocked versus Follows Schedule",
            "An evening with a 21:00 off schedule and an approved request from 21:30 to 22:00.")
    x0, x1, h0, h1 = 190, 730, 16, 24
    ph = (x1 - x0) / (h1 - h0)
    X = lambda h: x0 + (h - h0) * ph
    for h in range(h0, h1 + 1):
        s.line(X(h), 60, X(h), 226, color='border', sw=1)
        s.text(X(h), 246, f'{h:02d}:00' if h < 24 else '24:00', size=10.5, anchor='middle', fill=C['muted'])
    rows = [('Internet', 'School nights, off 21:00'), ('Always Blocked app', ''), ('Follows Schedule app', 'Blocked during School nights')]
    segs = [
        [(16, 21, 'g'), (21, 21.5, 'r'), (21.5, 22, 'h'), (22, 24, 'r')],
        [(16, 24, 'r')],
        [(16, 21, 'g'), (21, 21.5, 'r'), (21.5, 22, 'h'), (22, 24, 'r')],
    ]
    for i, ((t, sub), ss) in enumerate(zip(rows, segs)):
        y = 70 + i * 54
        s.text(20, y + 15, t, size=13, weight=700)
        if sub: s.text(20, y + 31, sub, size=11, fill=C['muted'])
        for a, b, k in ss:
            fill, stroke = {'g': (C['greenL'], C['green']), 'r': (C['redL'], C['red']), 'h': ('url(#hatch)', C['green'])}[k]
            s.rect(X(a), y, X(b) - X(a), 30, fill=fill, stroke=stroke, rx=5, sw=1.2)
    s.text(X(21.75), 54, 'approved request', size=11.5, weight=600, anchor='middle', fill=C['green'])
    s.line(X(21.75), 58, X(21.75), 68, color='green', sw=1.2)
    s.rect(190, 260, 22, 14, fill=C['greenL'], stroke=C['green'], rx=3)
    s.text(218, 272, 'Allowed', size=12)
    s.rect(290, 260, 22, 14, fill=C['redL'], stroke=C['red'], rx=3)
    s.text(318, 272, 'Blocked', size=12)
    s.rect(390, 260, 22, 14, fill='url(#hatch)', stroke=C['green'], rx=3)
    s.text(418, 272, 'Allowed by an approved request', size=12)
    s.save(f'{OUT}/ug-app-rules.svg')


def request_flow():
    s = SVG(760, 300, "A time request from start to finish",
            "The child sends a request, you approve it on your Mac, and the child's internet turns on immediately.")
    cols = [(20, "Child's Mac", 'asks for time'), (270, 'Your Mac', 'Requests'), (520, "Child's Mac", 'gets the answer')]
    for x, t, sub in cols:
        s.rect(x, 20, 220, 260, fill=C['panel'], stroke=C['border'], rx=14)
        s.text(x + 18, 46, t, size=14, weight=700)
        s.text(x + 18, 63, sub, size=12, fill=C['muted'])
    for x in (246, 496):
        s.path(f'M{x},150 L{x + 16},150', color='faint', sw=3, arrow=True)
    x = 20
    s.popover(x + 16, 80, 188, 172)
    s.text(x + 110, 104, 'Request More Time', size=13, weight=700, anchor='middle')
    s.rect(x + 34, 118, 152, 28, fill=C['white'], stroke=C['line'], rx=6, sw=1)
    s.text(x + 46, 137, '30 minutes', size=12.5)
    s.text(x + 170, 137, '−  +', size=13, anchor='end', fill=C['muted'])
    s.rect(x + 34, 154, 152, 28, fill=C['white'], stroke=C['line'], rx=6, sw=1)
    s.text(x + 46, 173, 'Finish homework', size=12.5, fill=C['muted'])
    s.button(x + 34, 200, 152, 28, 'Send Request')
    x = 270
    s.rect(x + 14, 84, 192, 132, fill=C['white'], stroke=C['line'], rx=10, sw=1)
    s.clock(x + 36, 110, 10, C['orange'])
    s.text(x + 54, 108, "Alex's MacBook", size=12.5, weight=700)
    s.text(x + 54, 124, '30 min', size=12, fill=C['muted'])
    s.text(x + 28, 150, 'Finish homework', size=12, fill=C['muted'])
    s.text(x + 28, 166, 'Today 20:58', size=11, fill=C['faint'])
    s.button(x + 28, 180, 76, 26, 'Approve')
    s.button(x + 114, 180, 76, 26, 'Deny', kind='danger')
    s.text(x + 110, 250, 'Approve needs the child’s', size=11.5, anchor='middle', fill=C['muted'])
    s.text(x + 110, 265, 'Mac to be connected', size=11.5, anchor='middle', fill=C['muted'])
    x = 520
    s.shield(x + 110, 112, 24, C['green'])
    s.text(x + 110, 166, 'Internet is ON', size=16, weight=700, anchor='middle')
    s.rect(x + 16, 182, 188, 44, fill=C['greenL'], rx=10)
    s.checkmark(x + 36, 204, 9, C['green'])
    s.text(x + 52, 200, 'Approved — internet', size=12, weight=600)
    s.text(x + 52, 216, 'on until 21:28', size=12, weight=600)
    s.text(x + 110, 250, 'Then the schedule applies', size=11.5, anchor='middle', fill=C['muted'])
    s.text(x + 110, 265, 'again', size=11.5, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/ug-request-flow.svg')


def child_view():
    s = SVG(760, 500, "What the child sees", "The child view in the menu bar with its main parts labelled.")
    x, y, w = 230, 20, 300
    s.popover(x, y, w, 460)
    cx = x + w / 2
    s.shield(cx, 70, 30, C['green'])
    s.text(cx, 140, 'Internet is ON', size=22, weight=700, anchor='middle')
    s.circle(cx - 66, 163, 4.5, fill=C['green'])
    s.text(cx - 56, 168, 'Connected to parent', size=13, fill=C['muted'])
    s.line(x + 40, 190, x + w - 40, 190, color='border', sw=1)
    s.text(cx, 216, "Today's Usage", size=14, weight=700, anchor='middle')
    s.text(cx, 236, 'Internet: 1h 20m', size=13, anchor='middle')
    for i, t in enumerate(['Safari: 45m', 'Minecraft: 30m', 'Notes: 10m']):
        s.text(cx, 254 + i * 16, t, size=11.5, anchor='middle', fill=C['muted'])
    s.rect(x + 24, 316, w - 48, 40, fill=C['greenL'], rx=8)
    s.checkmark(x + 44, 336, 8, C['green'])
    s.text(x + 58, 341, 'Approved — internet on until 21:28', size=12, fill=C['ink'])
    s.button(cx - 80, 372, 160, 30, 'Request More Time', size=12.5)
    s.text(x + 24, 460, 'Pair with Parent', size=12, fill=C['muted'])
    s.text(x + w - 24, 460, 'Parent Access', size=12, fill=C['muted'], anchor='end')
    # callouts
    s.callout(200, 70, x + 18 - 0, 70, 'Internet status', 'left', sub='refreshed every 30 s')
    s.callout(200, 163, cx - 74, 163, 'Link to your Mac', 'left')
    s.callout(200, 245, cx - 70, 245, "Today's usage", 'left', sub='top three apps')
    s.callout(560, 336, x + w - 16, 336, 'Latest request', 'right', sub='shown for an hour')
    s.callout(560, 387, cx + 82, 387, 'Ask for more time', 'right', sub='needs your Mac online')
    s.callout(200, 456, x + 18, 456, 'Enter a pairing code', 'left')
    s.callout(560, 456, x + w - 18, 456, 'Open the dashboard', 'right', sub='with your PIN')
    s.save(f'{OUT}/ug-child-view.svg')


def usage():
    s = SVG(760, 280, "Only the app in front is counted",
            "Over ten minutes, each app accrues time only while it is frontmost; background helpers are not counted.")
    x0, x1 = 170, 610
    pm = (x1 - x0) / 10
    X = lambda m: x0 + m * pm
    for m in range(0, 11, 2):
        s.line(X(m), 40, X(m), 226, color='border', sw=1)
        s.text(X(m), 244, f'{m} min', size=10.5, anchor='middle', fill=C['muted'])
    s.text(680, 32, 'Counted', size=12, weight=700, anchor='middle', fill=C['muted'])
    rows = [
        ('Safari', [(0, 10)], [(0, 4), (7, 9)], '6m'),
        ('Minecraft', [(3, 10)], [(4, 7)], '3m'),
        ('Notes', [(8.5, 10)], [(9, 10)], '1m'),
        ('Updater (helper)', [(0, 10)], [], '—'),
    ]
    for i, (name, opn, fg, tot) in enumerate(rows):
        y = 50 + i * 44
        s.text(20, y + 19, name, size=13, weight=600, fill=C['ink'] if fg else C['muted'])
        for a, b in opn:
            s.rect(X(a), y + 6, X(b) - X(a), 16, fill=C['panel2'], stroke=C['line'], rx=4, sw=1, dash='3 3')
        for a, b in fg:
            s.rect(X(a), y + 2, X(b) - X(a), 24, fill=C['blue'], rx=5)
        s.text(680, y + 19, tot, size=14, weight=700, anchor='middle', fill=C['blue'] if fg else C['faint'])
    s.rect(170, 256, 22, 12, fill=C['blue'], rx=3)
    s.text(198, 266, 'In front: counted', size=12)
    s.rect(330, 256, 22, 12, fill=C['panel2'], stroke=C['line'], rx=3, dash='3 3')
    s.text(358, 266, 'Open in the background: not counted', size=12)
    s.save(f'{OUT}/ug-usage.svg')


def parent_access():
    s = SVG(760, 260, "Parent Access checks the PIN on your Mac",
            "The PIN typed on the child's Mac is sent encrypted to your Mac, which checks it and counts wrong attempts.")
    s.popover(30, 30, 210, 150)
    s.text(135, 58, 'Enter Parent PIN', size=13.5, weight=700, anchor='middle')
    s.rect(60, 74, 150, 30, fill=C['white'], stroke=C['line'], rx=6, sw=1)
    for i in range(6):
        s.circle(80 + i * 22, 89, 4.5, fill=C['ink'])
    s.button(95, 120, 80, 26, 'Unlock')
    s.text(135, 214, "Child's Mac", size=14, weight=700, anchor='middle')
    s.text(135, 233, 'The PIN is never stored here', size=12, anchor='middle', fill=C['muted'])
    s.line(262, 90, 528, 90, color='orange', sw=2.5, arrow=True)
    s.text(395, 78, 'PIN, encrypted', size=12.5, weight=600, anchor='middle', fill=C['orange'])
    s.line(528, 130, 262, 130, color='green', sw=2.5, arrow=True)
    s.text(395, 152, 'correct / wrong / locked out', size=12.5, weight=600, anchor='middle', fill=C['green'])
    s.lock(395, 108, 10, color=C['slate'], bg=C['white'])
    s.laptop(555, 52, 150, screen_fill=C['blueL'])
    s.checkmark(630, 98, 17, C['green'])
    s.text(630, 214, 'Your Mac', size=14, weight=700, anchor='middle')
    s.text(630, 233, 'Checks the PIN, counts wrong attempts', size=12, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/ug-parent-access.svg')


for fn in (overview, menubar, pairing, dashboard, schedule_overnight, precedence, app_rules, request_flow, child_view, usage, parent_access):
    fn()
print('ug done')
