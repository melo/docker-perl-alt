---
name: version-bump
description: Validate and update the base image versions, the cpm installer, and AWS Lambda RIE for the docker-perl-alt images, and keep the README version references in sync. TRIGGER when the user asks to check/update/bump base image versions, perl/alpine/chainguard versions, the cpm installer, or the Lambda Runtime Interface Emulator, or types /version-bump. Covers where versions are defined, how to find the latest upstream releases, the checksum verification required for cpm and the Lambda RIE, and how to refresh the README.
---

# Version bump

All base image versions and the AWS Lambda RIE URLs+checksums live in a single Perl
script at the repo root: [`build`](../../../build).

- The image matrix is the `@versions` array (`['family', 'tag', 'version', ...]`).
- The cpm installer URL + SHA1 are in `%cpm` (passed as `CPM_URL`/`CPM_SHA1` build-args).
- The Lambda RIE per-arch URL + SHA256 pairs are in `%lambda_runtime_versions`.

There is nothing else to edit — the Dockerfiles take these as `--build-arg`s. All three
Dockerfiles share one cpm setup: the verified fatpacked cpm bootstraps the install of the
official `App::cpm`, which becomes the real `cpm`. Each image also ships an **optional**
lenient App::cpm fork as a layer (see step 3).

## Procedure

> **Principle — always derive "latest" from the live source, never from memory.**
> Your training data has a cutoff and *will* be stale: a version you "know" to be
> current may be one or more releases behind by the time this runs. Compute every
> "latest" from the upstream queries below. When a result matches what you already
> expected, treat that as a reason to double-check with a second, broader query — not
> as confirmation. Watch out especially for narrow `grep` patterns that can *miss* a
> newer release (e.g. matching only bare `5.NN` moving tags and skipping `5.NN.0-*`
> point tags) and thus read as "no new version" when there is one. Prefer **enumerating
> all candidates and selecting the newest** over pattern-matching for the one you
> expect. When in doubt, confirm ground truth by building the image and running
> `perl -e 'print $^V'` inside it.

### 1. Check each base image against upstream

| Image | Where to check latest | Notes |
|---|---|---|
| **perl** (`latest`=`X.Y-slim`, `full`=`X.Y`) | Enumerate the perl5 git tags — see the perl snippet below | Use the latest **stable** release. Perl uses **even** minor numbers for stable (5.40, 5.42, 5.44, …); **odd** minors (5.43, 5.45) are development — do NOT use them. |
| **alpine** (`latest`=`3.NN`) | `curl -s https://alpinelinux.org/releases/` → newest `v3.NN` | Use the newest stable branch. Watch for branches nearing EOL (marked "on request"). |
| **alpine** (`next`/`edge`) | — | Rolling tag `edge`, never changes. |
| **chainguard** (`latest`) | — | Rolling `wolfi-base:latest`, never changes. |
| **cpm** installer | `https://github.com/skaji/cpm` (`main` branch, or latest release tag) | Pinned by SHA1 in `%cpm`. See cpm step below. |
| **AWS Lambda RIE** | `https://api.github.com/repos/aws/aws-lambda-runtime-interface-emulator/releases/latest` → `tag_name` | See checksum step below. |

**perl — find the newest stable release from the authoritative source, then confirm the
base tags exist.** Do NOT infer the current version from memory, and do NOT rely on a
single docker-tag grep (the moving `5.NN` tags can lag a fresh release, and a narrow
pattern can miss `5.NN.0-*` point tags):

```bash
# 1. Enumerate ALL perl releases from the perl5 git tags; keep only STABLE (even minor),
#    newest last. The final line is the target release; its 5.NN is the base tag to use.
git ls-remote --tags --refs https://github.com/Perl/perl5 \
  | grep -oE 'v5\.[0-9]+\.[0-9]+$' | sed 's/^v//' \
  | awk -F. '$2 % 2 == 0' | sort -V | tail -5

# 2. Confirm the moving base tags we depend on actually exist before switching to them
#    (200 = exists, 404 = not published yet). Replace 5.NN with the minor from step 1.
for t in 5.NN 5.NN-slim; do
  echo "perl:$t -> $(curl -s -o /dev/null -w '%{http_code}' \
    https://registry.hub.docker.com/v2/repositories/library/perl/tags/$t)"
done
```

