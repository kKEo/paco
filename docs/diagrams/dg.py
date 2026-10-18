import sys
from svgkit import SVG, C

OUT = sys.argv[1]


def architecture():
    s = SVG(760, 540, "PaCo architecture",
            "On each Mac the app and agent run in the user session and talk to the root daemon over XPC; "
            "the daemon owns policy.json and the pf anchor; the two apps talk over Bonjour with TLS-PSK.")

    def mac(x0, title, mirrored):
        w = 320
        s.rect(x0, 20, w, 452, fill=C['white'], stroke=C['slate'], rx=16, sw=1.5)
        s.text(x0 + w / 2, 46, title, size=15, weight=800, anchor='middle')
        # user zone
        s.rect(x0 + 10, 60, w - 20, 196, fill=C['panel'], rx=12)
        s.text(x0 + 22, 80, 'LOGGED-IN USER', size=10.5, weight=700, fill=C['muted'])
        app_x, agent_x = (x0 + 170, x0 + 20) if mirrored else (x0 + 20, x0 + 170)
        s.box(app_x, 92, 130, 62, 'PaCo.app', ['SwiftData · UI', 'Bonjour peer'], fill=C['blueL'], stroke=C['blue'], ssize=11)
        s.box(agent_x, 92, 130, 62, 'PaCoAgent', ['app monitor', 'usage'], fill=C['purpleL'], stroke=C['purple'], ssize=11)
        s.file(x0 + 115, 190, 90, 36, 'usage.json', size=10.5)
        ag_c, app_c = agent_x + 65, app_x + 65
        fx = x0 + 115
        if mirrored:   # agent on the left, app on the right
            s.line(agent_x + 112, 154, fx + 22, 188, color='purple', sw=1.6, arrow=True, dash='4 3')
            s.line(fx + 68, 190, app_x + 18, 156, color='blue', sw=1.6, arrow=True, dash='4 3')
        else:          # app on the left, agent on the right
            s.line(agent_x + 18, 154, fx + 68, 188, color='purple', sw=1.6, arrow=True, dash='4 3')
            s.line(fx + 22, 190, app_x + 112, 156, color='blue', sw=1.6, arrow=True, dash='4 3')
        # root zone
        s.rect(x0 + 10, 266, w - 20, 196, fill=C['slateL'], rx=12)
        s.text(x0 + w / 2, 286, 'ROOT', size=10.5, weight=700, anchor='middle', fill=C['slate'])
        s.box(x0 + 20, 298, 280, 60, 'PaCoDaemon', ['PolicyEngine · FirewallManager · ProcessManager'],
              fill=C['slate'], stroke=C['slate'], tcolor='#fff', scolor='#CBD5E1', ssize=11)
        s.cylinder(x0 + 28, 384, 124, 56, 'policy.json', 'DaemonPolicy')
        s.cylinder(x0 + 170, 384, 124, 56, 'com.paco', 'pf anchor')
        s.line(x0 + 90, 358, x0 + 90, 382, color='slate', sw=1.6, arrow=True)
        s.line(x0 + 232, 358, x0 + 232, 382, color='slate', sw=1.6, arrow=True)
        # XPC
        for bx in (app_x, agent_x):
            cx = bx + 30 if bx == x0 + 20 else bx + 100
            s.line(cx, 154, cx, 296, color='ink', sw=2, arrow=True)
            s.pill(cx - 18, 232, 36, 18, 'XPC', C['white'], C['ink'], size=10)
        return app_x

    pa = mac(20, "Parent's Mac", mirrored=True)
    ca = mac(420, "Child's Mac", mirrored=False)
    # Bonjour link between the two apps
    s.line(pa + 130, 123, ca, 123, color='orange', sw=2.5, arrow=True, start_arrow=True)
    s.text(380, 110, 'Bonjour', size=11.5, weight=700, anchor='middle', fill=C['orange'])
    s.text(380, 142, 'TLS-PSK', size=11.5, weight=700, anchor='middle', fill=C['orange'])
    # legend
    y = 500
    s.line(30, y, 62, y, color='ink', sw=2, arrow=True)
    s.text(70, y + 4, 'XPC, code-signing checked', size=12)
    s.line(250, y, 282, y, color='blue', sw=1.6, arrow=True, dash='4 3')
    s.text(290, y + 4, 'file in ~/Library/Application Support/com.paco', size=12)
    s.line(578, y, 626, y, color='orange', sw=2.5, arrow=True, start_arrow=True)
    s.text(634, y + 4, 'encrypted LAN link', size=12)
    s.save(f'{OUT}/dg-architecture.svg')


