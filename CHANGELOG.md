# Changelog

## 0.2.0 - 2026-08-24

Multi-forge support.

- **GitLab adapter**: MRs where you are a reviewer + failing pipelines on your
  open MRs. Zero-setup when the `glab` CLI is logged in; otherwise a PAT in
  `secretsDir/gitlab.token`. Self-hosted GitLab works via `gitlabHost`.
- **Bitbucket Cloud adapter**: PRs assigned to you + failed build statuses on
  your open PRs. Needs `secretsDir/bitbucket.token` (`email:app-password`)
  since Bitbucket has no standard authenticated CLI.
- Orchestrator emits per-forge JSON; the badge sums all forges, the tooltip
  breaks counts down (GH 2R+1F · GL 0R+3F) and surfaces per-forge errors.
- Widget entry point renamed to `Widget.qml`; new settings: `forges`,
  `secretsDir`, `gitlabHost`, `gitlabUser`.

## 0.1.0 - 2026-08-24

Initial release.

- Bar widget showing open PRs awaiting your review (GitHub)
- CI-failure count across your own open PRs (GitHub)
- Token resolution: explicit token file first, then `gh auth token` keyring
- Secret handling: credentials never appear in process arguments or logs
- Settings: poll interval, hide-when-zero, webmail URL, per-counter toggles
