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
    curl wget make zlib1g libssl3 libexpat1 gnupg libxml2 libxml2-utils jq           \
    build-essential                                                                  \
    && apt upgrade -y                                                                \
    && cpm-bootstrap install -g --no-test                                            \
    App::cpanminus Carton Carton::Snapshot App::cpm Path::Tiny Digest::SHA           \
    autodie Module::CPANfile CPAN::Meta::Prereqs AWS::Lambda AWS::XRay               \
    && rm -rf ~/.perl-cpm ~/.cpanm                                                   \
    && rm -f /usr/local/bin/cpm-bootstrap                                            \
    && mkdir -p /app /deps /stack                                                    \
    && apt purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false      \
    && apt autoremove -y build-essential                                             \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/*


## AWS Lambda Emulator support
ARG AWS_LAMBDA_RIE_URL_aarch64="unknown"
ARG AWS_LAMBDA_RIE_SIG_aarch64="unknown"
ARG AWS_LAMBDA_RIE_URL_x86_64="unknown"
ARG AWS_LAMBDA_RIE_SIG_x86_64="unknown"

RUN mkdir -p /usr/local/bin                                        \
    && cd /usr/local/bin                                           \
    && arch=`uname -m`                                             \
    && url="AWS_LAMBDA_RIE_URL_$arch"                              \
    && sig="AWS_LAMBDA_RIE_SIG_$arch"                              \
    && echo ">>>> arch $arch"                                      \
    && sh -c "echo '>>>> url ' \${$url}"                           \
    && sh -c "echo '>>>> sig ' \${$sig}"                           \
    && sh -c "curl -Lo ./aws-lambda-rie \${$url}"                  \
    && chmod +x ./aws-lambda-rie                                   \
    && sh -c "echo 'SHA256 (aws-lambda-rie) =' \${$sig}" > ./.sig  \
    && shasum -c .sig                                              \
    && rm .sig


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


## Our files
FROM scratch AS project

COPY bin/lambda-bootstrap /var/runtime/bootstrap
COPY layers/ cpanfile* /deps/layers/
COPY --from=app-cpm-lenient /deps/layers/app-cpm-lenient /deps/layers/app-cpm-lenient
COPY scripts/ /usr/bin/


## Final Versions: Development
FROM build-base AS devel
COPY --from=project / /

RUN pdi-build-deps --layer=devel  \
    && echo 'eval $( pdi-perl-env )' > /etc/profile.d/perl_env.sh


## Final Versions: Build
FROM build-base AS build
COPY --from=project / /


## Final Versions: Runtime
FROM runtime-base AS runtime
COPY --from=project / /


## Final Versions: Repl
FROM devel AS reply
RUN /usr/local/bin/cpm install --no-test Reply && rm -rf /root/.perl-cpm

CMD ["reply"]
