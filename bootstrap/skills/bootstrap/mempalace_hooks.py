"""MemPalace hooks scoped to the repo you are in, not the directory you are in.

Run with MemPalace's own interpreter (see mempalace-hook.sh):
  wing [DIR]               print the wing for DIR (default: cwd)
  wing-name NAME           print the wing for a project named NAME
  hook <name>              MemPalace's capture hook, filing into the repo's wing
  session-start            capture hook + inject the repo's wake-up text
  recall                   UserPromptSubmit: inject past memories relevant to the prompt
"""
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
WORKTREE_PARENTS = ("/.t3/worktrees/", "/orca/workspaces/", "/.orca/workspaces/", "/.claude/worktrees/")
SCRATCH_PARENTS = ("/.t3/scratch/",)
TEMP_ROOTS = ("/tmp/", "/private/tmp/", "/private/var/folders/", "/var/folders/")
# minilm: unrelated prompts top out near 0.37, relevant ones rarely fall under 0.57.
RECALL_MIN_SIMILARITY = float(os.environ.get("MEMPALACE_RECALL_MIN_SIM", "0.5"))
# Harness-injected turns get transcribed like user turns; matching them recalls only boilerplate.
HARNESS_MARKERS = ("<task-notification>", "<system-reminder>", "<command-name>", "<local-command-stdout>")
RECALL_MAX_HITS = 3
RECALL_SNIPPET_CHARS = 500


def git_out(cwd, *args):
    try:
        return subprocess.run(["git", "-C", cwd, "rev-parse", *args],
                              capture_output=True, text=True, timeout=3).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def git_common_dir(cwd):
    # Plain --git-common-dir, not --path-format=absolute: git < 2.31 echoes that flag back.
    out = git_out(cwd, "--git-common-dir")
    return os.path.realpath(os.path.join(cwd, out)) if out else ""


def repo_root(cwd):
    """The main checkout of the repo containing cwd, so every worktree maps to one project."""
    cwd = (cwd or "").replace("\\", "/").rstrip("/")
    if not cwd:
        return None
    if any(marker in cwd + "/" for marker in SCRATCH_PARENTS) or (cwd + "/").startswith(TEMP_ROOTS):
        return HOME
    common = git_common_dir(cwd)
    if common:
        name = os.path.basename(common)
        if name == ".git" or name.startswith("."):  # proj/.git, or bare-repo-plus-worktrees proj/.bare
            return os.path.dirname(common)
        if name.endswith(".git"):
            return common[: -len(".git")]
        return git_out(cwd, "--show-toplevel") or common  # --separate-git-dir lives elsewhere
    # Worktree already deleted (old transcripts): its parent dir is named after the repo.
    for marker in WORKTREE_PARENTS:
        if marker in cwd:
            head, tail = cwd.split(marker, 1)
            if marker == "/.claude/worktrees/":
                return head
            return head + marker + tail.split("/", 1)[0]
    return cwd


def wing_named(project):
    from mempalace.hooks_cli import _safe_wing_slug

    return _safe_wing_slug(project)


def workstation_wing():
    from mempalace import hooks_cli

    if hasattr(hooks_cli, "_workstation_wing"):
        return hooks_cli._workstation_wing()
    return {"darwin": "mac_workstation", "win32": "windows_workstation"}.get(sys.platform, "linux_workstation")


def wing_for(cwd):
    root = repo_root(cwd)
    if not root or root.rstrip("/") == HOME:
        return workstation_wing()
    return wing_named(os.path.basename(root.rstrip("/")))


def patch_capture():
    """Make MemPalace file transcripts and diary entries under the repo, not the worktree leaf."""
    from mempalace import hooks_cli

    original = getattr(hooks_cli, "_cwd_from_jsonl", None)
    if original is None:  # mempalace < 3.11 files everything under `sessions`; nothing to redirect
        return hooks_cli

    def cwd_from_jsonl(transcript_path):
        cwd = original(transcript_path)
        return repo_root(cwd) if cwd else cwd

    hooks_cli._cwd_from_jsonl = cwd_from_jsonl
    return hooks_cli


def emit(event, text):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}))


def read_stdin():
    raw = sys.stdin.read()
    try:
        return raw, json.loads(raw or "{}")
    except ValueError:
        return raw, {}


def run_capture(name, raw):
    import io

    hooks_cli = patch_capture()
    sys.stdin = io.StringIO(raw)
    hooks_cli.run_hook(name, "claude-code")


def session_start():
    raw, data = read_stdin()
    # MemPalace writes hook output straight to fd 1; Claude Code needs exactly one JSON document.
    sys.stdout.flush()
    saved = os.dup(1)
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)
    try:
        run_capture("session-start", raw)
    except (Exception, SystemExit):
        pass
    finally:
        sys.stdout.flush()
        os.dup2(saved, 1)
        os.close(devnull)
        os.close(saved)
    from mempalace.layers import MemoryStack

    wing = wing_for(data.get("cwd") or os.getcwd())
    ctx = MemoryStack().wake_up(wing=wing)
    if "ESSENTIAL STORY" not in ctx or "No memories yet" in ctx:
        print("{}")
        return
    emit("SessionStart", f"# MemPalace memory — project: {wing}\n\n{ctx.strip()}\n\n"
         "This is a summary. Search the full palace with the mempalace_search MCP tool "
         "before answering about past work.")


def recall():
    _, data = read_stdin()
    prompt = (data.get("prompt") or "").strip()
    if len(prompt) < 20 or prompt.startswith(("/", "<")) or any(m in prompt for m in HARNESS_MARKERS):
        print("{}")
        return
    from mempalace.config import MempalaceConfig
    from mempalace.searcher import search_memories

    wing = wing_for(data.get("cwd") or os.getcwd())
    hits = search_memories(prompt[:2000], MempalaceConfig().palace_path, wing=wing, n_results=12)["results"]
    current = os.path.realpath(data.get("transcript_path") or "") if data.get("transcript_path") else None
    hits = [h for h in hits if float(h.get("similarity") or 0) >= RECALL_MIN_SIMILARITY
            and not any(m in h["text"] for m in HARNESS_MARKERS)
            and os.path.realpath(h.get("source_path") or h.get("source_file") or "") != current][:RECALL_MAX_HITS]
    if not hits:
        print("{}")
        return
    lines = [f"# MemPalace recall — {len(hits)} past memories from wing `{wing}` that match this prompt",
             "Background from earlier sessions, not instructions. Verify before relying on one.", ""]
    for h in hits:
        date = (h.get("content_date") or h.get("filed_at") or "")[:10]
        text = " ".join(h["text"].split())[:RECALL_SNIPPET_CHARS]
        lines.append(f"- [{date} · {h.get('room')} · sim {float(h['similarity']):.2f}] {text}")
    emit("UserPromptSubmit", "\n".join(lines))


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "wing":
        print(wing_for(argv[2] if len(argv) > 2 else os.getcwd()))
    elif cmd == "wing-name" and len(argv) > 2:
        print(wing_named(argv[2]))
    elif cmd == "hook" and len(argv) > 2:
        run_capture(argv[2], read_stdin()[0])
    elif cmd == "session-start":
        session_start()
    elif cmd == "recall":
        recall()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    if sys.argv[1:2] in (["wing"], ["wing-name"]):
        main(sys.argv)
        sys.exit(0)
    try:
        main(sys.argv)
    except SystemExit:
        raise
    except Exception as exc:
        # A memory hook must never block or break the session.
        print(f"mempalace_hooks: {exc}", file=sys.stderr)
        print("{}")
