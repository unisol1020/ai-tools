"""Incrementally refresh a repo's graphify graph from the latest commit.

No LLM, no tokens: AST-only re-extraction of the code files changed in HEAD~1..HEAD,
merged into the existing graphify-out/graph.json. Generated/native/vendor dirs are
excluded by path segment, so they never enter the graph.

Installed by `/bootstrap` and invoked by the Claude Code PostToolUse hook after a
`git commit`. Deterministic and silent; the model is never involved.
"""

import subprocess
import sys
from pathlib import Path

EXCLUDE_SEGMENTS = {
    "node_modules", "ios", "android", "Pods", "dist", "build", ".next", "out",
    "vendor", "coverage", "graphify-out", ".venv", "venv", "__pycache__",
    ".git", "target", ".turbo", ".expo", "Carthage",
}
CODE_EXTS = (
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".go", ".rs", ".java",
    ".rb", ".php", ".c", ".cc", ".cpp", ".h", ".hpp", ".cs", ".kt", ".swift",
    ".scala", ".lua",
)
GRAPH = Path("graphify-out/graph.json")


def in_scope(f: str) -> bool:
    return f.endswith(CODE_EXTS) and not (set(f.split("/")) & EXCLUDE_SEGMENTS)


SYNCED = Path("graphify-out/.synced-sha")


def sync_base() -> str | None:
    prev = SYNCED.read_text().strip() if SYNCED.exists() else ""
    if prev and subprocess.run(["git", "cat-file", "-e", prev + "^{commit}"],
                               capture_output=True).returncode == 0:
        return prev
    return "HEAD~1" if subprocess.run(
        ["git", "rev-parse", "HEAD~1"], capture_output=True).returncode == 0 else None


def git_files(diff_filter: str, base: str) -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--name-only", f"--diff-filter={diff_filter}", base, "HEAD"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        return []
    return [f for f in out.stdout.splitlines() if in_scope(f)]


def main() -> int:
    if not GRAPH.exists():
        return 0
    base = sync_base()
    if base is None:
        return 0

    head = subprocess.run(["git", "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    changed = git_files("ACMR", base)
    deleted = git_files("D", base)
    if not changed and not deleted:
        SYNCED.write_text(head)
        return 0

    import json
    import networkx as nx  # noqa: F401
    from networkx.readwrite import json_graph
    from graphify.extract import extract
    from graphify.build import build_from_json
    from graphify.cluster import cluster, score_all
    from graphify.analyze import god_nodes, surprising_connections, suggest_questions
    from graphify.report import generate
    from graphify.export import to_json, to_html

    G = json_graph.node_link_graph(json.loads(GRAPH.read_text()), edges="links")

    stale = set(changed) | set(deleted)
    G.remove_nodes_from([n for n, d in G.nodes(data=True) if d.get("source_file") in stale])

    if changed:
        ext = extract([Path(f) for f in changed], cache_root=Path("."))
        G.update(build_from_json(ext))

    communities = cluster(G)
    cohesion = score_all(G, communities)
    labels = {cid: "Community " + str(cid) for cid in communities}
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    questions = suggest_questions(G, communities, labels)
    detection = {
        "total_files": 0, "total_words": 0, "needs_graph": True, "warning": None,
        "files": {"code": [], "document": [], "paper": []},
    }
    tokens = {"input": 0, "output": 0}

    report = generate(G, communities, cohesion, labels, gods, surprises,
                      detection, tokens, "incremental", suggested_questions=questions)
    Path("graphify-out/GRAPH_REPORT.md").write_text(report)
    to_json(G, communities, "graphify-out/graph.json")
    if G.number_of_nodes() <= 5000:
        to_html(G, communities, "graphify-out/graph.html", community_labels=labels or None)

    SYNCED.write_text(head)

    print(f"synced: {len(changed)} changed, {len(deleted)} deleted -> "
          f"{G.number_of_nodes()} nodes, {G.number_of_edges()} edges")
    return 0


if __name__ == "__main__":
    sys.exit(main())