Edit `@versions` in `build` for perl/alpine. Keep the array formatting aligned.

### 2. Update the cpm installer (SHA1)

`%cpm` in `build` pins the fatpacked `skaji/cpm` by `url` (currently the mutable `main`
branch) and `sha1`. Because `main` floats, `./build --check` (step 4) may report cpm
`out-of-date` even when you didn't touch it — that means upstream pushed to `main`. When
that happens, update `%cpm{sha1}` to the reported `actual` value (optionally also pin
`url` to a release tag like `.../skaji/cpm/vX.Y.Z/cpm` for immutability):

```bash
curl -fsSL "https://raw.githubusercontent.com/skaji/cpm/main/cpm" -o /tmp/cpm
echo "sha1: $(shasum /tmp/cpm | awk '{print $1}')"
```

`App::cpm` itself is intentionally **unpinned** — the Dockerfiles install the latest from
CPAN. So is the lenient fork (step 3), which tracks a branch. After bumping cpm, confirm a
build still succeeds.

### 3. The lenient App::cpm fork (NO_MYMETA support)

`App::cpm` refuses distributions built with `NO_MYMETA` (by design — see
[skaji/cpm#311](https://github.com/skaji/cpm/issues/311)). Instead of patching the stock
install, each image ships a small fork,
[`melo/cpm@no-mymeta-fallback`](https://github.com/melo/cpm/tree/no-mymeta-fallback), as an
**optional layer** at `/deps/layers/app-cpm-lenient`. The `app-cpm-lenient` build stage
downloads the branch tarball (`LENIENT_CPM_URL`) and copies its `lib/` into the layer's
`lib/perl5/` plus a `bin/cpm` wrapper; nothing loads it unless `pdi-build-deps --lenient`
(or `PDI_BUILD_DEPS_LENIENT=1`) puts it on `PATH`/`PERL5LIB`.

The fork carries a **single logic change** on top of upstream `App::cpm` (a `MYMETA`
fallback in `App::cpm::Builder::Base`) and **no new dependencies**, so its `lib/` cleanly
shadows the stock install while every dependency still resolves from the global one.

> ⚠️ **If a new upstream `cpm`/`App::cpm` release is available, STOP.** The fork branch
> must be rebased onto the new upstream before the images ship it, or the lenient layer
> will lag behind (and may reintroduce bugs the update fixed). Do **not** just bump the
> base images: strongly recommend rebasing `melo/cpm@no-mymeta-fallback` over the new
> upstream tag first, regenerate the branch, then rebuild and re-verify.

### 4. Update the Lambda RIE (REQUIRED: checksums)

The `%lambda_runtime_versions` hash pins a SHA256 for each arch. If you bump the RIE
version you MUST recompute both checksums — a stale checksum fails the Docker build.

For the new version `vX.YZ`, download both binaries and compute the digests:

```bash
for arch in arm64 x86_64; do
  url="https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/download/vX.YZ/aws-lambda-rie-$arch"
  curl -sL -o "/tmp/rie-$arch" "$url"
  echo "$arch: $(shasum -a 256 /tmp/rie-$arch | awk '{print $1}')"
done
```

Note the arch naming mismatch: the hash keys are `aarch64`/`x86_64`, but the release
asset filenames are `aws-lambda-rie-arm64`/`aws-lambda-rie-x86_64`. Update the URL and
the hex digest for both entries.

### 5. Verify

The build script self-verifies the cpm and RIE checksums against the live downloads:

```bash
./build --check
```

Every line must report `ok:` (wanted == actual). `out-of-date` means the pinned checksum
doesn't match what you'll download — fix it before committing. `download-failed` means the
fetch itself failed (e.g. GitHub rate-limit even after retries) — just re-run `--check`.

Then do at least one real image build to confirm the new base actually works — don't stop
at `--check`. Build the `devel` target of a bumped family (it exercises the base, the cpm
bootstrap, and `pdi-build-deps --layer=devel`) and read the perl version back out of it:

```bash
./build --filter='perl-latest-devel' --debug
docker run --rm --pull=never melopt/perl-alt:perl-latest-devel perl -e 'print "$^V\n"'
```

> **Known limitation — Chainguard `devel`/`reply` do not currently build.**
> wolfi's perl is now 5.44, and `Perl::LanguageServer` (in `layers/devel/cpanfile`) pulls
> in `Coro`, which fails to compile against wolfi's perl 5.44 (a `Time::HiRes` `nvtime`
> mismatch). Coro builds fine on Alpine and the official `perl` image, so only the
> Chainguard `devel`/`reply` targets are affected; Chainguard `build`/`runtime` are fine.
> Because `build` dies on the first target failure and iterates targets in the order
> `devel, build, runtime, reply`, a full `./build` run will stop at `chainguard-latest-devel`
> **before** it reaches the working Chainguard targets — so build those explicitly, e.g.
> `./build --filter='chainguard-latest-(build|runtime)'`. This is a deliberately
> unsupported combination for now, not a regression from your version bump.

### 6. Update the README

[`README.md`](../../../README.md) hard-codes the base image versions in two places; both
must be kept in sync with `@versions` after any base-image bump.

1. **The image matrix table** (near the top, the `| Base Image | Development | ... |`
   table). Update the `alpine:3.NN` and `perl:5.NN[-slim]` base-image labels **and** every
   tag name that embeds the version, e.g. `alpine-3.NN-devel`, `perl-5.NN-slim-build`,
   `perl-5.NN-runtime`. The `latest`/`next`/`edge`/`chainguard` rolling tags don't carry a
   number and stay as-is.
2. **The "What's inside?" perl bullet**, which lists the actual perl **point-release**
   (e.g. `5.42.2`) shipped by each image family. These come from the distros, not from
   `@versions`, so look each one up:

   ```bash
   # Alpine (per branch: vX.NN and edge) - system perl package version
   for br in vX.NN edge; do
     echo -n "$br: "
     curl -s "https://pkgs.alpinelinux.org/packages?name=perl&branch=$br&repo=main&arch=x86_64" \
       | grep -oE '>[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+<' | head -1
   done

   # Official perl:5.NN image - newest 5.NN.x (filter by name, then sort; do NOT
   # `head -1` an unsorted page, and do NOT assume the minor - use the one from step 1)
   curl -s "https://registry.hub.docker.com/v2/repositories/library/perl/tags?page_size=100&name=5.NN" \
     | grep -oE '"name":"5\.NN\.[0-9]+"' | sort -uV | tail -1

   # Chainguard wolfi-base - newest perl in the APKINDEX. NOTE: the archive index keeps
   # many historical versions, so `sort -V | tail -1` is only the newest *present*, which
   # can differ from what `apk add perl` actually resolves in a fresh build. Treat this as
   # a hint and confirm ground truth from the built image (below).
   curl -s "https://packages.wolfi.dev/os/x86_64/APKINDEX.tar.gz" -o /tmp/wolfi.tar.gz \
     && tar xzf /tmp/wolfi.tar.gz -C /tmp \
     && awk '/^P:perl$/{getline; print}' /tmp/APKINDEX | sort -V | tail -1
   ```

   **Ground truth beats index parsing.** After building an image (step 5 / your verify
   build), read the real point-release straight from it — and pass `--pull=never` so you
   don't accidentally inspect a *stale published* image instead of your fresh local build:

   ```bash
   docker run --rm --pull=never melopt/perl-alt:<family>-latest-devel \
     perl -e 'print "$^V\n"'
   ```

   Update the `3.NN: perl X.Y.Z`, `edge: perl X.Y.Z`, official, and Chainguard lines to the
   looked-up point-releases.

After editing, sanity-check that no stale version strings remain:

```bash
grep -nE 'alpine:3\.[0-9]+|perl:5\.[0-9]+|perl 5\.[0-9]+\.[0-9]+' README.md
```

### 7. Commit

Commit `build` and `README.md` together when both changed (plus this skill if you touched
it). Suggested message form:

```
base: bump base images and Lambda RIE to latest

- perl: A.B -> C.D (current stable) ...
- alpine latest: ...
- AWS Lambda RIE: vX -> vY, updating URLs and both SHA256 checksums
- README: refresh version table and perl point-releases
```
