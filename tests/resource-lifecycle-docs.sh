#!/usr/bin/env bash
# Static guidance contracts; these do not prove agent/host runtime compliance.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
entries = ["skills/executing-plans/SKILL.md",
           "skills/subagent-driven-development/implementer-prompt.md",
           "skills/finishing-a-development-branch/SKILL.md", "docs/README.codex.md"]
for entry in entries:
    content = Path(entry).read_text()
    for required in ["resource-lifecycle", "GOCACHE", "database", "active",
                     "unknown", "failed", "reusable", "job-resources.py"]:
        assert required.lower() in content.lower(), (entry, required)
content = Path("docs/resource-lifecycle.md").read_text()
for required in ["go env GOCACHE", "go env -w", "cold cache", "anonymous volumes",
                 "--outcome failure", "attribution, not authentication", "review-candidate",
                 "never deletion permission", "no lifecycle hook", "10,000", "1 MiB"]:
    assert required in content, required
print("PASS: resource lifecycle guidance contracts (static only)")
PY