def trust():
    s = SVG(760, 500, "Trust boundaries", "What the monitored user can reach, and the checks at each boundary.")
    def zone(x, y, w, h, title, items, col, bg):
        s.rect(x, y, w, h, fill=bg, stroke=col, rx=12, sw=1.5)
        s.text(x + 14, y + 24, title, size=13.5, weight=700, fill=col)
        for i, it in enumerate(items):
            s.text(x + 14, y + 48 + i * 19, '• ' + it, size=12, fill=C['ink'])

    def gate(x, y, h, n):
        s.rect(x, y, 26, h, fill=C['slate'], rx=6)
        s.num(x + 13, y + h / 2, n, fill=C['orange'], r=12)

    s.text(20, 22, 'On the child’s Mac', size=12, weight=700, fill=C['muted'])
    zone(20, 72, 190, 150, 'Monitored user', ['Terminal, any app', 'files in ~', 'launchctl (own domain)'], C['red'], C['redL'])
    gate(222, 82, 130, 1)
    zone(260, 72, 210, 150, 'PaCo app & agent', ['signed com.paco.app/agent', 'push policy, overrides', 'ask to kill an app'], C['orange'], C['orangeL'])
    gate(482, 82, 130, 2)
    zone(520, 72, 220, 150, 'Root daemon', ['policy.json (root-owned)', 'pf anchor com.paco', 'SIGKILL', 'integrity check / 15 s'], C['green'], C['greenL'])
    s.line(210, 147, 220, 147, color='faint', sw=2)
    s.line(250, 147, 258, 147, color='faint', sw=2, arrow=True)
    s.line(470, 147, 480, 147, color='faint', sw=2)
    s.line(510, 147, 518, 147, color='faint', sw=2, arrow=True)
    # direct attempt blocked
    s.path('M120,72 C140,30 600,30 620,70', color='red', sw=1.8, dash='5 4', arrow=True)
    s.cross(370, 40, 9, C['red'])
    s.text(370, 63, 'direct edits blocked: files are root-owned', size=11, weight=600, anchor='middle', fill=C['red'])
    s.text(20, 258, 'On the network', size=12, weight=700, fill=C['muted'])
    zone(20, 270, 190, 96, 'Other LAN devices', ['anyone on Wi-Fi', 'with the source code'], C['red'], C['redL'])
    gate(222, 280, 76, 3)
    zone(260, 270, 210, 96, "Child's PaCo app", ['accepts paired parent only', 'relays to its daemon'], C['orange'], C['orangeL'])
    s.line(210, 318, 220, 318, color='faint', sw=2)
    s.line(250, 318, 258, 318, color='faint', sw=2, arrow=True)
    s.rect(520, 270, 220, 96, fill=C['panel'], stroke=C['line'], rx=12)
    s.text(534, 294, "Parent's PIN hash", size=13.5, weight=700, fill=C['slate'])
    s.text(534, 316, 'stays on the parent’s Mac;', size=12)
    s.text(534, 334, 'the child asks it to verify', size=12)
    s.text(534, 352, '(.verifyPIN, shared lockout)', size=12, fill=C['muted'])
    legend = [
        ('1', 'XPC code-signing requirement: same Team ID as the daemon, identifier com.paco.app or com.paco.agent'),
        ('2', 'Daemon validates input: kills only signed bundle IDs in the restricted set; overrides must end in the future'),
        ('3', 'TLS-PSK with the pairing key; an unpaired child cancels every connection'),
    ]
    for i, (n, t) in enumerate(legend):
        y = 402 + i * 30
        s.num(32, y, n, fill=C['orange'], r=11)
        s.text(52, y + 4.5, t, size=12)
    s.save(f'{OUT}/dg-trust-boundaries.svg')


