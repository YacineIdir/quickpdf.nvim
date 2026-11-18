---
status: accepted
---

# Branching, merging and releases

Work branches start from `develop`; only hotfixes start from `main` and go
straight back to it. Pull requests into `develop` and hotfix pull requests
are squash-merged with a Conventional Commits title, so each pull request is
one commit and one changelog line. `develop` is merged into `main` with a
merge commit, so release-please still sees every `feat` and `fix`.

release-please runs on `main`: it keeps a release pull request open, and
merging it tags `vX.Y.Z`, writes `CHANGELOG.md`, creates the GitHub Release
and, in the same workflow, publishes the rock to LuaRocks. Publishing lives
in that workflow because a tag pushed with `GITHUB_TOKEN` does not trigger
other workflows.

Accepted on 2026-11-17, not implemented yet.
