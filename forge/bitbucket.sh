#!/bin/sh
# Bitbucket Cloud adapter for PR Pulse.
#
# Usage: bitbucket.sh <secrets-dir>
# Prints "<prs-on-my-plate> <my-prs-failing-builds>" on stdout.
#
# Bitbucket Cloud has no standard authenticated CLI, so this adapter needs a
# credential file: $secrets-dir/bitbucket.token containing ONE line:
#   email:app-password
# (Create an app password at https://bitbucket.org/account/settings/app-passwords/
#  with Pull requests: Read and Repositories: Read, or use an API token.)
# Exit codes: 0 ok, 2 setup problem, 3 API failure.

set -u

[ $# -eq 1 ] || { echo "usage: bitbucket.sh secrets-dir" >&2; exit 2; }

secrets_dir=$1
cred_file="$secrets_dir/bitbucket.token"
[ -r "$cred_file" ] || {
  echo "no Bitbucket credential: put email:app-password in $cred_file" >&2
  exit 2
}
cred=$(tr -d ' \r\n' < "$cred_file")
case "$cred" in
  *:*) : ;;
  *) echo "$cred_file must contain email:app-password on one line" >&2; exit 2 ;;
esac
case "$cred" in
  *'"'*) echo "$cred_file must not contain double quotes" >&2; exit 2 ;;
esac

PULSE_BB_CRED="$cred" python3 << 'PYEOF'
import json, os, subprocess, sys

CRED = os.environ["PULSE_BB_CRED"]
API = "https://api.bitbucket.org/2.0"


def bb_get(path):
    """GET an API path with the credential handed to curl over stdin config."""
    raw = subprocess.run(
        ["curl", "-sS", "--max-time", "20",
         "--config", "-", "--url", f"{API}{path}"],
        input=f'user = "{CRED}"\n',
        text=True, capture_output=True,
    ).stdout
    try:
        return json.loads(raw)
    except ValueError:
        print(f"non-JSON response for {path}", file=sys.stderr)
        sys.exit(3)


def values(data, what):
    if isinstance(data, dict) and data.get("error"):
        msg = data["error"].get("message", str(data["error"]))
        print(f"{what}: {msg}", file=sys.stderr)
        sys.exit(3)
    if not isinstance(data, dict):
        print(f"unexpected response shape for {what}", file=sys.stderr)
        sys.exit(3)
    return data.get("values", [])


# PRs where I am an assignee/reviewer. Bitbucket has no reviewer-only list
# endpoint; assigned_to_me is the closest "needs my attention" set.
reviews = values(bb_get("/pullrequests/assigned_to_me?pagelen=50"), "assigned PRs")

mine = values(
    bb_get("/pullrequests/created_by_me?pagelen=50&state=OPEN"),
    "own PRs",
)

failing = 0
checked = 0
for pr in mine:
    if checked >= 20:
        break
    try:
        repo = pr["destination"]["repository"]["full_name"]
        sha = pr["source"]["commit"]["hash"]
    except (KeyError, TypeError):
        continue
    checked += 1
    statuses = bb_get(f"/repositories/{repo}/commit/{sha}/statuses")
    states = [s.get("state") for s in statuses.get("values", [])]
    if "FAILED" in states:
        failing += 1

print(len(reviews), failing)
PYEOF
