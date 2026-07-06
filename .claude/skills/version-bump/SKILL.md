---
name: version-bump
description: Validate and update the base image versions, the cpm installer, and AWS Lambda RIE for the docker-perl-alt images. TRIGGER when the user asks to check/update/bump base image versions, perl/alpine/chainguard versions, the cpm installer, or the Lambda Runtime Interface Emulator, or types /version-bump. Covers where versions are defined, how to find the latest upstream releases, and the checksum verification required for cpm and the Lambda RIE.
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

### 1. Check each base image against upstream

| Image | Where to check latest | Notes |
|---|---|---|
| **perl** (`latest`=`X.Y-slim`, `full`=`X.Y`) | `curl -s "https://registry.hub.docker.com/v2/repositories/library/perl/tags?page_size=100"` | Use the latest **stable** release. Perl uses **even** minor numbers for stable (5.40, 5.42, …); **odd** minors (5.43) are development — do NOT use them. |
| **alpine** (`latest`=`3.NN`) | https://alpinelinux.org/releases/ | Use the newest stable branch. Watch for branches nearing EOL (marked "on request"). |
| **alpine** (`next`/`edge`) | — | Rolling tag `edge`, never changes. |
| **chainguard** (`latest`) | — | Rolling `wolfi-base:latest`, never changes. |
| **cpm** installer | `https://github.com/skaji/cpm` (`main` branch, or latest release tag) | Pinned by SHA1 in `%cpm`. See cpm step below. |
| **AWS Lambda RIE** | `https://api.github.com/repos/aws/aws-lambda-runtime-interface-emulator/releases/latest` → `tag_name` | See checksum step below. |

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

### 6. Commit

Commit only `build` (unless you also touched this skill). Suggested message form:

```
base: bump base images and Lambda RIE to latest

- perl: A.B -> C.D (current stable) ...
- alpine latest: ...
- AWS Lambda RIE: vX -> vY, updating URLs and both SHA256 checksums
```
