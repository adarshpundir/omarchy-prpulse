# PR Pulse

Pull requests awaiting your review and CI failures on your own open PRs,
live in the Omarchy bar.

```
 octocat 3        <- 3 PRs need your review
 octocat 1 (red)  <- red when a build is failing
```

- **Reviews**: open PRs with `review-requested:@me`
- **CI failures**: your open PRs whose latest status is failing
- Red icon = failing checks or an error (hover for details)
- Dim icon = all clear, badge hidden by default when nothing needs you

Left click opens GitHub, right click refreshes now. Polls the GitHub GraphQL
API every 5 minutes.

## Install

Requires [Omarchy](https://omarchy.org/) Quattro (4.x).

```sh
omarchy plugin add https://github.com/adarshpundir/omarchy-prpulse.git --enable
```

## Authentication

PR Pulse resolves a token in this order:

1. The file set on the widget's `tokenFile` setting
   (default `~/.config/omarchy/github.token`, one raw token inside,
   `chmod 600` recommended) - use this for fine-grained tokens or machines
   without `gh`.
2. [`gh auth token`](https://cli.github.com/) - if the GitHub CLI is installed
   and logged in, its keyring token is used and no file is needed.

Either way the token is handed to curl over stdin config, so it never shows up
in process arguments (`ps`), logs, or core dumps - it travels to
`api.github.com` over TLS and nowhere else.

Scope guidance: classic token with `repo` scope sees public + private PRs;
a fine-grained read-only token counts only repos you grant it; the default
`gh` OAuth token works out of the box.

## Configuration

Everything lives inline on the widget entry in `~/.config/omarchy/shell.json`
or via the bar settings UI:

```sh
omarchy bar set prpulse.bar pollIntervalSec 120   # poll faster
omarchy bar set prpulse.bar showCi false          # reviews only
omarchy bar set prpulse.bar hideWhenZero false    # keep the icon visible
omarchy bar set prpulse.bar webUrl https://github.com/notifications
```

| Setting | Default | Meaning |
|---|---|---|
| `tokenFile` | `~/.config/omarchy/github.token` | Token file checked before the gh keyring |
| `pollIntervalSec` | `300` | Refresh cadence (min 60) |
| `hideWhenZero` | `true` | Hide icon when nothing needs attention |
| `webUrl` | `https://github.com/pulls` | Left-click target |
| `showReviews` | `true` | Count PRs awaiting my review |
| `showCi` | `true` | Count failing CI on my open PRs |

## How it works

A single GraphQL request runs two searches per poll:

```graphql
reviews: search(query: "is:pull-request is:open review-requested:@me archived:false") { issueCount }
failing: search(query: "is:pull-request is:open author:@me status:failure archived:false") { issueCount }
```

`check.sh` prints `<reviews> <failing>`; the QML widget renders state from
those two numbers.

## Troubleshooting

Hover the widget for the last error message, or run the checker by hand:

```sh
~/.config/omarchy/plugins/prpulse.bar/check.sh ~/.config/omarchy/github.token
```

Exit codes: `0` ok, `2` setup problem, `3` API failure.
GraphQL errors (expired token, rate limit) surface in the tooltip verbatim.

## License

[MIT](LICENSE)
