#!/usr/bin/env bash
# Fails unless the pull request title given as $1 follows Conventional
# Commits: <type>[(<scope>)][!]: <description>. Squash merges turn the title
# into the commit message release-please reads
# (docs/adr/0005-branching-merging-and-releases.md).

set -euo pipefail

title="${1:-}"
types="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
pattern="^(${types})(\([a-z0-9._/-]+\))?!?: [^[:space:]]"

if [[ "$title" =~ $pattern ]]; then
    exit 0
fi

{
    printf 'The PR title must look like "<type>(<scope>): <description>".\n'
    printf 'The scope is optional; "!" before the colon marks a breaking change.\n'
    printf 'Types: %s\n' "${types//|/, }"
    printf 'Title: %s\n' "$title"
} >&2
exit 1
