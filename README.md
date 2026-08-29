# unidoc-aports

A small Alpine Linux package repository for UniDoc's own software - built,
signed, and published straight from GitHub, no infrastructure of our own to
run.

## Install

```sh
# trust our signing key
wget -P /etc/apk/keys/ https://pkg.unidoc.io/keys/unidoc-aports.rsa.pub

# add the repo - "main" is the channel (see "Layout" below), same idea as
# Alpine's own main/community/testing split, just with one channel so far
echo "https://pkg.unidoc.io/main" >> /etc/apk/repositories
apk update

apk add unidoc-incus unidoc-ndppd isms unisupply unipdf-cli
```

## What's in here, and why it looks like this

Every package here follows the same rule: **if it ships as a real `.apk`,
it uses the same filesystem paths a normal Alpine package would** -
`/etc`, `/usr/bin` or `/usr/sbin`, `/etc/init.d`, `/var/lib`, `/var/log`.
Nothing lives under `/opt/unidoc`. That's a deliberate reversal from how
`unidoc-ndppd`'s standalone GitHub-release binary was set up (its compiled-in
default config path is still `/opt/unidoc/etc/unidoc-ndppd.conf` from that
era) - a raw binary drop and a real apk-repo package are different things,
and the whole point of a package repo is that `apk add unidoc-incus` feels
exactly like `apk add incus`. `/opt/unidoc` still makes sense for tools that
never become apk packages (e.g. cross-platform binaries pushed straight to
GitHub Releases for non-Alpine hosts).

### `unidoc-incus`, not `incus`

We don't shadow the real `incus` package name. Two repos both shipping a
package literally called `incus` means installs flip-flop on whichever repo
currently has the higher version - unpredictable for a hypervisor package,
and nobody could tell whose incus they're actually running. Instead:

- `unidoc-incus` `provides="incus=$pkgver-r$pkgrel"`, so anything that just
  `depends on incus` resolves against it.
- **You cannot have both `incus` and `unidoc-incus` installed at once** -
  not because of a special conflict declaration, but because both packages
  own the exact same files (`/usr/sbin/incusd`, `/etc/init.d/incusd`, ...).
  `apk` refuses that transaction outright with a clear error. This is
  automatic and doesn't need any extra APKBUILD machinery.
- One package instead of upstream's ~9 (client/agent/user/vm/conversion/
  utils/bash-completion/openrc x2) - `incus-agent` stays separate since it's
  the one piece that gets copied alone into VM guests. Everything else has
  no reason to be split for our use.
- Tracks Incus's **latest stable** release, not the LTS branch Alpine's own
  `community/incus` deliberately pins to (currently 7.0.x LTS vs. 7.4.0
  stable - confirmed by diffing Alpine's aports APKBUILD against Incus's
  actual tag list).
- KVM/VM support is bundled in by default (no separate `-vm` subpackage),
  but qemu/ovmf/aavmf are still `depends=`, never vendored - that stays
  Alpine's own package, patched on Alpine's own schedule.

### Release cadence

Semi-automatic, not hands-off. `check-updates.yml` runs daily, checks each
package's upstream `/releases/latest` against its own `pkgver`, and - if
there's a newer one - opens a PR with `pkgver` and the tarball checksum
already bumped. `build-and-publish.yml`'s `build` job also runs on that PR
(never the `publish`/signing job - that only ever runs on a push to
`master`), so by the time there's something to look at, it's already
proven to build. Nothing merges itself; approving is a deliberate choice,
and a broken bump can just be closed. `unidoc-incus` gets an extra warning
in its PR body every time, since a version bump there has already broken
things this repo doesn't re-verify automatically (the static-build patch,
the `_tools` list, the `check()` skip list) - green CI on that package
specifically is not the same as "safe to merge without reading the log."

## Hosting

Built by GitHub Actions on every push to `master` that touches `main/**`,
published to **GitHub Pages** (`actions/upload-pages-artifact` +
`actions/deploy-pages` - first-party actions, no third-party dependency).
Signing key lives in the `ABUILD_PRIVATE_KEY` repository secret; it's never
in this repo. Two things worth knowing:

- **No version history.** Each publish replaces the whole Pages site - only
  the latest build of each package is ever served. This isn't a size
  workaround so much as the actual design: nobody's pinning old package
  versions from this repo. If that ever needs to change, the fallback is
  one GitHub Release per arch instead of Pages (unlimited storage, less
  clean URLs) - not needed yet.
- **Signing only runs on pushes to `master`**, never on a fork's pull
  request - a malicious PR against a public repo can't get anywhere near
  the private key.

