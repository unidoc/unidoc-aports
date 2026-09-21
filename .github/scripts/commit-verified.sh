#!/bin/sh
# commit-verified.sh BRANCH FILE MESSAGE - moves BRANCH to a single new
# commit on top of the current default branch's tip, containing one
# file update, made through GitHub's own Contents API rather than a
# local `git commit` - so it comes back Verified.
#
# Why this matters, precisely (unidoc-alip's PR #5 review caught the
# original version of this comment overstating it): this repo's
# required_signatures ruleset only inspects what actually lands on
# master. Squash-merging a bump PR - confirmed against PR #4, the one
# real bump PR this workflow has produced - sidesteps it entirely:
# GitHub creates and signs the squash commit itself regardless of
# whether the PR's own head commit was signed, so an unsigned head
# commit merged there with one ordinary approval, no override. The
# "Create a merge commit" method does not get that same pass - it lands
# the head commit itself, unsigned, and required_signatures blocks
# THAT - so this is real protection against a footgun tied to merge
# method, not a fix for something that has actually happened yet.
# Commits made through the Contents API come back genuinely Verified
# regardless of which merge method gets used, closing the gap outright
# rather than depending on everyone remembering to squash.
#
# Needs: GH_TOKEN (or GITHUB_TOKEN) and GITHUB_REPOSITORY in the
# environment - both already set automatically inside any GitHub
# Actions run. Only handles a single-file change - exactly what every
# caller in this repo currently needs (one APKBUILD, or one workflow
# file); a multi-file version would need the lower-level Git Data API
# (trees/commits) instead of the Contents API's own one-file-per-call
# shape.
#
# GITHUB_TOKEN cannot write under .github/workflows/ at all - there is
# no "workflows" key in a workflow's own `permissions:` block to grant
# it (confirmed against GitHub's own workflow-syntax reference; a
# GitHub App's "workflows" permission is a different, unrelated thing).
# check-alpine, the one caller that commits a workflow file, cannot
# succeed until that's addressed with a PAT or an App token - out of
# scope here. What this script does guarantee even then: a failure
# writing the file never moves BRANCH at all (see the scratch-branch
# design below), so that caller fails without leaving a stray branch
# behind.
set -eu

BRANCH="${1:?usage: commit-verified.sh BRANCH FILE MESSAGE}"
FILE="${2:?usage: commit-verified.sh BRANCH FILE MESSAGE}"
MESSAGE="${3:?usage: commit-verified.sh BRANCH FILE MESSAGE}"

base_sha="$(git rev-parse HEAD)"

# A real, separate branch for the scratch commit, not a plan to reuse
# BRANCH directly for it - the whole point. The old version force-reset
# BRANCH to base_sha, THEN wrote the file: between those two calls
# BRANCH carried no change at all, and if the write then failed (rate
# limit, transient 5xx, or check-alpine's permanent permission gap
# above), the run aborted with BRANCH left pointing at master and, if a
# PR was already open against it, that PR now showing an empty diff -
# or, on the very first run for a new BRANCH, a stray branch nobody
# asked for. Building the commit here first means BRANCH only ever
# moves once, to the fully-committed result, or not at all.
tmp_branch="$BRANCH-tmp.$$"

cleanup() {
    gh api --method DELETE "repos/$GITHUB_REPOSITORY/git/refs/heads/$tmp_branch" \
        >/dev/null 2>&1 || true
}
trap cleanup EXIT

# create_or_move_branch NAME SHA - creates refs/heads/NAME at SHA, or
# force-moves it there if NAME already exists. The POST's stderr used
# to be discarded outright (2>&1 >/dev/null), so any failure other than
# "the branch already exists" - a bad SHA, a permissions problem -
# surfaced only as the fallback PATCH's own unrelated error one line
# later. Capturing it and checking the actual message keeps the
# already-exists fall-through intact while failing fast, with the real
# cause, on everything else.
create_or_move_branch() {
    name="$1"
    sha="$2"
    if err="$(gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" \
            -f ref="refs/heads/$name" -f sha="$sha" 2>&1 >/dev/null)"; then
        return 0
    fi
    if ! printf '%s\n' "$err" | grep -q 'Reference already exists'; then
        printf 'commit-verified: creating refs/heads/%s: %s\n' "$name" "$err" >&2
        return 1
    fi
    gh api --method PATCH "repos/$GITHUB_REPOSITORY/git/refs/heads/$name" \
        -f sha="$sha" -F force=true >/dev/null
}

create_or_move_branch "$tmp_branch" "$base_sha"

# The blob sha at base_sha directly - no need to read it back off
# tmp_branch now that tmp_branch is guaranteed to already be at
# base_sha.
file_sha="$(gh api "repos/$GITHUB_REPOSITORY/contents/$FILE?ref=$base_sha" --jq .sha)"

# base64 -w0 is GNU-only and errors out on macOS's own base64 - this
# repo's CI is Ubuntu-only so it was never actually wrong there, but
# CLAUDE.md's own "verifying a change locally" section points
# contributors at macOS, where this would fail if anyone ever ran it by
# hand. `tr -d '\n'` is portable and produces byte-identical output on
# both.
new_sha="$(gh api --method PUT "repos/$GITHUB_REPOSITORY/contents/$FILE" \
    -f message="$MESSAGE" \
    -f content="$(base64 "$FILE" | tr -d '\n')" \
    -f sha="$file_sha" \
    -f branch="$tmp_branch" \
    --jq .commit.sha)"

create_or_move_branch "$BRANCH" "$new_sha"
