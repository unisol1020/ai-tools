#!/usr/bin/env python3
"""Claude Code status line — at-a-glance instrumentation, current session only.

Line 1  identity / place / repo state
Line 2  a compact context meter (eighth-block sub-cell fill) and session tokens

Scope is deliberately this session: no spend, no 5h/7d rate-limit windows —
Orca already surfaces those.

Env overrides: SL_WIDTH, SL_ASCII, SL_NO_NERD, NO_COLOR
"""
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time

CACHE_DIR = "/tmp/sl-meters-cache"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
RESET = "\x1b[0m"
BG_OFF = "\x1b[49m"
EIGHTHS = "▏▎▍▌▋▊▉"
FULLBLK = "█"
SHADE = "░"

PAL = {
    "brand": (114, 102, 234),
    "text": (205, 214, 244),
    "sub": (166, 173, 200),
    "dim": (108, 112, 134),
    "faint": (81, 84, 103),
    "trough": (69, 71, 90),
    "track": (56, 58, 76),
    "dither": (84, 87, 110),
    "ink": (24, 24, 37),
    "mauve": (203, 166, 247),
    "lav": (180, 190, 254),
    "blue": (137, 180, 250),
    "sky": (137, 220, 235),
    "teal": (148, 226, 213),
    "green": (166, 227, 161),
    "yellow": (249, 226, 175),
    "peach": (250, 179, 135),
    "red": (243, 139, 168),
    "pink": (245, 194, 231),
}

LOAD_RAMP = [(0.00, PAL["green"]), (0.45, PAL["yellow"]),
             (0.72, PAL["peach"]), (1.00, PAL["red"])]
WARM_RAMP = [(0.00, PAL["blue"]), (0.35, PAL["teal"]),
             (0.68, PAL["yellow"]), (1.00, PAL["peach"])]

WIDE = ((0x1100, 0x115F), (0x2E80, 0x303E), (0x3041, 0x33FF), (0x3400, 0x4DBF),
        (0x4E00, 0x9FFF), (0xA000, 0xA4CF), (0xAC00, 0xD7A3), (0xF900, 0xFAFF),
        (0xFE30, 0xFE6F), (0xFF00, 0xFF60), (0xFFE0, 0xFFE6),
        (0x1F300, 0x1F64F), (0x1F680, 0x1F6FF), (0x1F900, 0x1F9FF),
        (0x20000, 0x3FFFD))

ASCII = os.environ.get("SL_ASCII") == "1" or "UTF" not in (
    os.environ.get("LC_ALL") or os.environ.get("LC_CTYPE") or
    os.environ.get("LANG") or "UTF-8").upper()
NERD = not ASCII and os.environ.get("SL_NO_NERD") != "1"
MONO = bool(os.environ.get("NO_COLOR"))
TRUE = os.environ.get("COLORTERM", "") in ("truecolor", "24bit")

if MONO:
    RESET = ""
    BG_OFF = ""

GL = {
    "brand": "<>" if ASCII else "◆",
    "dir": "d:" if ASCII else ("" if NERD else "▪"),
    "branch": "br" if ASCII else ("" if NERD else "⎇"),
    "fork": "wt" if ASCII else ("" if NERD else "⑂"),
    "up": "^" if ASCII else "⇡",
    "down": "v" if ASCII else "⇣",
    "cg": "cg" if ASCII else "⬡",
    "dot": "*" if ASCII else "●",
    "sep": " | " if ASCII else " · ",
    "bay": " | " if ASCII else " │ ",
    "pmL": "[" if not NERD else "",
    "pmR": "]" if not NERD else "",
    "ell": "~" if ASCII else "…",
    "none": "-" if ASCII else "–",
    "delta": "~" if ASCII else "±",
}


