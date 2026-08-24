# PR Pulse

Pull requests awaiting your review and CI failures across **GitHub, GitLab
and Bitbucket**, live in the Omarchy bar.

```
 octocat 3        <- 3 items need your review
 octocat 1 (red)  <- red when a build is failing
```

- **Reviews**: PRs/MRs where you are the requested reviewer (Bitbucket:
  assigned to you)
- **CI failures**: your own open PRs whose latest pipeline/build is failing
- Red icon = failing checks or total failure to reach any forge; dim = all clear
- Badge sums every enabled forge; hover for the per-forge breakdown
  (`GH 2R+1F · GL 0R+3F`)

Left click opens your forge, right click refreshes now. Polls every 5 minutes.

## Install

Requires [Omarchy](https://omarchy.org/) Quattro (4.x).

```sh
omarchy plugin add https://github.com/adarshpundir/omarchy-prpulse.git --enable
```

## Authentication

PR Pulse never puts credentials in process arguments - each adapter hands its
token to curl over stdin config, so nothing shows up in `ps`, logs, or core
dumps. Secrets travel over TLS to the forge API and nowhere else.

| Forge | Zero setup | File fallback |
|---|---|---|
| GitHub | [`gh auth token`](https://cli.github.com/) keyring | `tokenFile` setting or `secretsDir/github.token` |
| GitLab | `glab auth login` keyring | `secretsDir/gitlab.token` (PAT with `read_api`) |
| Bitbucket Cloud | none exists - file required | `secretsDir/bitbucket.token` containing one line `email:app-password` |

Default `secretsDir` is `~/.config/omarchy/prpulse`. Create it with:

```sh
install -d -m700 ~/.config/omarchy/prpulse
```

Scope guidance: a classic GitHub token with `repo` scope sees private PRs;
fine-grained read-only tokens count only repos you grant; GitLab PATs need
`read_api`; Bitbucket app passwords need Pull requests: Read + Repositories:
Read.

## Configuration

Everything lives inline on the widget entry in `~/.config/omarchy/shell.json`
or via the bar settings UI:

```sh
omarchy bar set prpulse.bar forges "github,gitlab"   # poll two forges
omarchy bar set prpulse.bar gitlabHost https://gitlab.mycorp.com
omarchy bar set prpulse.bar showCi false             # reviews only
omarchy bar set prpulse.bar hideWhenZero false       # keep the icon visible
```

| Setting | Default | Meaning |
|---|---|---|
| `forges` | `github` | Comma-separated: `github`, `gitlab`, `bitbucket` |
| `gitlabHost` | `https://gitlab.com` | Point at self-hosted GitLab instances |
| `gitlabUser` | *(empty)* | Auto-resolved from the API when empty |
| `secretsDir` | `~/.config/omarchy/prpulse` | Where per-forge token files live |
| `tokenFile` | `~/.config/omarchy/github.token` | GitHub token file checked before the gh keyring |
| `pollIntervalSec` | `300` | Refresh cadence (min 60) |
| `hideWhenZero` | `true` | Hide icon when nothing needs attention |
| `webUrl` | `https://github.com/pulls` | Left-click target |
| `showReviews` / `showCi` | `true` | Toggle either counter |

## How it works

Each forge is an isolated adapter under `forge/` speaking that platform's
native API:

- GitHub: one GraphQL request with two searches (`review-requested:@me`,
  `author:@me status:failure`)
- GitLab: REST v4 `/merge_requests` with `reviewer_username=` +
  `head_pipeline.status` filtering on your open MRs
- Bitbucket Cloud: REST 2.0 `pullrequests` lists + per-commit build statuses

`check.sh` runs the adapters you enable, tolerates individual failures
(a dead forge dims into the tooltip instead of breaking the widget), and
prints aggregate JSON for the QML widget.

## Troubleshooting

Hover the widget: working forges show as `GH 2R+1F`; broken ones show their
error line. Run any adapter by hand:

```sh
~/.config/omarchy/plugins/prpulse.bar/forge/github.sh ""
~/.config/omarchy/plugins/prpulse.bar/forge/gitlab.sh https://gitlab.com "" ~/.config/omarchy/prpulse
```

Exit codes: `0` ok, `2` setup problem, `3` API failure.

## License

[MIT](LICENSE)
