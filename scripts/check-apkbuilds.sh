#!/usr/bin/env sh
# Every APKBUILD that builds with go must set GOTOOLCHAIN=auto. Alpine's go defaults to GOTOOLCHAIN=local and
# Alpine packages an older Go than the one a new release asks for, so without it the package builds today and fails
# at the first bump that needs a newer Go (pdfdebug 0.5.0 did: "go.mod requires go >= 1.27.0 (running go 1.26.8)").
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
bad=0
for f in "$root"/main/*/APKBUILD; do
    # a package builds with go when it lists go in makedepends or runs go build / go install
    if tr '\n' ' ' < "$f" | grep -Eq 'makedepends="[^"]*[[:space:]"]go[[:space:]"]' || grep -Eq '^[[:space:]]*(CGO_ENABLED=[0-9] )?go (build|install)' "$f"; then
        if ! grep -Eq '^export GOTOOLCHAIN=auto$' "$f"; then
            echo "✗ ${f#"$root"/}: builds with go but does not 'export GOTOOLCHAIN=auto'" >&2
            bad=1
        fi
    fi
done
[ "$bad" = 0 ] && echo "✓ every APKBUILD that builds with go sets GOTOOLCHAIN=auto"
exit "$bad"
