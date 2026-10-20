"""Re-file an existing palace by repo, the way mempalace_hooks.py files new memories.

  bash mempalace-hook.sh reorg [--reimport-claude-mem]

1. Every wing holding Claude Code transcripts is split by the repo each session ran in, so
   `sessions`, per-worktree and per-branch wings collapse into one wing per repo.
2. --reimport-claude-mem drops drawers mined from the old monthly claude-mem export,
   re-exports one file per memory, and mines each project into its repo-named wing.
Back up ~/.mempalace/palace first; MCP servers holding the palace lock must be stopped.
"""
import glob
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mempalace_hooks as mh  # noqa: E402
from mempalace.config import MempalaceConfig  # noqa: E402
from mempalace.hooks_cli import _cwd_from_jsonl  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = os.path.expanduser("~/claude-mem-export")
CFG = MempalaceConfig()
DB = os.path.join(CFG.palace_path, "chroma.sqlite3")
TEMP_KEY_PREFIXES = ("-private-tmp-", "-tmp-", "-private-var-folders-")


def sql(query, *args):
    return sqlite3.connect(f"file:{DB}?mode=ro", uri=True).execute(query, args).fetchall()


def mempalace(*args):
    # Live sessions' Stop hooks take the palace lock for a few seconds; wait them out.
    for _ in range(120):
        r = subprocess.run(["mempalace", *args], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if r.returncode == 0:
            return
        if "is held by PID" not in r.stderr:
            sys.exit(f"mempalace {' '.join(args)} failed:\n{r.stderr[-2000:]}")
        time.sleep(5)
    sys.exit(f"mempalace {' '.join(args)}: palace stayed locked for 10 minutes")


def target_for_key(key, current):
    """Wing for an encoded ~/.claude/projects/<key> dir, from a surviving transcript if any."""
    for f in glob.glob(os.path.expanduser(f"~/.claude/projects/{glob.escape(key)}/*.jsonl"))[:5]:
        cwd = _cwd_from_jsonl(f)
        if cwd:
            return mh.wing_for(cwd)
    m = re.search(r"-(?:orca-workspaces|t3-worktrees)-([A-Za-z0-9_.]+)-", key)
    if m:
        return mh.wing_named(m.group(1))
    if "-t3-scratch-" in key or key.startswith(TEMP_KEY_PREFIXES):
        return mh.wing_for(mh.HOME)
    return current


def split_transcript_wings():
    wings = [w for (w,) in sql(
        "select distinct w.string_value from embedding_metadata w join embedding_metadata s "
        "on s.id = w.id and s.key = 'source_file' where w.key = 'wing' and s.string_value like ?",
        os.path.expanduser("~/.claude/projects/%"))]
    for wing in wings:
        mempalace("wings", "split", "--wing", wing)
        path = os.path.join(CFG.palace_path, "wings", f"split-{wing}.json")
        plan = json.load(open(path))
        for key, entry in plan["projects"].items():
            entry["target"] = target_for_key(key, entry["target"])
            entry["how"] = "repo"
        moving = sum(e["drawers"] for e in plan["projects"].values() if e["target"] != wing)
        if not moving:
            continue
        json.dump(plan, open(path, "w"), indent=2)
        mempalace("wings", "split", "--wing", wing, "--yes")
        print(f"  {wing}: {moving} drawers re-filed by repo")


def reimport_claude_mem():
    from mempalace.mcp_server import tool_delete_by_source

    # Export first: if it fails, the old drawers are still there.
    subprocess.run(["node", os.path.join(HERE, "mempalace-export.mjs")], check=True)
    sources = [s for (s,) in sql(
        "select distinct string_value from embedding_metadata where key = 'source_file' and string_value like ?",
        EXPORT + "/%")]
    for s in sources:
        r = tool_delete_by_source(s, dry_run=False)
        if not r.get("success"):
            sys.exit(f"delete failed for {s}: {r.get('error')}")
    print(f"  dropped drawers from {len(sources)} previously mined export files")
    for d in sorted(glob.glob(os.path.join(EXPORT, "projects", "*", ""))):
        name = os.path.basename(d.rstrip("/"))
        mempalace("mine", d, "--wing", mh.wing_named(name))
        print(f"  mined {name}")


if __name__ == "__main__":
    split_transcript_wings()
    if "--reimport-claude-mem" in sys.argv:
        if not os.path.exists(os.path.expanduser("~/.claude-mem/claude-mem.db")):
            sys.exit("no ~/.claude-mem/claude-mem.db to re-export from")
        reimport_claude_mem()