Generating the keypair: see `scripts/keygen.sh` - run it yourself, locally,
never through an AI assistant's sandbox. Only the **private** half
(`unidoc-aports.rsa`) goes into the `ABUILD_PRIVATE_KEY` GitHub secret - the
public half is never committed to this repo; CI derives it fresh from the
secret on every run (`openssl rsa -pubout`) and publishes it straight to
`https://pkg.unidoc.io/keys/unidoc-aports.rsa.pub`, so there's no separate
file that can ever drift out of sync with whatever key is actually signing.
Back the private key up somewhere durable (e.g. 1Password) before it goes
into the GitHub secret; there's no recovery if it's lost, only re-issuing a
new key and re-trusting it on every client.

### Custom domain (pkg.unidoc.io)

Two manual, one-time steps this repo can't do for you:

1. **DNS**: a `CNAME` record at your DNS provider - `pkg` -> `unidoc.github.io`.
2. **GitHub**: Settings -> Pages -> **Build and deployment -> Source = GitHub
   Actions**, and separately, **Custom domain = `pkg.unidoc.io`** (this also
   offers an "Enforce HTTPS" checkbox - turn it on once the cert issues,
   which takes a few minutes after DNS propagates).

The workflow itself writes `CNAME` into every published deploy (Actions-based
Pages publishes don't persist a custom domain across deploys on their own the
way the old branch-based flow did) - but the Settings values above still have
to be set once by hand; nothing in `main/**` triggers them.

## Packages

| Package | Source | Language | Status |
|---|---|---|---|
| `unidoc-incus` | [lxc/incus](https://github.com/lxc/incus) | Go + cgo (cowsql/raft) | scaffolded, **not yet build-tested** - incus's build is the most complex thing here, expect at least one CI debugging round |
| `unidoc-ndppd` | [unidoc/unidoc-ndppd](https://github.com/unidoc/unidoc-ndppd) | C | scaffolded |
| `isms` | [unidoc/isms](https://github.com/unidoc/isms) | Go + Vue (embedded) | scaffolded |
| `unisupply` | [unidoc/unisupply](https://github.com/unidoc/unisupply) | Go | scaffolded |
| `unipdf-cli` | [unidoc/unipdf-cli](https://github.com/unidoc/unipdf-cli) | Go | scaffolded - commercial (license code required at runtime), `license=custom` reflects that |

**Not yet scaffolded:**

- `pdfdebug` ([unidoc/pdfdebug](https://github.com/unidoc/pdfdebug)) - a
  Wails desktop app with a separate `server` build tag (HTTP-only, no GUI
  deps) that's the one relevant here. More novel packaging shape than
  anything above (embedded frontend + wails build tooling); wanted a closer
  look before writing something that only looks right.
- `isms-python` ([unidoc/isms-python](https://github.com/unidoc/isms-python)) -
  a Python client library, not a system service. This is a `py3-isms`-style
  APKBUILD (pyproject/gpep517 build class), a genuinely different shape from
  every Go/C package above - worth its own pass rather than bolting it onto
  this one.
- `incus-console` ([unidoc/incus-console](https://github.com/unidoc/incus-console)) -
  wanted for real, but **has no tagged release yet** (empty tag list as of
  this writing), so there's nothing reproducible to point an APKBUILD's
  `source=` at. It's also a Fyne desktop GUI app (X11/GL/audio deps, plus
  `go.mod replace` directives onto sibling repos that need vendoring to
  build standalone) - a meaningfully different packaging shape from
  everything else here. Revisit once it has a first tag.

**Deliberately excluded:**

- `isms-templates` - not versioned/tagged yet either; same reasoning as
  `incus-console` above. `isms.confd`'s `ISMS_TEMPLATE_PATH` already has a
  slot ready for this once it is.
- `unihtml` - doesn't fit here.
- `unipdf`, `unioffice`, `unitype`, `unichart`, and the various vendored
  font/image forks - these are Go **libraries** (`go get` dependencies),
  not standalone binaries. Nothing to package as an apk.

## Layout

Mirrors Alpine's own `aports` repo (and postmarketOS's `pmaports`, the
closest real-world precedent for "a third party running their own
Alpine-compatible package channel"): the repo *is* the package tree, no
extra `aports/` nesting inside it. `main/` is our one channel so far - the
same role Alpine's own `main` plays, one level down from the repo root
exactly like theirs. A `testing/` channel could be added later the same
way, each with its own `REPODEST` in CI.

```
main/<pkgname>/APKBUILD     - one directory per package, standard Alpine layout
.github/workflows/          - CI: build (per-arch, in a throwaway Alpine
                               container) -> publish (GitHub Pages, under /main)
scripts/keygen.sh           - abuild signing key setup (run locally, not in CI)
```

There's no `keys/` directory in this repo - the public key isn't committed
here at all. CI derives it from the `ABUILD_PRIVATE_KEY` secret on every
run and publishes it to the live site at `https://pkg.unidoc.io/keys/unidoc-aports.rsa.pub`
(see "Hosting" above for why).