def x256(rgb):
    r, g, b = rgb
    if abs(r - g) < 12 and abs(g - b) < 12 and abs(r - b) < 12:
        return 232 + min(23, max(0, (r - 8) * 24 // 247))
    q = lambda c: int(round(c / 255.0 * 5))
    return 16 + 36 * q(r) + 6 * q(g) + q(b)


def fg(rgb):
    if MONO:
        return ""
    if TRUE:
        return "\x1b[38;2;%d;%d;%dm" % rgb
    return "\x1b[38;5;%dm" % x256(rgb)


def bg(rgb):
    if MONO:
        return ""
    if TRUE:
        return "\x1b[48;2;%d;%d;%dm" % rgb
    return "\x1b[48;5;%dm" % x256(rgb)


def paint(rgb, s, bold=False):
    if MONO:
        return s
    return ("\x1b[1m" if bold else "") + fg(rgb) + s + RESET


def cwidth(ch):
    o = ord(ch)
    if o < 32:
        return 0
    if 0x0300 <= o <= 0x036F or 0xFE00 <= o <= 0xFE0F:
        return 0
    for lo, hi in WIDE:
        if lo <= o <= hi:
            return 2
    return 1


def dwidth(s):
    return sum(cwidth(c) for c in ANSI_RE.sub("", s))


def trunc(s, n):
    if n <= 1:
        return ""
    if dwidth(s) <= n:
        return s
    out = ""
    for c in s:
        if dwidth(out) + cwidth(c) > n - 1:
            break
        out += c
    return out + GL["ell"]


def clamp01(v):
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def ramp_at(ramp, t):
    t = clamp01(t)
    for i in range(len(ramp) - 1):
        p0, c0 = ramp[i]
        p1, c1 = ramp[i + 1]
        if t <= p1:
            k = 0.0 if p1 == p0 else (t - p0) / (p1 - p0)
            return tuple(int(round(c0[j] + (c1[j] - c0[j]) * k)) for j in range(3))
    return ramp[-1][1]


def meter(frac, cells, ramp):
    if ASCII:
        if frac is None:
            return paint(PAL["trough"], "-" * cells)
        n = int(round(clamp01(frac) * cells))
        if frac > 0 and n == 0:
            n = 1
        return paint(ramp_at(ramp, clamp01(frac)), "#" * n) + paint(PAL["trough"], "-" * (cells - n))

    def track(n):
        if n <= 0:
            return ""
        return bg(PAL["track"]) + fg(PAL["dither"]) + SHADE * n

    if frac is None:
        return track(cells) + BG_OFF + RESET
    frac = clamp01(frac)
    e = int(round(frac * cells * 8))
    if frac > 0 and e == 0:
        e = 1
    e = min(e, cells * 8)
    full, rem = divmod(e, 8)
    out = []
    for i in range(full):
        out.append(fg(ramp_at(ramp, (i + 0.5) / cells)) + FULLBLK)
    idx = full
    if rem:
        out.append(bg(PAL["track"]) + fg(ramp_at(ramp, (idx + 0.5) / cells)) + EIGHTHS[rem - 1])
        idx += 1
        if idx < cells:
            out.append(fg(PAL["dither"]) + SHADE * (cells - idx))
    else:
        out.append(track(cells - idx))
    out.append(BG_OFF + RESET)
    return "".join(out)


DOTS = ((0x01, 0x02, 0x04, 0x40), (0x08, 0x10, 0x20, 0x80))


def spark(vals, chars):
    need = chars * 2
    v = list(vals)[-need:]
    v = [0] * (need - len(v)) + v
    if ASCII:
        step = " .:|#"
        return "".join(step[min(4, max(0, int(x) * 5 // 101))] for x in v[-chars:])
    out = ""
    for c in range(chars):
        bits = 0
        for col in range(2):
            val = max(0, min(100, int(v[c * 2 + col])))
            lvl = 1 if val <= 0 else max(1, min(4, int(math.ceil(val / 100.0 * 4))))
            for r in range(4 - lvl, 4):
                bits |= DOTS[col][r]
        out += chr(0x2800 + bits)
    return out


def dig(d, path, default=None):
    cur = d
    for k in path.split("."):
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return default if cur is None else cur


def fnum(v, default=None):
    try:
        f = float(v)
    except Exception:
        return default
    if f != f or f in (float("inf"), float("-inf")):
        return default
    return f


def key_for(s):
    return hashlib.md5(s.encode("utf-8", "replace")).hexdigest()[:14]


def cached(key, ttl, fn):
    path = os.path.join(CACHE_DIR, key + ".json")
    now = time.time()
    stale = None
    try:
        st = os.stat(path)
        with open(path) as f:
            stale = json.load(f)
        if now - st.st_mtime < ttl:
            return stale
    except Exception:
        stale = None
    try:
        fresh = fn()
    except Exception:
        fresh = None
    if fresh is None:
        if stale is not None:
            try:
                os.utime(path, (now, now))
            except Exception:
                pass
        return stale
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = "%s.%d" % (path, os.getpid())
        with open(tmp, "w") as f:
            json.dump(fresh, f)
        os.replace(tmp, path)
    except Exception:
        pass
    return fresh


def run(args, cwd, timeout):
    try:
        p = subprocess.run(args, cwd=cwd, timeout=timeout, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"))
    except Exception:
        return None
    if p.returncode != 0:
        return None
    return p.stdout.decode("utf-8", "replace")


def git_probe(d):
    out = run(["git", "status", "--porcelain=v2", "--branch"], d, 1.2)
    if out is None:
        return {"repo": False}
    info = {"repo": True, "branch": "", "ahead": 0, "behind": 0, "files": 0, "up": False}
    for ln in out.split("\n"):
        if ln.startswith("# branch.head "):
            info["branch"] = ln[14:].strip()
        elif ln.startswith("# branch.oid "):
            info["oid"] = ln[13:].strip()[:7]
        elif ln.startswith("# branch.ab "):
            parts = ln[12:].split()
            if len(parts) == 2:
                info["up"] = True
                info["ahead"] = abs(int(parts[0]))
                info["behind"] = abs(int(parts[1]))
        elif ln and not ln.startswith("# "):
            info["files"] += 1
    if info["branch"] in ("", "(detached)"):
        info["branch"] = info.get("oid", "")
        info["detached"] = True
    return info


def find_up(start, rel):
    d = os.path.abspath(start)
    for _ in range(40):
        if os.path.exists(os.path.join(d, rel)):
            return d
        nd = os.path.dirname(d)
        if nd == d:
            break
        d = nd
    return None


def cg_probe(root):
    out = run(["codegraph", "status", "--json"], root, 1.8)
    if out is None:
        return {"state": "off", "pending": 0}
    try:
        j = json.loads(out)
    except Exception:
        return {"state": "off", "pending": 0}
    if not j.get("initialized"):
        return {"state": "off", "pending": 0}
    pc = j.get("pendingChanges") or {}
    pending = sum(int(pc.get(k) or 0) for k in ("added", "modified", "removed"))
    if (j.get("index") or {}).get("reindexRecommended"):
        return {"state": "reindex", "pending": pending}
    return {"state": "stale" if pending else "ok", "pending": pending}


def codegraph_state(d):
    root = find_up(d, os.path.join(".codegraph", "codegraph.db"))
    if not root:
        return {"state": "none", "pending": 0}
    if not shutil.which("codegraph"):
        return {"state": "none", "pending": 0}
    got = cached("cg-" + key_for(root), 30, lambda: cg_probe(root))
    return got or {"state": "off", "pending": 0}


def trend_push(sid, pct):
    path = os.path.join(CACHE_DIR, "trend-" + key_for(sid) + ".json")
    now = time.time()
    data = {"t": 0, "v": []}
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        pass
    vals = [int(x) for x in (data.get("v") or [])][-24:]
    if pct is not None and (now - float(data.get("t") or 0) >= 15 or not vals):
        vals.append(int(round(pct)))
        vals = vals[-24:]
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            tmp = "%s.%d" % (path, os.getpid())
            with open(tmp, "w") as f:
                json.dump({"t": now, "v": vals}, f)
            os.replace(tmp, path)
        except Exception:
            pass
    return vals


def countdown(ts):
    if not ts:
        return ""
    left = int(ts - time.time())
    if left <= 0:
        return "now"
    m = left // 60
    if m < 60:
        return "%dm" % m
    h, m2 = m // 60, m % 60
    if h < 24:
        return "%dh%02d" % (h, m2)
    d, h2 = h // 24, h % 24
    if d < 10:
        return "%dd%02d" % (d, h2)
    return "%dd" % d


def term_width():
    v = fnum(os.environ.get("SL_WIDTH"))
    if v:
        return int(v)
    v = fnum(os.environ.get("COLUMNS"))
    if v and v > 20:
        return int(v)
    for fd in (1, 2, 0):
        try:
            return os.get_terminal_size(fd).columns
        except Exception:
            pass
    try:
        fd = os.open("/dev/tty", os.O_RDONLY)
        try:
            return os.get_terminal_size(fd).columns
        finally:
            os.close(fd)
    except Exception:
        pass
    return 110


def pill(text, tone, bold=True):
    if MONO:
        return "[" + text + "]"
    if not NERD:
        return ("\x1b[1m" if bold else "") + fg(tone) + "[" + text + "]" + RESET
    return (fg(tone) + GL["pmL"] + bg(tone) + fg(PAL["ink"]) + ("\x1b[1m" if bold else "")
            + text + RESET + fg(tone) + GL["pmR"] + RESET)


EFFORT_GLYPH = {"low": "▁", "medium": "▃", "high": "▅",
                "xhigh": "▇", "max": "█"}
EFFORT_TONE = {"low": PAL["sky"], "medium": PAL["green"], "high": PAL["yellow"],
               "xhigh": PAL["peach"], "max": PAL["red"]}
EFFORT_WORD = {"low": "low", "medium": "med", "high": "high", "xhigh": "xhigh", "max": "MAX"}


def gauge(label, frac, pct_txt, ramp, extra, cells, hot, lab_tone=None):
    boldlab = False
    if lab_tone is None:
        lab_tone = PAL["dim"]
        if hot is not None:
            if hot >= 90:
                lab_tone, boldlab = PAL["red"], True
            elif hot >= 75:
                lab_tone = PAL["peach"]
            else:
                lab_tone = PAL["sub"]
    tip = ramp_at(ramp, frac) if frac is not None else PAL["dim"]
    s = (paint(lab_tone, "%7s" % label[:7], boldlab) + " ") if label else ""
    s += meter(frac, cells, ramp) + " " + paint(tip, "%4s" % pct_txt)
    if extra is not None:
        s += " " + extra
    return s


def elapsed(seconds):
    seconds = int(max(0, seconds))
    h, m = divmod(seconds // 60, 60)
    if h >= 24:
        return "%dd%dh" % (h // 24, h % 24)
    if h:
        return "%dh%02d" % (h, m)
    return "%dm" % m if m else "%ds" % seconds


def build_gauges(d, W, trend):
    """A compact context meter. Small on purpose — it sits under a dense line."""
    cw = d.get("context_window") or {}
    pct = fnum(cw.get("used_percentage"))
    size = fnum(cw.get("context_window_size")) or 0
    tok = (fnum(cw.get("total_input_tokens"), 0) or 0) \
        + (fnum(cw.get("total_output_tokens"), 0) or 0)
    if pct is None:
        cu = cw.get("current_usage") or {}
        tot = sum(fnum(cu.get(k), 0) or 0 for k in
                  ("input_tokens", "output_tokens", "cache_creation_input_tokens",
                   "cache_read_input_tokens"))
        if size > 0 and tot > 0:
            pct = tot * 100.0 / size

    trail = ""
    if tok > 0 and size > 0:
        trail = "%s/%s" % (compact_tokens(tok), compact_tokens(size))
    elif tok > 0:
        trail = compact_tokens(tok)

    cells = max(8, min(20, (W - 3) - 5 - (1 + dwidth(trail) if trail else 0)))
    pct_txt = GL["none"] if pct is None else "%d%%" % int(round(pct))
    extra = paint(PAL["dim"], trail) if trail else None
    return gauge("", None if pct is None else clamp01(pct / 100.0),
                 pct_txt, LOAD_RAMP, extra, cells, pct)


P_AGENT, P_WT, P_BRANCH, P_DIRTY, P_CG = 1, 1, 2, 2, 3
P_DIR, P_DIR2, P_VIM, P_PR = 4, 7, 5, 5
P_EFFORT, P_LINES, P_TOKENS, P_CGNONE, P_MINOR = 6, 7, 8, 8, 9


def compact_tokens(n):
    n = int(n)
    if n >= 1000000:
        return ("%.1fM" % (n / 1000000.0)).replace(".0M", "M")
    return "%dk" % (n / 1000.0) if n >= 1000 else str(n)


def build_place(d, W):
    cwd = dig(d, "workspace.current_dir") or d.get("cwd") or os.getcwd()
    segs = []

    def add(pri, txt):
        segs.append([pri, txt, dwidth(txt)])

    name = dig(d, "model.display_name") or ""
    name = re.sub(r"\s*\(.*?\)\s*$", "", name).strip()
    name = re.sub(r"^Claude\s+", "", name) or "claude"
    size = fnum(dig(d, "context_window.context_window_size"), 0) or 0
    head = paint(PAL["brand"], GL["brand"]) + " " + paint(PAL["lav"], trunc(name, 18), True)
    if size >= 1000000:
        head += " " + paint(PAL["mauve"], "1M")
    add(0, head)

    eff = dig(d, "effort.level") or d.get("effortLevel")
    if eff:
        think = dig(d, "thinking.enabled", True)
        tone = EFFORT_TONE.get(eff, PAL["dim"]) if think else PAL["faint"]
        gly = "" if ASCII else EFFORT_GLYPH.get(eff, "▃") + " "
        add(P_EFFORT, paint(tone, gly + EFFORT_WORD.get(eff, str(eff)[:5])))

    if d.get("fast_mode"):
        add(P_EFFORT, pill("FAST", PAL["yellow"]))

    agent = dig(d, "agent.name")
    if agent:
        add(P_AGENT, pill(trunc(str(agent), 18), PAL["mauve"]))

    wt = dig(d, "worktree.name") or dig(d, "workspace.git_worktree")
    base = os.path.basename(os.path.normpath(cwd)) or cwd
    if not (wt and str(wt) in base):
        add(P_DIR2 if wt else P_DIR, paint(PAL["blue"], GL["dir"] + " " + trunc(base, 20)))
    if wt:
        add(P_WT, paint(PAL["mauve"], GL["fork"] + " " + trunc(str(wt), 22)))

    gi = cached("git-" + key_for(cwd), 5, lambda: git_probe(cwd)) if os.path.isdir(cwd) else None
    if gi and gi.get("repo"):
        br = gi.get("branch") or "?"
        tone = PAL["peach"] if gi.get("detached") else PAL["lav"]
        s = paint(tone, GL["branch"] + " " + trunc(br, 22))
        if gi.get("up"):
            a, b = gi.get("ahead", 0), gi.get("behind", 0)
            if a or b:
                s += " " + paint(PAL["green"] if a else PAL["faint"], GL["up"] + (str(a) if a else ""))
                s += " " + paint(PAL["sky"] if b else PAL["faint"], GL["down"] + (str(b) if b else ""))
            else:
                s += " " + paint(PAL["faint"], GL["up"] + GL["down"])
        add(P_BRANCH, s)
        n = gi.get("files", 0)
        add(P_DIRTY, paint(PAL["peach"], GL["delta"] + str(n)) if n else paint(PAL["green"], "clean"))

    la = int(fnum(dig(d, "cost.total_lines_added"), 0) or 0)
    lr = int(fnum(dig(d, "cost.total_lines_removed"), 0) or 0)
    if la or lr:
        add(P_LINES, paint(PAL["green"], "+" + str(la)) + " " + paint(PAL["red"], "-" + str(lr)))

    cg = codegraph_state(cwd)
    st, pend = cg.get("state"), cg.get("pending", 0)
    cgtxt = {"ok": (PAL["teal"], "ok"), "stale": (PAL["peach"], "~%d" % pend),
             "reindex": (PAL["red"], "rdx"), "off": (PAL["dim"], "off"),
             "none": (PAL["faint"], "none")}.get(st, (PAL["faint"], "none"))
    add(P_CGNONE if st == "none" else P_CG, paint(cgtxt[0], GL["cg"] + " " + cgtxt[1]))

    prn = dig(d, "pr.number")
    if prn:
        rs = str(dig(d, "pr.review_state") or "")
        tone = {"approved": PAL["green"], "changes_requested": PAL["red"],
                "pending": PAL["yellow"]}.get(rs, PAL["sky"])
        add(P_PR, paint(PAL["sub"], "PR#" + str(prn)) + " " + paint(tone, GL["dot"]))

    vm = dig(d, "vim.mode")
    if vm:
        tone = {"NORMAL": PAL["green"], "INSERT": PAL["blue"], "VISUAL": PAL["peach"],
                "REPLACE": PAL["red"]}.get(str(vm).upper(), PAL["sub"])
        add(P_VIM, pill(str(vm).upper()[:7], tone))

    wall = (fnum(dig(d, "cost.total_duration_ms"), 0) or 0) / 1000.0
    if wall >= 60:
        add(P_TOKENS, paint(PAL["dim"], elapsed(wall)))

    style = dig(d, "output_style.name")
    if style and style != "default":
        add(P_MINOR, paint(PAL["dim"], trunc(str(style), 12)))

    add(0, pill("PONYTAIL", PAL["pink"]))

    budget = W - 3
    sep = paint(PAL["faint"], GL["sep"])
    sepw = dwidth(GL["sep"])

    def total():
        return sum(s[2] for s in segs) + sepw * max(0, len(segs) - 1)

    while total() > budget:
        worst, idx = -1, -1
        for i, s in enumerate(segs):
            if s[0] >= worst and s[0] > 0:
                worst, idx = s[0], i
        if idx < 0:
            break
        segs.pop(idx)
    return sep.join(s[1] for s in segs)


def main():
    raw = ""
    try:
        raw = sys.stdin.read()
    except Exception:
        raw = ""
    try:
        d = json.loads(raw) if raw.strip() else {}
    except Exception:
        d = {}
    if not isinstance(d, dict):
        d = {}
    W = max(40, min(400, term_width()))

    trend = []

    l1 = build_place(d, W)
    l2 = build_gauges(d, W, trend)
    gap = "\n\n" if os.environ.get("SL_GAP", "1") == "1" else "\n"
    write(l1 + gap + l2)


def write(text):
    """stdout may not be UTF-8 (PYTHONIOENCODING, C locale) — degrade, never raise."""
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass
    try:
        sys.stdout.write(text)
    except Exception:
        try:
            sys.stdout.write(ANSI_RE.sub("", text).encode("ascii", "replace").decode("ascii"))
        except Exception:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        try:
            write("claude-code")
        except Exception:
            pass
    sys.exit(0)
