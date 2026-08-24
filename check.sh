#!/bin/sh
# Attention counter for the PR Pulse bar widget.
#
# Usage (internal): check.sh <token-file>
#
# Token resolution order:
#   1. the given file (one raw token inside)
#   2. `gh auth token` from the GitHub CLI keyring
#
# Prints "<reviews-needed> <ci-failing>" on stdout. The token is fed to curl
# through its config on stdin so it never appears in `ps` output or logs.
# Exit codes: 0 ok, 2 setup problem, 3 API failure.

set -u

[ $# -eq 1 ] || { echo "usage: check.sh token-file" >&2; exit 2; }

token_file=$1
if [ -r "$token_file" ]; then
  token=$(tr -d ' \r\n' < "$token_file")
  [ -n "$token" ] || { echo "token file is empty: $token_file" >&2; exit 2; }
elif command -v gh > /dev/null 2>&1 && gh auth token > /dev/null 2>&1; then
  token=$(gh auth token)
else
  echo "no token: create $token_file or run \`gh auth login\`" >&2
  exit 2
fi

query='query {
  reviews: search(query: "is:pull-request is:open review-requested:@me archived:false", type: ISSUE, first: 1) { issueCount }
  failing: search(query: "is:pull-request is:open author:@me status:failure archived:false", type: ISSUE, first: 1) { issueCount }
}'

payload=$(python3 -c '
import json, sys
print(json.dumps({"query": sys.argv[1]}))
' "$query") || { echo "python3 is required but was not found" >&2; exit 2; }

response=$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sS --max-time 20 \
  --url "https://api.github.com/graphql" \
  --data "$payload" \
  --config - 2>&1)
status=$?

if [ $status -ne 0 ]; then
  echo "curl failed ($status): $response" >&2
  exit 3
fi

printf '%s\n' "$response" | python3 -c '
import json, sys

try:
    body = json.load(sys.stdin)
except ValueError:
    print("non-JSON response from GitHub API", file=sys.stderr)
    sys.exit(3)

errors = body.get("errors")
if errors:
    print("; ".join(str(e.get("message", e)) for e in errors), file=sys.stderr)
    sys.exit(3)

data = body.get("data")
if not data:
    print("missing data in response (bad token or rate limit)", file=sys.stderr)
    sys.exit(3)

try:
    reviews = int(data["reviews"]["issueCount"])
    failing = int(data["failing"]["issueCount"])
except (KeyError, TypeError, ValueError):
    print("unexpected response shape", file=sys.stderr)
    sys.exit(3)

print(reviews, failing)
'
exit $?
