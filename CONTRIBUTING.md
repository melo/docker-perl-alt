# Contributing / maintaining

## Publishing images

The [`build`](build) script is the single source of truth for the image
matrix: the base versions, the tag scheme, the pinned `cpm` and Lambda RIE
checksums, and the OCI labels. `./build --check` verifies the pinned checksums
against their live sources; `./build --emit-matrix` prints the whole plan as
JSON.

Images are built and pushed by GitHub Actions
([`.github/workflows/publish.yml`](.github/workflows/publish.yml)), which
consumes `build --emit-matrix` so it never re-hardcodes any of the above. It
builds every image **natively** on `amd64` and `arm64` runners (no QEMU),
pushes each architecture by digest to both registries, and then assembles the
multi-arch manifest lists. It runs on pushes to `master` that touch the build
inputs, on a weekly schedule (to pick up base-image security patches), and on
manual dispatch (with an optional tag filter).

Two secrets are required for the Docker Hub push:

* `DOCKERHUB_USERNAME` — account (or robot) with push access to
  `melopt/perl-alt`;
* `DOCKERHUB_TOKEN` — a Docker Hub access token with Read & Write (and Delete,
  if you also run the tag-pruning workflow below).

The GHCR push uses the built-in `GITHUB_TOKEN` (the jobs request
`packages: write`) and publishes to the public `ghcr.io/melo/perl-alt` package.

## Pruning stale tags

[`.github/workflows/prune-tags.yml`](.github/workflows/prune-tags.yml) deletes
Docker Hub tags this project no longer produces. The keep-set is computed
dynamically — tags from `build --emit-matrix` plus the version-pinned
`perl-5.N*` / `alpine-3.N*` tags that clients may pin to. It is manual-dispatch
only and **dry-run by default**: the first run lists what it would delete; re-run
with `dry_run=false` to actually delete (needs a Docker Hub token with the
Delete scope).

## Bumping versions

See the `version-bump` skill in
[`.claude/skills/version-bump`](.claude/skills/version-bump) for how the base
image versions, the `cpm` installer, and the Lambda RIE are checked and updated,
and how the README version references are kept in sync.
