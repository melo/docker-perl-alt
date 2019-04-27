# Perl Docker Image System #

[![Docker Pulls](https://img.shields.io/docker/pulls/melopt/perl-alt.svg)]()
[![Docker Build Status](https://img.shields.io/docker/build/melopt/perl-alt.svg)]()

This set of images provide a full and extensible setup to run your Perl
applications with Docker.

There are two versions of the image:

* a `-build` version that can be used to build your applications;
* a `-runtime` version that should be used to run the final
  applications;
* a `-devel` version that can be used for local development, on your laptop.

See below on how to create a Dockerfile for you own project that makes
full use of this setup, while making sure that you'll end up with the
smallest possible final image.


## Included

All images are based on Alpine 3.9 and include:

* [perl-5.26.3](https://metacpan.org/release/perl): this is the system
  perl included with the base Alpine image;
* [cpanm](https://metacpan.org/release/App-cpanminus);
* [carton](https://metacpan.org/release/Carton).

Some common libs and tools are also available:

* openssl: this is not the default for Alpine 3.9, but a lof of software
  fails to buil without it;
* zlib;
* expat;
* libxml2 and libxml-utils;
* jq.

The `-devel` versions include the development versions of this libraries.

## Versions

The system is provided with several different flavours. Each of them is available with two tags for the `-build` and `-runtime` versions.

|   | *Build version* | *Runtime version* | *Notes* |
|---|---|---|---|
| Latest | `latest-build`  | `latest-runtime` | uses the system perl, includes all the libs and helpers. The `latest` tag is aliased to the `latest-build` version |


## Rational

The system was designed to have a big, fully feature, build-time image, and another slim runtime image.

With a Docker multi-stage build, you can use a single Dockerfile to build and generate the final runtime image.

But to make the system more extensible, we also include some helper to install Perl dependencies in a way that allows you to use the final image also for local development, using the `-devel` variant.

TBC


# How to use #

Below you'll find the recommended Dockerfile. The goal is to get a fast build, making use as much as possible of the Docker build cache, and provide the smallest possible image in the end.

...

# Repository #

This image source repository is at https://github.com/melo/docker-perl-alt.


# Author #

Pedro Melo melo@simplicidade.org
