#!/bin/sh
# GitHub adapter for PR Pulse.
#
# Usage: github.sh <token-file-or-empty>
# Prints "<reviews-needed> <ci-failing>" on stdout.
#
# Token resolution order:
#   1. $1 if non-empty and readable
#   2. `gh auth token` keyring
# Exit codes: 0 ok, 2 setup problem, 3 API failure.

set -u

[ $# -eq 1 ] || { echo "usage: github.sh token-file" >&2; exit 2; }
token_file=$1

if [ -n "$token_file" ] && [ -r "$token_file" ]; then
  token=$(tr -d ' \r\n' < "$token_file")
  [ -n "$token" ] || { echo "token file is empty: $token_file" >&2; exit 2; }
elif command -v gh > /dev/null 2>&1 && gh auth token > /dev/null 2>&1; then
  token=$(gh auth token)
else
  echo "no GitHub token: set one up in the widget settings or run \`gh auth login\`" >&2
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
