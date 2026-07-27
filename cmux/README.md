# cmux setup — my terminal + editor + Claude Code environment, 1:1

This is my whole [cmux](https://cmux.com) workspace captured as files, so it reinstalls (or shares) exactly. cmux is a native macOS terminal app that bundles Ghostty; this setup makes it a glass terminal (Catppuccin theme, transparent + blurred), routes file-opens into Cursor at the git repo root instead of opening lone files, adds a colored Claude Code statusline, and ships a `db-tui` launcher that opens a terminal SQL client in a right-side split. Send this README to Claude Code and say *"install this"* — the installer lays everything down, backs up every file it touches, and **merges** your Claude settings instead of clobbering them. macOS only.

## How it works

The installer copies six config files to where each tool reads them. They don't talk to each other directly — each one just changes how its own app behaves, and together they produce the look and the file-routing.

```mermaid
graph LR
  CMUXJSON["config/cmux.json"] --> A["~/.config/cmux/cmux.json"]
  WRAP["config/open-in-micro.sh"] --> B["~/.config/cmux/open-in-micro.sh"]
  GHOST["config/ghostty-config"] --> C["~/.config/ghostty/config"]
  STATUS["config/statusline.sh"] --> D["~/.claude/statusline.sh"]
  SNIP["config/claude-settings.snippet.json"] -- "deep-merge" --> E["~/.claude/settings.json"]
  DBTUI["bin/db-tui.sh"] -- "symlink" --> F["~/.local/bin/db-tui"]

  A -- "preferredEditor points at wrapper" --> B
  B -- "text/code" --> CURSOR["Cursor, opened at git repo root"]
  B -- "images/PDF/video" --> PREVIEW["cmux preview, split right"]
  C --> LOOK["glass terminal: theme, opacity, blur, font"]
  D --> BAR["colored Claude Code statusline"]
  E -- "statusLine command" --> D
```

Walkthrough: cmux reads `cmux.json` for its own behavior (and `ghostty/config` for all the visuals, since it bundles Ghostty). When you Cmd-click a path, double-click a file, or click a Claude Code file mention, cmux hands the file to the open wrapper, which sends media to its preview split and text/code to Cursor — rooted at the file's git repo so it lands in a real project window. Claude Code reads the merged `settings.json`, which points `statusLine` at `statusline.sh`. `db-tui` rides along on your PATH for when you want a SQL client.

## What you get

| File | Installs to | Role |
|------|-------------|------|
| `config/cmux.json` | `~/.config/cmux/cmux.json` | cmux app behavior — editor routing, sidebar, browser link handling, minimal mode, `claude` on new workspace (UI `+` only — **not** on CLI-created workspaces) |
| `config/ghostty-config` | `~/.config/ghostty/config` | all terminal visuals — theme, opacity, blur, font, cursor |
| `config/open-in-micro.sh` | `~/.config/cmux/open-in-micro.sh` | the `preferredEditor` wrapper — routes text/code to Cursor at the git repo root, media to cmux preview |
| `config/statusline.sh` | `~/.claude/statusline.sh` | the Claude Code statusline (segments + colors) |
| `config/claude-settings.snippet.json` | merged into `~/.claude/settings.json` | statusLine / theme / tui / effort / model |
| `bin/db-tui.sh` | `~/.local/bin/db-tui` | open a terminal SQL client in a right-side cmux split |
| `skills/cmux/` | `~/.claude/skills/cmux` (symlink) | the **cmux driver skill** — lets Claude Code drive workspaces, panes, surfaces, the built-in browser, notifications and sidebar status. `parallel/` uses it to lay out its task runners. |

## Install — send this README to Claude Code

> **🤖 Claude Code — if a user sent you this README, install it now. macOS only. Steps:**
>
> 1. **Preflight.** Confirm `git` and the `cmux` CLI are present (`brew install --cask cmux` if not). `jq` is needed for the statusline + settings merge.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run the installer** (it backs up every file it touches and MERGES Claude settings — never overwrites):
>    ```bash
>    bash ~/.claude-tools/cmux/install.sh
>    ```
> 4. **Offer the optional flags — ASK the user first, don't assume:**
>    - `--with-deps` → brew-installs Cursor (`--cask cursor`), the JetBrains Mono Nerd Font, and `jq`. Ask before running brew.
>    - `--with-db` → brew-installs `harlequin` (the recommended terminal SQL client).
> 4b. **WARN the user before running:** the merged settings turn ON `permissions.defaultMode=bypassPermissions` — **every tool call is auto-approved with no prompt** (the screenshot's "bypass permissions on"). If they don't want that, delete the `permissions` and `skipDangerousModePermissionPrompt` keys from `config/claude-settings.snippet.json` before installing, or cycle modes later with **Shift+Tab**.
> 5. **Report back:** confirm what was written, list any `✗` dependencies the installer printed with their `brew` commands, and tell the user to **restart Claude Code once**. Mention the ponytail plugin (lazy-senior-dev mode) installs separately (step in the README); the `[PONYTAIL]` statusline badge shows regardless.
>
> Update later with `git -C ~/.claude-tools pull` then re-run `install.sh`. Uninstall: restore the `.bak-*` files (see bottom).

### Requirements

- **macOS 14+** and **[cmux](https://cmux.com)** (`brew install --cask cmux`). cmux bundles Ghostty, so it reads `~/.config/ghostty/config` directly.
- **Cursor** — the editor the open-wrapper drives (`brew install --cask cursor`); the wrapper calls its `cursor` CLI at `/usr/local/bin/cursor`.
- **`jq`** (statusline + settings merge) and the **JetBrains Mono Nerd Font** (`brew install --cask font-jetbrains-mono-nerd-font`).
- Optional: **`harlequin`** for the DB TUI.

---

## Configure each part 1:1

### 1. Terminal colors / theme / glass — `~/.config/ghostty/config`

All visual terminal config lives here. cmux reads Ghostty's config; it is *not* in `cmux.json`.

```ini
theme = light:Catppuccin Latte,dark:Catppuccin Mocha   # auto light/dark; or a single theme name
background-opacity = 0.92      # 1.0 = solid, lower = more see-through
background-blur = 20           # macOS blur radius behind the transparency
unfocused-split-opacity = 0.85 # dim panes you're not focused on
font-family = "JetBrainsMono Nerd Font"
font-size = 14
font-thicken = true            # slightly bolder glyphs
window-padding-x = 14
window-padding-y = 12
window-padding-balance = true  # even padding on all sides
window-padding-color = background
cursor-style = bar             # bar | block | underline
cursor-style-blink = false
mouse-hide-while-typing = true
```

- **Change the theme:** `ghostty +list-themes` lists every built-in (Catppuccin, Dracula, Nord, Tokyo Night, Gruvbox, and more). Set `theme = <name>` or the `light:…,dark:…` pair.
- **More/less glass:** drop `background-opacity` toward `0.80` for more transparency; set `background-blur = 0` to kill the blur.
- **Apply:** `cmux reload-config` (or **⌘⇧,**) — no app restart.

### 2. cmux behavior — `~/.config/cmux/cmux.json`

What this config changes from cmux defaults:

| Key | Value | Effect |
|-----|-------|--------|
| `app.preferredEditor` | the open wrapper | files open via the wrapper (§3) instead of cmux's default editor |
| `app.openSupportedFilesInCmux` | `false` | hand text/code to the wrapper rather than cmux's built-in editor |
| `app.openMarkdownInCmuxViewer` | `true` | `.md` opens in cmux's live markdown renderer |
| `app.minimalMode` | `true` | stripped-down chrome |
| `app.warnBeforeClosingTab` | `false` | no "are you sure" on close |
| `sidebar.showLog` / `showProgress` | `true` | live agent log + progress in the sidebar |
| `sidebarAppearance.matchTerminalBackground` | `true` | sidebar tint follows the terminal background (the glass look extends to the sidebar) |
| `terminal.showScrollBar` | `false` | no scrollbar |
| `fileExplorer.doubleClickAction` | `preferredEditor` | double-click a file → open via the wrapper |
| `shortcuts.bindings.switchRightSidebarToDock` | `cmd+shift+g` | custom keybind |
| `browser.*` | all `true` | terminal links, `localhost` ports, and PR links open in cmux's built-in browser |
| `newWorkspaceCommand` | `claude` | every new workspace launches Claude Code |

Edit with `cmux settings cmux-json`; the schema referenced at the top of the file gives autocomplete. Reload with `cmux reload-config`.

### 3. The open-routing wrapper → Cursor — `~/.config/cmux/open-in-micro.sh`

cmux calls this wrapper whenever you open a readable file (Cmd-click a terminal path, double-click in the file tree, click a Claude Code file mention). It routes by type:

- **images / PDF / audio / video** → cmux's built-in preview, split to the right.
- **text / code** → **Cursor**. The wrapper walks up from the file to the nearest `.git` and opens **that repo root as the workspace folder** — so the file lands in a real project window (LSP, search, file tree all scoped to the repo), not a lone untitled file. Cursor reuses a window already rooted at that folder, else opens a new one. The invocation is `cursor "$projroot" "$file"`. Every open is logged to `~/.config/cmux/open-wrapper.log`.

The wrapper is GUI-launched (minimal PATH), so each binary is an absolute path: Cursor's CLI at `/usr/local/bin/cursor` and cmux at `/Applications/cmux.app/Contents/Resources/bin/cmux`. If yours live elsewhere, adjust `CURSOR` / `CMUX` at the top of the script.

To use a different editor, point `app.preferredEditor` at it directly (e.g. `"zed"`, `"nvim"`) or edit `CURSOR` in the wrapper.

### 4. The statusline — `~/.claude/statusline.sh`

A bash script Claude Code runs to render the bottom bar (wired up via `statusLine` in settings), styled to the **Catppuccin Mocha** palette with `·` dividers. Segments, in order:

```
dir · ⎇ branch · ⇡ahead ⇣behind · ±files +adds -dels · context% · model 1M · effort · ⬡ codegraph · [PONYTAIL]
```

- **branch** + **ahead/behind** vs upstream, **±files +adds -dels** (or **✓ clean**).
- **context %** is parsed from the live transcript (matches `/context`): green <50%, peach 50–80%, red ≥80%.
- **model** name, with a Mauve `1M` badge for a 1M-context model.
- **effort** — read from the live merged settings (project-local > project > user), colored by level.
- **⬡ codegraph** — only when `codegraph` is installed and the repo has a `.codegraph/codegraph.db`: `✓` ok, `⚠N` stale (N pending), `reindex`, `off`, or `—` when no index db.
- **`[PONYTAIL]`** — a static trailing label; no plugin needed.

Tweaks:
- **Recolor:** the `C_*` variables near the top are ANSI-256 codes (`\033[38;5;<n>m`). Change a number, save — live on the next render.
- **Add/remove a segment:** each pushes onto the `segs` array; delete a block to drop it. The codegraph block no-ops cleanly when codegraph isn't installed.
- **Drop the badge:** delete the `segs+=("…[PONYTAIL]…")` line, or recolor it via `C_PONY`.

### 5. Claude Code settings — merged into `~/.claude/settings.json`

The installer deep-merges these keys (your other settings are preserved):

| Key | Value | Effect |
|-----|-------|--------|
| `statusLine.command` | `bash ~/.claude/statusline.sh` | wires up §4 |
| `theme` | `dark` | Claude Code UI theme |
| `tui` | `fullscreen` | full-screen TUI |
| `effortLevel` | `xhigh` | reasoning effort |
| `model` | `claude-opus-5[1m]` | Opus 5 with the 1M-context window |
| `autoCompactEnabled` | `true` | auto-compact long sessions |
| `ultracode` | `true` | multi-agent Workflow orchestration on substantive tasks |
| `skipDangerousModePermissionPrompt` | `true` | no confirmation when starting in bypass mode |
| `permissions.defaultMode` | `bypassPermissions` | ⚠️ auto-approves **every** tool call (see below) |

**⚠️ `bypassPermissions` ships ON by default** — the "**bypass permissions on**" line in the screenshot. Claude can edit files, run any shell command, and call any tool without asking. That is a real risk; keep it only if you understand it and trust your workflow. To opt out, delete the `permissions` and `skipDangerousModePermissionPrompt` keys from `config/claude-settings.snippet.json` before installing (or from `~/.claude/settings.json` after). Toggle it live anytime in Claude Code with **Shift+Tab** (cycles permission modes).

**One thing the installer does NOT do automatically:**

- **ponytail (lazy-senior-dev mode)** — install the plugin: `/plugin` → add marketplace `DietrichGebert/ponytail` → enable `ponytail`. Restart. (The `[PONYTAIL]` statusline badge shows regardless.)

---

## Terminal database client (TUI)

For poking at a database from the terminal, install one of these and use the `db-tui` launcher.

- **[harlequin](https://harlequin.sh)** *(recommended)* — a SQL IDE in the terminal: results grid, schema tree, query history, autocomplete; one tool for Postgres, SQLite, MySQL, DuckDB, and more.
  ```bash
  brew install harlequin            # or: pipx install 'harlequin[postgres]'
  ```
- **[lazysql](https://github.com/jorgerojas26/lazysql)** — lighter, vim-style TUI browser (Postgres/MySQL/SQLite). `brew install lazysql`.
- CLI-with-autocomplete alternatives: `pgcli`, `litecli`, `usql`.

**`db-tui`** opens your client in a **right-side cmux split** anchored to the current workspace (and runs inline when you're not in cmux):

```bash
db-tui 'postgres://user:pass@host:5432/db'   # explicit URL
DATABASE_URL='postgres://…' db-tui           # from the env
DB_CLIENT=lazysql db-tui                      # force a client
```

It auto-picks the first installed client in order: harlequin → lazysql → pgcli → litecli → usql.

---

## Uninstall / revert

Every file the installer writes is backed up next to it as `<file>.bak-<timestamp>`. To revert a piece, restore its newest `.bak-*`:

```bash
ls -t ~/.config/ghostty/config.bak-*    | head -1   # newest backup
ls -t ~/.claude/settings.json.bak-*     | head -1
# cp the one you want back over the live file, then: cmux reload-config
rm ~/.local/bin/db-tui                              # remove the launcher
```
