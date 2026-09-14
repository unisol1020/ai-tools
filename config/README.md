# config

My Claude Code preferences as a preset you can merge into your own `~/.claude/settings.json`.

```bash
./install.sh            # adds anything you don't already have; never clobbers your values
./install.sh --force    # let the preset win on conflicts
```

It backs up `settings.json` first, merges key by key, and prints exactly what it changed. Keys you already set are kept and reported, so running it is safe on a configured machine.

## What's in it

| Setting | Value | Why |
|---------|-------|-----|
| `permissions.defaultMode` | `bypassPermissions` | No approval prompt per tool call. **Read the warning below.** |
| `permissions.allow` | codegraph MCP tools | Pre-approved read-only code queries. |
| `ultracode` | `true` | Claude reaches for multi-agent workflows by default on substantial tasks. |
| `effortLevel` | `xhigh` | Default reasoning effort. |
| `tui` | `fullscreen` | Full-screen terminal UI. |
| `theme` | `dark` | |
| `autoCompactEnabled` | `true` | Compact automatically instead of stopping at the context limit. |
| `autoContinueAtUsageLimit` | `true` | Resume by itself once a rate-limit window rolls over. |
| `agentPushNotifEnabled` | `true` | Push notification when a background agent finishes. |
| `skipDangerousModePermissionPrompt` | `true` | Don't re-ask about bypass mode at every launch. |
| `skipWorkflowUsageWarning` | `true` | Don't warn about workflow token cost each time. |
| `voice` / `voiceEnabled` | hold-to-talk, off | |
| `enabledPlugins` | ponytail, vercel, posthog, typescript-lsp | Includes [ponytail](https://github.com/DietrichGebert/ponytail) — lazy-senior-dev mode. |
| `extraKnownMarketplaces` | ponytail, cmux-hub, ast-grep | Where those plugins come from. |

> **`bypassPermissions` lets Claude Code run tools without asking you first.** That is the point of it, and it is also the risk. Use it in repos you trust, on a machine where a bad command is recoverable. If you'd rather not, delete that key from `settings.preset.json` before installing.

## What's deliberately not in it

- **`model`** — yours to pick.
- **`hooks`** — each tool in this repo installs its own; a blanket copy would fight them.
- **`statusLine`** — installed by [`statusline/`](../statusline/README.md).
- Machine-local plugin cache paths, which only resolve on the machine that created them.

Ponytail is also installed by [`bootstrap/`](../bootstrap/README.md) via `setup-env.sh`, so a fresh machine gets it either way.
