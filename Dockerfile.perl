## The Perl Official version
ARG BASE=perl:5.42-slim

## Fetch and verify the cpm installer before we trust it (pin comes from ./build)
FROM ${BASE} AS cpm
ARG CPM_URL=https://raw.githubusercontent.com/skaji/cpm/main/cpm
ARG CPM_SHA1=c6a592f4a77e0dcdde64fb29b23a3c12ef5a27dc

RUN apt-get update                                                       \
    && apt-get install -y --no-install-recommends curl ca-certificates   \
    && curl -fsSL "${CPM_URL}" -o /cpm                                    \
    && echo "${CPM_SHA1}  /cpm" | sha1sum -c -                           \
    && chmod 0755 /cpm

## The main event...
FROM ${BASE} AS runtime-base

## The verified fatpacked cpm, used only to bootstrap the official App::cpm
COPY --from=cpm /cpm /usr/local/bin/cpm-bootstrap

## Bootstrap installs the official App::cpm (whose own /usr/local/bin/cpm becomes THE
## cpm), then we drop the fatpacked bootstrap.
RUN apt update                                                                       \
    && apt install -y --no-install-recommends                                        \
    curl make zlib1g libssl3 libexpat1 libxml2 jq                                    \
    build-essential                                                                  \
    && apt upgrade -y                                                                \
    && cpm-bootstrap install -g --no-test                                            \
    App::cpanminus Carton Carton::Snapshot App::cpm Path::Tiny Digest::SHA           \
    autodie Module::CPANfile CPAN::Meta::Prereqs AWS::Lambda AWS::XRay               \
    && rm -rf ~/.perl-cpm ~/.cpanm                                                   \
    && rm -f /usr/local/bin/cpm-bootstrap                                            \
    && mkdir -p /app /deps /stack                                                    \
    ## Purge the C toolchain from the runtime image. `apt autoremove build-essential`
    ## alone leaves orphaned toolchain packages behind - notably linux-libc-dev and
    ## libc6-dev, which by themselves account for ~40 HIGH + 1 CRITICAL CVE (kernel
    ## headers, non-exploitable in a container but still flagged). Purge them explicitly,
    ## then sweep the now-orphaned gcc/cpp/binutils/dpkg-dev. build-base re-adds the
    ## toolchain for the -build/-devel targets, so runtime loses nothing it needs.
    && apt-get purge -y build-essential libc6-dev linux-libc-dev                      \
    && apt-get autoremove -y --purge -o APT::AutoRemove::RecommendsImportant=false    \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/*


## The setup...
ENV PATH=/app/bin:/deps/bin:/deps/local/bin:/stack/bin:/stack/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /app
ENTRYPOINT [ "/usr/bin/pdi-entrypoint" ]


## The Build version
FROM runtime-base AS build-base

RUN apt update                                                                  \
    && apt install -y --no-install-recommends                                   \
    build-essential zlib1g-dev libssl-dev libexpat1-dev libxml2-dev       \
    && apt upgrade -y                                                           \
    && apt purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/*


## Optional lenient App::cpm layer
##
## App::cpm (skaji/cpm) refuses distributions that disable MYMETA (NO_MYMETA), by design
## - https://github.com/skaji/cpm/issues/311. To still install such dists we ship the
## melo/cpm@no-mymeta-fallback fork in an *optional* layer: its lib/ shadows the stock
## App::cpm only when `pdi-build-deps --lenient` (or PDI_BUILD_DEPS_LENIENT=1) puts bin/ on
## PATH and lib/perl5/ on PERL5LIB. The .optional marker keeps anything that auto-activates
## layers from ever loading it by default.
FROM runtime-base AS app-cpm-lenient
ARG LENIENT_CPM_URL=https://github.com/melo/cpm/archive/refs/heads/no-mymeta-fallback.tar.gz
RUN mkdir -p /deps/layers/app-cpm-lenient/bin /deps/layers/app-cpm-lenient/lib/perl5    \
    && curl -fsSL "${LENIENT_CPM_URL}" | tar -xz -C /tmp                                \
    && cp -R /tmp/cpm-*/lib/. /deps/layers/app-cpm-lenient/lib/perl5/                   \
    && sed '1s|^#!.*|#!/usr/bin/env perl|' /tmp/cpm-*/script/cpm                        \
       > /deps/layers/app-cpm-lenient/bin/cpm                                           \
    && chmod 0755 /deps/layers/app-cpm-lenient/bin/cpm                                  \
    && touch /deps/layers/app-cpm-lenient/.optional                                     \
    && rm -rf /tmp/cpm-*


## AWS Lambda Runtime Interface Emulator (local testing only)
##
## The RIE is a Go binary that carries a number of Go-stdlib CVEs, and on real AWS
## Lambda it is never used (AWS provides its own runtime interface client). We build it
## in its own stage and bake it only into the -devel and -runtime-lambda images; the
## plain -runtime and -build images stay free of its CVEs. AWS's own guidance is likewise
## to keep the RIE out of the deployed image.
FROM runtime-base AS aws-lambda-rie
ARG AWS_LAMBDA_RIE_URL_aarch64="unknown"
ARG AWS_LAMBDA_RIE_SIG_aarch64="unknown"
ARG AWS_LAMBDA_RIE_URL_x86_64="unknown"
ARG AWS_LAMBDA_RIE_SIG_x86_64="unknown"
RUN mkdir -p /usr/local/bin && cd /usr/local/bin                   \
    && arch=`uname -m`                                             \
    && url="AWS_LAMBDA_RIE_URL_$arch"                              \
    && sig="AWS_LAMBDA_RIE_SIG_$arch"                              \
    && sh -c "curl -Lo ./aws-lambda-rie \${$url}"                  \
    && chmod +x ./aws-lambda-rie                                   \
    && sh -c "echo 'SHA256 (aws-lambda-rie) =' \${$sig}" > ./.sig  \
    && shasum -c .sig                                              \
    && rm .sig


## Our files
FROM scratch AS project

COPY bin/lambda-bootstrap /var/runtime/bootstrap
COPY layers/ cpanfile* /deps/layers/
COPY --from=app-cpm-lenient /deps/layers/app-cpm-lenient /deps/layers/app-cpm-lenient
COPY scripts/ /usr/bin/


## Final Versions: Development
FROM build-base AS devel
COPY --from=project / /
## devel images bundle the RIE for local Lambda testing (carries Go-stdlib CVEs)
COPY --from=aws-lambda-rie /usr/local/bin/aws-lambda-rie /usr/local/bin/aws-lambda-rie

RUN pdi-build-deps --layer=devel  \
    && echo 'eval $( pdi-perl-env )' > /etc/profile.d/perl_env.sh


## Final Versions: Build
FROM build-base AS build
COPY --from=project / /


## Final Versions: Runtime
FROM runtime-base AS runtime
COPY --from=project / /


## Final Versions: Runtime + Lambda RIE
##
## Deployable Lambda image: the plain runtime plus the AWS RIE for local emulation.
## NOTE: this variant carries the RIE's Go-stdlib CVEs - prefer -runtime for anything
## that does not need the local Lambda emulator.
FROM runtime AS runtime-lambda
COPY --from=aws-lambda-rie /usr/local/bin/aws-lambda-rie /usr/local/bin/aws-lambda-rie


## Final Versions: Repl
FROM devel AS reply
RUN /usr/local/bin/cpm install --no-test Reply && rm -rf /root/.perl-cpm

CMD ["reply"]
