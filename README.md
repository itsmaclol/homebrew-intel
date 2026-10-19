# Homebrew installers for Intel Macs (unofficial)

Homebrew 7 (September 2026) made both install paths on [brew.sh](https://brew.sh) Apple Silicon only, even though `brew` itself still runs on Intel Macs (macOS 11 or newer) until September 2027. This repository rebuilds those two installers for Intel (x86_64) on the same infrastructure Homebrew uses: the same scripts, the same GitHub Actions build steps, the same Homebrew/brew release tags, the same `formulae.brew.sh` API and the same `ghcr.io` bottles.

It is **not affiliated with Homebrew** and the package is **not signed or notarized**. Report problems here, not to Homebrew.

## Test it on an Intel Mac

Install the Xcode Command Line Tools first. On Intel, most packages now build from source, so you need them anyway:

```sh
xcode-select --install
```

**Option A: the .pkg installer**

```sh
curl -fLO https://github.com/itsmaclol/homebrew-intel/releases/latest/download/Homebrew-intel.pkg
# optional: check it was built by this repository's workflow
gh attestation verify Homebrew-intel.pkg --repo itsmaclol/homebrew-intel
sudo installer -pkg Homebrew-intel.pkg -target /
```

Installing from Terminal avoids Gatekeeper's prompt for unsigned packages. To use the installer window instead, double-click the file, then allow it under **System Settings → Privacy & Security → Open Anyway**.

**Option B: the one-line script**

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/itsmaclol/homebrew-intel/HEAD/install.sh)"
```

**Check it worked**

```sh
brew config          # HOMEBREW_PREFIX: /usr/local, Homebrew 7.x
brew install hello && hello
brew doctor          # always warns that Intel is Tier 3; that is expected
```

On macOS 26.2 or newer you can also add Homebrew's new app with `brew install --cask homebrew-app`. BrewUI is a universal binary that knows `/usr/local/bin/brew`.

**Uninstall.** Homebrew's own uninstall script still handles `/usr/local`:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
sudo pkgutil --forget io.github.itsmaclol.homebrew-intel   # only if you used the .pkg
```

## How brew.sh works

