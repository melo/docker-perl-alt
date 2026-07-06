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
official `App::cpm`, which is then patched (see step 3) and becomes the real `cpm`.

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
CPAN. The runtime-base `grep` guard (see step 3) fails the build loudly if a new App::cpm
breaks the MYMETA patch, so after bumping cpm confirm a build still succeeds.

### 3. The App::cpm MYMETA patch

All three images apply [`patches/App-cpm-Builder-Base-optional-MYMETA.patch`](../../../patches/App-cpm-Builder-Base-optional-MYMETA.patch)
to the installed `App::cpm::Builder::Base` (makes the `MYMETA.json` copy optional). The
runtime-base RUN locates the module via `@INC`, applies it with `patch -N`, and then
`grep`s for the guard so a failed/fuzzed apply aborts the build. If a build fails at that
`grep`, upstream changed `Builder/Base.pm` — refresh the patch's context lines against the
current source and re-verify.

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
