#!/bin/sh
# commit-verified.sh BRANCH FILE MESSAGE - creates/resets BRANCH to the
# current default branch's tip and pushes a single-file update to it as
# a real commit made through GitHub's own Contents API, not a local
# `git commit`.
#
# Why: a plain `git commit` + `git push`, even when the push is
# authenticated with a valid GITHUB_TOKEN, produces an ordinary
# unsigned commit - GitHub does not retroactively sign a commit just
# because the PUSH was authenticated. required_signatures branch
# protection then blocks it from ever being merged without an admin
# override, every single time, for every automated bump PR. Commits
# made through GitHub's own Contents/Git Data API, by contrast, are
# automatically signed with GitHub's own key and shown "Verified",
# authored as github-actions[bot] - no GPG key pair to generate, no
# separate GitHub App to register and install, no extra secrets to
# rotate: this reuses the GITHUB_TOKEN every workflow already has, with
# the contents: write permission these jobs already request.
#
# Force-resets BRANCH to the CURRENT tip rather than accumulating
# commits on top of a stale previous run's bump - matches this
# project's own previous `git push --force` semantics exactly (a fresh,
# single-commit branch every run, not a growing history of abandoned
# bump attempts).
#
# Needs: GH_TOKEN (or GITHUB_TOKEN) and GITHUB_REPOSITORY in the
# environment - both already set automatically inside any GitHub
# Actions run. Only handles a single-file change - exactly what every
# caller in this repo currently needs (one APKBUILD, or one workflow
# file); a multi-file version would need the lower-level Git Data API
# (trees/commits) instead of the Contents API's own one-file-per-call
# shape.
set -eu

BRANCH="${1:?usage: commit-verified.sh BRANCH FILE MESSAGE}"
FILE="${2:?usage: commit-verified.sh BRANCH FILE MESSAGE}"
MESSAGE="${3:?usage: commit-verified.sh BRANCH FILE MESSAGE}"

base_sha="$(git rev-parse HEAD)"

if ! gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" \
    -f ref="refs/heads/$BRANCH" -f sha="$base_sha" >/dev/null 2>&1; then
    gh api --method PATCH "repos/$GITHUB_REPOSITORY/git/refs/heads/$BRANCH" \
        -f sha="$base_sha" -F force=true >/dev/null
fi

file_sha="$(gh api "repos/$GITHUB_REPOSITORY/contents/$FILE?ref=$BRANCH" --jq .sha)"

gh api --method PUT "repos/$GITHUB_REPOSITORY/contents/$FILE" \
    -f message="$MESSAGE" \
    -f content="$(base64 -w0 "$FILE")" \
    -f sha="$file_sha" \
    -f branch="$BRANCH" >/dev/null
