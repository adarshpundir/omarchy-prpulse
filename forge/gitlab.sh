#!/bin/sh
# GitLab adapter for PR Pulse.
#
# Usage: gitlab.sh <host> <username-or-empty> <secrets-dir>
# Prints "<mrs-awaiting-my-review> <my-mrs-failing-ci>" on stdout.
#
# Token resolution order:
#   1. `glab` CLI keyring (glab auth status -t)
#   2. $secrets-dir/gitlab.token (a personal access token with read_api)
# Exit codes: 0 ok, 2 setup problem, 3 API failure.

set -u

[ $# -eq 3 ] || { echo "usage: gitlab.sh host username secrets-dir" >&2; exit 2; }

base=${1%/}
wanted_user=$2
secrets_dir=$3
api="$base/api/v4"

token=""
if command -v glab > /dev/null 2>&1; then
  hostname=$(printf '%s\n' "$base" | sed -E 's#^https?://##')
  token=$(glab auth status -t --hostname "$hostname" 2>/dev/null | grep -oE 'glpat-[A-Za-z0-9_-]+' | head -n 1)
fi
if [ -z "$token" ] && [ -r "$secrets_dir/gitlab.token" ]; then
  token=$(tr -d ' \r\n' < "$secrets_dir/gitlab.token")
fi
[ -n "$token" ] || {
  echo "no GitLab token: run \`glab auth login\` or put a PAT in $secrets_dir/gitlab.token" >&2
  exit 2
}

gl_get() {
  printf 'header = "PRIVATE-TOKEN: %s"\n' "$token" | curl -sS --max-time 20 \
    --url "$1" --config - 2>&1
}

user="$wanted_user"
if [ -z "$user" ]; then
  me=$(gl_get "$api/user")
  user=$(printf '%s\n' "$me" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    print(json.loads(raw)["username"])
except Exception:
    print(f"could not resolve GitLab username, got: {raw[:200]}", file=sys.stderr)
    sys.exit(1)
') || exit 3
fi

reviews_json=$(gl_get "$api/merge_requests?scope=all&state=opened&reviewer_username=$user&per_page=100")
mine_json=$(gl_get "$api/merge_requests?scope=created_by_me&state=opened&per_page=100")

python3 - "$reviews_json" "$mine_json" << 'PYEOF'
import json, sys

def parse(raw, what):
    try:
        data = json.loads(raw)
    except ValueError:
        print(f"non-JSON response for {what}", file=sys.stderr)
        sys.exit(3)
    if isinstance(data, dict):
        msg = data.get("message") or data.get("error")
        if msg:
            print(f"{what}: {msg}", file=sys.stderr)
            sys.exit(3)
        print(f"unexpected response shape for {what}", file=sys.stderr)
        sys.exit(3)
    return data

reviews = parse(sys.argv[1], "review MRs")
mine = parse(sys.argv[2], "own MRs")

failing = sum(
    1 for mr in mine
    if ((mr.get("head_pipeline") or {}).get("status")) == "failed"
)

print(len(reviews), failing)
PYEOF