def pipeline():
    s = SVG(760, 370, "Policy pipeline inside the daemon",
            "XPC mutations go through mutate(), are persisted, update the kill allowlist and trigger evaluation; a 30-second timer re-evaluates.")
    inputs = ['updatePolicy', 'setActiveProfile', 'grantInternetOverride', 'setManualInternet']
    for i, t in enumerate(inputs):
        y = 40 + i * 52
        s.box(20, y, 190, 38, t, fill=C['blueL'], stroke=C['blue'], tsize=12.5, mono_title=True)
        s.line(210, y + 19, 264, 118 + i * 14, color='blue', sw=1.5, arrow=True)
    s.text(115, 30, 'XPC calls', size=11, weight=700, anchor='middle', fill=C['muted'])
    s.box(266, 108, 140, 66, 'mutate()', ['copy · change', 'persist · swap'], fill=C['white'], stroke=C['slate'], mono_title=True, ssize=11)
    s.cylinder(276, 214, 120, 56, 'policy.json', 'root-owned, 0644')
    s.line(336, 174, 336, 212, color='slate', sw=1.6, arrow=True)
    s.box(452, 108, 132, 66, 'DaemonPolicy', ['in memory'], fill=C['slateL'], stroke=C['slate'], ssize=11)
    s.line(406, 141, 450, 141, color='slate', sw=1.8, arrow=True)
    s.box(618, 28, 122, 56, 'ProcessManager', ['kill allowlist'], fill=C['white'], stroke=C['slate'], tsize=13, ssize=11)
    s.line(584, 118, 616, 70, color='slate', sw=1.6, arrow=True)
    s.text(586, 98, 'restrictedBundleIDs', size=10.5, anchor='end', fill=C['muted'], mono=True)
    s.box(618, 116, 122, 56, 'PaCoAgent', ['fetchPolicy (read)'], fill=C['purpleL'], stroke=C['purple'], tsize=13, ssize=11)
    s.line(584, 144, 616, 144, color='purple', sw=1.6, arrow=True, dash='4 3')
    # evaluation
    s.rect(452, 214, 150, 118, fill=C['white'], stroke=C['blue'], rx=12, sw=1.5)
    s.text(527, 236, 'internetAction()', size=12.5, weight=700, anchor='middle', mono=True)
    for i, (n, t, col) in enumerate([('1', 'manual override', C['purple']), ('2', 'approved extension', C['green']), ('3', 'schedules', C['blue'])]):
        s.num(472, 258 + i * 24, n, fill=col, r=9)
        s.text(488, 262 + i * 24, t, size=12)
    s.line(518, 174, 518, 212, color='slate', sw=1.6, arrow=True)
    s.clock(416, 300, 13, C['muted'])
    s.text(444, 334, 'every 30 s', size=11, anchor='end', fill=C['muted'])
    s.text(444, 349, '+ after mutate', size=11, anchor='end', fill=C['muted'])
    s.line(430, 300, 450, 300, color='muted', sw=1.5, arrow=True)
    s.box(618, 244, 122, 56, 'FirewallManager', ['pfctl'], fill=C['white'], stroke=C['slate'], tsize=13, ssize=11)
    s.line(602, 272, 616, 272, color='red', sw=1.8, arrow=True)
    s.text(679, 322, 'only when the state', size=11, anchor='middle', fill=C['muted'])
    s.text(679, 337, 'changes (edge-triggered)', size=11, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/dg-policy-pipeline.svg')


def evaluator():
    s = SVG(760, 336, "Which day a schedule window belongs to",
            "Same-day windows check today's weekday; the post-midnight part of an overnight window checks yesterday's.")
    x0, x1 = 60, 740
    ph = (x1 - x0) / 48
    X = lambda h: x0 + h * ph
    def axis(y):
        s.rect(X(0), y, X(24) - X(0), 34, fill=C['panel'], rx=0)
        s.rect(X(24), y, X(48) - X(24), 34, fill=C['white'], stroke=C['border'], rx=0, sw=1)
        for h in range(0, 49, 6):
            s.line(X(h), y + 34, X(h), y + 39, color='faint', sw=1)
            s.text(X(h), y + 52, f'{h % 24:02d}', size=10.5, anchor='middle', fill=C['muted'])
    s.text(X(12), 30, 'Day D', size=13, weight=700, anchor='middle')
    s.text(X(36), 30, 'Day D+1', size=13, weight=700, anchor='middle')
    s.text(20, 62, 'Same-day window, off 09:00 → on 15:00', size=13, weight=700)
    axis(72)
    s.rect(X(9), 72, X(15) - X(9), 34, fill=C['redL'], stroke=C['red'], rx=4)
    s.text(X(12), 94, 'blocked', size=11.5, weight=600, anchor='middle', fill=C['red'])
    s.text(X(15) + 10, 94, 'requires D selected', size=11.5, fill=C['muted'])
    s.text(20, 160, 'Overnight window, off 21:00 → on 07:00, grace 15 min', size=13, weight=700)
    axis(200)
    s.rect(X(21), 200, X(31) - X(21), 34, fill=C['redL'], stroke=C['red'], rx=4)
    s.rect(X(21), 200, max(6, X(21.25) - X(21)), 34, fill=C['orangeM'], rx=2)
    s.line(X(24), 190, X(24), 238, color='slate', sw=1.5, dash='3 3')
    s.text(X(24) - 6, 192, 'now ≥ off: checks D', size=11, weight=600, anchor='end', fill=C['red'])
    s.text(X(24) + 6, 192, 'now < on: checks yesterday = D', size=11, weight=600, fill=C['red'])
    s.text(X(21) - 8, 221, 'grace: first 15 min →', size=11, weight=600, anchor='end', fill=C['orange'])
    s.path(f'M{X(21)},{270} L{X(21)},{278} L{X(31)},{278} L{X(31)},{270}', color='slate', sw=1.5)
    s.text(X(26), 298, 'one window, attributed to day D', size=12, weight=700, anchor='middle', fill=C['slate'])
    s.text(X(26), 314, 'blocks only if D is a selected day', size=11.5, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/dg-evaluator-windows.svg')


def pf_rules():
    s = SVG(760, 380, "Why the pass rules must be quick",
            "pf evaluates every rule and the last match wins unless a matching rule is quick.")
    cols = [(20, 'Without quick', 'last match wins', False), (395, 'With quick (PaCo)', 'first quick match wins', True)]
    for x, title, sub, quick in cols:
        s.rect(x, 20, 345, 300, fill=C['panel'], stroke=C['border'], rx=14)
        s.text(x + 18, 46, title, size=14.5, weight=700)
        s.text(x + 18, 64, sub, size=12, fill=C['muted'])
        s.pill(x + 18, 80, 210, 24, 'packet → 192.168.1.20 (printer)', C['white'], C['ink'], size=11, weight=500)
        rules = [('pass out quick to 10.0.0.0/8' if quick else 'pass out to 10.0.0.0/8', 'no'),
                 ('pass out quick to 192.168.0.0/16' if quick else 'pass out to 192.168.0.0/16', 'match'),
                 ('pass out quick to 224.0.0.0/4 …' if quick else 'pass out to 224.0.0.0/4 …', 'skip' if quick else 'no'),
                 ('block drop out … any to any', 'skip' if quick else 'match')]
        for i, (r, st) in enumerate(rules):
            y = 118 + i * 40
            col = {'no': C['line'], 'match': C['green'] if (quick or i < 3) else C['red'], 'skip': C['line']}[st]
            fill = C['white'] if st != 'skip' else C['panel2']
            s.rect(x + 18, y, 238, 30, fill=fill, stroke=col, rx=6, sw=1.5 if st == 'match' else 1)
            s.text(x + 28, y + 20, r, size=11, mono=True, fill=C['faint'] if st == 'skip' else C['ink'])
            tag = {'no': 'no match', 'match': 'match', 'skip': 'not evaluated'}[st]
            s.text(x + 264, y + 20, tag, size=10.5, weight=600, fill=col if st == 'match' else C['muted'])
        if quick:
            s.path(f'M{x + 8},{132} L{x + 8},{173}', color='green', sw=2, arrow=True)
            s.box(x + 18, 280, 310, 30, 'PASS — stops at the quick match', fill=C['greenL'], stroke=C['green'], tcolor=C['green'], tsize=12.5)
        else:
            s.path(f'M{x + 8},{132} L{x + 8},{253}', color='red', sw=2, arrow=True)
            s.box(x + 18, 280, 310, 30, 'BLOCKED — the block rule matched last', fill=C['redL'], stroke=C['red'], tcolor=C['red'], tsize=12.5)
    s.text(380, 350, 'Internet traffic matches no pass rule, so it reaches the block rule in both cases.', size=12.5, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/dg-pf-rules.svg')


def frame():
    s = SVG(760, 250, "Frame format on the parent–child link",
            "Four-byte big-endian length, one type byte, then JSON.")
    cells = [('00', C['blueL'], C['blue']), ('00', C['blueL'], C['blue']), ('01', C['blueL'], C['blue']), ('2C', C['blueL'], C['blue']),
             ('01', C['orangeL'], C['orange'])]
    x = 40
    for t, f, c in cells:
        s.rect(x, 50, 52, 52, fill=f, stroke=c, rx=6)
        s.text(x + 26, 82, t, size=16, weight=700, anchor='middle', mono=True)
        x += 56
    s.rect(x, 50, 720 - x, 52, fill=C['greenL'], stroke=C['green'], rx=6)
    s.text(x + 14, 81, '{"command":"updatePolicy","payload":…}', size=12.5, mono=True)
    s.text(40, 36, 'byte 0', size=10.5, fill=C['muted'], mono=True)
    def brace(xa, xb, y, label, sub, col):
        s.path(f'M{xa},{y} L{xa},{y + 8} L{xb},{y + 8} L{xb},{y}', color=col, sw=1.5)
        s.text((xa + xb) / 2, y + 28, label, size=12.5, weight=700, anchor='middle', fill=col)
        for i, t in enumerate(sub):
            s.text((xa + xb) / 2, y + 46 + i * 16, t, size=11.5, anchor='middle', fill=C['muted'])
    brace(40, 260, 112, 'length: UInt32, big-endian', ['= 300: type byte + JSON', '0 < length < 1 MiB'], C['blue'])
    brace(264, 316, 112, 'type', ['1 message', '2 response'], C['orange'])
    brace(320, 720, 112, 'JSON body: PaCoMessage or PaCoResponse', ['299 bytes in this example'], C['green'])
    s.text(380, 230, 'A malformed header, short read or receive error cancels the connection; the parent reconnects.',
           size=12, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/dg-frame-format.svg')


def pairing_crypto():
    s = SVG(760, 420, "Pairing key derivation",
            "Both Macs derive the same 32-byte key from the code with PBKDF2; the code never crosses the network.")
    for x, title, ident in ((20, "Parent's Mac", 'identity = child service name'), (480, "Child's Mac", 'identity = "parent"')):
        s.rect(x, 20, 260, 300, fill=C['panel'], stroke=C['border'], rx=14)
        s.text(x + 130, 46, title, size=14.5, weight=700, anchor='middle')
        steps = [('7KQ2M9XD', 'code', C['blueL'], C['blue']),
                 ('normalize', 'upper-case, strip spaces', C['white'], C['line']),
                 ('PBKDF2-HMAC-SHA256', '210,000 iterations · salt com.paco.pairing.v1', C['white'], C['line']),
                 ('32-byte PSK', '', C['greenL'], C['green']),
                 ('Keychain', ident, C['white'], C['line'])]
        for i, (t, sub, f, c) in enumerate(steps):
            y = 60 + i * 52
            s.box(x + 16, y, 228, 40, t, [sub] if sub else None, fill=f, stroke=c, tsize=12.5, ssize=10, mono_title=(i in (0, 2)))
            if i < 4:
                s.line(x + 130, y + 40, x + 130, y + 50, color='muted', sw=1.5, arrow=True)
    # human transfer
    s.path('M264,80 C330,60 430,60 496,80', color='muted', sw=2, dash='6 5', arrow=True)
    s.person(380, 102, 22, C['muted'])
    s.text(380, 138, 'typed by a person', size=12, weight=600, anchor='middle', fill=C['muted'])
    s.text(380, 154, 'not sent over the network', size=11.5, anchor='middle', fill=C['muted'])
    # TLS
    s.line(150, 322, 150, 358, color='orange', sw=2)
    s.line(610, 322, 610, 358, color='orange', sw=2)
    s.line(150, 358, 610, 358, color='orange', sw=2.5, arrow=True, start_arrow=True)
    s.lock(380, 344, 11, color=C['orange'], bg=C['white'])
    s.text(380, 384, 'TLS ≥ 1.2 · TLS_PSK_WITH_AES_128_GCM_SHA256 · PSK identity "com.paco"', size=12, weight=600, anchor='middle', fill=C['orange'])
    s.text(380, 402, 'A peer without the same key fails the handshake.', size=11.5, anchor='middle', fill=C['muted'])
    s.save(f'{OUT}/dg-pairing-crypto.svg')


def conn_states():
    s = SVG(760, 330, "Parent-side connection lifecycle",
            "Discovered paired children are connected automatically; stuck or failed connections are removed and retried.")
    s.box(20, 60, 170, 70, 'Discovered', ['service seen + key stored'], fill=C['panel'], stroke=C['line'], ssize=11)
    s.box(250, 60, 170, 70, 'Connecting', ['.preparing / .waiting'], fill=C['orangeL'], stroke=C['orange'], ssize=11)
    s.box(470, 60, 116, 70, 'Ready', ['.ready'], fill=C['greenL'], stroke=C['green'], ssize=11)
    s.box(250, 222, 170, 70, 'Removed', ['cancelled / forgotten'], fill=C['redL'], stroke=C['red'], ssize=11)
    s.line(190, 95, 248, 95, color='ink', sw=2, arrow=True)
    s.text(219, 86, 'connect', size=11, anchor='middle', fill=C['muted'])
    s.line(420, 95, 468, 95, color='green', sw=2, arrow=True)
    s.text(444, 86, 'TLS ok', size=11, anchor='middle', fill=C['muted'])
    s.line(335, 130, 335, 220, color='red', sw=2, arrow=True)
    s.text(345, 168, '20 s timeout', size=11, fill=C['red'])
    s.text(345, 183, 'or .failed', size=11, fill=C['red'])
    s.path('M528,130 L528,257 L422,257', color='red', sw=2, arrow=True)
    s.text(536, 190, '.failed / peer closed', size=11, fill=C['red'])
    s.text(536, 205, 'receive error', size=11, fill=C['red'])
    s.path('M250,257 L105,257 L105,132', color='blue', sw=2, arrow=True)
    s.text(112, 225, 'retry: every 30 s', size=11, fill=C['blue'])
    s.text(112, 240, 'or browse change', size=11, fill=C['blue'])
    s.rect(604, 52, 146, 86, fill=C['white'], stroke=C['green'], rx=10, dash='4 3')
    s.text(616, 74, 'on .ready', size=11.5, weight=700, fill=C['green'])
    s.text(616, 93, 'connectedIdentities', size=10, mono=True)
    s.text(616, 107, '+= identity', size=10, mono=True)
    s.text(616, 126, 'push full policy', size=11)
    s.line(586, 95, 602, 95, color='green', sw=1.5)
    s.text(20, 32, 'Driven by BonjourService.autoConnectPairedDevices()', size=12, weight=600, fill=C['muted'])
    s.save(f'{OUT}/dg-connection-states.svg')


def storage():
    s = SVG(760, 362, "Where PaCo keeps its data", "Root-owned system files, per-user files, and Keychain items.")
    cols = [
        (20, 'Root-owned', C['slate'], C['slateL'], [
            ('/Library/Application Support/', None),
            ('PaCo/policy.json', 'DaemonPolicy'),
            ('PaCo/daemon-state.json', 'intended block state'),
            ('PaCo/PaCoDaemon, PaCoAgent', 'installed binaries'),
            ('/etc/', None),
            ('pf.anchors/com.paco', 'block rules'),
            ('pf.conf.paco-backup', 'original pf.conf'),
        ]),
        (265, 'Per user', C['blue'], C['blueL'], [
            ('~/Library/Application Support/', None),
            ('com.paco/PaCo.store', 'SwiftData database'),
            ('com.paco/usage.json', "today's usage"),
            ('com.paco/events.json', 'agent activity log'),
            ('com.paco/child-requests.json', "child's request log"),
        ]),
        (510, 'Keychain', C['green'], C['greenL'], [
            ('service com.paco.keychain', None),
            ('com.paco.pin.hash / .salt', 'parent only'),
            ('com.paco.pin.attempts', 'parent only'),
            ('com.paco.pin.lockoutUntil', 'parent only'),
            ('com.paco.pairing.keys', 'both Macs'),
        ]),
    ]
    for x, title, col, bg, rows in cols:
        s.rect(x, 20, 230, 322, fill=C['white'], stroke=col, rx=14, sw=1.5)
        s.rect(x, 20, 230, 44, fill=bg, rx=14)
        s.rect(x, 50, 230, 14, fill=bg, rx=0)
        s.text(x + 16, 48, title, size=15, weight=800, fill=col)
        y = 92
        for name, desc in rows:
            if desc is None:
                s.text(x + 16, y, name, size=10.5, mono=True, weight=700, fill=C['muted'])
                y += 24
            else:
                s.file(x + 16, y - 14, 16, 20, '', color=col)
                s.text(x + 40, y, name, size=10.5, mono=True, weight=600)
                s.text(x + 40, y + 16, desc, size=11, fill=C['muted'])
                y += 42
    s.save(f'{OUT}/dg-storage.svg')


def cloud():
    s = SVG(760, 470, "PaCo Cloud",
            "The parent uses a browser. The PaCo Cloud server keeps the rules, requests and screen time. "
            "On the child's Mac the root daemon talks to the server over HTTPS: a long-poll brings commands, "
            "heartbeats, usage and requests go up; a pf pass rule keeps the server reachable while internet is off.")
    # parent's browser
    s.rect(20, 40, 170, 230, fill=C['white'], stroke=C['line'], rx=16, sw=1.5)
    s.text(105, 66, "Parent", size=15, weight=800, anchor='middle')
    s.box(36, 86, 138, 92, 'Browser', ['any device', 'no PaCo app'], fill=C['blueL'], stroke=C['blue'], ssize=11)
    s.text(105, 214, 'rules · requests', size=11, anchor='middle', fill=C['muted'])
    s.text(105, 230, 'screen time · PIN', size=11, anchor='middle', fill=C['muted'])
    s.text(105, 246, 'Macs · activity', size=11, anchor='middle', fill=C['muted'])

    # server
    s.rect(230, 20, 260, 370, fill=C['panel'], stroke=C['slate'], rx=16, sw=1.5)
    s.text(360, 46, 'PaCo Cloud server', size=15, weight=800, anchor='middle')
    s.text(360, 64, 'Laravel · Octane on FrankenPHP', size=11, anchor='middle', fill=C['muted'])
    s.box(250, 80, 220, 58, 'Parent dashboard', ['Livewire pages, 2FA'], fill=C['white'], stroke=C['blue'], ssize=11)
    s.box(250, 158, 220, 58, 'Device API  /api/v1', ['bearer device token'], fill=C['white'], stroke=C['green'], ssize=11)
    s.cylinder(258, 238, 204, 64, 'MariaDB', 'rules · usage_days · device_events')
    s.text(360, 330, 'device_events = outbox,', size=11, anchor='middle', fill=C['muted'])
    s.text(360, 346, 'delivered at least once', size=11, anchor='middle', fill=C['muted'])
    s.line(360, 138, 360, 156, color='slate', sw=1.4)
    s.line(360, 216, 360, 236, color='slate', sw=1.4)

    # browser <-> dashboard
    s.line(174, 120, 248, 110, color='blue', sw=2.5, arrow=True, start_arrow=True)
    s.text(211, 94, 'HTTPS', size=11, weight=700, anchor='middle', fill=C['blue'])

    # child's Mac
    s.rect(530, 20, 210, 370, fill=C['white'], stroke=C['slate'], rx=16, sw=1.5)
    s.text(635, 46, "Child's Mac", size=15, weight=800, anchor='middle')
    s.rect(540, 60, 190, 120, fill=C['panel'], rx=12)
    s.text(552, 78, 'LOGGED-IN USER', size=10.5, weight=700, fill=C['muted'])
    s.box(550, 88, 82, 54, 'PaCo.app', ['child view'], fill=C['blueL'], stroke=C['blue'], tsize=12.5, ssize=10.5)
    s.box(640, 88, 82, 54, 'PaCoAgent', ['usage'], fill=C['purpleL'], stroke=C['purple'], tsize=12.5, ssize=10.5)
    s.rect(540, 190, 190, 190, fill=C['slateL'], rx=12)
    s.text(635, 208, 'ROOT', size=10.5, weight=700, anchor='middle', fill=C['slate'])
    s.box(550, 218, 172, 66, 'PaCoDaemon', ['CloudSyncService', 'PolicyEngine'],
          fill=C['slate'], stroke=C['slate'], tcolor='#fff', scolor='#CBD5E1', ssize=10.5)
    s.cylinder(548, 300, 88, 56, 'cloud.json', '0600, token')
    s.cylinder(642, 300, 82, 56, 'pf anchor', 'paco_cloud')
    # XPC
    s.line(591, 142, 591, 216, color='ink', sw=2, arrow=True)
    s.pill(566, 150, 50, 18, 'cloud()', C['white'], C['ink'], size=10)
    s.line(681, 142, 681, 216, color='ink', sw=2, arrow=True)
    s.pill(646, 150, 70, 18, 'reportUsage', C['white'], C['ink'], size=10)

    # daemon <-> device API
    s.line(548, 236, 472, 176, color='green', sw=2.5, arrow=True)
    s.text(512, 186, 'up', size=11, weight=700, anchor='middle', fill=C['green'])
    s.line(472, 198, 548, 262, color='orange', sw=2.5, arrow=True)
    s.text(472, 232, 'down', size=11, weight=700, anchor='middle', fill=C['orange'])

    # legend
    y = 418
    s.line(30, y, 62, y, color='green', sw=2.5, arrow=True)
    s.text(70, y + 4, 'heartbeat 30 s, usage, requests, PIN check', size=12)
    s.line(360, y, 392, y, color='orange', sw=2.5, arrow=True)
    s.text(400, y + 4, 'long-poll: commands within a second', size=12)
    s.line(30, y + 28, 62, y + 28, color='ink', sw=2, arrow=True)
    s.text(70, y + 32, 'XPC, code-signing checked', size=12)
    s.text(360, y + 32, 'All traffic HTTPS; the daemon starts every connection.', size=12, fill=C['muted'])
    s.save(f'{OUT}/dg-cloud.svg')


for fn in (architecture, trust, pipeline, evaluator, pf_rules, frame, pairing_crypto, conn_states, storage, cloud):
    fn()
print('dg done')
