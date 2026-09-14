# statusline

A quiet, two-line Claude Code status line scoped to **the current session**.

```
 claude-tools    statusline-and-config ±28 ↑2   +2822 −62    #42 ●
󰙴 Fable 5.1 1M   󰧑 xhigh   43m   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 29%  294k   PONYTAIL
```

**Line 1 — where you are.** Directory, branch (with changed-file count and ahead/behind when non-zero), lines added and removed this session, the open PR and its review state. A worktree or subagent name appears here when you're in one; a stale codegraph index shows as `graph ~12`.

**Line 2 — the session.** Model, context window size, reasoning effort, elapsed time, and the context meter with tokens used.

## Design

Two greys and one accent. Text and branch in white, everything secondary in grey, and colour only where it carries meaning: peach for a dirty tree, green and red for lines, and the meter — a gradient that runs green to 50 %, yellow to 70 %, red beyond, with the percentage in the colour of the tip. The one decorative element is the pink `PONYTAIL` pill.

Groups are separated by whitespace, not dots. Nothing is shown for "nothing": no `⬡ none`, no empty `↑↓`, no `$0.00`. The meter is a thin rule, the way pnpm draws progress, because a heavy block bar under a line of text swamps it.

Nothing account-level — no spend, no 5-hour or 7-day windows. Orca shows those.

## Install

```bash
./install.sh          # links into ~/.claude and wires settings.json
./demo.sh             # preview every state without restarting Claude Code
```

Python 3, stdlib only. Restart Claude Code after installing.

## Configuration

| Variable | Default | Effect |
|----------|---------|--------|
| `SL_WIDTH` | detected, else `110` | Column budget. Claude Code runs the script without a tty, so set this if your terminal is much wider or narrower. |
| `SL_GAP` | `0` | `1` adds a spacer row between the two lines (a zero-width space, since Claude Code drops empty rows). |
| `SL_ASCII` | `0` | Pure ASCII. Also on automatically when the locale isn't UTF-8. |
| `SL_NO_NERD` | `0` | Keep Unicode but drop the Nerd Font icons. |
| `NO_COLOR` | unset | Monochrome. |

Narrow terminals shed segments by priority; the directory, branch, model and meter are the last to go.

## Performance

Git state is cached 5 s and the codegraph probe 30 s, keyed per directory so switching repos never shows another repo's branch. Every subprocess has a timeout. Survives empty, malformed and non-UTF-8 input without a traceback and always exits 0 — `demo.sh` asserts it.

## Credits

- Started from [kcchien/claude-code-statusline](https://github.com/kcchien/claude-code-statusline) (MIT) — the habit of hiding zero-valued segments survives from there.
- Palette is [Catppuccin Mocha](https://github.com/catppuccin/catppuccin).
- Icons need a [Nerd Font](https://www.nerdfonts.com/); without one, set `SL_NO_NERD=1`.
- Payload reference: [Claude Code status line docs](https://code.claude.com/docs/en/statusline).