The site offers two installers. Both put a Git checkout of [Homebrew/brew](https://github.com/Homebrew/brew) on the stable branch, at its latest tag, into a *prefix*. Everything after that is `brew` itself.

1. **`install.sh`** ([Homebrew/install](https://github.com/Homebrew/install)) is the `curl | bash` one-liner. It:
   - picks the prefix;
   - checks the macOS version, sudo access and Git;
   - creates and takes ownership of `bin etc include lib sbin share var opt Cellar Caskroom Frameworks …`;
   - installs the Command Line Tools through `softwareupdate`;
   - runs `git init`, fetches Homebrew/brew and runs `git checkout -B stable <latest tag>`;
   - links `bin/brew` when the repository is separate from the prefix;
   - runs `brew update --force`.
2. **`Homebrew.pkg`** is built by Homebrew/brew's [`release.yml`](https://github.com/Homebrew/brew/blob/main/.github/workflows/release.yml) on a GitHub Actions macOS runner. That workflow:
   - checks out Homebrew/brew with full history and switches to `stable`;
   - runs `brew update` to seed the API cache into `cache_api/`;
   - runs `pkgbuild`, using the checkout as the payload, `package/scripts/{preinstall,postinstall}` plus `macos_user.sh`, and an install location;
   - runs `productbuild` with `package/Distribution.xml`, `WELCOME`, `LICENSE` and `CONCLUSION`;
   - signs, notarizes and attests the package, tests it on fresh runners, and uploads it to the release.

   When it runs, `preinstall` picks the user and `postinstall` does the rest: creates the prefix directories, sets ownership, resets Git to the tag as that user, and moves `cache_api/` into `~/Library/Caches/Homebrew/api`.
3. **At runtime**, `bin/brew` (bash) bootstraps the following:
   - **Portable Ruby** for the host architecture. The x86_64 build is still published (`portable-ruby` 4.0.7 `big_sur` bottle).
   - **The signed package index** `formulae.brew.sh/api/internal/packages.<tag>.jws.json`. On Intel, `<tag>` is the bare macOS name (`sonoma`, `sequoia`, `tahoe` …); on Apple Silicon it is `arm64_<name>`.
   - **Bottles** from `ghcr.io/v2/homebrew/core`, built for a fixed prefix: `/usr/local` on Intel, `/opt/homebrew` on Apple Silicon.

### What Homebrew 7 changed for Intel

| Piece | Upstream now | Source |
|---|---|---|
| `install.sh` | aborts: "only supported on Apple Silicon processors!" | Homebrew/install `e078684c4a` (#1140) |
| `Homebrew.pkg` | `hostArchitectures="arm64"`, macOS 15+; Intel relocation code deleted | Homebrew/brew #23779, #23928 |
| Bottles | Intel is Tier 3; no new Intel bottles, existing ones stay | Homebrew/brew #23677, #23679 |
| `brew` | still runs on Intel macOS 11+ in `/usr/local`, until 2027-09-01 | 7.0.0 release notes |
| API | `packages.{big_sur…golden_gate}.jws.json` still published daily | `formulae.brew.sh` |

Why simply allowing the official `.pkg` onto an Intel Mac is not enough:
- **Wrong install location.** It installs to `/opt/homebrew`, and brew refuses to install anything there on Intel: *"Cannot install on Intel processor in ARM default prefix (/opt/homebrew)!"* (`Library/Homebrew/extend/os/mac/install.rb`).
- **Wrong bottles.** Intel bottles are only relocatable to prefixes of 10 characters or fewer, and `/opt/homebrew` is 13.
- **Wrong API cache.** Its seeded cache is `packages.arm64_tahoe.jws.json`, the Apple Silicon index.

## What this repository changes

Commit `fed8cf4` imports the upstream files untouched, so the next commit's diff against it is exactly the Intel port.

| File | Change from upstream |
|---|---|
| `install.sh` | x86_64 defaults to prefix `/usr/local` with the repository in `/usr/local/Homebrew` (Apple Silicon behaviour is unchanged). Refuses macOS older than 11. Prints the Tier 3 notice. When the user is not an admin, the recursive `chmod` stays inside Homebrew-owned paths. |
| `package/Distribution.xml` | `hostArchitectures="x86_64"`, macOS 11+, its own package identifier, and a hard stop on Apple Silicon (including under Rosetta). |
| `package/scripts/postinstall` | 7.0.9's script with these changes: the payload lands in `/usr/local/Homebrew`; it links `/usr/local/bin/brew`; it fixes the shared `/usr/local` directories the way `install.sh` does, without recursing into other software's files and without following symlinks as root; it writes no `/etc/paths.d` entry. |
| `package/resources/*.rtf` | Intel paths and next steps, the Tier 3 note, and an "unofficial" note. |
| `.github/workflows/intel-pkg.yml` | Upstream's build steps on `macos-15-intel`, unsigned, with `actions/attest` provenance, plus Intel tests. |

`preinstall`, `macos_user.sh` and the whole payload come straight from the Homebrew/brew tag being packaged.

## What CI checks on every build (`macos-15-intel`)

- `install.sh` refuses `/opt/homebrew` and installs to `/usr/local`.
- The `.pkg` upgrades an existing `install.sh` installation.
- A fresh `.pkg` install has the right layout: `/usr/local/bin/brew → ../Homebrew/bin/brew`, a clean `stable` checkout, no `cache_api` left behind, an Intel API cache, and ownership set correctly.
- `brew config` runs, and `brew install hello` works.
- Reinstalling the `.pkg` keeps working.
- A non-admin install works, and no group- or world-writable paths are left after either a fresh install or a reinstall.

To package a newer Homebrew release, open **Actions → Intel installer → Run workflow**. Leave the tag empty to use the latest release.

## Limits

- **Intel is Tier 3 upstream.** On 2026-10-19, 5,253 of 8,662 homebrew/core formulae (61%) still had a bottle Intel can use: mostly `sonoma`, plus `:all` bottles. Frequently updated ones such as `git`, `wget`, `node`, `python@3.14` and `ffmpeg` have none, so they and their dependencies build from source. That can take a long time, and some may not build at all.
- **Homebrew stops running on Intel on 2027-09-01.** Rebuilding the installer can't change that.
- **CI covers macOS 15 only**, the one Intel runner GitHub still offers. macOS 11–14 and 26 are allowed but untested.
- **Unsigned.** The package has build provenance but no Apple Developer ID signature or notarization.

Licensed under BSD-2-Clause like Homebrew (see `LICENSE.txt`).
