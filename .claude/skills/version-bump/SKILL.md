---
name: version-bump
description: Validate and update the base image versions and AWS Lambda RIE for the docker-perl-alt images. TRIGGER when the user asks to check/update/bump base image versions, perl/alpine/chainguard versions, or the Lambda Runtime Interface Emulator, or types /version-bump. Covers where versions are defined, how to find the latest upstream releases, and the checksum verification required for the Lambda RIE.
---

# Version bump

All base image versions and the AWS Lambda RIE URLs+checksums live in a single Perl
script at the repo root: [`build`](../../../build).

- The image matrix is the `@versions` array (`['family', 'tag', 'version', ...]`).
- The Lambda RIE per-arch URL + SHA256 pairs are in `%lambda_runtime_versions`.

There is nothing else to edit — the Dockerfiles take these as `--build-arg`s.

## Procedure

### 1. Check each base image against upstream

| Image | Where to check latest | Notes |
|---|---|---|
| **perl** (`latest`=`X.Y-slim`, `full`=`X.Y`) | `curl -s "https://registry.hub.docker.com/v2/repositories/library/perl/tags?page_size=100"` | Use the latest **stable** release. Perl uses **even** minor numbers for stable (5.40, 5.42, …); **odd** minors (5.43) are development — do NOT use them. |
| **alpine** (`latest`=`3.NN`) | https://alpinelinux.org/releases/ | Use the newest stable branch. Watch for branches nearing EOL (marked "on request"). |
| **alpine** (`next`/`edge`) | — | Rolling tag `edge`, never changes. |
| **chainguard** (`latest`) | — | Rolling `wolfi-base:latest`, never changes. |
| **AWS Lambda RIE** | `https://api.github.com/repos/aws/aws-lambda-runtime-interface-emulator/releases/latest` → `tag_name` | See checksum step below. |

Edit `@versions` in `build` for perl/alpine. Keep the array formatting aligned.

### 2. Update the Lambda RIE (REQUIRED: checksums)

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

### 3. Verify

The build script self-verifies the RIE checksums against the live downloads:

```bash
./build --check
```

Both arches must report `ok:` (wanted == actual). If either says `out-of-date`, the
checksum in `build` doesn't match what you'll download — fix it before committing.

### 4. Commit

Commit only `build` (unless you also touched this skill). Suggested message form:

```
base: bump base images and Lambda RIE to latest

- perl: A.B -> C.D (current stable) ...
- alpine latest: ...
- AWS Lambda RIE: vX -> vY, updating URLs and both SHA256 checksums
```
