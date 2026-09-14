#!/usr/bin/env python3
"""Claude Code status line — quiet, session-scoped, two lines.

   claude-tools    statusline-and-config ±27 ↑2   +2822 −62    #42 ●
  ◆ Opus 5 1M   xhigh   43m   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 29%  294k   PONYTAIL

Line 1 is where you are: directory, branch, working-tree changes, lines this
session, open PR. Line 2 is the session: model, effort, elapsed, context.

Nothing account-level (no spend, no rate limits) and nothing that needs a
caption. Two greys and one accent; colour only where it means something — the
meter runs green to 50 %, yellow to 70 %, red beyond, and the % follows it.
Whitespace separates groups. One pink badge, no filler.

Env:  SL_WIDTH  column budget (default: detected, else 110)
      SL_ASCII  1 → plain ASCII      SL_NO_NERD  1 → no Nerd Font icons
      SL_GAP    1 → spacer row       NO_COLOR    → monochrome
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
CACHE_DIR = "/tmp/claude-statusline-%d" % os.getuid()

ASCII = os.environ.get("SL_ASCII") == "1" or "UTF" not in (
    os.environ.get("LC_ALL") or os.environ.get("LC_CTYPE")
    or os.environ.get("LANG") or "UTF-8").upper()
NERD = not ASCII and os.environ.get("SL_NO_NERD") != "1"
MONO = bool(os.environ.get("NO_COLOR"))
TRUE = os.environ.get("COLORTERM", "") in ("truecolor", "24bit")

# Catppuccin Mocha, the quiet half of it.
TEXT = (205, 214, 244)
SUB = (166, 173, 200)
OVER = (108, 112, 134)
SURF = (69, 71, 90)
LAV = (180, 190, 254)
BRAND = (114, 102, 234)
GREEN = (166, 227, 161)
PEACH = (250, 179, 135)
RED = (243, 139, 168)
YELLOW = (249, 226, 175)
MAUVE = (203, 166, 247)
PINK = (245, 194, 231)

if ASCII:
    G = dict(brand="*", dir="", branch="", pr="PR", fork="wt", up="^", down="v",
             delta="~", dot="*", fill="=", rest="-", gap="   ")
else:
    G = dict(brand="◆", dir=" " if NERD else "", branch=" " if NERD else "⎇ ",
             pr=" " if NERD else "PR ", fork=" " if NERD else "⚇ ",
             up="↑", down="↓", delta="±", dot="●",
             fill="━", rest="─", gap="   ")


# ── color ────────────────────────────────────────────────────────────────────

def x256(rgb):
    r, g, b = rgb
    if abs(r - g) < 12 and abs(g - b) < 12:
        return 232 + min(23, max(0, (r - 8) * 24 // 247))
    q = lambda c: int(round(c / 255.0 * 5))
    return 16 + 36 * q(r) + 6 * q(g) + q(b)


def fg(rgb):
    if MONO:
        return ""
    return "\x1b[38;2;%d;%d;%dm" % rgb if TRUE else "\x1b[38;5;%dm" % x256(rgb)


def bg(rgb):
    if MONO:
        return ""
    return "\x1b[48;2;%d;%d;%dm" % rgb if TRUE else "\x1b[48;5;%dm" % x256(rgb)


def pill(text, tone, ink=(17, 17, 27)):
    if ASCII or not NERD:
        return paint(tone, "[%s]" % text, True)
    if MONO:
        return "[%s]" % text
    return (fg(tone) + "\ue0b6" + bg(tone) + fg(ink) + "\x1b[1m" + text
            + "\x1b[0m" + fg(tone) + "\ue0b4" + "\x1b[0m")


def ramp(t):
    """Meter colour by position: green to 50 %, yellow to 70 %, red beyond."""
    stops = [(0.0, GREEN), (0.5, YELLOW), (0.7, RED), (1.0, RED)]
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(int(round(c0[i] + (c1[i] - c0[i]) * k)) for i in range(3))
    return RED


def paint(rgb, s, bold=False):
    if MONO:
        return s
    return ("\x1b[1m" if bold else "") + fg(rgb) + s + "\x1b[0m"


# ── text width ───────────────────────────────────────────────────────────────

def dwidth(s):
    w = 0
    for ch in ANSI_RE.sub("", s):
        if unicodedata.combining(ch) or ch == "​":
            continue
        w += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return w


def trunc(s, n):
    return s if len(s) <= n else s[: max(1, n - 1)] + "…"


# ── payload ──────────────────────────────────────────────────────────────────

def dig(d, path, default=None):
    for k in path.split("."):
        if not isinstance(d, dict):
            return default
        d = d.get(k)
    return default if d is None else d


def fnum(v, default=None):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return default
    return default if f != f or f in (float("inf"), float("-inf")) else f


def compact(n):
    n = int(n)
    if n >= 1_000_000:
        return ("%.1fM" % (n / 1e6)).replace(".0M", "M")
    return "%dk" % (n / 1e3) if n >= 1000 else str(n)


def elapsed(seconds):
    m = int(seconds) // 60
    h, m = divmod(m, 60)
    if h >= 24:
        return "%dd%dh" % (h // 24, h % 24)
    return "%dh%02dm" % (h, m) if h else "%dm" % m


# ── git / codegraph, cached per directory ────────────────────────────────────

def cached(key, ttl, fn):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
    except Exception:
        return fn()
    path = os.path.join(CACHE_DIR, key + ".json")
    try:
        if time.time() - os.stat(path).st_mtime < ttl:
            with open(path) as f:
                return json.load(f)
    except Exception:
        pass
    val = fn()
    try:
        tmp = "%s.%d" % (path, os.getpid())
        with open(tmp, "w") as f:
            json.dump(val, f)
        os.replace(tmp, path)
    except Exception:
        pass
    return val


def run(args, cwd, timeout=2):
    try:
        r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def git_probe(cwd):
    if not run(["git", "rev-parse", "--git-dir"], cwd):
        return {}
    branch = run(["git", "symbolic-ref", "--short", "-q", "HEAD"], cwd)
    detached = not branch
    if detached:
        branch = run(["git", "rev-parse", "--short", "HEAD"], cwd)
    status = run(["git", "status", "--porcelain"], cwd)
    files = len([l for l in status.splitlines() if l.strip()])
    ahead = behind = 0
    ab = run(["git", "rev-list", "--left-right", "--count", "@{upstream}...HEAD"], cwd).split()
    if len(ab) == 2:
        try:
            behind, ahead = int(ab[0]), int(ab[1])
        except ValueError:
            pass
    root = run(["git", "rev-parse", "--show-toplevel"], cwd)
    return {"branch": branch, "detached": detached, "files": files,
            "ahead": ahead, "behind": behind, "root": root}


def codegraph_probe(root):
    if not root or not shutil.which("codegraph"):
        return {}
    if not os.path.exists(os.path.join(root, ".codegraph", "codegraph.db")):
        return {}
    try:
        st = json.loads(run(["codegraph", "status", "--json"], root) or "{}")
    except Exception:
        return {}
    if st.get("initialized") is not True:
        return {}
    pc = st.get("pendingChanges") or {}
    pending = sum(int(fnum(pc.get(k), 0) or 0) for k in ("added", "modified", "removed"))
    if dig(st, "index.reindexRecommended", False):
        return {"state": "reindex"}
    return {"state": "stale", "pending": pending} if pending else {"state": "ok"}


# ── layout ───────────────────────────────────────────────────────────────────

def term_width():
    for key in ("SL_WIDTH", "COLUMNS"):
        v = fnum(os.environ.get(key))
        if v and v > 20:
            return int(v)
    for fd in (1, 2, 0):
        try:
            return os.get_terminal_size(fd).columns
        except Exception:
            pass
    return 110


def fit(segs, width):
    """segs: [priority, text]. Drop the highest priority number first until it fits."""
    segs = [list(s) for s in segs if s[1]]
    gap = dwidth(G["gap"])

    def total():
        return sum(dwidth(s[1]) for s in segs) + gap * max(0, len(segs) - 1)

    while total() > width:
        idx = max(range(len(segs)), key=lambda i: segs[i][0])
        if segs[idx][0] == 0:
            break
        segs.pop(idx)
    return G["gap"].join(s[1] for s in segs)


def place_line(d, cwd):
    segs = []
    base = os.path.basename(os.path.normpath(cwd)) or cwd
    segs.append([0, paint(OVER, G["dir"]) + paint(SUB, trunc(base, 24))])

    wt = dig(d, "worktree.name") or dig(d, "workspace.git_worktree")
    if wt and str(wt) not in base:
        segs.append([1, paint(OVER, G["fork"]) + paint(LAV, trunc(str(wt), 22))])

    gi = cached("git-" + hashlib.md5(cwd.encode("utf-8", "replace")).hexdigest()[:12],
                5, lambda: git_probe(cwd)) if os.path.isdir(cwd) else {}
    if gi.get("branch"):
        tone = PEACH if gi.get("detached") else TEXT
        s = paint(OVER, G["branch"]) + paint(tone, trunc(gi["branch"], 28))
        if gi.get("files"):
            s += " " + paint(PEACH, G["delta"] + str(gi["files"]))
        if gi.get("ahead"):
            s += " " + paint(OVER, G["up"] + str(gi["ahead"]))
        if gi.get("behind"):
            s += " " + paint(OVER, G["down"] + str(gi["behind"]))
        segs.append([0, s])

    la = int(fnum(dig(d, "cost.total_lines_added"), 0) or 0)
    lr = int(fnum(dig(d, "cost.total_lines_removed"), 0) or 0)
    if la or lr:
        segs.append([2, paint(GREEN, "+%d" % la) + " " + paint(RED, "−%d" % lr)])

    prn = dig(d, "pr.number")
    if prn:
        state = str(dig(d, "pr.review_state") or "")
        tone = {"approved": GREEN, "changes_requested": RED, "pending": YELLOW}.get(state, OVER)
        segs.append([3, paint(OVER, G["pr"]) + paint(SUB, "#%s" % prn) + " " + paint(tone, G["dot"])])

    cg = cached("cg-" + hashlib.md5((gi.get("root") or "").encode()).hexdigest()[:12],
                30, lambda: codegraph_probe(gi.get("root") or ""))
    if cg.get("state") == "stale":
        segs.append([4, paint(PEACH, "graph ~%d" % cg.get("pending", 0))])
    elif cg.get("state") == "reindex":
        segs.append([4, paint(RED, "graph reindex")])

    agent = dig(d, "agent.name")
    if agent:
        segs.append([1, paint(MAUVE, trunc(str(agent), 20))])
    return segs


def session_line(d):
    segs = []
    name = re.sub(r"\s*\(.*?\)\s*$", "", dig(d, "model.display_name") or "").strip()
    name = re.sub(r"^Claude\s+", "", name) or "Claude"
    head = paint(BRAND, G["brand"]) + " " + paint(TEXT, trunc(name, 18), True)
    size = fnum(dig(d, "context_window.context_window_size"), 0) or 0
    if size >= 1_000_000:
        head += " " + paint(OVER, "1M")
    segs.append([0, head])

    eff = dig(d, "effort.level")
    if eff:
        segs.append([2, paint(SUB, str(eff))])
    if d.get("fast_mode"):
        segs.append([2, paint(YELLOW, "fast")])

    wall = (fnum(dig(d, "cost.total_duration_ms"), 0) or 0) / 1000.0
    if wall >= 60:
        segs.append([3, paint(OVER, elapsed(wall))])

    pct = fnum(dig(d, "context_window.used_percentage"))
    if pct is not None:
        pct = max(0.0, min(100.0, pct))
        cells = 32
        n = int(round(pct / 100.0 * cells))
        bar = "".join(fg(ramp((i + 0.5) / cells)) + G["fill"] for i in range(n))
        bar += paint(SURF, G["rest"] * (cells - n))
        s = bar + " " + paint(ramp(pct / 100.0), "%d%%" % int(round(pct)))
        used = (fnum(dig(d, "context_window.total_input_tokens"), 0) or 0) \
            + (fnum(dig(d, "context_window.total_output_tokens"), 0) or 0)
        if used:
            s += "  " + paint(OVER, compact(used))
        segs.append([0, s])

    vm = dig(d, "vim.mode")
    if vm:
        segs.append([4, paint(SUB, str(vm).lower())])

    segs.append([5, pill("PONYTAIL", PINK)])
    return segs


def write(text):
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


def main():
    try:
        raw = sys.stdin.read()
        d = json.loads(raw) if raw.strip() else {}
    except Exception:
        d = {}
    if not isinstance(d, dict):
        d = {}
    cwd = dig(d, "workspace.current_dir") or d.get("cwd") or os.getcwd()
    width = max(40, min(400, term_width())) - 2
    top = fit(place_line(d, cwd), width)
    bottom = fit(session_line(d), width)
    # Claude Code drops empty rows; a zero-width space survives a trim() and draws nothing.
    spacer = "\n​" if os.environ.get("SL_GAP", "0") == "1" else ""
    write(top + spacer + "\n" + bottom)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        write("claude-code")
    sys.exit(0)
