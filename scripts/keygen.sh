#!/bin/sh
# Run this yourself, locally - never paste the .rsa (private) key into chat
# with an AI assistant, and never commit it anywhere. It only ever needs to
# exist in two places: your own backup, and the ABUILD_PRIVATE_KEY GitHub
# secret. The .pub is not committed either - CI derives it from the secret
# on every run and publishes it to the live site (see README's "Hosting").
#
# Usage: sh scripts/keygen.sh   (run from an Alpine box, or via:
#   docker run --rm -it -v "$PWD:/work" -w /work alpine:3.24 sh scripts/keygen.sh)
set -eu

apk add --no-cache abuild >/dev/null

mkdir -p ~/.abuild
PACKAGER="UniDoc <ahall@unidoc.io>" abuild-keygen -a -n

# abuild-keygen names the key after $PACKAGER + a timestamp; abuild.conf
# now points PACKAGER_PRIVKEY at it. Find it and give it our fixed name -
# purely cosmetic, doesn't need to match anything in CI (the secret holds
# the key material, not a filename).
generated="$(grep PACKAGER_PRIVKEY ~/.abuild/abuild.conf | cut -d= -f2 | tr -d '"')"
mv "$generated" ~/.abuild/unidoc-aports.rsa
rm -f "$generated.pub"
sed -i 's#^PACKAGER_PRIVKEY=.*#PACKAGER_PRIVKEY="/root/.abuild/unidoc-aports.rsa"#' ~/.abuild/abuild.conf

echo
echo "Done. ~/.abuild/unidoc-aports.rsa is the PRIVATE key. Do exactly two"
echo "things with it, in order:"
echo "  1. Back it up somewhere durable (1Password) - there is no recovery"
echo "     if it's lost, only re-issuing a new key and re-trusting it on"
echo "     every client that ever ran \`apk add\` against this repo."
echo "  2. Paste its contents into a GitHub Actions secret named"
echo "     ABUILD_PRIVATE_KEY (repo Settings > Secrets and variables >"
echo "     Actions > New repository secret)."
echo
echo "Nothing else needs this file, and nothing from this keygen belongs"
echo "in a git commit - not the .rsa, not a .pub either."
