#!/bin/sh
# Orchestrator for the PR Pulse bar widget.
#
# Usage: check.sh <github-token-file> <forges-csv> <secrets-dir> \
#                 <gitlab-host> <gitlab-user>
#
# Runs each enabled forge adapter and prints one JSON object on stdout:
#   {"total":{"reviews":R,"failing":F},
#    "forges":{"github":{"reviews":2,"failing":1},
#              "gitlab":{"error":"no token"}}}
# Errors go to stderr as they happen; per-forge errors also land in the JSON.
# Exit codes: 0 at least one forge succeeded, 3 every enabled forge failed.

set -u

[ $# -eq 5 ] || { echo "usage: check.sh github-token-file forges secrets-dir gitlab-host gitlab-user" >&2; exit 2; }

gh_token_file=$1
forges=$2
secrets_dir=$3
gitlab_host=$4
gitlab_user=$5

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

wanted=$(printf '%s' "$forges" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
[ -n "$wanted" ] || { echo "no forges configured" >&2; exit 2; }

echo "$wanted" | while IFS= read -r forge; do
  case "$forge" in
    github)
      timeout 45 sh "$here/forge/github.sh" "$gh_token_file" \
        > "$work/github.out" 2> "$work/github.err" ;;
    gitlab)
      timeout 45 sh "$here/forge/gitlab.sh" "$gitlab_host" "$gitlab_user" "$secrets_dir" \
        > "$work/gitlab.out" 2> "$work/gitlab.err" ;;
    bitbucket)
      timeout 45 sh "$here/forge/bitbucket.sh" "$secrets_dir" \
        > "$work/bitbucket.out" 2> "$work/bitbucket.err" ;;
    *)
      echo "unknown forge: $forge (supported: github, gitlab, bitbucket)" >&2 ;;
  esac
done

PULSE_WORK="$work" PULSE_FORGES="$wanted" python3 << 'PYEOF'
import json, os, sys

work = os.environ["PULSE_WORK"]
forges = [f for f in os.environ["PULSE_FORGES"].splitlines() if f]

result = {"total": {"reviews": 0, "failing": 0}, "forges": {}}
ok = False
for forge in forges:
    out_path = os.path.join(work, f"{forge}.out")
    err_path = os.path.join(work, f"{forge}.err")
    entry = {}
    try:
        with open(out_path) as f:
            parts = f.read().split()
            entry["reviews"] = int(parts[0])
            entry["failing"] = int(parts[1])
            ok = True
    except (OSError, IndexError, ValueError):
        try:
            with open(err_path) as f:
                message = f.read().strip()
            entry["error"] = message.split("\n")[0] if message else "failed"
        except OSError:
            entry["error"] = "failed"
        print(entry.get("error", ""), file=sys.stderr)
    result["forges"][forge] = entry

for entry in result["forges"].values():
    if "reviews" in entry:
        result["total"]["reviews"] += entry["reviews"]
        result["total"]["failing"] += entry["failing"]

print(json.dumps(result, separators=(",", ":")))
sys.exit(0 if ok else 3)
PYEOF
